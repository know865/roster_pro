import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main()=>runApp(MaterialApp(debugShowCheckedModeBanner:false, theme: ThemeData(useMaterial3:true, colorSchemeSeed: Colors.indigo), home: MainPage()));

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
  int get mins{ var p=start.split(':'); try{return int.parse(p[0])*60+int.parse(p[1]);}catch(e){return 0;} }
}
class RosterPattern{
  String name; List<String> codes;
  RosterPattern(this.name,this.codes);
  Map toJson()=>{'name':name,'codes':codes};
  static RosterPattern fromJson(Map m)=>RosterPattern(m['name'], List<String>.from(m['codes']));
}

class MainPage extends StatefulWidget{ @override State<MainPage> createState()=>_S(); }
class _S extends State<MainPage>{
  int tab=0;
  Map<String,String> roster={}, notes={};
  Map<String,double> extra={};
  List<Shift> shifts=[];
  List<Allowance> allowances=[];
  List<RosterPattern> patterns=[];
  DateTime focused=DateTime.now(), selected=DateTime.now();
  double fs=11, otR=100, transB=20;

  _S(){
    shifts=[
      Shift('早','早更','07:00','15:30',Colors.orange.value,8,true),
      Shift('中','中更','15:00','23:30',Colors.blue.value,8,true),
      Shift('夜','夜更','23:00','07:30',Colors.indigo.value,8,true),
      Shift('宵','通宵','23:30','08:00',Colors.deepPurple.value,8,true),
      Shift('O','例休','','',Colors.green.value,0,false),
      Shift('OT','OT','','',Colors.brown.value,4,true),
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
  Shift getS(String c){ for(var s in shifts) if(s.code==c) return s; return Shift('','','','',Colors.grey.value,0,false); }
  int parseMins(String t){ try{ if(t=='') return -1; var p=t.split(':'); return int.parse(p[0])*60+int.parse(p[1]); }catch(e){ return -1; } }
  double allowanceForShift(Shift s){
    if(!s.work || s.start=='') return 0;
    int sm=parseMins(s.start); if(sm<0) return 0;
    Allowance? best; int bestDiff=10000;
    for(var a in allowances){ if(!a.enabled) continue; int am=a.mins; int diff=sm-am; if(diff<0) diff+=1440; if(diff<bestDiff && diff<720){ bestDiff=diff; best=a; } }
    return best?.amount??0;
  }
  void save() async{ var p=await SharedPreferences.getInstance(); p.setString('roster',jsonEncode(roster)); p.setString('notes',jsonEncode(notes)); p.setString('extra',jsonEncode(extra)); p.setString('shifts',jsonEncode(shifts.map((e)=>e.toJson()).toList())); p.setString('allowances',jsonEncode(allowances.map((e)=>e.toJson()).toList())); p.setString('patterns',jsonEncode(patterns.map((e)=>e.toJson()).toList())); p.setDouble('otR',otR); p.setDouble('transB',transB); p.setDouble('fs',fs); }
  void load() async{ var p=await SharedPreferences.getInstance(); var r=p.getString('roster'); if(r!=null){ var d=jsonDecode(r); roster=(d as Map).map((k,v)=>MapEntry(k.toString(),v.toString())); } var sh=p.getString('shifts'); if(sh!=null){ var d=jsonDecode(sh) as List; shifts=d.map((e)=>Shift.fromJson(e)).toList(); } var al=p.getString('allowances'); if(al!=null){ var d=jsonDecode(al) as List; allowances=d.map((e)=>Allowance.fromJson(e)).toList(); } var n=p.getString('notes'); if(n!=null){ var d=jsonDecode(n); notes=(d as Map).map((k,v)=>MapEntry(k.toString(),v.toString())); } var ex=p.getString('extra'); if(ex!=null){ var d=jsonDecode(ex); extra=(d as Map).map((k,v)=>MapEntry(k.toString(),(v as num).toDouble())); } var pat=p.getString('patterns'); if(pat!=null){ var d=jsonDecode(pat) as List; patterns=d.map((e)=>RosterPattern.fromJson(e)).toList(); } setState((){ otR=p.getDouble('otR')??100; transB=p.getDouble('transB')??20; fs=p.getDouble('fs')??11; }); }
  @override void initState(){ super.initState(); load(); }
  void goToday(){ setState((){ focused=DateTime.now(); selected=DateTime.now(); }); }
  void changeMonth(int add){ setState(()=>focused=DateTime(focused.year,focused.month+add,1)); }
  void pickYM(){ int y=focused.year,m=focused.month; TextEditingController yearC=TextEditingController(text: y.toString()); showDialog(context: context, builder: (ctx)=>StatefulBuilder(builder: (ctx,setM){ return AlertDialog(title: Text('選擇年月 無限'), content: SizedBox(width:340,height:380, child: Column(children:[ Row(children:[ IconButton(onPressed:(){ setM((){ y-=10; yearC.text=y.toString(); }); }, icon:Icon(Icons.fast_rewind)), IconButton(onPressed:(){ setM((){ y-=1; yearC.text=y.toString(); }); }, icon:Icon(Icons.remove)), Expanded(child: TextField(controller: yearC, textAlign:TextAlign.center, keyboardType:TextInputType.number, decoration:InputDecoration(border:OutlineInputBorder()))), IconButton(onPressed:(){ setM((){ y+=1; yearC.text=y.toString(); }); }, icon:Icon(Icons.add)), IconButton(onPressed:(){ setM((){ y+=10; yearC.text=y.toString(); }); }, icon:Icon(Icons.fast_forward)), ]), SizedBox(height:50, child: ListView.builder(scrollDirection:Axis.horizontal, itemCount:80, itemBuilder:(c,i){ int yy=y-40+i; return Padding(padding:EdgeInsets.all(3), child: ChoiceChip(label:Text(yy.toString()), selected:yy==y, onSelected:(v){ setM((){ y=yy; yearC.text=yy.toString(); }); })); })), GridView.count(shrinkWrap:true, crossAxisCount:4, children:[ for(int mm=1;mm<=12;mm++) ChoiceChip(label:Text('${mm}月'), selected:m==mm, onSelected:(v){ setM((){ m=mm; }); }) ]), ])), actions:[ TextButton(onPressed:()=>Navigator.pop(ctx),child:Text('取消')), FilledButton(onPressed:(){ int? yy=int.tryParse(yearC.text); if(yy!=null) y=yy; setState(()=>focused=DateTime(y,m,1)); Navigator.pop(ctx); },child:Text('跳轉'))]); })); }
  void editCell(DateTime d){ TextEditingController noteC=TextEditingController(text: notes[k(d)]?? ''); TextEditingController exC=TextEditingController(text: (extra[k(d)]?? 0).toString()); String cur=roster[k(d)]?? ''; showModalBottomSheet(context: context, isScrollControlled:true, builder:(ctx)=>StatefulBuilder(builder:(ctx,setM){ return Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom,left:16,right:16,top:16), child:Column(mainAxisSize:MainAxisSize.min, children:[ Text(DateFormat('yyyy-MM-dd EEEE').format(d)), Wrap(spacing:6, children:[ for(var s in shifts) ChoiceChip(label:Text(s.code), selected:cur==s.code, onSelected:(v){ setM((){ cur=v?s.code:''; }); }) ]), TextField(controller: noteC, decoration:InputDecoration(labelText:'記事')), TextField(controller: exC, decoration:InputDecoration(labelText:'額外OT小時'),keyboardType:TextInputType.number), FilledButton(onPressed:(){ setState((){ if(cur=='') roster.remove(k(d)); else roster[k(d)]=cur; if(noteC.text=='') notes.remove(k(d)); else notes[k(d)]=noteC.text; var vv=double.tryParse(exC.text); if(vv==null||vv==0) extra.remove(k(d)); else extra[k(d)]=vv; save(); }); Navigator.pop(ctx); },child:Text('保存')), SizedBox(height:20) ])); })); }
  void editShiftDialog(Shift? old){ TextEditingController codeC=TextEditingController(text: old?.code??''); TextEditingController nameC=TextEditingController(text: old?.name??''); TextEditingController startC=TextEditingController(text: old?.start??'07:00'); TextEditingController endC=TextEditingController(text: old?.end??'15:00'); TextEditingController hC=TextEditingController(text: (old?.h??8).toString()); Color pickC=old!=null?Color(old.c):Colors.orange; bool work=old?.work??true; showDialog(context: context, builder: (ctx)=>StatefulBuilder(builder: (ctx,setM){ return AlertDialog(title:Text(old==null?'新增班次':'編輯班次'), content:SingleChildScrollView(child:Column(children:[ TextField(controller: codeC, decoration:InputDecoration(labelText:'代號')), TextField(controller: nameC, decoration:InputDecoration(labelText:'名稱')), Row(children:[ Expanded(child: TextField(controller: startC, decoration:InputDecoration(labelText:'開始 HH:MM'))), SizedBox(width:8), Expanded(child: TextField(controller: endC, decoration:InputDecoration(labelText:'結束'))) ]), TextField(controller: hC, keyboardType:TextInputType.number, decoration:InputDecoration(labelText:'時數')), CheckboxListTile(title:Text('有交通'), value:work, onChanged:(v){ setM(()=>work=v!); }), Wrap(spacing:6, children:[ for(var c in [Colors.orange, Colors.blue, Colors.indigo, Colors.purple, Colors.green, Colors.brown, Colors.red, Colors.teal]) GestureDetector(onTap:(){ setM(()=>pickC=c); }, child:CircleAvatar(backgroundColor:c, radius:18)) ]) ])), actions:[ TextButton(onPressed:()=>Navigator.pop(ctx),child:Text('取消')), FilledButton(onPressed:(){ if(codeC.text=='') return; setState((){ var ns=Shift(codeC.text, nameC.text==''?codeC.text:nameC.text, startC.text, endC.text, pickC.value, double.tryParse(hC.text)??8, work); if(old==null) shifts.add(ns); else { int idx=shifts.indexOf(old); shifts[idx]=ns; } }); save(); Navigator.pop(ctx); },child:Text('保存'))]); })); }
  void editAllowanceDialog(Allowance? old){ TextEditingController nameC=TextEditingController(text: old?.name??''); TextEditingController startC=TextEditingController(text: old?.start??'07:00'); TextEditingController amountC=TextEditingController(text: (old?.amount??0).toString()); bool enabled=old?.enabled??true; showDialog(context: context, builder: (ctx)=>StatefulBuilder(builder: (ctx,setM){ return AlertDialog(title:Text(old==null?'新增津貼':'編輯津貼'), content:Column(mainAxisSize:MainAxisSize.min, children:[ TextField(controller: nameC, decoration:InputDecoration(labelText:'名稱')), TextField(controller: startC, decoration:InputDecoration(labelText:'開始時間 HH:MM')), TextField(controller: amountC, keyboardType:TextInputType.number, decoration:InputDecoration(labelText:'金額 \$')), CheckboxListTile(title:Text('啟用'), value:enabled, onChanged:(v){ setM(()=>enabled=v!); }) ]), actions:[ TextButton(onPressed:()=>Navigator.pop(ctx),child:Text('取消')), FilledButton(onPressed:(){ if(nameC.text=='') return; setState((){ var na=Allowance(nameC.text, startC.text, double.tryParse(amountC.text)??0, enabled); if(old==null) allowances.add(na); else { int idx=allowances.indexOf(old); allowances[idx]=na; } }); save(); Navigator.pop(ctx); },child:Text('保存'))]); })); }
  void createPattern(){ TextEditingController nameC=TextEditingController(text:'自定${patterns.length+1}'); TextEditingController rowC=TextEditingController(text:'22'); showDialog(context: context, builder: (ctx)=>AlertDialog(title:Text('7 x 自定行數'), content:Column(mainAxisSize:MainAxisSize.min, children:[ TextField(controller: nameC), TextField(controller: rowC, keyboardType:TextInputType.number, decoration:InputDecoration(labelText:'行數 1-100')) ]), actions:[ TextButton(onPressed:()=>Navigator.pop(ctx),child:Text('取消')), FilledButton(onPressed:(){ int rows=int.tryParse(rowC.text)??22; Navigator.pop(ctx); openPatternEditor(RosterPattern(nameC.text, List.filled(rows*7, shifts.first.code))); },child:Text('下一步')) ])); }
  void openPatternEditor(RosterPattern pat){ showDialog(context: context, builder: (ctx)=>StatefulBuilder(builder: (ctx,setM){ return AlertDialog(title:Text(pat.name), content:SizedBox(width:400,height:460, child:GridView.builder(gridDelegate:SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:7), itemCount:pat.codes.length, itemBuilder:(c,i){ String code=pat.codes[i]; Shift s=getS(code); return GestureDetector(onTap:(){ showModalBottomSheet(context:ctx, builder:(b)=>Container(padding:EdgeInsets.all(16), child:Wrap(children:[ for(var ss in shifts) ChoiceChip(label:Text(ss.code), selected:ss.code==code, onSelected:(v){ setM((){ pat.codes[i]=ss.code; }); Navigator.pop(b); }) ]))); }, child:Container(margin:EdgeInsets.all(2), color:s.color, child:Center(child:Text(code,style:TextStyle(color:Colors.white))))); })), actions:[ FilledButton(onPressed:(){ setState(()=>patterns.add(pat)); save(); Navigator.pop(ctx); },child:Text('保存')) ]); })); }
  void applyPattern(){ if(patterns.isEmpty) return; RosterPattern sel=patterns.first; DateTime sDate=DateTime(focused.year,focused.month,1); DateTime eDate=DateTime(focused.year,focused.month+1,0); showDialog(context: context, builder: (ctx)=>StatefulBuilder(builder: (ctx,setM){ return AlertDialog(title:Text('套用模式'), content:Column(mainAxisSize:MainAxisSize.min, children:[ DropdownButton<RosterPattern>(value:sel, items:[for(var p in patterns) DropdownMenuItem(value:p, child:Text(p.name))], onChanged:(v){ if(v!=null) setM(()=>sel=v); }), ListTile(title:Text('開始 ${DateFormat('yyyy-MM-dd').format(sDate)}'), onTap:()async{ DateTime? d=await showDatePicker(context:ctx,firstDate:DateTime(1900),lastDate:DateTime(2100),initialDate:sDate); if(d!=null) setM(()=>sDate=d); }) ]), actions:[ FilledButton(onPressed:(){ setState((){ int idx=0; for(DateTime d=sDate;!d.isAfter(eDate); d=d.add(Duration(days:1))){ roster[k(d)]=sel.codes[idx%sel.codes.length]; idx++; } save(); }); Navigator.pop(ctx); },child:Text('開始')) ]); })); }
  List<DateTime> daysInMonth(DateTime mon){ var first=DateTime(mon.year,mon.month,1); int off=first.weekday-1; var start=first.subtract(Duration(days:off)); return List.generate(42,(i)=>start.add(Duration(days:i))); }

  @override Widget build(BuildContext context){ return Scaffold(body: [buildCal(), buildReport(), buildSetting()][tab], bottomNavigationBar: NavigationBar(selectedIndex:tab,onDestinationSelected:(i)=>setState(()=>tab=i),destinations:[ NavigationDestination(icon:Icon(Icons.calendar_month),label:'月曆'), NavigationDestination(icon:Icon(Icons.bar_chart),label:'報表'), NavigationDestination(icon:Icon(Icons.settings),label:'設定') ])); }

  Widget buildCal(){
    var days=daysInMonth(focused); Shift? sel=roster.containsKey(k(selected))?getS(roster[k(selected)]!):null;
    return Scaffold(appBar: AppBar(leading: IconButton(icon:Icon(Icons.today), onPressed:goToday), title: InkWell(onTap:pickYM, child: Row(children:[ Text('${focused.year}年${focused.month}月',style:TextStyle(fontWeight:FontWeight.w900)), Icon(Icons.arrow_drop_down) ])), actions:[ IconButton(icon:Icon(Icons.grid_view), onPressed:createPattern), IconButton(icon:Icon(Icons.playlist_play), onPressed:applyPattern) ]), body: Column(children:[
      Row(children:[ for(var w in ['Mon','Tue','Wed','Thu','Fri','Sat','Sun']) Expanded(child:Center(child:Text(w))) ]),
      Expanded(flex:3, child: GestureDetector(onHorizontalDragEnd:(d){ if(d.primaryVelocity!=null){ if(d.primaryVelocity! < -300) changeMonth(1); if(d.primaryVelocity! > 300) changeMonth(-1); } }, child: GridView.builder(padding:EdgeInsets.all(4), physics:NeverScrollableScrollPhysics(), gridDelegate:SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:7, childAspectRatio:0.88, crossAxisSpacing:4, mainAxisSpacing:4), itemCount:42, itemBuilder:(c,i){
        DateTime day=days[i]; bool out=day.month!=focused.month; String key=k(day); String? code=roster[key]; Shift? sh=code!=null?getS(code):null; bool isToday=k(day)==k(DateTime.now()); bool isSel=k(day)==k(selected); bool isMon=day.weekday==1;
        if(out) return Center(child:Text(day.day.toString(),style:TextStyle(color:Colors.grey)));
        double dayA=sh!=null? allowanceForShift(sh) + (sh.work?transB:0) : 0;
        return GestureDetector(onTap:()=>setState(()=>selected=day), onLongPress:()=>editCell(day), child:Container(decoration:BoxDecoration(color:sh!=null?sh.color:Color(0xFFF0F0F0), borderRadius:BorderRadius.circular(8), border:isToday?Border.all(color:Colors.amber,width:3):isSel?Border.all(color:Colors.indigo,width:2):null), child:Stack(children:[
          if(isMon) Positioned(top:2,left:2,child:Container(padding:EdgeInsets.symmetric(horizontal:3,vertical:1),color:Colors.black54,child:Text('W${isoWeek(day)}',style:TextStyle(color:Colors.white,fontSize:7)))),
          Center(child:Column(mainAxisAlignment:MainAxisAlignment.center, children:[ Text(day.day.toString(),style:TextStyle(fontWeight:FontWeight.bold,color:sh!=null?Colors.white:Colors.black)), if(sh!=null) Text(sh.code,style:TextStyle(color:Colors.white,fontSize:fs)), if(sh!=null && dayA>0) Text('\$${dayA.toStringAsFixed(0)}',style:TextStyle(color:Colors.white,fontSize:8)) ]))
        ])));
      }))),
      Divider(height:1),
      Expanded(flex:2, child: Container(color:Colors.white, padding:EdgeInsets.all(12), child:ListView(children:[
        Row(children:[ Container(padding:EdgeInsets.symmetric(horizontal:12,vertical:6),decoration:BoxDecoration(color:sel?.color??Colors.grey.shade300,borderRadius:BorderRadius.circular(20)),child:Text('${DateFormat('MM/dd').format(selected)} ${roster[k(selected)]??'未排'}')), Spacer(), FilledButton(onPressed:()=>editCell(selected),child:Text('編輯')) ]),
        if(sel!=null) Text('津貼 \$${allowanceForShift(sel)} + 交通 \$${sel.work?transB:0} = \$${(allowanceForShift(sel)+(sel.work?transB:0)).toStringAsFixed(0)}'),
      ]))),
    ]));
  }

  Widget buildReport(){
    DateTime mon=focused; double totH=0,totA=0,totTrans=0,totOT=0,totOTPay=0; int cWork=0;
    roster.forEach((kk,v){ var d=DateTime.parse(kk); if(d.year!=mon.year||d.month!=mon.month) return; var s=getS(v); totH+=s.h; if(s.work){ cWork++; totTrans+=transB; } totA+=allowanceForShift(s); });
    return Scaffold(appBar:AppBar(title:Text('${mon.year}年${mon.month}月 報表')), body:ListView(padding:EdgeInsets.all(16), children:[
      Card(child:ListTile(title:Text('返工 $cWork日 工時 ${totH}h'))),
      Card(child:ListTile(title:Text('津貼自動計'), subtitle:Text('按開始時間'), trailing:Text('\$${totA.toStringAsFixed(0)}'))),
      Card(child:ListTile(title:Text('交通'), trailing:Text('\$${totTrans.toStringAsFixed(0)}'))),
      Card(child:ListTile(title:Text('總額'), trailing:Text('\$${(totA+totTrans).toStringAsFixed(0)}',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold)))),
    ]));
  }

  Widget buildSetting(){
    return Scaffold(appBar:AppBar(title:Text('設定')), body:ListView(padding:EdgeInsets.all(12), children:[
      Text('自定班次 (5行，多過可拉動) - 修復彩虹',style:TextStyle(fontWeight:FontWeight.bold)),
      RepaintBoundary(
        child: Container(height: 310, decoration:BoxDecoration(color:Colors.white, border:Border.all(color:Colors.grey.shade300), borderRadius:BorderRadius.circular(12)), clipBehavior: Clip.hardEdge,
          child: Scrollbar(thumbVisibility: true, child: ListView.builder(physics: ClampingScrollPhysics(), itemCount: shifts.length, itemBuilder:(c,i){
            var s=shifts[i];
            return Card(margin:EdgeInsets.symmetric(horizontal:6,vertical:2), child: ListTile(dense:true, leading:CircleAvatar(backgroundColor:s.color, radius:16, child:Text(s.code,style:TextStyle(color:Colors.white,fontSize:10))), title:Text('${s.code} ${s.name} ${s.start}-${s.end}',style:TextStyle(fontSize:12)), subtitle:Text('自動津貼 \$${allowanceForShift(s).toStringAsFixed(0)}',style:TextStyle(fontSize:10)), trailing
