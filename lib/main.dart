import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
void main()=>runApp(MaterialApp(debugShowCheckedModeBanner:false, home:MainPage()));
class Shift{ String code,name,start,end; int c; double h; bool work; Shift(this.code,this.name,this.start,this.end,this.c,this.h,this.work); Map toJson()=>{'code':code,'name':name,'start':start,'end':end,'c':c,'h':h,'work':work}; static Shift fromJson(Map m)=>Shift(m['code'],m['name'],m['start'],m['end'],m['c'],(m['h'] as num).toDouble(),m['work']); Color get color=>Color(c); }
class Allowance{ String name; String start; double amount; bool enabled; Allowance(this.name,this.start,this.amount,this.enabled); Map toJson()=>{'name':name,'start':start,'amount':amount,'enabled':enabled}; static Allowance fromJson(Map m)=>Allowance(m['name'],m['start'],(m['amount'] as num).toDouble(),m['enabled']); int get mins{ try{var p=start.split(':'); return int.parse(p[0])*60+int.parse(p[1]);}catch(_){return 0;}} }
class Pattern{ String name; List<String> codes; Pattern(this.name,this.codes); Map toJson()=>{'name':name,'codes':codes}; static Pattern fromJson(Map m)=>Pattern(m['name'], List<String>.from(m['codes'])); }
class MainPage extends StatefulWidget{ @override State<MainPage> createState()=>_S(); }
class _S extends State<MainPage>{
  int tab=0; Map<String,String> roster={}; Map<String,String> notes={}; Map<String,double> extra={};
  List<Shift> shifts=[]; List<Allowance> allowances=[]; List<Pattern> patterns=[];
  DateTime focused=DateTime.now(), selected=DateTime.now(); double otR=100, transB=20;
  _S(){
    shifts=[Shift('早','早更','07:00','15:30',0xFFFF9800,8,true),Shift('中','中更','15:00','23:30',0xFF2196F3,8,true),Shift('夜','夜更','23:00','07:30',0xFF3F51B5,8,true),Shift('宵','通宵','23:30','08:00',0xFF673AB7,8,true),Shift('O','例休','','',0xFF4CAF50,0,false),Shift('OT','OT','','',0xFF795548,4,true)];
    allowances=[Allowance('早班津貼','06:00',20,true),Allowance('中班津貼','14:00',0,true),Allowance('夜班津貼','22:00',80,true),Allowance('通宵津貼','23:30',120,true)];
  }
  String k(DateTime d)=>DateFormat('yyyy-MM-dd').format(d);
  int isoWeek(DateTime d){ var thu=d.add(Duration(days:4-d.weekday)); var jan1=DateTime(thu.year,1,1); return (thu.difference(jan1).inDays/7).floor()+1; }
  Shift getS(String c){ for(var s in shifts) if(s.code==c) return s; return Shift('','','','',0xFF9E9E9E,0,false); }
  int pMins(String t){ try{var p=t.split(':'); return int.parse(p[0])*60+int.parse(p[1]);}catch(_){return -1;} }
  double allowFor(Shift s){ if(!s.work||s.start=='') return 0; int sm=pMins(s.start); if(sm<0) return 0; Allowance? best; int bd=10000; for(var a in allowances){ if(!a.enabled) continue; int d=sm-a.mins; if(d<0) d+=1440; if(d<bd&&d<720){ bd=d; best=a; } } return best==null?0:best.amount; }
  void save() async{ var p=await SharedPreferences.getInstance(); p.setString('roster',jsonEncode(roster)); p.setString('notes',jsonEncode(notes)); p.setString('extra',jsonEncode(extra)); p.setString('shifts',jsonEncode(shifts.map((e)=>e.toJson()).toList())); p.setString('allowances',jsonEncode(allowances.map((e)=>e.toJson()).toList())); p.setString('patterns',jsonEncode(patterns.map((e)=>e.toJson()).toList())); }
  void load() async{ var p=await SharedPreferences.getInstance(); var r=p.getString('roster'); if(r!=null){ var d=jsonDecode(r); roster=(d as Map).map((k,v)=>MapEntry(k.toString(),v.toString())); } var n=p.getString('notes'); if(n!=null){ var d=jsonDecode(n); notes=(d as Map).map((k,v)=>MapEntry(k.toString(),v.toString())); } var ex=p.getString('extra'); if(ex!=null){ var d=jsonDecode(ex); extra=(d as Map).map((k,v)=>MapEntry(k.toString(),(v as num).toDouble())); } var sh=p.getString('shifts'); if(sh!=null){ var d=jsonDecode(sh) as List; shifts=d.map((e)=>Shift.fromJson(e)).toList(); } var al=p.getString('allowances'); if(al!=null){ var d=jsonDecode(al) as List; allowances=d.map((e)=>Allowance.fromJson(e)).toList(); } var pat=p.getString('patterns'); if(pat!=null){ var d=jsonDecode(pat) as List; patterns=d.map((e)=>Pattern.fromJson(e)).toList(); } setState((){}); }
  @override void initState(){ super.initState(); load(); }
  List<DateTime> days42(DateTime mon){ var first=DateTime(mon.year,mon.month,1); int off=first.weekday-1; var start=first.subtract(Duration(days:off)); return List.generate(42,(i)=>start.add(Duration(days:i))); }

  @override Widget build(BuildContext context){
    return Scaffold(body:[buildCal(),buildSetting()][tab], bottomNavigationBar:BottomNavigationBar(currentIndex:tab,onTap:(i)=>setState(()=>tab=i), items:[BottomNavigationBarItem(icon:Icon(Icons.calendar_today),label:'月曆'),BottomNavigationBarItem(icon:Icon(Icons.settings),label:'設定')]));
  }

  Widget buildCal(){
    var days=days42(focused);
    return Column(children:[
      Container(color:Colors.indigo, padding:EdgeInsets.all(8), child:SafeArea(child:Row(children:[Text('${focused.year}年${focused.month}月',style:TextStyle(color:Colors.white,fontWeight:FontWeight.bold)), Spacer(), IconButton(icon:Icon(Icons.chevron_left,color:Colors.white), onPressed:(){ setState(()=>focused=DateTime(focused.year,focused.month-1,1)); }), IconButton(icon:Icon(Icons.chevron_right,color:Colors.white), onPressed:(){ setState(()=>focused=DateTime(focused.year,focused.month+1,1)); })]))),
      Row(children:[ for(var w in ['Mon','Tue','Wed','Thu','Fri','Sat','Sun']) Expanded(child:Text(w,textAlign:TextAlign.center,style:TextStyle(fontSize:10,fontWeight:FontWeight.bold))) ]),
      // 終極安全：不用GridView，用Column+Row，零圖層
      Column(children:[
        for(int r=0;r<6;r++) Row(children:[
          for(int c=0;c<7;c++) Builder(builder:(_){
            int idx=r*7+c; DateTime day=days[idx]; bool out=day.month!=focused.month; String key=k(day); String? code=roster[key]; Shift? sh=code!=null?getS(code):null;
            if(out) return Expanded(child: Container(height:52, child:Center(child:Text(day.day.toString(),style:TextStyle(color:Colors.grey)))));
            double dayA=sh!=null?allowFor(sh)+(sh.work?transB:0):0;
            return Expanded(child: GestureDetector(onTap:(){ setState(()=>selected=day); }, onLongPress:(){
              showModalBottomSheet(context:context, builder:(ctx)=>Wrap(children:[ for(var s in shifts) ActionChip(label:Text(s.code), onPressed:(){ setState(()=>roster[key]=s.code); save(); Navigator.pop(ctx); }) ]));
            }, child: Container(height:52, color:sh!=null?sh.color:Color(0xFFE0E0E0), child:Column(children:[
              if(day.weekday==1) Text('W${isoWeek(day)}',style:TextStyle(fontSize:6)),
              Text(day.day.toString(),style:TextStyle(fontWeight:FontWeight.bold,fontSize:12,color:sh!=null?Colors.white:Colors.black)),
              if(sh!=null) Text(sh.code,style:TextStyle(fontSize:10,color:Colors.white)),
              if(dayA>0) Text('\$${dayA.toStringAsFixed(0)}',style:TextStyle(fontSize:7,color:Colors.white)),
            ]))));
          })
        ])
      ]),
      Expanded(child:Container(padding:EdgeInsets.all(8), child:Text('${DateFormat('MM/dd').format(selected)} ${roster[k(selected)]??'未排'} 津貼\$${roster[k(selected)]!=null?allowFor(getS(roster[k(selected)]!)):0} ${notes[k(selected)]??''}'))),
    ]);
  }

  Widget buildSetting(){
    var ss=shifts.length>5?shifts.sublist(0,5):shifts;
    var aa=allowances.length>5?allowances.sublist(0,5):allowances;
    return ListView(padding:EdgeInsets.all(8), children:[
      Text('班次 (5行)',style:TextStyle(fontWeight:FontWeight.bold)),
      for(var s in ss) ListTile(dense:true, title:Text('${s.code} ${s.name} ${s.start}-${s.end} \$${allowFor(s)}')),
      if(shifts.length>5) TextButton(onPressed:(){ showDialog(context:context, builder:(ctx)=>AlertDialog(title:Text('全部班次'), content:Column(children:[ for(var s in shifts) Text('${s.code} ${s.name} ') ]))); }, child:Text('查看全部 ${shifts.length}個')),
      Divider(),
      Text('津貼 (5行，可自定開始)',style:TextStyle(fontWeight:FontWeight.bold)),
      for(var a in aa) ListTile(dense:true, title:Text('${a.name} ${a.start} \$${a.amount}')),
      if(allowances.length>5) TextButton(onPressed:(){ showDialog(context:context, builder:(ctx)=>AlertDialog(title:Text('全部津貼'), content:Column(children:[ for(var a in allowances) Text('${a.name} ${a.start}') ]))); }, child:Text('查看全部')),
      ElevatedButton(onPressed:(){ TextEditingController n=TextEditingController(), s=TextEditingController(text:'06:00'), am=TextEditingController(text:'20'); showDialog(context:context, builder:(ctx)=>AlertDialog(title:Text('新增津貼'), content:Column(mainAxisSize:MainAxisSize.min, children:[TextField(controller:n,decoration:InputDecoration(labelText:'名稱')),TextField(controller:s,decoration:InputDecoration(labelText:'開始')),TextField(controller:am,decoration:InputDecoration(labelText:'金額'))]), actions:[TextButton(onPressed:(){ if(n.text!=''){ setState(()=>allowances.add(Allowance(n.text,s.text,double.tryParse(am.text)??0,true))); save(); } Navigator.pop(ctx); },child:Text('新增'))])); }, child:Text('新增津貼')),
      SizedBox(height:40),
    ]);
  }
}
