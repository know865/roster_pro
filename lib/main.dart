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
    return MaterialApp(title:'Roster Pro v6.20',theme:ThemeData(useMaterial3:true,colorSchemeSeed:Colors.deepPurple),home:const MainPage());
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
  Map<String,String> roster={};
  Map<String,String> rosterNote={};
  Map<String,double> rosterOT={};
  Map<String,ShiftDef> defs={
    '早':ShiftDef('早','早班 08-16',8,Colors.orange,start:"08:00",end:"16:00"),
    '中':ShiftDef('中','中班 16-00',8,Colors.blue,start:"16:00",end:"00:00"),
    '宵':ShiftDef('宵','宵班 00-08',8,Colors.purple,allowance:60,start:"00:00",end:"08:00"),
    'OT':ShiftDef('OT','加班',0,Colors.brown,ot:2,start:"",end:""),
    'O':ShiftDef('O','休',0,Colors.green,start:"",end:""),
    '早收':ShiftDef('早收','早收長代號',8,Colors.orange,start:"08:00",end:"15:00"),
  };
  List<List<String>> pattern=[["早","早","中","中","宵","宵","O"],["早","早","早","中","中","O","O"]];
  String customName='我的排更';
  String? calId;
  double carry=-42;
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
      carry=sp.getDouble('carry')??-42;
      var fm=sp.getString('focused'); if(fm!=null){try{focused=DateTime.parse(fm);}catch(_){}}
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
    return Column(children:[
      AppBar(title:Text('${focused.year}年${focused.month}月'),actions:[
        IconButton(tooltip:'返回今天',icon:const Icon(Icons.my_location),onPressed:(){setState((){focused=DateTime.now();}); save();}),
        IconButton(icon:const Icon(Icons.chevron_left),onPressed:(){setState((){focused=DateTime(focused.year,focused.month-1,1);}); save();}),
        IconButton(icon:const Icon(Icons.chevron_right),onPressed:(){setState((){focused=DateTime(focused.year,focused.month+1,1);}); save();}),
      ]),
      Container(color:Colors.grey.shade200,padding:const EdgeInsets.symmetric(vertical:6),child:Row(children: const[
        SizedBox(width:36,child:Text('Wk',textAlign:TextAlign.center,style:TextStyle(fontWeight:FontWeight.bold))),
        Expanded(child:Row(mainAxisAlignment:MainAxisAlignment.spaceAround,children:[Text('一'),Text('二'),Text('三'),Text('四'),Text('五'),Text('六'),Text('日')])),
      ])),
      Expanded(child:ListView.builder(itemCount:6,itemBuilder:(ctx,weekIdx){
        DateTime weekStart=days[weekIdx*7];
        int wk=isoWeekNumber(weekStart);
        return Row(children:[
          SizedBox(width:36,child:Container(margin:const EdgeInsets.all(2),padding:const EdgeInsets.symmetric(vertical:18),decoration:BoxDecoration(color:Colors.deepPurple.shade50,borderRadius:BorderRadius.circular(8)),child:Text('W$wk',textAlign:TextAlign.center,style:const TextStyle(fontSize:11,fontWeight:FontWeight.bold)))),
          Expanded(child:Row(children:List.generate(7,(dIdx){
            DateTime day=days[weekIdx*7+dIdx];
            bool inMonth=day.month==focused.month;
            String k=DateFormat('yyyy-MM-dd').format(day);
            String? code=roster[k];
            var def=code!=null?defs[code]:null;
            bool isToday=DateFormat('yyyy-MM-dd').format(day)==DateFormat('yyyy-MM-dd').format(DateTime.now());
            bool hol=hols.containsKey(DateFormat('MM-dd').format(day));
            return Expanded(child:GestureDetector(
              onTap:(){showDayDetail(day);},
              child:Container(
                height:72,
                margin:const EdgeInsets.all(2),
                padding:const EdgeInsets.all(3),
                decoration:BoxDecoration(color:isToday?Colors.yellow.shade200:def!=null?def.color.withOpacity(0.25):inMonth?const Color(0xFFF2F4E8):Colors.grey.shade100,borderRadius:BorderRadius.circular(10),border:isToday?Border.all(color:Colors.deepPurple,width:1.5):null),
                child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                  Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
                    Text('${day.day}',style:TextStyle(fontSize:12,fontWeight:FontWeight.bold,color:hol?Colors.red:inMonth?Colors.black54:Colors.grey)),
                    if(rosterOT[k]!=null&&rosterOT[k]! >0) const Icon(Icons.access_time,size:10,color:Colors.red),
                  ]),
                  if(hol) Text(hols[DateFormat('MM-dd').format(day)]!,style:const TextStyle(fontSize:8,color:Colors.red)),
                  if(code!=null) Container(
                    margin:const EdgeInsets.only(top:1),
                    padding:const EdgeInsets.symmetric(horizontal:4,vertical:1),
                    decoration:BoxDecoration(color:def?.color??Colors.orange,borderRadius:BorderRadius.circular(6)),
                    child:FittedBox(fit:BoxFit.scaleDown,child:Text(code,style:const TextStyle(fontSize:11,color:Colors.white,fontWeight:FontWeight.bold))),
                  ),
                  if(rosterNote[k]!=null&&rosterNote[k]!.isNotEmpty) const Icon(Icons.note_alt,size:10,color:Colors.grey),
                ]),
              ),
            ));
          }))),
        ]);
      })),
      Padding(padding:const EdgeInsets.all(8),child:Card(child:ListTile(dense:true,title:Text('承上 $carry h + 本月 ${rep['hrs']}h = 餘額 ${rep['bal']}h | OT ${rep['ot']}h'),subtitle:Text('津貼 \$${rep['allow']}'),trailing:IconButton(icon:const Icon(Icons.edit),onPressed:(){editCarry();})))),
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
          const Text('班次',style:TextStyle(fontWeight:FontWeight.bold)),
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
            Expanded(child:TextField(controller:noteCtrl,decoration:const InputDecoration(labelText:'記事',border:OutlineInputBorder(),hintText:'例如: 10:00 開會'),)),
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
      AppBar(title:const Text('排更模式 7天 x 行數'),actions:[
        IconButton(icon:const Icon(Icons.add),onPressed:(){setState((){pattern.add(List.filled(7,'O'));}); save();}),
        IconButton(icon:const Icon(Icons.play_arrow),onPressed:(){showAutoApplyDialog();},tooltip:'自動排更'),
      ]),
      Padding(padding:const EdgeInsets.all(8),child:Row(children:[const Text('行數: '),Text('${pattern.length}'),const Spacer(),FilledButton.tonalIcon(onPressed:(){setState((){if(pattern.length>1) pattern.removeLast();}); save();},icon:const Icon(Icons.remove),label:const Text('減一行')),const SizedBox(width:8),FilledButton.tonalIcon(onPressed:(){setState((){pattern.add(List.filled(7,'O'));}); save();},icon:const Icon(Icons.add),label:const Text('加一行'))])),
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
        const Text('1. 點格子選擇班次，組成循環模式\n2. 按右上角 ▶ 自動排更，選開始/結束日期\n3. 系統會由開始日循環套用此模式'),
      ])))),
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
        return AlertDialog(title:const Text('自動根據模式排更'),content:Column(mainAxisSize:MainAxisSize.min,children:[
          ListTile(title:Text('開始: ${DateFormat('yyyy-MM-dd').format(start)}'),trailing:const Icon(Icons.calendar_today),onTap:() async{var d=await showDatePicker(context:ctx2,initialDate:start,firstDate:DateTime(2024),lastDate:DateTime(2028)); if(d!=null) setD(()=>start=d);}),
          ListTile(title:Text('結束: ${DateFormat('yyyy-MM-dd').format(end)}'),trailing:const Icon(Icons.calendar_today),onTap:() async{var d=await showDatePicker(context:ctx2,initialDate:end,firstDate:DateTime(2024),lastDate:DateTime(2028)); if(d!=null) setD(()=>end=d);}),
          const SizedBox(height:8),
          Text('模式 ${pattern.length}行 x 7天 = ${pattern.length*7}天一循環',style:const TextStyle(fontSize:12)),
        ]),actions:[
          TextButton(onPressed:(){Navigator.pop(ctx2);},child:const Text('取消')),
          FilledButton(onPressed:(){
            int totalDays=end.difference(start).inDays+1;
            int flatIndex=0;
            List<String> flat=pattern.expand((row)=>row).toList();
            if(flat.isEmpty) return;
            setState((){
              for(int i=0;i<totalDays;i++){
                DateTime d=start.add(Duration(days:i));
                String k=DateFormat('yyyy-MM-dd').format(d);
                roster[k]=flat[flatIndex % flat.length];
                flatIndex++;
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
    return ListView(padding:const EdgeInsets.all(12),children:[
      Row(children:[
        Text('${focused.year}年${focused.month}月 報表',style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
        const Spacer(),
        FilledButton.tonal(onPressed:(){setState((){focused=DateTime.now();});},child:const Text('今天')),
      ]),
      const SizedBox(height:12),
      Card(color:const Color(0xFFE0F7FA),child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('本月班次統計',style:TextStyle(fontWeight:FontWeight.bold)),
        const SizedBox(height:8),
        cnt.isEmpty?const Text('暫無'):Wrap(spacing:8,children:cnt.entries.map((e)=>Chip(label:Text('${e.key} x ${e.value}'))).toList()),
        const Divider(),
        const Text('本月津貼統計',style:TextStyle(fontWeight:FontWeight.bold)),
        Text('OT 總計: ${rep['ot']}h\n津貼總計: \$${rep['allow']}\n總工時: ${rep['hrs']}h\n餘額: ${rep['bal']}h (承上 $carry)'),
      ]))),
      const SizedBox(height:12),
      Card(child:ListView.separated(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),itemCount:DateTime(focused.year,focused.month+1,0).day,itemBuilder:(ctx,i){
        DateTime d=DateTime(focused.year,focused.month,i+1);
        String k=DateFormat('yyyy-MM-dd').format(d);
        String? code=roster[k]; if(code==null) return const SizedBox.shrink();
        var def=defs[code];
        return ListTile(dense:true,title:Text('${d.day}日 ${DateFormat('EEE','zh').format(d)} $code'),subtitle:Text('${def?.label??''} ${def?.start??''}-${def?.end??''} ${rosterNote[k]??''} ${rosterOT[k]!=null?'額外OT ${rosterOT[k]}h':''}'),trailing:Text('${def?.hours??0}h'));
      },separatorBuilder:(_,__)=>const Divider(height:1))),
    ]);
  }
  Widget settingsTab(){
    return ListView(padding:const EdgeInsets.all(16),children:[
      const Text('班次自定義 (可新增/編輯/刪除)',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
      Card(child:Column(children:[
       ...defs.entries.map((e){
          var d=e.value;
          return ListTile(leading:CircleAvatar(backgroundColor:d.color,radius:14),title:Text('${d.code} - ${d.label}'),subtitle:Text('工時${d.hours}h 津貼\$${d.allowance} OT${d.ot}h ${d.start}-${d.end}'),trailing:Row(mainAxisSize:MainAxisSize.min,children:[
            IconButton(icon:const Icon(Icons.edit,size:18),onPressed:(){editShift(d);}),
            IconButton(icon:const Icon(Icons.delete,size:18),onPressed:(){setState((){defs.remove(e.key);}); save();}),
          ]));
        }),
        ListTile(leading:const Icon(Icons.add),title:const Text('新增班次'),onTap:(){editShift(null);}),
      ])),
      const SizedBox(height:16),
      const Text('津貼自定義',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
      Card(child:Column(children:defs.entries.map((e){
        var d=e.value;
        return ListTile(title:Text('${d.code} 津貼'),subtitle:Slider(value:d.allowance.clamp(0,200),min:0,max:200,divisions:20,label:'\$${d.allowance.round()}',onChanged:(v){setState((){d.allowance=v;}); save();}),trailing:Text('\$${d.allowance.toStringAsFixed(0)}'));
      }).toList())),
      const SizedBox(height:16),
      const Text('備份與專屬日曆',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
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
        const SizedBox(height:8),
        TextField(decoration:InputDecoration(labelText:'日曆名稱',hintText:customName),onSubmitted:(v){setState((){customName=v.isEmpty?'我的排更':v;}); save();}),
        const SizedBox(height:8),
        Text('顯示名稱根據班次代碼: ${defs.keys.join(', ')}',style:const TextStyle(fontSize:12)),
        const SizedBox(height:8),
        FilledButton.icon(onPressed:createCal,icon:const Icon(Icons.calendar_month),label:Text('建立/同步到「$customName」')),
        const SizedBox(height:8),
        FilledButton.icon(onPressed:exportICS,icon:const Icon(Icons.file_download),label:const Text('匯出.ics')),
        if(calId!=null) Text('ID $calId',style:const TextStyle(fontSize:10)),
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
        return AlertDialog(title:Text(oldDef==null?'新增班次':'編輯 ${oldDef.code}'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
          TextField(controller:codeCtrl,decoration:const InputDecoration(labelText:'代碼 (如 早收) 無限制長度')),
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
            double h=double.tryParse(hoursCtrl.text)??8;
            double al=double.tryParse(allowCtrl.text)??0;
            double ot=double.tryParse(otCtrl.text)??0;
            setState((){
              if(oldDef!=null && oldDef.code!=code){defs.remove(oldDef.code);}
              defs[code]=ShiftDef(code,labelCtrl.text,h,col,allowance:al,ot:ot,start:startCtrl.text,end:endCtrl.text);
            });
            save(); Navigator.pop(ctx2);
          },child:const Text('儲存')),
        ]);
      });
    });
  }
  Future<void> backupLocal() async{var dir=await getApplicationDocumentsDirectory(); var f=File('${dir.path}/roster_backup.json'); await f.writeAsString(jsonEncode({'roster':roster,'note':rosterNote,'ot':rosterOT,'defs':defs.map((k,v)=>MapEntry(k,v.toJson())),'pattern':pattern})); if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('已備份 ${f.path}')));}
  Future<void> restoreLocal() async{var res=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['json']); if(res==null) return; String c=await File(res.files.single.path!).readAsString(); var j=jsonDecode(c); setState((){if(j['roster']!=null) roster=Map<String,String>.from(j['roster']); if(j['note']!=null) rosterNote=Map<String,String>.from(j['note']); if(j['ot']!=null) rosterOT=(j['ot'] as Map).map<String,double>((k,v)=>MapEntry(k,(v as num).toDouble())); if(j['defs']!=null){defs=(j['defs'] as Map).map<String,ShiftDef>((k,v)=>MapEntry(k,ShiftDef.fromJson(Map<String,dynamic>.from(v))));} if(j['pattern']!=null){pattern=(j['pattern'] as List).map<List<String>>((r)=>(r as List).map<String>((e)=>e.toString()).toList()).toList();}}); save();}
  Future<void> backupDrive() async{try{var acc=await gSign.signIn(); if(acc==null) return; var client=await gSign.authenticatedClient(); var api=drive.DriveApi(client!); var file=drive.File()..name='roster_pro_v6.20.json'; var data=jsonEncode({'roster':roster,'note':rosterNote,'ot':rosterOT}); await api.files.create(file,uploadMedia:drive.Media(Stream.value(utf8.encode(data)), utf8.encode(data).length)); if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('已備份到Drive')));}catch(e){if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('失敗 $e')));}}
  Future<void> restoreDrive() async{try{var acc=await gSign.signIn(); if(acc==null) return; var client=await gSign.authenticatedClient(); var api=drive.DriveApi(client!); var list=await api.files.list(q:"name contains 'roster_pro'",orderBy:'createdTime desc'); var id=list.files!.first.id!; var media=await api.files.get(id,downloadOptions:drive.DownloadOptions.fullMedia) as drive.Media; String s=await utf8.decodeStream(media.stream); var j=jsonDecode(s); setState((){roster=Map<String,String>.from(j['roster']??j);}); save();}catch(e){if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('失敗 $e')));}}
  Future<void> createCal() async{try{var client=await gSign.authenticatedClient(); if(client==null){var acc=await gSign.signIn(); client=await gSign.authenticatedClient();} var api=cal.CalendarApi(client!); var list=await api.calendarList.list(); var exist=list.items?.where((c)=>c.summary==customName).toList(); String cid; if(exist!=null&&exist.isNotEmpty){cid=exist.first.id!;} else{var nc=cal.Calendar()..summary=customName..timeZone='Asia/Hong_Kong'; var cr=await api.calendars.insert(nc); cid=cr.id!;} calId=cid; await save(); for(var e in roster.entries){DateTime d=DateFormat('yyyy-MM-dd').parse(e.key); if(d.month!=focused.month) continue; var ev=cal.Event()..summary=e.value..description='${defs[e.value]?.label??''} ${rosterNote[e.key]??''} OT:${rosterOT[e.key]??0}'..start=(cal.EventDateTime()..date=DateTime(d.year,d.month,d.day))..end=(cal.EventDateTime()..date=DateTime(d.year,d.month,d.day+1)); await api.events.insert(ev,cid);} if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('已同步到 $customName')));}catch(e){if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('失敗 $e')));}}
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
