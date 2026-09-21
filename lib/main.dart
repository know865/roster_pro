import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

void main(){runApp(const RosterApp());}

class ShiftDef{
  String code; String label; double hours; double allowance; double ot; Color color;
  String start; String end;
  ShiftDef(this.code,this.label,this.hours,this.color,{this.allowance=0,this.ot=0,this.start='07:00',this.end='15:30'});
  Map<String,dynamic> toJson()=>{'code':code,'label':label,'hours':hours,'allowance':allowance,'ot':ot,'color':color.value,'start':start,'end':end};
  factory ShiftDef.fromJson(Map<String,dynamic> j)=>ShiftDef(j['code'],j['label']??j['code'],(j['hours']??8).toDouble(),Color(j['color']??0xFFFF9800),allowance:(j['allowance']??0).toDouble(),ot:(j['ot']??0).toDouble(),start:j['start']??'07:00',end:j['end']??'15:30');
}

class ExtraAllowance{
  String name; double amount; DateTime startDate;
  ExtraAllowance(this.name,this.amount,this.startDate);
  Map<String,dynamic> toJson()=>{'name':name,'amount':amount,'start':DateFormat('yyyy-MM-dd').format(startDate)};
  factory ExtraAllowance.fromJson(Map<String,dynamic> j)=>ExtraAllowance(j['name'],(j['amount'] as num).toDouble(),DateTime.tryParse(j['start']??'')??DateTime(2020,1,1));
}

class RosterApp extends StatelessWidget{
  const RosterApp({super.key});
  @override Widget build(BuildContext context){return MaterialApp(title:'Roster Pro v6.35',theme:ThemeData(useMaterial3:true,colorSchemeSeed:Colors.deepPurple),home:const MainPage());}
}

const Map<String,String> hkHolidays={'2026-09-26':'中秋翌日','2026-10-01':'國慶','2026-12-25':'聖誕','2026-10-19':'重陽'};

class MainPage extends StatefulWidget{const MainPage({super.key}); @override State<MainPage> createState()=>MainPageState();}

class MainPageState extends State<MainPage>{
int tab=0; DateTime focused=DateTime.now(); DateTime selectedDay=DateTime.now();
Map<String,String> roster={}; Map<String,String> rosterNote={}; Map<String,double> rosterOt={};
Map<String,ShiftDef> defs={
  '早':ShiftDef('早','早更',8,Colors.orange,allowance:80,start:'07:00',end:'15:30'),
  '中':ShiftDef('中','中更',8,Colors.blue,start:'14:00',end:'22:00'),
  '宵':ShiftDef('宵','宵更',8,Colors.purple,allowance:60,start:'22:00',end:'06:00'),
  'O':ShiftDef('O','休',0,Colors.green,start:'00:00',end:'00:00'),
};
List<List<String>> pattern=[["早","早","中","中","宵","宵","O"],["早","早","早","中","中","O","O"]];
double carry=0; String customName='我的排更'; TextEditingController nameCtrl=TextEditingController();
double standardWeeklyHours=44; double overtimeRate=80;
List<ExtraAllowance> extraAllowances=[];
double calendarFontSize=12;

@override void initState(){super.initState();nameCtrl.text=customName;load();}
Future<void> load() async{
  var sp=await SharedPreferences.getInstance();
  var r=sp.getString('roster'); if(r!=null) roster=Map<String,String>.from(jsonDecode(r));
  var rn=sp.getString('note'); if(rn!=null) rosterNote=Map<String,String>.from(jsonDecode(rn));
  var ro=sp.getString('roOt'); if(ro!=null){try{rosterOt=Map<String,double>.from(jsonDecode(ro).map((k,v)=>MapEntry(k,(v as num).toDouble())));}catch(_){}}
  var d=sp.getString('defs'); if(d!=null){try{var m=Map<String,dynamic>.from(jsonDecode(d)); defs=m.map((k,v)=>MapEntry(k,ShiftDef.fromJson(Map<String,dynamic>.from(v))));}catch(_){}}
  var p=sp.getString('pattern'); if(p!=null){try{var l=jsonDecode(p) as List; pattern=l.map<List<String>>((row)=>(row as List).map<String>((e)=>e.toString()).toList()).toList();}catch(_){}}
  var ea=sp.getString('extraAllowNew'); if(ea!=null){try{extraAllowances=(jsonDecode(ea) as List).map((e)=>ExtraAllowance.fromJson(Map<String,dynamic>.from(e))).toList();}catch(_){}}
  setState((){
    carry=sp.getDouble('carry')??0; customName=sp.getString('cName')??'我的排更'; nameCtrl.text=customName;
    standardWeeklyHours=sp.getDouble('stdWeek')??44; overtimeRate=sp.getDouble('otRate')??80;
    calendarFontSize=sp.getDouble('calFont')??12;
  });
}
Future<void> save() async{
  var sp=await SharedPreferences.getInstance();
  sp.setString('roster',jsonEncode(roster)); sp.setString('note',jsonEncode(rosterNote)); sp.setString('roOt',jsonEncode(rosterOt));
  sp.setString('defs',jsonEncode(defs.map((k,v)=>MapEntry(k,v.toJson())))); sp.setString('pattern',jsonEncode(pattern));
  sp.setDouble('carry',carry); sp.setString('cName',customName); sp.setDouble('stdWeek',standardWeeklyHours);
  sp.setDouble('otRate',overtimeRate); sp.setString('extraAllowNew',jsonEncode(extraAllowances.map((e)=>e.toJson()).toList()));
  sp.setDouble('calFont',calendarFontSize);
}
int isoWeek(DateTime d){var jan1=DateTime(d.year,1,1); return 1+((d.difference(jan1).inDays+jan1.weekday-1)/7).floor();}

void quickJumpMonth({bool forReport=false}){
  int y=focused.year; int m=focused.month;
  showDialog(context:context,builder:(ctx){return StatefulBuilder(builder:(ctx2,setD){return AlertDialog(title:Text(forReport?'選擇報表年月':'快速查找年月'),content:Column(mainAxisSize:MainAxisSize.min,children:[
    Row(children:[IconButton(icon:const Icon(Icons.remove),onPressed:()=>setD(()=>y--)),Expanded(child:Text('$y年',textAlign:TextAlign.center,style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold))),IconButton(icon:const Icon(Icons.add),onPressed:()=>setD(()=>y++))]),
    Wrap(spacing:8,children:List.generate(12,(i){int mon=i+1;return ChoiceChip(label:Text('${mon}月'),selected:mon==m,onSelected:(_)=>setD(()=>m=mon));})),
  ]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx2),child:const Text('取消')),FilledButton(onPressed:(){setState(()=>focused=DateTime(y,m,1));Navigator.pop(ctx2);},child:const Text('跳轉'))]);});});
}

Widget calTab(){
  DateTime first=DateTime(focused.year,focused.month,1);
  DateTime start=first.subtract(Duration(days:first.weekday-1));
  List<DateTime> days=List.generate(42,(i)=>start.add(Duration(days:i)));
  String selKey=DateFormat('yyyy-MM-dd').format(selectedDay);
  var selDef=roster[selKey]!=null?defs[roster[selKey]]:null;
  double selOt=rosterOt[selKey]??selDef?.ot??0;
  return SafeArea(child:Column(children:[
    Padding(padding:const EdgeInsets.fromLTRB(12,8,12,4),child:Row(children:[
      InkWell(onTap:()=>quickJumpMonth(),child:Row(children:[Text('${focused.year}年${focused.month}月',style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const Icon(Icons.arrow_drop_down)])),
      const Spacer(),
      IconButton(icon:const Icon(Icons.chevron_left),onPressed:(){setState(()=>focused=DateTime(focused.year,focused.month-1,1));}),
      IconButton(icon:const Icon(Icons.chevron_right),onPressed:(){setState(()=>focused=DateTime(focused.year,focused.month+1,1));}),
      FilledButton.tonal(onPressed:(){setState((){focused=DateTime.now();selectedDay=DateTime.now();});},child:const Text('今天')),
    ])),
    Expanded(child:GridView.builder(padding:const EdgeInsets.all(6),gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:7,childAspectRatio:0.72,mainAxisSpacing:6,crossAxisSpacing:6),itemCount:42,itemBuilder:(ctx,idx){
      DateTime day=days[idx]; bool inM=day.month==focused.month; String k=DateFormat('yyyy-MM-dd').format(day);
      String? code=roster[k]; var def=code!=null?defs[code]:null; bool sel=k==selKey; String? hol=hkHolidays[k];
      bool hasNote=rosterNote[k]!=null && rosterNote[k]!.trim().isNotEmpty;
      Color bg=!inM?const Color(0xFFF5F5F0):hol!=null?const Color(0xFFFFEBEE):sel?Colors.white:def!=null?def.color.withOpacity(0.18):const Color(0xFFFFF0D0);
      return GestureDetector(
        onTap:(){setState(()=>selectedDay=day);},
        child:Container(decoration:BoxDecoration(color:bg,borderRadius:BorderRadius.circular(16),border:sel?Border.all(width:2.5,color:Colors.deepPurple):null),child:Stack(children:[
        if(hol!=null) Positioned(right:4,top:4,child:Container(width:7,height:7,decoration:const BoxDecoration(color:Colors.red,shape:BoxShape.circle))),
        if(hasNote) Positioned(right:4,bottom:4,child:Container(width:7,height:7,decoration:const BoxDecoration(color:Colors.blue,shape:BoxShape.circle))),
        Center(child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
          Text('${day.day}',style:TextStyle(fontWeight:FontWeight.bold,fontSize:calendarFontSize-1,color:inM?hol!=null?Colors.red:Colors.black:Colors.grey)),
          if(hol!=null) Text(hol,style:TextStyle(fontSize:calendarFontSize-6,color:Colors.red)),
          if(code!=null) Container(margin:const EdgeInsets.only(top:2),padding:const EdgeInsets.symmetric(horizontal:4,vertical:2),decoration:BoxDecoration(color:def?.color??Colors.orange,borderRadius:BorderRadius.circular(10)),child:FittedBox(child:Text(code,style:TextStyle(color:Colors.white,fontSize:calendarFontSize,fontWeight:FontWeight.bold)))),
          if(hasNote) Text('·記事',style:TextStyle(fontSize:calendarFontSize-6,color:Colors.blue)),
        ])),
      ])));
    })),
    Container(padding:const EdgeInsets.fromLTRB(12,12,12,12),decoration:BoxDecoration(color:Colors.white,border:Border(top:BorderSide(color:Colors.grey.shade200))),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text('${DateFormat('MM/dd EEE').format(selectedDay)} ${hkHolidays[selKey]??''} ${roster[selKey]??'未排班'}',style:const TextStyle(fontSize:15,fontWeight:FontWeight.bold)),
      const SizedBox(height:6),
      Container(padding:const EdgeInsets.all(10),decoration:BoxDecoration(color:Colors.grey.shade100,borderRadius:BorderRadius.circular(10)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('班次：${selDef?.label??'無'} ${selDef!=null?'${selDef.start}-${selDef.end}':''} | 工時：${selDef?.hours??0}h | OT：${selOt}h | 津貼：\$${selDef?.allowance??0}'),
        Text('記事：${rosterNote[selKey]??'無'}',style:const TextStyle(fontSize:13)),
      ])),
      const SizedBox(height:10),
      SizedBox(width:double.infinity,height:48,child:OutlinedButton.icon(onPressed:(){showDetail(selectedDay);},icon:const Icon(Icons.edit),label:const Text('編輯此日'))),
    ])),
  ]));
}

void showDetail(DateTime day){
  String k=DateFormat('yyyy-MM-dd').format(day); String cur=roster[k]??'';
  var nc=TextEditingController(text:rosterNote[k]??'');
  var otc=TextEditingController(text:(rosterOt[k]??defs[cur]?.ot??0).toString());
  showModalBottomSheet(context:context,isScrollControlled:true,builder:(ctx){
    return StatefulBuilder(builder:(ctx2,setM){
      return Padding(padding:EdgeInsets.only(bottom:MediaQuery.of(ctx2).viewInsets.bottom),child:Padding(padding:const EdgeInsets.all(16),child:Column(mainAxisSize:MainAxisSize.min,children:[
        Text(DateFormat('yyyy-MM-dd EEE').format(day),style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
        const SizedBox(height:10),
        Wrap(spacing:8,children:defs.keys.map((c)=>ChoiceChip(label:Text(c),selected:cur==c,onSelected:(_)=>setM(()=>cur=c))).toList()),
        const SizedBox(height:10),
        TextField(controller:nc,decoration:const InputDecoration(labelText:'記事 (無班次也可保存)',border:OutlineInputBorder())),
        const SizedBox(height:10),
        TextField(controller:otc,decoration:const InputDecoration(labelText:'超時 OT 時數',suffixText:'h',border:OutlineInputBorder()),keyboardType:const TextInputType.numberWithOptions(decimal:true)),
        const SizedBox(height:12),
        Row(children:[
          Expanded(child:OutlinedButton(onPressed:(){setState((){roster.remove(k);rosterNote.remove(k);rosterOt.remove(k);});save();Navigator.pop(ctx2);},child:const Text('清除'))),
          const SizedBox(width:8),
          Expanded(child:FilledButton(onPressed:(){
            double? otVal=double.tryParse(otc.text);
            setState((){
              if(cur.isNotEmpty) roster[k]=cur;
              if(nc.text.trim().isNotEmpty) rosterNote[k]=nc.text; else rosterNote.remove(k);
              if(otVal!=null) rosterOt[k]=otVal;
            });
            save(); Navigator.pop(ctx2);
          },child:const Text('儲存'))),
        ]),
      ])));
    });
  });
}

Future<void> pickRangeAndApply() async{
  DateTimeRange? p=await showDateRangePicker(context:context,firstDate:DateTime(2023),lastDate:DateTime(2030));
  if(p==null) return; var flat=pattern.expand((e)=>e).toList();
  setState((){
    int i=0; for(DateTime d=p.start;!d.isAfter(p.end);d=d.add(const Duration(days:1))){roster[DateFormat('yyyy-MM-dd').format(d)]=flat[i%flat.length]; i++;}
  }); save(); setState(()=>tab=0);
}

Widget patternTab(){
  return SafeArea(child:Column(children:[
    Padding(padding:const EdgeInsets.all(12),child:Row(children:[const Text('排更模式',style:TextStyle(fontWeight:FontWeight.bold,fontSize:18)),const Spacer(),FilledButton.tonal(onPressed:(){setState(()=>pattern.add(List.filled(7,'O')));save();},child:const Text('加一行'))])),
    Expanded(child:ListView.builder(itemCount:pattern.length,itemBuilder:(ctx,r){return Row(children:[Text(' ${r+1} '),Expanded(child:Row(children:List.generate(7,(c){return Expanded(child:GestureDetector(onTap:(){showModalBottomSheet(context:context,builder:(ctx){return Wrap(children:defs.keys.map((k)=>ListTile(title:Text('$k - ${defs[k]?.label??''} ${defs[k]?.start??''}-${defs[k]?.end??''}'),onTap:(){setState(()=>pattern[r][c]=k);save();Navigator.pop(ctx);})).toList());});},child:Container(margin:const EdgeInsets.all(2),height:38,color:defs[pattern[r][c]]?.color.withOpacity(0.3),child:Center(child:FittedBox(child:Text(pattern[r][c],style:TextStyle(fontSize:calendarFontSize)))))));}))),IconButton(icon:const Icon(Icons.delete),onPressed:(){setState(()=>pattern.removeAt(r));save();})]);})),
    Padding(padding:const EdgeInsets.all(12),child:SizedBox(width:double.infinity,child:FilledButton(onPressed:pickRangeAndApply,child:const Text('選擇日期範圍並自動排班')))),
  ]));
}

Widget reportTab(){
  int dim=DateTime(focused.year,focused.month+1,0).day;
  double hrs=0,allow=0,ot=0; Map<String,double> allowByCode={}; Map<int,double> weeklyHours={};
  for(int i=1;i<=dim;i++){
    DateTime dt=DateTime(focused.year,focused.month,i); String k=DateFormat('yyyy-MM-dd').format(dt); String? c=roster[k]; if(c==null) continue;
    var d=defs[c]; double curOt=rosterOt[k]??d?.ot??0;
    if(d!=null){hrs+=d.hours;allow+=d.allowance;allowByCode[c]=(allowByCode[c]??0)+d.allowance;int w=isoWeek(dt);weeklyHours[w]=(weeklyHours[w]??0)+d.hours;}
    ot+=curOt;
  }
  List<ExtraAllowance> validExtras=extraAllowances.where((e)=>!e.startDate.isAfter(DateTime(focused.year,focused.month,dim))).toList();
  double extraTotal=validExtras.fold(0,(a,b)=>a+b.amount);
  double otAmount=ot * overtimeRate;
  double totalAllow=allow + extraTotal + otAmount;
  return SafeArea(child:ListView(padding:const EdgeInsets.all(12),children:[
    InkWell(onTap:()=>quickJumpMonth(forReport:true),child:Row(children:[Text('${focused.year}年${focused.month}月 報表',style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const Icon(Icons.arrow_drop_down)])),
    const SizedBox(height:8),
    Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text('承上 $carry h + 本月 $hrs h = ${carry+hrs}h',style:const TextStyle(fontWeight:FontWeight.bold)),
      const Divider(), const Text('每週工時統計 (標準工時 & 承上)',style:TextStyle(fontWeight:FontWeight.bold)),
     ...weeklyHours.entries.map((e){
        double avgCarry=weeklyHours.isEmpty?0:carry/weeklyHours.length;
        double adjusted=e.value + avgCarry; double diff=adjusted - standardWeeklyHours;
        return Padding(padding:const EdgeInsets.symmetric(vertical:3),child:Row(children:[
          Text('W${e.key}',style:const TextStyle(fontWeight:FontWeight.bold)), const SizedBox(width:8),
          Text('${e.value.toStringAsFixed(1)}h +承上${avgCarry.toStringAsFixed(1)} = ${adjusted.toStringAsFixed(1)}h'), const Spacer(),
          Text('${diff>=0?'+':''}${diff.toStringAsFixed(1)}h',style:TextStyle(color:diff>0?Colors.red:Colors.green,fontWeight:FontWeight.bold)),
        ]));
      }),
      const Divider(), Text('標準 ${standardWeeklyHours}h/週 | 總差額 ${(carry+hrs - standardWeeklyHours*weeklyHours.length).toStringAsFixed(1)}h'),
    ]))),
    Card(color:const Color(0xFFE8F5E9),child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('津貼類別',style:TextStyle(fontWeight:FontWeight.bold)),
     ...allowByCode.entries.map((e)=>Row(children:[Text(e.key),const Spacer(),Text('\$${e.value.toStringAsFixed(1)}')])),
      if(validExtras.isNotEmpty) const Divider(),
     ...validExtras.map((e)=>Row(children:[Text('${e.name} (${DateFormat('MM/dd').format(e.startDate)}起)'),const Spacer(),Text('\$${e.amount.toStringAsFixed(1)}')])),
      const Divider(),
      Row(children:[const Text('班次津貼'),const Spacer(),Text('\$${allow.toStringAsFixed(1)}')]),
      Row(children:[Text('OT ${ot.toStringAsFixed(1)}h x \$${overtimeRate.toStringAsFixed(0)}'),const Spacer(),Text('\$${otAmount.toStringAsFixed(1)}')]),
      Row(children:[Text('額外津貼 (有效期內)'),const Spacer(),Text('\$${extraTotal.toStringAsFixed(1)}')]),
      const Divider(),
      Row(children:[const Text('津貼總額 (含OT)',style:TextStyle(fontWeight:FontWeight.bold)),const Spacer(),Text('\$${totalAllow.toStringAsFixed(1)}',style:const TextStyle(fontWeight:FontWeight.bold))]),
    ]))),
  ]));
}

void editShiftDialog({ShiftDef? oldDef}){
  var codeCtrl=TextEditingController(text:oldDef?.code??'');
  var labelCtrl=TextEditingController(text:oldDef?.label??'');
  var hoursCtrl=TextEditingController(text:oldDef?.hours.toString()??'8');
  var allowCtrl=TextEditingController(text:oldDef?.allowance.toString()??'0');
  var otCtrl=TextEditingController(text:oldDef?.ot.toString()??'0');
  var startCtrl=TextEditingController(text:oldDef?.start??'07:00');
  var endCtrl=TextEditingController(text:oldDef?.end??'15:30');
  Color picked=oldDef?.color??Colors.orange;
  String oldKey=oldDef?.code??'';
  showDialog(context:context,builder:(ctx){
    return StatefulBuilder(builder:(ctx2,setS){
      return AlertDialog(title:Text(oldDef==null?'新增班次':'編輯 ${oldDef.code}'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:codeCtrl,decoration:const InputDecoration(labelText:'代號 例如 早/中/宵/O麼麼')),TextField(controller:labelCtrl,decoration:const InputDecoration(labelText:'名稱 例如 早更')),
        const SizedBox(height:8),
        Row(children:[Expanded(child:TextField(controller:startCtrl,decoration:const InputDecoration(labelText:'開始時間 HH:mm',border:OutlineInputBorder()))),const SizedBox(width:8),Expanded(child:TextField(controller:endCtrl,decoration:const InputDecoration(labelText:'結束時間 HH:mm',border:OutlineInputBorder())))]),
        const SizedBox(height:8),
        Row(children:[Expanded(child:TextField(controller:hoursCtrl,decoration:const InputDecoration(labelText:'工時'),keyboardType:TextInputType.number)),const SizedBox(width:8),Expanded(child:TextField(controller:otCtrl,decoration:const InputDecoration(labelText:'OT'),keyboardType:TextInputType.number))]),
        TextField(controller:allowCtrl,decoration:const InputDecoration(labelText:'津貼'),keyboardType:const TextInputType.numberWithOptions(decimal:true)),
        const SizedBox(height:8),
        Wrap(spacing:8,children:[Colors.orange,Colors.blue,Colors.purple,Colors.green,Colors.red,Colors.teal,Colors.brown].map((c)=>GestureDetector(onTap:()=>setS(()=>picked=c),child:CircleAvatar(backgroundColor:c,radius:16,child:picked==c?const Icon(Icons.check,size:14,color:Colors.white):null))).toList()),
      ])),actions:[
        TextButton(onPressed:()=>Navigator.pop(ctx2),child:const Text('取消')),
        FilledButton(onPressed:(){
          String newCode=codeCtrl.text.trim(); if(newCode.isEmpty) return;
          double hrs=double.tryParse(hoursCtrl.text)??8;
          try{
            var s=DateFormat('HH:mm').parse(startCtrl.text);
            var e=DateFormat('HH:mm').parse(endCtrl.text);
            var diff=e.difference(s).inMinutes/60.0; if(diff<0) diff+=24; hrs=diff;
          }catch(_){}
          setState((){
            if(oldKey.isNotEmpty && oldKey!=newCode){
              defs.remove(oldKey);
              roster.forEach((k,v){if(v==oldKey) roster[k]=newCode;});
              for(int i=0;i<pattern.length;i++){for(int j=0;j<pattern[i].length;j++){if(pattern[i][j]==oldKey) pattern[i][j]=newCode;}}
            }
            defs[newCode]=ShiftDef(newCode,labelCtrl.text.isEmpty?newCode:labelCtrl.text,hrs,picked,allowance:double.tryParse(allowCtrl.text)??0,ot:double.tryParse(otCtrl.text)??0,start:startCtrl.text,end:endCtrl.text);
          });
          save(); Navigator.pop(ctx2);
        },child:const Text('儲存')),
      ]);
    });
  });
}

Future<void> backupLocalFile() async{
  var dir=await getApplicationDocumentsDirectory();
  var f=File('${dir.path}/roster_backup_v635.json');
  await f.writeAsString(jsonEncode({
    'roster':roster,'note':rosterNote,'roOt':rosterOt,
    'defs':defs.map((k,v)=>MapEntry(k,v.toJson())),
    'pattern':pattern,'carry':carry,'cName':customName,'stdWeek':standardWeeklyHours,'otRate':overtimeRate,
    'extraNew':extraAllowances.map((e)=>e.toJson()).toList(),'calFont':calendarFontSize
  }));
  if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('已備份 ${f.path}')));
}
Future<void> restoreLocalFile() async{
  var res=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['json']);
  if(res==null) return;
  try{
    String c=await File(res.files.single.path!).readAsString();
    var j=jsonDecode(c);
    setState((){
      if(j['roster']!=null) roster=Map<String,String>.from(j['roster']);
      if(j['note']!=null) rosterNote=Map<String,String>.from(j['note']);
      if(j['roOt']!=null) rosterOt=Map<String,double>.from((j['roOt'] as Map).map((k,v)=>MapEntry(k,(v as num).toDouble())));
      if(j['defs']!=null) defs=(j['defs'] as Map).map<String,ShiftDef>((k,v)=>MapEntry(k,ShiftDef.fromJson(Map<String,dynamic>.from(v))));
      if(j['pattern']!=null) pattern=(j['pattern'] as List).map<List<String>>((r)=>(r as List).map<String>((e)=>e.toString()).toList()).toList();
      if(j['carry']!=null) carry=(j['carry'] as num).toDouble();
      if(j['cName']!=null){customName=j['cName'];nameCtrl.text=customName;}
      if(j['stdWeek']!=null) standardWeeklyHours=(j['stdWeek'] as num).toDouble();
      if(j['otRate']!=null) overtimeRate=(j['otRate'] as num).toDouble();
      if(j['extraNew']!=null) extraAllowances=(j['extraNew'] as List).map((e)=>ExtraAllowance.fromJson(Map<String,dynamic>.from(e))).toList();
      if(j['calFont']!=null) calendarFontSize=(j['calFont'] as num).toDouble();
    });
    save();
    if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('還原成功')));
  }catch(e){if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('還原失敗 $e')));}
}

Widget settingsTab(){
  var stdCtrl=TextEditingController(text:standardWeeklyHours.toString());
  var carryCtrl=TextEditingController(text:carry.toString());
  var otRateCtrl=TextEditingController(text:overtimeRate.toString());
  return SafeArea(child:ListView(padding:const EdgeInsets.all(16),children:[
    const Text('自定班次內容編輯和刪除',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
    Card(child:Column(children:[
    ...defs.entries.map((e){var d=e.value;return ListTile(leading:CircleAvatar(backgroundColor:d.color,child:Text(d.code,style:const TextStyle(color:Colors.white,fontSize:10))),title:Text('${d.code} - ${d.label} ${d.start}-${d.end}',style:const TextStyle(fontSize:14)),subtitle:Text('${d.hours.toStringAsFixed(1)}h \$${d.allowance} OT:${d.ot}h'),trailing:Row(mainAxisSize:MainAxisSize.min,children:[IconButton(icon:const Icon(Icons.edit),onPressed:()=>editShiftDialog(oldDef:d)),IconButton(icon:const Icon(Icons.delete),onPressed:(){setState(()=>defs.remove(e.key));save();})]));}),
      ListTile(leading:const Icon(Icons.add),title:const Text('新增班次'),onTap:()=>editShiftDialog()),
    ])),
    const SizedBox(height:16),
    const Text('標準工時 & 承上 & 超時金額',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
    Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(children:[
      Row(children:[
        Expanded(child:TextField(controller:stdCtrl,decoration:const InputDecoration(labelText:'標準工時',suffixText:'h/週',border:OutlineInputBorder()),keyboardType:TextInputType.number)),
        const SizedBox(width:8),
        Expanded(child:TextField(controller:carryCtrl,decoration:const InputDecoration(labelText:'承上餘額',suffixText:'h',border:OutlineInputBorder()),keyboardType:TextInputType.number)),
      ]),
      const SizedBox(height:10),
      TextField(controller:otRateCtrl,decoration:const InputDecoration(labelText:'超時工作金額 (每小時)',prefixText:'\$ ',suffixText:'/h',border:OutlineInputBorder()),keyboardType:const TextInputType.numberWithOptions(decimal:true)),
      const SizedBox(height:10),
      SizedBox(width:double.infinity,child:FilledButton(onPressed:(){
        double? v1=double.tryParse(stdCtrl.text); double? v2=double.tryParse(carryCtrl.text); double? v3=double.tryParse(otRateCtrl.text);
        if(v1!=null) standardWeeklyHours=v1; if(v2!=null) carry=v2; if(v3!=null) overtimeRate=v3; setState((){}); save();
      },child:const Text('保存設定'))),
    ]))),
    const SizedBox(height:16),
    const Text('日曆文字大小',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
    Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(children:[
      Row(children:[const Text('小'),Expanded(child:Slider(value:calendarFontSize,min:8,max:20,divisions:12,label:calendarFontSize.toStringAsFixed(0),onChanged:(v){setState(()=>calendarFontSize=v);})),const Text('大')]),
      Row(children:[Container(width:50,height:50,color:Colors.orange.withOpacity(0.3),child:Center(child:Text('早',style:TextStyle(fontSize:calendarFontSize,fontWeight:FontWeight.bold)))),const SizedBox(width:8),Text('目前 ${calendarFontSize.toStringAsFixed(0)}px',style:TextStyle(fontSize:calendarFontSize))]),
      FilledButton.tonal(onPressed:(){save();},child:const Text('保存文字大小')),
    ]))),
    const SizedBox(height:16),
    const Text('自定津貼編輯 (直接輸入)',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
    Card(child:Column(children:defs.entries.map((e){
      var d=e.value;
      return Padding(padding:const EdgeInsets.fromLTRB(12,6,4,6),child:Row(children:[
        SizedBox(width:60,child:Text(d.code,style:const TextStyle(fontWeight:FontWeight.bold,fontSize:12),overflow:TextOverflow.ellipsis)),
        Expanded(child:Text('${d.label} ${d.start}-${d.end}',style:const TextStyle(fontSize:11),overflow:TextOverflow.ellipsis)),
        SizedBox(width:90,child:TextFormField(initialValue:d.allowance.toString(),decoration:InputDecoration(labelText:'\$',isDense:true,border:OutlineInputBorder(borderRadius:BorderRadius.circular(8))),keyboardType:const TextInputType.numberWithOptions(decimal:true),onFieldSubmitted:(v){double? val=double.tryParse(v); if(val!=null){setState(()=>d.allowance=val); save();}})),
        IconButton(icon:const Icon(Icons.close,size:18,color:Colors.red),onPressed:(){setState(()=>d.allowance=0); save();},tooltip:'清零津貼'),
        IconButton(icon:const Icon(Icons.delete,size:18),onPressed:(){setState(()=>defs.remove(e.key)); save();},tooltip:'刪除班次'),
      ]));
    }).toList())),
    const SizedBox(height:16),
    const Text('新增津貼類別 (含生效日期)',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
    Card(child:Column(children:[
    ...extraAllowances.asMap().entries.map((en){
        int idx=en.key; var e=en.value;
        return ListTile(title:Text(e.name),subtitle:Text('\$${e.amount.toStringAsFixed(1)} 生效：${DateFormat('yyyy-MM-dd').format(e.startDate)}'),trailing:Row(mainAxisSize:MainAxisSize.min,children:[
        IconButton(icon:const Icon(Icons.edit,size:18),onPressed:(){
          var nCtrl=TextEditingController(text:e.name); var vCtrl=TextEditingController(text:e.amount.toString()); DateTime sel=e.startDate;
          showDialog(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx2,setS){return AlertDialog(title:const Text('編輯津貼類別'),content:Column(mainAxisSize:MainAxisSize.min,children:[
            TextField(controller:nCtrl,decoration:const InputDecoration(labelText:'名稱')),
            TextField(controller:vCtrl,decoration:const InputDecoration(labelText:'金額'),keyboardType:const TextInputType.numberWithOptions(decimal:true)),
            const SizedBox(height:10),
            Row(children:[Text('生效：${DateFormat('yyyy-MM-dd').format(sel)}'),const Spacer(),TextButton(onPressed:() async{DateTime? p=await showDatePicker(context:context,firstDate:DateTime(2020),lastDate:DateTime(2030),initialDate:sel); if(p!=null) setS(()=>sel=p);},child:const Text('改日期'))]),
          ]),actions:[FilledButton(onPressed:(){String newName=nCtrl.text.trim(); double? val=double.tryParse(vCtrl.text); if(newName.isEmpty||val==null) return; setState(()=>extraAllowances[idx]=ExtraAllowance(newName,val,sel)); save(); Navigator.pop(ctx);},child:const Text('儲存'))]);}));
        }),
        IconButton(icon:const Icon(Icons.delete,size:18,color:Colors.red),onPressed:(){setState(()=>extraAllowances.removeAt(idx)); save();}),
      ]));}),
      ListTile(leading:const Icon(Icons.add),title:const Text('新增津貼類別'),onTap:(){
        var nCtrl=TextEditingController(); var vCtrl=TextEditingController(text:'0'); DateTime sel=DateTime.now();
        showDialog(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx2,setS){return AlertDialog(title:const Text('新增津貼類別'),content:Column(mainAxisSize:MainAxisSize.min,children:[
          TextField(controller:nCtrl,decoration:const InputDecoration(labelText:'名稱 例如 交通津貼')),
          TextField(controller:vCtrl,decoration:const InputDecoration(labelText:'金額'),keyboardType:const TextInputType.numberWithOptions(decimal:true)),
          const SizedBox(height:10),
          Row(children:[Text('生效：${DateFormat('yyyy-MM-dd').format(sel)}'),const Spacer(),TextButton(onPressed:() async{DateTime? p=await showDatePicker(context:context,firstDate:DateTime(2020),lastDate:DateTime(2030),initialDate:sel); if(p!=null) setS(()=>sel=p);},child:const Text('選擇開始時間'))]),
        ]),actions:[FilledButton(onPressed:(){String name=nCtrl.text.trim(); double? val=double.tryParse(vCtrl.text); if(name.isEmpty||val==null) return; setState(()=>extraAllowances.add(ExtraAllowance(name,val,sel))); save(); Navigator.pop(ctx);},child:const Text('新增'))]);}));
      }),
    ])),
    const SizedBox(height:16),
    const Text('備份與還原',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
    Card(child:Padding(padding:const EdgeInsets.all(12),child:Row(children:[
      Expanded(child:OutlinedButton.icon(onPressed:backupLocalFile,icon:const Icon(Icons.backup),label:const Text('備份到手機'))),
      const SizedBox(width:8),
      Expanded(child:OutlinedButton.icon(onPressed:restoreLocalFile,icon:const Icon(Icons.restore),label:const Text('還原'))),
    ]))),
    const SizedBox(height:16),
    Card(child:Padding(padding:const EdgeInsets.all(12),child:Row(children:[Expanded(child:TextField(controller:nameCtrl,decoration:const InputDecoration(labelText:'日曆名稱'))),const SizedBox(width:8),FilledButton(onPressed:(){setState(()=>customName=nameCtrl.text.trim().isEmpty?'我的排更':nameCtrl.text.trim()); save();},child:const Text('確認'))]))),
  ]));
}

@override Widget build(BuildContext context){
  return Scaffold(body:[calTab(),patternTab(),reportTab(),settingsTab()][tab],bottomNavigationBar:NavigationBar(selectedIndex:tab,onDestinationSelected:(i)=>setState(()=>tab=i),destinations:const[
    NavigationDestination(icon:Icon(Icons.calendar_month),label:'月曆'),
    NavigationDestination(icon:Icon(Icons.pattern),label:'模式'),
    NavigationDestination(icon:Icon(Icons.settings),label:'設定'),
    NavigationDestination(icon:Icon(Icons.bar_chart),label:'報表'),
  ].reversed.toList().reversed.toList()..insertAll(2,[])), // keep order
  );
}
}
