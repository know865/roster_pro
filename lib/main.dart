import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

void main(){runApp(const RosterApp());}

class ShiftDef{
  String code;String label;double hours;double allowance;double ot;Color color;
  ShiftDef(this.code,this.label,this.hours,this.color,{this.allowance=0,this.ot=0});
  Map<String,dynamic> toJson()=>{'code':code,'label':label,'hours':hours,'allowance':allowance,'ot':ot,'color':color.value};
  factory ShiftDef.fromJson(Map<String,dynamic> j)=>ShiftDef(j['code'],j['label']??j['code'],(j['hours']??8).toDouble(),Color(j['color']??0xFFFF9800),allowance:(j['allowance']??0).toDouble(),ot:(j['ot']??0).toDouble());
}

class RosterApp extends StatelessWidget{
  const RosterApp({super.key});
  @override Widget build(BuildContext context){return MaterialApp(title:'Roster Pro v6.27',theme:ThemeData(useMaterial3:true,colorSchemeSeed:Colors.deepPurple),home:const MainPage());}
}

class MainPage extends StatefulWidget{const MainPage({super.key}); @override State<MainPage> createState()=>MainPageState();}

class MainPageState extends State<MainPage>{
int tab=0; DateTime focused=DateTime.now(); DateTime selectedDay=DateTime.now();
Map<String,String> roster={}; Map<String,String> rosterNote={};
Map<String,ShiftDef> defs={
  '早':ShiftDef('早','早更 07:00-15:30',8,Colors.orange),
  '中':ShiftDef('中','中更 14:00-22:00',8,Colors.blue),
  '宵':ShiftDef('宵','宵更 22:00-06:00',8,Colors.purple,allowance:60),
  'O':ShiftDef('O','休',0,Colors.green),
  '早收':ShiftDef('早收','早收長代號',8,Colors.orange),
};
List<List<String>> pattern=[["早","早","中","中","宵","宵","O"],["早","早","早","中","中","O","O"]];
double carry=0; String customName='我的排更';

@override void initState(){super.initState();load();}
Future<void> load() async{
  var sp=await SharedPreferences.getInstance();
  var r=sp.getString('roster'); if(r!=null) roster=Map<String,String>.from(jsonDecode(r));
  var rn=sp.getString('note'); if(rn!=null) rosterNote=Map<String,String>.from(jsonDecode(rn));
  var d=sp.getString('defs'); if(d!=null){try{var m=Map<String,dynamic>.from(jsonDecode(d)); defs=m.map((k,v)=>MapEntry(k,ShiftDef.fromJson(v)));}catch(_){}}
  var p=sp.getString('pattern'); if(p!=null){try{var l=jsonDecode(p) as List; pattern=l.map<List<String>>((row)=>(row as List).map<String>((e)=>e.toString()).toList()).toList();}catch(_){}}
  setState((){carry=sp.getDouble('carry')??0; customName=sp.getString('cName')??'我的排更';});
}
Future<void> save() async{
  var sp=await SharedPreferences.getInstance();
  sp.setString('roster',jsonEncode(roster)); sp.setString('note',jsonEncode(rosterNote));
  sp.setString('defs',jsonEncode(defs.map((k,v)=>MapEntry(k,v.toJson()))));
  sp.setString('pattern',jsonEncode(pattern)); sp.setDouble('carry',carry); sp.setString('cName',customName);
}
int isoWeek(DateTime d){var jan1=DateTime(d.year,1,1); return 1+((d.difference(jan1).inDays+jan1.weekday-1)/7).floor();}

Widget calTab(){
  DateTime first=DateTime(focused.year,focused.month,1); DateTime start=first.subtract(Duration(days:first.weekday-1)); List<DateTime> days=List.generate(42,(i)=>start.add(Duration(days:i))); String selKey=DateFormat('yyyy-MM-dd').format(selectedDay);
  return SafeArea(child:Column(children:[
    Padding(padding:const EdgeInsets.fromLTRB(12,8,12,4),child:Row(children:[const Icon(Icons.calendar_month,size:22),const SizedBox(width:8),Text('${focused.year}年${focused.month}月',style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const Spacer(),IconButton(icon:const Icon(Icons.chevron_left),onPressed:(){setState(()=>focused=DateTime(focused.year,focused.month-1,1));}),IconButton(icon:const Icon(Icons.chevron_right),onPressed:(){setState(()=>focused=DateTime(focused.year,focused.month+1,1));}),FilledButton.tonal(onPressed:(){setState((){focused=DateTime.now(); selectedDay=DateTime.now();});},child:const Text('今天'))])),
    Padding(padding:const EdgeInsets.symmetric(horizontal:8,vertical:4),child:Row(children:const [Expanded(child:Text('Mon',textAlign:TextAlign.center,style:TextStyle(fontSize:12))),Expanded(child:Text('Tue',textAlign:TextAlign.center,style:TextStyle(fontSize:12))),Expanded(child:Text('Wed',textAlign:TextAlign.center,style:TextStyle(fontSize:12))),Expanded(child:Text('Thu',textAlign:TextAlign.center,style:TextStyle(fontSize:12))),Expanded(child:Text('Fri',textAlign:TextAlign.center,style:TextStyle(fontSize:12))),Expanded(child:Text('Sat',textAlign:TextAlign.center,style:TextStyle(fontSize:12))),Expanded(child:Text('Sun',textAlign:TextAlign.center,style:TextStyle(fontSize:12)))])),
    Expanded(child:GridView.builder(padding:const EdgeInsets.all(6),gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:7,childAspectRatio:0.78,mainAxisSpacing:6,crossAxisSpacing:6),itemCount:42,itemBuilder:(ctx,idx){
      DateTime day=days[idx]; bool inM=day.month==focused.month; String k=DateFormat('yyyy-MM-dd').format(day); String? code=roster[k]; var def=code!=null?defs[code]:null; bool sel=k==selKey; String w=idx%7==0?'W${isoWeek(day)}':''; Color bg=!inM?const Color(0xFFF5F5F0):sel?Colors.white:def!=null?def.color.withOpacity(0.15):const Color(0xFFFFF0D0); if(code=='O') bg=const Color(0xFFE0F2E9);
      return GestureDetector(onTap:(){setState(()=>selectedDay=day); showDetail(day);},child:Container(decoration:BoxDecoration(color:bg,borderRadius:BorderRadius.circular(16),border:sel?Border.all(width:2):null),child:Stack(children:[if(w.isNotEmpty) Positioned(left:6,top:4,child:Text(w,style:const TextStyle(fontSize:9,fontWeight:FontWeight.bold,color:Colors.brown))),Center(child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Text('${day.day}',style:TextStyle(fontWeight:FontWeight.bold,color:inM?Colors.black:Colors.grey)),if(code!=null) Container(margin:const EdgeInsets.only(top:4),padding:const EdgeInsets.symmetric(horizontal:8,vertical:2),decoration:BoxDecoration(color:def?.color??Colors.orange,borderRadius:BorderRadius.circular(10)),child:Text(code,style:const TextStyle(color:Colors.white,fontSize:12)))]))]))); })),
    Container(padding:const EdgeInsets.fromLTRB(12,8,12,12),decoration:BoxDecoration(color:Colors.white,border:Border(top:BorderSide(color:Colors.grey.shade200))),child:Row(children:[Expanded(child:Text('${DateFormat('MM/dd EEE').format(selectedDay)} ${roster[selKey]??''} ${rosterNote[selKey]??'無記事'}',style:const TextStyle(fontSize:15,fontWeight:FontWeight.bold))),FilledButton(onPressed:(){showDetail(selectedDay);},child:const Text('編輯'))])),
  ]));
}
void showDetail(DateTime day){String k=DateFormat('yyyy-MM-dd').format(day); String cur=roster[k]??''; var nc=TextEditingController(text:rosterNote[k]??''); showModalBottomSheet(context:context,isScrollControlled:true,builder:(ctx){return StatefulBuilder(builder:(ctx2,setM){return Padding(padding:EdgeInsets.only(bottom:MediaQuery.of(ctx2).viewInsets.bottom),child:Padding(padding:const EdgeInsets.all(16),child:Column(mainAxisSize:MainAxisSize.min,children:[Text(DateFormat('yyyy-MM-dd EEE').format(day),style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),Wrap(spacing:8,children:defs.keys.map((c)=>ChoiceChip(label:Text(c),selected:cur==c,onSelected:(_)=>setM(()=>cur=c))).toList()),TextField(controller:nc,decoration:const InputDecoration(labelText:'記事')),const SizedBox(height:12),Row(children:[Expanded(child:OutlinedButton(onPressed:()=>Navigator.pop(ctx2),child:const Text('取消'))),const SizedBox(width:8),Expanded(child:FilledButton(onPressed:(){setState((){if(cur!=''){roster[k]=cur; rosterNote[k]=nc.text;}}); save(); Navigator.pop(ctx2);},child:const Text('儲存')))])])));});});}

Future<void> pickRangeAndApply() async{
  DateTimeRange? picked=await showDateRangePicker(context:context,initialDateRange:DateTimeRange(start:DateTime(focused.year,focused.month,1),end:DateTime(focused.year,focused.month+1,0)),firstDate:DateTime(2023),lastDate:DateTime(2030),locale:const Locale('zh','HK'));
  if(picked==null) return;
  List<String> flat=pattern.expand((e)=>e).toList(); if(flat.isEmpty) return;
  setState((){int idx=0; for(DateTime d=picked.start;!d.isAfter(picked.end); d=d.add(const Duration(days:1))){String k=DateFormat('yyyy-MM-dd').format(d); roster[k]=flat[idx%flat.length]; idx++;}});
  save(); setState(()=>tab=0);
  if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('已套用 ${DateFormat('MM/dd').format(picked.start)} - ${DateFormat('MM/dd').format(picked.end)} 共 ${picked.end.difference(picked.start).inDays+1} 天')));
}
Widget patternTab(){return SafeArea(child:Column(children:[Padding(padding:const EdgeInsets.fromLTRB(16,12,16,8),child:Row(children:[const Text('排更模式 7天 x 自定行數',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),const Spacer(),FilledButton.tonal(onPressed:(){setState(()=>pattern.add(List.filled(7,'O'))); save();},child:const Text('加一行')),const SizedBox(width:8),FilledButton.tonal(onPressed:(){if(pattern.length>1){setState(()=>pattern.removeLast()); save();}},child:const Text('減一行'))])),Expanded(child:ListView.builder(itemCount:pattern.length,itemBuilder:(ctx,r){return Padding(padding:const EdgeInsets.symmetric(horizontal:8,vertical:2),child:Row(children:[SizedBox(width:28,child:Text('${r+1}',textAlign:TextAlign.center,style:const TextStyle(fontWeight:FontWeight.bold))),Expanded(child:Row(children:List.generate(7,(c){String code=pattern[r][c]; var d=defs[code]; return Expanded(child:GestureDetector(onTap:(){showModalBottomSheet(context:context,builder:(ctx){return SafeArea(child:Wrap(children:defs.keys.map((k){var def=defs[k]!; return ListTile(leading:CircleAvatar(backgroundColor:def.color,radius:12),title:Text('$k - ${def.label}'),onTap:(){setState(()=>pattern[r][c]=k); save(); Navigator.pop(ctx);});}).toList()));});},child:Container(margin:const EdgeInsets.all(3),height:44,decoration:BoxDecoration(color:d!=null?d.color.withOpacity(0.25):Colors.white,border:Border.all(color:Colors.grey.shade300),borderRadius:BorderRadius.circular(10)),child:Center(child:FittedBox(child:Text(code,style:const TextStyle(fontWeight:FontWeight.bold)))))));}))),IconButton(icon:const Icon(Icons.delete_outline,size:20),onPressed:(){setState(()=>pattern.removeAt(r)); save();})]));})),Padding(padding:const EdgeInsets.fromLTRB(16,8,16,16),child:Column(children:[Container(padding:const EdgeInsets.all(10),decoration:BoxDecoration(color:Colors.orange.shade50,borderRadius:BorderRadius.circular(12)),child:const Row(children:[Icon(Icons.info_outline,size:16),SizedBox(width:6),Expanded(child:Text('先選擇日期範圍，再按套用，不會再一按就排成個月',style:TextStyle(fontSize:12)))])),const SizedBox(height:10),SizedBox(width:double.infinity,height:52,child:FilledButton.icon(onPressed:pickRangeAndApply,icon:const Icon(Icons.date_range),label:const Text('選擇日期範圍並自動排班',style:TextStyle(fontSize:16))))]))]));}

Widget reportTab(){int dim=DateTime(focused.year,focused.month+1,0).day; Map<String,int> cnt={}; double hrs=0,allow=0; for(int i=1;i<=dim;i++){String k=DateFormat('yyyy-MM-dd').format(DateTime(focused.year,focused.month,i)); String? c=roster[k]; if(c==null) continue; cnt[c]=(cnt[c]??0)+1; var d=defs[c]; if(d!=null){hrs+=d.hours; allow+=d.allowance;}} return SafeArea(child:ListView(padding:const EdgeInsets.all(12),children:[Text('${focused.year}年${focused.month}月 報表',style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const SizedBox(height:8),Card(child:ListTile(title:const Text('本月班次統計'),subtitle:Text(cnt.isEmpty?'暫無':cnt.entries.map((e)=>'${e.key}x${e.value}').join(' ')))),Card(color:const Color(0xFFE3F2FD),child:ListTile(title:Text('總工時 ${hrs}h'),subtitle:Text('承上 $carry + 本月 = ${carry+hrs}h'))),Card(color:const Color(0xFFE8F5E9),child:ListTile(title:Text('津貼總額 \$${allow.toStringAsFixed(0)}')))]));}

Future<void> backupLocalFile() async{
  var dir=await getApplicationDocumentsDirectory(); var f=File('${dir.path}/roster_backup.json');
  await f.writeAsString(jsonEncode({'roster':roster,'note':rosterNote,'defs':defs.map((k,v)=>MapEntry(k,v.toJson())),'pattern':pattern,'carry':carry,'cName':customName}));
  if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('已備份到 ${f.path}')));
}
Future<void> restoreLocalFile() async{
  var res=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['json']);
  if(res==null) return; try{String c=await File(res.files.single.path!).readAsString(); var j=jsonDecode(c);
  setState((){if(j['roster']!=null) roster=Map<String,String>.from(j['roster']); if(j['note']!=null) rosterNote=Map<String,String>.from(j['note']); if(j['defs']!=null) defs=(j['defs'] as Map).map<String,ShiftDef>((k,v)=>MapEntry(k,ShiftDef.fromJson(Map<String,dynamic>.from(v)))); if(j['pattern']!=null) pattern=(j['pattern'] as List).map<List<String>>((r)=>(r as List).map<String>((e)=>e.toString()).toList()).toList(); if(j['carry']!=null) carry=(j['carry'] as num).toDouble(); if(j['cName']!=null) customName=j['cName'];}); save();
  if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('已從手機還原')));}catch(e){if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('還原失敗 $e')));}
}
Future<void> exportICS() async{
  StringBuffer ics=StringBuffer('BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Roster Pro//\n');
  roster.forEach((k,v){try{DateTime d=DateFormat('yyyy-MM-dd').parse(k); String dt=DateFormat('yyyyMMdd').format(d); String dt2=DateFormat('yyyyMMdd').format(d.add(const Duration(days:1))); ics.writeln('BEGIN:VEVENT\nDTSTART;VALUE=DATE:$dt\nDTEND;VALUE=DATE:$dt2\nSUMMARY:$v ${defs[v]?.label??''}\nDESCRIPTION:${rosterNote[k]??''}\nEND:VEVENT');}catch(_){}});
  ics.writeln('END:VCALENDAR'); var dir=await getApplicationDocumentsDirectory(); var f=File('${dir.path}/$customName.ics'); await f.writeAsString(ics.toString());
  if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('已匯出 ${f.path}')));
}

Widget settingsTab(){
  String backupCode=jsonEncode({'roster':roster,'note':rosterNote,'defs':defs.map((k,v)=>MapEntry(k,v.toJson())),'pattern':pattern});
  return SafeArea(child:ListView(padding:const EdgeInsets.all(16),children:[
    const Text('自定班次內容編輯和刪除',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
    Card(child:Column(children:[...defs.entries.map((e){var d=e.value; return ListTile(leading:CircleAvatar(backgroundColor:d.color,radius:14,child:Text(d.code,style:const TextStyle(color:Colors.white,fontSize:11))),title:Text('${d.code} - ${d.label}'),subtitle:Text('${d.hours}h 津貼\$${d.allowance} OT${d.ot}h'),trailing:Row(mainAxisSize:MainAxisSize.min,children:[IconButton(icon:const Icon(Icons.edit,size:18),onPressed:(){editShift(d);}),IconButton(icon:const Icon(Icons.delete,size:18),onPressed:(){setState(()=>defs.remove(e.key)); save();})]));}),ListTile(leading:const Icon(Icons.add),title:const Text('新增自定班次'),onTap:(){editShift(null);})])),
    const SizedBox(height:16),
    const Text('自定津貼編輯和刪除',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
    Card(child:Column(children:defs.entries.map((e){var d=e.value; return ListTile(title:Text('${d.code} 津貼'),subtitle:Slider(value:d.allowance.clamp(0,200),min:0,max:200,divisions:20,label:'\$${d.allowance.round()}',onChanged:(v){setState(()=>d.allowance=v); save();}),trailing:Row(mainAxisSize:MainAxisSize.min,children:[Text('\$${d.allowance.toStringAsFixed(0)}'),IconButton(icon:const Icon(Icons.delete_outline,size:18),onPressed:(){setState(()=>d.allowance=0); save();})]));}).toList())),
    const SizedBox(height:16),
    const Text('備份與匯出',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
    Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(children:[Row(children:[Expanded(child:OutlinedButton.icon(onPressed:backupLocalFile,icon:const Icon(Icons.save_alt),label:const Text('備份到手機'))),const SizedBox(width:8),Expanded(child:OutlinedButton.icon(onPressed:restoreLocalFile,icon:const Icon(Icons.folder_open),label:const Text('從手機還原')))]),const SizedBox(height:8),SizedBox(width:double.infinity,child:OutlinedButton.icon(onPressed:exportICS,icon:const Icon(Icons.calendar_month),label:Text('匯出 $customName.ics')))]))),
    const SizedBox(height:16),
    const Text('專屬排更日曆 (可自定名稱)',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
    Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[TextField(decoration:InputDecoration(labelText:'日曆名稱',hintText:customName),onSubmitted:(v){setState(()=>customName=v.isEmpty?'我的排更':v); save();}),const SizedBox(height:8),Row(children:[Expanded(child:Text('現時名稱：$customName',style:const TextStyle(fontWeight:FontWeight.bold))),FilledButton.tonal(onPressed:(){setState(()=>customName=customName); save(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('已設定為 $customName')));},child:const Text('確認'))])]))),
    const SizedBox(height:16),
    Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('備份碼 (長按全選複製)',style:TextStyle(fontWeight:FontWeight.bold)),const SizedBox(height:8),Container(padding:const EdgeInsets.all(8),decoration:BoxDecoration(color:Colors.grey.shade100,borderRadius:BorderRadius.circular(8)),child:SelectableText(backupCode,style:const TextStyle(fontSize:10)))]))),
    const SizedBox(height:16),
    Card(child:ListTile(title:const Text('承上結餘修改'),subtitle:Text('$carry h'),trailing:IconButton(icon:const Icon(Icons.edit),onPressed:(){var ctrl=TextEditingController(text:carry.toString()); showDialog(context:context,builder:(c)=>AlertDialog(title:const Text('修改承上'),content:TextField(controller:ctrl,keyboardType:TextInputType.number),actions:[FilledButton(onPressed:(){setState(()=>carry=double.tryParse(ctrl.text)??carry); save(); Navigator.pop(c);},child:const Text('儲存'))]));}))),
  ]));
}

void editShift(ShiftDef? oldDef){
  var codeCtrl=TextEditingController(text:oldDef?.code??''); var labelCtrl=TextEditingController(text:oldDef?.label??''); var hoursCtrl=TextEditingController(text:oldDef?.hours.toString()??'8'); var allowCtrl=TextEditingController(text:oldDef?.allowance.toString()??'0'); var otCtrl=TextEditingController(text:oldDef?.ot.toString()??'0'); Color col=oldDef?.color??Colors.orange;
  showDialog(context:context,builder:(ctx){return StatefulBuilder(builder:(ctx2,setD){return AlertDialog(title:Text(oldDef==null?'新增自定班次':'編輯 ${oldDef.code}'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:codeCtrl,decoration:const InputDecoration(labelText:'代碼 如 早收')),TextField(controller:labelCtrl,decoration:const InputDecoration(labelText:'內容說明')),Row(children:[Expanded(child:TextField(controller:hoursCtrl,decoration:const InputDecoration(labelText:'工時'),keyboardType:TextInputType.number)),const SizedBox(width:8),Expanded(child:TextField(controller:allowCtrl,decoration:const InputDecoration(labelText:'津貼 \$'),keyboardType:TextInputType.number))]),Row(children:[Expanded(child:TextField(controller:otCtrl,decoration:const InputDecoration(labelText:'OT'),keyboardType:TextInputType.number)),const SizedBox(width:8),Expanded(child:Container())]),const SizedBox(height:10),Wrap(spacing:6,children:[Colors.orange,Colors.blue,Colors.purple,Colors.green,Colors.brown,Colors.red,Colors.teal,Colors.indigo].map((c)=>GestureDetector(onTap:()=>setD(()=>col=c),child:CircleAvatar(backgroundColor:c,radius:16,child:col==c?const Icon(Icons.check,size:16,color:Colors.white):null))).toList())])),actions:[TextButton(onPressed:()=>Navigator.pop(ctx2),child:const Text('取消')),FilledButton(onPressed:(){String code=codeCtrl.text.trim(); if(code.isEmpty) return; setState((){if(oldDef!=null&&oldDef.code!=code) defs.remove(oldDef.code); defs[code]=ShiftDef(code,labelCtrl.text.isEmpty?code:labelCtrl.text,double.tryParse(hoursCtrl.text)??8,col,allowance:double.tryParse(allowCtrl.text)??0,ot:double.tryParse(otCtrl.text)??0);}); save(); Navigator.pop(ctx2);},child:const Text('儲存'))]);});});
}
@override Widget build(BuildContext context){return Scaffold(body:[calTab(),patternTab(),reportTab(),settingsTab()][tab],bottomNavigationBar:NavigationBar(selectedIndex:tab,onDestinationSelected:(i)=>setState(()=>tab=i),destinations:const[NavigationDestination(icon:Icon(Icons.calendar_month),label:'月曆'),NavigationDestination(icon:Icon(Icons.pattern),label:'模式'),NavigationDestination(icon:Icon(Icons.bar_chart),label:'報表'),NavigationDestination(icon:Icon(Icons.settings),label:'設定')]));}
}
