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
String get detailTime=>isAllDay?'全天':'$start-$end ${hours.toStringAsFixed(1)}h';
}
class ExtraAllowance { String name; double amount; ExtraAllowance(this.name,this.amount); Map<String,dynamic> toJson()=>{'name':name,'amount':amount}; factory ExtraAllowance.fromJson(Map<String,dynamic> j)=>ExtraAllowance(j['name'],(j['amount'] as num).toDouble()); }
class SavedPattern { String name; List<List<String>> data; SavedPattern(this.name,this.data); Map<String,dynamic> toJson()=>{'name':name,'data':data}; factory SavedPattern.fromJson(Map<String,dynamic> j)=>SavedPattern(j['name'],(j['data'] as List).map<List<String>>((r)=>(r as List).map<String>((e)=>e.toString()).toList()).toList()); }

class RosterApp extends StatelessWidget{ const RosterApp({super.key}); @override Widget build(BuildContext context){ return MaterialApp(title:'Roster Pro v7.0',theme:ThemeData(useMaterial3:true,colorSchemeSeed:Colors.deepPurple),home:const MainPage()); } }

class MainPage extends StatefulWidget{ const MainPage({super.key}); @override State<MainPage> createState()=>MainPageState(); }
class MainPageState extends State<MainPage>{
int tab=0; DateTime focused=DateTime.now(); DateTime selectedDay=DateTime.now();
Map<String,String> roster={}; Map<String,String> rosterNote={}; Map<String,double> rosterOt={}; Map<String,double> rosterExtra={}; Map<String,double> rosterExtraHrs={};
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
DeviceCalendarPlugin _calendarPlugin=DeviceCalendarPlugin();
String? _rosterCalendarId; String _rosterCalendarName='未選'; String _rosterAccountName='';
Map<String,String> _googleEventIdMap={};
Future<void> updateWidget() async{ try{ String todayKey=DateFormat('yyyy-MM-dd').format(DateTime.now()); String tomorrowKey=DateFormat('yyyy-MM-dd').format(DateTime.now().add(const Duration(days:1))); await HomeWidget.saveWidgetData('today_code', roster[todayKey]??'O'); await HomeWidget.saveWidgetData('tomorrow_code', roster[tomorrowKey]??'O'); await HomeWidget.saveWidgetData('note', rosterNote[todayKey]??''); await HomeWidget.updateWidget(androidName:'RosterWidgetProvider'); }catch(_){} }

bool _isSyncing=false;
String _lastBackupPath='未備份'; Color todayBgColor=const Color(0xFFFFF9C4); Color todayBorderColor=Colors.orange; Color holidayDotColor=Colors.red;

Map<String,String> getHolidays(int year,String region){
Map<String,String> m={}; if(region=='無') return m;
if(region=='香港'){ m['$year-01-01']='元旦'; m['$year-05-01']='勞動節'; m['$year-07-01']='回歸'; m['$year-10-01']='國慶'; m['$year-12-25']='聖誕'; if(year==2026){ m.addAll({'2026-02-17':'初一','2026-02-18':'初二','2026-02-19':'初三','2026-04-05':'清明','2026-05-24':'佛誕','2026-06-19':'端午'}); } }
return m;
}
bool isHoliday(DateTime d){ return getHolidays(d.year,holidayRegion).containsKey(DateFormat('yyyy-MM-dd').format(d)); }
String holidayName(DateTime d){ return getHolidays(d.year,holidayRegion)[DateFormat('yyyy-MM-dd').format(d)]??''; }

@override void initState(){ super.initState(); nameCtrl.text=customName; load().then((_){ handleCalendarPermission(silent:true); }); }
Future<void> load() async{
var sp=await SharedPreferences.getInstance();
var r=sp.getString('roster'); if(r!=null) roster=Map<String,String>.from(jsonDecode(r));
var rn=sp.getString('note'); if(rn!=null) rosterNote=Map<String,String>.from(jsonDecode(rn));
var ro=sp.getString('roOt'); if(ro!=null) try{ rosterOt=Map<String,double>.from((jsonDecode(ro) as Map).map((k,v)=>MapEntry(k as String,(v as num).toDouble())));}catch(_){}
var re=sp.getString('roEx'); if(re!=null) try{ rosterExtra=Map<String,double>.from((jsonDecode(re) as Map).map((k,v)=>MapEntry(k as String,(v as num).toDouble())));}catch(_){}
var reh=sp.getString('roExH'); if(reh!=null) try{ rosterExtraHrs=Map<String,double>.from((jsonDecode(reh) as Map).map((k,v)=>MapEntry(k as String,(v as num).toDouble())));}catch(_){}
var d=sp.getString('defs'); if(d!=null) try{ defs=Map<String,dynamic>.from(jsonDecode(d)).map((k,v)=>MapEntry(k,ShiftDef.fromJson(Map<String,dynamic>.from(v))));}catch(_){}
var p=sp.getString('pattern'); if(p!=null) try{ pattern=(jsonDecode(p) as List).map<List<String>>((row)=>(row as List).map<String>((e)=>e.toString()).toList()).toList();}catch(_){}
var ea=sp.getString('extraAllowNewV36'); if(ea!=null) try{ extraAllowances=(jsonDecode(ea) as List).map((e)=>ExtraAllowance.fromJson(Map<String,dynamic>.from(e))).toList();}catch(_){}
var spSaved=sp.getString('savedPatternsV40'); if(spSaved!=null) try{ savedPatterns=(jsonDecode(spSaved) as List).map((e)=>SavedPattern.fromJson(Map<String,dynamic>.from(e))).toList();}catch(_){}
var evMap=sp.getString('googleEventIdMap'); if(evMap!=null) try{ _googleEventIdMap=Map<String,String>.from(jsonDecode(evMap));}catch(_){}
setState((){
carry=sp.getDouble('carry')??0; customName=sp.getString('cName')??'我的排更-專屬日曆'; nameCtrl.text=customName;
standardWeeklyHours=sp.getDouble('stdWeek')??42; overtimeRate=sp.getDouble('otRate')??80;
calendarFontSize=sp.getDouble('calFont')??14; googleSyncEnabled=sp.getBool('gSync')??false; autoSync=sp.getBool('gAuto')??false;
holidayRegion=sp.getString('holidayRegion')??'香港'; _rosterCalendarId=sp.getString('rosterCalId');
_rosterCalendarName=sp.getString('rosterCalName')??'未選'; _lastBackupPath=sp.getString('lastBackupPath')??'未備份';
todayBgColor=Color(sp.getInt('todayBg')??0xFFFFF9C4); todayBorderColor=Color(sp.getInt('todayBorder')??0xFFFF9800);
});
updateWidget();
}
Future<void> save() async{
var sp=await SharedPreferences.getInstance();
sp.setString('roster',jsonEncode(roster)); sp.setString('note',jsonEncode(rosterNote)); sp.setString('roOt',jsonEncode(rosterOt));
sp.setString('roEx',jsonEncode(rosterExtra)); sp.setString('roExH',jsonEncode(rosterExtraHrs));
sp.setString('defs',jsonEncode(defs.map((k,v)=>MapEntry(k,v.toJson())))); sp.setString('pattern',jsonEncode(pattern));
sp.setDouble('carry',carry); sp.setString('cName',customName); sp.setDouble('stdWeek',standardWeeklyHours);
sp.setDouble('otRate',overtimeRate); sp.setString('extraAllowNewV36',jsonEncode(extraAllowances.map((e)=>e.toJson()).toList()));
sp.setDouble('calFont',calendarFontSize); sp.setBool('gSync',googleSyncEnabled); sp.setBool('gAuto',autoSync);
sp.setString('savedPatternsV40',jsonEncode(savedPatterns.map((e)=>e.toJson()).toList())); sp.setString('holidayRegion',holidayRegion);
sp.setString('googleEventIdMap',jsonEncode(_googleEventIdMap));
if(_rosterCalendarId!=null) sp.setString('rosterCalId',_rosterCalendarId!);
sp.setString('rosterCalName',_rosterCalendarName); sp.setString('lastBackupPath',_lastBackupPath);
sp.setInt('todayBg',todayBgColor.value); sp.setInt('todayBorder',todayBorderColor.value);
updateWidget();
if(autoSync&&googleSyncEnabled&&!_isSyncing){ _syncToGoogle(silent:true); }
}
int isoWeek(DateTime date){ DateTime th=date.add(Duration(days:4-date.weekday)); DateTime jan1=DateTime(th.year,1,1); return 1+(th.difference(jan1).inDays/7).floor(); }
void quickJumpMonth({bool forReport=false}){
int y=focused.year,m=focused.month;
showDialog(context:context,builder:(ctx){ return StatefulBuilder(builder:(ctx2,setD){ return AlertDialog(title:Text(forReport?'選擇報表年月':'快速查找年月'),content:Column(mainAxisSize:MainAxisSize.min,children:[Row(children:[IconButton(icon:const Icon(Icons.remove),onPressed:()=>setD(()=>y--)),Expanded(child:Text('$y年',textAlign:TextAlign.center,style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold))),IconButton(icon:const Icon(Icons.add),onPressed:()=>setD(()=>y++))]),Wrap(spacing:8,children:List.generate(12,(i){ int mon=i+1; return ChoiceChip(label:Text('${mon}月'),selected:mon==m,onSelected:(_)=>setD(()=>m=mon)); }))]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx2),child:const Text('取消')),FilledButton(onPressed:(){ setState(()=>focused=DateTime(y,m,1)); Navigator.pop(ctx2); },child:const Text('跳轉'))]); }); });
}
Future<bool> handleCalendarPermission({bool silent=false}) async{
try{ await Permission.calendar.request(); }catch(_){} try{ await Permission.calendarFullAccess.request(); }catch(_){}
var devHas=await _calendarPlugin.hasPermissions(); if(devHas.isSuccess&&devHas.data==true) return true;
var devReq=await _calendarPlugin.requestPermissions(); return devReq.isSuccess&&devReq.data==true;
}
Future<String?> _pickGoogleCalendarDialog() async{
await handleCalendarPermission(silent:true);
var calsResult=await _calendarPlugin.retrieveCalendars(); var cals=calsResult.data??[];
var writable=cals.where((c)=>c.isReadOnly==false).toList();
var list=writable.isNotEmpty?writable:cals;
Calendar? picked=await showDialog<Calendar>(context:context,builder:(ctx){
return AlertDialog(title:Text('選擇日曆 (可寫${writable.length})'),content:SizedBox(width:420,height:420,child:ListView.builder(itemCount:list.length,itemBuilder:(c,i){ var cal=list[i]; return ListTile(title:Text(cal.name??'未命名'),subtitle:Text(cal.accountName??''),onTap:()=>Navigator.pop(ctx,cal)); })),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('取消'))]);
});
if(picked!=null){ _rosterCalendarId=picked.id; _rosterCalendarName=picked.name??'未命名'; _rosterAccountName=picked.accountName??''; var sp=await SharedPreferences.getInstance(); sp.setString('rosterCalId',_rosterCalendarId!); sp.setString('rosterCalName',_rosterCalendarName); setState((){}); }
return picked?.id;
}
Future<void> _requestGooglePerm() async{ String? id=await _pickGoogleCalendarDialog(); if(id==null) return; setState(()=>googleSyncEnabled=true); await _syncToGoogle(); save(); }
Future<void> _ensureCalendar() async{ if(_rosterCalendarId!=null&&_rosterCalendarId!.isNotEmpty) return; await _pickGoogleCalendarDialog(); }

Future<void> _syncToGoogle({bool silent=false}) async{
if(!googleSyncEnabled &&!silent){
bool? en = await showDialog<bool>(context: context, builder: (ctx)=>AlertDialog(title:const Text('未開啟同步'), content:const Text('是否開啟同步並立即寫入？'), actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false), child:const Text('取消')), FilledButton(onPressed:()=>Navigator.pop(ctx,true), child:const Text('開啟並同步'))]));
if(en==true) setState(()=>googleSyncEnabled=true); else return;
}
if(_isSyncing) return; _isSyncing=true;
if(!silent) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('開始同步，正在去重以 [RosterPro]yyyy-MM-dd...')));
try{
if(_rosterCalendarId==null || _rosterCalendarId!.isEmpty) await _ensureCalendar();
if(_rosterCalendarId==null || _rosterCalendarId!.isEmpty) throw '未選真 Google 日曆';
var existingEvents=await _calendarPlugin.retrieveEvents(_rosterCalendarId!, RetrieveEventsParams(startDate: DateTime(2023,1,1), endDate: DateTime(2030,12,31)));
int del=0;
for(var e in existingEvents.data??[]){ if((e.description??'').contains('[RosterPro]')){ await _calendarPlugin.deleteEvent(_rosterCalendarId!, e.eventId); del++; } }
_googleEventIdMap.clear();
int add=0;
for(var entry in roster.entries){
var code=entry.value; var def=defs[code]; if(def==null) continue;
DateTime date=DateFormat('yyyy-MM-dd').parse(entry.key);
String note = rosterNote[entry.key]??'';
String tag='[RosterPro]${entry.key}';
String desc='$tag\n$customName\n排更: ${def.label}\n時間: ${def.isAllDay?'全天':'${def.start}-${def.end}'} ${def.hours}h\nOT: ${rosterOt[entry.key]??0}h\n津貼: ${def.hasAllowance?'${def.allowance}':''} 額外\$${rosterExtra[entry.key]??0}\n記事: ${note.isEmpty?'無':note}\n日期: ${entry.key}${isHoliday(date)?'\n假期: ${holidayName(date)}':''}\n同步: ${DateTime.now().toIso8601String()}';
Event ev;
if(def.isAllDay || def.code=='O'){
ev=Event(_rosterCalendarId!, title:'${def.code}', description:desc, start:tz.TZDateTime(tz.local,date.year,date.month,date.day), end:tz.TZDateTime(tz.local,date.year,date.month,date.day+1), allDay:true);
}else{
DateTime s=DateTime(date.year,date.month,date.day,int.parse(def.start.split(':')[0]),int.parse(def.start.split(':')[1]));
DateTime ee=DateTime(date.year,date.month,date.day,int.parse(def.end.split(':')[0]),int.parse(def.end.split(':')[1]));
if(ee.isBefore(s)) ee=ee.add(const Duration(days:1));
ev=Event(_rosterCalendarId!, title:'${def.code} ${def.start}-${def.end}${note.isNotEmpty?' | $note':''}', description:desc, start:tz.TZDateTime.from(s,tz.local), end:tz.TZDateTime.from(ee,tz.local), allDay:false);
}
var res=await _calendarPlugin.createOrUpdateEvent(ev); if(res!=null && res.isSuccess && res.data!=null){ _googleEventIdMap[entry.key]=res.data!; add++; }
}
var sp=await SharedPreferences.getInstance(); sp.setString('googleEventIdMap',jsonEncode(_googleEventIdMap));
updateWidget();
if(!silent && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('已寫入 $_rosterCalendarName 刪$del 加$add 項，去重 [RosterPro]yyyy-MM-dd 全天 allDay:true 含記事')));
}catch(e){ if(!silent && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('同步失敗 $e'))); }
finally { _isSyncing=false; }
}

Future<void> clearRosterByRange() async{
DateTimeRange? range=await showDateRangePicker(context:context,firstDate:DateTime(2023),lastDate:DateTime(2030),helpText:'選擇要清除的排更範圍');
if(range==null) return; int count=0;
for(DateTime d=range.start;!d.isAfter(range.end);d=d.add(const Duration(days:1))){
String k=DateFormat('yyyy-MM-dd').format(d);
if(roster.containsKey(k)){ count++; roster.remove(k); rosterOt.remove(k); rosterExtra.remove(k); rosterExtraHrs.remove(k); if(_googleEventIdMap.containsKey(k)&&_rosterCalendarId!=null){ try{ await _calendarPlugin.deleteEvent(_rosterCalendarId!, _googleEventIdMap[k]); }catch(_){} _googleEventIdMap.remove(k); } }
}
await save(); setState((){}); if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('已清除 $count 天排更')));
}
Future<void> shareScreenshotDialog() async{ await exportShareImage(); }
Future<void> exportShareImage() async{
try{
RenderRepaintBoundary? b=calKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
if(b==null) return;
ui.Image img=await b.toImage(pixelRatio:3);
var byte=await img.toByteData(format:ui.ImageByteFormat.png);
var png=byte!.buffer.asUint8List();
Directory baseDir=Directory('/storage/emulated/0/Pictures/Roster'); if(!await baseDir.exists()) await baseDir.create(recursive:true);
String path='${baseDir.path}/roster_${focused.year}_${focused.month}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.png';
File f=File(path); await f.writeAsBytes(png);
await Share.shareXFiles([XFile(path)],text:'${focused.year}年${focused.month}月 $customName');
if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('截圖已保存 $path')));
}catch(e){ if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('截圖失敗 $e'))); }
}
Future<void> backupAnywhere() async{
String? dir=await FilePicker.platform.getDirectoryPath(dialogTitle:'選擇備份位置'); if(dir==null) return;
String fileName='roster_pro_full_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.json';
var backup={'version':'7.0','roster':roster,'note':rosterNote,'roOt':rosterOt,'roEx':rosterExtra,'roExH':rosterExtraHrs,'defs':defs.map((k,v)=>MapEntry(k,v.toJson())),'pattern':pattern,'carry':carry,'cName':customName,'extraNewV36':extraAllowances.map((e)=>e.toJson()).toList(),'calFont':calendarFontSize,'holidayRegion':holidayRegion,'rosterCalId':_rosterCalendarId,'gSync':googleSyncEnabled,'todayBg':todayBgColor.value,'savedPatternsV40':savedPatterns.map((e)=>e.toJson()).toList()};
var f=File('$dir/$fileName'); await f.writeAsString(jsonEncode(backup));
setState(()=>_lastBackupPath='$dir/$fileName'); await save();
if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('全部備份 $_lastBackupPath')));
}
Future<void> restoreLocalFile() async{
var res=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['json']); if(res==null) return;
try{
String c=await File(res.files.single.path!).readAsString(); var j=jsonDecode(c);
setState((){
if(j['roster']!=null) roster=Map<String,String>.from(j['roster']);
if(j['note']!=null) rosterNote=Map<String,String>.from(j['note']);
if(j['roOt']!=null) rosterOt=Map<String,double>.from((j['roOt'] as Map).map((k,v)=>MapEntry(k as String,(v as num).toDouble())));
if(j['roEx']!=null) rosterExtra=Map<String,double>.from((j['roEx'] as Map).map((k,v)=>MapEntry(k as String,(v as num).toDouble())));
if(j['defs']!=null) defs=(j['defs'] as Map).map<String,ShiftDef>((k,v)=>MapEntry(k as String,ShiftDef.fromJson(Map<String,dynamic>.from(v as Map))));
if(j['pattern']!=null) pattern=(j['pattern'] as List).map<List<String>>((r)=>(r as List).map<String>((e)=>e.toString()).toList()).toList();
if(j['cName']!=null){ customName=j['cName']; nameCtrl.text=customName; }
if(j['extraNewV36']!=null) extraAllowances=(j['extraNewV36'] as List).map((e)=>ExtraAllowance.fromJson(Map<String,dynamic>.from(e as Map))).toList();
if(j['holidayRegion']!=null) holidayRegion=j['holidayRegion'];
if(j['rosterCalId']!=null) _rosterCalendarId=j['rosterCalId'];
if(j['savedPatternsV40']!=null) savedPatterns=(j['savedPatternsV40'] as List).map((e)=>SavedPattern.fromJson(Map<String,dynamic>.from(e as Map))).toList();
});
save(); if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('還原成功')));
}catch(e){ if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('還原失敗 $e'))); }
}
Future<void> exportReport() async{
StringBuffer sb=StringBuffer();
if(!isYearReport){
int dim=DateTime(focused.year,focused.month+1,0).day; double hrs=0,ot=0; double allow=0; Map<String,int> shiftCount={};
for(int i=1;i<=dim;i++){ DateTime dt=DateTime(focused.year,focused.month,i); String k=DateFormat('yyyy-MM-dd').format(dt); String? c=roster[k]; if(c==null) continue; var d=defs[c]; if(d!=null){ hrs+=d.hours; shiftCount[c]=(shiftCount[c]??0)+1; if(d.hasAllowance) allow+=d.allowance; } ot+=(rosterOt[k]??0); allow+=(rosterExtra[k]??0); hrs+=(rosterExtraHrs[k]??0); }
sb.writeln('${focused.year}年${focused.month}月 報表'); shiftCount.forEach((k,v)=>sb.writeln('$k $v次')); sb.writeln('總工時 $hrs OT $ot 津貼 $allow');
}else{
sb.writeln('${focused.year}年 全年統計');
for(int mon=1;mon<=12;mon++){ int dim=DateTime(focused.year,mon+1,0).day; double hrs=0; for(int d=1;d<=dim;d++){ DateTime dt=DateTime(focused.year,mon,d); String k=DateFormat('yyyy-MM-dd').format(dt); String? c=roster[k]; if(c==null) continue; var def=defs[c]; if(def!=null) hrs+=def.hours; } sb.writeln('$mon月 ${hrs}h'); }
}
String? path=await FilePicker.platform.saveFile(dialogTitle:'匯出報表',fileName:'report_${isYearReport?'year${focused.year}':'${focused.year}_${focused.month}'}.csv',type:FileType.custom,allowedExtensions:['csv','txt']);
if(path!=null){ await File(path).writeAsString(sb.toString()); if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('已匯出 $path'))); }
}

void showDetail(DateTime day){
String k=DateFormat('yyyy-MM-dd').format(day); String cur=roster[k]??'';
var nc=TextEditingController(text:rosterNote[k]??''); var otc=TextEditingController(text:(rosterOt[k]??0).toString()); var exCtrl=TextEditingController(text:(rosterExtra[k]??0).toString()); var exHCtrl=TextEditingController(text:(rosterExtraHrs[k]??0).toString());
showModalBottomSheet(context:context,isScrollControlled:true,builder:(ctx){
return StatefulBuilder(builder:(ctx2,setM){
return Padding(padding:EdgeInsets.only(bottom:MediaQuery.of(ctx2).viewInsets.bottom),child:Padding(padding:const EdgeInsets.all(16),child:Column(mainAxisSize:MainAxisSize.min,children:[
Text(DateFormat('yyyy-MM-dd EEE ${isHoliday(day)?'[${holidayName(day)}]':''}').format(day),style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
Wrap(spacing:8,children:defs.keys.map((c)=>ChoiceChip(label:Text(c),selected:cur==c,onSelected:(_)=>setM(()=>cur=c))).toList()),
SizedBox(height:56, child:TextField(controller:nc,decoration:const InputDecoration(labelText:'記事 (會同步到Google日曆標題+描述)',isDense:true,border:OutlineInputBorder()))),
Row(children:[Expanded(child:SizedBox(height:56, child:TextField(controller:otc,decoration:const InputDecoration(labelText:'OT',isDense:true,border:OutlineInputBorder()),keyboardType:TextInputType.number))), const SizedBox(width:8), Expanded(child:SizedBox(height:56, child:TextField(controller:exCtrl,decoration:const InputDecoration(labelText:'額外津貼',isDense:true,border:OutlineInputBorder()),keyboardType:TextInputType.number)))]),
SizedBox(height:56, child:TextField(controller:exHCtrl,decoration:const InputDecoration(labelText:'額外工時',isDense:true,border:OutlineInputBorder()),keyboardType:TextInputType.number)),
const SizedBox(height:12),
Row(children:[Expanded(child:OutlinedButton(onPressed:(){ setState(()=>roster.remove(k)); save(); Navigator.pop(ctx2); },child:const Text('清除'))), const SizedBox(width:8), Expanded(child:FilledButton(onPressed:(){ setState((){ if(cur.isNotEmpty) roster[k]=cur; rosterNote[k]=nc.text; rosterOt[k]=double.tryParse(otc.text)??0; rosterExtra[k]=double.tryParse(exCtrl.text)??0; rosterExtraHrs[k]=double.tryParse(exHCtrl.text)??0; }); save(); Navigator.pop(ctx2); },child:const Text('儲存')))])
]))); }); });
}

Widget calTab(){
DateTime first=DateTime(focused.year,focused.month,1); DateTime start=first.subtract(Duration(days:first.weekday-1));
int daysInMonth=DateTime(focused.year,focused.month+1,0).day; int neededCells=first.weekday-1+daysInMonth; int weeks=(neededCells/7).ceil(); if(weeks<5) weeks=5; if(weeks>6) weeks=6;
List<DateTime> days=List.generate(weeks*7,(i)=>start.add(Duration(days:i)));
String selKey=DateFormat('yyyy-MM-dd').format(selectedDay); var selDef=roster[selKey]!=null?defs[roster[selKey]]:null;
double selOt=rosterOt[selKey]??selDef?.ot??0; String note=rosterNote[selKey]??'無';
DateTime today=DateTime.now();
return SafeArea(child:Column(children:[
Padding(padding:const EdgeInsets.fromLTRB(12,8,12,4),child:Row(children:[InkWell(onTap:()=>quickJumpMonth(),child:Row(children:[Text('${focused.year}年${focused.month}月',style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const Icon(Icons.arrow_drop_down)])),const Spacer(),IconButton(icon:const Icon(Icons.camera_alt_outlined),tooltip:'整月截圖分享',onPressed:shareScreenshotDialog),IconButton(icon:const Icon(Icons.chevron_left),onPressed:(){ setState(()=>focused=DateTime(focused.year,focused.month-1,1)); }),IconButton(icon:const Icon(Icons.chevron_right),onPressed:(){ setState(()=>focused=DateTime(focused.year,focused.month+1,1)); }),FilledButton.tonal(onPressed:(){ setState((){ focused=DateTime(today.year,today.month,1); selectedDay=DateTime(today.year,today.month,today.day); }); },child:const Text('今天')),])),
Expanded(child: GestureDetector(
onHorizontalDragEnd: (details){ if(details.primaryVelocity!=null){ if(details.primaryVelocity! < -200){ setState(()=>focused=DateTime(focused.year,focused.month+1,1)); } else if(details.primaryVelocity! > 200){ setState(()=>focused=DateTime(focused.year,focused.month-1,1)); } } },
child: RepaintBoundary(key:calKey,child:Column(children:[Padding(padding:const EdgeInsets.symmetric(horizontal:6),child:Row(children:[Container(width:32,child:const Text('週',textAlign:TextAlign.center,style:TextStyle(fontWeight:FontWeight.bold,fontSize:11,color:Colors.deepPurple))),Expanded(child:Row(children:["一","二","三","四","五","六","日"].map((w)=>Expanded(child:Text(w,textAlign:TextAlign.center,style:const TextStyle(fontSize:11)))).toList()))])),Expanded(child: ListView.builder(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),padding:EdgeInsets.zero,itemCount:weeks,itemBuilder:(ctx,row){ return Row(children:[Container(width:32,alignment:Alignment.center,child:Text('W${isoWeek(days[row*7])}',style:const TextStyle(fontSize:11,color:Colors.deepPurple,fontWeight:FontWeight.bold))),Expanded(child:GridView.builder(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),padding:const EdgeInsets.all(3),gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:7,childAspectRatio:0.78,mainAxisSpacing:4,crossAxisSpacing:4),itemCount:7,itemBuilder:(ctx2,col){ int idx=row*7+col; DateTime day=days[idx]; bool inM=day.month==focused.month; String k=DateFormat('yyyy-MM-dd').format(day); String? code=roster[k]; var def=code!=null?defs[code]:null; bool sel=k==selKey; bool isToday=day.year==today.year&&day.month==today.month&&day.day==today.day; bool hasNote=rosterNote.containsKey(k)&&rosterNote[k]!.isNotEmpty; bool isHol=isHoliday(day);
Color bg; if(isToday) bg=todayBgColor; else if(!inM) bg=const Color(0xFFF5F5F0); else if(def!=null) bg=def.color.withOpacity(0.18); else bg=const Color(0xFFFFF0D0);
return GestureDetector(onTap:(){ setState(()=>selectedDay=day); },onLongPress:(){ setState(()=>selectedDay=day); showDetail(day); },child:Container(decoration:BoxDecoration(color:bg,borderRadius:BorderRadius.circular(12),border:isToday?Border.all(width:2.8,color:todayBorderColor):sel?Border.all(width:2,color:Colors.deepPurple):null),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Text('${day.day}',style:TextStyle(fontWeight:isToday?FontWeight.w900:FontWeight.bold,fontSize:calendarFontSize-1)),if(code!=null) Container(margin:const EdgeInsets.only(top:1),padding:const EdgeInsets.symmetric(horizontal:4,vertical:1),decoration:BoxDecoration(color:def?.color,borderRadius:BorderRadius.circular(8)),child:Text(code,style:TextStyle(color:Colors.white,fontSize:calendarFontSize-2))),Row(mainAxisAlignment:MainAxisAlignment.center,children:[if(isHol) Container(width:6,height:6,margin:const EdgeInsets.symmetric(horizontal:1),decoration:BoxDecoration(color:holidayDotColor,shape:BoxShape.circle)),if(hasNote) Container(width:6,height:6,margin:const EdgeInsets.symmetric(horizontal:1),decoration:const BoxDecoration(color:Colors.blue,shape:BoxShape.circle))])])));
})),
]); })),
])),
),
Container(width:double.infinity,padding:const EdgeInsets.all(10),color:Colors.white,child:Text('${DateFormat('MM/dd EEE').format(selectedDay)} ${roster[selKey]??'未排班'} | OT ${rosterOt[selKey]??0} | 津貼 ${rosterExtra[selKey]??0} | 記事 $note')),
]));
}

Widget patternTab(){
return SafeArea(child:Column(children:[
const Padding(padding:EdgeInsets.only(top:12),child:Center(child:Text('排更模式',style:TextStyle(fontWeight:FontWeight.bold,fontSize:18)))),
Padding(padding:const EdgeInsets.symmetric(vertical:6),child:Row(mainAxisAlignment:MainAxisAlignment.center,children:[
FilledButton.icon(icon:const Icon(Icons.add),label:Text('加一行(自動${defs.length}格)'),onPressed:(){ setState(()=>pattern.add(List.filled(7,'O'))); save(); }),
const SizedBox(width:8),
FilledButton.tonalIcon(icon:const Icon(Icons.playlist_add),label:const Text('一次加N行'),onPressed:(){
var c=TextEditingController(text:'3');
showDialog(context:context,builder:(ctx)=>AlertDialog(title:const Text('一次加幾行'),content:SizedBox(height:56,child:TextField(controller:c,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'行數',isDense:true,border:OutlineInputBorder()))),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('取消')),FilledButton(onPressed:(){ int n=int.tryParse(c.text)??1; setState(()=>pattern.addAll(List.generate(n,(_)=>List.filled(7,'O')))); save(); Navigator.pop(ctx); },child:const Text('確定'))]));
}),
const SizedBox(width:8),
FilledButton(onPressed:() async{ DateTimeRange? p=await showDateRangePicker(context:context,firstDate:DateTime(2023),lastDate:DateTime(2030)); if(p==null) return; var flat=pattern.expand((e)=>e).toList(); setState((){ int i=0; for(DateTime d=p.start;!d.isAfter(p.end);d=d.add(const Duration(days:1))){ roster[DateFormat('yyyy-MM-dd').format(d)]=flat[i%flat.length]; i++; }}); save(); setState(()=>tab=0); },child:const Text('自動排班'))
])),
SingleChildScrollView(scrollDirection: Axis.horizontal, padding:const EdgeInsets.all(8), child: Row(children: defs.keys.map((k)=>Padding(padding:const EdgeInsets.only(right:8),child: Chip(label:Text(k),backgroundColor:defs[k]!.color.withOpacity(0.3)))).toList())),
Expanded(child:ListView.builder(itemCount:pattern.length,itemBuilder:(ctx,r){
return Card(margin:const EdgeInsets.symmetric(horizontal:8,vertical:4),child:Padding(padding:const EdgeInsets.all(6),child:Row(children:[
SizedBox(width:28,child:Text('${r+1}',textAlign:TextAlign.center,style:const TextStyle(fontWeight:FontWeight.bold))),
Expanded(child:Row(children:List.generate(7,(c){ return Expanded(child:GestureDetector(onTap:(){ showModalBottomSheet(context:context,builder:(ctx)=>Wrap(children:defs.keys.map((k)=>ListTile(title:Text(k),onTap:(){ setState(()=>pattern[r][c]=k); save(); Navigator.pop(ctx); })).toList())); },child:Container(margin:const EdgeInsets.all(2),height:56,decoration:BoxDecoration(color:defs[pattern[r][c]]?.color.withOpacity(0.3),borderRadius:BorderRadius.circular(8),border:Border.all(color:Colors.black12)),child:Center(child:FittedBox(child:Text(pattern[r][c],style:TextStyle(fontSize:calendarFontSize))))))); }))),
IconButton(icon:const Icon(Icons.delete),onPressed:(){ setState(()=>pattern.removeAt(r)); save(); })
]))); })),
]));
}
Widget reportTab(){
int dim=DateTime(focused.year,focused.month+1,0).day; double hrs=0,ot=0,allow=0; Map<String,int> cnt={};
for(int i=1;i<=dim;i++){ DateTime dt=DateTime(focused.year,focused.month,i); String k=DateFormat('yyyy-MM-dd').format(dt); String? c=roster[k]; if(c==null) continue; var d=defs[c]; if(d!=null){ hrs+=d.hours; cnt[c]=(cnt[c]??0)+1; if(d.hasAllowance) allow+=d.allowance; } ot+=(rosterOt[k]??0); allow+=(rosterExtra[k]??0); hrs+=(rosterExtraHrs[k]??0); }
double fixedExtra=extraAllowances.fold(0,(s,e)=>s+e.amount);
return ListView(padding:const EdgeInsets.all(12),children:[
Row(children:[Text('${focused.year}年${focused.month}月報表',style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)), const Spacer(), Switch(value:isYearReport,onChanged:(v)=>setState(()=>isYearReport=v)), const Text('全年')]),
...cnt.entries.map((e)=>ListTile(title:Text(e.key),trailing:Text('${e.value}次'))),
const Divider(), ListTile(title:const Text('總工時'),trailing:Text('${hrs.toStringAsFixed(1)}h')), ListTile(title:const Text('OT'),trailing:Text('${ot.toStringAsFixed(1)}h')), ListTile(title:const Text('班次津貼+當日額外'),trailing:Text('\$$allow')),
const Divider(),
Row(children:[const Text('額外津貼 (自定名) - 計入總津貼',style:TextStyle(fontWeight:FontWeight.bold)), const Spacer(), IconButton(icon:const Icon(Icons.add),onPressed:(){
var nCtrl=TextEditingController(); var aCtrl=TextEditingController();
showDialog(context:context,builder:(ctx)=>AlertDialog(title:const Text('新增津貼'),content:Column(mainAxisSize:MainAxisSize.min,children:[SizedBox(height:56,child:TextField(controller:nCtrl,decoration:const InputDecoration(labelText:'名稱 例如: 大假津貼',isDense:true,border:OutlineInputBorder()))), const SizedBox(height:8), SizedBox(height:56,child:TextField(controller:aCtrl,decoration:const InputDecoration(labelText:'金額',isDense:true,border:OutlineInputBorder()),keyboardType:TextInputType.number))]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('取消')), FilledButton(onPressed:(){ if(nCtrl.text.isEmpty) return; setState(()=>extraAllowances.add(ExtraAllowance(nCtrl.text,double.tryParse(aCtrl.text)??0))); save(); Navigator.pop(ctx); },child:const Text('新增'))]));
})]),
...extraAllowances.asMap().entries.map((en)=>ListTile(title:Text(en.value.name),subtitle:Text('金額可刪除'),trailing:Row(mainAxisSize:MainAxisSize.min,children:[Text('\$${en.value.amount}'), IconButton(icon:const Icon(Icons.delete),onPressed:(){ setState(()=>extraAllowances.removeAt(en.key)); save(); })]))),
const Divider(),
ListTile(title:const Text('總津貼 (含自定)',style:TextStyle(fontWeight:FontWeight.bold)),trailing:Text('\$${(allow+fixedExtra).toStringAsFixed(0)}',style:const TextStyle(fontWeight:FontWeight.bold,fontSize:16))),
FilledButton(onPressed:exportReport,child:const Text('匯出報表 CSV')),
]);
}
Widget settingsTab(){
return ListView(padding:const EdgeInsets.all(16),children:[
ListTile(title:TextField(controller:nameCtrl,decoration:const InputDecoration(labelText:'日曆名稱',isDense:true,border:OutlineInputBorder()),onChanged:(v){ customName=v; save(); }),),
SwitchListTile(title:const Text('啟用日曆同步'),subtitle:Text(_rosterCalendarName),value:googleSyncEnabled,onChanged:(v) async { if(v){ await _requestGooglePerm(); } else { setState(()=>googleSyncEnabled=false); save(); }}),
SwitchListTile(title:const Text('自動同步'),subtitle:const Text('儲存即同步'),value:autoSync,onChanged:(v)=>setState(()=>autoSync=v)),
ListTile(title:const Text('手動同步去重 (先刪後加)'),subtitle:const Text('用 [RosterPro]yyyy-MM-dd 標籤，全天 allDay:true'),onTap:()=>_syncToGoogle()),
ListTile(title:const Text('備份到任意位置'),subtitle:Text(_lastBackupPath),onTap:backupAnywhere),
ListTile(title:const Text('還原備份'),onTap:restoreLocalFile),
ListTile(title:const Text('清除範圍排更'),onTap:clearRosterByRange),
ListTile(title:const Text('匯出報表'),onTap:exportReport),
ListTile(title:const Text('截圖分享'),onTap:exportShareImage),
const Divider(),
const ListTile(title:Text('桌面Widget已接通 home_widget'),subtitle:Text('今日/明日自動更新到桌面 RosterWidgetProvider - 需在原生加入 Widget')),
]);
}
@override Widget build(BuildContext context){ return Scaffold(body:[calTab(),patternTab(),reportTab(),settingsTab()][tab],bottomNavigationBar:NavigationBar(selectedIndex:tab,onDestinationSelected:(i)=>setState(()=>tab=i),destinations:const[NavigationDestination(icon:Icon(Icons.calendar_month),label:'月曆'),NavigationDestination(icon:Icon(Icons.pattern),label:'模式'),NavigationDestination(icon:Icon(Icons.bar_chart),label:'報表'),NavigationDestination(icon:Icon(Icons.settings),label:'設定')])); }
}
