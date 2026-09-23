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
import 'package:home_widget/home_widget.dart'; // <-- Widget

void main() { tzData.initializeTimeZones(); WidgetsFlutterBinding.ensureInitialized(); HomeWidget.setAppGroupId('group.rosterPro'); runApp(const RosterApp()); }

class ShiftDef {
  String code; String label; double hours; double ot; Color color; String start; String end; bool hasAllowance; double allowance; bool isAllDay;
  ShiftDef(this.code,this.label,this.hours,this.color,{this.ot=0,this.start='07:00',this.end='15:30',this.hasAllowance=false,this.allowance=0,this.isAllDay=false});
  Map<String,dynamic> toJson()=>{'code':code,'label':label,'hours':hours,'ot':ot,'color':color.value,'start':start,'end':end,'hasAllowance':hasAllowance,'allowance':allowance,'isAllDay':isAllDay};
  factory ShiftDef.fromJson(Map<String,dynamic> j)=>ShiftDef(j['code'],j['label']??j['code'],(j['hours']??8).toDouble(),Color(j['color']??0xFFFF9800),ot:(j['ot']??0).toDouble(),start:j['start']??'07:00',end:j['end']??'15:30',hasAllowance:j['hasAllowance']??((j['allowance']??0)>0),allowance:(j['allowance']??0).toDouble(),isAllDay:j['isAllDay']??false);
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
'中':ShiftDef('中','中更',8,Colors.blue,start:'14:00',end:'22:00'),
'宵':ShiftDef('宵','宵更',8,Colors.purple,start:'22:00',end:'06:00',hasAllowance:true,allowance:60),
'O':ShiftDef('O','休',0,Colors.green,start:'00:00',end:'00:00',isAllDay:true),
};
List<List<String>> pattern=[["早","早","中","中","宵","宵","O"],["早","早","早","中","中","O","O"]];
List<SavedPattern> savedPatterns=[]; double carry=0; String customName='我的排更-專屬日曆'; TextEditingController nameCtrl=TextEditingController();
double standardWeeklyHours=42; double overtimeRate=80; List<ExtraAllowance> extraAllowances=[]; double calendarFontSize=14;
bool googleSyncEnabled=false; bool autoSync=false; bool isYearReport=false;
String? editingPatternName; int? editingPatternIndex; String holidayRegion='香港';
GlobalKey calKey=GlobalKey();
DeviceCalendarPlugin _calendarPlugin = DeviceCalendarPlugin();
String? _rosterCalendarId; Map<String,String> _googleEventIdMap={}; bool _isSyncing=false;

Future<void> updateWidget() async {
  String todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
  String tomorrowKey = DateFormat('yyyy-MM-dd').format(DateTime.now().add(const Duration(days:1)));
  String todayCode = roster[todayKey]?? '休';
  String tomorrowCode = roster[tomorrowKey]?? '休';
  var def = defs[todayCode];
  await HomeWidget.saveWidgetData('today_code', todayCode);
  await HomeWidget.saveWidgetData('today_label', def?.label?? todayCode);
  await HomeWidget.saveWidgetData('today_time', def!=null? '${def.start}-${def.end}' : '');
  await HomeWidget.saveWidgetData('tomorrow_code', tomorrowCode);
  await HomeWidget.saveWidgetData('note', rosterNote[todayKey]?? '');
  await HomeWidget.updateWidget(name: 'RosterWidgetProvider', androidName: 'RosterWidgetProvider');
}

Map<String,String> getHolidays(int year, String region){
if(region=='無') return {};
if(region=='香港'){ return {'$year-01-01':'元旦','$year-01-29':'農曆年初一','$year-01-30':'農曆年初二','$year-01-31':'農曆年初三','$year-04-04':'清明節','$year-05-01':'勞動節','$year-05-05':'佛誕','$year-07-01':'香港回歸','$year-10-01':'國慶','$year-12-25':'聖誕節'}; }
return {};
}
bool isHoliday(DateTime d){ return getHolidays(d.year, holidayRegion).containsKey(DateFormat('yyyy-MM-dd').format(d)); }
String holidayName(DateTime d){ return getHolidays(d.year, holidayRegion)[DateFormat('yyyy-MM-dd').format(d)]??''; }

@override void initState(){ super.initState(); nameCtrl.text=customName; load().then((_)=>handleCalendarPermission(silent:true)); }
Future<void> load() async{
var sp=await SharedPreferences.getInstance();
var r=sp.getString('roster'); if(r!=null) roster=Map<String,String>.from(jsonDecode(r));
var rn=sp.getString('note'); if(rn!=null) rosterNote=Map<String,String>.from(jsonDecode(rn));
var ro=sp.getString('roOt'); if(ro!=null) try{ rosterOt=Map<String,double>.from((jsonDecode(ro) as Map).map((k,v)=>MapEntry(k as String,(v as num).toDouble()))); }catch(_){}
setState((){ customName=sp.getString('cName')??'我的排更-專屬日曆'; nameCtrl.text=customName; _rosterCalendarId=sp.getString('rosterCalId'); googleSyncEnabled=sp.getBool('gSync')??false; });
updateWidget();
}
Future<void> save() async{
var sp=await SharedPreferences.getInstance();
sp.setString('roster',jsonEncode(roster)); sp.setString('note',jsonEncode(rosterNote));
sp.setString('roOt',jsonEncode(rosterOt)); sp.setString('roEx',jsonEncode(rosterExtra)); sp.setString('roExH',jsonEncode(rosterExtraHrs));
sp.setString('defs',jsonEncode(defs.map((k,v)=>MapEntry(k,v.toJson())))); sp.setString('pattern',jsonEncode(pattern));
if(_rosterCalendarId!=null) sp.setString('rosterCalId', _rosterCalendarId!);
sp.setString('googleEventIdMap', jsonEncode(_googleEventIdMap)); sp.setBool('gSync', googleSyncEnabled);
updateWidget();
}

int isoWeek(DateTime date){ DateTime th=date.add(Duration(days:4-date.weekday)); DateTime jan1=DateTime(th.year,1,1); return 1+(th.difference(jan1).inDays/7).floor(); }
void quickJumpMonth(){ int y=focused.year,m=focused.month; showDialog(context:context,builder:(ctx){ return StatefulBuilder(builder:(ctx2,setD){ return AlertDialog(title:const Text('快速查找年月'),content:Column(mainAxisSize:MainAxisSize.min,children:[Row(children:[IconButton(icon:const Icon(Icons.remove),onPressed:()=>setD(()=>y--)),Expanded(child:Text('$y年',textAlign:TextAlign.center,style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold))),IconButton(icon:const Icon(Icons.add),onPressed:()=>setD(()=>y++))]),Wrap(spacing:8,children:List.generate(12,(i){ int mon=i+1; return ChoiceChip(label:Text('${mon}月'),selected:mon==m,onSelected:(_)=>setD(()=>m=mon)); }))]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx2),child:const Text('取消')),FilledButton(onPressed:(){ setState(()=>focused=DateTime(y,m,1)); Navigator.pop(ctx2); },child:const Text('跳轉'))]); }); }); }

Future<bool> handleCalendarPermission({bool silent=false}) async {
try{ await Permission.calendar.request(); }catch(_){} try{ await Permission.calendarFullAccess.request(); }catch(_){}
var devHas = await _calendarPlugin.hasPermissions(); if(devHas.isSuccess && devHas.data==true) return true;
var devReq = await _calendarPlugin.requestPermissions(); if(devReq.isSuccess && devReq.data==true) return true;
return false;
}
Future<String?> _pickGoogleCalendarDialog() async {
await handleCalendarPermission(silent:true);
var calsResult=await _calendarPlugin.retrieveCalendars(); var cals=calsResult.data??[];
List<Calendar> writable = cals.where((c)=>c.isReadOnly==false).toList().cast<Calendar>();
List<Calendar> displayList = writable.isNotEmpty? writable : cals.cast<Calendar>();
Calendar? picked = await showDialog<Calendar>(context: context, builder: (ctx){
return AlertDialog(title:Text('選擇日曆 (可寫${writable.length})'),content:SizedBox(width:420,height:420,child:ListView.builder(itemCount:displayList.length,itemBuilder:(c,i){ var cal=displayList[i]; return ListTile(title:Text(cal.name??'未命名'),subtitle:Text(cal.accountName??''),onTap:()=>Navigator.pop(ctx,cal)); })),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('取消')),TextButton(onPressed:() async { await openAppSettings(); },child:const Text('前往設定'))]);
});
return picked?.id;
}
Future<void> _requestGooglePerm() async{ String? id=await _pickGoogleCalendarDialog(); if(id==null) return; _rosterCalendarId=id; var sp=await SharedPreferences.getInstance(); sp.setString('rosterCalId', id); setState(()=>googleSyncEnabled=true); await _syncToGoogle(); save(); }
Future<void> _ensureCalendar() async{ if(_rosterCalendarId!=null){ var cals=await _calendarPlugin.retrieveCalendars(); if(cals.data!=null && cals.data!.any((c)=>c.id==_rosterCalendarId)) return; } String? id=await _pickGoogleCalendarDialog(); if(id!=null) _rosterCalendarId=id; }
Future<void> _syncToGoogle({bool silent=false}) async{
if(!googleSyncEnabled) return; if(_isSyncing) return; _isSyncing=true;
try{
if(_rosterCalendarId==null) await _ensureCalendar(); if(_rosterCalendarId==null) throw '未選日曆';
var existing=await _calendarPlugin.retrieveEvents(_rosterCalendarId!, RetrieveEventsParams(startDate:DateTime(2023,1,1),endDate:DateTime(2030,12,31)));
for(var e in existing.data??[]){ if((e.description??'').contains('[RosterPro]')) await _calendarPlugin.deleteEvent(_rosterCalendarId!, e.eventId); }
for(var entry in roster.entries){
var def=defs[entry.value]; if(def==null) continue; DateTime date=DateFormat('yyyy-MM-dd').parse(entry.key);
DateTime s=DateTime(date.year,date.month,date.day,int.parse(def.start.split(':')[0]),int.parse(def.start.split(':')[1]));
DateTime ee=def.end=='00:00'? DateTime(date.year,date.month,date.day+1,0,0) : DateTime(date.year,date.month,date.day,int.parse(def.end.split(':')[0]),int.parse(def.end.split(':')[1]));
if(ee.isBefore(s)) ee=ee.add(const Duration(days:1));
String desc='[RosterPro]${entry.key} ${customName}\n${def.code} ${def.start}-${def.end} ${rosterNote[entry.key]??''}';
var ev=Event(_rosterCalendarId!,title:'${def.code} ${def.start}-${def.end}',description:desc,start:tz.TZDateTime.from(s,tz.local),end:tz.TZDateTime.from(ee,tz.local),allDay:def.isAllDay);
var res=await _calendarPlugin.createOrUpdateEvent(ev); if(res!=null && res.isSuccess) _googleEventIdMap[entry.key]=res.data!;
}
if(!silent && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('已同步 ${roster.length}項')));
}catch(e){ if(!silent && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('同步失敗 $e'))); } finally{ _isSyncing=false; }
}

void showDetail(DateTime day){
String k=DateFormat('yyyy-MM-dd').format(day); String cur=roster[k]??''; var nc=TextEditingController(text:rosterNote[k]??'');
var otc=TextEditingController(text:(rosterOt[k]??0).toString()); var exCtrl=TextEditingController(text:(rosterExtra[k]??0).toString()); var exH=TextEditingController(text:(rosterExtraHrs[k]??0).toString());
showModalBottomSheet(context:context,isScrollControlled:true,builder:(ctx){ return StatefulBuilder(builder:(ctx2,setM){ return Padding(padding:EdgeInsets.only(bottom:MediaQuery.of(ctx2).viewInsets.bottom),child:Padding(padding:const EdgeInsets.all(16),child:Column(mainAxisSize:MainAxisSize.min,children:[Text(DateFormat('yyyy-MM-dd EEE').format(day),style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),Wrap(spacing:8,children:defs.keys.map((c)=>ChoiceChip(label:Text(c),selected:cur==c,onSelected:(_)=>setM(()=>cur=c))).toList()),TextField(controller:nc,decoration:const InputDecoration(labelText:'記事')),Row(children:[Expanded(child:TextField(controller:otc,decoration:const InputDecoration(labelText:'OT'),keyboardType:TextInputType.number)),const SizedBox(width:8),Expanded(child:TextField(controller:exH,decoration:const InputDecoration(labelText:'額外工時'),keyboardType:TextInputType.number))]),TextField(controller:exCtrl,decoration:const InputDecoration(labelText:'額外津貼'),keyboardType:TextInputType.number),const SizedBox(height:12),Row(children:[Expanded(child:OutlinedButton(onPressed:(){ setState(()=>roster.remove(k)); save(); Navigator.pop(ctx2); },child:const Text('清除'))),const SizedBox(width:8),Expanded(child:FilledButton(onPressed:(){ setState((){ if(cur.isNotEmpty) roster[k]=cur; if(nc.text.isNotEmpty) rosterNote[k]=nc.text; rosterOt[k]=double.tryParse(otc.text)??0; rosterExtra[k]=double.tryParse(exCtrl.text)??0; rosterExtraHrs[k]=double.tryParse(exH.text)??0; }); save(); Navigator.pop(ctx2); },child:const Text('儲存')))]) ))); }); });
}

Widget calTab(){
DateTime first=DateTime(focused.year,focused.month,1); DateTime start=first.subtract(Duration(days:first.weekday-1));
int dim=DateTime(focused.year,focused.month+1,0).day; int weeks=((first.weekday-1+dim)/7).ceil(); if(weeks<5) weeks=5;
List<DateTime> days=List.generate(weeks*7,(i)=>start.add(Duration(days:i)));
String selKey=DateFormat('yyyy-MM-dd').format(selectedDay); DateTime today=DateTime.now();
return SafeArea(child:Column(children:[
Padding(padding:const EdgeInsets.fromLTRB(12,8,12,4),child:Row(children:[InkWell(onTap:quickJumpMonth,child:Row(children:[Text('${focused.year}年${focused.month}月',style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const Icon(Icons.arrow_drop_down)])),const Spacer(),IconButton(icon:const Icon(Icons.chevron_left),onPressed:(){ setState(()=>focused=DateTime(focused.year,focused.month-1,1)); }),IconButton(icon:const Icon(Icons.chevron_right),onPressed:(){ setState(()=>focused=DateTime(focused.year,focused.month+1,1)); }),FilledButton.tonal(onPressed:(){ setState((){ focused=DateTime(today.year,today.month,1); selectedDay=today; }); },child:const Text('今天'))])),
RepaintBoundary(key:calKey,child:Column(children:[Padding(padding:const EdgeInsets.symmetric(horizontal:6),child:Row(children:[const SizedBox(width:32,child:Text('週',textAlign:TextAlign.center,style:TextStyle(fontSize:11,fontWeight:FontWeight.bold,color:Colors.deepPurple))),Expanded(child:Row(children:["一","二","三","四","五","六","日"].map((w)=>Expanded(child:Text(w,textAlign:TextAlign.center,style:const TextStyle(fontSize:11)))).toList()))])),ListView.builder(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),padding:EdgeInsets.zero,itemCount:weeks,itemBuilder:(ctx,row){ return Row(children:[Container(width:32,alignment:Alignment.center,child:Text('W${isoWeek(days[row*7])}',style:const TextStyle(fontSize:11,color:Colors.deepPurple))),Expanded(child:GridView.builder(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),padding:const EdgeInsets.all(3),gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:7,childAspectRatio:0.78,mainAxisSpacing:4,crossAxisSpacing:4),itemCount:7,itemBuilder:(ctx2,col){ int idx=row*7+col; DateTime d=days[idx]; bool inM=d.month==focused.month; String k=DateFormat('yyyy-MM-dd').format(d); String? code=roster[k]; var def=code!=null?defs[code]:null; bool sel=k==selKey; bool isToday=d.year==today.year&&d.month==today.month&&d.day==today.day; return GestureDetector(onTap:(){ setState(()=>selectedDay=d); },onLongPress:(){ setState(()=>selectedDay=d); showDetail(d); },child:Container(decoration:BoxDecoration(color:isToday?const Color(0xFFFFF9C4):!inM?const Color(0xFFF5F5F0):def!=null?def.color.withOpacity(0.18):const Color(0xFFFFF0D0),borderRadius:BorderRadius.circular(12),border:isToday?Border.all(width:2.5,color:Colors.orange):sel?Border.all(width:2,color:Colors.deepPurple):null),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Text('${d.day}',style:TextStyle(fontWeight:FontWeight.bold,fontSize:calendarFontSize-1)),if(code!=null)Container(padding:const EdgeInsets.symmetric(horizontal:4,vertical:1),decoration:BoxDecoration(color:def?.color,borderRadius:BorderRadius.circular(8)),child:Text(code,style:TextStyle(color:Colors.white,fontSize:calendarFontSize-2)))]) )); }))]))])),
Container(width:double.infinity,padding:const EdgeInsets.all(10),color:Colors.white,child:Text('${DateFormat('MM/dd EEE').format(selectedDay)} ${roster[selKey]??'未排班'} | ${rosterNote[selKey]??'無記事'}')),
]));
}
Widget patternTab(){
return SafeArea(child:Column(children:[
Padding(padding:const EdgeInsets.all(12),child:Row(children:[const Text('排更模式',style:TextStyle(fontWeight:FontWeight.bold)),const Spacer(),FilledButton(onPressed:() async { DateTimeRange? p=await showDateRangePicker(context:context,firstDate:DateTime(2023),lastDate:DateTime(2030)); if(p==null) return; var flat=pattern.expand((e)=>e).toList(); setState((){ int i=0; for(DateTime d=p.start;!d.isAfter(p.end);d=d.add(const Duration(days:1))){ roster[DateFormat('yyyy-MM-dd').format(d)]=flat[i%flat.length]; i++; } }); save(); setState(()=>tab=0); },child:const Text('選日期自動排班'))])),
Expanded(child:ListView.builder(itemCount:pattern.length,itemBuilder:(ctx,r){ return Row(children:[Text('${r+1}'),Expanded(child:Row(children:List.generate(7,(c){ return Expanded(child:GestureDetector(onTap:(){ showModalBottomSheet(context:context,builder:(ctx)=>Wrap(children:defs.keys.map((k)=>ListTile(title:Text(k),onTap:(){ setState(()=>pattern[r][c]=k); save(); Navigator.pop(ctx); })).toList())); },child:Container(margin:const EdgeInsets.all(2),height:36,color:defs[pattern[r][c]]?.color.withOpacity(0.3),child:Center(child:Text(pattern[r][c]))))); }).toList())),IconButton(icon:const Icon(Icons.delete),onPressed:(){ setState(()=>pattern.removeAt(r)); save(); })]); })),
ElevatedButton(onPressed:(){ setState(()=>pattern.add(List.filled(7,'O'))); save(); },child:const Text('加一行'))
]));
}
Widget reportTab(){
int dim=DateTime(focused.year,focused.month+1,0).day; double hrs=0,allow=0; Map<String,int> cnt={};
for(int i=1;i<=dim;i++){ String k=DateFormat('yyyy-MM-dd').format(DateTime(focused.year,focused.month,i)); var code=roster[k]; if(code==null) continue; var d=defs[code]; if(d!=null){ hrs+=d.hours; if(d.hasAllowance) allow+=d.allowance; cnt[code]=(cnt[code]??0)+1; } allow+=rosterExtra[k]??0; }
return ListView(padding:const EdgeInsets.all(12),children:[Text('${focused.year}年${focused.month}月報表',style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),...cnt.entries.map((e)=>ListTile(title:Text(e.key),trailing:Text('${e.value}次'))),const Divider(),ListTile(title:const Text('總工時'),trailing:Text('$hrs')),ListTile(title:const Text('總津貼'),trailing:Text('\$$allow'))]);
}
Widget settingsTab(){ return ListView(padding:const EdgeInsets.all(16),children:[SwitchListTile(title:const Text('啟用日曆同步'),value:googleSyncEnabled,onChanged:(v) async { if(v){ await _requestGooglePerm(); } else { setState(()=>googleSyncEnabled=false); save(); } }),ListTile(title:const Text('手動同步去重'),onTap:()=>_syncToGoogle()),ListTile(title:const Text('桌面Widget已啟用'),subtitle:const Text('今日/明日更份會自動更新到桌面')),]); }
@override Widget build(BuildContext context){ return Scaffold(body:[calTab(),patternTab(),reportTab(),settingsTab()][tab],bottomNavigationBar:NavigationBar(selectedIndex:tab,onDestinationSelected:(i)=>setState(()=>tab=i),destinations:const[NavigationDestination(icon:Icon(Icons.calendar_month),label:'月曆'),NavigationDestination(icon:Icon(Icons.pattern),label:'模式'),NavigationDestination(icon:Icon(Icons.bar_chart),label:'報表'),NavigationDestination(icon:Icon(Icons.settings),label:'設定')])); }
}
