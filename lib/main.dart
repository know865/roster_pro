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
  double fs=11, otR=100, transB=20;

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
  void save() async{ var p=await SharedPreferences.getInstance(); p.setString('roster',jsonEncode(roster)); p.setString('notes',jsonEncode(notes)); p.setString('extra',jsonEncode(extra)); p.setString('shifts',jsonEncode(shifts.map((e)=>e.toJson()).toList())); p.setString('patterns',jsonEncode(patterns.map((e)=>e.toJson()).toList())); p.setDouble('otR',otR); p.setDouble('transB',transB); p.setDouble('fs',fs); }
  void load() async{ var p=await SharedPreferences.getInstance(); var r=p.getString('roster'); if(r!=null){ var d=jsonDecode(r); roster=(d as Map).map((k,v)=>MapEntry(k.toString(),v.toString())); } var sh=p.getString('shifts'); if(sh!=null){ var d=jsonDecode(sh) as List; shifts=d.map((e)=>Shift.fromJson(e)).toList(); } var n=p.getString('notes'); if(n!=null){ var d=jsonDecode(n); notes=(d as Map).map((k,v)=>MapEntry(k.toString(),v.toString())); } var ex=p.getString('extra'); if(ex!=null){ var d=jsonDecode(ex); extra=(d as Map).map((k,v)=>MapEntry(k.toString(),(v as num).toDouble())); } var pat=p.getString('patterns'); if(pat!=null){ var d=jsonDecode(pat) as List; patterns=d.map((e)=>RosterPattern.fromJson(e)).toList(); } setState((){ otR=p.getDouble('otR')??100; transB=p.getDouble('transB')??20; fs=p.getDouble('fs')??11; }); }
  @override void initState(){ super.initState(); load(); }
  void goToday(){ setState((){ focused=DateTime.now(); selected=DateTime.now(); }); }
  void changeMonth(int add){ setState(()=>focused=DateTime(focused.year,focused.month+add,1)); }

  void pickYM(){
    int y=focused.year,m=focused.month;
    TextEditingController yearC=TextEditingController(text:y.toString());
    showDialog(context: context, builder: (ctx)=>StatefulBuilder(builder: (ctx,setM){
      return AlertDialog(
        title: Text('選擇年月 無限遠',style:TextStyle(fontSize:22,fontWeight:FontWeight.w900)),
        content: SizedBox(width:340,height:400, child: Column(children:[
          Row(children:[
            IconButton(onPressed:(){ setM((){ y-=10; yearC.text=y.toString(); }); }, icon:Icon(Icons.fast_rewind)),
            IconButton(onPressed:(){ setM((){ y-=1; yearC.text=y.toString(); }); }, icon:Icon(Icons.remove)),
            Expanded(child: TextField(controller:yearC, textAlign:TextAlign.center, keyboardType:TextInputType.number, style:TextStyle(fontSize:20,fontWeight:FontWeight.bold), decoration:InputDecoration(labelText:'年份無限', border:OutlineInputBorder()), onChanged:(v){ int? yy=int.tryParse(v); if(yy!=null) setM((){ y=yy; }); })),
            IconButton(onPressed:(){ setM((){ y+=1; yearC.text=y.toString(); }); }, icon:Icon(Icons.add)),
            IconButton(onPressed:(){ setM((){ y+=10; yearC.text=y.toString(); }); }, icon:Icon(Icons.fast_forward)),
          ]),
          SizedBox(height:8),
          SizedBox(height:50, child: ListView.builder(scrollDirection:Axis.horizontal, itemCount:80, itemBuilder:(c,i){ int yy=y-40+i; return Padding(padding:EdgeInsets.all(3), child: ChoiceChip(label:Text(yy.toString()), selected:yy==y, onSelected:(v){ setM((){ y=yy; yearC.text=yy.toString(); }); })); })),
          Divider(),
          GridView.count(shrinkWrap:true, crossAxisCount:4, childAspectRatio:1.8, children:[ for(int mm=1;mm<=12;mm++) Padding(padding:EdgeInsets.all(4), child: ChoiceChip(label: SizedBox(width:40, child:Center(child:Text('${mm}月'))), selected:m==mm, onSelected:(v){ setM((){ m=mm; }); })) ]),
        ])),
        actions:[ TextButton(onPressed:()=>Navigator.pop(ctx),child:Text('取消')), FilledButton(onPressed:(){ int? yy=int.tryParse(yearC.text); if(yy!=null) y=yy; setState(()=>focused=DateTime(y,m,1)); Navigator.pop(ctx); },child:Text('跳轉'))]
      );
    }));
  }

  void editCell(DateTime d){ var noteC=TextEditingController(text: notes[k(d)]??''); var exC=TextEditingController(text
