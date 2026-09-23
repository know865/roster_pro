import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_calendar/device_calendar.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:permission_handler/permission_handler.dart';
import 'package:home_widget/home_widget.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

// ============ MODEL ============
class Shift {
  String code; String name; String start; String end;
  bool isAllDay; double workHours; double otHours;
  bool hasAllowance; Color color;
  Shift({required this.code, required this.name, required this.start, required this.end, this.isAllDay=false, this.workHours=0, this.otHours=0, this.hasAllowance=false, required this.color});
  Map<String,dynamic> toJson()=>{"code":code,"name":name,"start":start,"end":end,"isAllDay":isAllDay,"workHours":workHours,"otHours":otHours,"hasAllowance":hasAllowance,"color":color.value};
  factory Shift.fromJson(Map<String,dynamic> j)=>Shift(code:j['code'],name:j['name'],start:j['start'],end:j['end'],isAllDay:j['isAllDay']??false,workHours:(j['workHours']??0).toDouble(),otHours:(j['otHours']??0).toDouble(),hasAllowance:j['hasAllowance']??false,color:Color(j['color']));
}

class DayEntry {
  String? shiftCode; String note; double ot; double extraHours; double extraAllowance; String allowanceType;
  DayEntry({this.shiftCode, this.note='', this.ot=0, this.extraHours=0, this.extraAllowance=0, this.allowanceType='夜更'});
  Map<String,dynamic> toJson()=>{"shiftCode":shiftCode,"note":note,"ot":ot,"extraHours":extraHours,"extraAllowance":extraAllowance,"allowanceType":allowanceType};
  factory DayEntry.fromJson(Map<String,dynamic> j)=>DayEntry(shiftCode:j['shiftCode'],note:j['note']??'',ot:(j['ot']??0).toDouble(),extraHours:(j['extraHours']??0).toDouble(),extraAllowance:(j['extraAllowance']??0).toDouble(),allowanceType:j['allowanceType']??'夜更');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();
  runApp(MaterialApp(debugShowCheckedModeBanner:false, theme:ThemeData(useMaterial3:true, colorSchemeSeed: Colors.deepPurple), home: RosterApp()));
}

class RosterApp extends StatefulWidget { @override State<RosterApp> createState()=>_RosterAppState(); }

class _RosterAppState extends State<RosterApp> {
  DateTime focusMonth = DateTime(2026,9,1);
  Map<String,Shift> shifts = {};
  Map<String,DayEntry> entries = {}; // key yyyy-MM-dd
  List<String> allowanceTypes = ['夜更','辛勞','特別','額外'];
  List<List<String>> rosterPatterns = [["T","T","T","T","T","Off","Off"]];
  String selectedCalendarId = "";
  int bottomIdx = 0;
  DeviceCalendarPlugin calendarPlugin = DeviceCalendarPlugin();

  @override void initState(){
    super.initState();
    _loadAll();
    HomeWidget.setAppGroupId('group.roster_pro');
  }

  Future<void> _loadAll() async {
    final sp = await SharedPreferences.getInstance();
    if(sp.containsKey('shifts')) shifts = (jsonDecode(sp.getString('shifts')!) as Map).map((k,v)=>MapEntry(k, Shift.fromJson(v)));
    if(sp.containsKey('entries')) entries = (jsonDecode(sp.getString('entries')!) as Map).map((k,v)=>MapEntry(k, DayEntry.fromJson(v)));
    if(sp.containsKey('allowanceTypes')) allowanceTypes = List<String>.from(jsonDecode(sp.getString('allowanceTypes')!));
    if(sp.containsKey('rosterPatterns')) rosterPatterns = List<List<String>>.from(jsonDecode(sp.getString('rosterPatterns')!).map((e)=>List<String>.from(e)));
    selectedCalendarId = sp.getString('calId')??"";
    // 預設班次
    if(shifts.isEmpty){
      shifts = {
        "T":Shift(code:"T",name:"早",start:"07:00",end:"15:00",workHours:8,color:Colors.orange),
        "U":Shift(code:"U",name:"中",start:"15:00",end:"23:00",workHours:8,color:Colors.blue),
        "P":Shift(code:"P",name:"夜",start:"23:00",end:"07:00",workHours:8,color:Colors.purple),
        "Off":Shift(code:"Off",name:"休",start:"00:00",end:"00:00",isAllDay:true,workHours:0,color:Colors.green),
      };
    }
    setState((){});
  }
  Future<void> _saveAll() async {
    final sp = await SharedPreferences.getInstance();
    sp.setString('shifts', jsonEncode(shifts.map((k,v)=>MapEntry(k,v.toJson()))));
    sp.setString('entries', jsonEncode(entries.map((k,v)=>MapEntry(k,v.toJson()))));
    sp.setString('allowanceTypes', jsonEncode(allowanceTypes));
    sp.setString('rosterPatterns', jsonEncode(rosterPatterns));
    sp.setString('calId', selectedCalendarId);
    _updateWidget();
  }

  Future<void> _updateWidget() async {
    // 更新 4x4 小工具顯示本月
    await HomeWidget.saveWidgetData('month', DateFormat('yyyy年M月').format(focusMonth));
    await HomeWidget.updateWidget(name: 'RosterWidgetProvider', androidName: 'RosterWidgetProvider');
  }

  // ============ 日曆同步 - 修復重複 + 全天邏輯 ============
  Future<void> syncSingleDay(DateTime date) async {
    if(selectedCalendarId.isEmpty) return;
    await Permission.calendarFullAccess.request();
    final key = DateFormat('yyyy-MM-dd').format(date);
    final entry = entries[key];
    final tag = "[RosterPro]$key"; // 唯一標記

    try{
      // 1. 先刪除該日所有含 tag 的事件，解決重複
      final params = RetrieveEventsParams(startDate: DateTime(date.year,date.month,date.day), endDate: DateTime(date.year,date.month,date.day,23,59));
      final existing = await calendarPlugin.retrieveEvents(selectedCalendarId, params);
      if(existing.data!=null){
        for(var ev in existing.data!){
          if(ev.description!=null && ev.description!.contains(tag)){
            await calendarPlugin.deleteEvent(selectedCalendarId, ev.eventId);
          }
        }
      }
      // 2. 如果已清除班次(保留記事)，就不新建
      if(entry==null || entry.shiftCode==null || entry.shiftCode!.isEmpty){
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text("$key 已從Google日曆刪除")));
        return;
      }
      final shift = shifts[entry.shiftCode];
      if(shift==null) return;

      final loc = tz.getLocation('Asia/Hong_Kong');
      final isAllDay = shift.isAllDay;
      final note = entry.note;

      // 全天用 allDay=true，標題用 全天 | 記事，不佔版面
      final title = isAllDay? "${shift.code} 全天${note.isNotEmpty?' | $note':''}" : "${shift.code} ${shift.start}-${shift.end}${note.isNotEmpty?' | $note':''}";
      final startTime = isAllDay? tz.TZDateTime.from(DateTime(date.year,date.month,date.day), loc) : tz.TZDateTime.from(DateTime(date.year,date.month,date.day,int.parse(shift.start.split(':')[0]),int.parse(shift.start.split(':')[1])), loc);
      final endTime = isAllDay? tz.TZDateTime.from(DateTime(date.year,date.month,date.day).add(Duration(days:1)), loc) : tz.TZDateTime.from(DateTime(date.year,date.month,date.day,int.parse(shift.end.split(':')[0]),int.parse(shift.end.split(':')[1])).isAfter(DateTime(date.year,date.month,date.day,int.parse(shift.start.split(':')[0]),int.parse(shift.start.split(':')[1])))? DateTime(date.year,date.month,date.day,int.parse(shift.end.split(':')[0]),int.parse(shift.end.split(':')[1])) : DateTime(date.year,date.month,date.day+1,int.parse(shift.end.split(':')[0]),int.parse(shift.end.split(':')[1])), loc);

      final description = "$tag|Hing\n排更: ${shift.code} (${shift.name})\n時間: ${isAllDay?'全天 ${shift.workHours}h':'${shift.start}-${shift.end} ${shift.workHours}h'}\nOT: ${entry.ot}h\n津貼: ${entry.allowanceType}\$${entry.extraAllowance}\n記事: $note\n日期: $key\n同步標記:${DateTime.now().toIso8601String()}";

      final event = Event(selectedCalendarId, title: title, description: description, start: startTime, end: endTime, allDay: isAllDay);
      await calendarPlugin.createOrUpdateEvent(event);
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text("同步完成: $key ${shift.code}"), duration: Duration(seconds:1)));
    }catch(e){
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text("同步失敗 $key: $e")));
    }
  }

  // ============ UI ============
  @override Widget build(BuildContext context){
    return Scaffold(
      body: [buildMonthView(), buildRosterMode(), buildReport(), buildSettings()][bottomIdx],
      bottomNavigationBar: NavigationBar(selectedIndex: bottomIdx, onDestinationSelected: (i)=>setState(()=>bottomIdx=i),
        destinations: [NavigationDestination(icon: Icon(Icons.calendar_month), label:"月曆"), NavigationDestination(icon: Icon(Icons.view_module), label:"模式"), NavigationDestination(icon: Icon(Icons.bar_chart), label:"報表"), NavigationDestination(icon: Icon(Icons.settings), label:"設定")]),
    );
  }

  Widget buildMonthView(){
    final first = DateTime(focusMonth.year, focusMonth.month,1);
    final start = first.subtract(Duration(days:(first.weekday+6)%7)); // 週一開始
    return Column(children:[
      SizedBox(height:40),
      Row(children:[
        DropdownButton<DateTime>(value: focusMonth, items: List.generate(24, (i){ final d=DateTime(2026,1+i); return DropdownMenuItem(value:DateTime(d.year,d.month), child:Text("${d.year}年${d.month}月"));}), onChanged:(v)=>setState(()=>focusMonth=v!)),
        IconButton(icon: Icon(Icons.camera_alt), onPressed: (){}),
        Spacer(),
        FilledButton(onPressed: ()=>setState(()=>focusMonth=DateTime.now()), child:Text("今天"))
      ]),
      Row(children:[SizedBox(width:40, child:Text("週", style:TextStyle(color:Colors.deepPurple))), Expanded(child: Row(children: ["一","二","三","四","五","六","日"].map((e)=>Expanded(child:Center(child:Text(e)))).toList()))]),
      Expanded(child: GridView.builder(gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:8, childAspectRatio:0.8), itemCount: 6*8, itemBuilder: (c, idx){
        if(idx%8==0){ // 週數
          final weekDate = start.add(Duration(days:(idx~/8)*7));
          final weekNum = int.parse(DateFormat('w').format(weekDate));
          return Center(child:Text("W$weekNum", style:TextStyle(fontSize:12, color:Colors.deepPurple)));
        }
        final date = start.add(Duration(days:(idx~/8)*7 + (idx%8)-1));
        final key = DateFormat('yyyy-MM-dd').format(date);
        final entry = entries[key];
        final isThisMonth = date.month==focusMonth.month;
        return GestureDetector(onTap: ()=>_openDayEdit(date), child: Container(margin:EdgeInsets.all(4), decoration: BoxDecoration(color: isThisMonth?Colors.orange.shade100.withOpacity(0.6):Colors.grey.shade200, borderRadius: BorderRadius.circular(12), border: DateFormat('yyyy-MM-dd').format(DateTime.now())==key?Border.all(color:Colors.deepPurple,width:2):null), child: Column(children:[Text("${date.day}", style:TextStyle(fontWeight: FontWeight.bold)), if(entry?.shiftCode!=null) Container(padding:EdgeInsets.symmetric(horizontal:4,vertical:2), decoration: BoxDecoration(color: shifts[entry!.shiftCode]?.color??Colors.grey, borderRadius: BorderRadius.circular(6)), child:Text(entry.shiftCode!, style:TextStyle(fontSize:11,color:Colors.white)))])));
      }))
    ]);
  }

  void _openDayEdit(DateTime date){
    final key = DateFormat('yyyy-MM-dd').format(date);
    final entry = entries[key]??DayEntry();
    String? selected = entry.shiftCode;
    TextEditingController noteC = TextEditingController(text: entry.note);
    TextEditingController otC = TextEditingController(text: entry.ot.toString());
    TextEditingController extraHC = TextEditingController(text: entry.extraHours.toString());
    TextEditingController extraAC = TextEditingController(text: entry.extraAllowance.toString());
    String selectedAllowType = entry.allowanceType;
    showModalBottomSheet(context: context, isScrollControlled:true, builder: (ctx)=> StatefulBuilder(builder:(ctx,setS)=> Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom), child: Container(padding:EdgeInsets.all(16), child: Column(mainAxisSize: MainAxisSize.min, children:[
      Text("${DateFormat('yyyy-MM-dd EEE').format(date)}", style:TextStyle(fontSize:18,fontWeight: FontWeight.bold)),
      SizedBox(height:12),
      Wrap(spacing:8, runSpacing:8, children: shifts.keys.map((code){
        final isSel = selected==code;
        return ChoiceChip(label: Text(code), selected: isSel, onSelected: (v)=> setS(()=> selected=v?code:null));
      }).toList()),
      SizedBox(height:12),
      TextField(controller: noteC, decoration: InputDecoration(labelText:"記事 (會同步到Google日曆標題+描述)")),
      SizedBox(height:8),
      Row(children:[
        Expanded(child: TextField(controller: otC, decoration: InputDecoration(labelText:"OT時數"), keyboardType: TextInputType.number)),
        SizedBox(width:12),
        Expanded(child: TextField(controller: extraHC, decoration: InputDecoration(labelText:"額外工時"), keyboardType: TextInputType.number)),
      ]),
      SizedBox(height:8),
      // 1. 額外津貼可選名稱
      Row(children:[
        DropdownButton<String>(value: allowanceTypes.contains(selectedAllowType)?selectedAllowType:allowanceTypes.first, items: allowanceTypes.map((t)=> DropdownMenuItem(value:t, child:Text(t))).toList(), onChanged:(v)=> setS(()=> selectedAllowType=v!)),
        IconButton(icon: Icon(Icons.edit), onPressed: ()=> _editAllowanceTypes()),
        Expanded(child: TextField(controller: extraAC, decoration: InputDecoration(labelText:"額外津貼 \$"), keyboardType: TextInputType.number)),
      ]),
      SizedBox(height:16),
      Row(children:[
        Expanded(child: OutlinedButton(onPressed: (){ entries.remove(key); _saveAll(); Navigator.pop(ctx); }, child:Text("清除班次(保留記事)", style:TextStyle(color:Colors.orange)))),
        SizedBox(width:12),
        Expanded(child: FilledButton(onPressed: (){ entries[key]=DayEntry(shiftCode:selected, note:noteC.text, ot:double.tryParse(otC.text)??0, extraHours:double.tryParse(extraHC.text)??0, extraAllowance:double.tryParse(extraAC.text)??0, allowanceType:selectedAllowType); _saveAll(); Navigator.pop(ctx); syncSingleDay(date); }, child:Text("儲存")))
      ])
    ])))));
  }

  void _editAllowanceTypes(){
    TextEditingController c = TextEditingController();
    showDialog(context: context, builder: (ctx)=> StatefulBuilder(builder:(ctx,setS)=> AlertDialog(title:Text("自定津貼名稱"), content: Column(mainAxisSize: MainAxisSize.min, children:[
      Wrap(children: allowanceTypes.map((t)=> Chip(label:Text(t), onDeleted: (){ setS(()=> allowanceTypes.remove(t)); _saveAll();})).toList()),
      TextField(controller: c, decoration: InputDecoration(hintText:"新增名稱")),
    ]), actions:[
      TextButton(onPressed: (){ if(c.text.isNotEmpty){ setState(()=> allowanceTypes.add(c.text)); _saveAll(); c.clear(); setS((){});} }, child:Text("新增")),
      FilledButton(onPressed: ()=> Navigator.pop(ctx), child:Text("完成"))
    ])));
  }

  // 編輯班次 - 修復全天跑位
  void _openShiftEdit([Shift? s]){
    bool isEdit = s!=null;
    TextEditingController codeC = TextEditingController(text:s?.code??"");
    TextEditingController nameC = TextEditingController(text:s?.name??"");
    TextEditingController startC = TextEditingController(text:s?.start??"00:00");
    TextEditingController endC = TextEditingController(text:s?.end??"00:00");
    TextEditingController workC = TextEditingController(text:s?.workHours.toString()??"0.0");
    TextEditingController otC = TextEditingController(text:s?.otHours.toString()??"0.0");
    bool isAllDay = s?.isAllDay??false;
    Color selColor = s?.color??Colors.orange;
    showDialog(context: context, builder: (ctx)=> StatefulBuilder(builder:(ctx,setS)=> AlertDialog(title:Text(isEdit?"編輯 ${s!.code}":"新增班次"), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children:[
      TextField(controller: codeC, decoration: InputDecoration(labelText:"代號")),
      TextField(controller: nameC, decoration: InputDecoration(labelText:"名稱")),
      SizedBox(height:8),
      Row(children:[
        Expanded(child: TextField(controller: startC, decoration: InputDecoration(labelText:"開始 HH:mm", border:OutlineInputBorder()))),
        SizedBox(width:8),
        Expanded(child: TextField(controller: endC, decoration: InputDecoration(labelText:"結束 HH:mm", border:OutlineInputBorder()))),
      ]),
      SizedBox(height:12),
      // 修復2：固定高度，不會跑位變大
      Container(padding:EdgeInsets.all(8), decoration: BoxDecoration(border:Border.all(color:Colors.greenAccent,width:2), borderRadius: BorderRadius.circular(12)), child: Column(children:[
        Row(children:[Checkbox(value: isAllDay, onChanged:(v)=> setS(()=> isAllDay=v!),), Text("全天", style:TextStyle(fontWeight: FontWeight.bold)), SizedBox(width:8), Expanded(child: Text("核實全天後時間變00:00，工時可任意轉", style:TextStyle(fontSize:10,color:Colors.grey), overflow: TextOverflow.ellipsis))]),
        SizedBox(height:8),
        SizedBox(height:56, child: Row(children:[
          Expanded(child: TextField(controller: workC, decoration: InputDecoration(labelText:"工時", border:OutlineInputBorder(), isDense:true))),
          SizedBox(width:12),
          Expanded(child: TextField(controller: otC, decoration: InputDecoration(labelText:"OT", border:OutlineInputBorder(), isDense:true))),
        ])),
        Align(alignment: Alignment.centerLeft, child: Text("全天可任意輸入", style:TextStyle(fontSize:12))),
      ])),
      CheckboxListTile(title:Text("有津貼核實"), value:s?.hasAllowance??false, onChanged:(v){}),
      Text("自定班次顏色"), Wrap(children: [Colors.orange,Colors.blue,Colors.purple,Colors.green,Colors.red,Colors.teal,Colors.brown,Colors.pink,Colors.indigo,Colors.amber,Colors.cyan,Colors.lime,Colors.deepOrange,Colors.lightBlue,Colors.deepPurple,Colors.blueGrey].map((co)=> GestureDetector(onTap: ()=> setS(()=> selColor=co), child: Container(margin:EdgeInsets.all(4), width:40,height:40, decoration: BoxDecoration(color:co, shape:BoxShape.circle, border: selColor==co?Border.all(width:3):null)))).toList())
    ])), actions:[
      TextButton(onPressed: ()=> Navigator.pop(ctx), child:Text("取消")),
      FilledButton(onPressed: (){ final ns=Shift(code:codeC.text,name:nameC.text,start:startC.text,end:endC.text,isAllDay:isAllDay,workHours:double.tryParse(workC.text)??0,otHours:double.tryParse(otC.text)??0,color:selColor); setState(()=> shifts[ns.code]=ns); _saveAll(); Navigator.pop(ctx);}, child:Text("儲存"))
    ]))));
  }

  Widget buildRosterMode(){
    TextEditingController rowCountC = TextEditingController(text:"1");
    return Padding(padding: EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
      Center(child: Text("排班模式", style:TextStyle(fontSize:20,fontWeight: FontWeight.bold))), // 3. 第一行置中
      SizedBox(height:8),
      Wrap(spacing:8, children:[FilledButton.tonal(onPressed: (){}, child: Row(children:[Icon(Icons.folder), Text("已存模式(1)")])), FilledButton.tonal(onPressed: (){}, child: Row(children:[Icon(Icons.save_as), Text("另存")])), FilledButton.tonal(onPressed: (){}, child: Text("清空"))]),
      SizedBox(height:12),
      Row(children:[
        Text("一次加 "), SizedBox(width:50, child: TextField(controller: rowCountC, keyboardType:TextInputType.number, decoration: InputDecoration(border:OutlineInputBorder(), isDense:true))), Text(" 行 "),
        ElevatedButton(onPressed: (){ int n=int.tryParse(rowCountC.text)??1; setState(()=> rosterPatterns.addAll(List.generate(n, (_)=> List.filled(7,"T")))); _saveAll();}, child:Text("添加"))
      ]),
      SizedBox(height:12),
      Expanded(child: ListView.builder(itemCount: rosterPatterns.length, itemBuilder: (c,i)=> Row(children:[
        Text("${i+1} "), Expanded(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: rosterPatterns[i].map((code)=> Container(margin:EdgeInsets.all(2), padding:EdgeInsets.symmetric(horizontal:12,vertical:8), color:shifts[code]?.color??Colors.grey.shade300, child:Text(code))).toList()))),
        IconButton(icon:Icon(Icons.delete), onPressed: ()=> setState(()=> rosterPatterns.removeAt(i)))
      ]))),
      Divider(),
      // 3. 無法全部顯示已有的班次代號 -> 用橫向滾動
      Text("所有班次代號(可點選填入):"),
      SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: shifts.keys.map((k)=> Padding(padding:EdgeInsets.all(4), child: ActionChip(label:Text(k), onPressed: (){}))).toList())),
    ]));
  }

  Widget buildReport(){
    double totalWork=0, totalOt=0, totalAllowance=0;
    Map<String,double> allowanceByType={};
    entries.forEach((k,v){ final s=shifts[v.shiftCode]; if(s!=null){ totalWork+=s.workHours+v.extraHours; totalOt+=v.ot; totalAllowance+=v.extraAllowance; allowanceByType[v.allowanceType]=(allowanceByType[v.allowanceType]??0)+v.extraAllowance; }});
    return ListView(padding:EdgeInsets.all(16), children:[
      Text("本月統計", style:TextStyle(fontSize:20,fontWeight: FontWeight.bold)),
      ListTile(title:Text("總工時"), trailing:Text("$totalWork h")),
      ListTile(title:Text("總OT"), trailing:Text("$totalOt h")),
      ListTile(title:Text("總津貼"), trailing:Text("\$$totalAllowance")),
      Divider(),
      Text("按津貼類型:"),
     ...allowanceByType.entries.map((e)=> ListTile(title:Text(e.key), trailing:Text("\$${e.value}"))),
    ]);
  }

  Widget buildSettings(){
    return ListView(padding:EdgeInsets.all(16), children:[
      ListTile(title:Text("Google日曆選擇"), subtitle:Text(selectedCalendarId.isEmpty?"未選擇":selectedCalendarId), onTap: () async {
        await Permission.calendarFullAccess.request();
        final cals = await calendarPlugin.retrieveCalendars();
        showDialog(context: context, builder: (ctx)=> SimpleDialog(title:Text("選擇日曆"), children: cals.data!.map((cal)=> SimpleDialogOption(child:Text("${cal.name}"), onPressed: (){ setState(()=> selectedCalendarId=cal.id!); _saveAll(); Navigator.pop(ctx);})).toList()));
      }),
      ListTile(title:Text("管理班次"), onTap: ()=> showDialog(context: context, builder: (ctx)=> SimpleDialog(title:Text("班次"), children: [...shifts.values.map((s)=> SimpleDialogOption(child:Text("${s.code} ${s.name}"), onPressed: ()=> _openShiftEdit(s))), SimpleDialogOption(child:Text("+ 新增"), onPressed: ()=> _openShiftEdit())]))),
      ListTile(title:Text("手動同步全月"), onTap: () async { for(var i=1;i<=DateTime(focusMonth.year,focusMonth.month+1,0).day;i++){ await syncSingleDay(DateTime(focusMonth.year,focusMonth.month,i)); } }),
      ListTile(title:Text("桌面小工具說明"), subtitle:Text("長按桌面 > 小工具 > RosterPro 4x4，單擊日期顯示詳情，雙擊進入App詳細操作")),
    ]);
  }
}
