import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_calendar/device_calendar.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzData;
import 'package:permission_handler/permission_handler.dart';
import 'package:home_widget/home_widget.dart';

void main() {
  tzData.initializeTimeZones();
  WidgetsFlutterBinding.ensureInitialized();
  HomeWidget.setAppGroupId('group.rosterPro');
  runApp(const RosterApp());
}

class ShiftDef {
  String code; String label; double hours; double ot; Color color;
  String start; String end; bool hasAllowance; double allowance; bool isAllDay;
  ShiftDef(this.code,this.label,this.hours,this.color,{this.ot=0,this.start='07:00',this.end='15:30',this.hasAllowance=false,this.allowance=0,this.isAllDay=false});
  Map<String,dynamic> toJson()=>{'code':code,'label':label,'hours':hours,'ot':ot,'color':color.value,'start':start,'end':end,'hasAllowance':hasAllowance,'allowance':allowance,'isAllDay':isAllDay};
  factory ShiftDef.fromJson(Map<String,dynamic> j)=>ShiftDef(j['code'],j['label']??j['code'],(j['hours']??8).toDouble(),Color(j['color']??0xFFFF9800),ot:(j['ot']??0).toDouble(),start:j['start']??'07:00',end:j['end']??'15:30',hasAllowance:j['hasAllowance']??((j['allowance']??0)>0),allowance:(j['allowance']??0).toDouble(),isAllDay:j['isAllDay']??false);
}
class ExtraAllowance { String name; double amount; ExtraAllowance(this.name,this.amount); Map<String,dynamic> toJson()=>{'name':name,'amount':amount}; factory ExtraAllowance.fromJson(Map<String,dynamic> j)=>ExtraAllowance(j['name'],(j['amount'] as num).toDouble()); }
class SavedPattern { String name; List<List<String>> data; SavedPattern(this.name,this.data); Map<String,dynamic> toJson()=>{'name':name,'data':data}; factory SavedPattern.fromJson(Map<String,dynamic> j)=>SavedPattern(j['name'], (j['data'] as List).map<List<String>>((r)=>(r as List).map<String>((e)=>e.toString()).toList()).toList()); }

class RosterApp extends StatelessWidget { const RosterApp({super.key}); @override Widget build(BuildContext context){ return MaterialApp(title:'Roster Pro v7',theme:ThemeData(useMaterial3:true,colorSchemeSeed:Colors.deepPurple),home:const MainPage()); } }

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
List<List<String>> pattern=[["早","早","中","中","宵","宵","O"]];
List<ExtraAllowance> extraAllowances=[];
double calendarFontSize=14;
bool googleSyncEnabled=false;
DeviceCalendarPlugin _calendarPlugin = DeviceCalendarPlugin();
String? _rosterCalendarId; bool _isSyncing=false;

Future<void> updateWidget() async {
  String todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
  String tomorrowKey = DateFormat('yyyy-MM-dd').format(DateTime.now().add(const Duration(days:1)));
  await HomeWidget.saveWidgetData('today_code', roster[todayKey]??'O');
  await HomeWidget.saveWidgetData('tomorrow_code', roster[tomorrowKey]??'O');
  await HomeWidget.saveWidgetData('today_label', defs[roster[todayKey]]?.label?? roster[todayKey]?? 'O');
  await HomeWidget.saveWidgetData('note', rosterNote[todayKey]??'');
  await HomeWidget.updateWidget(androidName: 'RosterWidgetProvider');
}
@override void initState(){ super.initState(); load(); }
Future<void> load() async{
  var sp=await SharedPreferences.getInstance();
  var r=sp.getString('roster'); if(r!=null) roster=Map<String,String>.from(jsonDecode(r));
  var rn=sp.getString('note'); if(rn!=null) rosterNote=Map<String,String>.from(jsonDecode(rn));
  var ro=sp.getString('roOt'); if(ro!=null) try{ rosterOt=Map<String,double>.from((jsonDecode(ro) as Map).map((k,v)=>MapEntry(k as String,(v as num).toDouble()))); }catch(_){}
  var re=sp.getString('roEx'); if(re!=null) try{ rosterExtra=Map<String,double>.from((jsonDecode(re) as Map).map((k,v)=>MapEntry(k as String,(v as num).toDouble()))); }catch(_){}
  var exList=sp.getString('extraAllowDefs'); if(exList!=null) try{ extraAllowances=(jsonDecode(exList) as List).map((e)=>ExtraAllowance.fromJson(e)).toList(); }catch(_){}
  var pat=sp.getString('pattern'); if(pat!=null) try{ pattern=(jsonDecode(pat) as List).map<List<String>>((e)=>(e as List).map<String>((x)=>x.toString()).toList()).toList(); }catch(_){}
  _rosterCalendarId=sp.getString('rosterCalId'); googleSyncEnabled=sp.getBool('gSync')??false;
  setState((){}); updateWidget();
}
Future<void> save() async{
  var sp=await SharedPreferences.getInstance();
  sp.setString('roster',jsonEncode(roster)); sp.setString('note',jsonEncode(rosterNote));
  sp.setString('roOt',jsonEncode(rosterOt)); sp.setString('roEx',jsonEncode(rosterExtra));
  sp.setString('extraAllowDefs', jsonEncode(extraAllowances.map((e)=>e.toJson()).toList()));
  sp.setString('pattern', jsonEncode(pattern));
  if(_rosterCalendarId!=null) sp.setString('rosterCalId', _rosterCalendarId!);
  sp.setBool('gSync', googleSyncEnabled);
  updateWidget();
}
int isoWeek(DateTime date){ DateTime th=date.add(Duration(days:4-date.weekday)); DateTime jan1=DateTime(th.year,1,1); return 1+(th.difference(jan1).inDays/7).floor(); }
Future<bool> handleCalendarPermission() async {
  try{ await Permission.calendar.request(); }catch(_){}
  try{ await Permission.calendarFullAccess.request(); }catch(_){}
  var has = await _calendarPlugin.hasPermissions(); if(has.isSuccess && has.data==true) return true;
  var req = await _calendarPlugin.requestPermissions(); return req.isSuccess && req.data==true;
}
Future<String?> _pickGoogleCalendarDialog() async {
  await handleCalendarPermission();
  var calsResult=await _calendarPlugin.retrieveCalendars(); var cals=calsResult.data??[];
  var writable = cals.where((c)=>c.isReadOnly==false).toList();
  var list = writable.isNotEmpty? writable : cals;
  if(!mounted) return null;
  Calendar? picked = await showDialog<Calendar>(context: context, builder: (ctx){
    return AlertDialog(title: Text('選擇日曆 (可寫${writable.length})'),
      content: SizedBox(width:380,height:380,child: ListView.builder(itemCount:list.length,itemBuilder:(c,i){ var cal=list[i]; return ListTile(title:Text(cal.name??'未命名'),subtitle:Text(cal.accountName??''),onTap:()=>Navigator.pop(ctx,cal)); })),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('取消'))]);
  });
  return picked?.id;
}
Future<void> _syncToGoogle({bool silent=false}) async{
  if(!googleSyncEnabled &&!silent) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請先啟用日曆同步'))); return; }
  if(_isSyncing) return; _isSyncing=true;
  if(!silent) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('開始同步...')));
  try{
    if(_rosterCalendarId==null){ String? id=await _pickGoogleCalendarDialog(); if(id==null) throw '未選日曆'; _rosterCalendarId=id; await save(); }
    var existing=await _calendarPlugin.retrieveEvents(_rosterCalendarId!, RetrieveEventsParams(startDate:DateTime(2023,1,1),endDate:DateTime(2030,12,31)));
    for(var e in existing.data??[]){ String desc=e.description??''; if(desc.contains('[RosterPro]')){ await _calendarPlugin.deleteEvent(_rosterCalendarId!, e.eventId); } }
    int count=0;
    for(var entry in roster.entries){
      var def=defs[entry.value]; if(def==null) continue;
      DateTime date=DateFormat('yyyy-MM-dd').parse(entry.key);
      String tag='[RosterPro]${entry.key}';
      String desc='$tag ${entry.value} ${rosterNote[entry.key]??''}';
      bool allDay = def.isAllDay || def.code=='O';
      Event ev;
      if(allDay){
        ev=Event(_rosterCalendarId!,title:'${def.code} ${customName()}',description:desc,start:tz.TZDateTime(tz.local,date.year,date.month,date.day),end:tz.TZDateTime(tz.local,date.year,date.month,date.day+1),allDay:true);
      } else {
        DateTime s=DateTime(date.year,date.month,date.day,int.parse(def.start.split(':')[0]),int.parse(def.start.split(':')[1]));
        DateTime ee=DateTime(date.year,date.month,date.day,int.parse(def.end.split(':')[0]),int.parse(def.end.split(':')[1]));
        if(ee.isBefore(s)) ee=ee.add(const Duration(days:1));
        ev=Event(_rosterCalendarId!,title:'${def.code} ${def.start}-${def.end}',description:desc,start:tz.TZDateTime.from(s,tz.local),end:tz.TZDateTime.from(ee,tz.local),allDay:false);
      }
      var res=await _calendarPlugin.createOrUpdateEvent(ev); if(res!=null && res.isSuccess) count++;
    }
    if(!silent && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('同步完成 $count 項，去重以 [RosterPro]日期')));
  }catch(e){ if(!silent && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('同步失敗 $e'))); } finally{ _isSyncing=false; }
}
String customName(){ return '我的排更'; }
void showDetail(DateTime day){
  String k=DateFormat('yyyy-MM-dd').format(day); String cur=roster[k]??'';
  var nc=TextEditingController(text:rosterNote[k]??'');
  var otc=TextEditingController(text:(rosterOt[k]??0).toString());
  var exCtrl=TextEditingController(text:(rosterExtra[k]??0).toString());
  showModalBottomSheet(context:context,isScrollControlled:true,builder:(ctx){
    return StatefulBuilder(builder:(ctx2,setM){
      return Padding(padding:EdgeInsets.only(bottom:MediaQuery.of(ctx2).viewInsets.bottom),
        child: Padding(padding: const EdgeInsets.all(16), child: Column(mainAxisSize: MainAxisSize.min, children:[
          Text(DateFormat('yyyy-MM-dd EEE').format(day),style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
          const SizedBox(height:12),
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: defs.keys.map((c)=>Padding(padding:const EdgeInsets.only(right:8),child:ChoiceChip(label:Text(c),selected:cur==c,onSelected:(_)=>setM(()=>cur=c)))).toList())),
          const SizedBox(height:8),
          SizedBox(height:56, child: TextField(controller:nc,decoration:const InputDecoration(labelText:'記事', isDense:true, border:OutlineInputBorder()))),
          const SizedBox(height:8),
          Row(children:[Expanded(child: SizedBox(height:56, child: TextField(controller:otc,decoration:const InputDecoration(labelText:'OT', isDense:true, border:OutlineInputBorder()),keyboardType:TextInputType.number))), const SizedBox(width:8), Expanded(child: SizedBox(height:56, child: TextField(controller:TextEditingController(text: (rosterExtra[k]??0).toString()),decoration:const InputDecoration(labelText:'額外工時 (顯示)', isDense:true, border:OutlineInputBorder()))))]),
          const SizedBox(height:8),
          SizedBox(height:56, child: TextField(controller:exCtrl,decoration:const InputDecoration(labelText:'額外津貼 (當日)', isDense:true, border:OutlineInputBorder()),keyboardType:TextInputType.number)),
          const SizedBox(height:12),
          Row(children:[Expanded(child: OutlinedButton(onPressed:(){ setState(()=>roster.remove(k)); save(); Navigator.pop(ctx2); },child:const Text('清除'))), const SizedBox(width:8), Expanded(child: FilledButton(onPressed:(){ setState((){ if(cur.isNotEmpty) roster[k]=cur; rosterNote[k]=nc.text; rosterOt[k]=double.tryParse(otc.text)??0; rosterExtra[k]=double.tryParse(exCtrl.text)??0; }); save(); Navigator.pop(ctx2); },child:const Text('儲存')))])
        ]))
      );
    });
  });
}
Widget buildDayCell(DateTime d, String selKey){
  String k=DateFormat('yyyy-MM-dd').format(d); String? code=roster[k]; var def=code!=null?defs[code]:null;
  bool inM=d.month==focused.month; bool isToday=DateTime.now().year==d.year && DateTime.now().month==d.month && DateTime.now().day==d.day; bool sel=k==selKey;
  Color bg; if(isToday) bg=const Color(0xFFFFF9C4); else if(!inM) bg=const Color(0xFFF5F5F0); else if(def!=null) bg=def.color.withOpacity(0.18); else bg=const Color(0xFFFFF0D0);
  return GestureDetector(onTap:(){ setState(()=>selectedDay=d); },onLongPress:(){ setState(()=>selectedDay=d); showDetail(d); },
    child: Container(margin: const EdgeInsets.all(2), decoration: BoxDecoration(color:bg,borderRadius: BorderRadius.circular(12),border:isToday?Border.all(width:2.5,color:Colors.orange):sel?Border.all(width:2,color:Colors.deepPurple):null),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children:[Text('${d.day}',style:TextStyle(fontWeight:FontWeight.bold,fontSize:calendarFontSize-1)),if(code!=null)Container(padding:const EdgeInsets.symmetric(horizontal:4,vertical:1),decoration:BoxDecoration(color:def?.color,borderRadius:BorderRadius.circular(8)),child:Text(code,style:TextStyle(color:Colors.white,fontSize:calendarFontSize-2)))])
    )
  );
}
Widget calTab(){
  DateTime first=DateTime(focused.year,focused.month,1); DateTime start=first.subtract(Duration(days:first.weekday-1));
  int dim=DateTime(focused.year,focused.month+1,0).day; int weeks=((first.weekday-1+dim)/7).ceil(); if(weeks<5) weeks=5;
  List<DateTime> days=List.generate(weeks*7,(i)=>start.add(Duration(days:i))); String selKey=DateFormat('yyyy-MM-dd').format(selectedDay); DateTime today=DateTime.now();
  return SafeArea(child:Column(children:[
    Padding(padding:const EdgeInsets.fromLTRB(12,8,12,4),child:Row(children:[Text('${focused.year}年${focused.month}月',style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const Spacer(),IconButton(icon:const Icon(Icons.chevron_left),onPressed:(){ setState(()=>focused=DateTime(focused.year,focused.month-1,1)); }),IconButton(icon:const Icon(Icons.chevron_right),onPressed:(){ setState(()=>focused=DateTime(focused.year,focused.month+1,1)); }),FilledButton.tonal(onPressed:(){ setState((){ focused=DateTime(today.year,today.month,1); selectedDay=today; }); },child:const Text('今天'))])),
    Column(children:[
      Padding(padding:const EdgeInsets.symmetric(horizontal:6),child:Row(children:[const SizedBox(width:32,child:Text('週',textAlign:TextAlign.center,style:TextStyle(fontSize:11,fontWeight:FontWeight.bold,color:Colors.deepPurple))),Expanded(child:Row(children:["一","二","三","四","五","六","日"].map((w)=>Expanded(child:Text(w,textAlign:TextAlign.center,style:const TextStyle(fontSize:11)))).toList()))])),
      Column(children: List.generate(weeks, (row){ return Row(children:[Container(width:32,alignment:Alignment.center,child:Text('W${isoWeek(days[row*7])}',style:const TextStyle(fontSize:11,color:Colors.deepPurple))),Expanded(child: Row(children: List.generate(7, (col){ int idx=row*7+col; return Expanded(child: SizedBox(height:68,child: buildDayCell(days[idx], selKey))); }))) ]); })),
    ]),
    Container(width:double.infinity,padding:const EdgeInsets.all(10),color:Colors.white,child:Text('${DateFormat('MM/dd EEE').format(selectedDay)} ${roster[selKey]??'未排班'} | ${rosterNote[selKey]??'無記事'}')),
  ]));
}
Widget patternTab(){
  return SafeArea(child:Column(children:[
    const Padding(padding:EdgeInsets.only(top:12,bottom:4),child: Center(child: Text('排更模式',style:TextStyle(fontWeight:FontWeight.bold,fontSize:18)))),
    Padding(padding:const EdgeInsets.symmetric(horizontal:12,vertical:6),child: Row(mainAxisAlignment: MainAxisAlignment.center, children:[
      FilledButton.icon(icon:const Icon(Icons.add), label:const Text('加一行'), onPressed:(){ setState(()=>pattern.add(List.filled(7,'O'))); save(); }),
      const SizedBox(width:8),
      FilledButton.tonal(icon:const Icon(Icons.playlist_add), label:const Text('一次加N行'), onPressed:(){
        TextEditingController ctrl=TextEditingController(text:'3');
        showDialog(context:context, builder:(ctx)=>AlertDialog(title:const Text('一次加幾行?'),content:SizedBox(height:56, child: TextField(controller:ctrl,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'行數', isDense:true, border:OutlineInputBorder()))),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('取消')), FilledButton(onPressed:(){ int n=int.tryParse(ctrl.text)??1; setState(()=>pattern.addAll(List.generate(n, (_)=>List.filled(7,'O')))); save(); Navigator.pop(ctx); },child:const Text('確定'))]));
      }),
      const SizedBox(width:8),
      FilledButton(onPressed:() async {
        DateTimeRange? p=await showDateRangePicker(context:context,firstDate:DateTime(2023),lastDate:DateTime(2030)); if(p==null) return;
        var flat=pattern.expand((e)=>e).toList(); setState((){ int i=0; for(DateTime d=p.start;!d.isAfter(p.end);d=d.add(const Duration(days:1))){ roster[DateFormat('yyyy-MM-dd').format(d)]=flat[i%flat.length]; i++; } }); save(); setState(()=>tab=0);
      },child:const Text('選日期自動排班')),
    ])),
    SingleChildScrollView(scrollDirection: Axis.horizontal, padding:const EdgeInsets.all(8), child: Row(children: defs.keys.map((k)=>Padding(padding:const EdgeInsets.only(right:8),child: Chip(label:Text(k),backgroundColor:defs[k]!.color.withOpacity(0.3))))).toList()),
    Expanded(child: ListView.builder(itemCount:pattern.length,itemBuilder:(ctx,r){
      return Card(margin:const EdgeInsets.symmetric(horizontal:8,vertical:4),child: Padding(padding:const EdgeInsets.all(6),child: Row(children:[
        SizedBox(width:28,child: Text('${r+1}',textAlign:TextAlign.center,style:const TextStyle(fontWeight:FontWeight.bold))),
        Expanded(child: Row(children: List.generate(7, (c){ return Expanded(child: GestureDetector(onTap:(){ showModalBottomSheet(context:context,builder:(ctx)=>Wrap(children:defs.keys.map((k)=>ListTile(title:Text(k),onTap:(){ setState(()=>pattern[r][c]=k); save(); Navigator.pop(ctx); })).toList())); },child: Container(margin:const EdgeInsets.all(2),height:40,decoration:BoxDecoration(color:defs[pattern[r][c]]?.color.withOpacity(0.3),borderRadius:BorderRadius.circular(8)),child:Center(child:Text(pattern[r][c]))))); }))),
        IconButton(icon:const Icon(Icons.delete),onPressed:(){ setState(()=>pattern.removeAt(r)); save(); })
      ])));
    })),
  ]));
}
Widget reportTab(){
  int dim=DateTime(focused.year,focused.month+1,0).day; double hrs=0,allow=0; Map<String,int> cnt={}; double extraDayAllow=0;
  for(int i=1;i<=dim;i++){ String k=DateFormat('yyyy-MM-dd').format(DateTime(focused.year,focused.month,i)); var code=roster[k]; if(code==null) continue; var d=defs[code]; if(d!=null){ hrs+=d.hours; if(d.hasAllowance) allow+=d.allowance; cnt[code]=(cnt[code]??0)+1; } extraDayAllow+=rosterExtra[k]??0; }
  double fixedExtra = extraAllowances.fold(0, (s,e)=>s+e.amount);
  double totalAllow = allow + extraDayAllow + fixedExtra;
  return ListView(padding:const EdgeInsets.all(12),children:[
    Text('${focused.year}年${focused.month}月報表',style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
   ...cnt.entries.map((e)=>ListTile(title:Text(e.key),trailing:Text('${e.value}次'))),
    const Divider(),
    ListTile(title:const Text('總工時'),trailing:Text('$hrs')),
    ListTile(title:Text('班次津貼'),trailing:Text('\$$allow')),
    ListTile(title:Text('當日額外津貼(按日)'),trailing:Text('\$$extraDayAllow')),
    const Divider(),
    Row(children:[const Text('額外津貼 (自定名)',style:TextStyle(fontWeight:FontWeight.bold)), const Spacer(), IconButton(icon:const Icon(Icons.add),onPressed:(){
      TextEditingController nCtrl=TextEditingController(); TextEditingController aCtrl=TextEditingController();
      showDialog(context:context, builder:(ctx)=>AlertDialog(title:const Text('新增津貼'),content:Column(mainAxisSize:MainAxisSize.min,children:[
        SizedBox(height:56, child: TextField(controller:nCtrl,decoration:const InputDecoration(labelText:'名稱 (例如 大假津貼)', isDense:true, border:OutlineInputBorder()))),
        const SizedBox(height:8),
        SizedBox(height:56, child: TextField(controller:aCtrl,decoration:const InputDecoration(labelText:'金額', isDense:true, border:OutlineInputBorder()),keyboardType:TextInputType.number)),
      ]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('取消')), FilledButton(onPressed:(){ if(nCtrl.text.isEmpty) return; setState(()=>extraAllowances.add(ExtraAllowance(nCtrl.text,double.tryParse(aCtrl.text)??0))); save(); Navigator.pop(ctx); },child:const Text('新增'))]));
    })]),
   ...extraAllowances.asMap().entries.map((e)=>ListTile(title: Text(e.value.name), trailing: Row(mainAxisSize: MainAxisSize.min, children:[Text('\$${e.value.amount}'), IconButton(icon:const Icon(Icons.delete),onPressed:(){ setState(()=>extraAllowances.removeAt(e.key)); save(); })]))),
    const Divider(),
    ListTile(title:const Text('總津貼 (含自定)',style:TextStyle(fontWeight:FontWeight.bold)),trailing:Text('\$$totalAllow',style:const TextStyle(fontWeight:FontWeight.bold,fontSize:16))),
  ]);
}
Widget settingsTab(){
  return ListView(padding:const EdgeInsets.all(16),children:[
    SwitchListTile(title:const Text('啟用日曆同步'),subtitle:Text(_rosterCalendarId??'未選日曆'),value:googleSyncEnabled,onChanged:(v) async {
      if(v){ String? id=await _pickGoogleCalendarDialog(); if(id==null) return; _rosterCalendarId=id; setState(()=>googleSyncEnabled=true); save(); if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已選日曆 $id'))); } else { setState(()=>googleSyncEnabled=false); save(); }
    }),
    ListTile(title:const Text('手動同步去重 (先刪後加)'),subtitle:const Text('用 [RosterPro]yyyy-MM-dd 標籤去重，全天 allDay:true'),onTap:()=>_syncToGoogle()),
    const ListTile(title:Text('桌面Widget已接通'),subtitle:Text('今日/明日更份會自動更新到桌面小工具 (RosterWidgetProvider)')),
  ]);
}
@override Widget build(BuildContext context){ return Scaffold(body:[calTab(),patternTab(),reportTab(),settingsTab()][tab],bottomNavigationBar:NavigationBar(selectedIndex:tab,onDestinationSelected:(i)=>setState(()=>tab=i),destinations:const[NavigationDestination(icon:Icon(Icons.calendar_month),label:'月曆'),NavigationDestination(icon:Icon(Icons.pattern),label:'模式'),NavigationDestination(icon:Icon(Icons.bar_chart),label:'報表'),NavigationDestination(icon:Icon(Icons.settings),label:'設定')])); }
}
