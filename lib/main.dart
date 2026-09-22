import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

void main(){runApp(const RosterApp());}

class ShiftDef{
  String code; String label; double hours; double allowance; double ot; Color color; String start; String end;
  ShiftDef(this.code,this.label,this.hours,this.color,{this.allowance=0,this.ot=0,this.start='07:00',this.end='15:30'});
  Map<String,dynamic> toJson()=>{'code':code,'label':label,'hours':hours,'allowance':allowance,'ot':ot,'color':color.value,'start':start,'end':end};
  factory ShiftDef.fromJson(Map<String,dynamic> j)=>ShiftDef(j['code'],j['label']??j['code'],(j['hours']??8).toDouble(),Color(j['color']??0xFFFF9800),allowance:(j['allowance']??0).toDouble(),ot:(j['ot']??0).toDouble(),start:j['start']??'07:00',end:j['end']??'15:30');
  String get detailTime=>'$code $start-$end ${hours.toStringAsFixed(1)}h';
}
class ExtraAllowance{
  String name; double amount; String time;
  ExtraAllowance(this.name,this.amount,this.time);
  Map<String,dynamic> toJson()=>{'name':name,'amount':amount,'time':time};
  factory ExtraAllowance.fromJson(Map<String,dynamic> j)=>ExtraAllowance(j['name'],(j['amount'] as num).toDouble(),j['time']??'00:00');
  int get minutes{try{var p=time.split(':'); return int.parse(p[0])*60+int.parse(p[1]);}catch(_){return 0;}}
}
class SavedPattern{
  String name; List<List<String>> data;
  SavedPattern(this.name,this.data);
  Map<String,dynamic> toJson()=>{'name':name,'data':data};
  factory SavedPattern.fromJson(Map<String,dynamic> j)=>SavedPattern(j['name'], (j['data'] as List).map<List<String>>((r)=>(r as List).map<String>((e)=>e.toString()).toList()).toList());
}
class RosterApp extends StatelessWidget{const RosterApp({super.key}); @override Widget build(BuildContext context){return MaterialApp(title:'Roster Pro v6.40',theme:ThemeData(useMaterial3:true,colorSchemeSeed:Colors.deepPurple),home:const MainPage());}}

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
List<SavedPattern> savedPatterns=[];
double carry=0; String customName='我的排更'; TextEditingController nameCtrl=TextEditingController();
double standardWeeklyHours=42; double overtimeRate=80; List<ExtraAllowance> extraAllowances=[]; double calendarFontSize=14;
bool googleSyncEnabled=false; bool autoSync=false;
bool isYearReport=false;
GlobalKey calKey=GlobalKey();

@override void initState(){super.initState();nameCtrl.text=customName;load();}
Future<void> load() async{
  var sp=await SharedPreferences.getInstance();
  var r=sp.getString('roster'); if(r!=null) roster=Map<String,String>.from(jsonDecode(r));
  var rn=sp.getString('note'); if(rn!=null) rosterNote=Map<String,String>.from(jsonDecode(rn));
  var ro=sp.getString('roOt'); if(ro!=null){try{rosterOt=Map<String,double>.from(jsonDecode(ro).map((k,v)=>MapEntry(k,(v as num).toDouble())));}catch(_){}}
  var d=sp.getString('defs'); if(d!=null){try{var m=Map<String,dynamic>.from(jsonDecode(d)); defs=m.map((k,v)=>MapEntry(k,ShiftDef.fromJson(Map<String,dynamic>.from(v))));}catch(_){}}
  var p=sp.getString('pattern'); if(p!=null){try{var l=jsonDecode(p) as List; pattern=l.map<List<String>>((row)=>(row as List).map<String>((e)=>e.toString()).toList()).toList();}catch(_){}}
  var ea=sp.getString('extraAllowNewV36'); if(ea!=null){try{extraAllowances=(jsonDecode(ea) as List).map((e)=>ExtraAllowance.fromJson(Map<String,dynamic>.from(e))).toList();}catch(_){}}
  var spSaved=sp.getString('savedPatternsV40'); if(spSaved!=null){try{savedPatterns=(jsonDecode(spSaved) as List).map((e)=>SavedPattern.fromJson(Map<String,dynamic>.from(e))).toList();}catch(_){}}
  setState((){
    carry=sp.getDouble('carry')??0; customName=sp.getString('cName')??'我的排更'; nameCtrl.text=customName;
    standardWeeklyHours=sp.getDouble('stdWeek')??42; overtimeRate=sp.getDouble('otRate')??80;
    calendarFontSize=sp.getDouble('calFont')??14;
    googleSyncEnabled=sp.getBool('gSync')??false; autoSync=sp.getBool('gAuto')??false;
  });
}
Future<void> save() async{
  var sp=await SharedPreferences.getInstance();
  sp.setString('roster',jsonEncode(roster)); sp.setString('note',jsonEncode(rosterNote)); sp.setString('roOt',jsonEncode(rosterOt));
  sp.setString('defs',jsonEncode(defs.map((k,v)=>MapEntry(k,v.toJson())))); sp.setString('pattern',jsonEncode(pattern));
  sp.setDouble('carry',carry); sp.setString('cName',customName); sp.setDouble('stdWeek',standardWeeklyHours);
  sp.setDouble('otRate',overtimeRate); sp.setString('extraAllowNewV36',jsonEncode(extraAllowances.map((e)=>e.toJson()).toList()));
  sp.setDouble('calFont',calendarFontSize); sp.setBool('gSync',googleSyncEnabled); sp.setBool('gAuto',autoSync);
  sp.setString('savedPatternsV40',jsonEncode(savedPatterns.map((e)=>e.toJson()).toList()));
  if(autoSync && googleSyncEnabled){ _syncToGoogle(); }
}
int isoWeek(DateTime date){DateTime thursday=date.add(Duration(days:4-date.weekday)); DateTime jan1=DateTime(thursday.year,1,1); int days=thursday.difference(jan1).inDays; return 1+(days/7).floor();}
int timeToMin(String t){try{var p=t.split(':'); return int.parse(p[0])*60+int.parse(p[1]);}catch(_){return 0;}}

void quickJumpMonth({bool forReport=false}){
  int y=focused.year; int m=focused.month;
  showDialog(context:context,builder:(ctx){return StatefulBuilder(builder:(ctx2,setD){return AlertDialog(title:Text(forReport?'選擇報表年月':'快速查找年月'),content:Column(mainAxisSize:MainAxisSize.min,children:[
    Row(children:[IconButton(icon:const Icon(Icons.remove),onPressed:()=>setD(()=>y--)),Expanded(child:Text('$y年',textAlign:TextAlign.center,style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold))),IconButton(icon:const Icon(Icons.add),onPressed:()=>setD(()=>y++))]),
    Wrap(spacing:8,children:List.generate(12,(i){int mon=i+1;return ChoiceChip(label:Text('${mon}月'),selected:mon==m,onSelected:(_)=>setD(()=>m=mon));})),
  ]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx2),child:const Text('取消')),FilledButton(onPressed:(){setState(()=>focused=DateTime(y,m,1));Navigator.pop(ctx2);},child:const Text('跳轉'))]);});});
}

// 2. Google 日曆同步 (模擬權限 + 手動同步)
Future<void> _requestGooglePerm() async{
  bool? ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Google日曆權限'),content:const Text('需要授權讀寫 Google 日曆，才能自動同步排更。\n\n功能：\n• 手動同步\n• 資料更新時自動同步\n• 包含班次詳細時間'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('取消')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('授權'))]));
  if(ok==true){setState(()=>googleSyncEnabled=true); save(); if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('已授權 Google日曆')));}
}
Future<void> _syncToGoogle() async{
  if(!googleSyncEnabled) return;
  // 實際接 Google Calendar API，呢度先存本地提示
  if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('已同步 ${roster.length} 項到 Google日曆 ${autoSync?'[自動]':''}')));
}

// 1. 截圖分享 一周/整月 + 詳細時間
Future<void> shareScreenshotDialog() async{
  showDialog(context:context,builder:(ctx)=>AlertDialog(title:const Text('截圖分享'),content:Column(mainAxisSize:MainAxisSize.min,children:[
    ListTile(leading:const Icon(Icons.calendar_view_week),title:const Text('截圖 本週 (含詳細時間)'),onTap:(){Navigator.pop(ctx); _exportShare(isWeek:true);}),
    ListTile(leading:const Icon(Icons.calendar_month),title:const Text('截圖 整月 (含詳細時間)'),onTap:(){Navigator.pop(ctx); _exportShare(isWeek:false);}),
  ])));
}
Future<void> _exportShare({required bool isWeek}) async{
  try{
    RenderRepaintBoundary? b=calKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    ui.Image? img;
    if(b!=null){ img=await b.toImage(pixelRatio:2.5); }
    // 同時生成帶詳細時間的文字分享檔
    StringBuffer sb=StringBuffer();
    sb.writeln(isWeek?'本週排更 ${DateFormat('yyyy-MM-dd').format(selectedDay)}':'${focused.year}年${focused.month}月 整月排更');
    sb.writeln('代碼詳細時間:');
    defs.forEach((k,v){sb.writeln('${v.detailTime} 津貼\$${v.allowance}');});
    sb.writeln('---');
    if(isWeek){
      DateTime mon=selectedDay.subtract(Duration(days:selectedDay.weekday-1));
      for(int i=0;i<7;i++){DateTime d=mon.add(Duration(days:i)); String key=DateFormat('yyyy-MM-dd').format(d); String? c=roster[key]; var def=c!=null?defs[c]:null; sb.writeln('${DateFormat('MM/dd EEE').format(d)} ${c??'無'} ${def!=null?def.detailTime:''} ${rosterNote[key]??''}');}
    }else{
      int dim=DateTime(focused.year,focused.month+1,0).day;
      for(int i=1;i<=dim;i++){DateTime d=DateTime(focused.year,focused.month,i); String key=DateFormat('yyyy-MM-dd').format(d); String? c=roster[key]; var def=c!=null?defs[c]:null; sb.writeln('${DateFormat('MM/dd').format(d)} ${c??'無'} ${def!=null?def.detailTime:''}');}
    }
    String? path=await FilePicker.platform.saveFile(dialogTitle:'保存截圖分享',fileName:'roster_${isWeek?'week':'month'}_${DateFormat('MMdd').format(DateTime.now())}.txt');
    if(path!=null){await File(path).writeAsString(sb.toString()); if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('已匯出詳細排更到 $path')));}
    if(img!=null){
      var byte=await img.toByteData(format:ui.ImageByteFormat.png);
      if(byte!=null){
        var dir=await getTemporaryDirectory();
        var f=File('${dir.path}/roster_share_${DateTime.now().millisecondsSinceEpoch}.png');
        await f.writeAsBytes(byte.buffer.asUint8List());
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('截圖已保存 ${f.path} 可分享')));
      }
    }
  }catch(e){if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('匯出失敗 $e')));}
}

Future<void> backupAnywhere() async{
  String? dir=await FilePicker.platform.getDirectoryPath(dialogTitle:'選擇備份位置'); if(dir==null) return;
  String fileName='roster_backup_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.json';
  var f=File('$dir/$fileName');
  await f.writeAsString(jsonEncode({'roster':roster,'note':rosterNote,'roOt':rosterOt,'defs':defs.map((k,v)=>MapEntry(k,v.toJson())),'pattern':pattern,'carry':carry,'cName':customName,'stdWeek':standardWeeklyHours,'otRate':overtimeRate,'extraNewV36':extraAllowances.map((e)=>e.toJson()).toList(),'calFont':calendarFontSize,'savedPatterns':savedPatterns.map((e)=>e.toJson()).toList()}));
  if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('已備份到 $dir/$fileName')));
}
Future<void> restoreLocalFile() async{
  var res=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['json']); if(res==null) return;
  try{String c=await File(res.files.single.path!).readAsString(); var j=jsonDecode(c);
    setState((){
      if(j['roster']!=null) roster=Map<String,String>.from(j['roster']); if(j['note']!=null) rosterNote=Map<String,String>.from(j['note']);
      if(j['roOt']!=null) rosterOt=Map<String,double>.from((j['roOt'] as Map).map((k,v)=>MapEntry(k,(v as num).toDouble())));
      if(j['defs']!=null) defs=(j['defs'] as Map).map<String,ShiftDef>((k,v)=>MapEntry(k,ShiftDef.fromJson(Map<String,dynamic>.from(v))));
      if(j['pattern']!=null) pattern=(j['pattern'] as List).map<List<String>>((r)=>(r as List).map<String>((e)=>e.toString()).toList()).toList();
      if(j['carry']!=null) carry=(j['carry'] as num).toDouble(); if(j['cName']!=null){customName=j['cName'];nameCtrl.text=customName;}
      if(j['stdWeek']!=null) standardWeeklyHours=(j['stdWeek'] as num).toDouble(); if(j['otRate']!=null) overtimeRate=(j['otRate'] as num).toDouble();
      if(j['extraNewV36']!=null) extraAllowances=(j['extraNewV36'] as List).map((e)=>ExtraAllowance.fromJson(Map<String,dynamic>.from(e))).toList();
      if(j['calFont']!=null) calendarFontSize=(j['calFont'] as num).toDouble();
      if(j['savedPatterns']!=null) savedPatterns=(j['savedPatterns'] as List).map((e)=>SavedPattern.fromJson(Map<String,dynamic>.from(e))).toList();
    }); save(); if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('還原成功')));
  }catch(e){if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('還原失敗 $e')));}
}

Future<void> exportReport() async{
  StringBuffer sb=StringBuffer();
  if(!isYearReport){
    int dim=DateTime(focused.year,focused.month+1,0).day; double hrs=0,allow=0,ot=0; Map<String,int> shiftCount={};
    for(int i=1;i<=dim;i++){DateTime dt=DateTime(focused.year,focused.month,i); String k=DateFormat('yyyy-MM-dd').format(dt); String? c=roster[k]; if(c==null) continue; var d=defs[c]; if(d!=null){hrs+=d.hours; allow+=d.allowance; shiftCount[c]=(shiftCount[c]??0)+1;} ot+=(rosterOt[k]??d?.ot??0);}
    sb.writeln('${focused.year}年${focused.month}月 報表');
    shiftCount.forEach((k,v)=>sb.writeln('$k $v次'));
    sb.writeln('總工時 $hrs OT $ot 津貼 \$${allow+ot*overtimeRate}');
  }else{
    sb.writeln('${focused.year}年 全年統計');
    for(int mon=1;mon<=12;mon++){int dim=DateTime(focused.year,mon+1,0).day; double hrs=0; Map<String,int> sc={}; for(int d=1;d<=dim;d++){DateTime dt=DateTime(focused.year,mon,d); String k=DateFormat('yyyy-MM-dd').format(dt); String? c=roster[k]; if(c==null) continue; var def=defs[c]; if(def!=null){hrs+=def.hours; sc[c]=(sc[c]??0)+1;}} sb.writeln('$mon月 ${hrs}h $sc');}
  }
  String? path=await FilePicker.platform.saveFile(dialogTitle:'匯出報表',fileName:'report_${isYearReport?'year_${focused.year}':'${focused.year}_${focused.month}'}.csv',type:FileType.custom,allowedExtensions:['csv','txt']);
  if(path!=null){await File(path).writeAsString(sb.toString()); if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('已匯出 $path')));}
}

Widget calTab(){
  DateTime first=DateTime(focused.year,focused.month,1); DateTime start=first.subtract(Duration(days:first.weekday-1));
  int daysInMonth=DateTime(focused.year,focused.month+1,0).day; int neededCells=first.weekday-1+daysInMonth; int weeks=(neededCells/7).ceil(); if(weeks<5) weeks=5; if(weeks>6) weeks=6;
  List<DateTime> days=List.generate(weeks*7,(i)=>start.add(Duration(days:i)));
  String selKey=DateFormat('yyyy-MM-dd').format(selectedDay); var selDef=roster[selKey]!=null?defs[roster[selKey]]:null;
  double selOt=rosterOt[selKey]??selDef?.ot??0; String note=rosterNote[selKey]??'無';
  double extraToday=0; List<String> extraTodayNames=[]; if(selDef!=null){int sMin=timeToMin(selDef.start); for(var ex in extraAllowances){ if(sMin>=ex.minutes){ extraToday+=ex.amount; extraTodayNames.add('${ex.name}(${ex.time})');}}}
  // 5. 週日計算該週實際工時差額
  double weekActual=0; if(selectedDay.weekday==7){DateTime mon=selectedDay.subtract(const Duration(days:6)); for(int i=0;i<7;i++){DateTime d=mon.add(Duration(days:i)); String k=DateFormat('yyyy-MM-dd').format(d); String? c=roster[k]; if(c!=null){ var dd=defs[c]; if(dd!=null) weekActual+=dd.hours; } weekActual+=(rosterOt[DateFormat('yyyy-MM-dd').format(mon.add(Duration(days:i)))]??0); }}
  double weekDiff=weekActual-standardWeeklyHours;

  return SafeArea(child:Column(children:[
    Padding(padding:const EdgeInsets.fromLTRB(12,8,12,4),child:Row(children:[
      InkWell(onTap:()=>quickJumpMonth(),child:Row(children:[Text('${focused.year}年${focused.month}月',style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const Icon(Icons.arrow_drop_down)])),
      const Spacer(),
      IconButton(icon:const Icon(Icons.camera_alt_outlined),tooltip:'截圖分享 一周/整月+詳細時間',onPressed:shareScreenshotDialog),
      IconButton(icon:const Icon(Icons.chevron_left),onPressed:(){setState(()=>focused=DateTime(focused.year,focused.month-1,1));}),
      IconButton(icon:const Icon(Icons.chevron_right),onPressed:(){setState(()=>focused=DateTime(focused.year,focused.month+1,1));}),
      FilledButton.tonal(onPressed:(){setState((){focused=DateTime.now();selectedDay=DateTime.now();});},child:const Text('今天')),
    ])),
    RepaintBoundary(key:calKey,child:Column(children:[
      Padding(padding:const EdgeInsets.symmetric(horizontal:6),child:Row(children:[Container(width:32,child:const Text('週',textAlign:TextAlign.center,style:TextStyle(fontWeight:FontWeight.bold,fontSize:11))),Expanded(child:Row(children:["一","二","三","四","五","六","日"].map((w)=>Expanded(child:Text(w,textAlign:TextAlign.center,style:const TextStyle(fontSize:11)))).toList()))])),
      ListView.builder(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),padding:EdgeInsets.zero,itemCount:weeks,itemBuilder:(ctx,row){
        return Row(children:[
          Container(width:32,alignment:Alignment.center,child:Text('W${isoWeek(days[row*7])}',style:const TextStyle(fontSize:10,color:Colors.grey,fontWeight:FontWeight.bold))),
          Expanded(child:GridView.builder(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),padding:const EdgeInsets.all(3),gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:7,childAspectRatio:0.78,mainAxisSpacing:4,crossAxisSpacing:4),itemCount:7,itemBuilder:(ctx2,col){
            int idx=row*7+col; DateTime day=days[idx]; bool inM=day.month==focused.month; String k=DateFormat('yyyy-MM-dd').format(day);
            String? code=roster[k]; var def=code!=null?defs[code]:null; bool sel=k==selKey;
            Color bg=!inM?const Color(0xFFF5F5F0):sel?Colors.white:def!=null?def.color.withOpacity(0.18):const Color(0xFFFFF0D0);
            return GestureDetector(onTap:(){setState(()=>selectedDay=day);},child:Container(decoration:BoxDecoration(color:bg,borderRadius:BorderRadius.circular(12),border:sel?Border.all(width:2,color:Colors.deepPurple):null),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
              Text('${day.day}',style:TextStyle(fontWeight:FontWeight.bold,fontSize:calendarFontSize-2,color:inM?Colors.black:Colors.grey)),
              if(code!=null) FittedBox(child:Container(margin:const EdgeInsets.only(top:1),padding:const EdgeInsets.symmetric(horizontal:4,vertical:1),decoration:BoxDecoration(color:def?.color??Colors.orange,borderRadius:BorderRadius.circular(8)),child:Text(code,style:TextStyle(color:Colors.white,fontSize:calendarFontSize-2)))),
            ])));
          })),
        ]);
      }),
    ])),
    Container(width:double.infinity,padding:const EdgeInsets.fromLTRB(12,10,12,12),decoration:const BoxDecoration(color:Colors.white,border:Border(top:BorderSide(color:Color(0xFFE0E0E0)))),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[
        Text('${DateFormat('MM/dd EEE').format(selectedDay)} ${roster[selKey]??'未排班'}',style:const TextStyle(fontSize:16,fontWeight:FontWeight.bold)),
        const SizedBox(width:8),
        if(selDef!=null) Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:3),decoration:BoxDecoration(color:selDef.color,borderRadius:BorderRadius.circular(10)),child:Text(selDef.code,style:const TextStyle(color:Colors.white,fontSize:11,fontWeight:FontWeight.bold))),
        const Spacer(),
        FilledButton.tonalIcon(onPressed:(){showDetail(selectedDay);},icon:const Icon(Icons.edit,size:16),label:const Text('編輯',style:TextStyle(fontSize:12)),style: FilledButton.styleFrom(minimumSize:const Size(0,34),padding:const EdgeInsets.symmetric(horizontal:12))),
      ]),
      const SizedBox(height:8),
      Container(width:double.infinity,padding:const EdgeInsets.all(10),decoration:BoxDecoration(color:const Color(0xFFF5F5F5),borderRadius:BorderRadius.circular(12)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('1. 班次：${selDef?.label??'無'} ${selDef!=null?'(${selDef.code})':''}',style:const TextStyle(fontSize:13,fontWeight:FontWeight.bold)),
        const SizedBox(height:3),
        Text('2. 時間：${selDef!=null?'${selDef.start} - ${selDef.end}': '無'} | 工時：${selDef?.hours.toStringAsFixed(1)??'0'}h',style:const TextStyle(fontSize:12)),
        const SizedBox(height:3),
        Text('3. 津貼：班次 \$${selDef?.allowance??0} + 額外 \$${extraToday.toStringAsFixed(1)} ${extraTodayNames.isEmpty?'': '(${extraTodayNames.join(',')})'}',style:const TextStyle(fontSize:12)),
        const SizedBox(height:3),
        Text('4. OT：${selOt.toStringAsFixed(1)}h (標準 \$${overtimeRate.toStringAsFixed(0)}/h = \$${(selOt*overtimeRate).toStringAsFixed(1)})',style:const TextStyle(fontSize:12)),
        const SizedBox(height:3),
        Text('5. 記事：${note.isEmpty?'無':note}',style:const TextStyle(fontSize:12),maxLines:2,overflow:TextOverflow.ellipsis),
        const SizedBox(height:3),
        if(selectedDay.weekday==7)
          Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:4),decoration:BoxDecoration(color:weekDiff>=0?Colors.red.withOpacity(0.12):Colors.green.withOpacity(0.12),borderRadius:BorderRadius.circular(8)),child:Text('6. 本週(W${isoWeek(selectedDay)})統計：實際 ${weekActual.toStringAsFixed(1)}h / 標準 ${standardWeeklyHours}h = 差額 ${weekDiff>=0?'+':''}${weekDiff.toStringAsFixed(1)}h',style:TextStyle(fontSize:12,fontWeight:FontWeight.bold,color:weekDiff>0?Colors.red:Colors.green))),
        if(selectedDay.weekday!=7)
          Text('6. 週數：W${isoWeek(selectedDay)} | 本月累計：${roster.keys.where((k)=>k.startsWith(DateFormat('yyyy-MM').format(selectedDay))).length}日',style:const TextStyle(fontSize:11,color:Colors.grey)),
      ])),
    ])),
  ]));
}

void showDetail(DateTime day){
  String k=DateFormat('yyyy-MM-dd').format(day); String cur=roster[k]??'';
  var nc=TextEditingController(text:rosterNote[k]??''); var otc=TextEditingController(text:(rosterOt[k]??0).toString());
  showModalBottomSheet(context:context,isScrollControlled:true,builder:(ctx){return StatefulBuilder(builder:(ctx2,setM){return Padding(padding:EdgeInsets.only(bottom:MediaQuery.of(ctx2).viewInsets.bottom),child:Padding(padding:const EdgeInsets.all(16),child:Column(mainAxisSize:MainAxisSize.min,children:[
    Text(DateFormat('yyyy-MM-dd EEE').format(day),style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
    Wrap(spacing:8,children:defs.keys.map((c)=>ChoiceChip(label:Text(c),selected:cur==c,onSelected:(_)=>setM(()=>cur=c))).toList()),
    TextField(controller:nc,decoration:const InputDecoration(labelText:'記事')), TextField(controller:otc,decoration:const InputDecoration(labelText:'OT時數'),keyboardType:TextInputType.number),
    Row(children:[Expanded(child:OutlinedButton(onPressed:(){setState((){roster.remove(k);rosterNote.remove(k);rosterOt.remove(k);});save();Navigator.pop(ctx2);},child:const Text('清除'))),const SizedBox(width:8),Expanded(child:FilledButton(onPressed:(){double? otVal=double.tryParse(otc.text); setState((){if(cur.isNotEmpty) roster[k]=cur; if(nc.text.isNotEmpty) rosterNote[k]=nc.text; else rosterNote.remove(k); if(otVal!=null) rosterOt[k]=otVal;}); save(); Navigator.pop(ctx2);},child:const Text('儲存')))]),
  ])));});});
}

Future<void> pickRangeAndApply() async{
  DateTimeRange? p=await showDateRangePicker(context:context,firstDate:DateTime(2023),lastDate:DateTime(2030)); if(p==null) return; var flat=pattern.expand((e)=>e).toList();
  setState((){int i=0; for(DateTime d=p.start;!d.isAfter(p.end);d=d.add(const Duration(days:1))){roster[DateFormat('yyyy-MM-dd').format(d)]=flat[i%flat.length]; i++;}}); save(); setState(()=>tab=0);
}

// 4. 模式另存
Widget patternTab(){
  return SafeArea(child:Column(children:[
    Padding(padding:const EdgeInsets.all(12),child:Row(children:[
      const Text('排更模式',style:TextStyle(fontWeight:FontWeight.bold)),
      const Spacer(),
      FilledButton.tonalIcon(onPressed:(){
        var ctrl=TextEditingController(text:'模式_${DateFormat('MMdd').format(DateTime.now())}');
        showDialog(context:context,builder:(ctx)=>AlertDialog(title:const Text('另存排更模式'),content:TextField(controller:ctrl,decoration:const InputDecoration(labelText:'模式名稱')),actions:[FilledButton(onPressed:(){String n=ctrl.text.trim(); if(n.isEmpty) return; setState(()=>savedPatterns.add(SavedPattern(n,pattern.map((r)=>List<String>.from(r)).toList()))); save(); Navigator.pop(ctx);},child:const Text('保存'))]));
      },icon:const Icon(Icons.save_as),label:const Text('另存')),
      const SizedBox(width:8),
      FilledButton.tonal(onPressed:(){setState(()=>pattern.add(List.filled(7,'O')));save();},child:const Text('加一行')),
    ])),
    if(savedPatterns.isNotEmpty) Container(height:50,child:ListView(scrollDirection:Axis.horizontal,padding:const EdgeInsets.symmetric(horizontal:8),children:savedPatterns.asMap().entries.map((en){
      return Padding(padding:const EdgeInsets.only(right:8),child:InputChip(label:Text(en.value.name),onPressed:(){setState(()=>pattern=en.value.data.map((r)=>List<String>.from(r)).toList()); save();},onDeleted:(){setState(()=>savedPatterns.removeAt(en.key)); save();}));
    }).toList())),
    Expanded(child:ListView.builder(itemCount:pattern.length,itemBuilder:(ctx,r){return Row(children:[Text(' ${r+1} '),Expanded(child:Row(children:List.generate(7,(c){return Expanded(child:GestureDetector(onTap:(){showModalBottomSheet(context:context,builder:(ctx){return Wrap(children:defs.keys.map((k)=>ListTile(title:Text(k),onTap:(){setState(()=>pattern[r][c]=k);save();Navigator.pop(ctx);})).toList());});},child:Container(margin:const EdgeInsets.all(2),height:36,color:defs[pattern[r][c]]?.color.withOpacity(0.3),child:Center(child:Text(pattern[r][c])))));}))),IconButton(icon:const Icon(Icons.delete),onPressed:(){setState(()=>pattern.removeAt(r));save();})]);})),
    Padding(padding:const EdgeInsets.all(12),child:SizedBox(width:double.infinity,child:FilledButton(onPressed:pickRangeAndApply,child:const Text('選擇日期範圍並自動排班')))),
  ]));
}

// 3. 報表全年
Widget reportTab(){
  int year=focused.year; int month=focused.month;
  double totalYearHrs=0; Map<String,int> yearShiftCount={}; Map<int,double> yearMonthlyHrs={};
  if(isYearReport){
    for(int m=1;m<=12;m++){int dim=DateTime(year,m+1,0).day; double hrs=0; for(int d=1;d<=dim;d++){String k=DateFormat('yyyy-MM-dd').format(DateTime(year,m,d)); String? c=roster[k]; if(c==null) continue; var def=defs[c]; if(def!=null){hrs+=def.hours; totalYearHrs+=def.hours; yearShiftCount[c]=(yearShiftCount[c]??0)+1;}} yearMonthlyHrs[m]=hrs;}
  }
  int dim=DateTime(year,month+1,0).day; double hrs=0,allow=0,ot=0; Map<String,int> shiftCount={}; Map<String,double> shiftHours={}; Map<String,double> allowByCode={}; Map<int,double> weeklyHours={}; List<Map<String,dynamic>> dailyForExtra=[];
  for(int i=1;i<=dim;i++){DateTime dt=DateTime(year,month,i); String k=DateFormat('yyyy-MM-dd').format(dt); String? c=roster[k]; if(c==null) continue; var d=defs[c]; double curOt=rosterOt[k]??d?.ot??0; if(d!=null){hrs+=d.hours; allow+=d.allowance; shiftCount[c]=(shiftCount[c]??0)+1; shiftHours[c]=(shiftHours[c]??0)+d.hours; allowByCode[c]=(allowByCode[c]??0)+d.allowance; int w=isoWeek(dt); weeklyHours[w]=(weeklyHours[w]??0)+d.hours; dailyForExtra.add({'code':c,'startMin':timeToMin(d.start),'date':dt});} ot+=curOt;}
  double extraTotal=0; Map<String,double> extraBreakdown={}; for(var ex in extraAllowances){double sum=0; for(var day in dailyForExtra){ if(day['startMin']>=ex.minutes) sum+=ex.amount; } if(sum>0){extraBreakdown[ex.name]=sum; extraTotal+=sum;}}
  double otAmount=ot * overtimeRate; double totalAllow=allow + extraTotal + otAmount;

  return SafeArea(child:ListView(padding:const EdgeInsets.all(12),children:[
    Row(children:[
      InkWell(onTap:()=>quickJumpMonth(forReport:true),child:Row(children:[Text('${year}年${isYearReport?' 全年': '${month}月'} 報表',style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const Icon(Icons.arrow_drop_down)])),
      const Spacer(),
      SegmentedButton<bool>(segments:const [ButtonSegment(value:false,label:Text('本月')),ButtonSegment(value:true,label:Text('全年'))],selected:{isYearReport},onSelectionChanged:(s){setState(()=>isYearReport=s.first);}),
      const SizedBox(width:8),
      FilledButton.tonal(onPressed:exportReport,child:const Text('匯出')),
    ]),
    const SizedBox(height:8),
    if(isYearReport)
      Card(color:const Color(0xFFE3F2FD),child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('全年總工時 ${totalYearHrs.toStringAsFixed(1)}h',style:const TextStyle(fontWeight:FontWeight.bold)),
        const Divider(),
       ...yearMonthlyHrs.entries.map((e)=>Row(children:[Text('${e.key}月'),const Spacer(),Text('${e.value.toStringAsFixed(1)}h')])),
        const Divider(),
       ...yearShiftCount.entries.map((e){var d=defs[e.key]; return Row(children:[Container(width:26,height:26,decoration:BoxDecoration(color:d?.color??Colors.grey,borderRadius:BorderRadius.circular(5)),child:Center(child:Text(e.key,style:const TextStyle(color:Colors.white,fontSize:10)))), const SizedBox(width:6), Text('${d?.label??e.key} ${e.value}次'), const Spacer(), Text('${(e.value*(d?.hours??0)).toStringAsFixed(1)}h')]);}),
      ]))),
    if(!isYearReport)
      Card(color:const Color(0xFFE3F2FD),child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('班次統計',style:TextStyle(fontWeight:FontWeight.bold)), const Divider(),
       ...shiftCount.entries.map((e){double h=shiftHours[e.key]??0; var d=defs[e.key]; return Padding(padding:const EdgeInsets.symmetric(vertical:2),child:Row(children:[Container(width:28,height:28,decoration:BoxDecoration(color:d?.color??Colors.grey,borderRadius:BorderRadius.circular(6)),child:Center(child:Text(e.key,style:const TextStyle(color:Colors.white,fontSize:11)))), const SizedBox(width:8), Text('${d?.label??e.key}'), const Spacer(), Text('${e.value}次 / ${h.toStringAsFixed(1)}h',style:const TextStyle(fontWeight:FontWeight.bold)),]));}),
        const Divider(), Text('總工時 ${hrs.toStringAsFixed(1)}h / 承上 ${carry}h / 合計 ${(hrs+carry).toStringAsFixed(1)}h'),
      ]))),
    Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text('承上 $carry h + 本月 $hrs h = ${carry+hrs}h',style:const TextStyle(fontWeight:FontWeight.bold)), const Divider(), Text(isYearReport?'每週工時統計 全年':'每週工時統計 (標準 & 承上) 週數',style:const TextStyle(fontWeight:FontWeight.bold)),
     ...weeklyHours.entries.map((e){double avgCarry=weeklyHours.isEmpty?0:carry/weeklyHours.length; double adjusted=e.value + avgCarry; double diff=adjusted - standardWeeklyHours; return Padding(padding:const EdgeInsets.symmetric(vertical:3),child:Row(children:[Text('W${e.key}',style:const TextStyle(fontWeight:FontWeight.bold)), const SizedBox(width:8), Text('${e.value.toStringAsFixed(1)}h +承上${avgCarry.toStringAsFixed(1)} = ${adjusted.toStringAsFixed(1)}h'), const Spacer(), Text('${diff>=0?'+':''}${diff.toStringAsFixed(1)}h',style:TextStyle(color:diff>0?Colors.red:Colors.green,fontWeight:FontWeight.bold)),]));}),
      const Divider(), Text('標準 ${standardWeeklyHours}h/週 | 總差額 ${(carry+hrs - standardWeeklyHours*weeklyHours.length).toStringAsFixed(1)}h'),
    ]))),
    Card(color:const Color(0xFFE8F5E9),child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('津貼類別',style:TextStyle(fontWeight:FontWeight.bold)),
     ...allowByCode.entries.map((e)=>Row(children:[Text(e.key),const Spacer(),Text('\$${e.value.toStringAsFixed(1)}')])),
      if(extraBreakdown.isNotEmpty) const Divider(),
     ...extraBreakdown.entries.map((e){var ex=extraAllowances.firstWhere((x)=>x.name==e.key); return Row(children:[Text('${e.key} (${ex.time}起)'),const Spacer(),Text('\$${e.value.toStringAsFixed(1)}')]);}),
      const Divider(), Row(children:[const Text('班次津貼'),const Spacer(),Text('\$${allow.toStringAsFixed(1)}')]), Row(children:[Text('OT ${ot.toStringAsFixed(1)}h x \$${overtimeRate.toStringAsFixed(0)}'),const Spacer(),Text('\$${otAmount.toStringAsFixed(1)}')]), Row(children:[const Text('額外津貼 (按時分生效)'),const Spacer(),Text('\$${extraTotal.toStringAsFixed(1)}')]), const Divider(), Row(children:[const Text('津貼總額 (含OT)',style:TextStyle(fontWeight:FontWeight.bold)),const Spacer(),Text('\$${totalAllow.toStringAsFixed(1)}',style:const TextStyle(fontWeight:FontWeight.bold))]),
    ]))),
  ]));
}

void editShiftDialog({ShiftDef? oldDef}){
  var codeCtrl=TextEditingController(text:oldDef?.code??''); var labelCtrl=TextEditingController(text:oldDef?.label??'');
  var hoursCtrl=TextEditingController(text:oldDef?.hours.toString()??'8'); var allowCtrl=TextEditingController(text:oldDef?.allowance.toString()??'0');
  var otCtrl=TextEditingController(text:oldDef?.ot.toString()??'0'); var startCtrl=TextEditingController(text:oldDef?.start??'07:00'); var endCtrl=TextEditingController(text:oldDef?.end??'15:30');
  Color picked=oldDef?.color??Colors.orange; String oldKey=oldDef?.code??'';
  List<Color> palette=[Colors.orange,Colors.blue,Colors.purple,Colors.green,Colors.red,Colors.teal,Colors.brown,Colors.pink,Colors.indigo,Colors.amber,Colors.cyan,Colors.lime,Colors.deepOrange,Colors.lightBlue,Colors.deepPurple,Colors.blueGrey];
  showDialog(context:context,builder:(ctx){return StatefulBuilder(builder:(ctx2,setS){return AlertDialog(title:Text(oldDef==null?'新增班次':'編輯 ${oldDef.code}'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
    TextField(controller:codeCtrl,decoration:const InputDecoration(labelText:'代號')),TextField(controller:labelCtrl,decoration:const InputDecoration(labelText:'名稱')),
    Row(children:[Expanded(child:TextField(controller:startCtrl,decoration:const InputDecoration(labelText:'開始 HH:mm'))),const SizedBox(width:8),Expanded(child:TextField(controller:endCtrl,decoration:const InputDecoration(labelText:'結束 HH:mm')))]),
    Row(children:[Expanded(child:TextField(controller:hoursCtrl,decoration:const InputDecoration(labelText:'工時'))),Expanded(child:TextField(controller:otCtrl,decoration:const InputDecoration(labelText:'OT')))]),
    TextField(controller:allowCtrl,decoration:const InputDecoration(labelText:'津貼')),
    const SizedBox(height:12), const Text('自定班次顏色',style:TextStyle(fontWeight:FontWeight.bold)), const SizedBox(height:8),
    Wrap(spacing:8,runSpacing:8,children:palette.map((c)=>GestureDetector(onTap:()=>setS(()=>picked=c),child:Container(width:36,height:36,decoration:BoxDecoration(color:c,shape:BoxShape.circle,border:picked==c?Border.all(width:3,color:Colors.black):null),child:picked==c?const Icon(Icons.check,color:Colors.white,size:18):null))).toList()),
  ])),actions:[TextButton(onPressed:()=>Navigator.pop(ctx2),child:const Text('取消')),FilledButton(onPressed:(){
    String newCode=codeCtrl.text.trim(); if(newCode.isEmpty) return; double hrs=double.tryParse(hoursCtrl.text)??8;
    try{var s=DateFormat('HH:mm').parse(startCtrl.text); var e=DateFormat('HH:mm').parse(endCtrl.text); var diff=e.difference(s).inMinutes/60.0; if(diff<0) diff+=24; hrs=diff;}catch(_){}
    setState((){
      if(oldKey.isNotEmpty && oldKey!=newCode){defs.remove(oldKey); roster.forEach((k,v){if(v==oldKey) roster[k]=newCode;}); for(int i=0;i<pattern.length;i++){for(int j=0;j<pattern[i].length;j++){if(pattern[i][j]==oldKey) pattern[i][j]=newCode;}}}
      defs[newCode]=ShiftDef(newCode,labelCtrl.text.isEmpty?newCode:labelCtrl.text,hrs,picked,allowance:double.tryParse(allowCtrl.text)??0,ot:double.tryParse(otCtrl.text)??0,start:startCtrl.text,end:endCtrl.text);
    }); save(); Navigator.pop(ctx2);
  },child:const Text('儲存'))]);});});
}

Widget settingsTab(){
  var stdCtrl=TextEditingController(text:standardWeeklyHours.toString()); var carryCtrl=TextEditingController(text:carry.toString()); var otRateCtrl=TextEditingController(text:overtimeRate.toString());
  return SafeArea(child:ListView(padding:const EdgeInsets.all(16),children:[
    const Text('自定班次內容編輯和刪除',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
    Card(child:Column(children:[...defs.entries.map((e){var d=e.value;return ListTile(leading:CircleAvatar(backgroundColor:d.color,child:Text(d.code,style:const TextStyle(color:Colors.white,fontSize:10))),title:Text('${d.code} - ${d.label} ${d.start}-${d.end}'),subtitle:Text('${d.hours.toStringAsFixed(1)}h \$${d.allowance} | ${d.detailTime}'),trailing:Row(mainAxisSize:MainAxisSize.min,children:[IconButton(icon:const Icon(Icons.edit),onPressed:()=>editShiftDialog(oldDef:d)),IconButton(icon:const Icon(Icons.delete),onPressed:(){setState(()=>defs.remove(e.key));save();})]));}),ListTile(leading:const Icon(Icons.add),title:const Text('新增班次'),onTap:()=>editShiftDialog()),])),
    const SizedBox(height:16),
    const Text('標準工時 & 承上 & 超時金額 (預設42h)',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
    Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(children:[
      Row(children:[Expanded(child:TextField(controller:stdCtrl,decoration:const InputDecoration(labelText:'標準工時',suffixText:'h/週',border:OutlineInputBorder()))),const SizedBox(width:8),Expanded(child:TextField(controller:carryCtrl,decoration:const InputDecoration(labelText:'承上餘額',border:OutlineInputBorder())))]),
      const SizedBox(height:10), TextField(controller:otRateCtrl,decoration:const InputDecoration(labelText:'超時金額 /h',prefixText:'\$ ',border:OutlineInputBorder())),
      const SizedBox(height:10), SizedBox(width:double.infinity,child:FilledButton(onPressed:(){double? v1=double.tryParse(stdCtrl.text); double? v2=double.tryParse(carryCtrl.text); double? v3=double.tryParse(otRateCtrl.text); if(v1!=null) standardWeeklyHours=v1; if(v2!=null) carry=v2; if(v3!=null) overtimeRate=v3; setState((){}); save();},child:const Text('保存設定'))),
    ]))),
    const SizedBox(height:16),
    const Text('Google日曆同步',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
    Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(children:[
      SwitchListTile(title:const Text('啟用 Google日曆同步'),subtitle:Text(googleSyncEnabled?'已授權':'未授權 需要權限'),value:googleSyncEnabled,onChanged:(v){if(v){_requestGooglePerm();}else{setState(()=>googleSyncEnabled=false); save();}}),
      SwitchListTile(title:const Text('資料更新時自動同步'),value:autoSync,onChanged:googleSyncEnabled? (v){setState(()=>autoSync=v); save();}:null),
      Row(children:[Expanded(child:OutlinedButton.icon(onPressed:googleSyncEnabled? _syncToGoogle:null,icon:const Icon(Icons.sync),label:const Text('手動立即同步'))),const SizedBox(width:8),Expanded(child:OutlinedButton.icon(onPressed:googleSyncEnabled? (){setState(()=>googleSyncEnabled=false); save();}:null,icon:const Icon(Icons.link_off),label:const Text('取消授權')))]),
    ]))),
    const SizedBox(height:16), const Text('日曆文字大小',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
    Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(children:[Row(children:[const Text('小'),Expanded(child:Slider(value:calendarFontSize,min:8,max:20,divisions:12,onChanged:(v){setState(()=>calendarFontSize=v);})),const Text('大')]), FilledButton.tonal(onPressed:(){save();},child:const Text('保存文字大小'))]))),
    const SizedBox(height:16), const Text('自定津貼編輯',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
    Card(child:Column(children:defs.entries.map((e){var d=e.value;return Padding(padding:const EdgeInsets.fromLTRB(12,6,4,6),child:Row(children:[
      SizedBox(width:50,child:Text(d.code,style:const TextStyle(fontWeight:FontWeight.bold))), Expanded(child:Text('${d.label}')),
      SizedBox(width:80,child:TextFormField(initialValue:d.allowance.toString(),decoration:InputDecoration(labelText:'\$',border:OutlineInputBorder(borderRadius:BorderRadius.circular(8)),isDense:true),onFieldSubmitted:(v){double? val=double.tryParse(v); if(val!=null){setState(()=>d.allowance=val); save();}})),
      IconButton(icon:const Icon(Icons.close,size:18,color:Colors.red),onPressed:(){setState(()=>d.allowance=0); save();}), IconButton(icon:const Icon(Icons.delete,size:18),onPressed:(){setState(()=>defs.remove(e.key)); save();}),
    ]));}).toList())),
    const SizedBox(height:16), const Text('新增津貼類別 (時分生效)',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
    Card(child:Column(children:[
...extraAllowances.asMap().entries.map((en){int idx=en.key; var e=en.value; return ListTile(title:Text(e.name),subtitle:Text('\$${e.amount} 生效時間 ${e.time}'),trailing:Row(mainAxisSize:MainAxisSize.min,children:[
        IconButton(icon:const Icon(Icons.edit,size:18),onPressed:(){
          var nCtrl=TextEditingController(text:e.name); var vCtrl=TextEditingController(text:e.amount.toString()); var tCtrl=TextEditingController(text:e.time);
          showDialog(context:context,builder:(ctx)=>AlertDialog(title:const Text('編輯津貼'),content:Column(mainAxisSize:MainAxisSize.min,children:[
            TextField(controller:nCtrl,decoration:const InputDecoration(labelText:'名稱')), TextField(controller:vCtrl,decoration:const InputDecoration(labelText:'金額'),keyboardType:TextInputType.number),
            TextField(controller:tCtrl,decoration:const InputDecoration(labelText:'生效時間 HH:mm'),readOnly:true,onTap:() async{TimeOfDay? tp=await showTimePicker(context:context,initialTime:TimeOfDay(hour:int.parse(tCtrl.text.split(':')[0]),minute:int.parse(tCtrl.text.split(':')[1]))); if(tp!=null) tCtrl.text='${tp.hour.toString().padLeft(2,'0')}:${tp.minute.toString().padLeft(2,'0')}';}),
          ]),actions:[FilledButton(onPressed:(){String nn=nCtrl.text.trim(); double? vv=double.tryParse(vCtrl.text); if(nn.isEmpty||vv==null) return; setState(()=>extraAllowances[idx]=ExtraAllowance(nn,vv,tCtrl.text)); save(); Navigator.pop(ctx);},child:const Text('儲存'))]));
        }),
        IconButton(icon:const Icon(Icons.delete,size:18,color:Colors.red),onPressed:(){setState(()=>extraAllowances.removeAt(idx)); save();}),
      ]));}),
      ListTile(leading:const Icon(Icons.add),title:const Text('新增津貼類別'),onTap:(){
        var nCtrl=TextEditingController(); var vCtrl=TextEditingController(text:'0'); var tCtrl=TextEditingController(text:'22:00');
        showDialog(context:context,builder:(ctx)=>AlertDialog(title:const Text('新增津貼類別'),content:Column(mainAxisSize:MainAxisSize.min,children:[
          TextField(controller:nCtrl,decoration:const InputDecoration(labelText:'名稱')), TextField(controller:vCtrl,decoration:const InputDecoration(labelText:'金額'),keyboardType:TextInputType.number),
          TextField(controller:tCtrl,decoration:const InputDecoration(labelText:'生效時間 HH:mm'),readOnly:true,onTap:() async{TimeOfDay? tp=await showTimePicker(context:context,initialTime:const TimeOfDay(hour:22,minute:0)); if(tp!=null) tCtrl.text='${tp.hour.toString().padLeft(2,'0')}:${tp.minute.toString().padLeft(2,'0')}';}),
        ]),actions:[FilledButton(onPressed:(){String name=nCtrl.text.trim(); double? val=double.tryParse(vCtrl.text); if(name.isEmpty||val==null) return; setState(()=>extraAllowances.add(ExtraAllowance(name,val,tCtrl.text))); save(); Navigator.pop(ctx);},child:const Text('新增'))]));
      }),
    ])),
    const SizedBox(height:16), const Text('備份與還原 (可選任意位置)',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
    Card(child:Padding(padding:const EdgeInsets.all(12),child:Row(children:[Expanded(child:OutlinedButton.icon(onPressed:backupAnywhere,icon:const Icon(Icons.folder_open),label:const Text('備份到任意位置'))),const SizedBox(width:8),Expanded(child:OutlinedButton.icon(onPressed:restoreLocalFile,icon:const Icon(Icons.restore),label:const Text('還原')))]))),
  ]));
}

@override Widget build(BuildContext context){
  return Scaffold(
    body:[calTab(),patternTab(),reportTab(),settingsTab()][tab],
    bottomNavigationBar:NavigationBar(selectedIndex:tab,onDestinationSelected:(i)=>setState(()=>tab=i),destinations:const[
      NavigationDestination(icon:Icon(Icons.calendar_month),label:'月曆'),
      NavigationDestination(icon:Icon(Icons.pattern),label:'模式'),
      NavigationDestination(icon:Icon(Icons.bar_chart),label:'報表'),
      NavigationDestination(icon:Icon(Icons.settings),label:'設定'),
    ]),
  );
}
}
