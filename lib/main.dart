import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:device_calendar/device_calendar.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzData;
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:home_widget/home_widget.dart';

void main() { tzData.initializeTimeZones(); WidgetsFlutterBinding.ensureInitialized(); HomeWidget.setAppGroupId('group.rosterPro'); runApp(const RosterApp()); }

class ShiftDef {
String code; String label; double hours; double ot; Color color; String start; String end; bool hasAllowance; double allowance; bool isAllDay;
ShiftDef(this.code,this.label,this.hours,this.color,{this.ot=0,this.start='07:00',this.end='15:30',this.hasAllowance=false,this.allowance=0,this.isAllDay=false});
Map<String,dynamic> toJson()=>{'code':code,'label':label,'hours':hours,'ot':ot,'color':color.value,'start':start,'end':end,'hasAllowance':hasAllowance,'allowance':allowance,'isAllDay':isAllDay};
factory ShiftDef.fromJson(Map<String,dynamic> j)=>ShiftDef(j['code'],j['label']??j['code'],(j['hours']??8).toDouble(),Color(j['color']??0xFFFF9800),ot:(j['ot']??0).toDouble(),start:j['start']??'07:00',end:j['end']??'15:30',hasAllowance:j['hasAllowance']??((j['allowance']??0)>0),allowance:(j['allowance']??0).toDouble(),isAllDay:j['isAllDay']??false);
String get detailTime=>isAllDay?'全天 ${start}-${end} ${hours.toStringAsFixed(1)}h':'${start}-${end} ${hours.toStringAsFixed(1)}h';
}
class ExtraAllowance { String name; double amount; ExtraAllowance(this.name,this.amount); Map<String,dynamic> toJson()=>{'name':name,'amount':amount}; factory ExtraAllowance.fromJson(Map<String,dynamic> j)=>ExtraAllowance(j['name'],(j['amount'] as num).toDouble()); }
class SavedPattern { String name; List<List<String>> data; SavedPattern(this.name,this.data); Map<String,dynamic> toJson()=>{'name':name,'data':data}; factory SavedPattern.fromJson(Map<String,dynamic> j)=>SavedPattern(j['name'], (j['data'] as List).map<List<String>>((r)=>(r as List).map<String>((e)=>e.toString()).toList()).toList()); }
class RosterApp extends StatelessWidget { const RosterApp({super.key}); @override Widget build(BuildContext context){ return MaterialApp(title:'Roster Pro v7.0',theme:ThemeData(useMaterial3:true,colorSchemeSeed:Colors.deepPurple),home:const MainPage()); } }

class MainPage extends StatefulWidget { const MainPage({super.key}); @override State<MainPage> createState()=>MainPageState(); }
class MainPageState extends State<MainPage> {
int tab=0; DateTime focused=DateTime.now(); DateTime selectedDay=DateTime.now();
Map<String,String> roster={}; Map<String,String> rosterNote={}; Map<String,String> rosterExtraType={}; Map<String,double> rosterOt={}; Map<String,double> rosterExtra={}; Map<String,double> rosterExtraHrs={};
Map<String,ShiftDef> defs={
'早':ShiftDef('早','早更',8,Colors.orange,start:'07:00',end:'15:30',hasAllowance:true,allowance:80),
'中':ShiftDef('中','中更',8,Colors.blue,start:'14:00',end:'22:00'),
'宵':ShiftDef('宵','宵更',8,Colors.purple,start:'22:00',end:'06:00',hasAllowance:true,allowance:60),
'O':ShiftDef('O','休',0,Colors.green,start:'00:00',end:'00:00',isAllDay:true),
};
List<List<String>> pattern=[["早","早","中","中","宵","宵","O"],["早","早","早","中","中","O","O"]];
List<List<String>> get _defaultPattern => [["早","早","中","中","宵","宵","O"],["早","早","早","中","中","O","O"]];
List<SavedPattern> savedPatterns=[]; double carry=0; String customName='我的排更-專屬日曆'; TextEditingController nameCtrl=TextEditingController();
double standardWeeklyHours=42; double overtimeRate=80; List<ExtraAllowance> extraAllowances=[]; double calendarFontSize=14;
bool googleSyncEnabled=false; bool autoSync=false; bool isYearReport=false; bool showAllShift=false; bool showAllExtra=false;
String? editingPatternName; int? editingPatternIndex; String holidayRegion='香港';
GlobalKey calKey=GlobalKey();
DeviceCalendarPlugin _calendarPlugin = DeviceCalendarPlugin();
static const _realChannel = MethodChannel('com.roster/calendar_real');
String? _rosterCalendarId; String _rosterCalendarName='未選'; String _rosterAccountName='';
Map<String,String> _googleEventIdMap={};

Future<void> updateWidget() async {
  try {
    String todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
    String tomorrowKey = DateFormat('yyyy-MM-dd').format(DateTime.now().add(const Duration(days: 1)));
    
    // 1. 保存基本今日/明日數據
    await HomeWidget.saveWidgetData('today_code', roster[todayKey] ?? 'O');
    await HomeWidget.saveWidgetData('tomorrow_code', roster[tomorrowKey] ?? 'O');
    await HomeWidget.saveWidgetData('note', rosterNote[todayKey] ?? '');
    await HomeWidget.saveWidgetData('extraType', rosterExtraType[todayKey] ?? '');
    await HomeWidget.saveWidgetData('today_bg', todayBgColor.value);
    await HomeWidget.saveWidgetData('today_border', todayBorderColor.value);

    // 2. 保存完整排更數據和班次定義 (關鍵！讓 Widget 能自己計算日曆)
    await HomeWidget.saveWidgetData('roster_json', jsonEncode(roster));
    await HomeWidget.saveWidgetData('defs_json', jsonEncode(defs.map((k, v) => MapEntry(k, v.toJson()))));
    
    // 3. 保存初始顯示的年月 (預設為當前月)
    DateTime now = DateTime.now();
    await HomeWidget.saveWidgetData('initial_year', now.year);
    await HomeWidget.saveWidgetData('initial_month', now.month);

    // 4. 觸發 Widget 更新
    await HomeWidget.updateWidget(androidName: 'RosterWidgetProvider');
  } catch (e) {
    print("Widget update error: $e");
  }
}

bool _isSyncing=false;
String _lastBackupPath='未備份'; Color todayBgColor=const Color(0xFFFFF9C4); Color todayBorderColor=Colors.orange; Color holidayDotColor=Colors.red;

Map<String,String> getHolidays(int year, String region){
Map<String,String> m={};
if(region=='無') return m;
if(region=='香港'){
m['${year}-01-01']='元旦';
m['${year}-05-01']='勞動節';
m['${year}-07-01']='回歸';
m['${year}-10-01']='國慶';
m['${year}-12-25']='聖誕';
if(year==2024){ m.addAll({'2024-02-10':'初一','2024-02-11':'初二','2024-02-12':'初三','2024-04-04':'清明','2024-05-15':'佛誕','2024-06-10':'端午','2024-09-18':'中秋翌日','2024-10-11':'重陽','2024-12-26':'聖誕後'}); }
else if(year==2025){ m.addAll({'2025-01-29':'初一','2025-01-30':'初二','2025-01-31':'初三','2025-04-04':'清明','2025-05-05':'佛誕','2025-05-31':'端午','2025-10-07':'中秋翌日','2025-10-29':'重陽'}); }
else if(year==2026){ m.addAll({'2026-02-17':'初一','2026-02-18':'初二','2026-02-19':'初三','2026-04-05':'清明','2026-05-24':'佛誕','2026-06-19':'端午','2026-09-26':'中秋翌日','2026-10-18':'重陽'}); }
else if(year==2027){ m.addAll({'2027-02-06':'初一','2027-02-07':'初二','2027-02-08':'初三','2027-04-05':'清明','2027-05-13':'佛誕','2027-06-09':'端午','2027-09-16':'中秋翌日','2027-10-08':'重陽'}); }
else if(year==2028){ m.addAll({'2028-01-26':'初一','2028-01-27':'初二','2028-01-28':'初三','2028-04-04':'清明','2028-05-01':'佛誕','2028-05-27':'端午','2028-10-04':'中秋翌日','2028-10-26':'重陽'}); }
else if(year==2029){ m.addAll({'2029-02-13':'初一','2029-02-14':'初二','2029-02-15':'初三','2029-04-05':'清明','2029-05-20':'佛誕','2029-06-16':'端午','2029-09-23':'中秋翌日','2029-10-15':'重陽'}); }
else if(year==2030){ m.addAll({'2030-02-03':'初一','2030-02-04':'初二','2030-02-05':'初三','2030-04-05':'清明','2030-05-09':'佛誕','2030-06-05':'端午','2030-09-12':'中秋翌日','2030-10-04':'重陽'}); }
else if(year>=2031){ m.addAll({'${year}-02-10':'春節','${year}-04-05':'清明','${year}-05-15':'佛誕','${year}-06-10':'端午','${year}-09-18':'中秋','${year}-10-11':'重陽'}); }
}
if(region=='中國內地'){ m['${year}-01-01']='元旦'; m['${year}-05-01']='勞動節'; m['${year}-10-01']='國慶'; }
if(region=='台灣'){ m['${year}-01-01']='元旦'; m['${year}-02-28']='和平紀念'; m['${year}-10-10']='國慶'; }
if(region=='美國'){ m['${year}-01-01']='New Year'; m['${year}-07-04']='Independence'; m['${year}-11-11']='Veterans'; m['${year}-12-25']='Christmas'; }
return m;
}
bool isHoliday(DateTime d){ var map=getHolidays(d.year, holidayRegion); return map.containsKey(DateFormat('yyyy-MM-dd').format(d)); }
String holidayName(DateTime d){ var map=getHolidays(d.year, holidayRegion); return map[DateFormat('yyyy-MM-dd').format(d)]??''; }

@override void initState(){ super.initState(); nameCtrl.text=customName; load().then((_) async { await Future.delayed(const Duration(milliseconds:500)); bool ok = await handleCalendarPermission(silent:false); if(!ok && mounted){ ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('需要日曆權限才能讀取日曆，請在設定中允許'))); } }); }
Future<void> load() async{
var sp=await SharedPreferences.getInstance();
var r=sp.getString('roster'); if(r!=null) roster=Map<String,String>.from(jsonDecode(r));
var rn=sp.getString('note'); if(rn!=null) rosterNote=Map<String,String>.from(jsonDecode(rn));
var rt=sp.getString('extraType'); if(rt!=null) rosterExtraType=Map<String,String>.from(jsonDecode(rt));
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
_rosterCalendarName=sp.getString('rosterCalName')??'未選'; _rosterAccountName=sp.getString('rosterAccName')??'';
_lastBackupPath=sp.getString('lastBackupPath')??'未備份';
todayBgColor=Color(sp.getInt('todayBg')??0xFFFFF9C4); todayBorderColor=Color(sp.getInt('todayBorder')??0xFFFF9800);
});
updateWidget();
}
Future<void> save() async{
var sp=await SharedPreferences.getInstance();
sp.setString('roster',jsonEncode(roster)); sp.setString('note',jsonEncode(rosterNote)); sp.setString('extraType',jsonEncode(rosterExtraType)); sp.setString('roOt',jsonEncode(rosterOt));
sp.setString('roEx',jsonEncode(rosterExtra)); sp.setString('roExH',jsonEncode(rosterExtraHrs));
sp.setString('defs',jsonEncode(defs.map((k,v)=>MapEntry(k,v.toJson())))); sp.setString('pattern',jsonEncode(pattern));
sp.setDouble('carry',carry); sp.setString('cName',customName); sp.setDouble('stdWeek',standardWeeklyHours);
sp.setDouble('otRate',overtimeRate); sp.setString('extraAllowNewV36',jsonEncode(extraAllowances.map((e)=>e.toJson()).toList()));
sp.setDouble('calFont',calendarFontSize); sp.setBool('gSync',googleSyncEnabled); sp.setBool('gAuto',autoSync);
sp.setString('savedPatternsV40',jsonEncode(savedPatterns.map((e)=>e.toJson()).toList())); sp.setString('holidayRegion', holidayRegion);
sp.setString('googleEventIdMap', jsonEncode(_googleEventIdMap));
if(_rosterCalendarId!=null) sp.setString('rosterCalId', _rosterCalendarId!);
sp.setString('rosterCalName', _rosterCalendarName); sp.setString('rosterAccName', _rosterAccountName);
sp.setString('lastBackupPath', _lastBackupPath); sp.setInt('todayBg', todayBgColor.value); sp.setInt('todayBorder', todayBorderColor.value);
updateWidget();
if(autoSync && googleSyncEnabled &&!_isSyncing){ _syncToGoogle(silent:true); }
}
int isoWeek(DateTime date){ DateTime thursday=date.add(Duration(days:4-date.weekday)); DateTime jan1=DateTime(thursday.year,1,1); int days=thursday.difference(jan1).inDays; return 1+(days/7).floor(); }
void quickJumpMonth({bool forReport=false}){ int y=focused.year; int m=focused.month; showDialog(context:context,builder:(ctx){ return StatefulBuilder(builder:(ctx2,setD){ return AlertDialog(title:Text(forReport?'選擇報表年月':'快速查找年月'),content:Column(mainAxisSize:MainAxisSize.min,children:[Row(children:[IconButton(icon:const Icon(Icons.remove),onPressed:()=>setD(()=>y--)),Expanded(child:Text('${y}年',textAlign:TextAlign.center,style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold))),IconButton(icon:const Icon(Icons.add),onPressed:()=>setD(()=>y++))]),Wrap(spacing:8,children:List.generate(12,(i){ int mon=i+1; return ChoiceChip(label:Text('${mon}月'),selected:mon==m,onSelected:(_)=>setD(()=>m=mon)); }))]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx2),child:const Text('取消')),FilledButton(onPressed:(){ setState(()=>focused=DateTime(y,m,1)); Navigator.pop(ctx2); },child:const Text('跳轉'))]); }); }); }
Future<bool> handleCalendarPermission({bool silent=false}) async {
try{
var s1 = await Permission.calendar.request();
var s2 = await Permission.calendarFullAccess.request();
var s3 = await Permission.calendarWriteOnly.request();
if(s1.isGranted || s2.isGranted || s3.isGranted) return true;
if(!silent && s1.isPermanentlyDenied){
await showDialog(context:context, builder:(ctx)=>AlertDialog(title:const Text('需要日曆權限'), content:const Text('新安裝App需允許存取日曆才能讀取，否則顯示空白(0)。請去設定>權限>允許日曆'), actions:[TextButton(onPressed:()=>Navigator.pop(ctx), child:const Text('取消')), FilledButton(onPressed:(){ openAppSettings(); Navigator.pop(ctx); }, child:const Text('去設定'))]));
}
}catch(_){}
try{
var devHas = await _calendarPlugin.hasPermissions();
if (devHas.isSuccess && devHas.data==true) return true;
var devReq = await _calendarPlugin.requestPermissions();
if(devReq.isSuccess && devReq.data==true) return true;
}catch(_){}
return false;
}
Future<List<Map<String,dynamic>>> _getRealCalendars() async {
try {
var res = await _realChannel.invokeMethod('getCalendars');
return (res as List).map((e)=>Map<String,dynamic>.from(e as Map)).toList();
} catch(e){
try{
var r = await _calendarPlugin.retrieveCalendars();
return (r.data??[]).map((c)=>{'id':c.id,'displayName':c.name,'accountName':c.accountName,'isGoogle':(c.accountName??'').contains('gmail')||(c.accountType??'').contains('google')}).toList();
}catch(_){ return []; }
}
}
Future<String?> _pickGoogleCalendarDialog() async {
bool ok = await handleCalendarPermission(silent:false);
if(!ok){ if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('未取得日曆權限，無法讀取日曆'))); return null; }
var cals = await _getRealCalendars();
if(cals.isEmpty){
if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('未讀取到任何日曆，請檢查權限或新增Google帳號')));
return null;
}
var googleCals = cals.where((c)=>c['isGoogle']==true).toList();
var otherCals = cals.where((c)=>c['isGoogle']!=true).toList();
var pickedMap = await showDialog<Map<String,dynamic>>(context: context, builder: (ctx){
return AlertDialog(
title: Text('選擇寫入日曆 真ID版 (${cals.length}) 日曆權限已恢復'), content: SizedBox(width: 460, height: 560, child: ListView(children:[
Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.green.withOpacity(0.12), borderRadius: BorderRadius.circular(8)), child: const Text('綠色=Google帳號 會上 calendar.google.com 灰色=本機日曆 已恢復存取所有日曆權限', style: TextStyle(fontSize:11, fontWeight: FontWeight.bold, color: Colors.green))),
const SizedBox(height:8),
Text('Google 日曆 (${googleCals.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
...googleCals.map((cal)=>Card(color: Colors.green.withOpacity(0.15), child: ListTile(leading: const Icon(Icons.cloud_done, color: Colors.green),title: Text('${cal['displayName']}', style: const TextStyle(fontSize:13, fontWeight: FontWeight.bold)),subtitle: Text('帳號: ${cal['accountName']}\nID: ${cal['id']}', style: const TextStyle(fontSize:9)),onTap: ()=>Navigator.pop(ctx, cal),))),
const Divider(),
Text('其他日曆 (${otherCals.length})'),
...otherCals.map((cal)=>Card(child: ListTile(leading: const Icon(Icons.phone_android),title: Text('${cal['displayName']}', style: const TextStyle(fontSize:13)),subtitle: Text('${cal['accountName']}', style: const TextStyle(fontSize:9)),onTap: ()=>Navigator.pop(ctx, cal),))),
])),
actions: [TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('取消'))],
);
});
if(pickedMap!=null && pickedMap['id']!=null){
_rosterCalendarId = pickedMap['id'].toString(); _rosterCalendarName = pickedMap['displayName'].toString(); _rosterAccountName = pickedMap['accountName'].toString();
var sp=await SharedPreferences.getInstance(); sp.setString('rosterCalId', _rosterCalendarId!); sp.setString('rosterCalName', _rosterCalendarName); sp.setString('rosterAccName', _rosterAccountName);
setState((){}); if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('已選 $_rosterCalendarId')));
return _rosterCalendarId;
}
return null;
}
Future<void> _requestGooglePerm() async{
String? id = await _pickGoogleCalendarDialog(); if(id==null) return;
bool? ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('已選擇真 Google 日曆'),content:Text('將寫入：$_rosterCalendarName\nID: $id\n已開啟記事同步'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('稍後')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('立即同步'))]));
if(ok==true){ setState(()=>googleSyncEnabled=true); await _syncToGoogle(); save(); }
}
Future<void> _ensureCalendar() async{ if(_rosterCalendarId!=null && _rosterCalendarId!.isNotEmpty) return; await _pickGoogleCalendarDialog(); }

Future<void> _syncToGoogle({bool silent=false}) async{
if(!googleSyncEnabled &&!silent){
bool? en = await showDialog<bool>(context: context, builder: (ctx)=>AlertDialog(title:const Text('未開啟同步'), content:const Text('是否開啟同步並立即寫入？'), actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false), child:const Text('取消')), FilledButton(onPressed:()=>Navigator.pop(ctx,true), child:const Text('開啟並同步'))]));
if(en==true) setState(()=>googleSyncEnabled=true); else return;
}
if(_isSyncing) return; _isSyncing=true;
if(!silent) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('開始同步，只同步班次代號+時間+記事...')));
try{
if(_rosterCalendarId==null || _rosterCalendarId!.isEmpty) await _ensureCalendar();
if(_rosterCalendarId==null || _rosterCalendarId!.isEmpty) throw '未選真 Google 日曆';

// ===== 去重：先刪除所有舊 [RosterPro] 事件（按描述 + 按已存ID 雙重保險）=====
var existingEvents=await _calendarPlugin.retrieveEvents(_rosterCalendarId!, RetrieveEventsParams(startDate: DateTime(2023,1,1), endDate: DateTime(2035,12,31)));
Set<String> toDelete = {};
for(var e in existingEvents.data??[]){
if((e.description??'').contains('[RosterPro]') && e.eventId!=null){
toDelete.add(e.eventId!);
}
}
for(var eid in _googleEventIdMap.values){
toDelete.add(eid);
}
int del=0;
for(var eid in toDelete){
try{ await _calendarPlugin.deleteEvent(_rosterCalendarId!, eid); del++; }catch(_){}
}
await Future.delayed(const Duration(milliseconds:400));
_googleEventIdMap.clear();
// ===== 去重完畢 =====

int add=0;
for(var entry in roster.entries){
var code=entry.value; var def=defs[code]; if(def==null) continue;
DateTime date=DateFormat('yyyy-MM-dd').parse(entry.key);
String note = rosterNote[entry.key]??'';
String tag='[RosterPro]${entry.key}';
bool allDayFlag = def.isAllDay || def.code=='O';

// ===== 只同步：班次代號、開始/結束時間、記事 =====
String desc;
String title;
if(allDayFlag){
// 全天班次：不顯示開始/結束時間
desc = '$tag\n$customName\n班次: ${def.code} ${def.label}\n類型: 全天${note.isNotEmpty?'\n記事: $note':''}';
title = '${def.code}${note.isNotEmpty?' | $note':''}';
} else {
desc = '$tag\n$customName\n班次: ${def.code} ${def.label}\n時間: ${def.start}-${def.end}${note.isNotEmpty?'\n記事: $note':''}';
title = '${def.code} ${def.start}-${def.end}${note.isNotEmpty?' | $note':''}';
}
// ============================================

Event ev;
if(allDayFlag){
ev=Event(_rosterCalendarId!, title:title, description:desc, start:tz.TZDateTime(tz.local,date.year,date.month,date.day), end:tz.TZDateTime(tz.local,date.year,date.month,date.day+1), allDay:true);
}else{
DateTime s=DateTime(date.year,date.month,date.day,int.parse(def.start.split(':')[0]),int.parse(def.start.split(':')[1]));
DateTime ee=DateTime(date.year,date.month,date.day,int.parse(def.end.split(':')[0]),int.parse(def.end.split(':')[1]));
if(ee.isBefore(s)) ee=ee.add(const Duration(days:1));
ev=Event(_rosterCalendarId!, title:title, description:desc, start:tz.TZDateTime.from(s,tz.local), end:tz.TZDateTime.from(ee,tz.local), allDay:false);
}
var res=await _calendarPlugin.createOrUpdateEvent(ev); if(res!=null && res.isSuccess && res.data!=null){ _googleEventIdMap[entry.key]=res.data!; add++; }
}
var sp=await SharedPreferences.getInstance(); sp.setString('googleEventIdMap',jsonEncode(_googleEventIdMap));
updateWidget();
if(!silent && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('已寫入 $_rosterCalendarName 刪$del 加$add 項，已去重（只同步代號+時間+記事）')));
}catch(e){ if(!silent && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('同步失敗 $e'))); }
finally { _isSyncing=false; }
}

Future<void> clearRosterByRange() async{
DateTimeRange? range=await showDateRangePicker(context:context, firstDate: DateTime(2023), lastDate: DateTime(2035), helpText: '選擇要清除的排更範圍');
if(range==null) return; int count=0;
for(DateTime d=range.start;!d.isAfter(range.end); d=d.add(const Duration(days:1))){
String k=DateFormat('yyyy-MM-dd').format(d);
if(roster.containsKey(k)){ count++; roster.remove(k); rosterOt.remove(k); rosterExtra.remove(k); rosterExtraHrs.remove(k); rosterExtraType.remove(k); if(_googleEventIdMap.containsKey(k) && _rosterCalendarId!=null){ try{ await _calendarPlugin.deleteEvent(_rosterCalendarId!, _googleEventIdMap[k]); }catch(_){} _googleEventIdMap.remove(k); } }
}
await save(); setState((){}); if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('已清除 $count 天排更，記事保留')));
}

Future<void> shareScreenshotDialog() async{ exportShareImage(); }
Future<void> exportShareImage() async{
try{
RenderRepaintBoundary? b=calKey.currentContext?.findRenderObject() as RenderRepaintBoundary?; ui.Image? calImg; if(b!=null){ calImg=await b.toImage(pixelRatio:3); }
final recorder=ui.PictureRecorder(); final canvas=Canvas(recorder); double width=1080; double y=0; final paintWhite=Paint()..color=Colors.white;
double calHeight = calImg!=null? width * calImg.height / calImg.width : 0;
Set<String> usedCodes={}; int dim=DateTime(focused.year,focused.month+1,0).day; for(int i=1;i<=dim;i++){ String k=DateFormat('yyyy-MM-dd').format(DateTime(focused.year,focused.month,i)); if(roster[k]!=null) usedCodes.add(roster[k]!); }
List<ShiftDef> legendDefs = defs.entries.where((e)=>usedCodes.contains(e.key)).map((e)=>e.value).toList();
double legendHeight = legendDefs.length*44 + 80; double totalHeight = calHeight + legendHeight + 40;
canvas.drawRect(Rect.fromLTWH(0,0,width,totalHeight), paintWhite);
if(calImg!=null){ canvas.drawImageRect(calImg, Rect.fromLTWH(0,0,calImg.width.toDouble(),calImg.height.toDouble()), Rect.fromLTWH(0,0,width,calHeight), Paint()); y=calHeight+16; }
TextPainter tp=TextPainter(textDirection: ui.TextDirection.ltr);
tp.text=TextSpan(text:'班次詳細時間圖例 (本月使用)：',style: TextStyle(color:Colors.black,fontSize:32,fontWeight:FontWeight.bold)); tp.layout(maxWidth:width); tp.paint(canvas, Offset(24,y)); y+=54;
for(var v in legendDefs){
canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(24,y,32,32), const Radius.circular(8)), Paint()..color=v.color);
tp.text=TextSpan(text:' ${v.code} ${v.label} ${v.isAllDay?'全天':'${v.start}-${v.end}'} ${v.hours.toStringAsFixed(1)}h${v.hasAllowance?' 津貼\$${v.allowance}':''}',style: const TextStyle(color:Colors.black87,fontSize:28,fontWeight:FontWeight.w600)); tp.layout(maxWidth:width-80); tp.paint(canvas, Offset(64,y)); y+=46;
}
final pic=recorder.endRecording(); final img=await pic.toImage(width.toInt(), (y+20).toInt()); final byte=await img.toByteData(format: ui.ImageByteFormat.png); final png=byte!.buffer.asUint8List();
Directory baseDir=Directory('/storage/emulated/0/Pictures/Roster'); if(!await baseDir.exists()){ await baseDir.create(recursive:true); }
String path='${baseDir.path}/roster_month_${focused.year}${focused.month}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.png';
File f=File(path); await f.writeAsBytes(png);
if(mounted){
ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('截圖已保存 $path')));
await Share.shareXFiles([XFile(path)],text:'${focused.year}年${focused.month}月 $customName');
}
}catch(e){ if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('截圖失敗 $e'))); }
}
Future<void> backupAnywhere() async{
String? dir=await FilePicker.platform.getDirectoryPath(dialogTitle:'選擇備份位置'); if(dir==null) return;
String fileName='roster_pro_full_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.json';
var backup = {'version':'7.1','exportTime':DateTime.now().toIso8601String(),'roster':roster,'note':rosterNote,'extraType':rosterExtraType,'roOt':rosterOt,'roEx':rosterExtra,'roExH':rosterExtraHrs,'defs':defs.map((k,v)=>MapEntry(k,v.toJson())),'pattern':pattern,'carry':carry,'cName':customName,'stdWeek':standardWeeklyHours,'otRate':overtimeRate,'extraNewV36':extraAllowances.map((e)=>e.toJson()).toList(),'calFont':calendarFontSize,'savedPatterns':savedPatterns.map((e)=>e.toJson()).toList(),'holidayRegion':holidayRegion,'rosterCalId':_rosterCalendarId,'rosterCalName':_rosterCalendarName,'rosterAccName':_rosterAccountName,'googleEventIdMap':_googleEventIdMap,'gSync':googleSyncEnabled,'gAuto':autoSync,'todayBg':todayBgColor.value,'todayBorder':todayBorderColor.value};
var f=File('$dir/$fileName'); await f.writeAsString(jsonEncode(backup));
setState(()=>_lastBackupPath='$dir/$fileName'); await save();
if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('全部備份 $_lastBackupPath')));
}
Future<void> restoreLocalFile() async{
var res=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['json']); if(res==null) return;
try{ String c=await File(res.files.single.path!).readAsString(); var j=jsonDecode(c);
setState((){
if(j['roster']!=null) roster=Map<String,String>.from(j['roster']);
if(j['note']!=null) rosterNote=Map<String,String>.from(j['note']);
if(j['extraType']!=null) rosterExtraType=Map<String,String>.from(j['extraType']);
if(j['roOt']!=null) rosterOt=Map<String,double>.from((j['roOt'] as Map).map((k,v)=>MapEntry(k as String,(v as num).toDouble())));
if(j['roEx']!=null) rosterExtra=Map<String,double>.from((j['roEx'] as Map).map((k,v)=>MapEntry(k as String,(v as num).toDouble())));
if(j['roExH']!=null) rosterExtraHrs=Map<String,double>.from((j['roExH'] as Map).map((k,v)=>MapEntry(k as String,(v as num).toDouble())));
if(j['defs']!=null) defs=(j['defs'] as Map).map<String,ShiftDef>((k,v)=>MapEntry(k as String,ShiftDef.fromJson(Map<String,dynamic>.from(v as Map))));
if(j['pattern']!=null) pattern=(j['pattern'] as List).map<List<String>>((r)=>(r as List).map<String>((e)=>e.toString()).toList()).toList();
if(j['carry']!=null) carry=(j['carry'] as num).toDouble();
if(j['cName']!=null){ customName=j['cName']; nameCtrl.text=customName; }
if(j['stdWeek']!=null) standardWeeklyHours=(j['stdWeek'] as num).toDouble();
if(j['otRate']!=null) overtimeRate=(j['otRate'] as num).toDouble();
if(j['extraNewV36']!=null) extraAllowances=(j['extraNewV36'] as List).map((e)=>ExtraAllowance.fromJson(Map<String,dynamic>.from(e as Map))).toList();
if(j['calFont']!=null) calendarFontSize=(j['calFont'] as num).toDouble();
if(j['savedPatterns']!=null) savedPatterns=(j['savedPatterns'] as List).map((e)=>SavedPattern.fromJson(Map<String,dynamic>.from(e as Map))).toList();
if(j['holidayRegion']!=null) holidayRegion=j['holidayRegion'];
if(j['rosterCalId']!=null) _rosterCalendarId=j['rosterCalId'];
if(j['rosterCalName']!=null) _rosterCalendarName=j['rosterCalName'];
if(j['rosterAccName']!=null) _rosterAccountName=j['rosterAccName'];
if(j['googleEventIdMap']!=null) _googleEventIdMap=Map<String,String>.from(j['googleEventIdMap']);
if(j['gSync']!=null) googleSyncEnabled=j['gSync'];
if(j['gAuto']!=null) autoSync=j['gAuto'];
if(j['todayBg']!=null) todayBgColor=Color(j['todayBg']);
if(j['todayBorder']!=null) todayBorderColor=Color(j['todayBorder']);
}); save(); if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('還原成功'))); }catch(e){ if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('還原失敗 $e'))); }
}
Future<void> exportReport() async{
StringBuffer sb=StringBuffer();
if(!isYearReport){
int dim=DateTime(focused.year,focused.month+1,0).day; double hrs=0,ot=0; double allow=0; Map<String,int> shiftCount={}; Map<String,double> extraByType={};
for(int i=1;i<=dim;i++){ DateTime dt=DateTime(focused.year,focused.month,i); String k=DateFormat('yyyy-MM-dd').format(dt); String? c=roster[k]; if(c==null) continue; var d=defs[c]; if(d!=null){ hrs+=d.hours; shiftCount[c]=(shiftCount[c]??0)+1; if(d.hasAllowance) allow+=d.allowance; } ot+=(rosterOt[k]??d?.ot??0); allow+=(rosterExtra[k]??0); if(rosterExtraType.containsKey(k) && rosterExtra.containsKey(k)){ extraByType[rosterExtraType[k]!]=(extraByType[rosterExtraType[k]!]??0)+rosterExtra[k]!; } hrs+=(rosterExtraHrs[k]??0); }
sb.writeln('${focused.year}年${focused.month}月 報表'); shiftCount.forEach((k,v)=>sb.writeln('$k $v次')); extraByType.forEach((t,a)=>sb.writeln('津貼類別 $t : $a')); sb.writeln('總工時 $hrs OT $ot 津貼 ${allow+ot*overtimeRate}');
}else{
sb.writeln('${focused.year}年 全年統計'); for(int mon=1;mon<=12;mon++){ int dim=DateTime(focused.year,mon+1,0).day; double hrs=0; for(int d=1;d<=dim;d++){ DateTime dt=DateTime(focused.year,mon,d); String k=DateFormat('yyyy-MM-dd').format(dt); String? c=roster[k]; if(c==null) continue; var def=defs[c]; if(def!=null) hrs+=def.hours; } sb.writeln('$mon月 ${hrs}h'); }
}
String? path=await FilePicker.platform.saveFile(dialogTitle:'匯出報表',fileName:'report_${isYearReport?'year${focused.year}':'${focused.year}${focused.month}'}.csv',type:FileType.custom,allowedExtensions:['csv','txt']);
if(path!=null){ await File(path).writeAsString(sb.toString()); if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('已匯出 $path'))); }
}

Widget calTab(){
DateTime first=DateTime(focused.year,focused.month,1);
DateTime start=first.subtract(Duration(days:first.weekday-1));
int daysInMonth=DateTime(focused.year,focused.month+1,0).day;
int neededCells=first.weekday-1+daysInMonth;
int weeks=(neededCells/7).ceil();
if(weeks<5) weeks=5;
if(weeks>6) weeks=6;
List<DateTime> days=List.generate(weeks*7,(i)=>start.add(Duration(days:i)));
String selKey=DateFormat('yyyy-MM-dd').format(selectedDay);
var selDef=roster[selKey]!=null?defs[roster[selKey]]:null;
double selOt=rosterOt[selKey]??selDef?.ot??0;
String note=rosterNote[selKey]??'無';
String extraType=rosterExtraType[selKey]??'';
DateTime today=DateTime.now();
return SafeArea(
child: Column(
children:[
Padding(padding:const EdgeInsets.fromLTRB(12,8,12,4),child:Row(children:[InkWell(onTap:()=>quickJumpMonth(),child:Row(children:[Text('${focused.year}年${focused.month}月',style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const Icon(Icons.arrow_drop_down)])),const Spacer(),IconButton(icon:const Icon(Icons.camera_alt_outlined),tooltip:'整月截圖分享',onPressed:shareScreenshotDialog),IconButton(icon:const Icon(Icons.chevron_left),onPressed:(){ setState(()=>focused=DateTime(focused.year,focused.month-1,1)); }),IconButton(icon:const Icon(Icons.chevron_right),onPressed:(){ setState(()=>focused=DateTime(focused.year,focused.month+1,1)); }),FilledButton.tonal(onPressed:(){ setState((){ focused=DateTime(today.year,today.month,1); selectedDay=DateTime(today.year,today.month,today.day); }); },child:const Text('今天')),])),
Expanded(
child: RepaintBoundary(
key: calKey,
child: Column(
children:[
Padding(padding:const EdgeInsets.symmetric(horizontal:6),child:Row(children:[Container(width:32,child:const Text('週',textAlign:TextAlign.center,style:TextStyle(fontWeight:FontWeight.bold,fontSize:11,color:Colors.deepPurple))),Expanded(child:Row(children:["一","二","三","四","五","六","日"].map((w)=>Expanded(child:Text(w,textAlign:TextAlign.center,style:const TextStyle(fontSize:11)))).toList()))])),
Expanded(
child: ListView.builder(
shrinkWrap:true,
physics:const NeverScrollableScrollPhysics(),
padding:EdgeInsets.zero,
itemCount:weeks,
itemBuilder:(ctx,row){
return Row(
children:[
Container(width:32,alignment:Alignment.center,child:Text('W${isoWeek(days[row*7])}',style:const TextStyle(fontSize:11,color:Colors.deepPurple,fontWeight:FontWeight.bold))),
Expanded(
child: GridView.builder(
shrinkWrap:true,
physics:const NeverScrollableScrollPhysics(),
padding:const EdgeInsets.all(3),
gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:7,childAspectRatio:0.78,mainAxisSpacing:4,crossAxisSpacing:4),
itemCount:7,
itemBuilder:(ctx2,col){
int idx=row*7+col;
DateTime day=days[idx];
bool inM=day.month==focused.month;
String k=DateFormat('yyyy-MM-dd').format(day);
String? code=roster[k];
var def=code!=null?defs[code]:null;
bool sel=k==selKey;
bool isToday = day.year==today.year && day.month==today.month && day.day==today.day;
bool hasNote = rosterNote.containsKey(k) && rosterNote[k]!.isNotEmpty;
bool isHol = isHoliday(day);
Color bg;
if(isToday){ bg=todayBgColor; } else if(!inM){ bg=const Color(0xFFF5F5F0); } else if(sel){ bg=Colors.white; } else if(def!=null){ bg=def.color.withOpacity(0.18); } else { bg=const Color(0xFFFFF0D0); }
return GestureDetector(
onTap:(){ setState(()=>selectedDay=day); },
onLongPress:(){ setState(()=>selectedDay=day); showDetail(day); },
child:Container(
decoration:BoxDecoration(color:bg,borderRadius:BorderRadius.circular(12),border:isToday?Border.all(width:2.8,color:todayBorderColor):sel?Border.all(width:2,color:Colors.deepPurple):null),
child:Column(
mainAxisAlignment:MainAxisAlignment.center,
children:[
Text('${day.day}',style:TextStyle(fontWeight:isToday?FontWeight.w900:FontWeight.bold,fontSize:calendarFontSize-1,color:inM?Colors.black:Colors.grey)),
if(code!=null) FittedBox(child:Container(margin:const EdgeInsets.only(top:1),padding:const EdgeInsets.symmetric(horizontal:4,vertical:1),decoration:BoxDecoration(color:def?.color??Colors.orange,borderRadius:BorderRadius.circular(8)),child:Text(code,style:TextStyle(color:Colors.white,fontSize:calendarFontSize-2)))),
const SizedBox(height:2),
Row(mainAxisAlignment:MainAxisAlignment.center,children:[if(isHol) Container(width:6,height:6,margin:const EdgeInsets.symmetric(horizontal:1),decoration:BoxDecoration(color:holidayDotColor,shape:BoxShape.circle)),if(hasNote) Container(width:6,height:6,margin:const EdgeInsets.symmetric(horizontal:1),decoration:const BoxDecoration(color:Colors.blue,shape:BoxShape.circle)),]),
]
)
)
);
}
)
)
]
);
}
)
)
]
)
)
),
Container(width:double.infinity,padding:const EdgeInsets.fromLTRB(12,12,12,16),decoration:const BoxDecoration(color:Colors.white,border:Border(top:BorderSide(color:Color(0xFFE0E0E0)))),child:Column(
crossAxisAlignment:CrossAxisAlignment.start,
children:[
Row(children:[
Expanded(child:Text('${roster[selKey]??'未排班'}${isHoliday(selectedDay)?' [${holidayName(selectedDay)}]':''} ${extraType.isNotEmpty?'[$extraType]':''}',style:const TextStyle(fontSize:16,fontWeight:FontWeight.bold),overflow:TextOverflow.ellipsis)),
const SizedBox(width:8),
if(selDef!=null) Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:3),decoration:BoxDecoration(color:selDef.color,borderRadius:BorderRadius.circular(10)),child:Text(selDef.code,style:const TextStyle(color:Colors.white,fontSize:11,fontWeight:FontWeight.bold))),
const SizedBox(width:8),
FilledButton.tonalIcon(onPressed:(){ showDetail(selectedDay); },icon:const Icon(Icons.edit,size:16),label:const Text('編輯',style:TextStyle(fontSize:12)),style: FilledButton.styleFrom(minimumSize:const Size(0,36),padding:const EdgeInsets.symmetric(horizontal:12))),
]),
const SizedBox(height:10),
Container(width:double.infinity,padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:const Color(0xFFF5F5F5),borderRadius:BorderRadius.circular(12)),child:Column(
crossAxisAlignment:CrossAxisAlignment.start,
children:[
Text('1. 班次：${selDef!=null?'(${selDef.code}) ${selDef.label}':''} ${isHoliday(selectedDay)?'[${holidayName(selectedDay)}]':''}',style:const TextStyle(fontSize:13,fontWeight:FontWeight.bold)),
const SizedBox(height:4),
Text('2. 時間：${selDef!=null?(selDef.isAllDay?'全天':'${selDef.start}-${selDef.end}'):''} | 工時：${selDef?.hours??0}h',style:const TextStyle(fontSize:12)),
const SizedBox(height:4),
Text('3. 班次津貼：${selDef!=null && selDef.hasAllowance?'有 \$${selDef.allowance}':'無'}',style:const TextStyle(fontSize:12)),
const SizedBox(height:4),
Text('4. 額外津貼名稱：${extraType.isNotEmpty?extraType:'無'}  金額：\$${(rosterExtra[selKey]??0).toStringAsFixed(1)}',style:const TextStyle(fontSize:12,color:Colors.deepPurple,fontWeight:FontWeight.w600)),
const SizedBox(height:4),
Text('5. OT：${(rosterOt[selKey]??0).toStringAsFixed(1)}h | 額外工時：${(rosterExtraHrs[selKey]??0).toStringAsFixed(1)}h',style:const TextStyle(fontSize:12)),
const SizedBox(height:4),
Text('6. 記事：${note.isEmpty?'無':note}',style:const TextStyle(fontSize:12,fontWeight:FontWeight.bold,color: Colors.deepPurple),maxLines:6,overflow:TextOverflow.ellipsis),
if(extraAllowances.isNotEmpty)...[
const SizedBox(height:4),
Text('7. 已登記額外津貼清單：${extraAllowances.map((e)=>'${e.name} \$${e.amount}').join('、')}',style:const TextStyle(fontSize:11,color:Colors.black54)),
],
]
)
),
]
)
),
]
)
);
}

void showDetail(DateTime day){
String k=DateFormat('yyyy-MM-dd').format(day); String cur=roster[k]??''; var nc=TextEditingController(text:rosterNote[k]??''); var otc=TextEditingController(text:(rosterOt[k]??0).toString()); var exCtrl=TextEditingController(text:(rosterExtra[k]??0).toString()); var exHCtrl=TextEditingController(text:(rosterExtraHrs[k]??0).toString()); var exTypeCtrl=TextEditingController(text:rosterExtraType[k]??'');
showModalBottomSheet(context:context,isScrollControlled:true,builder:(ctx){ return StatefulBuilder(builder:(ctx2,setM){ return Padding(padding:EdgeInsets.only(bottom:MediaQuery.of(ctx2).viewInsets.bottom),child:Padding(padding:const EdgeInsets.all(16),child:Column(mainAxisSize:MainAxisSize.min,children:[
Text('${DateFormat('yyyy-MM-dd EEE').format(day)} ${isHoliday(day)?' [${holidayName(day)}]':''}',style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
Wrap(spacing:8,children:defs.keys.map((c)=>ChoiceChip(label:Text(c),selected:cur==c,onSelected:(_)=>setM(()=>cur=c))).toList()),
Padding(padding:const EdgeInsets.only(top:6),child:TextField(controller:nc,minLines:2,maxLines:6,keyboardType:TextInputType.multiline,textInputAction:TextInputAction.newline,decoration:const InputDecoration(labelText:'記事 (可換行多行，會同步到Google日曆標題+描述)',alignLabelWithHint:true,isDense:true,border:OutlineInputBorder()))),
Row(children:[Expanded(child:SizedBox(height:56, child:TextField(controller:otc,decoration:const InputDecoration(labelText:'OT時數',isDense:true,border:OutlineInputBorder()),keyboardType:TextInputType.number))),const SizedBox(width:8),Expanded(child:SizedBox(height:56, child:TextField(controller:exHCtrl,decoration:const InputDecoration(labelText:'額外工時',isDense:true,border:OutlineInputBorder()),keyboardType:TextInputType.number))),]),
Row(children:[
Expanded(child:SizedBox(height:56, child:TextField(controller:exTypeCtrl,decoration:const InputDecoration(labelText:'額外津貼名稱 (例:大假津貼)',isDense:true,border:OutlineInputBorder())))),
const SizedBox(width:8),
Expanded(child:SizedBox(height:56, child:TextField(controller:exCtrl,decoration:const InputDecoration(labelText:'額外津貼金額',isDense:true,border:OutlineInputBorder()),keyboardType:TextInputType.number))),
]),
const SizedBox(height:12),
Row(children:[Expanded(child:OutlinedButton(onPressed:() async { setState((){ roster.remove(k); rosterOt.remove(k); rosterExtra.remove(k); rosterExtraHrs.remove(k); rosterExtraType.remove(k); }); if(_googleEventIdMap.containsKey(k) && _rosterCalendarId!=null){ try{ await _calendarPlugin.deleteEvent(_rosterCalendarId!, _googleEventIdMap[k]); }catch(_){} _googleEventIdMap.remove(k); } save(); Navigator.pop(ctx2); },child:const Text('清除班次(保留記事)',style:TextStyle(color: Colors.orange)),)),const SizedBox(width:8),Expanded(child:FilledButton(onPressed:(){ double? otVal=double.tryParse(otc.text); double? exVal=double.tryParse(exCtrl.text); double? exHVal=double.tryParse(exHCtrl.text); setState((){ if(cur.isNotEmpty) roster[k]=cur; if(nc.text.isNotEmpty) rosterNote[k]=nc.text; else rosterNote.remove(k); if(exTypeCtrl.text.isNotEmpty) rosterExtraType[k]=exTypeCtrl.text.trim(); else rosterExtraType.remove(k); if(otVal!=null) rosterOt[k]=otVal; if(exVal!=null && exVal!=0) rosterExtra[k]=exVal; else if(exVal==0) rosterExtra.remove(k); if(exHVal!=null && exHVal!=0) rosterExtraHrs[k]=exHVal; else rosterExtraHrs.remove(k); }); save(); Navigator.pop(ctx2); },child:const Text('儲存'))),]),])); }); }); }

Future<TimeOfDay?> _pickWheelTime(BuildContext ctx, TimeOfDay init) async{
return await showTimePicker(context:ctx, initialTime:init, builder:(ctx,child){ return MediaQuery(data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat:true), child: child!); });
}
void editShiftDialog({ShiftDef? oldDef}){
var codeCtrl=TextEditingController(text:oldDef?.code??''); var labelCtrl=TextEditingController(text:oldDef?.label??''); var hoursCtrl=TextEditingController(text:oldDef?.hours.toString()??'8'); var otCtrl=TextEditingController(text:oldDef?.ot.toString()??'0'); var startCtrl=TextEditingController(text:oldDef?.start??'07:00'); var endCtrl=TextEditingController(text:oldDef?.end??'15:30'); var allowCtrl=TextEditingController(text:oldDef?.allowance.toString()??'0'); bool hasAllow=oldDef?.hasAllowance??false; bool isAllDay=oldDef?.isAllDay??false; Color picked=oldDef?.color??Colors.orange; String oldKey=oldDef?.code??'';
List<Color> palette=[Colors.orange,Colors.blue,Colors.purple,Colors.green,Colors.red,Colors.teal,Colors.brown,Colors.pink,Colors.indigo,Colors.amber,Colors.cyan,Colors.lime,Colors.deepOrange,Colors.lightBlue,Colors.deepPurple,Colors.blueGrey];
showDialog(context:context,builder:(ctx){ return StatefulBuilder(builder:(ctx2,setS){
void calcHours(){
if(isAllDay) return;
try{
var s=DateFormat('HH:mm').parse(startCtrl.text); var e=DateFormat('HH:mm').parse(endCtrl.text);
var diff=e.difference(s).inMinutes/60.0; if(diff<0) diff+=24; setS(()=>hoursCtrl.text=diff.toStringAsFixed(1));
}catch(_){}
}
return AlertDialog(title:Text(oldDef==null?'新增班次':'編輯 ${oldDef.code}'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
TextField(controller:codeCtrl,decoration:const InputDecoration(labelText:'代號')),
TextField(controller:labelCtrl,decoration:const InputDecoration(labelText:'名稱')),
const SizedBox(height:10),
Row(children:[ Expanded(child: InkWell(onTap:() async { if(isAllDay) return; TimeOfDay? t=await _pickWheelTime(ctx2, TimeOfDay(hour:int.parse(startCtrl.text.split(':')[0]), minute:int.parse(startCtrl.text.split(':')[1]))); if(t!=null){ setS(()=>startCtrl.text='${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')}'); calcHours(); } }, child: InputDecorator(decoration: const InputDecoration(labelText:'開始 HH:mm',border:OutlineInputBorder()), child: Text(startCtrl.text)))), const SizedBox(width:8), Expanded(child: InkWell(onTap:() async { if(isAllDay) return; TimeOfDay? t=await _pickWheelTime(ctx2, TimeOfDay(hour:int.parse(endCtrl.text.split(':')[0]), minute:int.parse(endCtrl.text.split(':')[1]))); if(t!=null){ setS(()=>endCtrl.text='${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')}'); calcHours(); } }, child: InputDecorator(decoration: const InputDecoration(labelText:'結束 HH:mm',border:OutlineInputBorder()), child: Text(endCtrl.text)))), ]),
const SizedBox(height:8),
Row(children:[
Checkbox(value:isAllDay,onChanged:(v){ setS((){ isAllDay=v??false; if(isAllDay){ startCtrl.text='00:00'; endCtrl.text='00:00'; } else { calcHours(); } }); }),
const Text('全天',style:TextStyle(fontWeight:FontWeight.bold)),
const SizedBox(width:8),
const Expanded(child: Text('核實全天後時間變00:00，工時可任意輸入',style:TextStyle(fontSize:10,color:Colors.grey))),
]),
Row(children:[
Expanded(child:SizedBox(height:78, child: TextField(controller:hoursCtrl,decoration:InputDecoration(labelText:'工時',border:const OutlineInputBorder(),helperText:isAllDay?'全天可任意輸入':' ',helperStyle:const TextStyle(fontSize:10)),keyboardType:TextInputType.number))),
const SizedBox(width:8),
Expanded(child:SizedBox(height:78, child: TextField(controller:otCtrl,decoration:const InputDecoration(labelText:'OT',border:OutlineInputBorder(),helperText:' ',helperStyle:TextStyle(fontSize:10)),keyboardType:TextInputType.number))),
]),
const SizedBox(height:12),
Row(children:[Checkbox(value:hasAllow,onChanged:(v)=>setS(()=>hasAllow=v??false)),const Text('有津貼核實',style:TextStyle(fontWeight:FontWeight.bold))]),
if(hasAllow) TextField(controller:allowCtrl,decoration:const InputDecoration(labelText:'津貼金額',prefixText:'\$ ',border:OutlineInputBorder()),keyboardType:TextInputType.number),
const SizedBox(height:12),
const Text('自定班次顏色',style:TextStyle(fontWeight:FontWeight.bold)), const SizedBox(height:8),
Wrap(spacing:8,runSpacing:8,children:palette.map((c)=>GestureDetector(onTap:()=>setS(()=>picked=c),child:Container(width:36,height:36,decoration:BoxDecoration(color:c,shape:BoxShape.circle,border:picked==c?Border.all(width:3,color:Colors.black):null),child:picked==c?const Icon(Icons.check,color:Colors.white,size:18):null))).toList()),
])),actions:[TextButton(onPressed:()=>Navigator.pop(ctx2),child:const Text('取消')),FilledButton(onPressed:(){ String newCode=codeCtrl.text.trim(); if(newCode.isEmpty) return; double hrs=double.tryParse(hoursCtrl.text)??8; double allowVal=double.tryParse(allowCtrl.text)??0; setState((){ if(oldKey.isNotEmpty && oldKey!=newCode){ defs.remove(oldKey); roster.forEach((k,v){ if(v==oldKey) roster[k]=newCode; }); for(int i=0;i<pattern.length;i++){ for(int j=0;j<pattern[i].length;j++){ if(pattern[i][j]==oldKey) pattern[i][j]=newCode; } } } defs[newCode]=ShiftDef(newCode,labelCtrl.text.isEmpty?newCode:labelCtrl.text,hrs,picked,ot:double.tryParse(otCtrl.text)??0,start:startCtrl.text,end:endCtrl.text,hasAllowance:hasAllow,allowance:hasAllow?allowVal:0,isAllDay:isAllDay); }); save(); Navigator.pop(ctx2); },child:const Text('儲存'))]); }); }); }
Future<void> pickRangeAndApply() async{ List<List<String>> chosenPattern = pattern; if(savedPatterns.isNotEmpty){ int? selected = await showDialog<int>(context:context,builder:(ctx){ return AlertDialog(title:const Text('選擇排更模式'),content:SizedBox(width:300,child:ListView(shrinkWrap:true,children:[ListTile(title:const Text('當前版面'),subtitle:Text('${pattern.length}行'),leading:const Icon(Icons.edit),onTap:()=>Navigator.pop(ctx,-1)),const Divider(),...savedPatterns.asMap().entries.map((en)=>ListTile(title:Text(en.value.name),subtitle:Text('${en.value.data.length}行'),leading:const Icon(Icons.folder),onTap:()=>Navigator.pop(ctx,en.key))),],)),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('取消'))]); }); if(selected==null) return; if(selected==-1){ chosenPattern = pattern; } else { chosenPattern = savedPatterns[selected].data.map((r)=>List<String>.from(r)).toList(); } } DateTimeRange? p=await showDateRangePicker(context:context,firstDate:DateTime(2023),lastDate:DateTime(2035)); if(p==null) return; var flat=chosenPattern.expand((e)=>e).toList(); setState((){ int i=0; for(DateTime d=p.start;!d.isAfter(p.end);d=d.add(const Duration(days:1))){ roster[DateFormat('yyyy-MM-dd').format(d)]=flat[i%flat.length]; i++; } }); save(); setState(()=>tab=0); }

Widget patternTab(){
return SafeArea(child:Column(children:[
const Padding(padding:EdgeInsets.only(top:12),child:Center(child:Text('排更模式',style:TextStyle(fontWeight:FontWeight.bold,fontSize:18)))),
Padding(padding:const EdgeInsets.symmetric(vertical:6),child:Column(children:[
Row(mainAxisAlignment:MainAxisAlignment.center,children:[
FilledButton.tonalIcon(icon:const Icon(Icons.playlist_add),label:const Text('一次加N行'),onPressed:(){
var c=TextEditingController(text:'3');
showDialog(context:context,builder:(ctx)=>AlertDialog(title:const Text('一次加幾行'),content:SizedBox(height:56,child:TextField(controller:c,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'行數',isDense:true,border:OutlineInputBorder()))),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('取消')),FilledButton(onPressed:(){ int n=int.tryParse(c.text)??1; setState(()=>pattern.addAll(List.generate(n,(_)=>List.filled(7,'O')))); save(); Navigator.pop(ctx); },child:const Text('確定'))]));
}),
const SizedBox(width:8),
FilledButton(onPressed:() async{ await pickRangeAndApply(); },child:const Text('自動排班')),
]),
const SizedBox(height:8),
Row(mainAxisAlignment:MainAxisAlignment.center,children:[
FilledButton.tonalIcon(icon:const Icon(Icons.folder),label:Text('已存模式${savedPatterns.isEmpty?'': '(${savedPatterns.length})'}'),onPressed:(){ if(savedPatterns.isEmpty){ ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('未有已存模式'))); return; } showModalBottomSheet(context:context,builder:(ctx)=>SafeArea(child:ListView(children:[const ListTile(title:Text('已存排班模式 (可自定義名稱)',style:TextStyle(fontWeight:FontWeight.bold))),...savedPatterns.asMap().entries.map((en)=>ListTile(title:Text(en.value.name),subtitle:Text('${en.value.data.length}行 - ${en.value.data.expand((e)=>e).take(7).join(',')}...'),trailing:Row(mainAxisSize:MainAxisSize.min,children:[IconButton(icon:const Icon(Icons.upload),tooltip:'載入',onPressed:(){ setState((){ pattern=en.value.data.map((r)=>List<String>.from(r)).toList(); editingPatternName=en.value.name; editingPatternIndex=en.key; }); save(); Navigator.pop(ctx); }),IconButton(icon:const Icon(Icons.edit),tooltip:'改名',onPressed:(){ var ctrl=TextEditingController(text:en.value.name); showDialog(context:context,builder:(ctx2)=>AlertDialog(title:const Text('改排班名稱'),content:TextField(controller:ctrl,decoration:const InputDecoration(labelText:'自定義名稱')),actions:[FilledButton(onPressed:(){ String nn=ctrl.text.trim(); if(nn.isNotEmpty){ setState(()=>savedPatterns[en.key]=SavedPattern(nn,en.value.data)); save(); Navigator.pop(ctx2); Navigator.pop(ctx); } },child:const Text('保存'))])); }),IconButton(icon:const Icon(Icons.delete),onPressed:(){ setState(()=>savedPatterns.removeAt(en.key)); save(); Navigator.pop(ctx); }),]))),]))); }),
const SizedBox(width:8),
FilledButton.tonalIcon(icon:const Icon(Icons.save_as),label:const Text('另存為新模式'),onPressed:(){
var ctrl=TextEditingController(text:'模式_${DateFormat('MMdd_HHmm').format(DateTime.now())}');
showDialog(context:context,builder:(ctx)=>AlertDialog(title:const Text('另存排更模式 自定義名稱'),content:TextField(controller:ctrl,decoration:const InputDecoration(labelText:'模式名稱 (可自定義)',border:OutlineInputBorder())),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('取消')),FilledButton(onPressed:(){ String n=ctrl.text.trim(); if(n.isEmpty) return; if(savedPatterns.any((e)=>e.name==n)){ ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('名稱 $n 已存在'))); return; }
setState((){
savedPatterns.add(SavedPattern(n,pattern.map((r)=>List<String>.from(r)).toList()));
pattern = _defaultPattern.map((r)=>List<String>.from(r)).toList();
editingPatternName=null;
editingPatternIndex=null;
});
save(); Navigator.pop(ctx); },child:const Text('保存'))]));
}),
]),
if(editingPatternName!=null) Padding(padding:const EdgeInsets.only(top:8),child:Container(padding:const EdgeInsets.symmetric(horizontal:12,vertical:6),decoration:BoxDecoration(color:Colors.orange.withOpacity(0.15),borderRadius:BorderRadius.circular(20)),child:Row(mainAxisSize:MainAxisSize.min,children:[Text('正在編輯: $editingPatternName',style:const TextStyle(fontSize:12,fontWeight:FontWeight.bold)),const SizedBox(width:8),FilledButton.tonal(onPressed:(){ if(editingPatternIndex!=null){ setState(()=>savedPatterns[editingPatternIndex!]=SavedPattern(editingPatternName!,pattern.map((r)=>List<String>.from(r)).toList())); save(); } },child:const Text('更新同名')),IconButton(icon:const Icon(Icons.close,size:16),onPressed:(){ setState((){ editingPatternName=null; editingPatternIndex=null; }); })]))),
])),
SingleChildScrollView(scrollDirection: Axis.horizontal, padding:const EdgeInsets.all(8), child: Row(children: defs.keys.map((k)=>Padding(padding:const EdgeInsets.only(right:8),child: Chip(label:Text(k),backgroundColor:defs[k]!.color.withOpacity(0.3)))).toList())),
Expanded(child:ListView.builder(itemCount:pattern.length,itemBuilder:(ctx,r){
return Card(margin:const EdgeInsets.symmetric(horizontal:8,vertical:4),child:Padding(padding:const EdgeInsets.all(6),child:Row(children:[
SizedBox(width:28,child:Text('${r+1}',textAlign:TextAlign.center,style:const TextStyle(fontWeight:FontWeight.bold))),
Expanded(child:Row(children:List.generate(7,(c){ return Expanded(child:GestureDetector(onTap:(){ showModalBottomSheet(context:context,builder:(ctx)=>Wrap(children:defs.keys.map((k)=>ListTile(title:Text(k),onTap:(){ setState(()=>pattern[r][c]=k); save(); Navigator.pop(ctx); })).toList())); },child:Container(margin:const EdgeInsets.all(2),height:56,decoration:BoxDecoration(color:defs[pattern[r][c]]?.color.withOpacity(0.3),borderRadius:BorderRadius.circular(8),border:Border.all(color:Colors.black12)),child:Center(child:FittedBox(fit:BoxFit.scaleDown,child:Text(pattern[r][c],style:TextStyle(fontSize:calendarFontSize))))))); }))),
IconButton(icon:const Icon(Icons.delete),onPressed:(){ setState(()=>pattern.removeAt(r)); save(); })
]))); })),
]));
}

Widget reportTab(){
int year=focused.year; int month=focused.month; double totalYearHrs=0; Map<String,int> yearShiftCount={}; Map<int,double> yearMonthlyHrs={}; if(isYearReport){ for(int m=1;m<=12;m++){ int dim=DateTime(year,m+1,0).day; double hrs=0; for(int d=1;d<=dim;d++){ String k=DateFormat('yyyy-MM-dd').format(DateTime(year,m,d)); String? c=roster[k]; if(c==null) continue; var def=defs[c]; if(def!=null){ hrs+=def.hours; totalYearHrs+=def.hours; yearShiftCount[c]=(yearShiftCount[c]??0)+1; } } yearMonthlyHrs[m]=hrs; } } int dim=DateTime(year,month+1,0).day; double hrs=0,ot=0; double allow=0; Map<String,int> shiftCount={}; Map<String,double> shiftHours={}; Map<int,double> weeklyHours={}; Map<String,double> extraByType={}; for(int i=1;i<=dim;i++){ DateTime dt=DateTime(year,month,i); String k=DateFormat('yyyy-MM-dd').format(dt); String? c=roster[k]; if(c==null) continue; var d=defs[c]; double curOt=rosterOt[k]??d?.ot??0; if(d!=null){ hrs+=d.hours; shiftCount[c]=(shiftCount[c]??0)+1; shiftHours[c]=(shiftHours[c]??0)+d.hours; if(d.hasAllowance) allow+=d.allowance; int w=isoWeek(dt); weeklyHours[w]=(weeklyHours[w]??0)+d.hours; } ot+=curOt; allow+=(rosterExtra[k]??0); if(rosterExtra.containsKey(k) && rosterExtraType.containsKey(k)){ String t=rosterExtraType[k]!; extraByType[t]=(extraByType[t]??0)+rosterExtra[k]!; } hrs+=(rosterExtraHrs[k]??0); } double otAmount=ot * overtimeRate; double totalAllow=allow + otAmount + extraAllowances.fold(0.0,(a,b)=>a+b.amount); return SafeArea(child: ListView(padding: const EdgeInsets.all(12),children: [ Row(children:[IconButton(onPressed:exportReport,icon:const Icon(Icons.ios_share),tooltip:'匯出',style:IconButton.styleFrom(backgroundColor:Colors.deepPurple.withOpacity(0.1))),const SizedBox(width:4),InkWell(onTap:()=>quickJumpMonth(forReport:true),child:Row(mainAxisSize:MainAxisSize.min,children:[Text('${year}年${isYearReport?' 全年':' ${month}月'} 報表',style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),const Icon(Icons.arrow_drop_down)])),const Spacer(),SegmentedButton<bool>(segments:const [ButtonSegment(value:false,label:Text('本月')),ButtonSegment(value:true,label:Text('全年'))],selected:{isYearReport},onSelectionChanged:(s){ setState(()=>isYearReport=s.first); }),]),
const SizedBox(height:8),
if(isYearReport) Card(color:const Color(0xFFE3F2FD),child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('全年總工時 ${totalYearHrs.toStringAsFixed(1)}h',style:const TextStyle(fontWeight:FontWeight.bold)), const Divider(),...yearMonthlyHrs.entries.map((e)=>Row(children:[Text('${e.key}月'),const Spacer(),Text('${e.value.toStringAsFixed(1)}h')])),const Divider(),...yearShiftCount.entries.map((e){ var d=defs[e.key]; return Row(children:[Container(width:26,height:26,decoration:BoxDecoration(color:d?.color??Colors.grey,borderRadius:BorderRadius.circular(5)),child:Center(child:Text(e.key,style:const TextStyle(color:Colors.white,fontSize:10)))), const SizedBox(width:6), Text('${d?.label??e.key} ${e.value}次'), const Spacer(), Text('${(e.value*(d?.hours??0)).toStringAsFixed(1)}h')]); }),]))),
if(!isYearReport) Card(color:const Color(0xFFE3F2FD),child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('班次統計',style:TextStyle(fontWeight:FontWeight.bold)), const Divider(),...shiftCount.entries.map((e){ double h=shiftHours[e.key]??0; var d=defs[e.key]; return Padding(padding:const EdgeInsets.symmetric(vertical:2),child:Row(children:[Container(width:28,height:28,decoration:BoxDecoration(color:d?.color??Colors.grey,borderRadius:BorderRadius.circular(6)),child:Center(child:Text(e.key,style:const TextStyle(color:Colors.white,fontSize:11)))), const SizedBox(width:8), Text('${d?.label??e.key} ${(d?.hasAllowance==true)?'有津貼':''}'), const Spacer(), Text('${e.value}次 / ${h.toStringAsFixed(1)}h',style:const TextStyle(fontWeight:FontWeight.bold)),])); }),const Divider(), Text('總工時 ${hrs.toStringAsFixed(1)}h / 承上 ${carry}h / 合計 ${(hrs+carry).toStringAsFixed(1)}h'),]))),
Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('承上 $carry h + 本月 $hrs h = ${carry+hrs}h',style:const TextStyle(fontWeight:FontWeight.bold)), const Divider(), Text(isYearReport?'每週工時統計 全年':'每週工時統計 (標準 & 承上) 週數',style:const TextStyle(fontWeight:FontWeight.bold)),...weeklyHours.entries.map((e){ double avgCarry=weeklyHours.isEmpty?0:carry/weeklyHours.length; double adjusted=e.value + avgCarry; double diff=adjusted - standardWeeklyHours; return Padding(padding:const EdgeInsets.symmetric(vertical:3),child:Row(children:[Text('W${e.key}',style:const TextStyle(fontWeight:FontWeight.bold)), const SizedBox(width:8), Text('${e.value.toStringAsFixed(1)}h +承上${avgCarry.toStringAsFixed(1)} = ${adjusted.toStringAsFixed(1)}h'), const Spacer(), Text('${diff>=0?'+':''}${diff.toStringAsFixed(1)}h',style:TextStyle(color:diff>0?Colors.green:Colors.red,fontWeight:FontWeight.bold)),])); }),const Divider(), Text('標準 ${standardWeeklyHours}h/週 | 總差額 ${(carry+hrs - standardWeeklyHours*weeklyHours.length).toStringAsFixed(1)}h'),]))),
Card(color:const Color(0xFFE8F5E9),child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
const Text('津貼類別 (含自定義類別)',style:TextStyle(fontWeight:FontWeight.bold)),
Row(children:[const Text('班次津貼+單日額外'),const Spacer(),Text('\$${allow.toStringAsFixed(1)}')]),
if(extraByType.isNotEmpty) const Divider(),
...extraByType.entries.map((e)=>Row(children:[Text('類別: ${e.key}'),const Spacer(),Text('\$${e.value.toStringAsFixed(1)}',style:const TextStyle(fontWeight:FontWeight.bold,color:Colors.deepPurple))])),
Row(children:[Text('OT${ot.toStringAsFixed(1)}h x ${overtimeRate.toStringAsFixed(0)}'),const Spacer(),Text('\$${otAmount.toStringAsFixed(1)}')]),
const Divider(),
...extraAllowances.map((e)=>Row(children:[Text(e.name),const Spacer(),Text('\$${e.amount}'),IconButton(icon:const Icon(Icons.delete,size:16),onPressed:(){ setState(()=>extraAllowances.removeAt(extraAllowances.indexOf(e))); save(); })])),
const Divider(),
Row(children:[const Text('津貼總額 (含自定+類別)'),const Spacer(),Text('\$${totalAllow.toStringAsFixed(1)}',style:const TextStyle(fontWeight:FontWeight.bold))]),
]))),
],),);
}

Widget settingsTab(){
var stdCtrl=TextEditingController(text:standardWeeklyHours.toString()); var carryCtrl=TextEditingController(text:carry.toString()); var otRateCtrl=TextEditingController(text:overtimeRate.toString());
List<MapEntry<String,ShiftDef>> shiftList=defs.entries.toList(); List<MapEntry<String,ShiftDef>> shiftShow=showAllShift? shiftList : shiftList.take(5).toList(); List<ExtraAllowance> allowShow=showAllExtra? extraAllowances : extraAllowances.take(5).toList();
return SafeArea(child:ListView(padding:const EdgeInsets.all(16),children:[
const Text('排更日曆自定名稱',style:TextStyle(fontSize:16,fontWeight:FontWeight.bold)),
Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(children:[TextField(controller:nameCtrl,decoration:const InputDecoration(labelText:'日曆名稱',border:OutlineInputBorder())),const SizedBox(height:8),SizedBox(width:double.infinity,child:FilledButton(onPressed:(){ setState(()=>customName=nameCtrl.text.trim().isEmpty?'我的排更':nameCtrl.text.trim()); save(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('日曆名已改為 $customName'))); },child:const Text('保存日曆名稱')))]))), const SizedBox(height:16), const Text('自定班次',style:TextStyle(fontSize:16,fontWeight:FontWeight.bold)), Card(child:Column(children:[...shiftShow.map((e){ var d=e.value; return ListTile(leading:CircleAvatar(backgroundColor:d.color,child:Text(d.code,style:const TextStyle(color:Colors.white,fontSize:10))),title:Text('${d.code} - ${d.label} ${d.isAllDay?'[全天]': '${d.start}-${d.end}'} ${d.hasAllowance?'[有津貼\$${d.allowance}]':''}'),subtitle:Text('${d.hours.toStringAsFixed(1)}h | ${d.detailTime}'),trailing:Row(mainAxisSize:MainAxisSize.min,children:[IconButton(icon:const Icon(Icons.edit),onPressed:()=>editShiftDialog(oldDef:d)),IconButton(icon:const Icon(Icons.delete),onPressed:(){ setState(()=>defs.remove(e.key)); save(); })])); }),if(shiftList.length>5) TextButton(onPressed:(){ setState(()=>showAllShift=!showAllShift); },child:Text(showAllShift?'收起':'顯示全部 ${shiftList.length}項')),ListTile(leading:const Icon(Icons.add),title:const Text('新增班次'),onTap:()=>editShiftDialog()),])), const SizedBox(height:16), const Text('公眾假期地區 (自動更新多年 2024-2035)',style:TextStyle(fontSize:16,fontWeight:FontWeight.bold)), Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(children:[DropdownButtonFormField<String>(value:holidayRegion,decoration:const InputDecoration(labelText:'地區 (已自動更新多年)',border:OutlineInputBorder()),items:['無','香港','中國內地','台灣','美國'].map((r)=>DropdownMenuItem(value:r,child:Text(r))).toList(),onChanged:(v){ setState(()=>holidayRegion=v!); save(); }),const SizedBox(height:8), Text('本年 ${focused.year} 假期數: ${getHolidays(focused.year,holidayRegion).length} 個 已自動更新至2035',style:const TextStyle(fontSize:12,color:Colors.grey))]))), const SizedBox(height:16), const Text('日曆同步 - 已恢復存取所有日曆權限',style:TextStyle(fontSize:16,fontWeight:FontWeight.bold)), Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(children:[ SwitchListTile(title:const Text('啟用日曆同步'),subtitle:Text(googleSyncEnabled?'已授權 只同步代號+時間+記事':'未授權 - 首次會詢問權限'),value:googleSyncEnabled,onChanged:(v) async { if(v){ await _requestGooglePerm(); }else{ setState(()=>googleSyncEnabled=false); save(); } }), SwitchListTile(title:const Text('自動同步(去重)'),value:autoSync,onChanged:googleSyncEnabled? (v){ setState(()=>autoSync=v); save(); }:null), Row(children:[Expanded(child:OutlinedButton.icon(onPressed:googleSyncEnabled? ()=>_syncToGoogle():null,icon:const Icon(Icons.sync),label:const Text('手動同步去重'))),const SizedBox(width:8),Expanded(child:OutlinedButton.icon(onPressed:(){ setState(()=>googleSyncEnabled=false); save(); },icon:const Icon(Icons.link_off),label:const Text('取消')))]), Text('當前: $_rosterCalendarName\nID: ${_rosterCalendarId??'未選'} 帳號: $_rosterAccountName\n同步內容: 班次代號+開始/結束時間+記事',style:const TextStyle(fontSize:11,color:Colors.grey)),
const SizedBox(height:8),
SizedBox(width: double.infinity, child: OutlinedButton.icon(icon:const Icon(Icons.list), label:const Text('選擇日曆 (已恢復權限)'), onPressed: () async { await _pickGoogleCalendarDialog(); })),
SizedBox(width: double.infinity, child: OutlinedButton.icon(icon:const Icon(Icons.security), label:const Text('重新請求日曆權限 (修復空白)'), onPressed: () async { await handleCalendarPermission(silent:false); setState((){}); })),
]))),
const SizedBox(height:16),
const Text('清除排更 - 按日期範圍 (保留記事)',style:TextStyle(fontSize:16,fontWeight:FontWeight.bold,color: Colors.red)),
Card(color: const Color(0xFFFFEBEE), child: Padding(padding:const EdgeInsets.all(12), child: Column(children:[SizedBox(width: double.infinity, child: FilledButton.icon(icon:const Icon(Icons.delete_sweep), style: FilledButton.styleFrom(backgroundColor: Colors.red), label:const Text('按日期範圍清除'), onPressed: clearRosterByRange)),]))),
const SizedBox(height:16), const Text('標準工時 & 承上 & 超時金額',style:TextStyle(fontSize:16,fontWeight:FontWeight.bold)),
Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(children:[Row(children:[Expanded(child:TextField(controller:stdCtrl,decoration:const InputDecoration(labelText:'標準工時',suffixText:'h/週',border:OutlineInputBorder()))),const SizedBox(width:8),Expanded(child:TextField(controller:carryCtrl,decoration:const InputDecoration(labelText:'承上餘額',border:OutlineInputBorder())))]),const SizedBox(height:10), TextField(controller:otRateCtrl,decoration:const InputDecoration(labelText:'超時金額 /h',prefixText:'\$ ',border:OutlineInputBorder())),const SizedBox(height:10), SizedBox(width:double.infinity,child:FilledButton(onPressed:(){ double? v1=double.tryParse(stdCtrl.text); double? v2=double.tryParse(carryCtrl.text); double? v3=double.tryParse(otRateCtrl.text); if(v1!=null) standardWeeklyHours=v1; if(v2!=null) carry=v2; if(v3!=null) overtimeRate=v3; setState((){}); save(); },child:const Text('保存設定'))),]))),
const SizedBox(height:16),
const Text('日曆顯示設定',style:TextStyle(fontSize:16,fontWeight:FontWeight.bold)),
Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(children:[
Row(children:[const Text('小'),Expanded(child:Slider(value:calendarFontSize,min:8,max:20,divisions:12,onChanged:(v){ setState(()=>calendarFontSize=v); })),const Text('大')]),
FilledButton.tonal(onPressed:(){ save(); },child:const Text('保存文字大小')),
const Divider(),
ListTile(title:const Text('當天日期格背景顏色'),leading:CircleAvatar(backgroundColor:todayBgColor),trailing:const Icon(Icons.color_lens),onTap:(){
showDialog(context:context,builder:(ctx)=>AlertDialog(title:const Text('選擇當天背景'),content:Wrap(spacing:8,children:[Colors.yellow.shade100,Colors.orange.shade100,Colors.green.shade100,Colors.blue.shade100,Colors.pink.shade100,const Color(0xFFFFF9C4)].map((c)=>GestureDetector(onTap:(){ setState(()=>todayBgColor=c); save(); Navigator.pop(ctx); },child:Container(width:40,height:40,decoration:BoxDecoration(color:c,shape:BoxShape.circle,border:Border.all())))).toList())));
}),
ListTile(title:const Text('當天日期格邊框顏色'),leading:CircleAvatar(backgroundColor:todayBorderColor),trailing:const Icon(Icons.border_color),onTap:(){
showDialog(context:context,builder:(ctx)=>AlertDialog(title:const Text('選擇當天邊框'),content:Wrap(spacing:8,children:[Colors.orange,Colors.red,Colors.green,Colors.blue,Colors.purple,Colors.black].map((c)=>GestureDetector(onTap:(){ setState(()=>todayBorderColor=c); save(); Navigator.pop(ctx); },child:Container(width:40,height:40,decoration:BoxDecoration(color:c,shape:BoxShape.circle)))).toList())));
}),
]))),
const SizedBox(height:16), const Text('額外津貼 (自定名)',style:TextStyle(fontSize:16,fontWeight:FontWeight.bold)),
Card(child:Column(children:[...allowShow.map((e){ int idx=extraAllowances.indexOf(e); return ListTile(title:Text(e.name),subtitle:Text('\$${e.amount}'),trailing:IconButton(icon:const Icon(Icons.delete,size:18,color:Colors.red),onPressed:(){ setState(()=>extraAllowances.removeAt(idx)); save(); })); }),ListTile(leading:const Icon(Icons.add),title:const Text('新增額外津貼 (自定名)'),onTap:(){ var nCtrl=TextEditingController(); var vCtrl=TextEditingController(text:'0'); showDialog(context:context,builder:(ctx)=>AlertDialog(title:const Text('新增額外津貼'),content:Column(mainAxisSize:MainAxisSize.min,children:[SizedBox(height:56,child:TextField(controller:nCtrl,decoration:const InputDecoration(labelText:'名稱 例如:大假津貼',isDense:true,border:OutlineInputBorder()))), const SizedBox(height:8), SizedBox(height:56,child:TextField(controller:vCtrl,decoration:const InputDecoration(labelText:'金額',isDense:true,border:OutlineInputBorder()),keyboardType:TextInputType.number)),]),actions:[FilledButton(onPressed:(){ String name=nCtrl.text.trim(); double? val=double.tryParse(vCtrl.text); if(name.isEmpty||val==null) return; setState(()=>extraAllowances.add(ExtraAllowance(name,val))); save(); Navigator.pop(ctx); },child:const Text('新增'))])); }),if(extraAllowances.length>5) TextButton(onPressed:()=>setState(()=>showAllExtra=!showAllExtra),child:Text(showAllExtra?'收起':'顯示全部 ${extraAllowances.length}項')),])),
const SizedBox(height:16), const Text('全部備份與還原',style:TextStyle(fontSize:16,fontWeight:FontWeight.bold)),
Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
Row(children:[Expanded(child:OutlinedButton.icon(onPressed:backupAnywhere,icon:const Icon(Icons.backup),label:const Text('全部備份'))),const SizedBox(width:8),Expanded(child:OutlinedButton.icon(onPressed:restoreLocalFile,icon:const Icon(Icons.restore),label:const Text('全部還原')))]),
const SizedBox(height:8),
Container(width:double.infinity,padding:const EdgeInsets.all(10),decoration:BoxDecoration(color:Colors.grey.shade100,borderRadius:BorderRadius.circular(8)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('最近備份路徑:',style:TextStyle(fontSize:11,fontWeight:FontWeight.bold)),Text(_lastBackupPath,style:const TextStyle(fontSize:10,color:Colors.black87)),const SizedBox(height:4),const Text('去手機 文件管理 > 上面路徑查找',style:TextStyle(fontSize:9,color:Colors.grey))]))
]))),
const SizedBox(height:16),
const Text('桌面小工具 4x4 (Fix 9)',style:TextStyle(fontSize:16,fontWeight:FontWeight.bold)),
Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
const Text('已添加 HomeWidget 4x4，長按桌面>小工具>RosterPro 4x4\n如找不到：\n1. pubspec.yaml 加 home_widget: ^0.6.0\n2. android/app/src/main/AndroidManifest.xml 加 <receiver android:name=".RosterWidgetProvider"...>\n3. android/app/src/main/res/layout/widget_layout.xml\n4. android/app/src/main/kotlin/.../RosterWidgetProvider.kt',style:TextStyle(fontSize:11)),
SizedBox(width:double.infinity,child:FilledButton.tonal(onPressed:(){ updateWidget(); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('已刷新桌面小工具'))); },child:const Text('刷新小工具'))),
]))),
]));}
@override Widget build(BuildContext context){
return Scaffold(body:[calTab(),patternTab(),reportTab(),settingsTab()][tab],bottomNavigationBar:NavigationBar(selectedIndex:tab,onDestinationSelected:(i)=>setState(()=>tab=i),destinations:const[NavigationDestination(icon:Icon(Icons.calendar_month),label:'月曆'),NavigationDestination(icon:Icon(Icons.pattern),label:'模式'),NavigationDestination(icon:Icon(Icons.bar_chart),label:'報表'),NavigationDestination(icon:Icon(Icons.settings),label:'設定'),]),);
}
}
