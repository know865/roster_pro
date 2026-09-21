import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main()=>runApp(MaterialApp(debugShowCheckedModeBanner:false, theme:ThemeData(useMaterial3:false), home:MainPage()));

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
  int get mins{ try{ var p=start.split(':'); return int.parse(p[0])*60+int.parse(p[1]); }catch(_){ return 0; } }
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
  int pMins(String t){ try{ var p=t.split(':'); return int.parse(p[0])*60+int.parse(p[1]); }catch(_){ return -1; } }
  double allowFor(Shift s){ if(!s.work||s.start=='') return 0; int sm=pMins(s.start); if(sm<0) return 0; Allowance? best; int bd=10000; for(var a in allowances){ if(!a.enabled) continue; int d=sm-a.mins; if(d<0) d+=1440; if(d<bd&&d<720){ bd=d; best=a; } } return best==null?0:best.amount; }
  void save() async{ var p=await SharedPreferences.getInstance(); p.setString('roster',jsonEncode(roster)); p.setString('notes',jsonEncode(notes)); p.setString('extra',jsonEncode(extra)); p.setString('shifts',jsonEncode(shifts.map((e)=>e.toJson()).toList())); p.setString('allowances',jsonEncode(allowances.map((e)=>e.toJson()).toList())); p.setString('patterns',jsonEncode(patterns.map((e)=>e.toJson()).toList())); p.setDouble('otR',otR); p.setDouble('transB',transB); p.setDouble('fs',fs); }
  void load() async{ var p=await SharedPreferences.getInstance(); var r=p.getString('roster'); if(r!=null){ var d=jsonDecode(r); roster=(d as Map).map((kk,v)=>MapEntry(kk.toString(),v.toString())); } var n=p.getString('notes'); if(n!=null){ var d=jsonDecode(n); notes=(d as Map).map((kk,v)=>MapEntry(kk.toString(),v.toString())); } var ex=p.getString('extra'); if(ex!=null){ var d=jsonDecode(ex); extra=(d as Map).map((kk,v)=>MapEntry(kk.toString(),(v as num).toDouble())); } var sh=p.getString('shifts'); if(sh!=null){ var d=jsonDecode(sh) as List; shifts=d.map((e)=>Shift.fromJson(e)).toList(); } var al=p.getString('allowances'); if(al!=null){ var d=jsonDecode(al) as List; allowances=d.map((e)=>Allowance.fromJson(e)).toList(); } var pat=p.getString('patterns'); if(pat!=null){ var d=jsonDecode(pat) as List; patterns=d.map((e)=>Pattern.fromJson(e)).toList(); } setState((){ otR=p.getDouble('otR')??100; transB=p.getDouble('transB')??20; fs=p.getDouble('fs')??11; }); }
  @override void initState(){ super.initState(); load(); }

  // 1. 無限年月 2. 一鍵返今日
  void pickYM(){
    int y=focused.year,m=focused.month; var yc=TextEditingController(text:y.toString());
    showDialog(context:context, builder:(ctx)=>StatefulBuilder(builder:(ctx,setM){
      return AlertDialog(title:Text('快速查看指定年月'), content:SizedBox(width:360,height:360, child:Column(children:[
        Row(children:[ IconButton(icon:Icon(Icons.fast_rewind), onPressed:(){ setM((){ y-=10; yc.text=y.toString(); }); }), IconButton(icon:Icon(Icons.remove), onPressed:(){ setM((){ y-=1; yc.text=y.toString(); }); }), Expanded(child:TextField(controller:yc, textAlign:TextAlign.center, keyboardType:TextInputType.number)), IconButton(icon:Icon(Icons.add), onPressed:(){ setM((){ y+=1; yc.text=y.toString(); }); }), IconButton(icon:Icon(Icons.fast_forward), onPressed:(){ setM((){ y+=10; yc.text=y.toString(); }); }), ]),
        SizedBox(height:50, child:ListView.builder(scrollDirection:Axis.horizontal, itemCount:80, itemBuilder:(c,i){ int yy=y-40+i; return Padding(padding:EdgeInsets.all(3), child:ChoiceChip(label:Text(yy.toString()), selected:yy==y, onSelected:(v){ setM((){ y=yy; yc.text=yy.toString(); }); })); })),
        Divider(),
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
        SizedBox(height:8),
        Wrap(spacing:6, children:[ for(var s in shifts) ChoiceChip(label:Text(s.code), selected:cur==s.code, onSelected:(v){ setM(()=>cur=v?s.code:''); }) ]),
        TextField(controller:noteC, decoration:InputDecoration(labelText:'記事')),
        TextField(controller:exC, decoration:InputDecoration(labelText:'額外OT小時'), keyboardType:TextInputType.numberWithOptions(decimal:true)),
        SizedBox(height:10),
        FilledButton(onPressed:(){ setState((){ if(cur=='') roster.remove(k(d)); else roster[k(d)]=cur; if(noteC.text=='') notes.remove(k(d)); else notes[k(d)]=noteC.text; var vv=double.tryParse(exC.text); if(vv==null||vv==0) extra.remove(k(d)); else extra[k(d)]=vv; save(); }); Navigator.pop(ctx); }, child:Text('保存')),
        SizedBox(height:20),
      ]));
    }));
  }

  void editShiftDialog(Shift? old){
    var codeC=TextEditingController(text:old?.code??''); var nameC=TextEditingController(text:old?.name??''); var stC=TextEditingController(text:old?.start??'07:00'); var enC=TextEditingController(text:old?.end??'15:30'); var hC=TextEditingController(text:(old?.h??8).toString()); bool work=old?.work??true;
    showDialog(context:context, builder:(ctx)=>StatefulBuilder(builder:(ctx,setM){
      return AlertDialog(title:Text(old==null?'新增班次':'編輯班次'), content:Column(mainAxisSize:MainAxisSize.min, children:[
        TextField(controller:codeC, decoration:InputDecoration(labelText:'代號')),
        TextField(controller:nameC, decoration:InputDecoration(labelText:'名稱')),
        Row(children:[ Expanded(child:TextField(controller:stC, decoration:InputDecoration(labelText:'開始 HH:MM'))), SizedBox(width:8), Expanded(child:TextField(controller:enC, decoration:InputDecoration(labelText:'結束'))), ]),
        TextField(controller:hC, decoration:InputDecoration(labelText:'時數'), keyboardType:TextInputType.number),
        CheckboxListTile(title:Text('有交通'), value:work, onChanged:(v){ setM(()=>work=v!); }),
      ]), actions:[ TextButton(onPressed:()=>Navigator.pop(ctx), child:Text('取消')), FilledButton(onPressed:(){ if(codeC.text=='') return; setState((){ var ns=Shift(codeC.text, nameC.text==''?codeC.text:nameC.text, stC.text, enC.text, old?.c??0xFFFF9800, double.tryParse(hC.text)??8, work); if(old==null) shifts.add(ns); else { int idx=shifts.indexOf(old); shifts[idx]=ns; } save(); }); Navigator.pop(ctx); }, child:Text('保存')) ]
      );
    }));
  }

  void editAllowDialog(Allowance? old){
    var nC=TextEditingController(text:old?.name??''); var sC=TextEditingController(text:old?.start??'06:00'); var aC=TextEditingController(text:(old?.amount??0).toString()); bool en=old?.enabled??true;
    showDialog(context:context, builder:(ctx)=>StatefulBuilder(builder:(ctx,setM){
      return AlertDialog(title:Text(old==null?'新增津貼':'編輯津貼'), content:Column(mainAxisSize:MainAxisSize.min, children:[
        TextField(controller:nC, decoration:InputDecoration(labelText:'津貼名稱')),
        TextField(controller:sC, decoration:InputDecoration(labelText:'開始時間 HH:MM')),
        TextField(controller:aC, decoration:InputDecoration(labelText:'金額'), keyboardType:TextInputType.number),
        CheckboxListTile(title:Text('啟用'), value:en, onChanged:(v){ setM(()=>en=v!); }),
        Text('自動判斷：班次開始時間最接近此時間',style:TextStyle(fontSize:10,color:Colors.grey)),
      ]), actions:[ TextButton(onPressed:()=>Navigator.pop(ctx), child:Text('取消')), FilledButton(onPressed:(){ if(nC.text=='') return; setState((){ var na=Allowance(nC.text, sC.text, double.tryParse(aC.text)??0, en); if(old==null) allowances.add(na); else { int idx=allowances.indexOf(old); allowances[idx]=na; } save(); }); Navigator.pop(ctx); }, child:Text('保存')) ]
      );
    }));
  }

  void createPattern(){
    var nameC=TextEditingController(text:'自定${patterns.length+1}'); var rowC=TextEditingController(text:'22');
    showDialog(context:context, builder:(ctx)=>AlertDialog(title:Text('頂部 7天 x 自定行數'), content:Column(mainAxisSize:MainAxisSize.min, children:[
      TextField(controller:nameC, decoration:InputDecoration(labelText:'名稱')),
      TextField(controller:rowC, decoration:InputDecoration(labelText:'行數 1-100'), keyboardType:TextInputType.number),
    ]), actions:[ TextButton(onPressed:()=>Navigator.pop(ctx), child:Text('取消')), FilledButton(onPressed:(){ int rows=int.tryParse(rowC.text)??22; if(rows<1) rows=1; if(rows>100) rows=100; Navigator.pop(ctx); openPatternEditor(Pattern(nameC.text, List.filled(rows*7, shifts.first.code))); }, child:Text('下一步')) ]
    ));
  }
  void openPatternEditor(Pattern pat){
    showDialog(context:context, builder:(ctx)=>StatefulBuilder(builder:(ctx,setM){
      return AlertDialog(title:Text('${pat.name} ${pat.codes.length~/7}行'), content:SizedBox(width:400,height:420, child:GridView.builder(gridDelegate:SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:7, childAspectRatio:0.9), itemCount:pat.codes.length, itemBuilder:(c,i){
        String code=pat.codes[i]; var s=getS(code);
        return GestureDetector(onTap:(){ showModalBottomSheet(context:ctx, builder:(b)=>Container(padding:EdgeInsets.all(12), child:Wrap(spacing:8, children:[ for(var ss in shifts) ChoiceChip(label:Text(ss.code), selected:ss.code==code, onSelected:(v){ setM(()=>pat.codes[i]=ss.code); Navigator.pop(b); }) ]))); }, child:Container(margin:EdgeInsets.all(2), color:s.color, child:Center(child:Text(code,style:TextStyle(color:Colors.white,fontWeight:FontWeight.bold)))));
      })), actions:[ TextButton(onPressed:()=>Navigator.pop(ctx), child:Text('取消')), FilledButton(onPressed:(){ setState(()=>patterns.add(pat)); save(); Navigator.pop(ctx); }, child:Text('保存')) ]
      );
    }));
  }
  void applyPattern(){
    if(patterns.isEmpty){ ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('請先新增模式'))); return; }
    Pattern sel=patterns.first; DateTime sD=DateTime(focused.year,focused.month,1); DateTime eD=DateTime(focused.year,focused.month+1,0);
    showDialog(context:context, builder:(ctx)=>StatefulBuilder(builder:(ctx,setM){
      return AlertDialog(title:Text('根據指定開始結束日期排更'), content:Column(mainAxisSize:MainAxisSize.min, children:[
        DropdownButton<Pattern>(value:sel, isExpanded:true, items:[ for(var p in patterns) DropdownMenuItem(value:p, child:Text(p.name)) ], onChanged:(v){ if(v!=null) setM(()=>sel=v); }),
        ListTile(title:Text('開始 ${DateFormat('yyyy-MM-dd').format(sD)}'), onTap:()async{ DateTime? d=await showDatePicker(context:ctx, firstDate:DateTime(1900), lastDate:DateTime(2100), initialDate:sD); if(d!=null) setM(()=>sD=d); }),
        ListTile(title:Text('結束 ${DateFormat('yyyy-MM-dd').format(eD)}'), onTap:()async{ DateTime? d=await showDatePicker(context:ctx, firstDate:DateTime(1900), lastDate:DateTime(2100), initialDate:eD); if(d!=null) setM(()=>eD=d); }),
      ]), actions:[ TextButton(onPressed:()=>Navigator.pop(ctx),
