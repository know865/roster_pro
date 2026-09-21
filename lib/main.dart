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
    return MaterialApp(title:'Roster Pro v6.23',theme:ThemeData(useMaterial3:true,colorSchemeSeed:Colors.deepPurple),home:const MainPage());
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
    '中':ShiftDef('中','中更',8,Colors.blue,start:"14:00",end:"22:00"),
    '宵':ShiftDef('宵','宵更',8,Colors.purple,allowance:60,start:"22:00",end:"06:00"),
    'OT':ShiftDef('OT','加班',0,Colors.brown,ot:2),
    'O':ShiftDef('O','休',0,Colors.green),
    '早收':ShiftDef('早收','早收長代號',8,Colors.orange,start:"07:00",end:"15:30"),
  };
  List<List<String>> pattern=[["早","早","中","中","宵","宵","O"],["早","早","早","中","中","O","O"]];
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
        Text('${focused.year}年${focused.month}月',style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
        const Spacer(),
        IconButton(icon:const Icon(Icons.chevron_left),onPressed:(){setState((){focused=DateTime(focused.year,focused.month-1,1);}); save();}),
        IconButton(icon:const Icon(Icons.chevron_right),onPressed:(){setState((){focused=DateTime(focused.year,focused.month+1,1);}); save();}),
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
        return GestureDetector(onTap:(){setState((){selectedDay=day;}); showDayDetail(day);},child:Container(decoration:BoxDecoration(color:bg,borderRadius:BorderRadius.circular(16),border:isSelected?Border.all(color:Colors.black,width:2):null),child:Stack(children:[
          if(weekLabel.isNotEmpty) Positioned(left:6,top:4,child:Text(weekLabel,style:TextStyle(fontSize:9,color:Colors.brown.shade400,fontWeight:FontWeight.bold))),
          Center(child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
            Text('${day.day}',style:TextStyle(fontSize:16,fontWeight:FontWeight.bold,color:inMonth?Colors.black:Colors.grey)),
            const SizedBox(height:4),
            if(code!=null) Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:2),decoration:BoxDecoration(color:def?.color??Colors.orange,borderRadius:BorderRadius.circular(10)),child:FittedBox(fit:BoxFit.scaleDown,child:Text(code,style:const TextStyle(fontSize:12,color:Colors.white,fontWeight:FontWeight.bold)))),
            if(hol) Text(hols[DateFormat('MM-dd').format(day)]!,style:const TextStyle(fontSize:9,color:Colors.red)),
          ])),
        ])));
      })),
      Container(padding:const EdgeInsets.fromLTRB(16,12,16,12),decoration:BoxDecoration(color:Colors.white,border:Border(top:BorderSide(color:Colors.grey.shade200))),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[
          Expanded(child:Text('${DateFormat('MM/dd EEE','en').format(selectedDay)} ${hols[DateFormat('MM-dd').format(selectedDay)]??''} ${selCode??''}'.trim(),style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold))),
          FilledButton.icon(onPressed:(){showDayDetail(selectedDay);},style: FilledButton.styleFrom(backgroundColor:Colors.deepPurple,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(20))),icon:const Icon(Icons.edit,size:16),label:const Text('編輯')),
        ]),
        if(selDef!=null) Text('${selDef.label} ${selDef.start}-${selDef.end} 工時${selDef.hours}h',style:TextStyle(color:Colors.grey.shade600,fontSize:13)),
        const SizedBox(height:8),
        Container(padding:const EdgeInsets.all(12),decoration:BoxDecoration(border:Border.all(color:Colors.blue.shade300),borderRadius:BorderRadius.circular(16)),child:Text(rosterNote[selKey]??'無記事',style:const TextStyle(fontSize:14))),
      ])),
      Padding(padding:const EdgeInsets.all(8),child:Card(child:ListTile(dense:true,title:Text('承上 $carry h + 本月 ${rep['hrs']}h = 餘額 ${rep['bal']}h | OT ${rep['ot']}h'),subtitle:Text('津貼 \$${rep['allow']}')))),
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
        return Padding(padding:EdgeInsets.only(bottom:MediaQuery.of(ctx2).viewInsets.bottom),child:Container(padding:const EdgeInsets.all(16),child:Column(mainAxisSize:MainAxisSize.min,children:[
          Text('${DateFormat('yyyy-MM-dd EEE','zh').format(day)}',style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
          Wrap(spacing:6,children:defs.keys.map((c){var d=defs[c]!; return ChoiceChip(label:Text(c),selected:selected==c,selectedColor:d.color.withOpacity(0.4),onSelected:(_){setM((){selected=c;});});}).toList()),
          Row(children:[
            Expanded(child:TextField(controller:otCtrl,decoration:const InputDecoration(labelText:'額外OT'),keyboardType:TextInputType.number)),
            const SizedBox(width:8),
            Expanded(child:TextField(controller:noteCtrl,decoration:const InputDecoration(labelText:'記事'),)),
          ]),
          Row(children:[
            Expanded(child:OutlinedButton(onPressed:(){Navigator.pop(ctx2);},child:const Text('取消'))),
            const SizedBox(width:8),
            Expanded(child:FilledButton(onPressed:(){
              setState((){
                if(selected!=''){roster[k]=selected; rosterNote[k]=noteCtrl.text; double ex=double.tryParse(otCtrl.text)??0; if(ex>0) rosterOT[k]=ex; selectedDay=day;}
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
    showDialog(context:context,builder:(c)=>AlertDialog(title:const Text('修改承上'),content:TextField(controller:ctrl,keyboardType:TextInputType.number),actions:[FilledButton(onPressed:(){setState((){carry=double.tryParse(ctrl.text)??carry;}); save(); Navigator.pop(c);},child:const Text('儲存'))]));
  }

  Widget patternTab(){
    return Column(children:[
      AppBar(title:const Text('排更模式 7天 x 自定行數'),actions:[IconButton(icon:const Icon(Icons.play_arrow),onPressed:(){showAutoApplyDialog();})]),
      Padding(padding:const EdgeInsets.all(8),child:Row(children:[const Text('行數: '),Text('${pattern.length}'),const Spacer(),FilledButton.tonal(onPressed:(){setState((){if(pattern.length>1) pattern.removeLast();}); save();},child:const Text('減一行')),const SizedBox(width:8),FilledButton.tonal(onPressed:(){setState((){pattern.add(List.filled(7,'O'));}); save();},child:const Text('加一行'))])),
      Expanded(child:ListView.builder(itemCount:pattern.length,itemBuilder:(ctx,row){
        return Row(children:[
          SizedBox(width:30,child:Text('${row+1}',textAlign:TextAlign.center)),
          Expanded(child:Row(children:List.generate(7,(col){
            String code=pattern[row][col];
            var def=defs[code];
            return Expanded(child:GestureDetector(onTap:(){pickPatternCell(row,col);},child:Container(margin:const EdgeInsets.all(2),height:48,decoration:BoxDecoration(color:def!=null?def.color.withOpacity(0.3):Colors.white,borderRadius:BorderRadius.circular(8),border:Border.all(color:Colors.grey.shade300)),child:Center(child:FittedBox(child:Text(code,style:const TextStyle(fontWeight:FontWeight.bold)))))));
          }))),
          IconButton(icon:const Icon(Icons.delete_outline,size:18),onPressed:(){setState((){pattern.removeAt(row);}); save();}),
        ]);
      })),
      Padding(padding:const EdgeInsets.all(12),child:FilledButton.icon(onPressed:(){showAutoApplyDialog();},icon:const Icon(Icons.play_arrow),label:const Text('按指定日期自動排班 (套用排更)'),style: FilledButton.styleFrom(minimumSize:const Size(double.infinity,50)))),
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
        return AlertDialog(title:const Text('自動排更'),content:Column(mainAxisSize:MainAxisSize.min,children:[
          ListTile(title:Text('開始: ${DateFormat('yyyy-MM-dd').format(start)}'),trailing:const Icon(Icons.calendar_today),onTap:() async{var d=await showDatePicker(context:ctx2,initialDate:start,firstDate:DateTime(2024),lastDate:DateTime(2028)); if(d!=null) setD(()=>start=d);}),
          ListTile(title:Text('結束: ${DateFormat('yyyy-MM-dd').format(end)}'),trailing:const Icon(Icons.calendar_today),onTap:() async{var d=await showDatePicker(context:ctx2,initialDate:end,firstDate:DateTime(2024),lastDate:DateTime(2028)); if(d!=null) setD(()=>end=d);}),
        ]),actions:[
          TextButton(onPressed:(){Navigator.pop(ctx2);},child:const Text('取消')),
          FilledButton(onPressed:(){
            int totalDays=end.difference(start).inDays+1;
            List<String> flat=pattern.expand((row)=>row).toList();
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
        const Text('本月班次統計',style:TextStyle(fontWeight:FontWeight.bold,fontSize:16)),
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
        const Text('本月工時統計',style:TextStyle(fontWeight:FontWeight.bold,fontSize:16)),
        const SizedBox(height:10),
        Row(children:[
          Expanded(child:Container(padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(12)),child:Column(children:[const Text('總工時'),Text('${totalHrs.toStringAsFixed(1)}h',style:const TextStyle(fontSize:22,fontWeight:FontWeight.bold,color:Colors.blue))]))),
          const SizedBox(width:8),
          Expanded(child:Container(padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(12)),child:Column(children:[const Text('餘額'),Text('${rep['bal'].toStringAsFixed(1)}h',style:const TextStyle(fontSize:22,fontWeight:FontWeight.bold))]))),
        ]),
      ]))),
      Card(color:const Color(0xFFE8F5E9),child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('本月津貼統計',style:TextStyle(fontWeight:FontWeight.bold,fontSize:16)),
        const SizedBox(height:10),
        Container(padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(12)),child:Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[const Text('津貼總額'),Text('\$${totalAllow.toStringAsFixed(0)}',style:const TextStyle(fontSize:22,fontWeight:FontWeight.bold,color:Colors.green))])),
        const SizedBox(height:8),
       ...allowPerCode.entries.where((e)=>e.value>0).map((e)=>Padding(padding:const EdgeInsets.symmetric(vertical:2),child:Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Text('${e.key} 津貼'),Text('\$${e.value.toStringAsFixed(0)}')]))),
      ]))),
      Card(color:const Color(0xFFFCE4EC),child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('超時工作統計',style:TextStyle(fontWeight:FontWeight.bold,fontSize:16)),
        const SizedBox(height:10),
        Row(children:[
          Expanded(child:Container(padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(12)),child:Column(children:[const Text('班次OT'),Text('${totalOT.toStringAsFixed(1)}h')]))),
          const SizedBox(width:8),
          Expanded(child:Container(padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(12)),child:Column(children:[const Text('額外OT'),Text('${totalExtraOT.toStringAsFixed(1)}h')]))),
          const SizedBox(width:8),
          Expanded(child:Container(padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:Colors.red.shade50,borderRadius:BorderRadius.circular(12)),child:Column(children:[const Text('總計'),Text('${allOT.toStringAsFixed(1)}h',style:const TextStyle(color:Colors.red,fontWeight:FontWeight.bold))]))),
        ]),
      ]))),
    ]);
  }

  Widget settingsTab(){
    return ListView(padding:const EdgeInsets.all(16),children:[
      const Text('自定班次內容編輯和刪除',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
      Card(child:Column(children:[
       ...defs.entries.map((e){
          var d=e.value;
          return ListTile(leading:CircleAvatar(backgroundColor:d.color,radius:14,child:Text(d.code,style:const TextStyle(color:Colors.white,fontSize:11))),title:Text('${d.code} - ${d.label}'),subtitle:Text('${d.start}-${d.end} ${d.hours}h 津貼\$${d.allowance} OT${d.ot}h'),trailing:Row(mainAxisSize:MainAxisSize.min,children:[
            IconButton(icon:const Icon(Icons.edit,size:18),onPressed:(){editShift(d);}),
            IconButton(icon:const Icon(Icons.delete,size:18),onPressed:(){setState((){defs.remove(e.key);}); save();}),
          ]));
        }),
        ListTile(leading:const Icon(Icons.add),title:const Text('新增自定班次'),onTap:(){editShift(null);}),
      ])),
      const SizedBox(height:16),
      const Text('自定津貼編輯和刪除',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
      Card(child:Column(children:defs.entries.map((e){
        var d=e.value;
        return ListTile(title:Text('${d.code} 津貼'),subtitle:Slider(value:d.allowance.clamp(0,200),min:0,max:200,divisions:20,label:'\$${d.allowance.round()}',onChanged:(v){setState((){d.allowance=v;}); save();}),trailing:Text('\$${d.allowance.toStringAsFixed(0)}'));
      }).toList())),
      const SizedBox(height:16),
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
      Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('專屬排更日曆 (可自定名稱，不與私人混亂)',style:TextStyle(fontWeight:FontWeight.bold)),
        TextField(decoration:InputDecoration(labelText:'日曆名稱',hintText:customName),onSubmitted:(v){setState((){customName=v.isEmpty?'我的排更':v;}); save();}),
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
          TextField(controller:codeCtrl,decoration:const InputDecoration(labelText:'代碼 (如 早收)')),
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
          Wrap(spacing:6,children:[Colors.orange,Colors.blue,Colors.purple,Colors.green,Colors.brown,Colors.red,Colors.teal].map((c)=>GestureDetector(onTap:(){setD(()=>col=c);},child:CircleAvatar(backgroundColor:c,radius:16,child:col==c?const Icon(Icons.check,size:16,color:Colors.white):null))).toList()),
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

  Future<void> backupLocal() async{
    var dir=await getApplicationDocumentsDirectory();
    var f=File('${dir.path}/roster_backup.json');
    await f.writeAsString(jsonEncode({
      'roster':roster,
      'note':rosterNote,
      'ot':rosterOT,
      'defs':defs.map((k,v)=>MapEntry(k,v.toJson())),
      'pattern':pattern
    }));
    if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('已備份 ${f.path}')));
  }

  Future<void> restoreLocal() async{
    var res=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['json']);
    if(res==null) return;
    String c=await File(res.files.single.path!).readAsString();
    var j=jsonDecode(c);
    setState((){
      if(j['roster']!=null) roster=Map<String,String>.from(j['roster']);
      if(j['note']!=null) rosterNote=Map<String,String>.from(j['note']);
      if(j['ot']!=null) rosterOT=(j['ot'] as Map).map<String,double>((k,v)=>MapEntry(k,(v as num).toDouble()));
      if(j['defs']!=null){defs=(j['defs'] as Map).map<String,ShiftDef>((k,v)=>MapEntry(k,ShiftDef.fromJson(Map<String,dynamic>.from(v))));}
      if(j['pattern']!=null){pattern=(j['pattern'] as List).map<List<String>>((r)=>(r as List).map<String>((e)=>e.toString()).toList()).toList();}
    });
    save();
  }

  Future<void> backupDrive() async{
    try{
      var acc=await gSign.signIn(); if(acc==null) return;
      var client=await gSign.authenticatedClient();
      var api=drive.DriveApi(client!);
      var file=drive.File()..name='roster_pro_v6.23.json';
      var data=jsonEncode({'roster':roster,'note':rosterNote,'ot':rosterOT});
      await api.files.create(file,uploadMedia:drive.Media(Stream.value(utf8.encode(data)), utf8.encode(data).length));
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('已備份到Drive')));
    }catch(e){
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('失敗 $e')));
    }
  }

  Future<void> restoreDrive() async{
    try{
      var acc=await gSign.signIn(); if(acc==null) return;
      var client=await gSign.authenticatedClient();
      var api=drive.DriveApi(client!);
      var list=await api.files.list(q:"name contains 'roster_pro'",orderBy:'createdTime desc');
      var id=list.files!.first.id!;
      var media=await api.files.get(id,downloadOptions:drive.DownloadOptions.fullMedia) as drive.Media;
      String s=await utf8.decodeStream(media.stream);
      var j=jsonDecode(s);
      setState((){roster=Map<String,String>.from(j['roster']??j);});
      save();
    }catch(e){
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('失敗 $e')));
    }
  }

  Future<void> createCal() async{
    try{
      var client=await gSign.authenticatedClient();
      if(client==null){var acc=await gSign.signIn(); client=await gSign.authenticatedClient();}
      var api=cal.CalendarApi(client!);
      var list=await api.calendarList.list();
      var exist=list.items?.where((c)=>c.summary==customName).toList();
      String cid;
      if(exist!=null&&exist.isNotEmpty){cid=exist.first.id!;}
      else{var nc=cal.Calendar()..summary=customName..timeZone='Asia/Hong_Kong'; var cr=await api.calendars.insert(nc); cid=cr.id!;}
      calId=cid; await save();
      for(var e in roster.entries){
        DateTime d=DateFormat('yyyy-MM-dd').parse(e.key);
        if(d.month!=focused.month) continue;
        var ev=cal.Event()
         ..summary=e.value
         ..description='${defs[e.value]?.label??''} ${rosterNote[e.key]??''} OT:${rosterOT[e.key]??0}'
         ..start=(cal.EventDateTime()..date=DateTime(d.year,d.month,d.day))
         ..end=(cal.EventDateTime()..date=DateTime(d.year,d.month,d.day+1));
        await api.events.insert(ev,cid);
      }
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('已同步到 $customName')));
    }catch(e){
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('失敗 $e')));
    }
  }

  Future<void> exportICS() async{
    StringBuffer ics=StringBuffer('BEGIN:VCALENDAR\nVERSION:2.0\n');
    roster.forEach((k,v){
      try{
        DateTime d=DateFormat('yyyy-MM-dd').parse(k);
        String dt=DateFormat('yyyyMMdd').format(d);
        String dt2=DateFormat('yyyyMMdd').format(d.add(const Duration(days:1)));
        ics.writeln('BEGIN:VEVENT\nDTSTART;VALUE=DATE:$dt\nDTEND;VALUE=DATE:$dt2\nSUMMARY:$v\nDESCRIPTION:${rosterNote[k]??''}\nEND:VEVENT');
      }catch(_){}
    });
    ics.writeln('END:VCALENDAR');
    var dir=await getApplicationDocumentsDirectory();
    var f=File('${dir.path}/$customName.ics');
    await f.writeAsString(ics.toString());
    if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('已匯出 ${f.path}')));
  }

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
