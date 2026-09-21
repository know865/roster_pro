import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main()=>runApp(MaterialApp(debugShowCheckedModeBanner:false, theme: ThemeData(useMaterial3:true, colorSchemeSeed: Colors.indigo), home: MainPage()));

class Shift{
  String code,name; int c; double h;
  Shift(this.code,this.name,this.c,this.h);
  Map toJson()=>{'code':code,'name':name,'c':c,'h':h};
  static Shift fromJson(Map m)=>Shift(m['code'],m['name'],m['c'],(m['h'] as num).toDouble());
  Color get color=>Color(c);
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
  List<RosterPattern> patterns=[];
  DateTime focused=DateTime.now(), selected=DateTime.now();
  double fs=11, otR=100, earlyB=20, nightB=80, overB=120, transB=20;
  double dragX=0, dragY=0;

  _S(){
    shifts=[
      Shift('早','早更',Colors.orange.value,8),
      Shift('中','中更',Colors.blue.value,8),
      Shift('夜','夜更',Colors.indigo.value,8),
      Shift('宵','通宵',Colors.deepPurple.value,8),
      Shift('O','例休',Colors.green.value,0),
      Shift('OT','OT',Colors.brown.value,4),
    ];
  }
  String k(DateTime d)=>DateFormat('yyyy-MM-dd').format(d);
  int isoWeek(DateTime d){ var thu=d.add(Duration(days:4-d.weekday)); var jan1=DateTime(thu.year,1,1); return (thu.difference(jan1).inDays/7).floor()+1; }
  Shift getS(String c){ for(var s in shifts) if(s.code==c) return s; return Shift('','','',Colors.grey.value,0); }
  void save() async{ var p=await SharedPreferences.getInstance(); p.setString('roster',jsonEncode(roster)); p.setString('notes',jsonEncode(notes)); p.setString('extra',jsonEncode(extra)); p.setString('patterns',jsonEncode(patterns.map((e)=>e.toJson()).toList())); p.setDouble('otR',otR); p.setDouble('earlyB',earlyB); p.setDouble('nightB',nightB); p.setDouble('overB',overB); p.setDouble('transB',transB); }
  void load() async{ var p=await SharedPreferences.getInstance(); var r=p.getString('roster'); if(r!=null){ var d=jsonDecode(r); roster=(d as Map).map((k,v)=>MapEntry(k.toString(),v.toString())); } var n=p.getString('notes'); if(n!=null){ var d=jsonDecode(n); notes=(d as Map).map((k,v)=>MapEntry(k.toString(),v.toString())); } var ex=p.getString('extra'); if(ex!=null){ var d=jsonDecode(ex); extra=(d as Map).map((k,v)=>MapEntry(k.toString(),(v as num).toDouble())); } var pat=p.getString('patterns'); if(pat!=null){ var d=jsonDecode(pat) as List; patterns=d.map((e)=>RosterPattern.fromJson(e)).toList(); } setState((){ otR=p.getDouble('otR')??100; earlyB=p.getDouble('earlyB')??20; nightB=p.getDouble('nightB')??80; overB=p.getDouble('overB')??120; transB=p.getDouble('transB')??20; }); }
  @override void initState(){ super.initState(); load(); }
  void goToday(){ setState((){ focused=DateTime.now(); selected=DateTime.now(); }); }
  void changeMonth(int add){ setState(()=>focused=DateTime(focused.year, focused.month+add,1)); }

  void pickYM(){
    int y=focused.year,m=focused.month;
    TextEditingController yearC=TextEditingController(text:y.toString());
    showDialog(context: context, builder: (ctx)=>StatefulBuilder(builder: (ctx,setM){
      return AlertDialog(
        title: Text('選擇年月 無限',style:TextStyle(fontSize:22,fontWeight:FontWeight.w900)),
        content: SizedBox(width:340,height:380, child: Column(children:[
          Row(children:[
            IconButton(onPressed:(){ setM((){ y-=10; yearC.text=y.toString(); }); }, icon:Icon(Icons.fast_rewind)),
            IconButton(onPressed:(){ setM((){ y-=1; yearC.text=y.toString(); }); }, icon:Icon(Icons.remove)),
            Expanded(child: TextField(controller:yearC, textAlign:TextAlign.center, keyboardType:TextInputType.number, decoration:InputDecoration(border:OutlineInputBorder(), labelText:'年份'), onChanged:(v){ var yy=int.tryParse(v); if(yy!=null) setM((){ y=yy; }); })),
            IconButton(onPressed:(){ setM((){ y+=1; yearC.text=y.toString(); }); }, icon:Icon(Icons.add)),
            IconButton(onPressed:(){ setM((){ y+=10; yearC.text=y.toString(); }); }, icon:Icon(Icons.fast_forward)),
          ]),
          SizedBox(height:10),
          Wrap(spacing:4, children:[ for(int yy=y-6; yy<=y+6; yy++) ChoiceChip(label:Text(yy.toString()), selected:yy==y, onSelected:(v){ setM((){ y=yy; yearC.text=yy.toString(); }); }) ]),
          Divider(),
          Wrap(spacing:4, children:[ for(int mm=1;mm<=12;mm++) ChoiceChip(label:Text('${mm}月'), selected:m==mm, onSelected:(v){ setM((){ m=mm; }); }) ]),
        ])),
        actions:[ TextButton(onPressed:()=>Navigator.pop(ctx),child:Text('取消')), FilledButton(onPressed:(){ var yy=int.tryParse(yearC.text)??y; setState(()=>focused=DateTime(yy,m,1)); Navigator.pop(ctx); },child:Text('跳轉'))]
      );
    }));
  }

  void editCell(DateTime d){ var noteC=TextEditingController(text: notes[k(d)]??''); var exC=TextEditingController(text: (extra[k(d)]??0).toString()); String cur=roster[k(d)]??''; showModalBottomSheet(context: context, isScrollControlled:true, builder:(ctx)=>StatefulBuilder(builder:(ctx,setM){ return Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom,left:16,right:16,top:16), child:Column(mainAxisSize:MainAxisSize.min, children:[ Text(DateFormat('yyyy-MM-dd EEEE').format(d),style:TextStyle(fontWeight:FontWeight.bold)), Wrap(spacing:6, children:[ for(var s in shifts) ChoiceChip(label:Text(s.code), selected:cur==s.code, onSelected:(v){ setM((){ cur=v?s.code:''; }); }) ]), SizedBox(height:8), TextField(controller:noteC,decoration:InputDecoration(labelText:'記事',border:OutlineInputBorder())), SizedBox(height:8), TextField(controller:exC,decoration:InputDecoration(labelText:'額外OT小時',border:OutlineInputBorder()),keyboardType:TextInputType.number), SizedBox(height:10), FilledButton(onPressed:(){ setState((){ if(cur=='') roster.remove(k(d)); else roster[k(d)]=cur; if(noteC.text=='') notes.remove(k(d)); else notes[k(d)]=noteC.text; var vv=double.tryParse(exC.text); if(vv==null||vv==0) extra.remove(k(d)); else extra[k(d)]=vv; save(); }); Navigator.pop(ctx); },child:Text('保存')), SizedBox(height:20) ])); })); }

  void createPattern(){
    TextEditingController nameC=TextEditingController(text:'自定${patterns.length+1}');
    TextEditingController rowC=TextEditingController(text:'22');
    showDialog(context: context, builder: (ctx)=>AlertDialog(title:Text('7 x 自定行數'), content:Column(mainAxisSize:MainAxisSize.min, children:[ TextField(controller:nameC,decoration:InputDecoration(labelText:'名稱')), TextField(controller:rowC,keyboardType:TextInputType.number,decoration:InputDecoration(labelText:'行數 1-100')), ]), actions:[ TextButton(onPressed:()=>Navigator.pop(ctx),child:Text('取消')), FilledButton(onPressed:(){ int rows=int.tryParse(rowC.text)??22; Navigator.pop(ctx); openPatternEditor(RosterPattern(nameC.text, List.filled(rows*7, shifts.first.code))); },child:Text('下一步')) ]));
  }
  void openPatternEditor(RosterPattern pat){ showDialog(context: context, builder: (ctx)=>StatefulBuilder(builder: (ctx,setM){ return AlertDialog(title:Text('${pat.name} ${pat.codes.length~/7}行'), content:SizedBox(width:400,height:400, child: SingleChildScrollView(child: Wrap(spacing:2, runSpacing:2, children:[ for(int i=0;i<pat.codes.length;i++) GestureDetector(onTap:(){ showModalBottomSheet(context:ctx, builder:(b)=>Wrap(children:[ for(var ss in shifts) ListTile(title:Text(ss.code), onTap:(){ setM((){ pat.codes[i]=ss.code; }); Navigator.pop(b); }) ])); }, child: Container(width:40,height:40, decoration:BoxDecoration(color:getS(pat.codes[i]).color, borderRadius:BorderRadius.circular(4)), child:Center(child:Text('${i+1}\n${pat.codes[i]}',textAlign:TextAlign.center,style:TextStyle(color:Colors.white,fontSize:10)))) ), ]))), actions:[ TextButton(onPressed:()=>Navigator.pop(ctx),child:Text('取消')), FilledButton(onPressed:(){ setState(()=>patterns.add(pat)); save(); Navigator.pop(ctx); },child:Text('保存')) ]); })); }
  void applyPattern(){ if(patterns.isEmpty){ ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('請先創造模式'))); return; } RosterPattern sel=patterns.first; DateTime sDate=DateTime(focused.year,focused.month,1); DateTime eDate=DateTime(focused.year,focused.month+1,0); showDialog(context: context, builder: (ctx)=>StatefulBuilder(builder: (ctx,setM){ return AlertDialog(title:Text('套用模式'), content:Column(mainAxisSize:MainAxisSize.min, children:[ DropdownButton<RosterPattern>(value:sel,isExpanded:true, items:[for(var p in patterns) DropdownMenuItem(value:p, child:Text(p.name))], onChanged:(v){ if(v!=null) setM((){ sel=v; }); }), ListTile(title:Text('開始 ${DateFormat('yyyy-MM-dd').format(sDate)}'), onTap:()async{ DateTime? d=await showDatePicker(context:ctx,firstDate:DateTime(1900),lastDate:DateTime(2100),initialDate:sDate); if(d!=null) setM((){ sDate=d; }); }), ListTile(title:Text('結束 ${DateFormat('yyyy-MM-dd').format(eDate)}'), onTap:()async{ DateTime? d=await showDatePicker(context:ctx,firstDate:DateTime(1900),lastDate:DateTime(2100),initialDate:eDate); if(d!=null) setM((){ eDate=d; }); }), ]), actions:[ TextButton(onPressed:()=>Navigator.pop(ctx),child:Text('取消')), FilledButton(onPressed:(){ setState((){ int idx=0; for(DateTime d=sDate;!d.isAfter(eDate); d=d.add(Duration(days:1))){ roster[k(d)]=sel.codes[idx%sel.codes.length]; idx++; } save(); }); Navigator.pop(ctx); },child:Text('開始排更')) ]); })); }

  @override Widget build(BuildContext context){
    return Scaffold(body: [buildCal(), buildReport(), buildSetting()][tab], bottomNavigationBar: NavigationBar(selectedIndex:tab,onDestinationSelected:(i)=>setState(()=>tab=i),destinations:[ NavigationDestination(icon:Icon(Icons.calendar_month),label:'月曆'), NavigationDestination(icon:Icon(Icons.bar_chart),label:'報表'), NavigationDestination(icon:Icon(Icons.settings),label:'設定') ]));
  }

  Widget buildCal(){
    DateTime first=DateTime(focused.year,focused.month,1);
    int offset=first.weekday-1;
    DateTime start=first.subtract(Duration(days:offset));
    List<DateTime> days=List.generate(42,(i)=>start.add(Duration(days:i)));
    Shift? selShift=roster.containsKey(k(selected))?getS(roster[k(selected)]!):null;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon:Icon(Icons.today), onPressed:goToday),
        title: InkWell(onTap:pickYM, child: Row(mainAxisSize:MainAxisSize.min, children:[ Text('W${isoWeek(focused)} ${focused.year}年${focused.month}月',style:TextStyle(fontSize:22,fontWeight:FontWeight.w900)), Icon(Icons.arrow_drop_down) ])),
        actions:[ IconButton(icon:Icon(Icons.grid_view), onPressed:createPattern), IconButton(icon:Icon(Icons.playlist_play), onPressed:applyPattern), IconButton(icon:Icon(Icons.share), onPressed:(){ var sb=StringBuffer(); roster.forEach((kk,v){ var d=DateTime.parse(kk); if(d.year==focused.year&&d.month==focused.month) sb.writeln('$kk,$v'); }); showDialog(context:context,builder:(c)=>AlertDialog(content:SelectableText(sb.toString()))); }) ],
      ),
      body: Column(children:[
        Row(children:[ for(var w in ['Mon','Tue','Wed','Thu','Fri','Sat','Sun']) Expanded(child:Center(child:Text(w,style:TextStyle(fontWeight:FontWeight.bold)))) ]),
        // 手勢滑動跳月 - 不用PageView
        Expanded(flex:3, child: GestureDetector(
          onPanStart:(d){ dragX=0; dragY=0; },
          onPanUpdate:(d){ dragX+=d.delta.dx; dragY+=d.delta.dy; },
          onPanEnd:(d){
            if(dragX.abs()>80 || dragY.abs()>80){
              if(dragX<-60 || dragY<-60) changeMonth(1);
              if(dragX>60 || dragY>60) changeMonth(-1);
            }
            dragX=0; dragY=0;
          },
          child: Container(
            color:Colors.white,
            child: Column(children:[
              for(int r=0;r<6;r++) Expanded(child: Row(children:[
                for(int c=0;c<7;c++)...[
                  Builder(builder: (ctx){
                    int idx=r*7+c;
                    DateTime day=days[idx];
                    bool out=day.month!=focused.month;
                    String key=k(day);
                    String? code=roster[key];
                    Shift? sh=code!=null?getS(code):null;
                    bool isToday=k(day)==k(DateTime.now());
                    bool isSel=k(day)==k(selected);
                    if(out) return Expanded(child: Container(margin:EdgeInsets.all(2), child:Center(child:Text(day.day.toString(),style:TextStyle(color:Colors.grey)))) );
                    return Expanded(child: GestureDetector(
                      onTap:(){ setState(()=>selected=day); },
                      onLongPress:(){ editCell(day); },
                      child: Container(margin:EdgeInsets.all(3), decoration:BoxDecoration(color:sh!=null?sh.color:Color(0xFFEFEFEF), borderRadius:BorderRadius.circular(10), border:isToday?Border.all(color:Colors.amber,width:3):isSel?Border.all(color:Colors.indigo,width:2):null), child:Center(child:Column(mainAxisAlignment:MainAxisAlignment.center, children:[ Text(day.day.toString(),style:TextStyle(fontSize:fs+2,fontWeight:FontWeight.bold,color:sh!=null?Colors.white:Colors.black87)), if(sh!=null) Text(sh.code,style:TextStyle(fontSize:fs-1,color:Colors.white)), if(day.weekday==1) Text('W${isoWeek(day)}',style:TextStyle(fontSize:7,color:sh!=null?Colors.white70:Colors.black54)) ])) ),
                    ));
                  })
                ]
              ]))
            ]),
          ),
        )),
        Divider(height:1),
        Expanded(flex:2, child: Container(color:Colors.white, padding:EdgeInsets.all(12), child:ListView(children:[ Row(children:[ Container(padding:EdgeInsets.symmetric(horizontal:12,vertical:6),decoration:BoxDecoration(color:selShift?.color??Colors.grey.shade300,borderRadius:BorderRadius.circular(20)),child:Text('${DateFormat('MM/dd EEEE').format(selected)} ${roster[k(selected)]??'未排'}',style:TextStyle(fontWeight:FontWeight.bold))), Spacer(), FilledButton(onPressed:(){ editCell(selected); },child:Text('編輯')) ]), if(notes[k(selected)]!=null) Card(color:Colors.amber.shade50, child:ListTile(title:Text(notes[k(selected)]!))) ]))),
      ]),
    );
  }

  Widget buildReport(){
    DateTime mon=focused; double totH=0,totOT=0,totTrans=0,totAll=0; int cWork=0;
    roster.forEach((kk,v){ var d=DateTime.parse(kk); if(d.year!=mon.year||d.month!=mon.month) return; var s=getS(v); double ex=extra[kk]??0; totH+=s.h+ex; if(s.h>0){ cWork++; totTrans+=transB; } double pay=0; if(s.code=='早') pay+=earlyB; if(s.code=='夜') pay+=nightB; if(s.code=='宵') pay+=overB; if(v=='OT'||ex>0) { double oh=(v=='OT'?s.h:0)+ex; totOT+=oh; pay+=oh*otR; } totAll+=pay; });
    totAll+=totTrans;
    return Scaffold(appBar:AppBar(title:Text('${mon.year}年${mon.month}月')), body:ListView(padding:EdgeInsets.all(16), children:[
      Card(child:ListTile(title:Text('總工時 ${totH}h 返工 $cWork日'))),
      Card(child:ListTile(title:Text('OT ${totOT}h x \$${otR}'), trailing:Text('\$${(totOT*otR).toStringAsFixed(0)}'))),
      Card(child:ListTile(title:Text('津貼總額'), trailing:Text('\$${totAll.toStringAsFixed(0)}',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold)))),
    ]));
  }

  Widget moneyInput(String label, double value, Function(double) onSave){
    TextEditingController c=TextEditingController(text:value.toString());
    return Card(child: ListTile(title:Text(label), trailing:SizedBox(width:130, child:TextField(controller:c, keyboardType:TextInputType.numberWithOptions(decimal:true), decoration:InputDecoration(prefixText:'\$', border:OutlineInputBorder(), isDense:true), onSubmitted:(v){ var vv=double.tryParse(v); if(vv!=null){ onSave(vv); save(); setState((){}); } })), subtitle:Text('輸入後按完成')));
  }

  Widget buildSetting(){
    return Scaffold(appBar:AppBar(title:Text('設定')), body:ListView(padding:EdgeInsets.all(16), children:[
      Text('津貼 (直接輸入)',style:TextStyle(fontWeight:FontWeight.bold)),
      moneyInput('OT時薪', otR, (v){ otR=v; }),
      moneyInput('早班', earlyB, (v){ earlyB=v; }),
      moneyInput('夜班', nightB, (v){ nightB=v; }),
      moneyInput('通宵', overB, (v){ overB=v; }),
      moneyInput('交通', transB, (v){ transB=v; }),
      Divider(),
      for(var p in patterns) ListTile(title:Text(p.name), subtitle:Text('${p.codes.length~/7}行'), trailing:IconButton(icon:Icon(Icons.delete), onPressed:(){ setState(()=>patterns.remove(p)); save(); })),
      FilledButton.icon(onPressed:createPattern, icon:Icon(Icons.add), label:Text('新增 7 x 自定行數')),
      FilledButton.icon(onPressed:applyPattern, icon:Icon(Icons.play_arrow), label:Text('套用排更')),
    ]));
  }
}
