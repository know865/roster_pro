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
String get detailTime=>isAllDay?'全天  {end}  {start}- {hours.toStringAsFixed(1)}h';
}
class ExtraAllowance { String name; double amount; ExtraAllowance(this.name,this.amount); Map<String,dynamic> toJson()=>{'name':name,'amount':amount}; factory ExtraAllowance.fromJson(Map<String,dynamic> j)=>ExtraAllowance(j['name'],(j['amount'] as num).toDouble()); }
class SavedPattern { String name; List<List<String>> data; SavedPattern(this.name,this.data); Map<String,dynamic> toJson()=>{'name':name,'data':data}; factory SavedPattern.fromJson(Map<String,dynamic> j)=>SavedPattern(j['name'], (j['data'] as List).map<List<String>>((r)=>(r as List).map<String>((e)=>e.toString()).toList()).toList()); }
class RosterApp extends StatelessWidget { const RosterApp({super.key}); @override Widget build(BuildContext context){ return MaterialApp(title:'Roster Pro v7.0',theme:ThemeData(useMaterial3:true,colorSchemeSeed:Colors.deepPurple),home:const MainPage()); } }

class MainPage extends StatefulWidget { const MainPage({super.key}); @override State<MainPage> createState()=>MainPageState(); }
class MainPageState extends State<MainPage> {
int tab=0; DateTime focused=DateTime.now(); DateTime selectedDay=DateTime.now();
Map<String,String> roster={}; Map<String,String> rosterNote={}; Map<String,String> rosterExtraType={}; Map<String,double> rosterOt={}; Map<String,double> rosterExtra={}; Map<String,double> rosterExtraHrs={};MainPageState extends State<MainPage> {
int tab=0; DateTime focused=DateTime.now(); DateTime selectedDay=DateTime.now();
Map<String,String> roster={}; Map<String,String> rosterNote={}; Map<String,String> rosterExtraType={}; Map<String,double> rosterOt={}; Map<String,double> rosterExtra={}; Map<String,double> rosterExtraHrs={};
Map<String,ShiftDef> defs={
'早':ShiftDef('早','早更',8,Colors.orange,start:'07:00',end:'15:30',hasAllowance:true,allowance:80),
'中':ShiftDef('中','中更',8,Colors.blue,start:'14:00',end:'22:00'),
'宵':ShiftDef('宵','宵更',8,Colors.purple,start:'22:00',end:'06:00',hasAllowance:true,allowance:60),
'O':ShiftDef('O','休',0,Colors.green,start:'00:00',end:'00:00',isAllDay:true),
};
List<List<String>> pattern=[["早","早","中","中","宵","宵","O"],["早","早","早","中","中","O","O"]];
List<SavedPattern> savedPatterns=[]; double carry=0; String customName='我的排更-專屬日曆'; TextEditingController nameCtrl=TextEditingController();
double standardWeeklyHours=42; double overtimeRate=80; List<ExtraAllowance> extraAllowances=[]; double calendarFontSize=14;
bool googleSyncEnabled=false; bool autoSync=false; bool isYearReport=false; bool showAllShift=false; bool showAllExtra=false;
String? editingPatternName; int? editingPatternIndex; String holidayRegion='香港';
GlobalKey calKey=GlobalKey();
DeviceCalendarPlugin _calendarPlugin = DeviceCalendarPlugin();
static const _realChannel = MethodChannel('com.roster/calendar_real');
String? _rosterCalendarId; String _rosterCalendarName='未選'; String _rosterAccountName='';
Map<String,String> googleEventIdMap={};
Future<void> updateWidget() async{ try{ String todayKey=DateFormat('yyyy-MM-dd').format(DateTime.now()); String tomorrowKey=DateFormat('yyyy-MM-dd').format(DateTime.now().add(const Duration(days:1))); await HomeWidget.saveWidgetData('today_code', roster[todayKey]??'O'); await HomeWidget.saveWidgetData('tomorrow_code', roster[tomorrowKey]??'O'); await HomeWidget.saveWidgetData('note', rosterNote[todayKey]??''); await HomeWidget.saveWidgetData('extraType', rosterExtraType[todayKey]??''); await HomeWidget.updateWidget(androidName:'RosterWidgetProvider'); }catch(){} }
bool _isSyncing=false;
String _lastBackupPath='未備份'; Color todayBgColor=const Color(0xFFFFF9C4); Color todayBorderColor=Colors.orange; Color holidayDotColor=Colors.red;

Map<String,String> getHolidays(int year, String region){
Map<String,String> m={};
if(region=='無') return m;
if(region=='香港'){
m[' {year}-05-01']='勞動節';
m[' {year}-10-01']='國慶';
m['${year}-12-25']='聖誕';
if(year2024){ m.addAll({'2024-02-10':'初一','2024-02-11':'初二','2024-02-12':'初三','2024-04-04':'清明','2024-05-15':'佛誕','2024-06-10':'端午','2024-09-18':'中秋翌日','2024-10-11':'重陽','2024-12-26':'聖誕後'}); }
else if(year2025){ m.addAll({'2025-01-29':'初一','2025-01-30':'初二','2025-01-31':'初三','2025-04-04':'清明','2025-05-05':'佛誕','2025-05-31':'端午','2025-10-07':'中秋翌日','2025-10-29':'重陽'}); }
else if(year2026){ m.addAll({'2026-02-17':'初一','2026-02-18':'初二','2026-02-19':'初三','2026-04-05':'清明','2026-05-24':'佛誕','2026-06-19':'端午','2026-09-26':'中秋翌日','2026-10-18':'重陽'}); }
else if(year2027){ m.addAll({'2027-02-06':'初一','2027-02-07':'初二','2027-02-08':'初三','2027-04-05':'清明','2027-05-13':'佛誕','2027-06-09':'端午','2027-09-16':'中秋翌日','2027-10-08':'重陽'}); }
else if(year2028){ m.addAll({'2028-01-26':'初一','2028-01-27':'初二','2028-01-28':'初三','2028-04-04':'清明','2028-05-01':'佛誕','2028-05-27':'端午','2028-10-04':'中秋翌日','2028-10-26':'重陽'}); }
else if(year2029){ m.addAll({'2029-02-13':'初一','2029-02-14':'初二','2029-02-15':'初三','2029-04-05':'清明','2029-05-20':'佛誕','2029-06-16':'端午','2029-09-23':'中秋翌日','2029-10-15':'重陽'}); }
else if(year2030){ m.addAll({'2030-02-03':'初一','2030-02-04':'初二','2030-02-05':'初三','2030-04-05':'清明','2030-05-09':'佛誕','2030-06-05':'端午','2030-09-12':'中秋翌日','2030-10-04':'重陽'}); }
else if(year>=2031){ m.addAll({' {year}-04-05':'清明',' {year}-06-10':'端午',' {year}-10-11':'重陽'}); }
}
if(region'中國內地'){ m[' {year}-05-01']='勞動節'; m['latex
{year}-10-01']='國慶'; } if(region=='台灣'){ m['

{year}-01-01']='元旦'; m[' {year}-10-10']='國慶'; }
if(region=='美國'){ m[' {year}-07-04']='Independence'; m[' {year}-12-25']='Christmas'; }
return m;
}
bool isHoliday(DateTime d){ var map=getHolidays(d.year, holidayRegion); return map.containsKey(DateFormat('yyyy-MM-dd').format(d)); }
String holidayName(DateTime d){ var map=getHolidays(d.year, holidayRegion); return map[DateFormat('yyyy-MM-dd').format(d)]??''; }

@override void initState(){ super.initState(); nameCtrl.text=customName; load().then(() async { await Future.delayed(const Duration(milliseconds:500)); bool ok = await handleCalendarPermission(silent:false); if(!ok && mounted){ ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('需要日曆權限才能讀取日曆，請在設定中允許'))); } }); }
Future<void> load() async{
var sp=await SharedPreferences.getInstance();
var r=sp.getString('roster'); if(r!=null) roster=Map<String,String>.from(jsonDecode(r));
var rn=sp.getString('note'); if(rn!=null) rosterNote=Map<String,String>.from(jsonDecode(rn));
var rt=sp.getString('extraType'); if(rt!=null) rosterExtraType=Map<String,String>.from(jsonDecode(rt));
var ro=sp.getString('roOt'); if(ro!=null){ try{ rosterOt=Map<String,double>.from((jsonDecode(ro) as Map).map((k,v)=>MapEntry(k as String,(v as num).toDouble()))); }catch(){} }
var re=sp.getString('roEx'); if(re!=null){ try{ rosterExtra=Map<String,double>.from((jsonDecode(re) as Map).map((k,v)=>MapEntry(k as String,(v as num).toDouble()))); }catch(){} }
var reh=sp.getString('roExH'); if(reh!=null){ try{ rosterExtraHrs=Map<String,double>.from((jsonDecode(reh) as Map).map((k,v)=>MapEntry(k as String,(v as num).toDouble()))); }catch(){} }
var d=sp.getString('defs'); if(d!=null){ try{ var m=Map<String,dynamic>.from(jsonDecode(d)); defs=m.map((k,v)=>MapEntry(k,ShiftDef.fromJson(Map<String,dynamic>.from(v)))); }catch(){} }
var p=sp.getString('pattern'); if(p!=null){ try{ var l=jsonDecode(p) as List; pattern=l.map<List<String>>((row)=>(row as List).map<String>((e)=>e.toString()).toList()).toList(); }catch(){} }
var ea=sp.getString('extraAllowNewV36'); if(ea!=null){ try{ extraAllowances=(jsonDecode(ea) as List).map((e)=>ExtraAllowance.fromJson(Map<String,dynamic>.from(e))).toList(); }catch(){} }
var spSaved=sp.getString('savedPatternsV40'); if(spSaved!=null){ try{ savedPatterns=(jsonDecode(spSaved) as List).map((e)=>SavedPattern.fromJson(Map<String,dynamic>.from(e))).toList(); }catch(){} }
var evMap=sp.getString('googleEventIdMap'); if(evMap!=null){ try{ googleEventIdMap=Map<String,String>.from(jsonDecode(evMap)); }catch(){} }
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
if(autoSync && googleSyncEnabled &&!isSyncing){ syncToGoogle(silent:true); }
}
int isoWeek(DateTime date){ DateTime thursday=date.add(Duration(days:4-date.weekday)); DateTime jan1=DateTime(thursday.year,1,1); int days=thursday.difference(jan1).inDays; return 1+(days/7).floor(); }
void quickJumpMonth({bool forReport=false}){ int y=focused.year; int m=focused.month; showDialog(context:context,builder:(ctx){ return StatefulBuilder(builder:(ctx2,setD){ return AlertDialog(title:Text(forReport?'選擇報表年月':'快速查找年月'),content:Column(mainAxisSize:MainAxisSize.min,children:[Row(children:[IconButton(icon:const Icon(Icons.remove),onPressed:()=>setD(()=>y--)),Expanded(child:Text('{y}年',textAlign:TextAlign.center,style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold))),IconButton(icon:const Icon(Icons.add),onPressed:()=&gt;setD(()=&gt;y++))]),Wrap(spacing:8,children:List.generate(12,(i){ int mon=i+1; return ChoiceChip(label:Text('{mon}月'),selected:mon==m,onSelected:()=>setD(()=>m=mon)); }))]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx2),child:const Text('取消')),FilledButton(onPressed:(){ setState(()=>focused=DateTime(y,m,1)); Navigator.pop(ctx2); },child:const Text('跳轉'))]); }); }); }
Future<bool> handleCalendarPermission({bool silent=false}) async {
try{
var s1 = await Permission.calendar.request();
var s2 = await Permission.calendarFullAccess.request();
var s3 = await Permission.calendarWriteOnly.request();
if(s1.isGranted || s2.isGranted || s3.isGranted) return true;
if(!silent && s1.isPermanentlyDenied){
await showDialog(context:context, builder:(ctx)=>AlertDialog(title:const Text('需要日曆權限'), content:const Text('新安裝App需允許存取日曆才能讀取，否則顯示空白(0)。請去設定>權限>允許日曆'), actions:[TextButton(onPressed:()=>Navigator.pop(ctx), child:const Text('取消')), FilledButton(onPressed:(){ openAppSettings(); Navigator.pop(ctx); }, child:const Text('去設定'))]));
}
}catch(){}
try{
var devHas = await calendarPlugin.hasPermissions();
if (devHas.isSuccess && devHas.datatrue) return true;
var devReq = await _calendarPlugin.requestPermissions();
if(devReq.isSuccess && devReq.datatrue) return true;
}catch(){}
return false;
}
Future<List<Map<String,dynamic>>> _getRealCalendars() async {
try {
var res = await _realChannel.invokeMethod('getCalendars');
return (res as List).map((e)=>Map<String,dynamic>.from(e as Map)).toList();
} catch(e){
try{
var r = await calendarPlugin.retrieveCalendars();
return (r.data??[]).map((c)=>{'id':c.id,'displayName':c.name,'accountName':c.accountName,'isGoogle':(c.accountName??'').contains('gmail')||(c.accountType??'').contains('google')}).toList();
}catch(){ return []; }
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
title: Text('選擇寫入日曆 真ID版 ( {googleCals.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
...googleCals.map((cal)=>Card(color: Colors.green.withOpacity(0.15), child: ListTile(leading: const Icon(Icons.cloud_done, color: Colors.green),title: Text(' {cal['accountName']}\nID:  {otherCals.length})'),
...otherCals.map((cal)=>Card(child: ListTile(leading: const Icon(Icons.phone_android),title: Text(' {cal['accountName']}', style: const TextStyle(fontSize:9)),onTap: ()=>Navigator.pop(ctx, cal),))),
])),
actions: [TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('取消'))],
);
});
if(pickedMap!=null && pickedMap['id']!=null){
_rosterCalendarId = pickedMap['id'].toString(); _rosterCalendarName = pickedMap['displayName'].toString(); _rosterAccountName = pickedMap['accountName'].toString();
var sp=await SharedPreferences.getInstance(); sp.setString('rosterCalId', _rosterCalendarId!); sp.setString('rosterCalName', _rosterCalendarName); sp.setString('rosterAccName', _rosterAccountName);
setState((){}); if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('已選 latex
_rosterCalendarId'))); return _rosterCalendarId; } return null; } Future&lt;void&gt; _requestGooglePerm() async{ String? id = await _pickGoogleCalendarDialog(); if(id==null) return; bool? ok=await showDialog&lt;bool&gt;(context:context,builder:(ctx)=&gt;AlertDialog(title:const Text('已選擇真 Google 日曆'),content:Text('將寫入：

_rosterCalendarName\nID: $`id\n已開啟記事同步'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('稍後')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('立即同步'))]));
if(ok==true){ setState(()=>googleSyncEnabled=true); await _syncToGoogle(); save(); }
}
Future<void> _ensureCalendar() async{ if(_rosterCalendarId!=null && _rosterCalendarId!.isNotEmpty) return; await _pickGoogleCalendarDialog(); }

Future<void> _syncToGoogle({bool silent=false}) async{
if(!googleSyncEnabled &&!silent){
bool? en = await showDialog<bool>(context: context, builder: (ctx)=>AlertDialog(title:const Text('未開啟同步'), content:const Text('是否開啟同步並立即寫入？'), actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false), child:const Text('取消')), FilledButton(onPressed:()=>Navigator.pop(ctx,true), child:const Text('開啟並同步'))]));
if(entrue) setState(()=>googleSyncEnabled=true); else return;
}
if(_isSyncing) return; _isSyncing=true;
if(!silent) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('開始同步，正在去重以 [RosterPro]yyyy-MM-dd...')));
try{
if(_rosterCalendarIdnull || _rosterCalendarId!.isEmpty) await _ensureCalendar();
if(_rosterCalendarIdnull || _rosterCalendarId!.isEmpty) throw '未選真 Google 日曆';
var existingEvents=await _calendarPlugin.retrieveEvents(_rosterCalendarId!, RetrieveEventsParams(startDate: DateTime(2023,1,1), endDate: DateTime(2035,12,31)));
int del=0;
for(var e in existingEvents.data??[]){ if((e.description??'').contains('[RosterPro]')){ await _calendarPlugin.deleteEvent(_rosterCalendarId!, e.eventId); del++; } }
_googleEventIdMap.clear();
int add=0;
for(var entry in roster.entries){
var code=entry.value; var def=defs[code]; if(defnull) continue;
DateTime date=DateFormat('yyyy-MM-dd').parse(entry.key);
String note = rosterNote[entry.key]??'';
String extraType = rosterExtraType[entry.key]??'';
String tag='[RosterPro]${entry.key}'; String desc='$tag\n$customName\n排更: ${def.label}\n時間: ${def.isAllDay?'全天':'${def.start}-${def.end}'} ${def.hours}h\nOT: ${rosterOt[entry.key]??0}h\n津貼: ${def.hasAllowance?'${def.allowance}':''} 額外\${rosterExtra[entry.key]??0} 類別:$extraType\n記事: ${note.isEmpty?'無':note}\n日期: ${entry.key}${isHoliday(date)?'\n假期: ${holidayName(date)}':''}'; Event ev; if(def.isAllDay || def.code=='O'){ ev=Event(_rosterCalendarId!, title:'${def.code} `${extraType.isNotEmpty?'[$extraType]':''}', description:desc, start:tz.TZDateTime(tz.local,date.year,date.month,date.day), end:tz.TZDateTime(tz.local,date.year,date.month,date.day+1), allDay:true);
}else{
DateTime s=DateTime(date.year,date.month,date.day,int.parse(def.start.split(':')[0]),int.parse(def.start.split(':')[1]));
DateTime ee=DateTime(date.year,date.month,date.day,int.parse(def.end.split(':')[0]),int.parse(def.end.split(':')[1]));
if(ee.isBefore(s)) ee=ee.add(const Duration(days:1));
ev=Event(_rosterCalendarId!, title:' {def.start}- {note.isNotEmpty?' | latex
note':''}

{extraType.isNotEmpty?' | latex
extraType':''}', description:desc, start:tz.TZDateTime.from(s,tz.local), end:tz.TZDateTime.from(ee,tz.local), allDay:false); } var res=await _calendarPlugin.createOrUpdateEvent(ev); if(res!=null && res.isSuccess && res.data!=null){ _googleEventIdMap[entry.key]=res.data!; add++; } } var sp=await SharedPreferences.getInstance(); sp.setString('googleEventIdMap',jsonEncode(_googleEventIdMap)); updateWidget(); if(!silent && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('已寫入 

_rosterCalendarName 刪 add 項，去重 [RosterPro]yyyy-MM-dd 全天 allDay:true 含記事和類別')));
}catch(e){ if(!silent && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('同步失敗 $`e'))); }
finally { _isSyncing=false; }
}

Future<void> clearRosterByRange() async{
DateTimeRange? range=await showDateRangePicker(context:context, firstDate: DateTime(2023), lastDate: DateTime(2035), helpText: '選擇要清除的排更範圍');
if(range==null) return; int count=0;
for(DateTime d=range.start;!d.isAfter(range.end); d=d.add(const Duration(days:1))){
String k=DateFormat('yyyy-MM-dd').format(d);
if(roster.containsKey(k)){ count++; roster.remove(k); rosterOt.remove(k); rosterExtra.remove(k); rosterExtraHrs.remove(k); rosterExtraType.remove(k); if(_googleEventIdMap.containsKey(k) && _rosterCalendarId!=null){ try{ await _calendarPlugin.deleteEvent(_rosterCalendarId!, googleEventIdMap[k]); }catch(){} _googleEventIdMap.remove(k); } }
}
await save(); setState((){}); if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('已清除 `$count 天排更，記事保留')));
}

Future<void> shareScreenshotDialog() async{ exportShareImage(); }
Future<void> exportShareImage() async{
try{
RenderRepaintBoundary? b=calKey.currentContext?.findRenderObject() as RenderRepaintBoundary?; ui.Image? calImg; if(b!=null){ calImg=await b.toImage(pixelRatio:3); }
final recorder=ui.PictureRecorder(); final canvas=Canvas(recorder); double width=1080; double y=0; final paintWhite=Paint()..color=Colors.white;
double calHeight = calImg!=null? width * calImg.height / calImg.width : 0;
Set<String> usedCodes={}; int dim=DateTime(focused.year,focused.month+1,0).day; for(int i=1;i<=dim;i++){ String k=DateFormat('yyyy-MM-dd').format(DateTime(focused.year,focused.month,i)); if(roster[k]!=null) usedCodes.add(roster[k]!); }
List<ShiftDef> legendDefs= defs.entries.where((e)=>usedCodes.contains(e.key)).map((e)=>e.value).toList();
double legendHeight = legendDefs.length*44 + 80; double totalHeight = calHeight + legendHeight + 40;
canvas.drawRect(Rect.fromLTWH(0,0,width,totalHeight), paintWhite);
if(calImg!=null){ canvas.drawImageRect(calImg, Rect.fromLTWH(0,0,calImg.width.toDouble(),calImg.height.toDouble()), Rect.fromLTWH(0,0,width,calHeight), Paint()); y=calHeight+16; }
TextPainter tp=TextPainter(textDirection: ui.TextDirection.ltr);
tp.text=TextSpan(text:'班次詳細時間圖例 (本月使用)：',style: TextStyle(color:Colors.black,fontSize:32,fontWeight:FontWeight.bold)); tp.layout(maxWidth:width); tp.paint(canvas, Offset(24,y)); y+=54;
for(var v in legendDefs){
canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(24,y,32,32), const Radius.circular(8)), Paint()..color=v.color);
tp.text=TextSpan(text:'  {v.label} latex
{v.isAllDay?'全天':'

{v.start}-latex
{v.end}'} 

{v.hours.toStringAsFixed(1)}hlatex
{v.hasAllowance?' 津貼\

{v.allowance}':''}',style: const TextStyle(color:Colors.black87,fontSize:28,fontWeight:FontWeight.w600)); tp.layout(maxWidth:width-80); tp.paint(canvas, Offset(64,y)); y+=46;
}
final pic=recorder.endRecording(); final img=await pic.toImage(width.toInt(), (y+20).toInt()); final byte=await img.toByteData(format: ui.ImageByteFormat.png); final png=byte!.buffer.asUint8List();
Directory baseDir=Directory('/storage/emulated/0/Pictures/Roster'); if(!await baseDir.exists()){ await baseDir.create(recursive:true); }
String path='latex
{baseDir.path}/roster_month_

{focused.year}latex
{focused.month}_

{DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.png';
File f=File(path); await f.writeAsBytes(png);
if(mounted){
ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('截圖已保存  {focused.year}年 customName');
}
}catch(e){ if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('截圖失敗 latex
e'))); } } Future&lt;void&gt; backupAnywhere() async{ String? dir=await FilePicker.platform.getDirectoryPath(dialogTitle:'選擇備份位置'); if(dir==null) return; String fileName='roster_pro_full_

{DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.json';
var backup = {'version':'7.1','exportTime':DateTime.now().toIso8601String(),'roster':roster,'note':rosterNote,'extraType':rosterExtraType,'roOt':rosterOt,'roEx':rosterExtra,'roExH':rosterExtraHrs,'defs':defs.map((k,v)=>MapEntry(k,v.toJson())),'pattern':pattern,'carry':carry,'cName':customName,'stdWeek':standardWeeklyHours,'otRate':overtimeRate,'extraNewV36':extraAllowances.map((e)=>e.toJson()).toList(),'calFont':calendarFontSize,'savedPatterns':savedPatterns.map((e)=>e.toJson()).toList(),'holidayRegion':holidayRegion,'rosterCalId':_rosterCalendarId,'rosterCalName':_rosterCalendarName,'rosterAccName':_rosterAccountName,'googleEventIdMap':_googleEventIdMap,'gSync':googleSyncEnabled,'gAuto':autoSync,'todayBg':todayBgColor.value,'todayBorder':todayBorderColor.value};
var f=File(' fileName'); await f.writeAsString(jsonEncode(backup));
setState(()=>_lastBackupPath=' fileName'); await save();
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
if(j['roEx']!=null) rosterExtra=Map<String,double>.from((j['roEx'] as Map).map((k,v)=>MapEntry(k as String,(v as num).toDouble()));
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
});save(); if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('還原成功'))); }catch(e){ if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('還原失敗 latex
e'))); } } Future&lt;void&gt; exportReport() async{ StringBuffer sb=StringBuffer(); if(!isYearReport){ int dim=DateTime(focused.year,focused.month+1,0).day; double hrs=0,ot=0; double allow=0; Map&lt;String,int&gt; shiftCount={}; Map&lt;String,double&gt; extraByType={}; for(int i=1;i&lt;=dim;i++){ DateTime dt=DateTime(focused.year,focused.month,i); String k=DateFormat('yyyy-MM-dd').format(dt); String? c=roster[k]; if(c==null) continue; var d=defs[c]; if(d!=null){ hrs+=d.hours; shiftCount[c]=(shiftCount[c]??0)+1; if(d.hasAllowance) allow+=d.allowance; } ot+=(rosterOt[k]??d?.ot??0); allow+=(rosterExtra[k]??0); if(rosterExtraType.containsKey(k) && rosterExtra.containsKey(k)){ extraByType[rosterExtraType[k]!]=(extraByType[rosterExtraType[k]!]??0)+rosterExtra[k]!; } hrs+=(rosterExtraHrs[k]??0); } sb.writeln('

{focused.year}年 k  t :  hrs OT  {allow+ot*overtimeRate}');
}else{
sb.writeln('latex
{focused.year}年 全年統計'); for(int mon=1;mon&lt;=12;mon++){ int dim=DateTime(focused.year,mon+1,0).day; double hrs=0; for(int d=1;d&lt;=dim;d++){ DateTime dt=DateTime(focused.year,mon,d); String k=DateFormat('yyyy-MM-dd').format(dt); String? c=roster[k]; if(c==null) continue; var def=defs[c]; if(def!=null) hrs+=def.hours; } sb.writeln('

mon月 latex
{hrs}h'); } } String? path=await FilePicker.platform.saveFile(dialogTitle:'匯出報表',fileName:'report_

{isYearReport?'year {focused.year}latex
{focused.month}'}.csv',type:FileType.custom,allowedExtensions:['csv','txt']); if(path!=null){ await File(path).writeAsString(sb.toString()); if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('已匯出 

path'))); }
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
Padding(padding:const EdgeInsets.fromLTRB(12,8,12,4),child:Row(children:[InkWell(onTap:()=>quickJumpMonth(),child:Row(children:[Text('${focus
ed.year}年latex
{focused.month}月',style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const Icon(Icons.arrow_drop_down)])),const Spacer(),IconButton(icon:const Icon(Icons.camera_alt_outlined),tooltip:'整月截圖分享',onPressed:shareScreenshotDialog),IconButton(icon:const Icon(Icons.chevron_left),onPressed:(){ setState(()=&gt;focused=DateTime(focused.year,focused.month-1,1)); }),IconButton(icon:const Icon(Icons.chevron_right),onPressed:(){ setState(()=&gt;focused=DateTime(focused.year,focused.month+1,1)); }),FilledButton.tonal(onPressed:(){ setState((){ focused=DateTime(today.year,today.month,1); selectedDay=DateTime(today.year,today.month,today.day); }); },child:const Text('今天')),])), Expanded( child: RepaintBoundary( key: calKey, child: Column( children:[ Padding(padding:const EdgeInsets.symmetric(horizontal:6),child:Row(children:[Container(width:32,child:const Text('週',textAlign:TextAlign.center,style:TextStyle(fontWeight:FontWeight.bold,fontSize:11,color:Colors.deepPurple))),Expanded(child:Row(children:["一","二","三","四","五","六","日"].map((w)=&gt;Expanded(child:Text(w,textAlign:TextAlign.center,style:const TextStyle(fontSize:11)))).toList()))])), Expanded( child: ListView.builder( shrinkWrap:true, physics:const NeverScrollableScrollPhysics(), padding:EdgeInsets.zero, itemCount:weeks, itemBuilder:(ctx,row){ return Row( children:[ Container(width:32,alignment:Alignment.center,child:Text('W

{isoWeek(days[row*7])}',style:const TextStyle(fontSize:11,color:Colors.deepPurple,fontWeight:FontWeight.bold))),
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
bool inM=day.monthfocused.month;
String k=DateFormat('yyyy-MM-dd').format(day);
String? code=roster[k];
var def=code!=null?defs[code]:null;
bool sel=kselKey;
bool isToday = day.yeartoday.year && day.monthtoday.month && day.day==today.day;
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
Text('latex
{day.day}',style:TextStyle(fontWeight:isToday?FontWeight.w900:FontWeight.bold,fontSize:calendarFontSize-1,color:inM?Colors.black:Colors.grey)), if(code!=null) FittedBox(child:Container(margin:const EdgeInsets.only(top:1),padding:const EdgeInsets.symmetric(horizontal:4,vertical:1),decoration:BoxDecoration(color:def?.color??Colors.orange,borderRadius:BorderRadius.circular(8)),child:Text(code,style:TextStyle(color:Colors.white,fontSize:calendarFontSize-2)))), const SizedBox(height:2), Row(mainAxisAlignment:MainAxisAlignment.center,children:[if(isHol) Container(width:6,height:6,margin:const EdgeInsets.symmetric(horizontal:1),decoration:BoxDecoration(color:holidayDotColor,shape:BoxShape.circle)),if(hasNote) Container(width:6,height:6,margin:const EdgeInsets.symmetric(horizontal:1),decoration:const BoxDecoration(color:Colors.blue,shape:BoxShape.circle)),]), ] ) ) ); } ) ) ] ); } ) ) ] ) ) ), Container(width:double.infinity,padding:const EdgeInsets.fromLTRB(12,12,12,16),decoration:const BoxDecoration(color:Colors.white,border:Border(top:BorderSide(color:Color(0xFFE0E0E0)))),child:Column( crossAxisAlignment:CrossAxisAlignment.start, children:[ Row(children:[ Expanded(child:Text('

{roster[selKey]??'未排班'}latex
{isHoliday(selectedDay)?' [

{holidayName(selectedDay)}]':''} latex
{extraType.isNotEmpty?'[

extraType]':''}',style:const TextStyle(fontSize:16,fontWeight:FontWeight.bold),overflow:TextOverflow.ellipsis)),
const SizedBox(width:8),
if(selDef!=null) Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:3),decoration:BoxDecoration(color:selDef.color,borderRadius:BorderRadius.circular(10)),child:Text(selDef.code,style:const TextStyle(color:Colors.white,fontSize:11,fontWeight:FontWeight.bold))),
const SizedBox(width:8),
FilledButton.tonalIcon(onPressed:(){ showDetail(selectedDay); },icon:const Icon(Icons.edit,size:16),label:const Text('編輯',style:TextStyle(fontSize:12)),style: FilledButton.styleFrom(minimumSize:const Size(0,36),padding:const EdgeInsets.symmetric(horizontal:12))),
]),
const SizedBox(height:10),
Container(width:double.infinity,padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:const Color(0xFFF5F5F5),borderRadius:BorderRadius.circular(12)),child:Column(
crossAxisAlignment:CrossAxisAlignment.start,
children:[
Text('1. 班次：latex
{selDef!=null?'(

{selDef.code}) latex
{selDef.label}':''} 

{isHoliday(selectedDay)?'[latex
{holidayName(selectedDay)}]':''}',style:const TextStyle(fontSize:13,fontWeight:FontWeight.bold)), const SizedBox(height:4), Text('2. 時間：

{selDef!=null?(selDef.isAllDay?'全天':' {selDef.end}'):''} | 工時： {selDef!=null && selDef.hasAllowance?'有 latex
{selDef.allowance}':'無'} + 單日 \

{rosterExtra[selKey]??0} latex
{extraType.isNotEmpty?'類別:

extraType':''}',style:const TextStyle(fontSize:12)),
const SizedBox(height:4),
Text('4. OT： {(rosterExtraHrs[selKey]??0).toStringAsFixed(1)}h',style:const TextStyle(fontSize:12)),
const SizedBox(height:4),
Text('5. 記事：$`{note.isEmpty?'無':note}',style:const TextStyle(fontSize:12,fontWeight:FontWeight.bold,color: Colors.deepPurple),maxLines:3,overflow:TextOverflow.ellipsis),
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
showModalBottomSheet(context:context,isScrollControlled:true,builder:(ctx){ return StatefulBuilder(builder:(ctx2,setM){ return Padding(padding:EdgeInsets.only(bottom:MediaQuery.of(ctx2).viewInsets.bottom),child:Padding(padding:const EdgeInsets.all(16),child:Column(mainAxisSize:MainAxisSize.min,children:[Text('${DateFormat('yyyy-MM-dd EEE').format(day)} ${isHoliday(day)?' [`${holidayName(day)}]':''}',style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),Wrap(spacing:8,children:defs.keys.map((c)=>ChoiceChip(label:Text(c),selected:cur==c,onSelected:(_)=>setM(()=>cur=c))).toList()),SizedBox(height:56, child:TextField(controller:nc,decoration:const InputDecoration(labelText:'記事 (會同步到Google日曆標題+描述)',isDense:true,border:OutlineInputBorder()))),Row(children:[Expanded(child:SizedBox(height:56, child:TextField(controller:otc,decoration:const InputDecoration(labelText:'OT時數',isDense:true,border:OutlineInputBorder()),keyboardType:TextInputType.number))),const SizedBox(width:8),Expanded(child:SizedBox(height:56, child:TextField(controller:exHCtrl,decoration:const InputDecoration(labelText:'額外工時',isDense:true,border:OutlineInputBorder()),keyboardType:TextInputType.number))),]),Row(children:[Expanded(child:SizedBox(height:56, child:TextField(controller:exCtrl,decoration:const InputDecoration(labelText:'額外津貼',isDense:true,border:OutlineInputBorder()),keyboardType:TextInputType.number))),const SizedBox(width:8),Expanded(child:SizedBox(height:56, child:TextField(controller:exTypeCtrl,decoration:const InputDecoration(labelText:'津貼類別 (例:大假津貼)',isDense:true,border:OutlineInputBorder())))),]),const SizedBox(height:12),Row(children:[Expanded(child:OutlinedButton(onPressed:() async { setState((){ roster.remove(k); rosterOt.remove(k); rosterExtra.remove(k); rosterExtraHrs.remove(k); rosterExtraType.remove(k); }); if(_googleEventIdMap.containsKey(k) && _rosterCalendarId!=null){ try{ await _calendarPlugin.deleteEvent(_rosterCalendarId!, googleEventIdMap[k]); }catch(){} _googleEventIdMap.remove(k); } save(); Navigator.pop(ctx2); },child:const Text('清除班次(保留記事)',style:TextStyle(color: Colors.orange)),)),const SizedBox(width:8),Expanded(child:FilledButton(onPressed:(){ double? otVal=double.tryParse(otc.text); double? exVal=double.tryParse(exCtrl.text); double? exHVal=double.tryParse(exHCtrl.text); setState((){ if(cur.isNotEmpty) roster[k]=cur; if(nc.text.isNotEmpty) rosterNote[k]=nc.text; else rosterNote.remove(k); if(exTypeCtrl.text.isNotEmpt
