import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_calendar/device_calendar.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

void main(){
  tz_data.initializeTimeZones();
  runApp(const MaterialApp(home: RosterProApp(), debugShowCheckedModeBanner: false));
}

class RosterProApp extends StatefulWidget{
  const RosterProApp({super.key});
  @override State<RosterProApp> createState()=> _RosterProAppState();
}

class _RosterProAppState extends State<RosterProApp>{
  final DeviceCalendarPlugin _calendarPlugin = DeviceCalendarPlugin();
  TextEditingController nameCtrl = TextEditingController();
  TextEditingController inputCtrl = TextEditingController();

  Map<String,String> rosterData = {}; // yyyy-MM-dd -> shift e.g. "0700-1600"
  Map<String,String> notesData = {}; // yyyy-MM-dd -> note
  Map<String,String> eventIdMap = {}; // yyyy-MM-dd -> google eventId

  String customName = "My Roster";
  bool googleSyncEnabled = false;
  String? googleCalendarId;
  bool hasCalendarPermission = false;
  DateTime focusedMonth = DateTime.now();

  @override
  void initState(){
    super.initState();
    nameCtrl.text = customName;
    loadAll().then((_) async {
      await Future.delayed(const Duration(milliseconds: 800));
      await _handleCalendarPermission(auto: true);
    });
  }

  // ============ 保存讀取 ============
  Future<void> loadAll() async {
    final p = await SharedPreferences.getInstance();
    customName = p.getString('customName')?? "My Roster";
    nameCtrl.text = customName;
    rosterData = Map<String,String>.from(jsonDecode(p.getString('rosterData')?? '{}'));
    notesData = Map<String,String>.from(jsonDecode(p.getString('notesData')?? '{}'));
    eventIdMap = Map<String,String>.from(jsonDecode(p.getString('eventIdMap')?? '{}'));
    googleSyncEnabled = p.getBool('googleSyncEnabled')?? false;
    googleCalendarId = p.getString('googleCalId');
    if(mounted) setState((){});
  }
  Future<void> saveAll() async {
    final p = await SharedPreferences.getInstance();
    p.setString('customName', customName);
    p.setString('rosterData', jsonEncode(rosterData));
    p.setString('notesData', jsonEncode(notesData));
    p.setString('eventIdMap', jsonEncode(eventIdMap));
    p.setBool('googleSyncEnabled', googleSyncEnabled);
    if(googleCalendarId!=null) p.setString('googleCalId', googleCalendarId!);
  }

  // ============ 1. 權限 + 強制揀 Google 日曆 ============
  Future<bool> _handleCalendarPermission({bool auto=false}) async {
    var s1 = await Permission.calendarFullAccess.status;
    if(!s1.isGranted){
      var r1 = await Permission.calendarFullAccess.request();
      if(!r1.isGranted){
        var r2 = await Permission.calendar.request();
        if(!r2.isGranted){
          if(!auto && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請允許日曆權限')));
          return false;
        }
      }
    }
    hasCalendarPermission = true;
    await _pickGoogleCalendar();
    if(mounted) setState((){});
    return true;
  }

  Future<void> _pickGoogleCalendar() async {
    var res = await _calendarPlugin.retrieveCalendars();
    if(res.data==null) return;
    // 三星日曆過濾：只留 Google
    List<Calendar> googleCals = res.data!.where((c){
      if(c.isReadOnly == true) return false;
      final acc = (c.accountName??'').toLowerCase();
      final type = (c.accountType??'').toLowerCase();
      final name = (c.name??'').toLowerCase();
      return type.contains('google') || acc.contains('gmail') || acc.contains('google') || name.contains('google');
    }).toList();

    List<Calendar> candidates = googleCals.isNotEmpty? googleCals : res.data!.where((c)=> c.isReadOnly==false).toList();
    if(candidates.isEmpty) return;

    if(candidates.length==1){
      googleCalendarId = candidates.first.id;
    }else{
      if(!mounted) return;
      Calendar? picked = await showDialog<Calendar>(
        context: context,
        builder: (_)=> SimpleDialog(
          title: const Text('選擇你的 Google 日曆 (非三星日曆)'),
          children: candidates.map((c)=> SimpleDialogOption(
            onPressed: ()=> Navigator.pop(_, c),
            child: Text('${c.name} - ${c.accountName}'),
          )).toList(),
        ),
      );
      if(picked!=null) googleCalendarId = picked.id;
    }
    await saveAll();
  }

  // ============ 2. 去重覆蓋同步 ============
  Future<void> syncToGoogle() async {
    if(!hasCalendarPermission){
      bool ok = await _handleCalendarPermission();
      if(!ok) return;
    }
    if(googleCalendarId==null) await _pickGoogleCalendar();
    if(googleCalendarId==null){
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('找不到 Google 日曆')));
      return;
    }

    // 先刪除範圍內所有舊的 RosterPro 事件，避免重複
    DateTime rangeStart = DateTime(focusedMonth.year, focusedMonth.month-1, 1);
    DateTime rangeEnd = DateTime(focusedMonth.year, focusedMonth.month+2, 0);
    var oldEvents = await _calendarPlugin.retrieveEvents(googleCalendarId!, RetrieveEventsParams(startDate: rangeStart, endDate: rangeEnd));
    if(oldEvents.isSuccess && oldEvents.data!=null){
      for(var e in oldEvents.data!){
        if((e.description??'').contains('[RosterPro]')){
          await _calendarPlugin.deleteEvent(googleCalendarId!, e.eventId);
        }
      }
    }
    eventIdMap.removeWhere((k,v){
      DateTime? d = DateTime.tryParse(k);
      if(d==null) return false;
      return d.isAfter(rangeStart.subtract(const Duration(days:1))) && d.isBefore(rangeEnd.add(const Duration(days:1)));
    });

    // 再寫入最新
    for(var entry in rosterData.entries){
      if(entry.value.trim().isEmpty) continue;
      DateTime? d = DateTime.tryParse(entry.key);
      if(d==null) continue;
      if(d.isBefore(rangeStart) || d.isAfter(rangeEnd)) continue;

      String note = notesData[entry.key]?? '';
      var start = tz.TZDateTime(tz.getLocation('Asia/Hong_Kong'), d.year, d.month, d.day, 9, 0);
      var end = tz.TZDateTime(tz.getLocation('Asia/Hong_Kong'), d.year, d.month, d.day, 18, 0);

      Event ev = Event(googleCalendarId!,
        title: '[更] ${entry.value}',
        description: '[RosterPro] 自動同步\n班次: ${entry.value}\n記事: $note\n日期: ${entry.key}\n---\n請勿手動刪除此標記，否則去重會失效',
        start: start, end: end, allDay: false,
      );
      var cr = await _calendarPlugin.createOrUpdateEvent(ev);
      if(cr!=null && cr.isSuccess && cr.data!=null){
        eventIdMap[entry.key] = cr.data!;
      }
    }
    await saveAll();
    if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已同步到 Google 日曆，去重完成')));
  }

  // 刪除同步時，Google 同步刪
  Future<void> deleteSingleDay(String dateKey) async {
    if(eventIdMap.containsKey(dateKey) && googleCalendarId!=null){
      await _calendarPlugin.deleteEvent(googleCalendarId!, eventIdMap[dateKey]);
      eventIdMap.remove(dateKey);
    }
    rosterData.remove(dateKey);
    await saveAll();
    setState((){});
  }

  // ============ 3. 按日期範圍清除排更 ============
  Future<void> clearByRange() async {
    DateTimeRange? range = await showDateRangePicker(
      context: context, firstDate: DateTime(2023), lastDate: DateTime(2030),
      helpText: '選擇要清除的範圍',
    );
    if(range==null) return;
    for(DateTime d = range.start;!d.isAfter(range.end); d = d.add(const Duration(days:1))){
      String key = "${d.year.toString().padLeft(4,'0')}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}";
      if(eventIdMap.containsKey(key) && googleCalendarId!=null){
        await _calendarPlugin.deleteEvent(googleCalendarId!, eventIdMap[key]);
        eventIdMap.remove(key);
      }
      rosterData.remove(key);
      // 注意：notesData 不刪，保留記事
    }
    await saveAll();
    setState((){});
    if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已清除 ${range.start.month}/${range.start.day} - ${range.end.month}/${range.end.day} 班次，記事已保留，Google日曆已同步刪除')));
  }

  // ============ 4. 日子編輯卡 - 只清班次 ============
  void showEditDialog(String dateKey){
    TextEditingController shiftCtrl = TextEditingController(text: rosterData[dateKey]?? '');
    TextEditingController noteCtrl = TextEditingController(text: notesData[dateKey]?? '');
    showDialog(context: context, builder: (_)=> AlertDialog(
      title: Text(dateKey),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: shiftCtrl, decoration: const InputDecoration(labelText: '班次 e.g. 0700-1600 / OFF')),
        const SizedBox(height:12),
        TextField(controller: noteCtrl, decoration: const InputDecoration(labelText: '記事'), maxLines: 3),
      ]),
      actions: [
        TextButton(
          onPressed: (){
            // 只清班次，保留記事
            rosterData.remove(dateKey);
            shiftCtrl.clear();
            saveAll();
            setState((){});
            Navigator.pop(context);
            if(googleCalendarId!=null && eventIdMap.containsKey(dateKey)){
              _calendarPlugin.deleteEvent(googleCalendarId!, eventIdMap[dateKey]);
              eventIdMap.remove(dateKey);
            }
          },
          child: const Text('清除班次 (保留記事)', style: TextStyle(color: Colors.orange)),
        ),
        TextButton(onPressed: ()=> Navigator.pop(context), child: const Text('取消')),
        ElevatedButton(onPressed: (){
          if(shiftCtrl.text.trim().isEmpty){
            rosterData.remove(dateKey);
          }else{
            rosterData[dateKey] = shiftCtrl.text.trim();
          }
          notesData[dateKey] = noteCtrl.text.trim();
          saveAll();
          setState((){});
          Navigator.pop(context);
          if(googleSyncEnabled) syncToGoogle();
        }, child: const Text('保存')),
      ],
    ));
  }

  @override
  Widget build(BuildContext context){
    List<DateTime> days = [];
    DateTime first = DateTime(focusedMonth.year, focusedMonth.month, 1);
    DateTime last = DateTime(focusedMonth.year, focusedMonth.month+1, 0);
    for(int i=0;i<last.day;i++) days.add(DateTime(focusedMonth.year, focusedMonth.month, i+1));

    return Scaffold(
      appBar: AppBar(title: TextField(controller: nameCtrl, onChanged: (v){customName=v; saveAll();}, decoration: const InputDecoration(border: InputBorder.none, hintText: 'Roster Name'))),
      drawer: Drawer(child: ListView(children: [
        const DrawerHeader(child: Text('設定', style: TextStyle(fontSize: 24))),
        SwitchListTile(
          title: const Text('啟用 Google日曆同步'),
          subtitle: Text(googleCalendarId==null? '未選擇' : '已選 Google 日曆 ID: $googleCalendarId'),
          value: googleSyncEnabled,
          onChanged: (v) async {
            if(v){
              bool ok = await _handleCalendarPermission();
              if(!ok) return;
              setState(()=> googleSyncEnabled = true);
              await saveAll();
              await syncToGoogle();
            }else{
              setState(()=> googleSyncEnabled = false);
              await saveAll();
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.calendar_month),
          title: const Text('直接取得日曆權限'),
          onTap: _handleCalendarPermission,
        ),
        ListTile(
          leading: const Icon(Icons.sync),
          title: const Text('立即同步到 Google 日曆 (去重)'),
          onTap: syncToGoogle,
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.delete_sweep, color: Colors.red),
          title: const Text('按日期範圍清除排更'),
          subtitle: const Text('只清班次，保留記事，同步刪除 Google'),
          onTap: clearByRange,
        ),
      ])),
      body: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          IconButton(onPressed: (){setState(()=> focusedMonth = DateTime(focusedMonth.year, focusedMonth.month-1));}, icon: const Icon(Icons.arrow_left)),
          Text('${focusedMonth.year}年 ${focusedMonth.month}月', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          IconButton(onPressed: (){setState(()=> focusedMonth = DateTime(focusedMonth.year, focusedMonth.month+1));}, icon: const Icon(Icons.arrow_right)),
        ]),
        Expanded(child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7),
          itemCount: days.length,
          itemBuilder: (_,i){
            DateTime d = days[i];
            String key = "${d.year.toString().padLeft(4,'0')}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}";
            String shift = rosterData[key]?? '';
            String note = notesData[key]?? '';
            bool hasShift = shift.isNotEmpty;
            return GestureDetector(
              onTap: ()=> showEditDialog(key),
              child: Container(margin: const EdgeInsets.all(2), padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(border: Border.all(color: hasShift? Colors.blue: Colors.grey.shade300), borderRadius: BorderRadius.circular(6), color: hasShift? Colors.blue.shade50: Colors.white),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${d.day}', style: const TextStyle(fontSize: 12)),
                  if(hasShift) Text(shift, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                  if(note.isNotEmpty) Text(note, style: const TextStyle(fontSize: 8, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
            );
          },
        )),
      ]),
    );
  }
}
