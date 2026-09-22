import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:device_calendar/device_calendar.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzData;
import 'package:permission_handler/permission_handler.dart';

void main() { tzData.initializeTimeZones(); runApp(const RosterApp()); }

class ShiftDef {
  String code; String label; double hours; double ot; Color color; String start; String end; bool hasAllowance; double allowance;
  ShiftDef(this.code,this.label,this.hours,this.color,{this.ot=0,this.start='07:00',this.end='15:30',this.hasAllowance=false,this.allowance=0});
  Map<String,dynamic> toJson()=>{'code':code,'label':label,'hours':hours,'ot':ot,'color':color.value,'start':start,'end':end,'hasAllowance':hasAllowance,'allowance':allowance};
  factory ShiftDef.fromJson(Map<String,dynamic> j)=>ShiftDef(j['code'],j['label']??j['code'],(j['hours']??8).toDouble(),Color(j['color']??0xFFFF9800),ot:(j['ot']??0).toDouble(),start:j['start']??'07:00',end:j['end']??'15:30',hasAllowance:j['hasAllowance']??((j['allowance']??0)>0),allowance:(j['allowance']??0).toDouble());
  String get detailTime=>'$start-$end ${hours.toStringAsFixed(1)}h';
}
class ExtraAllowance { String name; double amount; ExtraAllowance(this.name,this.amount); Map<String,dynamic> toJson()=>{'name':name,'amount':amount}; factory ExtraAllowance.fromJson(Map<String,dynamic> j)=>ExtraAllowance(j['name'],(j['amount'] as num).toDouble()); }
class SavedPattern { String name; List<List<String>> data; SavedPattern(this.name,this.data); Map<String,dynamic> toJson()=>{'name':name,'data':data}; factory SavedPattern.fromJson(Map<String,dynamic> j)=>SavedPattern(j['name'], (j['data'] as List).map<List<String>>((r)=>(r as List).map<String>((e)=>e.toString()).toList()).toList()); }
class RosterApp extends StatelessWidget { const RosterApp({super.key}); @override Widget build(BuildContext context){ return MaterialApp(title:'Roster Pro v6.83',theme:ThemeData(useMaterial3:true,colorSchemeSeed:Colors.deepPurple),home:const MainPage()); } }

class MainPage extends StatefulWidget { const MainPage({super.key}); @override State<MainPage> createState()=>MainPageState(); }
class MainPageState extends State<MainPage> {
int tab=0; DateTime focused=DateTime.now(); DateTime selectedDay=DateTime.now();
Map<String,String> roster={}; Map<String,String> rosterNote={}; Map<String,double> rosterOt={}; Map<String,double> rosterExtra={}; Map<String,double> rosterExtraHrs={};
Map<String,ShiftDef> defs={
  '早':ShiftDef('早','早更',8,Colors.orange,start:'07:00',end:'15:30',hasAllowance:true,allowance:80),
  '中':ShiftDef('中','中更',8,Colors.blue,start:'14:00',end:'22:00',hasAllowance:false,allowance:0),
  '宵':ShiftDef('宵','宵更',8,Colors.purple,start:'22:00',end:'06:00',hasAllowance:true,allowance:60),
  'O':ShiftDef('O','休',0,Colors.green,start:'00:00',end:'00:00',hasAllowance:false,allowance:0),
};
List<List<String>> pattern=[["早","早","中","中","宵","宵","O"],["早","早","早","中","中","O","O"]];
List<SavedPattern> savedPatterns=[]; double carry=0; String customName='我的排更-專屬日曆'; TextEditingController nameCtrl=TextEditingController();
double standardWeeklyHours=42; double overtimeRate=80; List<ExtraAllowance> extraAllowances=[]; double calendarFontSize=14;
bool googleSyncEnabled=false; bool autoSync=false; bool isYearReport=false; bool showAllShift=false; bool showAllExtra=false;
String? editingPatternName; int? editingPatternIndex; String holidayRegion='香港';
GlobalKey calKey=GlobalKey();
DeviceCalendarPlugin _calendarPlugin = DeviceCalendarPlugin();
String? _rosterCalendarId;
Map<String,String> _googleEventIdMap={};
bool _isSyncing=false;

Map<String,String> getHolidays(int year, String region){
  if(region=='無') return {};
  if(region=='香港'){ return {'$year-01-01':'元旦','$year-01-29':'農曆年初一','$year-01-30':'農曆年初二','$year-01-31':'農曆年初三','$year-04-04':'清明節','$year-05-01':'勞動節','$year-05-05':'佛誕','$year-06-19':'端午節','$year-07-01':'香港回歸','$year-09-25':'中秋翌日','$year-10-01':'國慶','$year-10-19':'重陽節','$year-12-25':'聖誕節',}; }
  if(region=='中國內地'){ return {'$year-01-01':'元旦','$year-05-01':'勞動節','$year-10-01':'國慶'}; }
  if(region=='台灣'){ return {'$year-01-01':'元旦','$year-02-28':'和平紀念','$year-10-10':'國慶'}; }
  if(region=='美國'){ return {'$year-01-01':'New Year','$year-07-04':'Independence','$year-12-25':'Christmas'}; }
  return {};
}
bool isHoliday(DateTime d){ var map=getHolidays(d.year, holidayRegion); return map.containsKey(DateFormat('yyyy-MM-dd').format(d)); }
String holidayName(DateTime d){ var map=getHolidays(d.year, holidayRegion); return map[DateFormat('yyyy-MM-dd').format(d)]??''; }

@override void initState(){ super.initState(); nameCtrl.text=customName; load().then((_) async { await Future.delayed(const Duration(milliseconds:800)); _handleCalendarPermission(silent:true); }); }
Future<void> load() async{
  var sp=await SharedPreferences.getInstance();
  var r=sp.getString('roster'); if(r!=null) roster=Map<String,String>.from(jsonDecode(r));
  var rn=sp.getString('note'); if(rn!=null) rosterNote=Map<String,String>.from(jsonDecode(rn));
  var ro=sp.getString('roOt'); if(ro!=null){ try{ rosterOt=Map<String,double>.from((jsonDecode(ro) as Map).map((k,v)=>MapEntry(k as String,(v as num).toDouble()))); }catch(_){} }
  var re=sp.getString('roEx'); if(re!=null){ try{ rosterExtra=Map<String,double>.from((jsonDecode(re) as Map).map((k,v)=>MapEntry(k as String,(v as num).toDouble()))); }catch(_){} }
  var reh=sp.getString('roExH'); if(reh!=null){ try{ rosterExtraHrs=Map<String,double>.from((jsonDecode(reh) as Map).map((k,v)=>MapEntry(k as String,(v as num).toDouble()))); }catch(_){} }
  var d=sp.getString('defs'); if(d!=null){ try{ var m=Map<String,dynamic>.from(jsonDecode(d)); defs=m.map((k,v)=>MapEntry(k,ShiftDef.fromJson(Map<String,dynamic>.from(v)))); }catch(_){} }
  var p=sp.getString('pattern'); if(p!=null){ try{ var l=jsonDecode(p) as List; pattern=l.map<List<String>>((row)=>(row as List).map<String>((e)=>e.toString()).toList()).toList(); }catch(_){} }
  var ea=sp.getString('extraAllowNewV36'); if(ea!=null){ try{ extraAllowances=(jsonDecode(ea) as List).map((e)=>ExtraAllowance.fromJson(Map<String,dynamic>.from(e))).toList(); }catch(_){} }
  var spSaved=sp.getString('savedPatternsV40'); if(spSaved!=null){ try{ savedPatterns=(jsonDecode(spSaved) as List).map((e)=>SavedPattern.fromJson(Map<String,dynamic>.from(e))).toList(); }catch(_){} }
  var evMap=sp.getString('googleEventIdMap'); if(evMap!=null){ try{ _googleEventIdMap=Map<String,String>.from(jsonDecode(evMap)); }catch(_){} }
  setState((){
    carry=sp.getDouble('carry')??0; customName=sp.getString('cName')??'我的排更-專屬日曆'; nameCtrl.text=customName;
    standardWeeklyHours=sp.getDouble('stdWeek')??42; overtimeRate=sp.getDouble('otRate')??80;
    calendarFontSize=sp.getDouble('calFont')??14; googleSyncEnabled=sp.getBool('gSync')??false; autoSync=sp.getBool('gAuto')??false;
    holidayRegion=sp.getString('holidayRegion')??'香港'; _rosterCalendarId=sp.getString('rosterCalId');
  });
}
Future<void> save() async{
  var sp=await SharedPreferences.getInstance();
  sp.setString('roster',jsonEncode(roster)); sp.setString('note',jsonEncode(rosterNote)); sp.setString('roOt',jsonEncode(rosterOt));
  sp.setString('roEx',jsonEncode(rosterExtra)); sp.setString('roExH',jsonEncode(rosterExtraHrs));
  sp.setString('defs',jsonEncode(defs.map((k,v)=>MapEntry(k,v.toJson())))); sp.setString('pattern',jsonEncode(pattern));
  sp.setDouble('carry',carry); sp.setString('cName',customName); sp.setDouble('stdWeek',standardWeeklyHours);
  sp.setDouble('otRate',overtimeRate); sp.setString('extraAllowNewV36',jsonEncode(extraAllowances.map((e)=>e.toJson()).toList()));
  sp.setDouble('calFont',calendarFontSize); sp.setBool('gSync',googleSyncEnabled); sp.setBool('gAuto',autoSync);
  sp.setString('savedPatternsV40',jsonEncode(savedPatterns.map((e)=>e.toJson()).toList())); sp.setString('holidayRegion', holidayRegion);
  sp.setString('googleEventIdMap', jsonEncode(_googleEventIdMap));
  if(_rosterCalendarId!=null) sp.setString('rosterCalId', _rosterCalendarId!);
  if(autoSync && googleSyncEnabled &&!_isSyncing){ _syncToGoogle(silent:true); }
}
int isoWeek(DateTime date){ DateTime thursday=date.add(Duration(days:4-date.weekday)); DateTime jan1=DateTime(thursday.year,1,1); int days=thursday.difference(jan1).inDays; return 1+(days/7).floor(); }
void quickJumpMonth({bool forReport=false}){ int y=focused.year; int m=focused.month; showDialog(context:context,builder:(ctx){ return StatefulBuilder(builder:(ctx2,setD){ return AlertDialog(title:Text(forReport?'選擇報表年月':'快速查找年月'),content:Column(mainAxisSize:MainAxisSize.min,children:[Row(children:[IconButton(icon:const Icon(Icons.remove),onPressed:()=>setD(()=>y--)),Expanded(child:Text('$y年',textAlign:TextAlign.center,style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold))),IconButton(icon:const Icon(Icons.add),onPressed:()=>setD(()=>y++))]),Wrap(spacing:8,children:List.generate(12,(i){ int mon=i+1; return ChoiceChip(label:Text('${mon}月'),selected:mon==m,onSelected:(_)=>setD(()=>m=mon)); }))]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx2),child:const Text('取消')),FilledButton(onPressed:(){ setState(()=>focused=DateTime(y,m,1)); Navigator.pop(ctx2); },child:const Text('跳轉'))]); }); }); }

Future<bool> _handleCalendarPermission({bool silent=false}) async {
  try { await Permission.calendar.request(); } catch(_){}
  try { await Permission.calendarFullAccess.request(); } catch(_){}
  try { await Permission.calendarWriteOnly.request(); } catch(_){}
  var devHas = await _calendarPlugin.hasPermissions();
  if (devHas.isSuccess && devHas.data==true) return true;
  var devReq = await _calendarPlugin.requestPermissions();
  if (devReq.isSuccess && devReq.data==true) return true;
  var s1 = await Permission.calendar.status;
  var s2 = await Permission.calendarFullAccess.status;
  if(s1.isGranted || s2.isGranted) return true;
  if (!silent) {
    bool? go = await showDialog<bool>(context: context, builder: (ctx)=>AlertDialog(
      title: const Text('需要手動開啟日曆權限 (三星 Android 14)'),
      content: const Text('三星會攔截：\n1. 按 前往設定\n2. 權限 → 日曆 → 允許\n3. 額外：顯示全部日曆 → 開啟'),
      actions: [TextButton(onPressed: ()=>Navigator.pop(ctx,false), child: const Text('取消')), FilledButton(onPressed: ()=>Navigator.pop(ctx,true), child: const Text('前往設定'))]
    ));
    if (go==true) await openAppSettings();
  }
  return false;
}

Future<String?> _pickGoogleCalendarDialog() async {
  await _handleCalendarPermission(silent:true);
  var calsResult=await _calendarPlugin.retrieveCalendars();
  var cals=calsResult.data??[];
  List<Calendar> writable = cals.where((c)=>c.isReadOnly==false).toList().cast<Calendar>();
  List<Calendar> all = cals.cast<Calendar>();
  List<Calendar> displayList = writable.isNotEmpty? writable : all;

  Calendar? picked = await showDialog<Calendar>(context: context, builder: (ctx){
    return AlertDialog(
      title: Text('選擇日曆 (可寫${writable.length} / 總${all.length})'),
      content: SizedBox(width: 420, height: 420, child: Column(children:[
        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.orange.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
          child: Text(
            writable.isEmpty? '可寫0：權限被三星攔截，請按下方 前往設定 → 權限 → 日曆 → 允許全部\n\n下面顯示的是手機全部日曆（只讀也會顯示），揀你的 Gmail 賬號' :
            '已找到 ${writable.length} 個可寫，${all.length} 個總數。請揀 Gmail 賬號',
            style: const TextStyle(fontSize:12, color: Colors.deepOrange),
          ),
        ),
        const SizedBox(height:8),
        Expanded(child: displayList.isEmpty? const Center(child:Text('真的無任何日曆，請去 手機 設定 → 帳號 → 加入 Google')) : ListView.builder(
          itemCount: displayList.length,
          itemBuilder: (c,i){
            var cal = displayList[i];
            String acc = cal.accountName??'無帳號';
            String type = cal.accountType??'未知';
            bool isRead = cal.isReadOnly==true;
            bool isGoogle = acc.toLowerCase().contains('gmail') || acc.contains('@') || type.toLowerCase().contains('google') || type.contains('com.google');
            return ListTile(
              dense: true,
              leading: Icon(isGoogle? Icons.account_circle : Icons.phone_android, color: isGoogle? Colors.blue : (isRead? Colors.grey: Colors.orange)),
              title: Text(cal.name??'未命名', style: TextStyle(fontSize:13, fontWeight: isGoogle? FontWeight.bold: FontWeight.normal)),
              subtitle: Text('帳號:$acc\n類型:$type\n${isRead?'只讀 🔒':'可寫 ✏️'} | ID:${cal.id?.substring(0,12)??''}', style: const TextStyle(fontSize:9)),
              isThreeLine: true,
              enabled:!isRead,
              onTap: isRead? null : ()=>Navigator.pop(ctx, cal),
              trailing: cal.name==customName? const Icon(Icons.check, color: Colors.green): (isGoogle? const Icon(Icons.star, size:14, color: Colors.blue):null),
            );
          },
        )),
      ])),
      actions: [
        TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('取消')),
        TextButton(onPressed: () async { await openAppSettings(); }, child: const Text('前往設定開權限')),
        FilledButton.icon(icon: const Icon(Icons.add), label: Text('新建「$customName」'), onPressed: () async {
          var cr = await _calendarPlugin.createCalendar(customName, calendarColor: Colors.deepPurple);
          if(cr.isSuccess && cr.data!=null){
            var after = await _calendarPlugin.retrieveCalendars();
            var all2 = after.data??[];
            var found = all2.where((x)=>x.id==cr.data).toList();
            if(found.isNotEmpty){ Navigator.pop(ctx, found.first); return; }
            var same = all2.where((x)=>x.name==customName).toList().cast<Calendar>();
            if(same.isNotEmpty){ Navigator.pop(ctx, same.first); return; }
          }
          if(context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('新建失敗，可能是權限不足，請先去設定開權限')));
        }),
      ],
    );
  });
  return picked?.id;
}

Future<void> _requestGooglePerm() async{
  String? id = await _pickGoogleCalendarDialog();
  if(id==null) return;
  _rosterCalendarId=id;
  var sp=await SharedPreferences.getInstance(); sp.setString('rosterCalId', id);
  bool? ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('已選擇日曆'),content:Text('將同步到：\n$customName\n日曆ID: $id\n\n已開啟去重'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('取消')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('同步'))]));
  if(ok==true){ setState(()=>googleSyncEnabled=true); await _syncToGoogle(); save(); }
}

Future<void> _ensureCalendar() async{
  if(_rosterCalendarId!=null){
    var cals=await _calendarPlugin.retrieveCalendars();
    if(cals.data!=null && cals.data!.any((c)=>c.id==_rosterCalendarId)) return;
  }
  String? id = await _pickGoogleCalendarDialog();
  if(id!=null) _rosterCalendarId=id;
}

Future<void> _syncToGoogle({bool silent=false}) async{
  if(!googleSyncEnabled) return;
  if(_isSyncing) return;
  _isSyncing=true;
  try{
    if(_rosterCalendarId==null) await _ensureCalendar(); if(_rosterCalendarId==null) throw '未選日曆';
    var existingEvents=await _calendarPlugin.retrieveEvents(_rosterCalendarId!, RetrieveEventsParams(startDate: DateTime(2023,1,1), endDate: DateTime(2030,12,31)));
    for(var e in existingEvents.data??[]){ if((e.description??'').contains('[RosterPro]')){ await _calendarPlugin.deleteEvent(_rosterCalendarId!, e.eventId); } }
    _googleEventIdMap.clear();
    for(var entry in roster.entries){
      var code=entry.value; var def=defs[code]; if(def==null) continue;
      DateTime date=DateFormat('yyyy-MM-dd').parse(entry.key);
      var startParts=def.start.split(':'); var endParts=def.end.split(':');
      DateTime startDt=DateTime(date.year,date.month,date.day,int.parse(startParts[0]),int.parse(startParts[1]));
      DateTime endDt=def.end=='00:00'? DateTime(date.year,date.month,date.day+1,0,0) : DateTime(date.year,date.month,date.day,int.parse(endParts[0]),int.parse(endParts[1]));
      if(endDt.isBefore(startDt)) endDt=endDt.add(const Duration(days:1));
      String title = '$code ${def.start}-${def.end}';
      String note = rosterNote[entry.key]??'';
      String desc = '[RosterPro]${entry.key}|$customName\n排更: $code\n時間: ${def.start}-${def.end} ${def.hours}h\n記事: $note\n日期: ${entry.key}${isHoliday(date)?'\n假期: ${holidayName(date)}':''}';
      var ev=Event(_rosterCalendarId!, title:title, description:desc, start:tz.TZDateTime.from(startDt, tz.local), end:tz.TZDateTime.from(endDt, tz.local));
      var res=await _calendarPlugin.createOrUpdateEvent(ev);
      if(res!=null && res.isSuccess && res.data!=null) _googleEventIdMap[entry.key]=res.data!;
    }
    var sp=await SharedPreferences.getInstance(); sp.setString('googleEventIdMap', jsonEncode(_googleEventIdMap));
    if(!silent && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('已同步到 [$customName] ${roster.length}項 去重完成')));
  }catch(e){ if(!silent && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('同步失敗 $e'))); }
  finally { _isSyncing=false; }
}

Future<void> clearRosterByRange() async{
  DateTimeRange? range=await showDateRangePicker(context:context, firstDate: DateTime(2023), lastDate: DateTime(2030), helpText: '選擇要清除的排更範圍');
  if(range==null) return;
  int count=0;
  for(DateTime d=range.start;!d.isAfter(range.end); d=d.add(const Duration(days:1))){
    String k=DateFormat('yyyy-MM-dd').format(d);
    if(roster.containsKey(k)){
      count++;
      roster.remove(k); rosterOt.remove(k); rosterExtra.remove(k); rosterExtraHrs.remove(k);
      if(_googleEventIdMap.containsKey(k) && _rosterCalendarId!=null){
        try{ await _calendarPlugin.deleteEvent(_rosterCalendarId!, _googleEventIdMap[k]); }catch(_){}
        _googleEventIdMap.remove(k);
      }
    }
  }
  await save(); setState((){});
  if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('已清除 $count 天排更')));
}

Future<void> shareScreenshotDialog() async{ _exportShareImage(); }
Future<void> _exportShareImage() async{
  try{
    RenderRepaintBoundary? b=calKey.currentContext?.findRenderObject() as RenderRepaintBoundary?; ui.Image? calImg; if(b!=null){ calImg=await b.toImage(pixelRatio:3); }
    final recorder=ui.PictureRecorder(); final canvas=Canvas(recorder); double width=1080; double y=0; final paintWhite=Paint()..color=Colors.white;
    double calHeight = calImg!=null? width * calImg.height / calImg.width : 0;
    Set<String> usedCodes={}; int dim=DateTime(focused.year,focused.month+1,0).day; for(int i=1;i<=dim;i++){ String k=DateFormat('yyyy-MM-dd').format(DateTime(focused.year,focused.month,i)); if(roster[k]!=null) usedCodes.add(roster[k]!); }
    List<ShiftDef> legendDefs = defs.entries.where((e)=>usedCodes.contains(e.key)).map((e)=>e.value).toList();
    double legendHeight = legendDefs.length*32 + 60; double totalHeight = calHeight + legendHeight + 20;
    canvas.drawRect(Rect.fromLTWH(0,0,width,totalHeight), paintWhite);
    if(calImg!=null){ canvas.drawImageRect(calImg, Rect.fromLTWH(0,0,calImg.width.toDouble(),calImg.height.toDouble()), Rect.fromLTWH(0,0,width,calHeight), Paint()); y=calHeight+12; }
    TextPainter tp=TextPainter(textDirection: ui.TextDirection.ltr);
    tp.text=const TextSpan(text:'班次詳細時間圖例 (本月使用)：',style: TextStyle(color:Colors.black,fontSize:22,fontWeight:FontWeight.bold)); tp.layout(maxWidth:width); tp.paint(canvas, Offset(20,y)); y+=34;
    for(var v in legendDefs){ canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(20,y,22,22), const Radius.circular(6)), Paint()..color=v.color); tp.text=TextSpan(text:' ${v.code} ${v.label} ${v.start}-${v.end}${v.hasAllowance?' 津貼\$${v.allowance}':''}',style: const TextStyle(color:Colors.black87,fontSize:19)); tp.layout(maxWidth:width-60); tp.paint(canvas, Offset(50,y)); y+=30; }
    final pic=recorder.endRecording(); final img=await pic.toImage(width.toInt(), (y+10).toInt()); final byte=await img.toByteData(format: ui.ImageByteFormat.png); final png=byte!.buffer.asUint8List();
    Directory baseDir=Directory('/storage/emulated/0/Pictures/Roster'); if(!await baseDir.exists()){ await baseDir.create(recursive:true); }
    String path='${baseDir.path}/roster_month_${focused.year}_${focused.month}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.jpg'; File f=File(path); await f.writeAsBytes(png);
    if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('整月截圖已保存 $path')));
  }catch(e){ if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('截圖失敗 $e'))); }
}

Future<void> backupAnywhere() async{
  String? dir=await FilePicker.platform.getDirectoryPath(dialogTitle:'選擇備份位置'); if(dir==null) return;
  String fileName='roster_pro_full_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.json';
  var backup = {'version':'6.83_full','exportTime':DateTime.now().toIso8601String(),'roster':roster,'note':rosterNote,'roOt':rosterOt,'roEx':rosterExtra,'roExH':rosterExtraHrs,'defs':defs.map((k,v)=>MapEntry(k,v.toJson())),'pattern':pattern,'carry':carry,'cName':customName,'stdWeek':standardWeeklyHours,'otRate':overtimeRate,'extraNewV36':extraAllowances.map((e)=>e.toJson()).toList(),'calFont':calendarFontSize,'savedPatterns':savedPatterns.map((e)=>e.toJson()).toList(),'holidayRegion':holidayRegion,'rosterCalId':_rosterCalendarId,'googleEventIdMap':_googleEventIdMap,'gSync':googleSyncEnabled,'gAuto':autoSync,};
  var f=File('$dir/$fileName'); await f.writeAsString(jsonEncode(backup));
  if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('全部備份 $dir/$fileName')));
}
Future<void> restoreLocalFile() async{
  var res=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['json']); if(res==null) return;
  try{ String c=await File(res.files.single.path!).readAsString(); var j=jsonDecode(c); setState((){
      if(j['roster']!=null) roster=Map<String,String>.from(j['roster']); if(j['note']!=null) rosterNote=Map<String,String>.from(j['note']);
      if(j['roOt']!=null) rosterOt=Map<String,double>.from((j['roOt'] as Map).map((k,v)=>MapEntry(k as String,(v as num).toDouble())));
      if(j['roEx']!=null) rosterExtra=Map<String,double>.from((j['roEx'] as Map).map((k,v)=>MapEntry(k as String,(v as num).toDouble())));
      if(j['roExH']!=null) rosterExtraHrs=Map<String,double>.from((j['roExH'] as Map).map((k,v)=>MapEntry(k as String,(v as num).toDouble())));
      if(j['defs']!=null) defs=(j['defs'] as Map).map<String,ShiftDef>((k,v)=>MapEntry(k as String,ShiftDef.fromJson(Map<String,dynamic>.from(v as Map))));
      if(j['pattern']!=null) pattern=(j['pattern'] as List).map<List<String>>((r)=>(r as List).map<String>((e)=>e.toString()).toList()).toList();
      if(j['carry']!=null) carry=(j['carry'] as num).toDouble(); if(j['cName']!=null){ customName=j['cName']; nameCtrl.text=customName; }
      if(j['stdWeek']!=null) standardWeeklyHours=(j['stdWeek'] as num).toDouble(); if(j['otRate']!=null) overtimeRate=(j['otRate'] as num).toDouble();
      if(j['extraNewV36']!=null) extraAllowances=(j['extraNewV36'] as List).map((e)=>ExtraAllowance.fromJson(Map<String,dynamic>.from(e as Map))).toList();
      if(j['calFont']!=null) calendarFontSize=(j['calFont'] as num).toDouble(); if(j['savedPatterns']!=null) savedPatterns=(j['savedPatterns'] as List).map((e)=>SavedPattern.fromJson(Map<String,dynamic>.from(e as Map))).toList();
      if(j['holidayRegion']!=null) holidayRegion=j['holidayRegion']; if(j['rosterCalId']!=null) _rosterCalendarId=j['rosterCalId'];
      if(j['googleEventIdMap']!=null) _googleEventIdMap=Map<String,String>.from(j['googleEventIdMap']); if(j['gSync']!=null) googleSyncEnabled=j['gSync']; if(j['gAuto']!=null) autoSync=j['gAuto'];
    }); save(); if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('還原成功'))); }catch(e){ if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('還原失敗 $e'))); }
}
Future<void> exportReport() async{ StringBuffer sb=StringBuffer(); if(!isYearReport){ int dim=DateTime(focused.year,focused.month+1,0).day; double hrs=0,ot=0; double allow=0; Map<String,int> shiftCount={}; for(int i=1;i<=dim;i++){ DateTime dt=DateTime(focused.year,focused.month,i); String k=DateFormat('yyyy-MM-dd').format(dt); String? c=roster[k]; if(c==null) continue; var d=defs[c]; if(d!=null){ hrs+=d.hours; shiftCount[c]=(shiftCount[c]??0)+1; if(d.hasAllowance) allow+=d.allowance; } ot+=(rosterOt[k]??d?.ot??0); allow+=(rosterExtra[k]??0); hrs+=(rosterExtraHrs[k]??0); } sb.writeln('${focused.year}年${focused.month}月 報表'); shiftCount.forEach((k,v)=>sb.writeln('$k $v次')); sb.writeln('總工時 $hrs OT $ot 津貼 \$${allow+ot*overtimeRate}'); }else{ sb.writeln('${focused.year}年 全年統計'); for(int mon=1;mon<=12;mon++){ int dim=DateTime(focused.year,mon+1,0).day; double hrs=0; Map<String,int> sc={}; for(int d=1;d<=dim;d++){ DateTime dt=DateTime(focused.year,mon,d); String k=DateFormat('yyyy-MM-dd').format(dt); String? c=roster[k]; if(c==null) continue; var def=defs[c]; if(def!=null){ hrs+=def.hours; sc[c]=(sc[c]??0)+1; } } sb.writeln('$mon月 ${hrs}h $sc'); } } String? path=await FilePicker.platform.saveFile(dialogTitle:'匯出報表',fileName:'report_${isYearReport?'year_${focused.year}':'${focused.year}_${focused.month}'}.csv',type:FileType.custom,allowedExtensions:['csv','txt']); if(path!=null){ await File(path).writeAsString(sb.toString()); if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('已匯出 $path'))); } }

Widget calTab(){
  DateTime first=DateTime(focused.year,focused.month,1); DateTime start=first.subtract(Duration(days:first.weekday-1));
  int daysInMonth=DateTime(focused.year,focused.month+1,0).day; int neededCells=first.weekday-1+daysInMonth; int weeks=(neededCells/7).ceil(); if(weeks<5) weeks=5; if(weeks>6) weeks=6;
  List<DateTime> days=List.generate(weeks*7,(i)=>start.add(Duration(days:i)));
  String selKey=DateFormat('yyyy-MM-dd').format(selectedDay); var selDef=roster[selKey]!=null?defs[roster[selKey]]:null;
  double selOt=rosterOt[selKey]??selDef?.ot??0; String note=rosterNote[selKey]??'無';
  DateTime today=DateTime.now();
  return SafeArea(child:Column(children:[
    Padding(padding:const EdgeInsets.fromLTRB(12,8,12,4),child:Row(children:[InkWell(onTap:()=>quickJumpMonth(),child:Row(children:[Text('${focused.year}年${focused.month}月',style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const Icon(Icons.arrow_drop_down)])),const Spacer(),IconButton(icon:const Icon(Icons.camera_alt_outlined),tooltip:'整月截圖',onPressed:shareScreenshotDialog),IconButton(icon:const Icon(Icons.chevron_left),onPressed:(){ setState(()=>focused=DateTime(focused.year,focused.month-1,1)); }),IconButton(icon:const Icon(Icons.chevron_right),onPressed:(){ setState(()=>focused=DateTime(focused.year,focused.month+1,1)); }),FilledButton.tonal(onPressed:(){ setState((){ focused=DateTime(today.year,today.month,1); selectedDay=DateTime(today.year,today.month,today.day); }); },child:const Text('今天')),])),
    RepaintBoundary(key:calKey,child:Column(children:[Padding(padding:const EdgeInsets.symmetric(horizontal:6),child:Row(children:[Container(width:32,child:const Text('週',textAlign:TextAlign.center,style:TextStyle(fontWeight:FontWeight.bold,fontSize:11,color:Colors.deepPurple))),Expanded(child:Row(children:["一","二","三","四","五","六","日"].map((w)=>Expanded(child:Text(w,textAlign:TextAlign.center,style:const TextStyle(fontSize:11)))).toList()))])),ListView.builder(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),padding:EdgeInsets.zero,itemCount:weeks,itemBuilder:(ctx,row){ return Row(children:[Container(width:32,alignment:Alignment.center,child:Text('W${isoWeek(days[row*7])}',style:const TextStyle(fontSize:11,color:Colors.deepPurple,fontWeight:FontWeight.bold))),Expanded(child:GridView.builder(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),padding:const EdgeInsets.all(3),gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:7,childAspectRatio:0.78,mainAxisSpacing:4,crossAxisSpacing:4),itemCount:7,itemBuilder:(ctx2,col){ int idx=row*7+col; DateTime day=days[idx]; bool inM=day.month==focused.month; String k=DateFormat('yyyy-MM-dd').format(day); String? code=roster[k]; var def=code!=null?defs[code]:null; bool sel=k==selKey; bool isToday = day.year==today.year && day.month==today.month && day.day==today.day; bool hasNote = rosterNote.containsKey(k) && rosterNote[k]!.isNotEmpty; bool isHol = isHoliday(day); Color bg; if(isToday){ bg=const Color(0xFFFFF9C4); } else if(!inM){ bg=const Color(0xFFF5F5F0); } else if(sel){ bg=Colors.white; } else if(def!=null){ bg=def.color.withOpacity(0.18); } else { bg=const Color(0xFFFFF0D0); } return GestureDetector(onTap:(){ setState(()=>selectedDay=day); },child:Container(decoration:BoxDecoration(color:bg,borderRadius:BorderRadius.circular(12),border:isToday?Border.all(width:2.5,color:Colors.orange):sel?Border.all(width:2,color:Colors.deepPurple):null),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Text('${day.day}',style:TextStyle(fontWeight:isToday?FontWeight.w900:FontWeight.bold,fontSize:calendarFontSize-1,color:inM?Colors.black:Colors.grey)),if(code!=null) FittedBox(child:Container(margin:const EdgeInsets.only(top:1),padding:const EdgeInsets.symmetric(horizontal:4,vertical:1),decoration:BoxDecoration(color:def?.color??Colors.orange,borderRadius:BorderRadius.circular(8)),child:Text(code,style:TextStyle(color:Colors.white,fontSize:calendarFontSize-2)))),const SizedBox(height:2),Row(mainAxisAlignment:MainAxisAlignment.center,children:[if(isHol) Container(width:6,height:6,margin:const EdgeInsets.symmetric(horizontal:1),decoration:const BoxDecoration(color:Colors.red,shape:BoxShape.circle)),if(hasNote) Container(width:6,height:6,margin:const EdgeInsets.symmetric(horizontal:1),decoration:const BoxDecoration(color:Colors.blue,shape:BoxShape.circle)),]),]))); })),]); }),])),
    Container(width:double.infinity,padding:const EdgeInsets.fromLTRB(12,10,12,12),decoration:const BoxDecoration(color:Colors.white,border:Border(top:BorderSide(color:Color(0xFFE0E0E0)))),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Row(children:[Text('${DateFormat('MM/dd EEE').format(selectedDay)} ${roster[selKey]??'未排班'}${isHoliday(selectedDay)?' [${holidayName(selectedDay)}]':''}',style:const TextStyle(fontSize:16,fontWeight:FontWeight.bold)),const SizedBox(width:8),if(selDef!=null) Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:3),decoration:BoxDecoration(color:selDef.color,borderRadius:BorderRadius.circular(10)),child:Text(selDef.code,style:const TextStyle(color:Colors.white,fontSize:11,fontWeight:FontWeight.bold))),const Spacer(),FilledButton.tonalIcon(onPressed:(){ showDetail(selectedDay); },icon:const Icon(Icons.edit,size:16),label:const Text('編輯',style:TextStyle(fontSize:12)),style: FilledButton.styleFrom(minimumSize:const Size(0,34),padding:const EdgeInsets.symmetric(horizontal:12))),]),const SizedBox(height:8),Container(width:double.infinity,padding:const EdgeInsets.all(10),decoration:BoxDecoration(color:const Color(0xFFF5F5F5),borderRadius:BorderRadius.circular(12)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('1. 班次：${selDef?.label??'無'} ${selDef!=null?'(${selDef.code})':''} ${isHoliday(selectedDay)?'[${holidayName(selectedDay)}]':''}',style:const TextStyle(fontSize:13,fontWeight:FontWeight.bold)),const SizedBox(height:3),Text('2. 時間：${selDef!=null?'${selDef.start} - ${selDef.end}': '無'} | 工時：${selDef?.hours.toStringAsFixed(1)??'0'}h',style:const TextStyle(fontSize:12)),const SizedBox(height:3),Text('3. 津貼：${selDef!=null && selDef.hasAllowance?'有 \$${selDef.allowance}':'無'} + 單日 \$${rosterExtra[selKey]??0}',style:const TextStyle(fontSize:12)),const SizedBox(height:3),Text('4. OT：${selOt.toStringAsFixed(1)}h + 額外工時 ${(rosterExtraHrs[selKey]??0).toStringAsFixed(1)}h',style:const TextStyle(fontSize:12)),const SizedBox(height:3),Text('5. 記事：${note.isEmpty?'無':note}',style:const TextStyle(fontSize:12),maxLines:2,overflow:TextOverflow.ellipsis),const SizedBox(height:3),if(selectedDay.weekday==7) Builder(builder: (ctx){ double weekActual=0; DateTime mon=selectedDay.subtract(const Duration(days:6)); for(int i=0;i<7;i++){ DateTime d=mon.add(Duration(days:i)); String k=DateFormat('yyyy-MM-dd').format(d); String? c=roster[k]; if(c!=null){ var dd=defs[c]; if(dd!=null) weekActual+=dd.hours; } weekActual+=(rosterOt[DateFormat('yyyy-MM-dd').format(mon.add(Duration(days:i)))]??0); weekActual+=(rosterExtraHrs[DateFormat('yyyy-MM-dd').format(mon.add(Duration(days:i)))]??0); } double weekDiff=weekActual-standardWeeklyHours; return Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:4),decoration:BoxDecoration(color:weekDiff>0?Colors.green.withOpacity(0.12):Colors.red.withOpacity(0.12),borderRadius:BorderRadius.circular(8)),child:Text('6. 本週(W${isoWeek(selectedDay)}) 實際 ${weekActual.toStringAsFixed(1)}h / 標準 ${standardWeeklyHours}h = 差額 ${weekDiff>=0?'+':''}${weekDiff.toStringAsFixed(1)}h',style:TextStyle(fontSize:12,fontWeight:FontWeight.bold,color:weekDiff>0?Colors.green:Colors.red))); }),]))])),
  ]));
}
void showDetail(DateTime day){
  String k=DateFormat('yyyy-MM-dd').format(day); String cur=roster[k]??''; var nc=TextEditingController(text:rosterNote[k]??''); var otc=TextEditingController(text:(rosterOt[k]??0).toString()); var exCtrl=TextEditingController(text:(rosterExtra[k]??0).toString()); var exHCtrl=TextEditingController(text:(rosterExtraHrs[k]??0).toString());
  showModalBottomSheet(context:context,isScrollControlled:true,builder:(ctx){ return StatefulBuilder(builder:(ctx2,setM){ return Padding(padding:EdgeInsets.only(bottom:MediaQuery.of(ctx2).viewInsets.bottom),child:Padding(padding:const EdgeInsets.all(16),child:Column(mainAxisSize:MainAxisSize.min,children:[Text('${DateFormat('yyyy-MM-dd EEE').format(day)}${isHoliday(day)?' [${holidayName(day)}]':''}',style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),Wrap(spacing:8,children:defs.keys.map((c)=>ChoiceChip(label:Text(c),selected:cur==c,onSelected:(_)=>setM(()=>cur=c))).toList()),TextField(controller:nc,decoration:const InputDecoration(labelText:'記事 (會同步到Google日曆)')),Row(children:[Expanded(child:TextField(controller:otc,decoration:const InputDecoration(labelText:'OT時數'),keyboardType:TextInputType.number)),const SizedBox(width:8),Expanded(child:TextField(controller:exHCtrl,decoration:const InputDecoration(labelText:'額外工時'),keyboardType:TextInputType.number)),]),TextField(controller:exCtrl,decoration:const InputDecoration(labelText:'額外津貼 \$'),keyboardType:TextInputType.number),const SizedBox(height:12),Row(children:[Expanded(child:OutlinedButton(onPressed:() async { setState((){ roster.remove(k); rosterOt.remove(k); rosterExtra.remove(k); rosterExtraHrs.remove(k); }); if(_googleEventIdMap.containsKey(k) && _rosterCalendarId!=null){ try{ await _calendarPlugin.deleteEvent(_rosterCalendarId!, _googleEventIdMap[k]); }catch(_){} _googleEventIdMap.remove(k); } save(); Navigator.pop(ctx2); },child:const Text('清除班次(保留記事)',style:TextStyle(color: Colors.orange)),)),const SizedBox(width:8),Expanded(child:FilledButton(onPressed:(){ double? otVal=double.tryParse(otc.text); double? exVal=double.tryParse(exCtrl.text); double? exHVal=double.tryParse(exHCtrl.text); setState((){ if(cur.isNotEmpty) roster[k]=cur; if(nc.text.isNotEmpty) rosterNote[k]=nc.text; else rosterNote.remove(k); if(otVal!=null) rosterOt[k]=otVal; if(exVal!=null && exVal!=0) rosterExtra[k]=exVal; else rosterExtra.remove(k); if(exHVal!=null && exHVal!=0) rosterExtraHrs[k]=exHVal; else rosterExtraHrs.remove(k); }); save(); Navigator.pop(ctx2); },child:const Text('儲存'))),]),]))); }); }); }
Future<void> pickRangeAndApply() async{ List<List<String>> chosenPattern = pattern; if(savedPatterns.isNotEmpty){ int? selected = await showDialog<int>(context:context,builder:(ctx){ return AlertDialog(title:const Text('選擇排更模式'),content:SizedBox(width:300,child:ListView(shrinkWrap:true,children:[ListTile(title:const Text('當前版面'),subtitle:Text('${pattern.length}行'),leading:const Icon(Icons.edit),onTap:()=>Navigator.pop(ctx,-1)),const Divider(),...savedPatterns.asMap().entries.map((en)=>ListTile(title:Text(en.value.name),subtitle:Text('${en.value.data.length}行'),leading:const Icon(Icons.folder),onTap:()=>Navigator.pop(ctx,en.key))),],)),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('取消'))]); }); if(selected==null) return; if(selected==-1){ chosenPattern = pattern; } else { chosenPattern = savedPatterns[selected].data.map((r)=>List<String>.from(r)).toList(); } } DateTimeRange? p=await showDateRangePicker(context:context,firstDate:DateTime(2023),lastDate:DateTime(2030)); if(p==null) return; var flat=chosenPattern.expand((e)=>e).toList(); setState((){ int i=0; for(DateTime d=p.start;!d.isAfter(p.end);d=d.add(const Duration(days:1))){ roster[DateFormat('yyyy-MM-dd').format(d)]=flat[i%flat.length]; i++; } }); save(); setState(()=>tab=0); }
Widget patternTab(){ return SafeArea(child:Column(children:[Padding(padding:const EdgeInsets.all(12),child:SingleChildScrollView(scrollDirection:Axis.horizontal,child:Row(children:[const Text('排更模式',style:TextStyle(fontWeight:FontWeight.bold)),const SizedBox(width:8),if(editingPatternName!=null) Container(padding:const EdgeInsets.symmetric(horizontal:10,vertical:6),decoration:BoxDecoration(color:Colors.orange.withOpacity(0.15),borderRadius:BorderRadius.circular(20),border:Border.all(color:Colors.orange)),child:Row(children:[Text('正在編輯：$editingPatternName',style:const TextStyle(fontSize:12,fontWeight:FontWeight.bold)),const SizedBox(width:6),InkWell(onTap:(){ setState(()=>pattern=[["早","早","中","中","宵","宵","O"]]); editingPatternName=null; editingPatternIndex=null; },child:const Icon(Icons.close,size:16))]),),const SizedBox(width:8),FilledButton.tonalIcon(icon:const Icon(Icons.folder),label:Text('已存模式${savedPatterns.isEmpty?'': '(${savedPatterns.length})'}'),onPressed:(){ if(savedPatterns.isEmpty){ ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('未有已存模式'))); return; } showModalBottomSheet(context:context,builder:(ctx)=>SafeArea(child:ListView(children:[const ListTile(title:Text('已存排班模式',style:TextStyle(fontWeight:FontWeight.bold))),...savedPatterns.asMap().entries.map((en)=>ListTile(title:Text(en.value.name),subtitle:Text('${en.value.data.length}行'),trailing:Row(mainAxisSize:MainAxisSize.min,children:[IconButton(icon:const Icon(Icons.upload),onPressed:(){ setState((){ pattern=en.value.data.map((r)=>List<String>.from(r)).toList(); editingPatternName=en.value.name; editingPatternIndex=en.key; }); save(); Navigator.pop(ctx); }),IconButton(icon:const Icon(Icons.delete),onPressed:(){ setState(()=>savedPatterns.removeAt(en.key)); save(); Navigator.pop(ctx); }),]))),]))); }),const SizedBox(width:8),if(editingPatternName!=null) FilledButton.icon(icon:const Icon(Icons.save),label:Text('保存同名'),onPressed:(){ if(editingPatternIndex!=null){ setState(()=>savedPatterns[editingPatternIndex!]=SavedPattern(editingPatternName!,pattern.map((r)=>List<String>.from(r)).toList())); save(); setState((){ pattern=[["早","早","中","中","宵","宵","O"]]; editingPatternName=null; editingPatternIndex=null; }); } }),const SizedBox(width:8),FilledButton.tonalIcon(icon:const Icon(Icons.save_as),label:const Text('另存'),onPressed:(){ var ctrl=TextEditingController(text:editingPatternName??'模式_${DateFormat('MMdd').format(DateTime.now())}'); showDialog(context:context,builder:(ctx)=>AlertDialog(title:const Text('另存排更模式'),content:TextField(controller:ctrl,decoration:const InputDecoration(labelText:'模式名稱 (不能同名)')),actions:[FilledButton(onPressed:(){ String n=ctrl.text.trim(); if(n.isEmpty) return; if(savedPatterns.any((e)=>e.name==n)){ ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('名稱 $n 已存在'))); return; } setState(()=>savedPatterns.add(SavedPattern(n,pattern.map((r)=>List<String>.from(r)).toList()))); save(); Navigator.pop(ctx); setState(()=>pattern=[["早","早","中","中","宵","宵","O"]]); editingPatternName=null; editingPatternIndex=null; },child:const Text('保存並回到預設')),])); }),const SizedBox(width:8),FilledButton.tonal(onPressed:(){ setState(()=>pattern.add(List.filled(7,'O'))); save(); },child:const Text('加一行')),]))),Expanded(child:ListView.builder(itemCount:pattern.length,itemBuilder:(ctx,r){ return Row(children:[Container(width:32,alignment:Alignment.centerRight,child:Text('${r+1}',style:const TextStyle(fontWeight:FontWeight.bold))),const SizedBox(width:4),Expanded(child:Row(children:List.generate(7,(c){ return Expanded(child:GestureDetector(onTap:(){ showModalBottomSheet(context:context,builder:(ctx){ return Wrap(children:defs.keys.map((k)=>ListTile(title:Text(k),onTap:(){ setState(()=>pattern[r][c]=k); save(); Navigator.pop(ctx); })).toList()); }); },child:Container(margin:const EdgeInsets.all(2),height:36,color:defs[pattern[r][c]]?.color.withOpacity(0.3),child:Center(child:Text(pattern[r][c]))))); }))),IconButton(icon:const Icon(Icons.delete),onPressed:(){ setState(()=>pattern.removeAt(r)); save(); }),]); })),Padding(padding:const EdgeInsets.all(12),child:SizedBox(width:double.infinity,child:FilledButton(onPressed:pickRangeAndApply,child:const Text('選擇日期範圍並自動排班')))),])); }
Widget reportTab(){
  int year=focused.year; int month=focused.month; double totalYearHrs=0; Map<String,int> yearShiftCount={}; Map<int,double> yearMonthlyHrs={};
  if(isYearReport){ for(int m=1;m<=12;m++){ int dim=DateTime(year,m+1,0).day; double hrs=0; for(int d=1;d<=dim;d++){ String k=DateFormat('yyyy-MM-dd').format(DateTime(year,m,d)); String? c=roster[k]; if(c==null) continue; var def=defs[c]; if(def!=null){ hrs+=def.hours; totalYearHrs+=def.hours; yearShiftCount[c]=(yearShiftCount[c]??0)+1; } } yearMonthlyHrs[m]=hrs; } }
  int dim=DateTime(year,month+1,0).day; double hrs=0,ot=0; double allow=0; Map<String,int> shiftCount={}; Map<String,double> shiftHours={}; Map<int,double> weeklyHours={};
  for(int i=1;i<=dim;i++){ DateTime dt=DateTime(year,month,i); String k=DateFormat('yyyy-MM-dd').format(dt); String? c=roster[k]; if(c==null) continue; var d=defs[c]; double curOt=rosterOt[k]??d?.ot??0; if(d!=null){ hrs+=d.hours; shiftCount[c]=(shiftCount[c]??0)+1; shiftHours[c]=(shiftHours[c]??0)+d.hours; if(d.hasAllowance) allow+=d.allowance; int w=isoWeek(dt); weeklyHours[w]=(weeklyHours[w]??0)+d.hours; } ot+=curOt; allow+=(rosterExtra[k]??0); hrs+=(rosterExtraHrs[k]??0); }
  double otAmount=ot * overtimeRate; double totalAllow=allow + otAmount;
  return SafeArea(child: ListView(padding: const EdgeInsets.all(12),children: [
    Row(children:[IconButton(onPressed:exportReport,icon:const Icon(Icons.ios_share),tooltip:'匯出',style:IconButton.styleFrom(backgroundColor:Colors.deepPurple.withOpacity(0.1))),const SizedBox(width:4),InkWell(onTap:()=>quickJumpMonth(forReport:true),child:Row(mainAxisSize:MainAxisSize.min,children:[Text('${year}年${isYearReport?' 全年': ' ${month}月'} 報表',style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),const Icon(Icons.arrow_drop_down)])),const Spacer(),SegmentedButton<bool>(segments:const [ButtonSegment(value:false,label:Text('本月')),ButtonSegment(value:true,label:Text('全年'))],selected:{isYearReport},onSelectionChanged:(s){ setState(()=>isYearReport=s.first); }),]),
    const SizedBox(height:8),
    if(isYearReport) Card(color:const Color(0xFFE3F2FD),child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('全年總工時 ${totalYearHrs.toStringAsFixed(1)}h',style:const TextStyle(fontWeight:FontWeight.bold)), const Divider(),...yearMonthlyHrs.entries.map((e)=>Row(children:[Text('${e.key}月'),const Spacer(),Text('${e.value.toStringAsFixed(1)}h')])),const Divider(),...yearShiftCount.entries.map((e){ var d=defs[e.key]; return Row(children:[Container(width:26,height:26,decoration:BoxDecoration(color:d?.color??Colors.grey,borderRadius:BorderRadius.circular(5)),child:Center(child:Text(e.key,style:const TextStyle(color:Colors.white,fontSize:10)))), const SizedBox(width:6), Text('${d?.label??e.key} ${e.value}次'), const Spacer(), Text('${(e.value*(d?.hours??0)).toStringAsFixed(1)}h')]); }),]))),
    if(!isYearReport) Card(color:const Color(0xFFE3F2FD),child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('班次統計',style:TextStyle(fontWeight:FontWeight.bold)), const Divider(),...shiftCount.entries.map((e){ double h=shiftHours[e.key]??0; var d=defs[e.key]; return Padding(padding:const EdgeInsets.symmetric(vertical:2),child:Row(children:[Container(width:28,height:28,decoration:BoxDecoration(color:d?.color??Colors.grey,borderRadius:BorderRadius.circular(6)),child:Center(child:Text(e.key,style:const TextStyle(color:Colors.white,fontSize:11)))), const SizedBox(width:8), Text('${d?.label??e.key} ${(d?.hasAllowance==true)?'有津貼':''}'), const Spacer(), Text('${e.value}次 / ${h.toStringAsFixed(1)}h',style:const TextStyle(fontWeight:FontWeight.bold)),])); }),const Divider(), Text('總工時 ${hrs.toStringAsFixed(1)}h / 承上 ${carry}h / 合計 ${(hrs+carry).toStringAsFixed(1)}h'),]))),
    Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('承上 $carry h + 本月 $hrs h = ${carry+hrs}h',style:const TextStyle(fontWeight:FontWeight.bold)), const Divider(), Text(isYearReport?'每週工時統計 全年':'每週工時統計 (標準 & 承上) 週數',style:const TextStyle(fontWeight:FontWeight.bold)),...weeklyHours.entries.map((e){ double avgCarry=weeklyHours.isEmpty?0:carry/weeklyHours.length; double adjusted=e.value + avgCarry; double diff=adjusted - standardWeeklyHours; return Padding(padding:const EdgeInsets.symmetric(vertical:3),child:Row(children:[Text('W${e.key}',style:const TextStyle(fontWeight:FontWeight.bold)), const SizedBox(width:8), Text('${e.value.toStringAsFixed(1)}h +承上${avgCarry.toStringAsFixed(1)} = ${adjusted.toStringAsFixed(1)}h'), const Spacer(), Text('${diff>=0?'+':''}${diff.toStringAsFixed(1)}h',style:TextStyle(color:diff>0?Colors.green:Colors.red,fontWeight:FontWeight.bold)),])); }),const Divider(), Text('標準 ${standardWeeklyHours}h/週 | 總差額 ${(carry+hrs - standardWeeklyHours*weeklyHours.length).toStringAsFixed(1)}h'),]))),
    Card(color:const Color(0xFFE8F5E9),child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('津貼類別 (僅班次核實津貼)',style:TextStyle(fontWeight:FontWeight.bold)),if(rosterExtra.isNotEmpty) Row(children:[const Text('單日額外津貼'),const Spacer(),Text('\$${rosterExtra.values.fold(0.0,(a,b)=>a+b).toStringAsFixed(1)}')]),const Divider(),Row(children:[const Text('班次津貼'),const Spacer(),Text('\$${allow.toStringAsFixed(1)}')]),Row(children:[Text('OT ${ot.toStringAsFixed(1)}h x \$${overtimeRate.toStringAsFixed(0)}'),const Spacer(),Text('\$${otAmount.toStringAsFixed(1)}')]),const Divider(),Row(children:[const Text('津貼總額 (含OT)'),const Spacer(),Text('\$${totalAllow.toStringAsFixed(1)}',style:const TextStyle(fontWeight:FontWeight.bold))]),]))),
  ],),);
}
void editShiftDialog({ShiftDef? oldDef}){ var codeCtrl=TextEditingController(text:oldDef?.code??''); var labelCtrl=TextEditingController(text:oldDef?.label??''); var hoursCtrl=TextEditingController(text:oldDef?.hours.toString()??'8'); var otCtrl=TextEditingController(text:oldDef?.ot.toString()??'0'); var startCtrl=TextEditingController(text:oldDef?.start??'07:00'); var endCtrl=TextEditingController(text:oldDef?.end??'15:30'); var allowCtrl=TextEditingController(text:oldDef?.allowance.toString()??'0'); bool hasAllow=oldDef?.hasAllowance??false; Color picked=oldDef?.color??Colors.orange; String oldKey=oldDef?.code??''; List<Color> palette=[Colors.orange,Colors.blue,Colors.purple,Colors.green,Colors.red,Colors.teal,Colors.brown,Colors.pink,Colors.indigo,Colors.amber,Colors.cyan,Colors.lime,Colors.deepOrange,Colors.lightBlue,Colors.deepPurple,Colors.blueGrey]; showDialog(context:context,builder:(ctx){ return StatefulBuilder(builder:(ctx2,setS){ return AlertDialog(title:Text(oldDef==null?'新增班次':'編輯 ${oldDef.code}'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[TextField(controller:codeCtrl,decoration:const InputDecoration(labelText:'代號')),TextField(controller:labelCtrl,decoration:const InputDecoration(labelText:'名稱')),Row(children:[Expanded(child:TextField(controller:startCtrl,decoration:const InputDecoration(labelText:'開始 HH:mm'))),const SizedBox(width:8),Expanded(child:TextField(controller:endCtrl,decoration:const InputDecoration(labelText:'結束 HH:mm')))]),Row(children:[Expanded(child:TextField(controller:hoursCtrl,decoration:const InputDecoration(labelText:'工時'))),Expanded(child:TextField(controller:otCtrl,decoration:const InputDecoration(labelText:'OT')))]),const SizedBox(height:12),Row(children:[Checkbox(value:hasAllow,onChanged:(v)=>setS(()=>hasAllow=v??false)),const Text('有津貼核實',style:TextStyle(fontWeight:FontWeight.bold))]),if(hasAllow) TextField(controller:allowCtrl,decoration:const InputDecoration(labelText:'津貼金額 \$',prefixText:'\$ ',border:OutlineInputBorder()),keyboardType:TextInputType.number),const SizedBox(height:12), const Text('自定班次顏色',style:TextStyle(fontWeight:FontWeight.bold)), const SizedBox(height:8),Wrap(spacing:8,runSpacing:8,children:palette.map((c)=>GestureDetector(onTap:()=>setS(()=>picked=c),child:Container(width:36,height:36,decoration:BoxDecoration(color:c,shape:BoxShape.circle,border:picked==c?Border.all(width:3,color:Colors.black):null),child:picked==c?const Icon(Icons.check,color:Colors.white,size:18):null))).toList()),])),actions:[TextButton(onPressed:()=>Navigator.pop(ctx2),child:const Text('取消')),FilledButton(onPressed:(){ String newCode=codeCtrl.text.trim(); if(newCode.isEmpty) return; double hrs=double.tryParse(hoursCtrl.text)??8; try{ var s=DateFormat('HH:mm').parse(startCtrl.text); var e=DateFormat('HH:mm').parse(endCtrl.text); var diff=e.difference(s).inMinutes/60.0; if(diff<0) diff+=24; hrs=diff; }catch(_){} double allowVal=double.tryParse(allowCtrl.text)??0; setState((){ if(oldKey.isNotEmpty && oldKey!=newCode){ defs.remove(oldKey); roster.forEach((k,v){ if(v==oldKey) roster[k]=newCode; }); for(int i=0;i<pattern.length;i++){ for(int j=0;j<pattern[i].length;j++){ if(pattern[i][j]==oldKey) pattern[i][j]=newCode; } } } defs[newCode]=ShiftDef(newCode,labelCtrl.text.isEmpty?newCode:labelCtrl.text,hrs,picked,ot:double.tryParse(otCtrl.text)??0,start:startCtrl.text,end:endCtrl.text,hasAllowance:hasAllow,allowance:hasAllow?allowVal:0); }); save(); Navigator.pop(ctx2); },child:const Text('儲存'))]); }); }); }
Widget settingsTab(){
  var stdCtrl=TextEditingController(text:standardWeeklyHours.toString()); var carryCtrl=TextEditingController(text:carry.toString()); var otRateCtrl=TextEditingController(text:overtimeRate.toString());
  List<MapEntry<String,ShiftDef>> shiftList=defs.entries.toList(); List<MapEntry<String,ShiftDef>> shiftShow=showAllShift? shiftList : shiftList.take(5).toList(); List<ExtraAllowance> allowShow=showAllExtra? extraAllowances : extraAllowances.take(5).toList();
  return SafeArea(child:ListView(padding:const EdgeInsets.all(16),children:[
    const Text('排更日曆自定名稱',style:TextStyle(fontSize:16,fontWeight:FontWeight.bold)),
    Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(children:[TextField(controller:nameCtrl,decoration:const InputDecoration(labelText:'日曆名稱',border:OutlineInputBorder())),const SizedBox(height:8),SizedBox(width:double.infinity,child:FilledButton(onPressed:(){ setState(()=>customName=nameCtrl.text.trim().isEmpty?'我的排更':nameCtrl.text.trim()); save(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('日曆名已改為 $customName'))); },child:const Text('保存日曆名稱')))]))),
    const SizedBox(height:16), const Text('自定班次',style:TextStyle(fontSize:16,fontWeight:FontWeight.bold)),
    Card(child:Column(children:[...shiftShow.map((e){ var d=e.value; return ListTile(leading:CircleAvatar(backgroundColor:d.color,child:Text(d.code,style:const TextStyle(color:Colors.white,fontSize:10))),title:Text('${d.code} - ${d.label} ${d.start}-${d.end} ${d.hasAllowance?'[有津貼\$${d.allowance}]':''}'),subtitle:Text('${d.hours.toStringAsFixed(1)}h | ${d.detailTime}'),trailing:Row(mainAxisSize:MainAxisSize.min,children:[IconButton(icon:const Icon(Icons.edit),onPressed:()=>editShiftDialog(oldDef:d)),IconButton(icon:const Icon(Icons.delete),onPressed:(){ setState(()=>defs.remove(e.key)); save(); })])); }),if(shiftList.length>5) TextButton(onPressed:(){ setState(()=>showAllShift=!showAllShift); },child:Text(showAllShift?'收起':'顯示全部 ${shiftList.length}項')),ListTile(leading:const Icon(Icons.add),title:const Text('新增班次'),onTap:()=>editShiftDialog()),])),
    const SizedBox(height:16), const Text('公眾假期地區',style:TextStyle(fontSize:16,fontWeight:FontWeight.bold)),
    Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(children:[DropdownButtonFormField<String>(value:holidayRegion,decoration:const InputDecoration(labelText:'地區',border:OutlineInputBorder()),items:['無','香港','中國內地','台灣','美國'].map((r)=>DropdownMenuItem(value:r,child:Text(r))).toList(),onChanged:(v){ setState(()=>holidayRegion=v!); save(); }),]))),
    const SizedBox(height:16), const Text('日曆同步 - 診斷版 v6.83',style:TextStyle(fontSize:16,fontWeight:FontWeight.bold)),
    Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(children:[
      SwitchListTile(title:const Text('啟用日曆同步'),subtitle:Text(googleSyncEnabled?'已授權':'未授權'),value:googleSyncEnabled,onChanged:(v) async { if(v){ await _requestGooglePerm(); }else{ setState(()=>googleSyncEnabled=false); save(); } }),
      SwitchListTile(title:const Text('自動同步(去重)'),value:autoSync,onChanged:googleSyncEnabled? (v){ setState(()=>autoSync=v); save(); }:null),
      Row(children:[Expanded(child:OutlinedButton.icon(onPressed:googleSyncEnabled? ()=>_syncToGoogle():null,icon:const Icon(Icons.sync),label:const Text('手動同步'))),const SizedBox(width:8),Expanded(child:OutlinedButton.icon(onPressed:(){ setState(()=>googleSyncEnabled=false); save(); },icon:const Icon(Icons.link_off),label:const Text('取消')))]),
      Text('當前ID: ${_rosterCalendarId??'未選'}',style:const TextStyle(fontSize:10,color:Colors.grey)),
      const SizedBox(height:8),
      SizedBox(width: double.infinity, child: OutlinedButton.icon(icon:const Icon(Icons.list), label:const Text('選擇/診斷日曆'), onPressed: () async { String? id=await _pickGoogleCalendarDialog(); if(id!=null){ setState(()=>_rosterCalendarId=id); save(); }})),
      SizedBox(width: double.infinity, child: FilledButton.icon(icon:const Icon(Icons.security), label:const Text('取得日曆權限 + 去設定'), onPressed: () async { await _handleCalendarPermission(silent:false); })),
    ]))),
    const SizedBox(height:16),
    const Text('清除排更 - 按日期範圍 (保留記事)',style:TextStyle(fontSize:16,fontWeight:FontWeight.bold,color: Colors.red)),
    Card(color: const Color(0xFFFFEBEE), child: Padding(padding:const EdgeInsets.all(12), child: Column(children:[const Text('只清除班次，記事保留', style: TextStyle(fontSize:12)),const SizedBox(height:8),SizedBox(width: double.infinity, child: FilledButton.icon(icon:const Icon(Icons.delete_sweep), style: FilledButton.styleFrom(backgroundColor: Colors.red), label:const Text('按日期範圍清除'), onPressed: clearRosterByRange)),]))),
    const SizedBox(height:16), const Text('標準工時 & 承上 & 超時金額',style:TextStyle(fontSize:16,fontWeight:FontWeight.bold)),
    Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(children:[Row(children:[Expanded(child:TextField(controller:stdCtrl,decoration:const InputDecoration(labelText:'標準工時',suffixText:'h/週',border:OutlineInputBorder()))),const SizedBox(width:8),Expanded(child:TextField(controller:carryCtrl,decoration:const InputDecoration(labelText:'承上餘額',border:OutlineInputBorder())))]),const SizedBox(height:10), TextField(controller:otRateCtrl,decoration:const InputDecoration(labelText:'超時金額 /h',prefixText:'\$ ',border:OutlineInputBorder())),const SizedBox(height:10), SizedBox(width:double.infinity,child:FilledButton(onPressed:(){ double? v1=double.tryParse(stdCtrl.text); double? v2=double.tryParse(carryCtrl.text); double? v3=double.tryParse(otRateCtrl.text); if(v1!=null) standardWeeklyHours=v1; if(v2!=null) carry=v2; if(v3!=null) overtimeRate=v3; setState((){}); save(); },child:const Text('保存設定'))),]))),
    const SizedBox(height:16), const Text('日曆文字大小',style:TextStyle(fontSize:16,fontWeight:FontWeight.bold)),
    Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(children:[Row(children:[const Text('小'),Expanded(child:Slider(value:calendarFontSize,min:8,max:20,divisions:12,onChanged:(v){ setState(()=>calendarFontSize=v); })),const Text('大')]), FilledButton.tonal(onPressed:(){ save(); },child:const Text('保存文字大小'))]))),
    const SizedBox(height:16), const Text('額外津貼',style:TextStyle(fontSize:16,fontWeight:FontWeight.bold)),
    Card(child:Column(children:[...allowShow.asMap().entries.map((en){ int idx=showAllExtra? en.key : extraAllowances.indexOf(en.value); var e=en.value; return ListTile(title:Text(e.name),subtitle:Text('\$${e.amount}'),trailing:Row(mainAxisSize:MainAxisSize.min,children:[IconButton(icon:const Icon(Icons.edit,size:18),onPressed:(){ var nCtrl=TextEditingController(text:e.name); var vCtrl=TextEditingController(text:e.amount.toString()); showDialog(context:context,builder:(ctx)=>AlertDialog(title:const Text('編輯額外津貼'),content:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:nCtrl,decoration:const InputDecoration(labelText:'名稱')), TextField(controller:vCtrl,decoration:const InputDecoration(labelText:'金額'),keyboardType:TextInputType.number),]),actions:[FilledButton(onPressed:(){ String nn=nCtrl.text.trim(); double? vv=double.tryParse(vCtrl.text); if(nn.isEmpty||vv==null) return; setState(()=>extraAllowances[idx]=ExtraAllowance(nn,vv)); save(); Navigator.pop(ctx); },child:const Text('儲存'))])); }),IconButton(icon:const Icon(Icons.delete,size:18,color:Colors.red),onPressed:(){ setState(()=>extraAllowances.removeAt(idx)); save(); }),])); }),if(extraAllowances.length>5) TextButton(onPressed:(){ setState(()=>showAllExtra=!showAllExtra); },child:Text(showAllExtra?'收起':'顯示全部 ${extraAllowances.length}項')),ListTile(leading:const Icon(Icons.add),title:const Text('新增額外津貼'),onTap:(){ var nCtrl=TextEditingController(); var vCtrl=TextEditingController(text:'0'); showDialog(context:context,builder:(ctx)=>AlertDialog(title:const Text('新增額外津貼'),content:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:nCtrl,decoration:const InputDecoration(labelText:'名稱')), TextField(controller:vCtrl,decoration:const InputDecoration(labelText:'金額'),keyboardType:TextInputType.number),]),actions:[FilledButton(onPressed:(){ String name=nCtrl.text.trim(); double? val=double.tryParse(vCtrl.text); if(name.isEmpty||val==null) return; setState(()=>extraAllowances.add(ExtraAllowance(name,val))); save(); Navigator.pop(ctx); },child:const Text('新增'))])); }),])),
    const SizedBox(height:16), const Text('全部備份與還原',style:TextStyle(fontSize:16,fontWeight:FontWeight.bold)),
    Card(child:Padding(padding:const EdgeInsets.all(12),child:Row(children:[Expanded(child:OutlinedButton.icon(onPressed:backupAnywhere,icon:const Icon(Icons.backup),label:const Text('全部備份'))),const SizedBox(width:8),Expanded(child:OutlinedButton.icon(onPressed:restoreLocalFile,icon:const Icon(Icons.restore),label:const Text('全部還原')))]))),
  ]));
}
@override Widget build(BuildContext context){
  return Scaffold(body:[calTab(),patternTab(),reportTab(),settingsTab()][tab],bottomNavigationBar:NavigationBar(selectedIndex:tab,onDestinationSelected:(i)=>setState(()=>tab=i),destinations:const[NavigationDestination(icon:Icon(Icons.calendar_month),label:'月曆'),NavigationDestination(icon:Icon(Icons.pattern),label:'模式'),NavigationDestination(icon:Icon(Icons.bar_chart),label:'報表'),NavigationDestination(icon:Icon(Icons.settings),label:'設定'),]),);
}
}
