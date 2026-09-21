import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main()=>runApp(MaterialApp(debugShowCheckedModeBanner:false, home:MainPage()));

class Shift{
  String code,name,start,end; int c; double h; bool work;
  Shift(this.code,this.name,this.start,this.end,this.c,this.h,this.work);
  Map toJson()=>{'code':code,'name':name,'start':start,'end':end,'c':c,'h':h,'work':work};
  static Shift fromJson(Map m)=>Shift(m['code'],m['name'],m['start'],m['end'],m['c'],(m['h'] as num).toDouble(),m['work']);
  Color get color=>Color(c);
}
class Allowance{
  String name; String start; double amount; bool enabled;
  Allowance(this.name,this.start,this.amount,this.enabled);
  Map toJson()=>{'name':name,'start':start,'amount':amount,'enabled':enabled};
  static Allowance fromJson(Map m)=>Allowance(m['name'],m['start'],(m['amount'] as num).toDouble(),m['enabled']);
  int get mins{ try{var p=start.split(':'); return int.parse(p[0])*60+int.parse(p[1]);}catch(_){return 0;}}
}
class Pattern{ String name; List<String> codes; Pattern(this.name,this.codes); Map toJson()=>{'name':name,'codes':codes}; static Pattern fromJson(Map m)=>Pattern(m['name'],List<String>.from(m['codes'])); }

class MainPage extends StatefulWidget{ @override State<MainPage> createState()=>_S(); }
class _S extends State<MainPage>{
  int tab=0; Map<String,String> roster={}, notes={}; Map<String,double> extra={};
  List<Shift> shifts=[]; List<Allowance> allowances=[]; List<Pattern> patterns=[];
  DateTime focused=DateTime.now(), selected=DateTime.now(); double otR=100, transB=20, fs=11;
  _S(){
    shifts=[
      Shift('早','早更','07:00','15:30',0xFFFF9800,8,true),
      Shift('中','中更','15:00','23:30',0xFF2196F3,8,true),
      Shift('夜','夜更','23:00','07:30',0xFF3F51B5,8,true),
      Shift('宵','通宵','23:30','08:00',0xFF673AB7,8,true),
      Shift('O','例休','','',0xFF4CAF50,0,false),
      Shift('OT','OT','','',0xFF795548,4,true),
    ];
    allowances=[
      Allowance('早班津貼','06:00',20,true),
      Allowance('中班津貼','14:00',0,true),
      Allowance('夜班津貼','22:00',80,true),
      Allowance('通宵津貼','23:30',120,true),
    ];
  }
  String k(DateTime d)=>DateFormat('yyyy-MM-dd').format(d);
  int isoWeek(DateTime d){ var thu=d.add(Duration(days:4-d.weekday)); var jan1=DateTime(thu.year,1,1); return (thu.difference(jan1).inDays/7).floor()+1; }
  Shift getS(String c){ for(var s in shifts) if(s.code==c) return s; return Shift('','','','',0xFF9E9E9E,0,false); }
  int pMins(String t){ try{var p=t.split(':'); return int.parse(p[0])*60+int.parse(p[1]);}catch(_){return -1;}}
  double allowFor(Shift s){ if(!s.work||s.start=='') return 0; int sm=pMins(s.start); if(sm<0) return 0; Allowance? best; int bd=10000; for(var a in allowances){ if(!a.enabled) continue; int d=sm-a.mins; if(d<0) d+=1440; if(d<bd&&d<720){ bd=d; best=a; } } return best==null?0:best.amount; }
  void save() async{ var p=await SharedPreferences.getInstance(); p.setString('roster',jsonEncode(roster)); p.setString('notes',jsonEncode(notes)); p.setString('extra',jsonEncode(extra)); p.setString('shifts',jsonEncode(shifts.map((e)=>e.toJson()).toList())); p.setString('allowances',jsonEncode(allowances.map((e)=>e.toJson()).toList())); p.setString('patterns',jsonEncode(patterns.map((e)=>e.toJson()).toList())); p.setDouble('otR',otR); p.setDouble('transB',transB); p.setDouble('fs',fs); }
  void load() async{ var p=await SharedPreferences.getInstance(); var r=p.getString('roster'); if(r!=null){ var d=jsonDecode(r); roster=(d as Map).map((kk,v)=>MapEntry(kk.toString(),v.toString())); } var n=p.getString('notes'); if(n!=null){ var d=jsonDecode(n); notes=(d as Map).map((kk,v)=>MapEntry(kk.toString(),v.toString())); } var ex=p.getString('extra'); if(ex!=null){ var d=jsonDecode(ex); extra=(d as Map).map((kk,v)=>MapEntry(kk.toString(),(v as num).toDouble())); } var sh=p.getString('shifts'); if(sh!=null){ var d=jsonDecode(sh) as List; shifts=d.map((e)=>Shift.fromJson(e)).toList(); } var al=p.getString('allowances'); if(al!=null){ var d=jsonDecode(al) as List; allowances=d.map((e)=>Allowance.fromJson(e)).toList(); } var pat=p.getString('patterns'); if(pat!=null){ var d=jsonDecode(pat) as List; patterns=d.map((e)=>Pattern.fromJson(e)).toList(); } setState((){ otR=p.getDouble('otR')??100; transB=p.getDouble('transB')??20; fs=p.getDouble('fs')??11; }); }
  @override void initState(){ super.initState(); load(); }
  List<DateTime> days42(DateTime mon){ var first=DateTime(mon.year,mon.month,1); int off=first.weekday-1; var start=first.subtract(Duration(days:off)); return List.generate(42,(i)=>start.add(Duration(days:i))); }

  void pickYM(){
    int y=focused.year,m=focused.month; var yc=TextEditingController(text:y.toString());
    showDialog(context:context, builder:(ctx)=>StatefulBuilder(builder:(ctx,setM){
      return AlertDialog(title:Text('快速查看指定年月'), content:SizedBox(width:300,height:120, child:Column(children:[
        Row(children:[ IconButton(icon:Icon(Icons.remove), onPressed:(){ setM((){ y-=1; yc.text=y.toString(); }); }), Expanded(child:TextField(controller:yc, textAlign:TextAlign.center)), IconButton(icon:Icon(Icons.add), onPressed:(){ setM((){ y+=1; yc.text=y.toString(); }); }) ]),
        Wrap(spacing:4, children:[ for(int mm=1;mm<=12;mm++) ChoiceChip(label:Text('${mm}月'), selected:m==mm, onSelected:(v){ setM(()=>m=mm); }) ]),
      ])), actions:[ TextButton(onPressed:()=>Navigator.pop(ctx), child:Text('取消')), FilledButton(onPressed:(){ int? yy=int.tryParse(yc.text); if(yy!=null) y=yy; setState(()=>focused=DateTime(y,m,1)); Navigator.pop(ctx); }, child:Text('跳轉')) ]
      );
    }));
  }
  void editCell(DateTime d){
    var noteC=TextEditingController(text:notes[k(d)]??''); var exC=TextEditingController(text:(extra[k(d)]??0).toString()); String cur=roster[k(d)]??'';
    showModalBottomSheet(context:context, isScrollControlled:true, builder:(ctx)=>StatefulBuilder(builder:(ctx,setM){
      return Padding(padding:EdgeInsets.only(bottom:MediaQuery.of(ctx).viewInsets.bottom, left:16,right:16,top:16), child:Column(mainAxisSize:MainAxisSize.min, children:[
        Text(DateFormat('yyyy-MM-dd EEEE').format(d),style:TextStyle(fontWeight:FontWeight.bold)),
        Wrap(spacing:6, children:[ for(var s in shifts) ChoiceChip(label:Text(s.code), selected:cur==s.code, onSelected:(v){ setM(()=>cur=v?s.code:''); }) ]),
        TextField(controller:noteC, decoration:InputDecoration(labelText:'記事')), TextField(controller:exC, decoration:InputDecoration(labelText:'額外OT小時')),
        SizedBox(height:10), FilledButton(onPressed:(){ setState((){ if(cur=='') roster.remove(k(d)); else roster[k(d)]=cur; if(noteC.text=='') notes.remove(k(d)); else notes[k(d)]=noteC.text; var vv=double.tryParse(exC.text); if(vv==null||vv==0) extra.remove(k(d)); else extra[k(d)]=vv; save(); }); Navigator.pop(ctx); }, child:Text('保存')), SizedBox(height:20),
      ]));
    }));
  }
  void editShiftDialog(Shift? old){
    var codeC=TextEditingController(text:old?.code??''); var nameC=TextEditingController(text:old?.name??''); var stC=TextEditingController(text:old?.start??'07:00'); var enC=TextEditingController(text:old?.end??'15:30'); var hC=TextEditingController(text:(old?.h??8).toString()); bool work=old?.work??true;
    showDialog(context:context, builder:(ctx)=>AlertDialog(title:Text(old==null?'新增班次':'編輯班次'), content:Column(mainAxisSize:MainAxisSize.min, children:[ TextField(controller:codeC, decoration:InputDecoration(labelText:'代號')), TextField(controller:nameC, decoration:InputDecoration(labelText:'名稱')), Row(children:[ Expanded(child:TextField(controller:stC)), SizedBox(width:8), Expanded(child:TextField(controller:enC)) ]), TextField(controller:hC), CheckboxListTile(title:Text('有交通'), value:work, onChanged:(v){}) ]), actions:[ TextButton(onPressed:()=>Navigator.pop(ctx), child:Text('取消')), FilledButton(onPressed:(){ if(codeC.text=='') return; setState((){ var ns=Shift(codeC.text, nameC.text==''?codeC.text:nameC.text, stC.text, enC.text, old?.c??0xFFFF9800, double.tryParse(hC.text)??8, work); if(old==null) shifts.add(ns); else { int idx=shifts.indexOf(old); shifts[idx]=ns; } save(); }); Navigator.pop(ctx); }, child:Text('保存')) ]));
  }
  void editAllowDialog(Allowance? old){
    var nC=TextEditingController(text:old?.name??''); var sC=TextEditingController(text:old?.start??'06:00'); var aC=TextEditingController(text:(old?.amount??0).toString()); bool en=old?.enabled??true;
    showDialog(context:context, builder:(ctx)=>StatefulBuilder(builder:(ctx,setM){
      return AlertDialog(title:Text(old==null?'新增津貼':'編輯津貼'), content:Column(mainAxisSize:MainAxisSize.min, children:[
        TextField(controller:nC, decoration:InputDecoration(labelText:'名稱')),
        TextField(controller:sC, decoration:InputDecoration(labelText:'開始時間 HH:MM')),
        TextField(controller:aC, decoration:InputDecoration(labelText:'金額')),
        CheckboxListTile(title:Text('啟用'), value:en, onChanged:(v){ setM(()=>en=v!); }),
      ]), actions:[ TextButton(onPressed:()=>Navigator.pop(ctx), child:Text('取消')), FilledButton(onPressed:(){ if(nC.text=='') return; setState((){ var na=Allowance(nC.text, sC.text, double.tryParse(aC.text)??0, en); if(old==null) allowances.add(na); else { int idx=allowances.indexOf(old); allowances[idx]=na; } save(); }); Navigator.pop(ctx); }, child:Text('保存')) ]
      );
    }));
  }
  void createPattern(){ var nameC=TextEditingController(text:'自定${patterns.length+1}'); var rowC=TextEditingController(text:'22'); showDialog(context:context, builder:(ctx)=>AlertDialog(title:Text('新增 7 x 自定行數'), content:Column(mainAxisSize:MainAxisSize.min, children:[ TextField(controller:nameC), TextField(controller:rowC, keyboardType:TextInputType.number) ]), actions:[ FilledButton(onPressed:(){ int rows=int.tryParse(rowC.text)??22; Navigator.pop(ctx); var pat=Pattern(nameC.text, List.filled(rows*7, shifts.first.code)); setState(()=>patterns.add(pat)); save(); }, child:Text('建立')) ])); }
  void applyPattern(){
    if(patterns.isEmpty) return; Pattern sel=patterns.first; DateTime sD=DateTime(focused.year,focused.month,1); DateTime eD=DateTime(focused.year,focused.month+1,0);
    showDialog(context:context, builder:(ctx)=>StatefulBuilder(builder:(ctx,setM){
      return AlertDialog(title:Text('套用模式排更'), content:Column(mainAxisSize:MainAxisSize.min, children:[
        DropdownButton<Pattern>(value:sel, items:[ for(var p in patterns) DropdownMenuItem(value:p, child:Text(p.name)) ], onChanged:(v){ if(v!=null) setM(()=>sel=v); }),
        ListTile(title:Text('開始 '+DateFormat('yyyy-MM-dd').format(sD)), onTap:()async{ DateTime? d=await showDatePicker(context:ctx, firstDate:DateTime(2000), lastDate:DateTime(2100), initialDate:sD); if(d!=null) setM(()=>sD=d); }),
        ListTile(title:Text('結束 '+DateFormat('yyyy-MM-dd').format(eD)), onTap:()async{ DateTime? d=await showDatePicker(context:ctx, firstDate:DateTime(2000), lastDate:DateTime(2100), initialDate:eD); if(d!=null) setM(()=>eD=d); }),
      ]), actions:[ FilledButton(onPressed:(){ setState((){ int idx=0; for(DateTime d=sD;!d.isAfter(eD); d=d.add(Duration(days:1))){ roster[k(d)]=sel.codes[idx%sel.codes.length]; idx++; } save(); }); Navigator.pop(ctx); }, child:Text('排更')) ]
      );
    }));
  }
  @override Widget build(BuildContext context){
    return Scaffold(
      body:[buildCal(),buildReport(),buildSetting()][tab],
      bottomNavigationBar:NavigationBar(selectedIndex:tab, onDestinationSelected:(i)=>setState(()=>tab=i), destinations:[ NavigationDestination(icon:Icon(Icons.calendar_month), label:'月曆'), NavigationDestination(icon:Icon(Icons.bar_chart), label:'報表'), NavigationDestination(icon:Icon(Icons.settings), label:'設定'), ]),
    );
  }
  Widget buildCal(){
    var days=days42(focused);
    // 修復那行，拆開寫避免 \$ 巢狀
    String selKey=k(selected);
    String selCode=roster[selKey]??'未排';
    String selInfo='';
    if(roster[selKey]!=null){
      double a=allowFor(getS(roster[selKey]!));
      selInfo=' 津貼'+a.toStringAsFixed(0);
    }
    String bottomText=DateFormat('MM/dd EEEE').format(selected)+' '+selCode+selInfo;
    return Column(children:[
      SafeArea(child:Padding(padding:EdgeInsets.all(12), child:Row(children:[
        IconButton(icon:Icon(Icons.calendar_today), onPressed:(){ setState((){ focused=DateTime.now(); selected=DateTime.now(); }); }),
        InkWell(onTap:pickYM, child:Row(children:[ Text('${focused.year}年${focused.month}月',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)), Icon(Icons.arrow_drop_down) ])),
        Spacer(), IconButton(icon:Icon(Icons.grid_view), onPressed:createPattern), IconButton(icon:Icon(Icons.playlist_add_check), onPressed:applyPattern),
      ]))),
      Row(children:[ for(var w in ['Mon','Tue','Wed','Thu','Fri','Sat','Sun']) Expanded(child:Center(child:Text(w,style:TextStyle(fontWeight:FontWeight.bold)))) ]),
      Column(children:[
        for(int r=0;r<6;r++) Row(children:[
          for(int c=0;c<7;c++) Builder(builder:(_){
            int idx=r*7+c; DateTime day=days[idx]; bool out=day.month!=focused.month; String key=k(day); String? code=roster[key]; Shift? sh=code!=null?getS(code):null; bool isSel=k(day)==k(selected);
            if(out) return Expanded(child: Container(height:64, margin:EdgeInsets.all(4), decoration:BoxDecoration(color:Color(0xFFF5F5F5), borderRadius:BorderRadius.circular(12)), child:Center(child:Text(day.day.toString(),style:TextStyle(color:Colors.black26)))));
            Color bg=isSel?Color(0xFFFFD54F):Color(0xFFF1F3F4); if(sh!=null&&!isSel) bg=sh.color.withOpacity(0.15);
            return Expanded(child: GestureDetector(onTap:(){ setState(()=>selected=day); }, child: Container(height:64, margin:EdgeInsets.all(4), decoration:BoxDecoration(color:bg, borderRadius:BorderRadius.circular(12), border:isSel?Border.all(color:Color(0xFFFFC107),width:3):null), child:Stack(children:[
              if(day.weekday==1) Positioned(top:2,left:2, child:Container(padding:EdgeInsets.symmetric(horizontal:4,vertical:1), decoration:BoxDecoration(color:Color(0xFF616161), borderRadius:BorderRadius.circular(4)), child:Text('W${isoWeek(day)}',style:TextStyle(color:Colors.white,fontSize:8)))),
              Center(child:Column(mainAxisAlignment:MainAxisAlignment.center, children:[ Text(day.day.toString(),style:TextStyle(fontWeight:FontWeight.bold)), if(sh!=null) Text(sh.code,style:TextStyle(fontSize:10,color:sh.color)) ])),
            ]))));
          })
        ])
      ]),
      Padding(padding:EdgeInsets.all(12), child:Row(children:[
        Expanded(child: Container(padding:EdgeInsets.symmetric(horizontal:16,vertical:10), decoration:BoxDecoration(color:Color(0xFFE0E0E0), borderRadius:BorderRadius.circular(24)), child:Text(bottomText,style:TextStyle(fontWeight:FontWeight.bold)))),
        SizedBox(width:8), FilledButton.icon(onPressed:()=>editCell(selected), icon:Icon(Icons.edit), label:Text('編輯')),
      ])),
    ]);
  }
  Widget buildReport(){
    DateTime mon=focused; double totA=0,totT=0,totOT=0,totH=0; int cW=0;
    roster.forEach((kk,v){ var d=DateTime.parse(kk); if(d.year!=mon.year||d.month!=mon.month) return; var s=getS(v); double ex=extra[kk]??0; totH+=s.h+ex; if(s.work){ cW++; totT+=transB; } totA+=allowFor(s); if(ex>0) totOT+=ex*otR; });
    return ListView(padding:EdgeInsets.all(16), children:[
      Text('${mon.year}年${mon.month}月 報表',style:TextStyle(fontWeight:FontWeight.bold,fontSize:18)),
      Card(child:ListTile(title:Text('返工 $cW日 ${totH}h'))),
      Card(child:ListTile(title:Text('津貼'), trailing:Text(totA.toStringAsFixed(0)))),
      Card(child:ListTile(title:Text('交通'), trailing:Text(totT.toStringAsFixed(0)))),
      Card(child:ListTile(title:Text('OT'), trailing:Text(totOT.toStringAsFixed(0)))),
      Card(color:Color(0xFFE8EAF6), child:ListTile(title:Text('總額',style:TextStyle(fontWeight:FontWeight.bold)), trailing:Text((totA+totT+totOT).toStringAsFixed(0),style:TextStyle(fontSize:22,fontWeight:FontWeight.bold)))),
    ]);
  }
  Widget buildSetting(){
    return ListView(padding:EdgeInsets.all(12), children:[
      Text('自定班次',style:TextStyle(fontWeight:FontWeight.bold,fontSize:18)),
      for(var s in shifts) Card(child:ListTile(
        leading:CircleAvatar(backgroundColor:s.color, child:Text(s.code,style:TextStyle(color:Colors.white))),
        title:Text('${s.code} - ${s.name} ${s.h}h'),
        subtitle:Text('津貼${allowFor(s).toStringAsFixed(1)} ${s.work?'有交通':'無交通'}'),
        trailing:Row(mainAxisSize:MainAxisSize.min, children:[ IconButton(icon:Icon(Icons.edit), onPressed:()=>editShiftDialog(s)), IconButton(icon:Icon(Icons.delete), onPressed:(){ setState(()=>shifts.remove(s)); save(); }) ]),
      )),
      FilledButton.icon(onPressed:()=>editShiftDialog(null), icon:Icon(Icons.add), label:Text('新增自定班次'), style: FilledButton.styleFrom(minimumSize:Size(double.infinity,48))),
      Divider(),
      Text('津貼設定 - 自定開始時間',style:TextStyle(fontWeight:FontWeight.bold,fontSize:18)),
      for(var a in allowances) Card(child:ListTile(
        title:Text('${a.name} ${a.start} \$${a.amount}'),
        subtitle:Text(a.enabled?'已啟用':'已停用'),
        trailing:Row(mainAxisSize:MainAxisSize.min, children:[ IconButton(icon:Icon(Icons.edit), onPressed:()=>editAllowDialog(a)), IconButton(icon:Icon(Icons.delete), onPressed:(){ setState(()=>allowances.remove(a)); save(); }) ]),
      )),
      Row(children:[ Expanded(child:ElevatedButton(onPressed:()=>editAllowDialog(null), child:Text('新增津貼'))), SizedBox(width:8), Expanded(child:OutlinedButton(onPressed:(){ setState(()=>allowances=[ Allowance('早班津貼','06:00',20,true), Allowance('中班津貼','14:00',0,true), Allowance('夜班津貼','22:00',80,true), Allowance('通宵津貼','23:30',120,true) ]); save(); }, child:Text('重置'))), ]),
      Divider(),
      ListTile(title:Text('OT時薪'), trailing:SizedBox(width:100, child:TextField(controller:TextEditingController(text:otR.toString()), decoration:InputDecoration(prefixText:'\$', border:OutlineInputBorder()), onSubmitted:(v){ var vv=double.tryParse(v); if(vv!=null){ setState(()=>otR=vv); save(); } }))),
      ListTile(title:Text('交通津貼'), trailing:SizedBox(width:100, child:TextField(controller:TextEditingController(text:transB.toString()), decoration:InputDecoration(prefixText:'\$', border:OutlineInputBorder()), onSubmitted:(v){ var vv=double.tryParse(v); if(vv!=null){ setState(()=>transB=vv); save(); } }))),
      ListTile(title:Text('格子文字大小 ${fs.toInt()}'), subtitle:Slider(value:fs, min:8, max:20, divisions:12, onChanged:(v){ setState(()=>fs=v); save(); })),
      Divider(),
      FilledButton.icon(onPressed:createPattern, icon:Icon(Icons.add), label:Text('新增 7 x 自定行數 模式'), style: FilledButton.styleFrom(minimumSize:Size(double.infinity,50))),
      SizedBox(height:8),
      FilledButton.icon(onPressed:applyPattern, icon:Icon(Icons.play_arrow), label:Text('套用模式排更'), style: FilledButton.styleFrom(minimumSize:Size(double.infinity,50))),
      SizedBox(height:60),
    ]);
  }
}
