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
  DateTime focused=DateTime.now(), selected=DateTime.now(), reportMonth=DateTime.now();
  double otR=100, transB=20, fs=11;
  final double cellH=62;

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
  String allowNameFor(Shift s){ if(!s.work||s.start=='') return ''; int sm=pMins(s.start); if(sm<0) return ''; Allowance? best; int bd=10000; for(var a in allowances){ if(!a.enabled) continue; int d=sm-a.mins; if(d<0) d+=1440; if(d<bd&&d<720){ bd=d; best=a; } } return best==null?'':best.name; }
  void save() async{ var p=await SharedPreferences.getInstance(); p.setString('roster',jsonEncode(roster)); p.setString('notes',jsonEncode(notes)); p.setString('extra',jsonEncode(extra)); p.setString('shifts',jsonEncode(shifts.map((e)=>e.toJson()).toList())); p.setString('allowances',jsonEncode(allowances.map((e)=>e.toJson()).toList())); p.setString('patterns',jsonEncode(patterns.map((e)=>e.toJson()).toList())); p.setDouble('otR',otR); p.setDouble('transB',transB); p.setDouble('fs',fs); }
  void load() async{ var p=await SharedPreferences.getInstance(); var r=p.getString('roster'); if(r!=null){ var d=jsonDecode(r); roster=(d as Map).map((kk,v)=>MapEntry(kk.toString(),v.toString())); } var n=p.getString('notes'); if(n!=null){ var d=jsonDecode(n); notes=(d as Map).map((kk,v)=>MapEntry(kk.toString(),v.toString())); } var ex=p.getString('extra'); if(ex!=null){ var d=jsonDecode(ex); extra=(d as Map).map((kk,v)=>MapEntry(kk.toString(),(v as num).toDouble())); } var sh=p.getString('shifts'); if(sh!=null){ var d=jsonDecode(sh) as List; shifts=d.map((e)=>Shift.fromJson(e)).toList(); } var al=p.getString('allowances'); if(al!=null){ var d=jsonDecode(al) as List; allowances=d.map((e)=>Allowance.fromJson(e)).toList(); } var pat=p.getString('patterns'); if(pat!=null){ var d=jsonDecode(pat) as List; patterns=d.map((e)=>Pattern.fromJson(e)).toList(); } setState((){ otR=p.getDouble('otR')??100; transB=p.getDouble('transB')??20; fs=p.getDouble('fs')??11; reportMonth=focused; }); }
  @override void initState(){ super.initState(); load(); }
  List<DateTime> days42(DateTime mon){ var first=DateTime(mon.year,mon.month,1); int off=first.weekday-1; var start=first.subtract(Duration(days:off)); return List.generate(42,(i)=>start.add(Duration(days:i))); }

  void pickYM(Function(DateTime) onPick, DateTime init){
    int y=init.year,m=init.month; var yc=TextEditingController(text:y.toString());
    showDialog(context:context, builder:(ctx)=>StatefulBuilder(builder:(ctx,setM){
      return AlertDialog(title:Text('選擇年月'), content:Column(mainAxisSize:MainAxisSize.min, children:[
        Row(children:[ IconButton(icon:Icon(Icons.remove), onPressed:(){ setM((){ y-=1; yc.text=y.toString(); }); }), Expanded(child:TextField(controller:yc, textAlign:TextAlign.center)), IconButton(icon:Icon(Icons.add), onPressed:(){ setM((){ y+=1; yc.text=y.toString(); }); }) ]),
        Wrap(spacing:4, runSpacing:4, children:[ for(int mm=1;mm<=12;mm++) ChoiceChip(label:Text('${mm}月'), selected:m==mm, onSelected:(v){ setM(()=>m=mm); }) ]),
      ]), actions:[ TextButton(onPressed:()=>Navigator.pop(ctx), child:Text('取消')), FilledButton(onPressed:(){ int? yy=int.tryParse(yc.text); if(yy!=null) y=yy; onPick(DateTime(y,m,1)); Navigator.pop(ctx); }, child:Text('跳轉')) ]
      );
    }));
  }
  void editCell(DateTime d){
    var noteC=TextEditingController(text:notes[k(d)]??''); var exC=TextEditingController(text:(extra[k(d)]??0).toString()); String cur=roster[k(d)]??'';
    showModalBottomSheet(context:context, isScrollControlled:true, builder:(ctx)=>StatefulBuilder(builder:(ctx,setM){
      return Padding(padding:EdgeInsets.only(bottom:MediaQuery.of(ctx).viewInsets.bottom, left:16,right:16,top:16), child:Column(mainAxisSize:MainAxisSize.min, children:[
        Text(DateFormat('yyyy-MM-dd EEEE').format(d),style:TextStyle(fontWeight:FontWeight.bold)),
        Wrap(spacing:6, children:[ for(var s in shifts) ChoiceChip(label:Text(s.code), selected:cur==s.code, onSelected:(v){ setM(()=>cur=v?s.code:''); }) ]),
        TextField(controller:noteC, decoration:InputDecoration(labelText:'詳細記事內容 (顯示在空白位置)'), maxLines:3),
        TextField(controller:exC, decoration:InputDecoration(labelText:'額外OT小時')),
        SizedBox(height:10), FilledButton(onPressed:(){ setState((){ if(cur=='') roster.remove(k(d)); else roster[k(d)]=cur; if(noteC.text=='') notes.remove(k(d)); else notes[k(d)]=noteC.text; var vv=double.tryParse(exC.text); if(vv==null||vv==0) extra.remove(k(d)); else extra[k(d)]=vv; save(); }); Navigator.pop(ctx); }, child:Text('保存')), SizedBox(height:20),
      ]));
    }));
  }
  void editShiftDialog(Shift? old){
    var codeC=TextEditingController(text:old?.code??''); var nameC=TextEditingController(text:old?.name??''); var stC=TextEditingController(text:old?.start??'07:00'); var enC=TextEditingController(text:old?.end??'15:30'); var hC=TextEditingController(text:(old?.h??8).toString());
    showDialog(context:context, builder:(ctx)=>AlertDialog(title:Text(old==null?'新增班次':'編輯班次'), content:Column(mainAxisSize:MainAxisSize.min, children:[ TextField(controller:codeC, decoration:InputDecoration(labelText:'代號')), TextField(controller:nameC, decoration:InputDecoration(labelText:'名稱')), Row(children:[ Expanded(child:TextField(controller:stC, decoration:InputDecoration(labelText:'開始'))), SizedBox(width:8), Expanded(child:TextField(controller:enC, decoration:InputDecoration(labelText:'結束'))) ]), TextField(controller:hC, decoration:InputDecoration(labelText:'時數')) ]), actions:[ TextButton(onPressed:()=>Navigator.pop(ctx), child:Text('取消')), FilledButton(onPressed:(){ if(codeC.text=='') return; setState((){ var ns=Shift(codeC.text, nameC.text==''?codeC.text:nameC.text, stC.text, enC.text, old?.c??0xFFFF9800, double.tryParse(hC.text)??8, true); if(old==null) shifts.add(ns); else { int idx=shifts.indexOf(old); shifts[idx]=ns; } save(); }); Navigator.pop(ctx); }, child:Text('保存')) ]));
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
  void createPattern(){
    var nameC=TextEditingController(text:'自定${patterns.length+1}'); var rowC=TextEditingController(text:'3');
    showDialog(context:context, builder:(ctx)=>AlertDialog(title:Text('新增 7 x 自定行數'), content:Column(mainAxisSize:MainAxisSize.min, children:[ TextField(controller:nameC, decoration:InputDecoration(labelText:'名稱')), TextField(controller:rowC, decoration:InputDecoration(labelText:'行數'), keyboardType:TextInputType.number) ]), actions:[ TextButton(onPressed:()=>Navigator.pop(ctx), child:Text('取消')), FilledButton(onPressed:(){ int rows=int.tryParse(rowC.text)??3; if(rows<1) rows=1; if(rows>20) rows=20; Navigator.pop(ctx); var pat=Pattern(nameC.text, List.filled(rows*7, shifts.first.code)); editPattern(pat, -1); }, child:Text('去編輯')) ]
    ));
  }
  void editPattern(Pattern pat, int idx){
    List<String> temp=List.from(pat.codes);
    showDialog(context:context, builder:(ctx)=>StatefulBuilder(builder:(ctx,setM){
      return AlertDialog(title:Text('編輯 ${pat.name} - 點格仔改班'), content:SizedBox(width:360, height:400, child:GridView.builder(gridDelegate:SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:7, childAspectRatio:1.1, crossAxisSpacing:4, mainAxisSpacing:4), itemCount:temp.length, itemBuilder:(c,i){
        var sh=getS(temp[i]);
        return InkWell(onTap:(){ showModalBottomSheet(context:ctx, builder:(b)=>Container(padding:EdgeInsets.all(16), child:Wrap(spacing:8, children:[ for(var s in shifts) ChoiceChip(label:Text(s.code), selected:s.code==temp[i], onSelected:(v){ setM(()=>temp[i]=s.code); Navigator.pop(b); }) ]))); }, child:Container(decoration:BoxDecoration(color:sh.color, borderRadius:BorderRadius.circular(8)), child:Center(child:Text(temp[i],style:TextStyle(color:Colors.white,fontWeight:FontWeight.bold)))));
      })), actions:[ TextButton(onPressed:()=>Navigator.pop(ctx), child:Text('取消')), FilledButton(onPressed:(){ setState((){ pat.codes=temp; if(idx==-1) patterns.add(pat); else patterns[idx]=pat; save(); }); Navigator.pop(ctx); }, child:Text('保存')) ]
      );
    }));
  }
  void applyPattern(){
    if(patterns.isEmpty){ ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('請先新增模式'))); return; }
    Pattern sel=patterns.first; DateTime sD=DateTime(focused.year,focused.month,1); DateTime eD=DateTime(focused.year,focused.month+1,0);
    showDialog(context:context, builder:(ctx)=>StatefulBuilder(builder:(ctx,setM){
      return AlertDialog(title:Text('套用排更'), content:Column(mainAxisSize:MainAxisSize.min, children:[
        DropdownButton<Pattern>(value:sel, isExpanded:true, items:[ for(var p in patterns) DropdownMenuItem(value:p, child:Text(p.name)) ], onChanged:(v){ if(v!=null) setM(()=>sel=v); }),
        ListTile(title:Text('開始 ${DateFormat('yyyy-MM-dd').format(sD)}'), onTap:()async{ DateTime? d=await showDatePicker(context:ctx, firstDate:DateTime(2000), lastDate:DateTime(2100), initialDate:sD); if(d!=null) setM(()=>sD=d); }),
        ListTile(title:Text('結束 ${DateFormat('yyyy-MM-dd').format(eD)}'), onTap:()async{ DateTime? d=await showDatePicker(context:ctx, firstDate:DateTime(2000), lastDate:DateTime(2100), initialDate:eD); if(d!=null) setM(()=>eD=d); }),
      ]), actions:[ TextButton(onPressed:()=>Navigator.pop(ctx), child:Text('取消')), FilledButton(onPressed:(){ setState((){ int i=0; for(DateTime d=sD;!d.isAfter(eD); d=d.add(Duration(days:1))){ roster[k(d)]=sel.codes[i%sel.codes.length]; i++; } save(); }); Navigator.pop(ctx); }, child:Text('排更')) ]
      );
    }));
  }

  @override Widget build(BuildContext context){
    return Scaffold(
      body: [buildCal(), buildReport(), buildSetting()][tab],
      bottomNavigationBar: NavigationBar(selectedIndex:tab, onDestinationSelected:(i)=>setState(()=>tab=i), destinations:[
        NavigationDestination(icon:Icon(Icons.calendar_month), label:'月曆'),
        NavigationDestination(icon:Icon(Icons.bar_chart), label:'報表'),
        NavigationDestination(icon:Icon(Icons.settings), label:'設定'),
      ]),
    );
  }

  Widget buildCal(){
    var days=days42(focused);
    String selKey=k(selected);
    String selCode=roster[selKey]??'';
    Shift? selShift=roster[selKey]!=null?getS(roster[selKey]!):null;
    String noteStr=notes[selKey]??'';
    double extraH=extra[selKey]??0;
    String bottomTitle=DateFormat('MM/dd EEEE').format(selected)+' '+(selCode==''?'未排':selCode);
    String bottomDetail='';
    if(selShift!=null) bottomDetail='${selShift.name} ${selShift.start}-${selShift.end} 津貼${allowFor(selShift).toStringAsFixed(0)}';
    if(extraH>0) bottomDetail+=' +OT${extraH}h';

    return SafeArea(child:Column(children:[
      Padding(padding:EdgeInsets.symmetric(horizontal:8,vertical:6), child:Row(children:[
        IconButton(icon:Icon(Icons.today), tooltip:'返回今日', onPressed:(){ setState((){ focused=DateTime.now(); selected=DateTime.now(); reportMonth=DateTime.now(); }); }),
        InkWell(onTap:(){ pickYM((d){ setState(()=>focused=d); }, focused); }, child:Row(children:[ Text('${focused.year}年${focused.month}月',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)), Icon(Icons.arrow_drop_down) ])),
        SizedBox(width:8),
        // 呢個就係你要嘅位置：顯示上下個月
        Container(decoration:BoxDecoration(color:Color(0xFFF1F3F4), borderRadius:BorderRadius.circular(22)), child:Row(mainAxisSize:MainAxisSize.min, children:[
          IconButton(icon:Icon(Icons.chevron_left), iconSize:22, padding:EdgeInsets.zero, constraints:BoxConstraints(minWidth:36,minHeight:36), onPressed:(){ setState(()=>focused=DateTime(focused.year,focused.month-1,1)); }),
          Container(width:1,height:18,color:Color(0xFFE0E0E0)),
          IconButton(icon:Icon(Icons.chevron_right), iconSize:22, padding:EdgeInsets.zero, constraints:BoxConstraints(minWidth:36,minHeight:36), onPressed:(){ setState(()=>focused=DateTime(focused.year,focused.month+1,1)); }),
        ])),
        Spacer(),
        IconButton(icon:Icon(Icons.grid_view), onPressed:createPattern, tooltip:'新增7x模式'),
        IconButton(icon:Icon(Icons.playlist_add_check), onPressed:applyPattern, tooltip:'套用排更'),
      ])),
      Padding(padding:EdgeInsets.symmetric(horizontal:8), child:Row(children:[ for(var w in ['Mon','Tue','Wed','Thu','Fri','Sat','Sun']) Expanded(child:Center(child:Text(w,style:TextStyle(fontWeight:FontWeight.bold,fontSize:11)))) ])),
      SizedBox(height:4),
      Padding(padding:EdgeInsets.symmetric(horizontal:6), child:Column(children:[
        for(int r=0;r<6;r++) Padding(padding:EdgeInsets.only(bottom:4), child:Row(children:[
          for(int c=0;c<7;c++) Builder(builder:(_){
            int idx=r*7+c; DateTime day=days[idx]; bool out=day.month!=focused.month;
            if(out) return Expanded(child:Container(height:cellH, margin:EdgeInsets.symmetric(horizontal:2), decoration:BoxDecoration(color:Color(0xFFF5F5F5), borderRadius:BorderRadius.circular(12)), child:Center(child:Text(day.day.toString(),style:TextStyle(color:Colors.black26)))));
            String key=k(day); String? code=roster[key]; Shift? sh=code!=null?getS(code):null; bool isSel=k(day)==k(selected);
            Color bg=Color(0xFFF1F3F4); if(sh!=null) bg=sh.color; if(isSel) bg=Color(0xFFFFC107);
            bool hasNote=notes[key]!=null&&notes[key]!='';
            return Expanded(child:GestureDetector(
              onTap:(){ setState(()=>selected=day); },
              onLongPress:()=>editCell(day),
              child:Container(height:cellH, margin:EdgeInsets.symmetric(horizontal:2), decoration:BoxDecoration(color:bg, borderRadius:BorderRadius.circular(12)), child:Stack(children:[
                if(day.weekday==1) Positioned(left:3, top:2, child:Text('W${isoWeek(day)}',style:TextStyle(fontSize:7,color:Colors.black54))),
                Center(child:Column(mainAxisAlignment:MainAxisAlignment.center, children:[
                  Text(day.day.toString(),style:TextStyle(fontWeight:FontWeight.bold,fontSize:fs-1, color:sh!=null||isSel?Colors.white:Colors.black)),
                  if(sh!=null) Text(sh.code,style:TextStyle(fontSize:10,color:Colors.white)),
                  if(hasNote) Container(width:4,height:4, margin:EdgeInsets.only(top:1), decoration:BoxDecoration(color:Colors.red, shape:BoxShape.circle)),
                ])),
              ])),
            ));
          })
        ]))
      ])),
      Expanded(child:Container(width:double.infinity, color:Color(0xFFFAFAFA), padding:EdgeInsets.all(12), child:SingleChildScrollView(child:Column(crossAxisAlignment:CrossAxisAlignment.start, children:[
        Row(children:[
          Expanded(child:Text(bottomTitle,style:TextStyle(fontWeight:FontWeight.bold,fontSize:16))),
          FilledButton.icon(onPressed:()=>editCell(selected), icon:Icon(Icons.edit,size:16), label:Text('編輯')),
        ]),
        if(bottomDetail!='') Padding(padding:EdgeInsets.only(top:4), child:Text(bottomDetail,style:TextStyle(fontSize:12,color:Colors.black54))),
        if(noteStr!='') Container(margin:EdgeInsets.only(top:8), padding:EdgeInsets.all(12), width:double.infinity, decoration:BoxDecoration(color:Colors.white, borderRadius:BorderRadius.circular(12), border:Border.all(color:Color(0xFFE0E0E0))), child:Column(crossAxisAlignment:CrossAxisAlignment.start, children:[
          Text('記事內容:',style:TextStyle(fontWeight:FontWeight.bold,fontSize:12)),
          SizedBox(height:4),
          Text(noteStr,style:TextStyle(fontSize:14)),
        ])),
        if(noteStr=='') Padding(padding:EdgeInsets.only(top:8), child:Text('暫無記事，點編輯新增',style:TextStyle(fontSize:12,color:Colors.black38))),
        if(extraH>0) Padding(padding:EdgeInsets.only(top:4), child:Text('額外OT: ${extraH}h = \$${(extraH*otR).toStringAsFixed(0)}',style:TextStyle(fontSize:12))),
      ])))),
    ]));
  }

  Widget buildReport(){
    Map<String,int> shiftCount={}; Map<String,double> shiftHours={};
    Map<String,double> allowSum={}; Map<String,int> allowCount={};
    double totTrans=0, totOTPay=0, totAllow=0, totHours=0; int totWorkDays=0;
    roster.forEach((kk,v){
      DateTime? d=DateTime.tryParse(kk); if(d==null) return;
      if(d.year!=reportMonth.year||d.month!=reportMonth.month) return;
      var s=getS(v); double ex=extra[kk]??0;
      shiftCount[v]=(shiftCount[v]??0)+1;
      shiftHours[v]=(shiftHours[v]??0)+s.h+ex;
      totHours+=s.h+ex;
      if(s.work){ totWorkDays++; totTrans+=transB; }
      double a=allowFor(s); String an=allowNameFor(s);
      if(a>0){ totAllow+=a; allowSum[an]=(allowSum[an]??0)+a; allowCount[an]=(allowCount[an]??0)+1; }
      if(ex>0){ totOTPay+=ex*otR; }
      if(v=='OT'){ totOTPay+=s.h*otR; }
    });
    double total=totAllow+totTrans+totOTPay;
    return SafeArea(child:ListView(padding:EdgeInsets.all(12), children:[
      Row(children:[
        Expanded(child:InkWell(onTap:(){ pickYM((d){ setState(()=>reportMonth=d); }, reportMonth); }, child:Row(children:[ Text('${reportMonth.year}年${reportMonth.month}月 報表',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)), Icon(Icons.arrow_drop_down) ]))),
        FilledButton.tonal(onPressed:(){ pickYM((d){ setState(()=>reportMonth=d); }, reportMonth); }, child:Text('選擇年月')),
      ]),
      SizedBox(height:8),
      Card(child:ListTile(title:Text('返工日數'), subtitle:Text('$totWorkDays日 / 總工時 ${totHours}h'))),
      Card(child:Column(children:[
        ListTile(title:Text('班次類別統計',style:TextStyle(fontWeight:FontWeight.bold))),
        for(var entry in shiftCount.entries) ListTile(dense:true, leading:Container(width:32,height:24,color:getS(entry.key).color, child:Center(child:Text(entry.key,style:TextStyle(color:Colors.white,fontSize:10)))), title:Text('${getS(entry.key).name}'), trailing:Text('${entry.value}次 / ${shiftHours[entry.key]?.toStringAsFixed(1)}h')),
        if(shiftCount.isEmpty) Padding(padding:EdgeInsets.all(12), child:Text('本月無排更')),
      ])),
      Card(child:Column(children:[
        ListTile(title:Text('津貼類別統計',style:TextStyle(fontWeight:FontWeight.bold))),
        for(var entry in allowSum.entries) ListTile(dense:true, title:Text(entry.key), subtitle:Text('${allowCount[entry.key]}次'), trailing:Text('\$${entry.value.toStringAsFixed(0)}')),
        Divider(),
        ListTile(dense:true, title:Text('交通津貼'), trailing:Text('\$${totTrans.toStringAsFixed(0)} (${totWorkDays}日 x \$${transB.toStringAsFixed(0)})')),
        ListTile(dense:true, title:Text('OT津貼'), trailing:Text('\$${totOTPay.toStringAsFixed(0)} (時薪 \$${otR.toStringAsFixed(0)})')),
        ListTile(dense:true, title:Text('班次津貼總計'), trailing:Text('\$${totAllow.toStringAsFixed(0)}')),
      ])),
      Card(color:Color(0xFFE8EAF6), child:ListTile(title:Text('本月總額',style:TextStyle(fontWeight:FontWeight.bold)), trailing:Text('\$${total.toStringAsFixed(0)}',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold)))),
    ]));
  }

  Widget buildSetting(){
    return SafeArea(child:ListView(padding:EdgeInsets.all(12), children:[
      Text('自定班次',style:TextStyle(fontWeight:FontWeight.bold,fontSize:18)),
      for(var s in shifts) Card(child:ListTile(
        leading:CircleAvatar(backgroundColor:s.color, child:Text(s.code,style:TextStyle(color:Colors.white,fontSize:12))),
        title:Text('${s.code} - ${s.name} ${s.h}h'),
        subtitle:Text('津貼${allowFor(s).toStringAsFixed(0)}'),
        trailing:Row(mainAxisSize:MainAxisSize.min, children:[ IconButton(icon:Icon(Icons.edit), onPressed:()=>editShiftDialog(s)), IconButton(icon:Icon(Icons.delete), onPressed:(){ setState(()=>shifts.remove(s)); save(); }) ]),
      )),
      FilledButton.icon(onPressed:()=>editShiftDialog(null), icon:Icon(Icons.add), label:Text('新增自定班次')),
      Divider(),
      Text('津貼設定 (已歸納OT/交通)',style:TextStyle(fontWeight:FontWeight.bold,fontSize:18)),
      Card(color:Color(0xFFFFF8E1), child:Column(children:[
        ListTile(title:Text('OT時薪'), trailing:SizedBox(width:110, child:TextField(controller:TextEditingController(text:otR.toString()), decoration:InputDecoration(prefixText:'\$', border:OutlineInputBorder(), isDense:true), keyboardType:TextInputType.number, onSubmitted:(v){ var vv=double.tryParse(v); if(vv!=null){ setState(()=>otR=vv); save(); } }))),
        ListTile(title:Text('交通津貼 (每日)'), trailing:SizedBox(width:110, child:TextField(controller:TextEditingController(text:transB.toString()), decoration:InputDecoration(prefixText:'\$', border:OutlineInputBorder(), isDense:true), keyboardType:TextInputType.number, onSubmitted:(v){ var vv=double.tryParse(v); if(vv!=null){ setState(()=>transB=vv); save(); } }))),
      ])),
      for(var a in allowances) Card(child:ListTile(
        title:Text('${a.name} ${a.start} \$${a.amount}'),
        subtitle:Text(a.enabled?'已啟用':'停用'),
        trailing:Row(mainAxisSize:MainAxisSize.min, children:[ IconButton(icon:Icon(Icons.edit), onPressed:()=>editAllowDialog(a)), IconButton(icon:Icon(Icons.delete), onPressed:(){ setState(()=>allowances.remove(a)); save(); }) ]),
      )),
      Row(children:[ Expanded(child:ElevatedButton(onPressed:()=>editAllowDialog(null), child:Text('新增津貼'))), SizedBox(width:8), Expanded(child:OutlinedButton(onPressed:(){ setState(()=>allowances=[ Allowance('早班津貼','06:00',20,true), Allowance('中班津貼','14:00',0,true), Allowance('夜班津貼','22:00',80,true), Allowance('通宵津貼','23:30',120,true) ]); save(); }, child:Text('重置預設'))), ]),
      Divider(),
      Text('輪班模式 (可編輯排位)',style:TextStyle(fontWeight:FontWeight.bold,fontSize:18)),
      for(int i=0;i<patterns.length;i++) Card(child:ListTile(
        title:Text(patterns[i].name),
        subtitle:Text('${patterns[i].codes.length~/7}行'),
        trailing:Row(mainAxisSize:MainAxisSize.min, children:[
          IconButton(icon:Icon(Icons.edit), onPressed:()=>editPattern(Pattern(patterns[i].name, List.from(patterns[i].codes)), i)),
          IconButton(icon:Icon(Icons.delete), onPressed:(){ setState(()=>patterns.removeAt(i)); save(); }),
        ]),
      )),
      FilledButton.icon(onPressed:createPattern, icon:Icon(Icons.add), label:Text('新增 7 x 自定行數')),
      SizedBox(height:8),
      FilledButton.icon(onPressed:applyPattern, icon:Icon(Icons.play_arrow), label:Text('套用排更 - 按開始結束日期')),
      SizedBox(height:80),
    ]));
  }
}
