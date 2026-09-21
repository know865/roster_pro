import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main()=>runApp(MaterialApp(debugShowCheckedModeBanner:false, theme:ThemeData(useMaterial3:false, scaffoldBackgroundColor:Colors.white), home:MainPage()));

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
  int get mins{ try{var p=start.split(':'); return int.parse(p[0])*60+int.parse(p[1]);}catch(_){return 0;} }
}
class Pattern{ String name; List<String> codes; Pattern(this.name,this.codes); Map toJson()=>{'name':name,'codes':codes}; static Pattern fromJson(Map m)=>Pattern(m['name'], List<String>.from(m['codes'])); }

class MainPage extends StatefulWidget{ @override State<MainPage> createState()=>_S(); }
class _S extends State<MainPage>{
  int tab=0;
  Map<String,String> roster={}, notes={}; Map<String,double> extra={};
  List<Shift> shifts=[]; List<Allowance> allowances=[]; List<Pattern> patterns=[];
  DateTime focused=DateTime.now(), selected=DateTime.now();
  double otR=100, transB=20, fs=11;

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
  int pMins(String t){ try{var p=t.split(':'); return int.parse(p[0])*60+int.parse(p[1]);}catch(_){return -1;} }
  double allowFor(Shift s){
    if(!s.work||s.start=='') return 0;
    int sm=pMins(s.start); if(sm<0) return 0;
    Allowance? best; int diffBest=10000;
    for(var a in allowances){ if(!a.enabled) continue; int d=sm-a.mins; if(d<0) d+=1440; if(d<diffBest && d<720){ diffBest=d; best=a; } }
    return best==null?0:best.amount;
  }
  void save() async{ var p=await SharedPreferences.getInstance(); p.setString('roster',jsonEncode(roster)); p.setString('notes',jsonEncode(notes)); p.setString('extra',jsonEncode(extra)); p.setString('shifts',jsonEncode(shifts.map((e)=>e.toJson()).toList())); p.setString('allowances',jsonEncode(allowances.map((e)=>e.toJson()).toList())); p.setString('patterns',jsonEncode(patterns.map((e)=>e.toJson()).toList())); p.setDouble('otR',otR); p.setDouble('transB',transB); }
  void load() async{ var p=await SharedPreferences.getInstance(); var r=p.getString('roster'); if(r!=null){ var d=jsonDecode(r); roster=(d as Map).map((k,v)=>MapEntry(k.toString(),v.toString())); } var n=p.getString('notes'); if(n!=null){ var d=jsonDecode(n); notes=(d as Map).map((k,v)=>MapEntry(k.toString(),v.toString())); } var ex=p.getString('extra'); if(ex!=null){ var d=jsonDecode(ex); extra=(d as Map).map((k,v)=>MapEntry(k.toString(),(v as num).toDouble())); } var sh=p.getString('shifts'); if(sh!=null){ var d=jsonDecode(sh) as List; shifts=d.map((e)=>Shift.fromJson(e)).toList(); } var al=p.getString('allowances'); if(al!=null){ var d=jsonDecode(al) as List; allowances=d.map((e)=>Allowance.fromJson(e)).toList(); } var pat=p.getString('patterns'); if(pat!=null){ var d=jsonDecode(pat) as List; patterns=d.map((e)=>Pattern.fromJson(e)).toList(); } setState((){ otR=p.getDouble('otR')??100; transB=p.getDouble('transB')??20; }); }
  @override void initState(){ super.initState(); load(); }

  List<DateTime> days42(DateTime mon){ var first=DateTime(mon.year,mon.month,1); int off=first.weekday-1; var start=first.subtract(Duration(days:off)); return List.generate(42,(i)=>start.add(Duration(days:i))); }

  void pickYM(){
    int y=focused.year,m=focused.month; TextEditingController yc=TextEditingController(text:y.toString());
    showDialog(context: context, builder:(ctx)=>StatefulBuilder(builder:(ctx,setM){
      return AlertDialog(title:Text('選擇年月'), content:Column(mainAxisSize:MainAxisSize.min, children:[
        Row(children:[ IconButton(onPressed:(){ setM((){ y-=10; yc.text=y.toString(); }); }, icon:Icon(Icons.fast_rewind)), IconButton(onPressed:(){ setM((){ y-=1; yc.text=y.toString(); }); }, icon:Icon(Icons.remove)), Expanded(child:TextField(controller:yc,textAlign:TextAlign.center)), IconButton(onPressed:(){ setM((){ y+=1; yc.text=y.toString(); }); }, icon:Icon(Icons.add)), IconButton(onPressed:(){ setM((){ y+=10; yc.text=y.toString(); }); }, icon:Icon(Icons.fast_forward)), ]),
        Wrap(children:[ for(int mm=1;mm<=12;mm++) ChoiceChip(label:Text('${mm}月'), selected:m==mm, onSelected:(v){ setM(()=>m=mm; }) ]),
      ]), actions:[ TextButton(onPressed:()=>Navigator.pop(ctx),child:Text('取消')), FilledButton(onPressed:(){ int? yy=int.tryParse(yc.text); if(yy!=null) y=yy; setState(()=>focused=DateTime(y,m,1)); Navigator.pop(ctx); },child:Text('跳轉')) ]
    ); }));
  }

  void editCell(DateTime d){
    TextEditingController noteC=TextEditingController(text:notes[k(d)]??'');
    TextEditingController exC=TextEditingController(text:(extra[k(d)]??0).toString());
    String cur=roster[k(d)]??'';
    showModalBottomSheet(context: context, isScrollControlled:true, builder:(ctx)=>Padding(padding:EdgeInsets.only(bottom:MediaQuery.of(ctx).viewInsets.bottom), child:Container(color:Colors.white, padding:EdgeInsets.all(16), child:Column(mainAxisSize:MainAxisSize.min, children:[
      Text(DateFormat('yyyy-MM-dd EEEE').format(d)),
      Wrap(spacing:6, children:[ for(var s in shifts) ChoiceChip(label:Text(s.code), selected:cur==s.code, onSelected:(v){ setState(()=>roster[k(d)]=s.code); save(); Navigator.pop(ctx); }) ]),
      TextField(controller:noteC, decoration:InputDecoration(labelText:'記事')),
      TextField(controller:exC, decoration:InputDecoration(labelText:'額外OT小時'), keyboardType:TextInputType.number),
      FilledButton(onPressed:(){ setState((){ notes[k(d)]=noteC.text; var vv=double.tryParse(exC.text); if(vv!=null) extra[k(d)]=vv; save(); }); Navigator.pop(ctx); }, child:Text('保存')),
    ]))));
  }

  @override Widget build(BuildContext context){
    return Scaffold(
      body:[buildCal(),buildReport(),buildSetting()][tab],
      bottomNavigationBar:BottomNavigationBar(currentIndex:tab,onTap:(i)=>setState(()=>tab=i), items:[BottomNavigationBarItem(icon:Icon(Icons.calendar_today),label:'月曆'),BottomNavigationBarItem(icon:Icon(Icons.bar_chart),label:'報表'),BottomNavigationBarItem(icon:Icon(Icons.settings),label:'設定')]),
    );
  }

  Widget buildCal(){
    var days=days42(focused);
    return Column(children:[
      Container(color:Colors.indigo, height:56, child:SafeArea(child:Row(children:[
        IconButton(icon:Icon(Icons.today,color:Colors.white), onPressed:(){ setState(()=>focused=DateTime.now()); }),
        GestureDetector(onTap:pickYM, child:Text('${focused.year}年${focused.month}月',style:TextStyle(color:Colors.white,fontSize:18,fontWeight:FontWeight.bold))),
        Spacer(),
        IconButton(icon:Icon(Icons.chevron_left,color:Colors.white), onPressed:(){ setState(()=>focused=DateTime(focused.year,focused.month-1,1)); }),
        IconButton(icon:Icon(Icons.chevron_right,color:Colors.white), onPressed:(){ setState(()=>focused=DateTime(focused.year,focused.month+1,1)); }),
      ]))),
      Container(color:Color(0xFFEEEEEE), child:Row(children:[ for(var w in ['Mon','Tue','Wed','Thu','Fri','Sat','Sun']) Expanded(child:Center(child:Text(w,style:TextStyle(fontSize:11,fontWeight:FontWeight.bold)))) ])),
      // 用Table代替GridView，Impeller最安全
      Table(children:[
        for(int row=0;row<6;row++) TableRow(children:[
          for(int col=0;col<7;col++) Builder(builder:(ctx){
            int idx=row*7+col; DateTime day=days[idx]; bool out=day.month!=focused.month; String key=k(day); String? code=roster[key]; Shift? sh=code!=null?getS(code):null; bool isSel=k(day)==k(selected); bool isToday=k(day)==k(DateTime.now()); bool isMon=day.weekday==1;
            if(out) return Container(height:58, color:Colors.white, child:Center(child:Text(day.day.toString(),style:TextStyle(color:Colors.grey))));
            Color bg=sh!=null?sh.color:Color(0xFFE0E0E0); if(isSel) bg=Color(0xFF303F9F); if(isToday) bg=Color(0xFFFFC107);
            double dayA=sh!=null?allowFor(sh)+(sh.work?transB:0):0;
            return GestureDetector(onTap:(){ setState(()=>selected=day); }, onLongPress:()=>editCell(day), child:Container(height:58, color:bg, child:Column(children:[
              if(isMon) Align(alignment:Alignment.topLeft, child:Container(color:Colors.black54, padding:EdgeInsets.symmetric(horizontal:2), child:Text('W${isoWeek(day)}',style:TextStyle(color:Colors.white,fontSize:6)))),
              Text(day.day.toString(),style:TextStyle(fontWeight:FontWeight.bold,color:sh!=null?Colors.white:Colors.black,fontSize:12)),
              if(sh!=null) Text(sh.code,style:TextStyle(color:Colors.white,fontSize:10)),
              if(sh!=null && dayA>0) Text('\$${dayA.toStringAsFixed(0)}',style:TextStyle(color:Colors.white,fontSize:7)),
            ])));
          }),
        ]),
      ]),
      Expanded(child:Container(color:Colors.white, padding:EdgeInsets.all(8), child: Builder(builder:(ctx){
        Shift? sel=roster.containsKey(k(selected))?getS(roster[k(selected)]!):null;
        if(sel==null) return Text('${DateFormat('MM/dd').format(selected)} 未排');
        return Text('${DateFormat('MM/dd EEEE').format(selected)} ${sel.code} ${sel.start}-${sel.end} 津貼 \$${allowFor(sel)} + 交通 \$${sel.work?transB:0} = \$${(allowFor(sel)+(sel.work?transB:0)).toStringAsFixed(0)} ${notes[k(selected)]??''}');
      }))),
    ]);
  }

  Widget buildReport(){
    DateTime mon=focused; double totH=0,totA=0,totTrans=0; int cWork=0;
    roster.forEach((kk,v){ var d=DateTime.parse(kk); if(d.year!=mon.year||d.month!=mon.month) return; var s=getS(v); totH+=s.h; if(s.work){ cWork++; totTrans+=transB; } totA+=allowFor(s); });
    return ListView(padding:EdgeInsets.all(12), children:[
      Container(color:Colors.indigo, height:48, child:Center(child:Text('${mon.year}年${mon.month}月 報表',style:TextStyle(color:Colors.white,fontWeight:FontWeight.bold)))),
      ListTile(title:Text('返工 $cWork日 工時 ${totH}h')),
      ListTile(title:Text('津貼 (按開始時間自動計)'), trailing:Text('\$${totA.toStringAsFixed(0)}')),
      ListTile(title:Text('交通'), trailing:Text('\$${totTrans.toStringAsFixed(0)}')),
      ListTile(title:Text('總額',style:TextStyle(fontWeight:FontWeight.bold)), trailing:Text('\$${(totA+totTrans).toStringAsFixed(0)}',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold))),
    ]);
  }

  Widget buildSetting(){
    var showShifts=shifts.length>5?shifts.sublist(0,5):shifts;
    var showAllows=allowances.length>5?allowances.sublist(0,5):allowances;
    return ListView(padding:EdgeInsets.all(8), children:[
      Container(color:Colors.black, padding:EdgeInsets.all(6), child:Text('自定班次 (只顯示5行)',style:TextStyle(color:Colors.white,fontWeight:FontWeight.bold))),
      Column(children:[
        for(var s in showShifts) Container(color:Colors.white, child:ListTile(leading:Container(width:24,height:24,color:s.color,child:Center(child:Text(s.code,style:TextStyle(color:Colors.white,fontSize:10)))), title:Text('${s.code} ${s.name} ${s.start}-${s.end} 自動\$${allowFor(s)}',style:TextStyle(fontSize:12)))),
        if(shifts.length>5) TextButton(onPressed:(){ showDialog(context:context, builder:(ctx)=>AlertDialog(title:Text('全部班次'), content:SizedBox(width:300,height:300, child:ListView(children:[for(var s in shifts) ListTile(title:Text('${s.code} ${s.name}'))])))); }, child:Text('還有 ${shifts.length-5}個 查看全部')),
        ElevatedButton(onPressed:(){ TextEditingController c=TextEditingController(),n=TextEditingController(),st=TextEditingController(text:'07:00'),en=TextEditingController(text:'15:00'); showDialog(context:context, builder:(ctx)=>AlertDialog(title:Text('新增班次'), content:Column(mainAxisSize:MainAxisSize.min, children:[TextField(controller:c,decoration:InputDecoration(labelText:'代號')),TextField(controller:n,decoration:InputDecoration(labelText:'名稱')),TextField(controller:st,decoration:InputDecoration(labelText:'開始')),TextField(controller:en,decoration:InputDecoration(labelText:'結束'))]), actions:[TextButton(onPressed:(){ if(c.text!=''){ setState(()=>shifts.add(Shift(c.text,n.text,st.text,en.text,0xFFFF9800,8,true))); save(); } Navigator.pop(ctx); },child:Text('新增'))])); }, child:Text('新增班次')),
      ]),
      SizedBox(height:12),
      Container(color:Colors.black, padding:EdgeInsets.all(6), child:Text('津貼設定 (可自定開始時間)',style:TextStyle(color:Colors.white,fontWeight:FontWeight.bold))),
      Column(children:[
        for(var a in showAllows) Container(color:Colors.white, child:ListTile(title:Text('${a.name} 開始${a.start} \$${a.amount}',style:TextStyle(fontSize:12)), trailing:IconButton(icon:Icon(Icons.edit,size:16), onPressed:(){
          TextEditingController nc=TextEditingController(text:a.name), sc=TextEditingController(text:a.start), ac=TextEditingController(text:a.amount.toString());
          showDialog(context:context, builder:(ctx)=>AlertDialog(title:Text('編輯津貼'), content:Column(mainAxisSize:MainAxisSize.min, children:[TextField(controller:nc,decoration:InputDecoration(labelText:'名稱')),TextField(controller:sc,decoration:InputDecoration(labelText:'開始 HH:MM')),TextField(controller:ac,decoration:InputDecoration(labelText:'金額'),keyboardType:TextInputType.number)]), actions:[TextButton(onPressed:(){ setState(()=>a.name=nc.text); a.start=sc.text; a.amount=double.tryParse(ac.text)??a.amount; save(); Navigator.pop(ctx); },child:Text('保存'))]));
        }))),
        if(allowances.length>5) TextButton(onPressed:(){ showDialog(context:context, builder:(ctx)=>AlertDialog(title:Text('全部津貼'), content:SizedBox(width:300,height:300, child:ListView(children:[for(var a in allowances) ListTile(title:Text('${a.name} ${a.start}'))])))); }, child:Text('還有 ${allowances.length-5}個')),
        Row(children:[ Expanded(child:ElevatedButton(onPressed:(){ TextEditingController nc=TextEditingController(), sc=TextEditingController(text:'06:00'), ac=TextEditingController(text:'20'); showDialog(context:context, builder:(ctx)=>AlertDialog(title:Text('新增津貼'), content:Column(mainAxisSize:MainAxisSize.min, children:[TextField(controller:nc,decoration:InputDecoration(labelText:'名稱')),TextField(controller:sc,decoration:InputDecoration(labelText:'開始 HH:MM')),TextField(controller:ac,decoration:InputDecoration(labelText:'金額'))]), actions:[TextButton(onPressed:(){ if(nc.text!=''){ setState(()=>allowances.add(Allowance(nc.text,sc.text,double.tryParse(ac.text)??0,true))); save(); } Navigator.pop(ctx); },child:Text('新增'))])); }, child:Text('新增津貼'))), SizedBox(width:8), Expanded(child:OutlinedButton(onPressed:(){ setState(()=>allowances=[Allowance('早班津貼','06:00',20,true),Allowance('中班津貼','14:00',0,true),Allowance('夜班津貼','22:00',80,true),Allowance('通宵津貼','23:30',120,true)]); save(); }, child:Text('重置'))), ]),
      ]),
      Divider(),
      ListTile(title:Text('交通 \$${transB}'), trailing:SizedBox(width:80, child:TextField(keyboardType:TextInputType.number, decoration:InputDecoration(border:OutlineInputBorder()), onSubmitted:(v){ double? vv=double.tryParse(v); if(vv!=null){ setState(()=>transB=vv); save(); } }))),
      ListTile(title:Text('OT時薪 \$${otR}'), trailing:SizedBox(width:80, child:TextField(keyboardType:TextInputType.number, decoration:InputDecoration(border:OutlineInputBorder()), onSubmitted:(v){ double? vv=double.tryParse(v); if(vv!=null){ setState(()=>otR=vv); save(); } }))),
      for(var p in patterns) ListTile(title:Text(p.name), subtitle:Text('${p.codes.length~/7}行')),
      ElevatedButton(onPressed:(){ TextEditingController nc=TextEditingController(text:'自定${patterns.length+1}'), rc=TextEditingController(text:'22'); showDialog(context:context, builder:(ctx)=>AlertDialog(title:Text('7 x 行數'), content:Column(mainAxisSize:MainAxisSize.min, children:[TextField(controller:nc),TextField(controller:rc,keyboardType:TextInputType.number)]), actions:[TextButton(onPressed:(){ int rows=int.tryParse(rc.text)??22; Navigator.pop(ctx); var pat=Pattern(nc.text,List.filled(rows*7,shifts.first.code)); showDialog(context:context, builder:(ctx2)=>StatefulBuilder(builder:(ctx2,setM){ return AlertDialog(title:Text(pat.name), content:SizedBox(width:320,height:360, child:GridView.builder(gridDelegate:SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:7), itemCount:pat.codes.length, itemBuilder:(c,i){ return GestureDetector(onTap:(){ showModalBottomSheet(context:ctx2, builder:(b)=>Wrap(children:[for(var s in shifts) ChoiceChip(label:Text(s.code), selected:pat.codes[i]==s.code, onSelected:(v){ setM(()=>pat.codes[i]=s.code); Navigator.pop(b); })])); }, child:Container(color:getS(pat.codes[i]).color, margin:EdgeInsets.all(1), child:Center(child:Text(pat.codes[i],style:TextStyle(color:Colors.white))))); })), actions:[TextButton(onPressed:(){ setState(()=>patterns.add(pat)); save(); Navigator.pop(ctx2); },child:Text('保存'))]); })); },child:Text('下一步'))])); }, child:Text('新增模式 7 x 自定行數')),
      ElevatedButton(onPressed:(){ if(patterns.isEmpty) return; var sel=patterns.first; DateTime sD=DateTime(focused.year,focused.month,1), eD=DateTime(focused.year,focused.month+1,0); showDialog(context:context, builder:(ctx)=>StatefulBuilder(builder:(ctx,setM){ return AlertDialog(title:Text('套用模式'), content:DropdownButton<Pattern>(value:sel, isExpanded:true, items:[for(var p in patterns) DropdownMenuItem(value:p,child:Text(p.name))], onChanged:(v){ if(v!=null) setM(()=>sel=v); }), actions:[TextButton(onPressed:(){ setState((){ int idx=0; for(DateTime d=sD;!d.isAfter(eD); d=d.add(Duration(days:1))){ roster[k(d)]=sel.codes[idx%sel.codes.length]; idx++; } save(); }); Navigator.pop(ctx); },child:Text('開始'))]); })); }, child:Text('套用排更')),
      SizedBox(height:40),
    ]);
  }
}
