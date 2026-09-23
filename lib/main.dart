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
import 'package:home_widget/home_widget.dart';

void main() { tzData.initializeTimeZones(); runApp(const RosterApp()); }

class ShiftDef {
  String code; String label; double hours; double ot; Color color; String start; String end; bool hasAllowance; double allowance; bool isAllDay;
  ShiftDef(this.code,this.label,this.hours,this.color,{this.ot=0,this.start='07:00',this.end='15:30',this.hasAllowance=false,this.allowance=0,this.isAllDay=false});
  Map<String,dynamic> toJson()=>{'code':code,'label':label,'hours':hours,'ot':ot,'color':color.value,'start':start,'end':end,'hasAllowance':hasAllowance,'allowance':allowance,'isAllDay':isAllDay};
  factory ShiftDef.fromJson(Map<String,dynamic> j)=>ShiftDef(j['code'],j['label']??j['code'],(j['hours']??8).toDouble(),Color(j['color']??0xFFFF9800),ot:(j['ot']??0).toDouble(),start:j['start']??'07:00',end:j['end']??'15:30',hasAllowance:j['hasAllowance']??((j['allowance']??0)>0),allowance:(j['allowance']??0).toDouble(),isAllDay:j['isAllDay']??false);
  String get detailTime=>isAllDay?'全天 ${hours.toStringAsFixed(1)}h':'$start-$end ${hours.toStringAsFixed(1)}h';
}
class ExtraAllowance { String name; double amount; ExtraAllowance(this.name,this.amount); Map<String,dynamic> toJson()=>{'name':name,'amount':amount}; factory ExtraAllowance.fromJson(Map<String,dynamic> j)=>ExtraAllowance(j['name'],(j['amount'] as num).toDouble()); }
class SavedPattern { String name; List<List<String>> data; SavedPattern(this.name,this.data); Map<String,dynamic> toJson()=>{'name':name,'data':data}; factory SavedPattern.fromJson(Map<String,dynamic> j)=>SavedPattern(j['name'], (j['data'] as List).map<List<String>>((r)=>(r as List).map<String>((e)=>e.toString()).toList()).toList()); }
class RosterApp extends StatelessWidget { const RosterApp({super.key}); @override Widget build(BuildContext context){ return MaterialApp(title:'Roster Pro v7.5',theme:ThemeData(useMaterial3:true,colorSchemeSeed:Colors.deepPurple),home:const MainPage()); } }

class MainPage extends StatefulWidget { const MainPage({super.key}); @override State<MainPage> createState()=>MainPageState(); }
class MainPageState extends State<MainPage> {
int tab=0; DateTime focused=DateTime.now(); DateTime selectedDay=DateTime.now();
Map<String,String> roster={}; Map<String,String> rosterNote={}; Map<String,double> rosterOt={}; Map<String,double> rosterExtra={}; Map<String,double> rosterExtraHrs={};
Map<String,String> rosterExtraType={};
List<String> allowanceTypes=['夜更','辛勞','特別','額外'];
Map<String,ShiftDef> defs={
'早':ShiftDef('早','早更',8,Colors.orange,start:'07:00',end:'15:30',hasAllowance:true,allowance:80),
'中':ShiftDef('中','中更',8,Colors.blue,start:'14:00',end:'22:00',hasAllowance:false,allowance:0),
'宵':ShiftDef('宵','宵更',8,Colors.purple,start:'22:00',end:'06:00',hasAllowance:true,allowance:60),
'O':ShiftDef('O','休',0,Colors.green,start:'00:00',end:'00:00',hasAllowance:false,allowance:0,isAllDay:true),
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
if(region=='香港'){ return {'$year-01-01':'元旦','$year-01-29':'農曆年初一','$year-05-01':'勞動節','$year-07-01':'香港回歸','$year-10-01':'國慶','$year-12-25':'聖誕節'}; }
return {};
}
bool isHoliday(DateTime d){ var map=getHolidays(d.year, holidayRegion); return map.containsKey(DateFormat('yyyy-MM-dd').format(d)); }
String holidayName(DateTime d){ var map=getHolidays(d.year, holidayRegion); return map[DateFormat('yyyy-MM-dd').format(d)]??''; }

@override void initState(){ super.initState(); nameCtrl.text=customName; load().then((_) async { await Future.delayed(const Duration(milliseconds:800)); handleCalendarPermission(silent:true); }); }
Future<void> load() async{
var sp=await SharedPreferences.getInstance();
var r=sp.getString('roster'); if(r!=null) roster=Map<String,String>.from(jsonDecode(r));
var rn=sp.getString('note'); if(rn!=null) rosterNote=Map<String,String>.from(jsonDecode(rn));
var ro=sp.getString('roOt'); if(ro!=null){ try{ rosterOt=Map<String,double>.from((jsonDecode(ro) as Map).map((k,v)=>MapEntry(k as String,(v as num).toDouble()))); }catch(_){} }
var re=sp.getString('roEx'); if(re!=null){ try{ rosterExtra=Map<String,double>.from((jsonDecode(re) as Map).map((k,v)=>MapEntry(k as String,(v as num).toDouble()))); }catch(_){} }
var reh=sp.getString('roExH'); if(reh!=null){ try{ rosterExtraHrs=Map<String,double>.from((jsonDecode(reh) as Map).map((k,v)=>MapEntry(k as String,(v as num).toDouble()))); }catch(_){} }
var ret=sp.getString('roExType'); if(ret!=null){ try{ rosterExtraType=Map<String,String>.from(jsonDecode(ret)); }catch(_){} }
var at=sp.getString('allowTypes'); if(at!=null){ try{ allowanceTypes=List<String>.from(jsonDecode(at)); }catch(_){} }
var d=sp.getString('defs'); if(d!=null){ try{ var m=Map<String,dynamic>.from(jsonDecode(d)); defs=m.map((k,v)=>MapEntry(k,ShiftDef.fromJson(Map<String,dynamic>.from(v)))); }catch(_){} }
var p=sp.getString('pattern'); if(p!=null){ try{ var l=jsonDecode(p) as List; pattern=l.map<List<String>>((row)=>(row as List).map<String>((e)=>e.toString()).toList()).toList(); }catch(_){} }
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
sp.setString('roExType', jsonEncode(rosterExtraType)); sp.setString('allowTypes', jsonEncode(allowanceTypes));
sp.setString('defs',jsonEncode(defs.map((k,v)=>MapEntry(k,v.toJson())))); sp.setString('pattern',jsonEncode(pattern));
sp.setDouble('carry',carry); sp.setString('cName',customName); sp.setDouble('stdWeek',standardWeeklyHours);
sp.setDouble('otRate',overtimeRate); sp.setDouble('calFont',calendarFontSize); sp.setBool('gSync',googleSyncEnabled); sp.setBool('gAuto',autoSync);
sp.setString('holidayRegion', holidayRegion); sp.setString('googleEventIdMap', jsonEncode(_googleEventIdMap));
if(_rosterCalendarId!=null) sp.setString('rosterCalId', _rosterCalendarId!);
try{ await HomeWidget.saveWidgetData('month', DateFormat('yyyy年M月').format(focused)); await HomeWidget.updateWidget(androidName:'RosterWidgetProvider'); }catch(_){}
if(autoSync && googleSyncEnabled &&!_isSyncing){ _syncToGoogle(silent:true); }
}
int isoWeek(DateTime date){ DateTime thursday=date.add(Duration(days:4-date.weekday)); DateTime jan1=DateTime(thursday.year,1,1); int days=thursday.difference(jan1).inDays; return 1+(days/7).floor(); }
void quickJumpMonth({bool forReport=false}){ int y=focused.year; int m=focused.month; showDialog(context:context,builder:(ctx){ return StatefulBuilder(builder:(ctx2,setD){ return AlertDialog(title:Text(forReport?'選擇報表年月':'快速查找年月'),content:Column(mainAxisSize:MainAxisSize.min,children:[Row(children:[IconButton(icon:const Icon(Icons.remove),onPressed:()=>setD(()=>y--)),Expanded(child:Text('$y年',textAlign:TextAlign.center,style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold))),IconButton(icon:const Icon(Icons.add),onPressed:()=>setD(()=>y++))]),Wrap(spacing:8,children:List.generate(12,(i){ int mon=i+1; return ChoiceChip(label:Text('${mon}月'),selected:mon==m,onSelected:(_)=>setD(()=>m=mon)); }))]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx2),child:const Text('取消')),FilledButton(onPressed:(){ setState(()=>focused=DateTime(y,m,1)); Navigator.pop(ctx2); },child:const Text('跳轉'))]); }); }); }

Future<bool> handleCalendarPermission({bool silent=false}) async {
try { await Permission.calendar.request(); } catch(_){}
try { await Permission.calendarFullAccess.request(); } catch(_){}
var devHas = await _calendarPlugin.hasPermissions();
if (devHas.isSuccess && devHas.data==true) return true;
var devReq = await _calendarPlugin.requestPermissions();
if (devReq.isSuccess && devReq.data==true) return true;
return false;
}

Future<String?> _pickGoogleCalendarDialog() async {
await handleCalendarPermission(silent:true);
var calsResult=await _calendarPlugin.retrieveCalendars();
var cals=calsResult.data??[];
List<Calendar> writable = cals.where((c)=>c.isReadOnly==false).toList().cast<Calendar>();
List<Calendar> all = cals.cast<Calendar>();
List<Calendar> displayList = writable.isNotEmpty? writable : all;
Calendar? picked = await showDialog<Calendar>(context: context, builder: (ctx){
return AlertDialog(
title: Text('選擇日曆 (可寫${writable.length} / 總${all.length})'),
content: SizedBox(width: 420, height: 420, child: ListView.builder(itemCount: displayList.length, itemBuilder: (c,i){
var cal = displayList[i];
return ListTile(title: Text(cal.name??'未命名'), subtitle: Text('${cal.accountName} ${cal.isReadOnly==true?'只讀':'可寫'}'), onTap: ()=>Navigator.pop(ctx, cal));
})),
actions: [TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('取消'))],
);
});
return picked?.id;
}

Future<void> _requestGooglePerm() async{
String? id = await _pickGoogleCalendarDialog(); if(id==null) return;
_rosterCalendarId=id;
var sp=await SharedPreferences.getInstance(); sp.setString('rosterCalId', id);
bool? ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('已選擇日曆'),content:Text('將同步到：$customName\nID: $id'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('取消')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('同步'))]));
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
if(!googleSyncEnabled &&!silent) return;
if(_isSyncing) return; _isSyncing=true;
try{
if(_rosterCalendarId==null) await _ensureCalendar(); if(_rosterCalendarId==null) throw '未選日曆';
var existingEvents=await _calendarPlugin.retrieveEvents(_rosterCalendarId!, RetrieveEventsParams(startDate: DateTime(2023,1,1), endDate: DateTime(2030,12,31)));
int del=0;
for(var e in existingEvents.data??[]){ if((e.description??'').contains('[RosterPro]')){ await _calendarPlugin.deleteEvent(_rosterCalendarId!, e.eventId); del++; } }
_googleEventIdMap.clear();
for(var entry in roster.entries){
var code=entry.value; var def=defs[code]; if(def==null) continue;
DateTime date=DateFormat('yyyy-MM-dd').parse(entry.key);
DateTime startDt=DateTime(date.year,date.month,date.day,int.parse(def.start.split(':')[0]),int.parse(def.start.split(':')[1]));
DateTime endDt=DateTime(date.year,date.month,date.day,int.parse(def.end.split(':')[0]),int.parse(def.end.split(':')[1]));
if(endDt.isBefore(startDt) || (def.start=='00:00' && def.end=='00:00')) endDt=endDt.add(const Duration(days:1));
String note=rosterNote[entry.key]??''; String exType=rosterExtraType[entry.key]??'津貼';
String tag='[RosterPro]${entry.key}';
String title = def.isAllDay? '$code 全天 ${note.isNotEmpty?'| $note':''}' : '$code ${def.start}-${def.end} ${note.isNotEmpty?'| $note':''}';
String desc = '$tag|$customName\n排更: $code (${def.label})\n時間: ${def.isAllDay?'全天':'${def.start}-${def.end}'} ${def.hours}h\nOT: ${rosterOt[entry.key]??0}h\n津貼: $exType \$${rosterExtra[entry.key]??0}\n記事: ${note.isEmpty?'無':note}\n日期: ${entry.key}';
var ev=Event(_rosterCalendarId!, title:title, description:desc, start:tz.TZDateTime.from(startDt, tz.local), end:tz.TZDateTime.from(endDt, tz.local), allDay: def.isAllDay);
var res=await _calendarPlugin.createOrUpdateEvent(ev); if(res!=null && res.isSuccess && res.data!=null) _googleEventIdMap[entry.key]=res.data!;
}
var sp=await SharedPreferences.getInstance(); sp.setString('googleEventIdMap', jsonEncode(_googleEventIdMap));
if(!silent && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('已同步到 [$customName] ${roster.length}項，刪舊${del}項，全天已用allDay')));
}catch(e){ if(!silent && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('同步失敗 $e'))); }
finally { _isSyncing=false; }
}

Future<void> clearRosterByRange() async{
DateTimeRange? range=await showDateRangePicker(context:context, firstDate: DateTime(2023), lastDate: DateTime(2030), helpText: '選擇要清除的排更範圍');
if(range==null) return; int count=0;
for(DateTime d=range.start;!d.isAfter(range.end); d=d.add(const Duration(days:1))){
String k=DateFormat('yyyy-MM-dd').format(d);
if(roster.containsKey(k)){ count++; roster.remove(k); rosterOt.remove(k); rosterExtra.remove(k); rosterExtraHrs.remove(k); rosterExtraType.remove(k); }
}
await save(); setState((){}); if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('已清除 $count 天排更')));
}

Widget calTab(){
DateTime first=DateTime(focused.year,focused.month,1); DateTime start=first.subtract(Duration(days:first.weekday-1));
int daysInMonth=DateTime(focused.year,focused.month+1,0).day; int neededCells=first.weekday-1+daysInMonth; int weeks=(neededCells/7).ceil(); if(weeks<5) weeks=5; if(weeks>6) weeks=6;
List<DateTime> days=List.generate(weeks*7,(i)=>start.add(Duration(days:i)));
String selKey=DateFormat('yyyy-MM-dd').format(selectedDay); var selDef=roster[selKey]!=null?defs[roster[selKey]]:null;
double selOt=rosterOt[selKey]??selDef?.ot??0; String note=rosterNote[selKey]??'無';
DateTime today=DateTime.now();
return SafeArea(child:Column(children:[
Padding(padding:const EdgeInsets.fromLTRB(12,8,12,4),child:Row(children:[InkWell(onTap:()=>quickJumpMonth(),child:Row(children:[Text('${focused.year}年${focused.month}月',style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const Icon(Icons.arrow_drop_down)])),const Spacer(),IconButton(icon:const Icon(Icons.chevron_left),onPressed:(){ setState(()=>focused=DateTime(focused.year,focused.month-1,1)); }),IconButton(icon:const Icon(Icons.chevron_right),onPressed:(){ setState(()=>focused=DateTime(focused.year,focused.month+1,1)); }),FilledButton.tonal(onPressed:(){ setState((){ focused=DateTime(today.year,today.month,1); selectedDay=DateTime(today.year,today.month,today.day); }); },child:const Text('今天')),])),
Expanded(child: Column(children:[Padding(padding:const EdgeInsets.symmetric(horizontal:6),child:Row(children:[Container(width:32,child:const Text('週',textAlign:TextAlign.center,style:TextStyle(fontWeight:FontWeight.bold,fontSize:11,color:Colors.deepPurple))),Expanded(child:Row(children:["一","二","三","四","五","六","日"].map((w)=>Expanded(child:Text(w,textAlign:TextAlign.center,style:const TextStyle(fontSize:11)))).toList()))])),Expanded(child: ListView.builder(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),padding:EdgeInsets.zero,itemCount:weeks,itemBuilder:(ctx,row){ return Row(children:[Container(width:32,alignment:Alignment.center,child:Text('W${isoWeek(days[row*7])}',style:const TextStyle(fontSize:11,color:Colors.deepPurple,fontWeight:FontWeight.bold))),Expanded(child:GridView.builder(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),padding:const EdgeInsets.all(3),gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:7,childAspectRatio:0.78,mainAxisSpacing:4,crossAxisSpacing:4),itemCount:7,itemBuilder:(ctx2,col){ int idx=row*7+col; DateTime day=days[idx]; bool inM=day.month==focused.month; String k=DateFormat('yyyy-MM-dd').format(day); String? code=roster[k]; var def=code!=null?defs[code]:null; bool sel=k==selKey; bool isToday = day.year==today.year && day.month==today.month && day.day==today.day; return GestureDetector(onTap:(){ setState(()=>selectedDay=day); },child:Container(decoration:BoxDecoration(color:isToday?const Color(0xFFFFF9C4):!inM?const Color(0xFFF5F5F0):def!=null?def.color.withOpacity(0.18):const Color(0xFFFFF0D0),borderRadius:BorderRadius.circular(12),border:isToday?Border.all(width:2.5,color:Colors.orange):sel?Border.all(width:2,color:Colors.deepPurple):null),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Text('${day.day}',style:TextStyle(fontWeight:FontWeight.bold,fontSize:calendarFontSize-1)),if(code!=null) Container(padding:const EdgeInsets.symmetric(horizontal:4,vertical:1),decoration:BoxDecoration(color:def?.color??Colors.orange,borderRadius:BorderRadius.circular(8)),child:Text(code,style:TextStyle(color:Colors.white,fontSize:calendarFontSize-2))),]))); })),]); })) ])),
Container(width:double.infinity,padding:const EdgeInsets.fromLTRB(12,10,12,12),decoration:const BoxDecoration(color:Colors.white,border:Border(top:BorderSide(color:Color(0xFFE0E0E0)))),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('${DateFormat('MM/dd EEE').format(selectedDay)} ${roster[selKey]??'未排班'}',style:const TextStyle(fontSize:16,fontWeight:FontWeight.bold)),Text('時間：${selDef!=null?(selDef.isAllDay?'全天':'${selDef.start}-${selDef.end}'):'無'} | 津貼：${rosterExtraType[selKey]??'津貼'} \$${rosterExtra[selKey]??0} | OT：${selOt}h | 記事：$note'),])),
]));
}

void showDetail(DateTime day){
String k=DateFormat('yyyy-MM-dd').format(day); String cur=roster[k]??''; var nc=TextEditingController(text:rosterNote[k]??''); var otc=TextEditingController(text:(rosterOt[k]??0).toString()); var exCtrl=TextEditingController(text:(rosterExtra[k]??0).toString()); var exHCtrl=TextEditingController(text:(rosterExtraHrs[k]??0).toString());
String exType=rosterExtraType[k]?? allowanceTypes.first;
showModalBottomSheet(context:context,isScrollControlled:true,builder:(ctx){
return StatefulBuilder(builder:(ctx2,setM){
return Padding(padding:EdgeInsets.only(bottom:MediaQuery.of(ctx2).viewInsets.bottom),child:Padding(padding:const EdgeInsets.all(16),child:Column(mainAxisSize:MainAxisSize.min,children:[
Text('${DateFormat('yyyy-MM-dd EEE').format(day)}',style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
Wrap(spacing:8,children:defs.keys.map((c)=>ChoiceChip(label:Text(c),selected:cur==c,onSelected:(_)=>setM(()=>cur=c))).toList()),
TextField(controller:nc,decoration:const InputDecoration(labelText:'記事 (會同步到Google日曆)')),
Row(children:[Expanded(child:TextField(controller:otc,decoration:const InputDecoration(labelText:'OT時數'),keyboardType:TextInputType.number)),const SizedBox(width:8),Expanded(child:TextField(controller:exHCtrl,decoration:const InputDecoration(labelText:'額外工時'),keyboardType:TextInputType.number)),]),
Row(children:[
DropdownButton<String>(value: allowanceTypes.contains(exType)?exType:allowanceTypes.first, items: allowanceTypes.map((t)=>DropdownMenuItem(value:t, child:Text(t))).toList(), onChanged:(v){ if(v!=null) setM(()=>exType=v); }),
IconButton(icon:const Icon(Icons.edit), onPressed:(){ _editAllowanceTypes(); }),
Expanded(child:TextField(controller:exCtrl,decoration:const InputDecoration(labelText:'額外津貼 \$'),keyboardType:TextInputType.number)),
]),
const SizedBox(height:12),
Row(children:[
Expanded(child:OutlinedButton(onPressed:(){ setState((){ roster.remove(k); }); save(); Navigator.pop(ctx2); },child:const Text('清除班次'))),
const SizedBox(width:8),
Expanded(child:FilledButton(onPressed:(){
setState((){
if(cur.isNotEmpty) roster[k]=cur;
if(nc.text.isNotEmpty) rosterNote[k]=nc.text; else rosterNote.remove(k);
rosterOt[k]=double.tryParse(otc.text)??0;
rosterExtra[k]=double.tryParse(exCtrl.text)??0;
rosterExtraHrs[k]=double.tryParse(exHCtrl.text)??0;
rosterExtraType[k]=exType;
});
save(); Navigator.pop(ctx2);
},child:const Text('儲存'))),
]),
])));
});
});
}

void _editAllowanceTypes(){
TextEditingController c=TextEditingController();
showDialog(context:context, builder:(ctx){
return StatefulBuilder(builder:(ctx2,setS){
return AlertDialog(
title:const Text('自定津貼名稱'),
content: Column(mainAxisSize:MainAxisSize.min, children:[
Wrap(spacing:4, children: allowanceTypes.map((t)=>Chip(label:Text(t), onDeleted: (){ setS((){ allowanceTypes.remove(t); }); save(); })).toList()),
TextField(controller:c, decoration:const InputDecoration(hintText:'新增名稱')),
]),
actions:[
TextButton(onPressed:(){ if(c.text.trim().isNotEmpty){ setState(()=>allowanceTypes.add(c.text.trim())); save(); c.clear(); setS((){}); } }, child:const Text('新增')),
FilledButton(onPressed: ()=>Navigator.pop(ctx2), child:const Text('完成')),
],
);
});
});
}

void editShiftDialog({ShiftDef? oldDef}){
var codeCtrl=TextEditingController(text:oldDef?.code??''); var labelCtrl=TextEditingController(text:oldDef?.label??''); var hoursCtrl=TextEditingController(text:oldDef?.hours.toString()??'8'); var startCtrl=TextEditingController(text:oldDef?.start??'07:00'); var endCtrl=TextEditingController(text:oldDef?.end??'15:30'); var allowCtrl=TextEditingController(text:oldDef?.allowance.toString()??'0'); bool hasAllow=oldDef?.hasAllowance??false; bool isAllDay=oldDef?.isAllDay??false; Color picked=oldDef?.color??Colors.orange; String oldKey=oldDef?.code??'';
showDialog(context:context,builder:(ctx){ return StatefulBuilder(builder:(ctx2,setS){
return AlertDialog(title:Text(oldDef==null?'新增班次':'編輯 ${oldDef.code}'),content:SingleChildScrollView(child:Column(children:[
TextField(controller:codeCtrl,decoration:const InputDecoration(labelText:'代號')), TextField(controller:labelCtrl,decoration:const InputDecoration(labelText:'名稱')),
Row(children:[
Expanded(child: TextField(controller:startCtrl, decoration:const InputDecoration(labelText:'開始 HH:mm', border:OutlineInputBorder(), isDense:true))),
const SizedBox(width:8),
Expanded(child: TextField(controller:endCtrl, decoration:const InputDecoration(labelText:'結束 HH:mm', border:OutlineInputBorder(), isDense:true))),
]),
Container(padding:const EdgeInsets.all(8), decoration:BoxDecoration(border:Border.all(color:Colors.greenAccent,width:2), borderRadius:BorderRadius.circular(12)), child:Column(children:[
Row(children:[Checkbox(value:isAllDay,onChanged:(v){ setS(()=>isAllDay=v??false; }), const Text('全天')]),
SizedBox(height:56, child: TextField(controller:hoursCtrl, decoration:const InputDecoration(labelText:'工時', border:OutlineInputBorder(), isDense:true))),
])),
Row(children:[Checkbox(value:hasAllow,onChanged:(v)=>setS(()=>hasAllow=v??false)),const Text('有津貼核實')]), if(hasAllow) TextField(controller:allowCtrl,decoration:const InputDecoration(labelText:'津貼金額', border:OutlineInputBorder(), isDense:true)),
])),
actions:[TextButton(onPressed:()=>Navigator.pop(ctx2),child:const Text('取消')),FilledButton(onPressed:(){ String newCode=codeCtrl.text.trim(); if(newCode.isEmpty) return; setState((){ if(oldKey.isNotEmpty && oldKey!=newCode){ defs.remove(oldKey); } defs[newCode]=ShiftDef(newCode,labelCtrl.text.isEmpty?newCode:labelCtrl.text,double.tryParse(hoursCtrl.text)??8,picked,start:startCtrl.text,end:endCtrl.text,hasAllowance:hasAllow,allowance:double.tryParse(allowCtrl.text)??0,isAllDay:isAllDay); }); save(); Navigator.pop(ctx2); },child:const Text('儲存'))]);
}); }); }

Widget patternTab(){
TextEditingController rowCountCtrl=TextEditingController(text:'1');
return SafeArea(child:Column(children:[
const Center(child: Padding(padding: EdgeInsets.all(12), child: Text('排班模式', style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)))),
Padding(padding:const EdgeInsets.symmetric(horizontal:12),child:Wrap(spacing:8, runSpacing:8, children:[
FilledButton.tonalIcon(icon:const Icon(Icons.folder),label:Text('已存模式(${savedPatterns.length})'),onPressed:(){}),
FilledButton.tonalIcon(icon:const Icon(Icons.save_as),label:const Text('另存'),onPressed:(){}),
FilledButton.tonal(onPressed:(){ setState(()=>pattern=[]); save(); },child:const Text('清空')),
])),
Padding(padding:const EdgeInsets.all(12), child: Row(children:[
const Text('一次加 '), SizedBox(width:60, child: TextField(controller:rowCountCtrl, decoration:const InputDecoration(border:OutlineInputBorder(), isDense:true), keyboardType: TextInputType.number)), const Text(' 行 '),
ElevatedButton(onPressed:(){ int n=int.tryParse(rowCountCtrl.text)??1; setState(()=>pattern.addAll(List.generate(n, (_)=>List.filled(7,'O')))); save(); }, child:const Text('添加')),
const SizedBox(width:12),
Expanded(child: FilledButton(onPressed:() async { DateTimeRange? p=await showDateRangePicker(context:context,firstDate:DateTime(2023),lastDate:DateTime(2030)); if(p==null) return; var flat=pattern.expand((e)=>e).toList(); setState((){ int i=0; for(DateTime d=p.start;!d.isAfter(p.end);d=d.add(const Duration(days:1))){ roster[DateFormat('yyyy-MM-dd').format(d)]=flat[i%flat.length]; i++; } }); save(); setState(()=>tab=0); },child:const Text('選日期自動排班'))),
])),
Expanded(child:ListView.builder(itemCount:pattern.length,itemBuilder:(ctx,r){
return Row(children:[
Container(width:32,alignment:Alignment.centerRight,child:Text('${r+1}')),
Expanded(child:Row(children:List.generate(7,(c){
return Expanded(child:GestureDetector(onTap:(){
showModalBottomSheet(context:context,builder:(ctx){ return Wrap(children:defs.keys.map((k)=>ListTile(title:Text(k),onTap:(){ setState(()=>pattern[r][c]=k); save(); Navigator.pop(ctx); })).toList()); });
},child:Container(margin:const EdgeInsets.all(2),height:36,color:defs[pattern[r][c]]?.color.withOpacity(0.3),child:Center(child:Text(pattern[r][c])))));
})))),
IconButton(icon:const Icon(Icons.delete),onPressed:(){ setState(()=>pattern.removeAt(r)); save(); }),
]);
})),
const Divider(),
const Padding(padding: EdgeInsets.all(8), child: Align(alignment: Alignment.centerLeft, child: Text('所有班次代號(可橫向滾動)：', style:TextStyle(fontWeight:FontWeight.bold)))),
SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: defs.keys.map((k)=>Padding(padding:const EdgeInsets.all(4), child: ActionChip(label:Text(k), backgroundColor: defs[k]!.color.withOpacity(0.3), onPressed: (){}))).toList())),
const SizedBox(height:12),
]));
}

Widget reportTab(){
int dim=DateTime(focused.year,focused.month+1,0).day; double hrs=0,ot=0; double allow=0; Map<String,int> shiftCount={}; Map<String,double> allowByType={};
for(int i=1;i<=dim;i++){ DateTime dt=DateTime(focused.year,focused.month,i); String k=DateFormat('yyyy-MM-dd').format(dt); String? c=roster[k]; if(c==null) continue; var d=defs[c]; if(d!=null){ hrs+=d.hours; shiftCount[c]=(shiftCount[c]??0)+1; if(d.hasAllowance) allow+=d.allowance; } ot+=(rosterOt[k]??0); allow+=(rosterExtra[k]??0); String t=rosterExtraType[k]??'津貼'; allowByType[t]=(allowByType[t]??0)+(rosterExtra[k]??0); }
return ListView(padding:const EdgeInsets.all(12),children:[
Text('${focused.year}年${focused.month}月 報表',style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
...shiftCount.entries.map((e)=>ListTile(title:Text(e.key), trailing:Text('${e.value}次'))),
const Divider(),
...allowByType.entries.map((e)=>ListTile(title:Text(e.key), trailing:Text('\$${e.value}'))),
ListTile(title:const Text('總工時'), trailing:Text('$hrs')),
ListTile(title:const Text('總津貼'), trailing:Text('\$$allow')),
]);
}

Widget settingsTab(){
return ListView(padding:const EdgeInsets.all(16),children:[
SwitchListTile(title:const Text('啟用日曆同步'), value:googleSyncEnabled, onChanged:(v) async { if(v){ await _requestGooglePerm(); } else { setState(()=>googleSyncEnabled=false); save(); } }),
ListTile(title:const Text('管理班次'), onTap: ()=> showDialog(context:context, builder:(ctx)=>SimpleDialog(title:const Text('班次'), children:[...defs.values.map((d)=>SimpleDialogOption(child:Text('${d.code} ${d.label}'), onPressed: ()=>editShiftDialog(oldDef:d))), SimpleDialogOption(child:const Text('+ 新增'), onPressed: ()=>editShiftDialog())]))),
ListTile(title:const Text('手動同步去重'), onTap: ()=>_syncToGoogle()),
ListTile(title:const Text('按範圍清除'), onTap: ()=>clearRosterByRange()),
const ListTile(title:Text('額外津貼名稱管理'), subtitle:Text('在日編輯頁可選')),
Wrap(spacing:6, children: allowanceTypes.map((t)=>Chip(label:Text(t), onDeleted: (){ setState(()=>allowanceTypes.remove(t)); save(); })).toList()),
]);
}
@override Widget build(BuildContext context){
return Scaffold(body:[calTab(),patternTab(),reportTab(),settingsTab()][tab],bottomNavigationBar:NavigationBar(selectedIndex:tab,onDestinationSelected:(i)=>setState(()=>tab=i),destinations:const[NavigationDestination(icon:Icon(Icons.calendar_month),label:'月曆'),NavigationDestination(icon:Icon(Icons.pattern),label:'模式'),NavigationDestination(icon:Icon(Icons.bar_chart),label:'報表'),NavigationDestination(icon:Icon(Icons.settings),label:'設定'),]),);
}
}
