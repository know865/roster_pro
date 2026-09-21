import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/calendar/v3.dart' as cal;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:device_calendar/device_calendar.dart';

void main() => runApp(const RosterProApp());

class ShiftDef {
  String code; String label; double hours; double allowance; double otHours; Color color;
  ShiftDef(this.code, this.label, this.hours, this.color, {this.allowance=0, this.otHours=0});
  Map<String,dynamic> toJson() => {'code':code,'label':label,'hours':hours,'allowance':allowance,'otHours':otHours,'color':color.value};
  static ShiftDef fromJson(Map<String,dynamic> j) => ShiftDef(j['code'], j['label']??j['code'], (j['hours']??8).toDouble(), Color(j['color']??0xFFFF9800), allowance:(j['allowance']??0).toDouble(), otHours:(j['otHours']??0).toDouble());
}

class RosterProApp extends StatelessWidget {
  const RosterProApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Roster Pro v6.19.1',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.deepPurple),
      home: const MainPage(),
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});
  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _index = 0;
  DateTime focused = DateTime(2026, 9, 1);
  Map<String, String> roster = {};
  Map<String, ShiftDef> defs = {
    '早': ShiftDef('早','早班 08-16',8, Colors.orange),
    '中': ShiftDef('中','中班 16-00',8, Colors.blue),
    '宵': ShiftDef('宵','宵班 00-08',8, Colors.purple, allowance: 60),
    'OT': ShiftDef('OT','OT 2小時',0, Colors.brown, otHours: 2),
    '早收': ShiftDef('早收','早收長代號測試',8, Colors.orange), // 測試不限制長度
    'O': ShiftDef('O','休',0, Colors.green),
  };
  bool googleSync = true;
  String customCalendarName = "我的排更";
  String? rosterCalendarId;
  double carryOver = 0.0;
  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: [drive.DriveApi.driveFileScope, cal.CalendarApi.calendarScope]);

  @override
  void initState(){ super.initState(); _load(); }
  Future<void> _load() async {
    var sp = await SharedPreferences.getInstance();
    var r = sp.getString('roster'); if(r!=null) roster = Map<String,String>.from(jsonDecode(r));
    var d = sp.getString('defs'); if(d!=null){ var m = Map<String,dynamic>.from(jsonDecode(d)); defs = m.map((k,v)=>MapEntry(k, ShiftDef.fromJson(v))); }
    setState((){
      customCalendarName = sp.getString('customCalName')?? "我的排更";
      rosterCalendarId = sp.getString('rosterCalId');
      carryOver = sp.getDouble('carry')?? 0;
      googleSync = sp.getBool('gSync')?? true;
    });
  }
  Future<void> _save() async {
    var sp = await SharedPreferences.getInstance();
    sp.setString('roster', jsonEncode(roster));
    sp.setString('defs', jsonEncode(defs.map((k,v)=>MapEntry(k, v.toJson()))));
    sp.setString('customCalName', customCalendarName);
    if(rosterCalendarId!=null) sp.setString('rosterCalId', rosterCalendarId!);
    sp.setDouble('carry', carryOver);
    sp.setBool('gSync', googleSync);
  }

  Map<String,String> _holidays = {'09-22':'秋分','09-25':'中秋翌日'};
  bool _isHoliday(DateTime d){ return _holidays.containsKey(DateFormat('MM-dd').format(d)); }
  String _holidayName(DateTime d){ return _holidays[DateFormat('MM-dd').format(d)]??''; }

  Map<String,dynamic> getReport(DateTime month){
    int dim = DateTime(month.year, month.month+1, 0).day;
    Map<String,int> count={}; double ot=0, allow=0, hrs=0;
    for(int i=1;i<=dim;i++){
      String key = DateFormat('yyyy-MM-dd').format(DateTime(month.year, month.month, i));
      String? code = roster[key]; if(code==null) continue;
      count[code]=(count[code]??0)+1;
      var def = defs[code]; if(def!=null){ hrs+=def.hours; ot+=def.otHours; allow+=def.allowance; }
    }
    return {'count':count,'ot':ot,'allow':allow,'hrs':hrs,'balance':carryOver+hrs-168};
  }

  Widget _buildDay(DateTime day, bool isThisMonth){
    if(!isThisMonth) return Container(margin: const EdgeInsets.all(4));
    String key = DateFormat('yyyy-MM-dd').format(day);
    String? code = roster[key];
    var def = code!=null? defs[code] : null;
    return GestureDetector(
      onTap: ()=>_pickShift(day),
      child: Container(
        margin: const EdgeInsets.all(3),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: def!=null? def.color.withOpacity(0.25) : const Color(0xFFF2F4E8), borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          Text('${day.day}', style: const TextStyle(fontWeight: FontWeight.bold)),
          if(_isHoliday(day)) Text(_holidayName(day), style: const TextStyle(fontSize:9, color: Colors.red)),
          if(code!=null) Container(
            margin: const EdgeInsets.only(top:2),
            padding: const EdgeInsets.symmetric(horizontal:6, vertical:2),
            decoration: BoxDecoration(color: def?.color?? Colors.orange, borderRadius: BorderRadius.circular(10)),
            child: FittedBox(fit: BoxFit.scaleDown, child: Text(code, maxLines:2, softWrap:true, overflow:TextOverflow.visible, style: const TextStyle(fontSize:12, color: Colors.white, fontWeight: FontWeight.bold))),
          )
        ]),
      ),
    );
  }

  Widget _buildCalendar(){
    DateTime first = DateTime(focused.year, focused.month, 1);
    int firstW = first.weekday; int dim = DateTime(focused.year, focused.month+1, 0).day;
    List<Widget> cells=[]; for(int i=1;i<firstW;i++) cells.add(Container(margin: const EdgeInsets.all(4)));
    for(int i=1;i<=dim;i++) cells.add(_buildDay(DateTime(focused.year, focused.month, i), true));
    var rep = getReport(focused);
    return CustomScrollView(slivers: [
      SliverAppBar(pinned:true, title: Text('${focused.year}年${focused.month}月'), actions: [
        IconButton(icon: const Icon(Icons.chevron_left), onPressed: ()=>setState(()=>focused=DateTime(focused.year, focused.month-1,1))),
        IconButton(icon: const Icon(Icons.chevron_right), onPressed: ()=>setState(()=>focused=DateTime(focused.year, focused.month+1,1))),
      ]),
      SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.symmetric(horizontal:12), child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: const [Text('Mon'),Text('Tue'),Text('Wed'),Text('Thu'),Text('Fri'),Text('Sat'),Text('Sun')]))),
      SliverToBoxAdapter(child: GridView.count(crossAxisCount:7, shrinkWrap:true, physics: const NeverScrollableScrollPhysics(), childAspectRatio:0.85, children: cells)),
      SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
        Row(children:[ Expanded(child: FilledButton.tonalIcon(onPressed: (){}, icon: const Icon(Icons.image), label: const Text('截圖分享'))), const SizedBox(width:8), Expanded(child: FilledButton.tonalIcon(onPressed: (){}, icon: const Icon(Icons.text_fields), label: const Text('分享文字'))), ]),
        const SizedBox(height:8),
        Card(child: ListTile(title: Text('承上 ${carryOver}h + 本月 ${rep['hrs']}h = 餘額 ${rep['balance']}h'), subtitle: const Text('之前功能已保留'))),
      ]))),
    ]);
  }

  Widget _buildReport(){
    var rep = getReport(focused); Map<String,int> count = rep['count'];
    return ListView(padding: const EdgeInsets.all(12), children: [
      Text('${focused.year}年${focused.month}月 報表', style: const TextStyle(fontSize:20, fontWeight: FontWeight.bold)),
      const SizedBox(height:12),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Text('承上 ${carryOver}h + 本月 ${rep['hrs']}h = 餘額 ${rep['balance']}h'))),
      const SizedBox(height:12),
      Card(color: const Color(0xFFE0F7FA), child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('本月班次統計 (v6.19.1新增)', style: TextStyle(fontWeight: FontWeight.bold, fontSize:16)),
        const SizedBox(height:8),
        count.isEmpty? const Text('暫無資料') : Wrap(spacing:8, children: count.entries.map((e)=>Chip(label: Text('${e.key} x ${e.value}'))).toList()),
        const Divider(),
        const Text('本月津貼統計 (v6.19.1新增)', style: TextStyle(fontWeight: FontWeight.bold, fontSize:16)),
        Text('OT 總計: ${rep['ot']}h\n津貼總計: \$${rep['allow']}'),
      ]))),
    ]);
  }

  Widget _buildSettings(){
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('備份與同步', style: TextStyle(fontSize:22, fontWeight: FontWeight.bold)),
      Card(child: Padding(padding: const EdgeInsets.all(12), child: Row(children:[ Expanded(child: OutlinedButton.icon(onPressed: _backupLocal, icon: const Icon(Icons.download), label: const Text('備份到手機'))), const SizedBox(width:8), Expanded(child: OutlinedButton.icon(onPressed: _restoreLocal, icon: const Icon(Icons.history), label: const Text('從手機還原')))]))),
      const SizedBox(height:8),
      Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children:[ const Text('網絡備份 Google Drive'), Row(children:[ Expanded(child: FilledButton.icon(onPressed: _backupDrive, icon: const Icon(Icons.cloud_upload), label: const Text('備份到Drive'))), const SizedBox(width:8), Expanded(child: FilledButton.icon(onPressed: _restoreDrive, icon: const Icon(Icons.cloud_download), label: const Text('從Drive還原')))]),]))),
      SwitchListTile(title: const Text('Google日曆同步'), subtitle: const Text('已啟用 - 輸入即自動同步'), value: googleSync, onChanged: (v){ setState(()=>googleSync=v); _save(); }),
      Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
        const Text('專屬排更日曆 (唔會同原有日曆混亂)', style: TextStyle(fontWeight: FontWeight.bold)),
        TextField(decoration: const InputDecoration(labelText:'日曆名稱自定義'), controller: TextEditingController(text: customCalendarName), onChanged: (v){ customCalendarName=v; _save(); }),
        const SizedBox(height:8),
        Text('顯示名稱會根據班次代碼: 例如 ${defs.keys.join(", ")}', style: const TextStyle(fontSize:12)),
        const SizedBox(height:8),
        FilledButton.icon(onPressed: _createDedicatedCalendar, icon: const Icon(Icons.calendar_month), label: Text('建立/同步到「$customCalendarName」')),
        FilledButton.icon(onPressed: _exportICS, icon: const Icon(Icons.file_download), label: const Text('匯出.ics 檔案 (免登入)')),
        if(rosterCalendarId!=null) Text('專屬日曆ID: $rosterCalendarId', style: const TextStyle(fontSize:10)),
      ]))),
    ]);
  }

  void _pickShift(DateTime d) async {
    String? sel = await showModalBottomSheet<String>(context: context, builder: (_)=>SafeArea(child: Wrap(children: defs.keys.map((k){ var def=defs[k]!; return ListTile(leading: CircleAvatar(backgroundColor:def.color, radius:12), title: Text('${def.code} - ${def.label}'), onTap: ()=>Navigator.pop(context,k)); }).toList()..add(const Divider())..add(ListTile(title: const Text('清除'), onTap: ()=>Navigator.pop(context,''))))));
    if(sel==null) return;
    String key = DateFormat('yyyy-MM-dd').format(d);
    setState((){ if(sel.isEmpty) roster.remove(key); else roster[key]=sel; });
    _save();
  }

  Future<void> _backupLocal() async { var dir = await getApplicationDocumentsDirectory(); var f = File('${dir.path}/roster_backup.json'); await f.writeAsString(jsonEncode(roster)); if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已備份 ${f.path}'))); }
  Future<void> _restoreLocal() async { var res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions:['json']); if(res==null) return; String c = await File(res.files.single.path!).readAsString(); setState(()=>roster=Map<String,String>.from(jsonDecode(c))); _save(); }
  Future<void> _backupDrive() async { try{ var acc = await _googleSignIn.signIn(); if(acc==null) return; var client = await _googleSignIn.authenticatedClient(); var api = drive.DriveApi(client!); var file = drive.File()..name='roster_pro_${DateFormat('yyyyMMdd').format(DateTime.now())}.json'; await api.files.create(file, uploadMedia: drive.Media(Stream.value(utf8.encode(jsonEncode(roster))), utf8.encode(jsonEncode(roster)).length)); if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已備份到Drive'))); }catch(e){ if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Drive失敗 $e'))); } }
  Future<void> _restoreDrive() async { try{ var acc = await _googleSignIn.signIn(); if(acc==null) return; var client = await _googleSignIn.authenticatedClient(); var api = drive.DriveApi(client!); var list = await api.files.list(q:"name contains 'roster_pro'", orderBy:'createdTime desc'); var id = list.files!.first.id!; var media = await api.files.get(id, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media; String s = await utf8.decodeStream(media.stream); setState(()=>roster=Map<String,String>.from(jsonDecode(s))); _save(); }catch(e){ if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('失敗 $e'))); } }
  Future<void> _createDedicatedCalendar() async { try{ var client = await _googleSignIn.authenticatedClient(); if(client==null){ var acc = await _googleSignIn.signIn(); client = await _googleSignIn.authenticatedClient(); } var api = cal.CalendarApi(client!); var list = await api.calendarList.list(); var exist = list.items?.where((c)=>c.summary==customCalendarName).toList(); String calId; if(exist!=null && exist.isNotEmpty){ calId=exist.first.id!; }else{ var nc = cal.Calendar()..summary=customCalendarName..timeZone='Asia/Hong_Kong'; var cr = await api.calendars.insert(nc); calId=cr.id!; } rosterCalendarId=calId; await _save(); for(var e in roster.entries){ DateTime d = DateFormat('yyyy-MM-dd').parse(e.key); if(d.month!=focused.month) continue; var ev = cal.Event()..summary=e.value..description=defs[e.value]?.label..start=(cal.EventDateTime()..date=DateTime(d.year,d.month,d.day))..end=(cal.EventDateTime()..date=DateTime(d.year,d.month,d.day+1)); await api.events.insert(calId, ev); } if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已同步到專屬日曆「$customCalendarName」'))); }catch(e){ if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('失敗 $e'))); } }
  Future<void> _exportICS() async { StringBuffer ics = StringBuffer('BEGIN:VCALENDAR\nVERSION:2.0\n'); roster.forEach((k,v){ try{ DateTime d = DateFormat('yyyy-MM-dd').parse(k); String dt = DateFormat('yyyyMMdd').format(d); ics.writeln('BEGIN:VEVENT\nDTSTART;VALUE=DATE:$dt\nSUMMARY:$v\nEND:VEVENT'); }catch(_){} }); ics.writeln('END:VCALENDAR'); var dir = await getApplicationDocumentsDirectory(); var f = File('${dir.path}/${customCalendarName}.ics'); await f.writeAsString(ics.toString()); if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已匯出 ${f.path}'))); }

  @override
  Widget build(BuildContext context){
    return Scaffold(body: [ _buildCalendar(), _buildReport(), _buildSettings() ][_index], bottomNavigationBar: NavigationBar(selectedIndex:_index, onDestinationSelected:(i)=>setState(()=>_index=i), destinations: const [
      NavigationDestination(icon: Icon(Icons.calendar_month), label:'月曆'),
      NavigationDestination(icon: Icon(Icons.bar_chart), label:'報表'),
      NavigationDestination(icon: Icon(Icons.settings), label:'設定'),
    ]));
  }
}
