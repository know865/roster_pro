import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/calendar/v3.dart' as cal;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';

void main(){runApp(const RosterApp());}

class ShiftDef{
  String code;String label;double hours;double allowance;double ot;Color color;String start;String end;
  ShiftDef(this.code,this.label,this.hours,this.color,{this.allowance=0,this.ot=0,this.start="08:00",this.end="16:00"});
  Map<String,dynamic> toJson()=>{'code':code,'label':label,'hours':hours,'allowance':allowance,'ot':ot,'color':color.value,'start':start,'end':end};
  factory ShiftDef.fromJson(Map<String,dynamic> j)=>ShiftDef(j['code'],j['label']??j['code'],(j['hours']??8).toDouble(),Color(j['color']??0xFFFF9800),allowance:(j['allowance']??0).toDouble(),ot:(j['ot']??0).toDouble(),start:j['start']??"08:00",end:j['end']??"16:00");
}

class RosterApp extends StatelessWidget{
  const RosterApp({super.key});
  @override
  Widget build(BuildContext context){
    return MaterialApp(title:'Roster Pro v6.22',theme:ThemeData(useMaterial3:true,colorSchemeSeed:Colors.deepPurple),home:const MainPage());
  }
}

class MainPage extends StatefulWidget{
  const MainPage({super.key});
  @override
  State<MainPage> createState()=>MainPageState();
}

class MainPageState extends State<MainPage>{
  int tab=0;
  DateTime focused=DateTime.now();
  DateTime selectedDay=DateTime.now();
  Map<String,String> roster={};
  Map<String,String> rosterNote={};
  Map<String,double> rosterOT={};
  Map<String,ShiftDef> defs={
    '早':ShiftDef('早','早更 07:00-15:30',8,Colors.orange,start:"07:00",end:"15:30"),
    '中':ShiftDef('中','中更 14:00-22:00',8,Colors.blue,start:"14:00",end:"22:00"),
    '夜':ShiftDef('夜','夜更 22:00-06:00',8,Colors.indigo,start:"22:00",end:"06:00"),
    '通宵':ShiftDef('通宵','通宵 23:30-08:00',8,Colors.purple,allowance:120,start:"23:30",end:"08:00"),
    'OT':ShiftDef('OT','加班',0,Colors.brown,ot:2),
    'O':ShiftDef('O','休',0,Colors.green),
  };
  List<List<String>> pattern=[["早","早","中","中","夜","夜","O"],["早","早","早","中","中","O","O"]];
  String customName='我的排更';
  String? calId;
  double carry=0;
  final GoogleSignIn gSign=GoogleSignIn(scopes:[drive.DriveApi.driveFileScope,cal.CalendarApi.calendarScope]);
  final Map<String,String> hols={'09-22':'秋分','09-25':'中秋翌日'};

  @override
  void initState(){super.initState();load();}
  Future<void> load() async{
    var sp=await SharedPreferences.getInstance();
    var r=sp.getString('roster'); if(r!=null){roster=Map<String,String>.from(jsonDecode(r));}
    var rn=sp.getString('rosterNote'); if(rn!=null){rosterNote=Map<String,String>.from(jsonDecode(rn));}
    var ro=sp.getString('rosterOT'); if(ro!=null){var m=jsonDecode(ro); rosterOT=m.map<String,double>((k,v)=>MapEntry(k,(v as num).toDouble()));}
    var d=sp.getString('defs'); if(d!=null){try{var m=Map<String,dynamic>.from(jsonDecode(d)); defs=m.map((k,v)=>MapEntry(k,ShiftDef.fromJson(v)));}catch(_){}}
    var p=sp.getString('pattern'); if(p!=null){try{var list=jsonDecode(p) as List; pattern=list.map<List<String>>((row)=>(row as List).map<String>((e)=>e.toString()).toList()).toList();}catch(_){}}
    setState((){
      customName=sp.getString('cName')??'我的排更';
      calId=sp.getString('calId');
      carry=sp.getDouble('carry')??0;
      var fm=sp.getString('focused'); if(fm!=null){try{focused=DateTime.parse(fm);}catch(_){}}
      var sd=sp.getString('selectedDay'); if(sd!=null){try{selectedDay=DateTime.parse(sd);}catch(_){}}
    });
  }
  Future<void> save() async{
    var sp=await SharedPreferences.getInstance();
    sp.setString('roster',jsonEncode(roster));
    sp.setString('rosterNote',jsonEncode(rosterNote));
    sp.setString('rosterOT',jsonEncode(rosterOT));
    sp.setString('defs',jsonEncode(defs.map((k,v)=>MapEntry(k,v.toJson()))));
    sp.setString('pattern',jsonEncode(pattern));
    sp.setString('cName',customName);
    if(calId!=null) sp.setString('calId',calId!);
    sp.setDouble('carry',carry);
    sp.setString('focused',focused.toIso8601String());
    sp.setString('selectedDay',selectedDay.toIso8601String());
  }
  int isoWeekNumber(DateTime date){
    var jan1=DateTime(date.year,1,1);
    var days=(date.difference(jan1).inDays+jan1.weekday-1);
    return 1+(days/7).floor();
  }
  Map<String,dynamic> report(DateTime m){
    int dim=DateTime(m.year,m.month+1,0).day;
    Map<String,int> cnt={}; double hrs=0,ot=0,allow=0;
    for(int i=1;i<=dim;i++){
      String k=DateFormat('yyyy-MM-dd').format(DateTime(m.year,m.month,i));
      String? code=roster[k]; if(code==null) continue;
      cnt[code]=(cnt[code]??0)+1;
      var d=defs[code]; if(d!=null){hrs+=d.hours; ot+=d.ot+(rosterOT[k]??0); allow+=d.allowance;}
    }
    return {'cnt':cnt,'hrs':hrs,'ot':ot,'allow':allow,'bal':carry+hrs};
  }

  Widget calTab(){
    DateTime first=DateTime(focused.year,focused.month,1);
    DateTime start=first.subtract(Duration(days:first.weekday-1));
    List<DateTime> days=List.generate(42,(i)=>start.add(Duration(days:i)));
    var rep=report(focused);
    String selKey=DateFormat('yyyy-MM-dd').format(selectedDay);
    String? selCode=roster[selKey];
    var selDef=selCode!=null?defs[selCode]:null;
    return Column(children:[
      Padding(padding:const EdgeInsets.fromLTRB(12,8,12,4),child:Row(children:[
        const Icon(Icons.calendar_today,size:22),
        const SizedBox(width:8),
        GestureDetector(onTap:() async{var d=await showDatePicker(context:context,initialDate:focused,firstDate:DateTime(2024),lastDate:DateTime(2028)); if(d!=null){setState((){focused=DateTime(d.year,d.month,1); selectedDay=d;}); save();}},child:Row(children:[Text('${focused.year}年${focused.month}月',style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const Icon(Icons.arrow_drop_down)])),
        const Spacer(),
        Container(decoration:BoxDecoration(color:Colors.grey.shade100,borderRadius:BorderRadius.circular(20)),child:Row(children:[
          IconButton(icon:const Icon(Icons.chevron_left,size:20),onPressed:(){setState((){focused=DateTime(focused.year,focused.month-1,1);}); save();}),
          Container(width:1,height:20,color:Colors.grey.shade300),
          IconButton(icon:const Icon(Icons.chevron_right,size:20),onPressed:(){setState((){focused=DateTime(focused.year,focused.month+1,1);}); save();}),
        ])),
        const SizedBox(width:8),
        IconButton(icon:const Icon(Icons.my_location),onPressed:(){setState((){focused=DateTime.now(); selectedDay=DateTime.now();}); save();},tooltip:'返回今天'),
      ])),
      Padding(padding:const EdgeInsets.symmetric(horizontal:8,vertical:4),child:Row(children: const[
        Expanded(child:Text('Mon',textAlign:TextAlign.center,style:TextStyle(fontSize:12))),
        Expanded(child:Text('Tue',textAlign:TextAlign.center,style:TextStyle(fontSize:12))),
        Expanded(child:Text('Wed',textAlign:TextAlign.center,style:TextStyle(fontSize:12))),
        Expanded(child:Text('Thu',textAlign:TextAlign.center,style:TextStyle(fontSize:12))),
        Expanded(child:Text('Fri',textAlign:TextAlign.center,style:TextStyle(fontSize:12))),
        Expanded(child:Text('Sat',textAlign:TextAlign.center,style:TextStyle(fontSize:12))),
        Expanded(child:Text('Sun',textAlign:TextAlign.center,style:TextStyle(fontSize:12))),
      ])),
      Expanded(child:GridView.builder(padding:const EdgeInsets.symmetric(horizontal:6),gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:7,childAspectRatio:0.78,mainAxisSpacing:6,crossAxisSpacing:6),itemCount:42,itemBuilder:(ctx,idx){
        DateTime day=days[idx];
        bool inMonth=day.month==focused.month;
        String k=DateFormat('yyyy-MM-dd').format(day);
        String? code=roster[k];
        var def=code!=null?defs[code]:null;
        bool isSelected=DateFormat('yyyy-MM-dd').format(day)==DateFormat('yyyy-MM-dd').format(selectedDay);
        bool hol=hols.containsKey(DateFormat('MM-dd').format(day));
        String weekLabel=''; if(idx%7==0){int wk=isoWeekNumber(day); weekLabel='W$wk';}
        Color bg;
        if(!inMonth){bg=const Color(0xFFF5F5F0);}
        else if(isSelected){bg=Colors.white;}
        else if(def!=null){bg=Color.lerp(Colors.white,def.color,0.15)??const Color(0xFFFFF0D0);}
        else {bg=const Color(0xFFFFF0D0);}
        if(code=='O'){bg=const Color(0xFFE0F2E9);}
        if(day.day==16 && inMonth && code=='中'){bg=const Color(0xFFD0E8FF);}
        return GestureDetector(onTap:(){setState((){selectedDay=day;});},child:Container(decoration:BoxDecoration(color:bg,borderRadius:BorderRadius.circular(16),border:isSelected?Border.all(color:Colors.black,width:2):Border.all(color:Colors.transparent)),child:Stack(children:[
          if(weekLabel.isNotEmpty) Positioned(left:6,top:4,child:Text(weekLabel,style:TextStyle(fontSize:9,color:Colors.brown.shade400,fontWeight:FontWeight.bold))),
          Positioned(right:6,top:4,child:Row(children:[
            if(rosterNote[k]!=null&&rosterNote[k]!.isNotEmpty) Container(width:6,height:6,margin:const EdgeInsets.only(right:3),decoration:const BoxDecoration(color:Colors.red,shape:BoxShape.circle)),
            if(rosterOT[k]!=null&&rosterOT[k]! >0) Container(width:6,height:6,decoration:const BoxDecoration(color:Colors.blue,shape:BoxShape.circle)),
          ])),
          Center(child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
            Text('${day.day}',style:TextStyle(fontSize:16,fontWeight:FontWeight.bold,color:inMonth?Colors.black:Colors.grey)),
            const SizedBox(height:4),
            if(code!=null) Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:2),decoration:BoxDecoration(color:def?.color??Colors.orange,borderRadius:BorderRadius.circular(10)),child:FittedBox(fit:BoxFit.scaleDown,child:Text(code,style:const TextStyle(fontSize:12,color:Colors.white,fontWeight:FontWeight.bold)))),
            if(hol) Padding(padding:const EdgeInsets.only(top:2),child:Text(hols[DateFormat('MM-dd').format(day)]!,style:const TextStyle(fontSize:9,color:Colors.red))),
          ])),
        ])));
      })),
      Container(padding:const EdgeInsets.fromLTRB(16,12,16,12),decoration:BoxDecoration(color:Colors.white,border:Border(top:BorderSide(color:Colors.grey.shade200))),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[
          Expanded(child:Text('${DateFormat('MM/dd EEE','en').format(selectedDay)} ${hols[DateFormat('MM-dd').format(selectedDay)]??''} ${selCode??''}'.trim(),style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold))),
          FilledButton.icon(onPressed:(){showDayDetail(selectedDay);},style: FilledButton.styleFrom(backgroundColor:Colors.deepPurple,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(20))),icon:const Icon(Icons.edit,size:16),label:const Text('編輯')),
        ]),
        if(selDef!=null) Padding(padding:const EdgeInsets.only(top:4),child:Text('${selDef.label} ${selDef.start}-${selDef.end} 工時${selDef.hours}h ${selDef.allowance>0?'津貼\$${selDef.allowance}':''} ${selDef.ot>0?'OT${selDef.ot}h':''} ${rosterOT[selKey]!=null?'額外OT ${rosterOT[selKey]}h':''}',style:TextStyle(color:Colors.grey.shade600,fontSize:13))),
        const SizedBox(height:8),
        Container(padding:const EdgeInsets.all(12),decoration:BoxDecoration(border:Border.all(color:Colors.blue.shade300),borderRadius:BorderRadius.circular(16)),child:Row(children:[Expanded(child:Text(rosterNote[selKey]??'哈哈',style:TextStyle(color:rosterNote[selKey]==null?Colors.grey:Colors.black))),])),
      ])),
      Padding(padding:const EdgeInsets.symmetric(horizontal:12,vertical:4),child:Card(child:ListTile(dense:true,title:Text('承上 $carry h + 本月 ${rep['hrs']}h = 餘額 ${rep['bal']}h | OT ${rep['ot']}h'),subtitle:Text('津貼 \$${rep['allow']}'),trailing:IconButton(icon:const Icon(Icons.edit),onPressed:(){editCarry();})))),
    ]);
  }

  void showDayDetail(DateTime day){
    String k=DateFormat('yyyy-MM-dd').format(day);
    String? code=roster[k];
    String note=rosterNote[k]??'';
    double ot=rosterOT[k]??0;
    TextEditingController noteCtrl=TextEditingController(text:note);
    TextEditingController otCtrl=TextEditingController(text:ot==0?'':ot.toString());
    String selected=code??'';
    showModalBottomSheet(context:context,isScrollControlled:true,builder:(ctx){
      return StatefulBuilder(builder:(ctx2,setM){
        return Padding(padding:EdgeInsets.only(bottom:MediaQuery.of(ctx2).viewInsets.bottom),child:Container(padding:const EdgeInsets.all(16),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('${DateFormat('yyyy-MM-dd EEE','zh').format(day)} ${hols[DateFormat('MM-dd').format(day)]??''}',style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
          const SizedBox(height:12),
          const Text('班次 - 長代號不限制 (早收XXXX完整顯示)',style:TextStyle(fontWeight:FontWeight.bold)),
          Wrap(spacing:6,children:defs.keys.map((c){
            var d=defs[c]!; bool sel=selected==c;
            return ChoiceChip(label:Text(c),selected:sel,selectedColor:d.color.withOpacity(0.4),onSelected:(_){setM((){selected=c;});});
          }).toList()..add(ChoiceChip(label:const Text('清除'),selected:selected==''&&code!=null,onSelected:(_){setM((){selected='__clear';});}))),
          const SizedBox(height:12),
          if(selected!=''&&selected!='__clear'&&defs[selected]!=null) Card(color:Colors.grey.shade100,child:ListTile(title:Text(defs[selected]!.label),subtitle:Text('時間 ${defs[selected]!.start}-${defs[selected]!.end} 工時 ${defs[selected]!.hours}h 津貼 \$${defs[selected]!.allowance} OT ${defs[selected]!.ot}h'),dense:true)),
          const SizedBox(height:8),
          Row(children:[
            Expanded(child:TextField(controller:otCtrl,decoration:const InputDecoration(labelText:'額外OT (小時)',border:OutlineInputBorder()),keyboardType:TextInputType.number)),
            const SizedBox(width:8),
            Expanded(child:TextField(controller:noteCtrl,decoration:const InputDecoration(labelText:'記事',border:OutlineInputBorder(),hintText:'例如: 哈哈'),)),
          ]),
          const SizedBox(height:12),
          Row(children:[
            Expanded(child:OutlinedButton(onPressed:(){Navigator.pop(ctx2);},child:const Text('取消'))),
            const SizedBox(width:8),
            Expanded(child:FilledButton(onPressed:(){
              setState((){
                if(selected=='__clear'){roster.remove(k); rosterNote.remove(k); rosterOT.remove(k);}
                else if(selected!=''){roster[k]=selected;
                  if(noteCtrl.text.isNotEmpty){rosterNote[k]=noteCtrl.text;} else {rosterNote.remove(k);}
                  double extra=double.tryParse(otCtrl.text)??0; if(extra>0){rosterOT[k]=extra;} else {rosterOT.remove(k);}
                  selectedDay=day;
                }
              });
              save(); Navigator.pop(ctx2);
            },child:const Text('儲存'))),
          ]),
        ])));
      });
    });
  }

  void editCarry(){
    var ctrl=TextEditingController(text:carry.toString());
    showDialog(context:context,builder:(c)=>AlertDialog(title:const Text('修改承上工時'),content:TextField(controller:ctrl,keyboardType:TextInputType.number),actions:[
      TextButton(onPressed:(){Navigator.pop(c);},child:const Text('取消')),
      FilledButton(onPressed:(){setState((){carry=double.tryParse(ctrl.text)??carry;}); save(); Navigator.pop(c);},child:const Text('儲存')),
    ]));
  }

  Widget patternTab(){
    return Column(children:[
      AppBar(title:const Text('排更模式 7天 x 自定行數'),actions:[
        IconButton(icon:const Icon(Icons.add),onPressed:(){setState((){pattern.add(List.filled(7,'O'));}); save();}),
        IconButton(icon:const Icon(Icons.play_arrow),onPressed:(){showAutoApplyDialog();},tooltip:'按指定日期自動排班'),
      ]),
      Padding(padding:const EdgeInsets.all(8),child:Row(children:[const Text('行數: '),Text('${pattern.length}行'),const Spacer(),FilledButton.tonalIcon(onPressed:(){setState((){if(pattern.length>1) pattern.removeLast();}); save();},icon:const Icon(Icons.remove),label:const Text('減一行')),const SizedBox(width:8),FilledButton.tonalIcon(onPressed:(){setState((){pattern.add(List.filled(7,'O'));}); save();},icon:const Icon(Icons.add),label:const Text('加一行'))])),
      Container(padding:const EdgeInsets.all(4),color:Colors.grey.shade200,child:Row(children: const[
        SizedBox(width:40,child:Text('行',textAlign:TextAlign.center)),
        Expanded(child:Row(mainAxisAlignment:MainAxisAlignment.spaceAround,children:[Text('一'),Text('二'),Text('三'),Text('四'),Text('五'),Text('六'),Text('日')])),
      ])),
      Expanded(child:ListView.builder(itemCount:pattern.length,itemBuilder:(ctx,row){
        return Row(children:[
          SizedBox(width:40,child:Text('${row+1}',textAlign:TextAlign.center)),
          Expanded(child:Row(children:List.generate(7,(col){
            String code=pattern[row][col];
            var def=defs[code];
            return Expanded(child:GestureDetector(onTap:(){pickPatternCell(row,col);},child:Container(margin:const EdgeInsets.all(2),height:48,decoration:BoxDecoration(color:def!=null?def.color.withOpacity(0.3):Colors.white,borderRadius:BorderRadius.circular(8),border:Border.all(color:Colors.grey.shade300)),child:Center(child:FittedBox(child:Text(code,style:const TextStyle(fontWeight:FontWeight.bold)))))));
          }))),
          IconButton(icon:const Icon(Icons.delete_outline,size:18),onPressed:(){setState((){pattern.removeAt(row);}); save();}),
        ]);
      })),
      Padding(padding:const EdgeInsets.all(12),child:Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('使用說明',style:TextStyle(fontWeight:FontWeight.bold)),
        const Text('1. 點格子選擇班次，組成循環模式\n2. 按右上角 ▶ 按指定日期自動排班 (套用排更)\n3. 系統會由開始日循環套用此模式'),
      ])))),
      Padding(padding:const EdgeInsets.symmetric(horizontal:12),child:FilmedButtonLarge()),
    ]);
  }

  Widget FilmedButtonLarge(){
    return Column(children:[
      FilledButton.icon(onPressed:(){showAutoApplyDialog();},icon:const Icon(Icons.play_arrow),label:const Text('按指定日期自動排班 (套用排更)'),style: FilledButton.styleFrom(minimumSize:const Size(double.infinity,50))),
    ]);
  }

  void pickPatternCell(int r,int c){
    showModalBottomSheet(context:context,builder:(ctx){
      return SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[
       ...defs.keys.map((k){var d=defs[k]!; return ListTile(leading:CircleAvatar(backgroundColor:d.color,radius:10),title:Text('$k - ${d.label}'),onTap:(){setState((){pattern[r][c]=k;}); save(); Navigator.pop(ctx);});}),
      ]));
    });
  }

  void showAutoApplyDialog(){
    DateTime start=DateTime(focused.year,focused.month,1);
    DateTime end=DateTime(focused.year,focused.month+1,0);
    showDialog(context:context,builder:(ctx){
      return StatefulBuilder(builder:(ctx2,setD){
        return AlertDialog(title:const Text('自動根據已建立的排更模式從開始和結束日期排更'),content:Column(mainAxisSize:MainAxisSize.min,children:[
          ListTile(title:Text('開始: ${DateFormat('yyyy-MM-dd').format(start)}'),trailing:const Icon(Icons.calendar_today),onTap:() async{var d=await showDatePicker(context:ctx2,initialDate:start,firstDate:DateTime(2024),lastDate:DateTime(2028)); if(d!=null) setD(()=>start=d);}),
          ListTile(title:Text('結束: ${DateFormat('yyyy-MM-dd').format(end)}'),trailing:const Icon(Icons.calendar_today),onTap:() async{var d=await showDatePicker(context:ctx2,initialDate:end,firstDate:DateTime(2024),lastDate:DateTime(2028)); if(d!=null) setD(()=>end=d);}),
          const SizedBox(height:8),
          Text('模式 ${pattern.length}行 x 7天 = ${pattern.length*7}天一循環',style:const TextStyle(fontSize:12)),
        ]),actions:[
          TextButton(onPressed:(){Navigator.pop(ctx2);},child:const Text('取消')),
          FilledButton(onPressed:(){
            int totalDays=end.difference(start).inDays+1;
            List<String> flat=pattern.expand((row)=>row).toList();
            if(flat.isEmpty) return;
            setState((){
              int idx=0;
              for(int i=0;i<totalDays;i++){
                DateTime d=start.add(Duration(days:i));
                String k=DateFormat('yyyy-MM-dd').format(d);
                roster[k]=flat[idx % flat.length];
                idx++;
              }
            });
            save(); Navigator.pop(ctx2);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('已由 ${DateFormat('MM-dd').format(start)} 到 ${DateFormat('MM-dd').format(end)} 套用 ${totalDays} 天')));
          },child:const Text('套用')),
        ]);
      });
    });
  }

  Widget reportTab(){
    var rep=report(focused);
    Map<String,int> cnt=rep['cnt'] as Map<String,int>;
    int dim=DateTime(focused.year,focused.month+1,0).day;
    Map<String,double> hrsPerCode={};
    Map<String,double> allowPerCode={};
    Map<String,double> otPerCode={};
    Map<String,double> extraOTPerCode={};
    double totalHrs=0,totalAllow=0,totalOT=0,totalExtraOT=0;
    int workDays=0, offDays=0;
    for(int i=1;i<=dim;i++){
      DateTime d=DateTime(focused.year,focused.month,i);
      String k=DateFormat('yyyy-MM-dd').format(d);
      String? code=roster[k]; if(code==null) continue;
      var def=defs[code];
      double h=def?.hours??0;
      double al=def?.allowance??0;
      double ot=def?.ot??0;
      double extra=rosterOT[k]??0;
      hrsPerCode[code]=(hrsPerCode[code]??0)+h;
      allowPerCode[code]=(allowPerCode[code]??0)+al;
      otPerCode[code]=(otPerCode[code]??0)+ot;
      extraOTPerCode[code]=(extraOTPerCode[code]??0)+extra;
      totalHrs+=h; totalAllow+=al; totalOT+=ot; totalExtraOT+=extra;
      if(h>0) workDays++; else offDays++;
    }
    double allOT=totalOT+totalExtraOT;
    return ListView(padding:const EdgeInsets.all(12),children:[
      Row(children:[
        Text('${focused.year}年${focused.month}月 報表',style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
        const Spacer(),
        FilledButton.tonal(onPressed:(){setState((){focused=DateTime.now();});},child:const Text('今天')),
      ]),
      const SizedBox(height:12),
      Card(color:const Color(0xFFFFF3E0),child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('本月班次統計 (所有班次資料)',style:TextStyle(fontWeight:FontWeight.bold,fontSize:16)),
        const SizedBox(height:10),
        cnt.isEmpty?const Text('暫無'):Column(children:cnt.entries.map((e){
          var def=defs[e.key];
          return Padding(padding:const EdgeInsets.symmetric(vertical:4),child:Row(children:[
            Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:4),decoration:BoxDecoration(color:def?.color??Colors.orange,borderRadius:BorderRadius.circular(8)),child:Text(e.key,style:const TextStyle(color:Colors.white,fontWeight:FontWeight.bold))),
            const SizedBox(width:8),
            Expanded(child:Text('${def?.label??''} x ${e.value}次')),
            Text('${hrsPerCode[e.key]?.toStringAsFixed(1)??'0'}h'),
          ]));
        }).toList()),
        const Divider(),
        Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Text('總日數 $dim天'),Text('返工 $workDays天'),Text('休 $offDays天')]),
      ]))),
      Card(color:const Color(0xFFE3F2FD),child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('本月工時統計 (所有工時)',style:TextStyle(fontWeight:FontWeight.bold,fontSize:16)),
        const SizedBox(height:10),
        Row(children:[
          Expanded(child:Container(padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(12)),child:Column(children:[const Text('總工時'),Text('${totalHrs.toStringAsFixed(1)}h',style:const TextStyle(fontSize:22,fontWeight:FontWeight.bold,color:Colors.blue))]))),
          const SizedBox(width:8),
          Expanded(child:Container(padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(12)),child:Column(children:[const Text('餘額'),Text('${rep['bal'].toStringAsFixed(1)}h',style:const TextStyle(fontSize:22,fontWeight:FontWeight.bold))]))),
        ]),
       ...hrsPerCode.entries.map((e)=>Padding(padding:const EdgeInsets.symmetric(vertical:2),child:Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Text('${e.key} 工時'),Text('${e.value.toStringAsFixed(1)}h')] ))),
      ]))),
      Card(color:const Color(0xFFE8F5E9),child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('本月津貼統計 (所有津貼資料)',style:TextStyle(fontWeight:FontWeight.bold,fontSize:16)),
        const SizedBox(height:10),
        Container(padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(12)),child:Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[const Text('津貼總額'),Text('\$${totalAllow.toStringAsFixed(0)}',style:const TextStyle(fontSize:22,fontWeight:FontWeight.bold,color:Colors.green))])),
        const SizedBox(height:8),
       ...allowPerCode.entries.where((e)=>e.value>0).map((e)=>Padding(padding:const EdgeInsets.symmetric(vertical:2),child:Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Text('${e.key} 津貼'),Text('\$${defs[e.key]?.allowance.toStringAsFixed(0)} x ${cnt[e.key]} = \$${e.value.toStringAsFixed(0)}')]))),
        if(totalAllow==0) const Text('本月無津貼'),
      ]))),
      Card(color:const Color(0xFFFCE4EC),child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('超時工作統計 (超時資料)',style:TextStyle(fontWeight:FontWeight.bold,fontSize:16)),
        const SizedBox(height:10),
        Row(children:[
          Expanded(child:Container(padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(12)),child:Column(children:[const Text('班次OT'),Text('${totalOT.toStringAsFixed(1)}h')]))),
          const SizedBox(width:8),
          Expanded(child:Container(padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(12)),child:Column(children:[const Text('額外OT'),Text('${totalExtraOT.toStringAsFixed(1)}h')]))),
          const SizedBox(width:8),
          Expanded(child:Container(padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:Colors.red.shade50,borderRadius:BorderRadius.circular(12)),child:Column(children:[const Text('總計'),Text('${allOT.toStringAsFixed(1)}h',style:const TextStyle(color:Colors.red,fontWeight:FontWeight.bold))]))),
        ]),
        const SizedBox(height:8),
       ...otPerCode.entries.where((e)=>e.value>0).map((e)=>Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Text('${e.key} OT'),Text('${e.value.toStringAsFixed(1)}h')])),
       ...extraOTPerCode.entries.where((e)=>e.value>0).map((e)=>Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Text('${e.key} 額外'),Text('+${e.value.toStringAsFixed(1)}h')])),
      ]))),
      const SizedBox(height:12),
      const Text('每日明細 (含超時/記事/工時)',style:TextStyle(fontWeight:FontWeight.bold)),
      Card(child:ListView.separated(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),itemCount:dim,itemBuilder:(ctx,i){
        DateTime d=DateTime(focused.year,focused.month,i+1);
        String k=DateFormat('yyyy-MM-dd').format(d);
        String? code=roster[k]; if(code==null) return const SizedBox.shrink();
        var def=defs[code];
        return ListTile(dense:true,leading:CircleAvatar(backgroundColor:def?.color??Colors.orange,radius:14,child:Text(code,style:const TextStyle(fontSize:11,color:Colors.white))),title:Text('${d.day}日 ${DateFormat('EEE','zh').format(d)} ${def?.label??''}'),subtitle:Text('${def?.start??''}-${def?.end??''} 工時:${def?.hours??0}h ${rosterNote[k]??''} ${rosterOT[k]!=null?'+OT${rosterOT[k]}h':''}'.trim()),trailing:Text('${def?.hours??0}h'));
      },separatorBuilder:(_,__)=>const Divider(height:1))),
    ]);
  }

  Widget settingsTab(){
    return ListView(padding:const EdgeInsets.all(16),children:[
      const Text('備份與同步',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
      Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(children:[
        Row(children:[
          Expanded(child:OutlinedButton.icon(onPressed:backupLocal,icon:const Icon(Icons.download),label:const Text('備份到手機'))),
          const SizedBox(width:8),
          Expanded(child:OutlinedButton.icon(onPressed:restoreLocal,icon:const Icon(Icons.history),label:const Text('從手機還原'))),
        ]),
        const SizedBox(height:8),
        Row(children:[
          Expanded(child:FilledButton.icon(onPressed:backupDrive,icon:const Icon(Icons.cloud_upload),label:const Text('備份到Drive'))),
          const SizedBox(width:8),
          Expanded(child:FilledButton.icon(onPressed:restoreDrive,icon:const Icon(Icons.cloud_download),label:const Text('從Drive還原'))),
        ]),
      ]))),
      const SizedBox(height:16),
      const Text('工時與顯示',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
      Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(children:[
        Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[const Text('承上餘額'),SizedBox(width:100,child:TextField(controller:TextEditingController(text:carry.toString()),keyboardType:TextInputType.number,onSubmitted:(v){setState((){carry=double.tryParse(v)??carry;}); save();},decoration:const InputDecoration(suffixText:'h',border:OutlineInputBorder())))]),
      ]))),
      const SizedBox(height:16),
      Row(children:[const Text('自定班次 (可選顏色)',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),const Spacer(),TextButton(onPressed:(){},child:Text('顯示全部 ${defs.length}個'))]),
      Card(child:Column(children:[
       ...defs.entries.map((e){
          var d=e.value;
          return ListTile(leading:CircleAvatar(backgroundColor:d.color,child:Text(d.code,style:const TextStyle(color:Colors.white,fontSize:12))),title:Text('${d.code} - ${d.label} ${d.hours}h'),subtitle:Text('${d.start}-${d.end} 津貼\$${d.allowance} OT${d.ot}h'),trailing:Row(mainAxisSize:MainAxisSize.min,children:[
            IconButton(icon:const Icon(Icons.edit),onPressed:(){editShift(d);}),
            IconButton(icon:const Icon(Icons.delete),onPressed:(){setState((){defs.remove(e.key);}); save();}),
          ]));
        }),
        ListTile(leading:const Icon(Icons.add),title:const Text('新增自定班次'),onTap:(){editShift(null);}),
      ])),
      const SizedBox(height:16),
      const Text('津貼設定',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
      Card(child:Column(children:defs.entries.map((e){
        var d=e.value;
        return ListTile(title:Text('${d.code} 津貼'),subtitle:Slider(value:d.allowance.clamp(0,200),min:0,max:200,divisions:20,label:'\$${d.allowance.round()}',onChanged:(v){setState((){d.allowance=v;}); save();}),trailing:Text('\$${d.allowance.toStringAsFixed(0)}'));
      }).toList())),
      const SizedBox(height:16),
      const Text('輪班模式',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
      Card(child:ListTile(title:Text('sst ${pattern.length}行'),subtitle:Text('${pattern.length}行模式'),trailing:Row(mainAxisSize:MainAxisSize.min,children:[IconButton(icon:const Icon(Icons.edit),onPressed:(){setState((){tab=1;});}),IconButton(icon:const Icon(Icons.delete),onPressed:(){setState((){pattern.clear(); pattern.add(List.filled(7,'O'));}); save();})]))),
      FilledButton.icon(onPressed:(){setState((){pattern.add(List.filled(7,'O'));}); save();},icon:const Icon(Icons.add),label:const Text('新增 7 x 自定行數')),
      const SizedBox(height:8),
      FilledButton.icon(onPressed:(){showAutoApplyDialog();},icon:const Icon(Icons.play_arrow),label:const Text('按指定日期自動排班 (套用排更)'),style: FilledButton.styleFrom(minimumSize:const Size(double.infinity,50))),
      const SizedBox(height:16),
      Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('專屬排更日曆 (可自定名稱，不與私人混亂)',style:TextStyle(fontWeight:FontWeight.bold)),
        TextField(decoration:InputDecoration(labelText:'日曆名稱',hintText:customName),onSubmitted:(v){setState((){customName=v.isEmpty?'我的排更':v;}); save();}),
        const SizedBox(height:8),
        Text('名稱顯示根據班次代碼: ${defs.keys.join(', ')}',style:const TextStyle(fontSize:12)),
        const SizedBox(height:8),
        FilledButton.icon(onPressed:createCal,icon:const Icon(Icons.calendar_month),label:Text('建立/同步到「$customName」')),
        FilledButton.icon(onPressed:exportICS,icon:const Icon(Icons.file_download),label:const Text('匯出.ics')),
      ]))),
    ]);
  }

  void editShift(ShiftDef? oldDef){
    var codeCtrl=TextEditingController(text:oldDef?.code??'');
    var labelCtrl=TextEditingController(text:oldDef?.label??'');
    var hoursCtrl=TextEditingController(text:oldDef?.hours.toString()??'8');
    var allowCtrl=TextEditingController(text:oldDef?.allowance.toString()??'0');
    var otCtrl=TextEditingController(text:oldDef?.ot.toString()??'0');
    var startCtrl=TextEditingController(text:oldDef?.start??'08:00');
    var endCtrl=TextEditingController(text:oldDef?.end??'16:00');
    Color col=oldDef?.color??Colors.orange;
    showDialog(context:context,builder:(ctx){
      return StatefulBuilder(builder:(ctx2,setD){
        return AlertDialog(title:Text(oldDef==null?'新增自定班次':'編輯 ${oldDef.code}'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
          TextField(controller:codeCtrl,decoration:const InputDecoration(labelText:'代碼 (無限制長度，如 早收)')),
          TextField(controller:labelCtrl,decoration:const InputDecoration(labelText:'內容')),
          Row(children:[
            Expanded(child:TextField(controller:hoursCtrl,decoration:const InputDecoration(labelText:'工時'),keyboardType:TextInputType.number)),
            const SizedBox(width:8),
            Expanded(child:TextField(controller:allowCtrl,decoration:const InputDecoration(labelText:'津貼 \$'),keyboardType:TextInputType.number)),
          ]),
          Row(children:[
            Expanded(child:TextField(controller:otCtrl,decoration:const InputDecoration(labelText:'OT h'),keyboardType:TextInputType.number)),
            const SizedBox(width:8),
            Expanded(child:TextField(controller:startCtrl,decoration:const InputDecoration(labelText:'開始時間'))),
          ]),
          TextField(controller:endCtrl,decoration:const InputDecoration(labelText:'結束時間')),
          const SizedBox(height:8),
          Wrap(spacing:6,children:[Colors.orange,Colors.blue,Colors.indigo,Colors.purple,Colors.green,Colors.brown,Colors.red,Colors.teal].map((c)=>GestureDetector(onTap:(){setD(()=>col=c);},child:CircleAvatar(backgroundColor:c,radius:16,child:col==c?const Icon(Icons.check,size:16,color:Colors.white):null))).toList()),
        ])),actions:[
          TextButton(onPressed:(){Navigator.pop(ctx2);},child:const Text('取消')),
          FilledButton(onPressed:(){
            String code=codeCtrl.text.trim(); if(code.isEmpty) return;
            setState((){
              if(oldDef!=null && oldDef.code!=code){defs.remove(oldDef.code);}
              defs[code]=ShiftDef(code,labelCtrl.text,double.tryParse(hoursCtrl.text)??8,col,allowance:double.tryParse(allowCtrl.text)??0,ot:double.tryParse(otCtrl.text)??0,start:startCtrl.text,end:endCtrl.text);
            });
            save(); Navigator.pop(ctx2);
          },child:const Text('儲存')),
        ]);
      });
    });
  }

  Future<void> backupLocal() async{var dir=await getApplicationDocumentsDirectory(); var f=File('${dir.path}/roster_backup.json'); await f.writeAsString(jsonEncode({'roster':roster,'note':rosterNote,'ot':rosterOT,'defs':defs.map((k,v)=>MapEntry(k,v.toJson())),'pattern':pattern})); if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('已備份 ${f.path}')));}
  Future<void> restoreLocal() async{var res=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['json']); if(res==null) return; String c=await File(res.files.single.path!).readAsString(); var j=jsonDecode(c); setState((){if(j['roster']!=null) roster=Map<String,String>.from(j['roster']); if(j['note']!=null) rosterNote=Map<String,String>.from(j['note']); if(j['ot']!=null) rosterOT=(j['ot'] as Map).map<String,double>((k,v)=>MapEntry(k,(v as num).toDouble())); if(j['defs']!=null){defs=(j['defs'] as Map).map<String,ShiftDef>((k,v)=>MapEntry(k,ShiftDef.fromJson(Map<String,dynamic>.from(v))));} if(j['pattern']!=null){pattern=(j['pattern'] as List).map<List<String>>((r)=>(r as List).map<String>((e)=>e.toString()).toList()).toList();}}); save();}
  Future<void> backupDrive() async{try{var acc=await gSign.signIn(); if(acc==null) return; var client=await gSign.authenticatedClient(); var api=drive.DriveApi(client!); var file=drive.File()..name='roster_pro_v6.22.json'; var data=jsonEncode({'roster':roster,'note':rosterNote,'ot':rosterOT,'defs':defs.map((k,v)=>MapEntry(k,v.toJson())),'pattern':pattern}); await api.files.create(file,uploadMedia:drive.Media(Stream.value(utf8.encode(data)), utf8.encode(data).length)); if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('已備份到Drive')));}catch(e){if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('失敗 $e')));}}
  Future<void> restoreDrive() async{try{var acc=await gSign.signIn(); if(acc==null) return; var client=await gSign.authenticatedClient(); var api=drive.DriveApi(client!); var list=await api.files.list(q:"name contains 'roster_pro'",orderBy:'createdTime desc'); var id=list.files!.first.id!; var media=await api.files.get(id,downloadOptions:drive.DownloadOptions.fullMedia) as drive.Media; String s=await utf8.decodeStream(media.stream); var j=jsonDecode(s); setState((){if(j['roster']!=null) roster=Map<String,String>.from(j['roster']); if(j['note']!=null) rosterNote=Map<String,String>.from(j['note']); if(j['ot']!=null) rosterOT=(j['ot'] as Map).map<String,double>((k,v)=>MapEntry(k,(v as num).toDouble()));}); save();}catch(e){if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('失敗 $e')));}}
  Future<void> createCal() async{try{var client=await gSign.authenticatedClient(); if(client==null){var acc=await gSign.signIn(); client=await gSign.authenticatedClient();} var api=cal.CalendarApi(client!); var list=await api.calendarList.list(); var exist=list.items?.where((c)=>c.summary==customName).toList(); String cid; if(exist!=null&&exist.isNotEmpty){cid=exist.first.id!;} else{var nc=cal.Calendar()..summary=customName..timeZone='Asia/Hong_Kong'; var cr=await api.calendars.insert(nc); cid=cr.id!;} calId=cid; await save(); for(var e in roster.entries){DateTime d=DateFormat('yyyy-MM-dd').parse(e.key); if(d.month!=focused.month) continue; var ev=cal.Event()..summary=e.value..description='${defs[e.value]?.label??''} ${rosterNote[e.key]??''}'..start=(cal.EventDateTime()..date=DateTime(d.year,d.month,d.day))..end=(cal.EventDateTime()..date=DateTime(d.year,d.month,d.day+1)); await api.events.insert(ev,cid);} if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('已同步到專屬日曆「$customName」 唔會同原有混亂')));}catch(e){if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('失敗 $e')));}}
  Future<void> exportICS() async{StringBuffer ics=StringBuffer('BEGIN:VCALENDAR\nVERSION:2.0\n'); roster.forEach((k,v){try{DateTime d=DateFormat('yyyy-MM-dd').parse(k); String dt=DateFormat('yyyyMMdd').format(d); String dt2=DateFormat('yyyyMMdd').format(d.add(const Duration(days:1))); ics.writeln('BEGIN:VEVENT\nDTSTART;VALUE=DATE:$dt\nDTEND;VALUE=DATE:$dt2\nSUMMARY:$v\nDESCRIPTION:${rosterNote[k]??''}\nEND:VEVENT');}catch(_){}}); ics.writeln('END:VCALENDAR'); var dir=await getApplicationDocumentsDirectory(); var f=File('${dir.path}/$customName.ics'); await f.writeAsString(ics.toString()); if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('已匯出 ${f.path}')));}

  @override
  Widget build(BuildContext context){
    return Scaffold(
      body:[calTab(),patternTab(),reportTab(),settingsTab()][tab],
      bottomNavigationBar:NavigationBar(selectedIndex:tab,onDestinationSelected:(i){setState((){tab=i;});},destinations:const[
        NavigationDestination(icon:Icon(Icons.calendar_month),label:'月曆'),
        NavigationDestination(icon:Icon(Icons.pattern),label:'模式'),
        NavigationDestination(icon:Icon(Icons.bar_chart),label:'報表'),
        NavigationDestination(icon:Icon(Icons.settings),label:'設定'),
      ]),
    );
  }
}
