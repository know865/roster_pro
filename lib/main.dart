import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main()=>runApp(MaterialApp(debugShowCheckedModeBanner:false, theme: ThemeData(useMaterial3:true, colorSchemeSeed: Colors.indigo), home: MainPage()));

class Shift{
  String code,name,start,end; int c; double h,b; bool work;
  Shift(this.code,this.name,this.start,this.end,this.c,this.h,this.b,this.work);
  Map toJson()=>{'code':code,'name':name,'start':start,'end':end,'c':c,'h':h,'b':b,'work':work};
  static Shift fromJson(Map m)=>Shift(m['code'],m['name'],m['start'],m['end'],m['c'],(m['h'] as num).toDouble(),(m['b'] as num).toDouble(),m['work']);
  Color get color=>Color(c);
}

class MainPage extends StatefulWidget{ @override State<MainPage> createState()=>_S(); }
class _S extends State<MainPage>{
  int tab=0;
  Map<String,String> roster={}, notes={};
  Map<String,double> extra={};
  List<Shift> shifts=[];
  DateTime focused=DateTime.now(), selected=DateTime.now();
  double fs=11, otR=100, earlyB=20, nightB=80, overB=120, transB=20, stdW=42;

  _S(){
    shifts=[
      Shift('早','早更','07:00','15:30',Colors.orange.value,8,20,true),
      Shift('中','中更','15:00','23:30',Colors.blue.value,8,0,true),
      Shift('夜','夜更','23:00','07:30',Colors.indigo.value,8,80,true),
      Shift('宵','通宵','23:30','08:00',Colors.deepPurple.value,8,120,true),
      Shift('O','例休','','',Colors.green.value,0,0,false),
      Shift('OT','OT','','',Colors.brown.value,4,100,true),
    ];
  }
  String k(DateTime d)=>DateFormat('yyyy-MM-dd').format(d);
  int isoWeek(DateTime d){ var thu=d.add(Duration(days:4-d.weekday)); var jan1=DateTime(thu.year,1,1); return (thu.difference(jan1).inDays/7).floor()+1; }
  Shift getS(String c){ for(var s in shifts) if(s.code==c) return s; return Shift('','','','',Colors.grey.value,0,0,false); }
  void save() async{ var p=await SharedPreferences.getInstance(); p.setString('roster',jsonEncode(roster)); p.setString('notes',jsonEncode(notes)); p.setString('extra',jsonEncode(extra)); p.setString('shifts',jsonEncode(shifts.map((e)=>e.toJson()).toList())); p.setDouble('otR',otR); p.setDouble('earlyB',earlyB); p.setDouble('nightB',nightB); p.setDouble('overB',overB); p.setDouble('transB',transB); p.setDouble('fs',fs); }
  void load() async{ var p=await SharedPreferences.getInstance(); var r=p.getString('roster'); if(r!=null){ var d=jsonDecode(r); roster=(d as Map).map((k,v)=>MapEntry(k.toString(),v.toString())); } var n=p.getString('notes'); if(n!=null){ var d=jsonDecode(n); notes=(d as Map).map((k,v)=>MapEntry(k.toString(),v.toString())); } var ex=p.getString('extra'); if(ex!=null){ var d=jsonDecode(ex); extra=(d as Map).map((k,v)=>MapEntry(k.toString(),(v as num).toDouble())); } setState((){ otR=p.getDouble('otR')??100; earlyB=p.getDouble('earlyB')??20; nightB=p.getDouble('nightB')??80; overB=p.getDouble('overB')??120; transB=p.getDouble('transB')??20; fs=p.getDouble('fs')??11; }); }
  @override void initState(){ super.initState(); load(); }
  void goToday(){ setState((){ focused=DateTime.now(); selected=DateTime.now(); }); }
  void pickYM(){ int y=focused.year,m=focused.month; showDialog(context: context, builder: (ctx)=>StatefulBuilder(builder: (ctx,setM){ return AlertDialog(title: Text('選擇年月',style:TextStyle(fontSize:22,fontWeight:FontWeight.w900)), content: SizedBox(width:320,height:360, child: Column(children: [ Text('年份'), Expanded(child: GridView.count(crossAxisCount:4, children:[ for(int yy=2024;yy<=2030;yy++) Padding(padding: EdgeInsets.all(4), child: ChoiceChip(label:Text(yy.toString(),style:TextStyle(fontSize:16)), selected: y==yy, onSelected:(v)=>setM(()=>y=yy))) ])), Divider(), Text('月份'), GridView.count(shrinkWrap:true, crossAxisCount:4, children:[ for(int mm=1;mm<=12;mm++) Padding(padding: EdgeInsets.all(4), child: ChoiceChip(label:Text('${mm}月'), selected:m==mm, onSelected:(v)=>setM(()=>m=mm))) ]) ])), actions:[ TextButton(onPressed:()=>Navigator.pop(ctx),child:Text('取消')), FilledButton(onPressed:(){ setState(()=>focused=DateTime(y,m,1)); Navigator.pop(ctx); },child:Text('跳轉')) ]); })); }
  void editCell(DateTime d){ var noteC=TextEditingController(text: notes[k(d)]??''); var exC=TextEditingController(text: (extra[k(d)]??0).toString()); String cur=roster[k(d)]??''; showModalBottomSheet(context: context, isScrollControlled:true, builder:(ctx)=>StatefulBuilder(builder:(ctx,setM){ return Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom,left:16,right:16,top:16), child:Column(mainAxisSize:MainAxisSize.min, children:[ Text(DateFormat('yyyy-MM-dd EEEE').format(d),style:TextStyle(fontWeight:FontWeight.bold,fontSize:18)), Wrap(spacing:6, children:[ for(var s in shifts) ChoiceChip(label:Text(s.code), selected:cur==s.code, onSelected:(v)=>setM(()=>cur=v?s.code:'')) ]), SizedBox(height:10), TextField(controller:noteC,decoration:InputDecoration(labelText:'記事',border:OutlineInputBorder())), SizedBox(height:8), TextField(controller:exC,decoration:InputDecoration(labelText:'額外OT小時',border:OutlineInputBorder()),keyboardType:TextInputType.number), SizedBox(height:10), FilledButton(onPressed:(){ setState((){ if(cur=='') roster.remove(k(d)); else roster[k(d)]=cur; if(noteC.text=='') notes.remove(k(d)); else notes[k(d)]=noteC.text; var vv=double.tryParse(exC.text); if(vv==null||vv==0) extra.remove(k(d)); else extra[k(d)]=vv; save(); }); Navigator.pop(ctx); },child:Text('保存')), SizedBox(height:20) ])); })); }
  List<DateTime> daysInMonth(DateTime mon){ var first=DateTime(mon.year,mon.month,1); int off=first.weekday-1; var start=first.subtract(Duration(days:off)); return List.generate(42,(i)=>start.add(Duration(days:i))); }

  @override Widget build(BuildContext context){
    return Scaffold(
      body: [buildCal(), buildReport(), buildSetting()][tab],
      bottomNavigationBar: NavigationBar(selectedIndex:tab,onDestinationSelected:(i)=>setState(()=>tab=i),destinations:[ NavigationDestination(icon:Icon(Icons.calendar_month),label:'月曆'), NavigationDestination(icon:Icon(Icons.bar_chart),label:'報表'), NavigationDestination(icon:Icon(Icons.settings),label:'設定') ]),
    );
  }

  Widget buildCal(){
    var days=daysInMonth(focused); Shift? sel=roster.containsKey(k(selected))?getS(roster[k(selected)]!):null;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon:Icon(Icons.today), tooltip:'回今日', onPressed:goToday),
        title: InkWell(onTap:pickYM, child: Row(mainAxisSize:MainAxisSize.min, children:[ Text('W${isoWeek(focused).toString().padLeft(2,'0')} ${focused.year}年${focused.month}月',style:TextStyle(fontSize:22,fontWeight:FontWeight.w900)), Icon(Icons.arrow_drop_down) ])),
        actions:[ IconButton(onPressed:(){ var sb=StringBuffer(); sb.writeln('日期,班次,工時,OT,記事'); roster.forEach((kk,v){ var d=DateTime.parse(kk); if(d.year==focused.year&&d.month==focused.month) sb.writeln('$kk,$v,${getS(v).h},${extra[kk]??0},${notes[kk]??''}'); }); showDialog(context:context,builder:(c)=>AlertDialog(title:Text('分享'),content:SingleChildScrollView(child:SelectableText(sb.toString())),actions:[TextButton(onPressed:()=>Navigator.pop(c),child:Text('關閉'))])); },icon:Icon(Icons.share)) ],
      ),
      body: Column(children:[
        Row(children:[ for(var w in ['Mon','Tue','Wed','Thu','Fri','Sat','Sun']) Expanded(child:Center(child:Text(w,style:TextStyle(fontWeight:FontWeight.bold)))) ]),
        Expanded(flex:3, child: GridView.builder(padding:EdgeInsets.all(4), gridDelegate:SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:7, childAspectRatio:0.85, crossAxisSpacing:4, mainAxisSpacing:4), itemCount:42, itemBuilder:(c,i){
          DateTime day=days[i]; bool out=day.month!=focused.month; String key=k(day); String? code=roster[key]; Shift? sh=code!=null?getS(code):null;
          bool isToday=k(day)==k(DateTime.now()); bool isSel=k(day)==k(selected); bool isMon=day.weekday==1;
          if(out) return Container(child:Center(child:Text(day.day.toString(),style:TextStyle(color:Colors.grey.shade400))));
          return GestureDetector(
            onTap:()=>setState(()=>selected=day),
            onLongPress:()=>editCell(day),
            child: Container(decoration:BoxDecoration(color:sh!=null?sh.color:Color(0xFFF0F0F0), borderRadius:BorderRadius.circular(10), border:isToday?Border.all(color:Colors.amber,width:3):isSel?Border.all(color:Colors.indigo,width:2.5):null), child:Stack(children:[
              if(isMon) Positioned(top:2,left:2,child:Container(padding:EdgeInsets.symmetric(horizontal:3,vertical:1),decoration:BoxDecoration(color:Colors.black54,borderRadius:BorderRadius.circular(3)),child:Text('W${isoWeek(day)}',style:TextStyle(color:Colors.white,fontSize:7)))),
              Center(child:Column(mainAxisAlignment:MainAxisAlignment.center, children:[ Text(day.day.toString(),style:TextStyle(fontSize:fs+3,fontWeight:FontWeight.bold,color:sh!=null?Colors.white:Colors.black87)), if(sh!=null) Text(sh.code,style:TextStyle(fontSize:fs,color:Colors.white)), if(extra.containsKey(key)) Text('+${extra[key]}h',style:TextStyle(fontSize:8,color:Colors.white)) ]))
            ])),
          );
        })),
        Divider(height:1),
        Expanded(flex:2, child: Container(color:Colors.white, padding:EdgeInsets.all(16), child:ListView(children:[
          Row(children:[ Container(padding:EdgeInsets.symmetric(horizontal:14,vertical:8),decoration:BoxDecoration(color:sel?.color??Colors.grey.shade300,borderRadius:BorderRadius.circular(24)),child:Text('${DateFormat('MM/dd EEEE').format(selected)} ${roster[k(selected)]??'未排'}',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold,color:sel!=null?Colors.white:Colors.black87))), Spacer(), FilledButton.icon(onPressed:()=>editCell(selected),icon:Icon(Icons.edit,size:16),label:Text('編輯')) ]),
          if(sel!=null) Card(child:ListTile(title:Text('${sel.name} ${sel.start}-${sel.end} ${sel.h}h +${extra[k(selected)]??0}h OT'))),
          if(notes[k(selected)]!=null) Card(color:Colors.amber.shade50, child:ListTile(title:Text(notes[k(selected)]!))),
        ]))),
      ]),
    );
  }

  Widget buildReport(){
    DateTime mon=focused; double totH=0,totOT=0,totTrans=0,totEarly=0,totNight=0,totOver=0,totOTPay=0; int cWork=0,cEarly=0,cNight=0,cOver=0,cOT=0;
    roster.forEach((kk,v){ var d=DateTime.parse(kk); if(d.year!=mon.year||d.month!=mon.month) return; var s=getS(v); double ex=extra[kk]??0; totH+=s.h+ex; if(s.work){ cWork++; totTrans+=transB; } if(s.code=='早'){ cEarly++; totEarly+=earlyB; } if(s.code=='夜'){ cNight++; totNight+=nightB; } if(s.code=='宵'){ cOver++; totOver+=overB; } if(s.code=='OT'||ex>0){ double oh=(s.code=='OT'?s.h:0)+ex; totOT+=oh; totOTPay+=oh*otR; cOT++; } });
    double all=totTrans+totEarly+totNight+totOver+totOTPay;
    return Scaffold(appBar:AppBar(title:Text('${mon.year}年${mon.month}月 報表',style:TextStyle(fontSize:20,fontWeight:FontWeight.w900))), body:ListView(padding:EdgeInsets.all(16), children:[
      Card(child:ListTile(title:Text('總工時 ${totH}h'), subtitle:Text('標準 ${stdW*4}h 差 ${(totH-stdW*4).toStringAsFixed(1)}h'))),
      Card(child:ListTile(title:Text('返工 $cWork日'), subtitle:Text('早$cEarly 夜$cNight 宵$cOver OT$cOT次'))),
      Card(color:Colors.orange.shade50, child:ListTile(title:Text('OT ${totOT}h x \$$otR'), trailing:Text('\$${totOTPay.toStringAsFixed(0)}',style:TextStyle(fontWeight:FontWeight.bold)))),
      Card(child:ListTile(title:Text('交通 $cWork x \$$transB'), trailing:Text('\$${totTrans.toStringAsFixed(0)}'))),
      Card(child:ListTile(title:Text('早班 $cEarly x \$$earlyB'), trailing:Text('\$${totEarly.toStringAsFixed(0)}'))),
      Card(child:ListTile(title:Text('夜班 $cNight x \$$nightB'), trailing:Text('\$${totNight.toStringAsFixed(0)}'))),
      Card(child:ListTile(title:Text('通宵 $cOver x \$$overB'), trailing:Text('\$${totOver.toStringAsFixed(0)}'))),
      Divider(),
      Card(color:Colors.indigo.shade50, child:ListTile(title:Text('津貼總額',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)), trailing:Text('\$${all.toStringAsFixed(0)}',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold,color:Colors.indigo)))),
    ]));
  }

  Widget buildSetting(){
    return Scaffold(appBar:AppBar(title:Text('設定')), body:ListView(padding:EdgeInsets.all(16), children:[
      Text('津貼設定',style:TextStyle(fontWeight:FontWeight.bold,fontSize:18)),
      ListTile(title:Text('OT時薪 \$${otR.toInt()}'), subtitle:Slider(value:otR,min:0,max:300,divisions:30,label:otR.toInt().toString(),onChanged:(v){ setState(()=>otR=v); save(); })),
      ListTile(title:Text('早班 \$${earlyB.toInt()}'), subtitle:Slider(value:earlyB,min:0,max:100,divisions:20,label:earlyB.toInt().toString(),onChanged:(v){ setState(()=>earlyB=v); save(); })),
      ListTile(title:Text('夜班 \$${nightB.toInt()}'), subtitle:Slider(value:nightB,min:0,max:200,divisions:20,label:nightB.toInt().toString(),onChanged:(v){ setState(()=>nightB=v); save(); })),
      ListTile(title:Text('通宵 \$${overB.toInt()}'), subtitle:Slider(value:overB,min:0,max:300,divisions:30,label:overB.toInt().toString(),onChanged:(v){ setState(()=>overB=v); save(); })),
      ListTile(title:Text('交通 \$${transB.toInt()}'), subtitle:Slider(value:transB,min:0,max:100,divisions:20,label:transB.toInt().toString(),onChanged:(v){ setState(()=>transB=v); save(); })),
      Divider(),
      Text('格子文字大小 ${fs.toInt()}'), Slider(value:fs,min:8,max:20,divisions:12,label:fs.toInt().toString(),onChanged:(v){ setState(()=>fs=v); save(); }),
    ]));
  }
}
