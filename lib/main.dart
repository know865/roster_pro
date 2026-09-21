import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';

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
  double weeklyStandard=44; // 2. 新增
  final double cellH=68;
  bool showAllShifts=false, showHolidays=true, googleSyncEnabled=false;
  int googleSyncMode=0;
  String lastBackup='從未備份', lastDriveBackup='未備份到Drive';
  final GoogleSignIn _gs = GoogleSignIn(scopes: [drive.DriveApi.driveAppdataScope, drive.DriveApi.driveFileScope]);

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
      Allowance('早班津貼','06:00',20,true),Allowance('中班津貼','14:00',0,true),Allowance('夜班津貼','22:00',80,true),Allowance('通宵津貼','23:30',120,true),
    ];
  }
  Map<String,String> hkHolidays={'2026-09-22':'秋分','2026-09-25':'中秋翌日','2026-10-01':'國慶','2026-01-01':'元旦','2026-02-17':'初一'};
  String k(DateTime d)=>DateFormat('yyyy-MM-dd').format(d);
  int isoWeek(DateTime d){ var thu=d.add(Duration(days:4-d.weekday)); var jan1=DateTime(thu.year,1,1); return (thu.difference(jan1).inDays/7).floor()+1; }
  Shift getS(String c){ for(var s in shifts) if(s.code==c) return s; return Shift('','','','',0xFF9E9E9E,0,false); }
  int pMins(String t){ try{var p=t.split(':'); return int.parse(p[0])*60+int.parse(p[1]);}catch(_){return -1;}}
  double allowFor(Shift s){ if(!s.work||s.start=='') return 0; int sm=pMins(s.start); if(sm<0) return 0; Allowance? best; int bd=10000; for(var a in allowances){ if(!a.enabled) continue; int d=sm-a.mins; if(d<0) d+=1440; if(d<bd&&d<720){ bd=d; best=a; } } return best==null?0:best.amount; }
  String allowNameFor(Shift s){ if(!s.work||s.start=='') return ''; int sm=pMins(s.start); if(sm<0) return ''; Allowance? best; int bd=10000; for(var a in allowances){ if(!a.enabled) continue; int d=sm-a.mins; if(d<0) d+=1440; if(d<bd&&d<720){ bd=d; best=a; } } return best==null?'':best.name; }
  void save() async{ var p=await SharedPreferences.getInstance(); p.setString('roster',jsonEncode(roster)); p.setString('notes',jsonEncode(notes)); p.setString('extra',jsonEncode(extra)); p.setString('shifts',jsonEncode(shifts.map((e)=>e.toJson()).toList())); p.setString('allowances',jsonEncode(allowances.map((e)=>e.toJson()).toList())); p.setString('patterns',jsonEncode(patterns.map((e)=>e.toJson()).toList())); p.setDouble('otR',otR); p.setDouble('transB',transB); p.setDouble('fs',fs); p.setDouble('weeklyStandard',weeklyStandard); p.setBool('showHolidays',showHolidays); p.setString('lastBackup',lastBackup); p.setString('lastDriveBackup',lastDriveBackup); }
  void load() async{ var p=await SharedPreferences.getInstance(); var r=p.getString('roster'); if(r!=null){ var d=jsonDecode(r); roster=(d as Map).map((kk,v)=>MapEntry(kk.toString(),v.toString())); } var n=p.getString('notes'); if(n!=null){ var d=jsonDecode(n); notes=(d as Map).map((kk,v)=>MapEntry(kk.toString(),v.toString())); } var ex=p.getString('extra'); if(ex!=null){ var d=jsonDecode(ex); extra=(d as Map).map((kk,v)=>MapEntry(kk.toString(),(v as num).toDouble())); } var sh=p.getString('shifts'); if(sh!=null){ var d=jsonDecode(sh) as List; shifts=d.map((e)=>Shift.fromJson(e)).toList(); } var al=p.getString('allowances'); if(al!=null){ var d=jsonDecode(al) as List; allowances=d.map((e)=>Allowance.fromJson(e)).toList(); } var pat=p.getString('patterns'); if(pat!=null){ var d=jsonDecode(pat) as List; patterns=d.map((e)=>Pattern.fromJson(e)).toList(); } setState((){ otR=p.getDouble('otR')??100; transB=p.getDouble('transB')??20; fs=p.getDouble('fs')??11; weeklyStandard=p.getDouble('weeklyStandard')??44; showHolidays=p.getBool('showHolidays')??true; lastBackup=p.getString('lastBackup')??'從未備份'; lastDriveBackup=p.getString('lastDriveBackup')??'未備份到Drive'; }); }
  @override void initState(){ super.initState(); load(); }
  List<DateTime> days42(DateTime mon){ var first=DateTime(mon.year,mon.month,1); int off=first.weekday-1; var start=first.subtract(Duration(days:off)); return List.generate(42,(i)=>start.add(Duration(days:i))); }
  String exportAllJson(){ Map all={'roster':roster,'notes':notes,'extra':extra,'shifts':shifts.map((e)=>e.toJson()).toList(),'allowances':allowances.map((e)=>e.toJson()).toList(),'patterns':patterns.map((e)=>e.toJson()).toList(),'otR':otR,'transB':transB,'fs':fs,'weeklyStandard':weeklyStandard,'exportTime':DateTime.now().toIso8601String()}; return jsonEncode(all); }
  void importAllJson(String js){ try{ var d=jsonDecode(js); setState((){ roster=(d['roster'] as Map).map((kk,v)=>MapEntry(kk.toString(),v.toString())); notes=(d['notes'] as Map).map((kk,v)=>MapEntry(kk.toString(),v.toString())); extra=(d['extra'] as Map).map((kk,v)=>MapEntry(kk.toString(),(v as num).toDouble())); shifts=(d['shifts'] as List).map((e)=>Shift.fromJson(e)).toList(); allowances=(d['allowances'] as List).map((e)=>Allowance.fromJson(e)).toList(); patterns=(d['patterns'] as List).map((e)=>Pattern.fromJson(e)).toList(); otR=(d['otR'] as num).toDouble(); transB=(d['transB'] as num).toDouble(); weeklyStandard=(d['weeklyStandard']??44 as num).toDouble(); }); save(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('還原成功'))); }catch(e){ ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('失敗:$e'))); } }

  Future<void> doLocalBackup() async{
    try{
      String jsonStr=exportAllJson();
      String fname='shift_backup_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.json';
      List<String> paths=[];
      try{ var dir=await getApplicationDocumentsDirectory(); File f=File('${dir.path}/$fname'); await f.writeAsString(jsonStr); paths.add(f.path); }catch(_){}
      try{ Directory dl=Directory('/storage/emulated/0/Download'); if(await dl.exists()){ File f=File('${dl.path}/$fname'); await f.writeAsString(jsonStr); paths.add(f.path); } }catch(_){}
      setState(()=>lastBackup='${DateFormat('MM/dd HH:mm').format(DateTime.now())} 已存 $fname'); save();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('本地備份成功: ${paths.join(", ")}')));
    }catch(e){ ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('備份失敗:$e'))); }
  }
  Future<void> doLocalRestore() async{
    try{
      List<FileSystemEntity> all=[];
      try{ var d=await getApplicationDocumentsDirectory(); all.addAll(d.listSync().where((f)=>f.path.endsWith('.json'))); }catch(_){}
      try{ Directory dl=Directory('/storage/emulated/0/Download'); if(await dl.exists()){ all.addAll(dl.listSync().where((f)=>f.path.contains('shift_backup')&&f.path.endsWith('.json'))); } }catch(_){}
      if(all.isEmpty){ ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('未找到本地備份檔，請檢查Download資料夾'))); return; }
      all.sort((a,b)=>b.statSync().modified.compareTo(a.statSync().modified));
      showDialog(context:context, builder:(ctx)=>AlertDialog(title:Text('從手機還原'), content:SizedBox(width:300, height:300, child:ListView(children:[ for(var f in all.take(10)) ListTile(title:Text(f.path.split('/').last), subtitle:Text(DateFormat('MM/dd HH:mm').format(f.statSync().modified)), onTap:()async{ String js=await File(f.path).readAsString(); importAllJson(js); Navigator.pop(ctx); }) ])), actions:[TextButton(onPressed:()=>Navigator.pop(ctx), child:Text('取消'))]));
    }catch(e){ ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('還原失敗:$e'))); }
  }
  Future<void> doDriveBackup() async{
    try{
      final acc=await _gs.signIn(); if(acc==null){ ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('已取消登入'))); return; }
      final auth=await _gs.authenticatedClient(); if(auth==null) throw 'auth fail';
      final driveApi=drive.DriveApi(auth);
      String jsonStr=exportAllJson();
      final media=drive.Media(Stream.value(utf8.encode(jsonStr)), utf8.encode(jsonStr).length);
      var file=drive.File()..name='roster_backup_${DateFormat('yyyyMMdd').format(DateTime.now())}.json'..parents=['appDataFolder'];
      // 先查舊檔刪除
      var list=await driveApi.files.list(spaces:'appDataFolder', q:"name contains 'roster_backup'");
      for(var f in list.files??[]){ try{ await driveApi.files.delete(f.id!); }catch(_){} }
      await driveApi.files.create(file, uploadMedia:media);
      setState(()=>lastDriveBackup='${DateFormat('MM/dd HH:mm').format(DateTime.now())} 已備份到Drive'); save();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Drive備份成功')));
    }catch(e){ ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Drive備份失敗:$e'))); }
  }
  Future<void> doDriveRestore() async{
    try{
      final acc=await _gs.signIn(); if(acc==null) return;
      final auth=await _gs.authenticatedClient(); if(auth==null) throw 'auth fail';
      final driveApi=drive.DriveApi(auth);
      var list=await driveApi.files.list(spaces:'appDataFolder', q:"name contains 'roster_backup'", orderBy:'modifiedTime desc');
      if(list.files==null||list.files!.isEmpty){ ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Drive無備份'))); return; }
      var f=list.files!.first;
      var media=await driveApi.files.get(f.id!, downloadOptions:drive.DownloadOptions.fullMedia) as drive.Media;
      List<int> bytes=[]; await for(var chunk in media.stream){ bytes.addAll(chunk); }
      String js=utf8.decode(bytes);
      importAllJson(js);
    }catch(e){ ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Drive還原失敗:$e'))); }
  }

  void pickYM(Function(DateTime) onPick, DateTime init){ int y=init.year,m=init.month; var yc=TextEditingController(text:y.toString()); showDialog(context:context, builder:(ctx)=>StatefulBuilder(builder:(ctx,setM){ return AlertDialog(title:Text('選擇年月'), content:Column(mainAxisSize:MainAxisSize.min, children:[ Row(children:[ IconButton(icon:Icon(Icons.remove), onPressed:(){ setM((){ y-=1; yc.text=y.toString(); }); }), Expanded(child:TextField(controller:yc, textAlign:TextAlign.center)), IconButton(icon:Icon(Icons.add), onPressed:(){ setM((){ y+=1; yc.text=y.toString(); }); }) ]), Wrap(spacing:4, runSpacing:4, children:[ for(int mm=1;mm<=12;mm++) ChoiceChip(label:Text('${mm}月'), selected:m==mm, onSelected:(v){ setM(()=>m=mm); }) ]), ]), actions:[ TextButton(onPressed:()=>Navigator.pop(ctx), child:Text('取消')), FilledButton(onPressed:(){ int? yy=int.tryParse(yc.text); if(yy!=null) y=yy; onPick(DateTime(y,m,1)); Navigator.pop(ctx); }, child:Text('跳轉')) ] ); })); }
  void editCell(DateTime d){ var noteC=TextEditingController(text:notes[k(d)]??''); var exC=TextEditingController(text:(extra[k(d)]??0).toString()); String cur=roster[k(d)]??''; showModalBottomSheet(context:context, isScrollControlled:true, builder:(ctx)=>StatefulBuilder(builder:(ctx,setM){ return Padding(padding:EdgeInsets.only(bottom:MediaQuery.of(ctx).viewInsets.bottom, left:16,right:16,top:16), child:Column(mainAxisSize:MainAxisSize.min, children:[ Text(DateFormat('yyyy-MM-dd EEEE').format(d),style:TextStyle(fontWeight:FontWeight.bold)), Wrap(spacing:6, children:[ for(var s in shifts) ChoiceChip(label:Text(s.code), selected:cur==s.code, onSelected:(v){ setM(()=>cur=v?s.code:''); }) ]), TextField(controller:noteC, decoration:InputDecoration(labelText:'記事內容（有色點標識）'), maxLines:3), TextField(controller:exC, decoration:InputDecoration(labelText:'額外OT小時')), SizedBox(height:10), FilledButton(onPressed:(){ setState((){ if(cur=='') roster.remove(k(d)); else roster[k(d)]=cur; if(noteC.text=='') notes.remove(k(d)); else notes[k(d)]=noteC.text; var vv=double.tryParse(exC.text); if(vv==null||vv==0) extra.remove(k(d)); else extra[k(d)]=vv; save(); }); Navigator.pop(ctx); }, child:Text('保存')), SizedBox(height:20), ])); })); }
  void editShiftDialog(Shift? old){ var codeC=TextEditingController(text:old?.code??''); var nameC=TextEditingController(text:old?.name??''); var stC=TextEditingController(text:old?.start??'07:00'); var enC=TextEditingController(text:old?.end??'15:30'); var hC=TextEditingController(text:(old?.h??8).toString()); showDialog(context:context, builder:(ctx)=>AlertDialog(title:Text(old==null?'新增班次':'編輯班次'), content:Column(mainAxisSize:MainAxisSize.min, children:[ TextField(controller:codeC, decoration:InputDecoration(labelText:'代號')), TextField(controller:nameC, decoration:InputDecoration(labelText:'名稱')), Row(children:[ Expanded(child:TextField(controller:stC, decoration:InputDecoration(labelText:'開始'))), SizedBox(width:8), Expanded(child:TextField(controller:enC, decoration:InputDecoration(labelText:'結束'))) ]), TextField(controller:hC, decoration:InputDecoration(labelText:'時數')) ]), actions:[ TextButton(onPressed:()=>Navigator.pop(ctx), child:Text('取消')), FilledButton(onPressed:(){ if(codeC.text=='') return; setState((){ var ns=Shift(codeC.text, nameC.text==''?codeC.text:nameC.text, stC.text, enC.text, old?.c??0xFFFF9800, double.tryParse(hC.text)??8, true); if(old==null) shifts.add(ns); else { int idx=shifts.indexOf(old); shifts[idx]=ns; } save(); }); Navigator.pop(ctx); }, child:Text('保存')) ])); }
  void editAllowDialog(Allowance? old){ var nC=TextEditingController(text:old?.name??''); var sC=TextEditingController(text:old?.start??'06:00'); var aC=TextEditingController(text:(old?.amount??0).toString()); bool en=old?.enabled??true; showDialog(context:context, builder:(ctx)=>StatefulBuilder(builder:(ctx,setM){ return AlertDialog(title:Text(old==null?'新增津貼':'編輯津貼'), content:Column(mainAxisSize:MainAxisSize.min, children:[ TextField(controller:nC, decoration:InputDecoration(labelText:'名稱')), TextField(controller:sC, decoration:InputDecoration(labelText:'開始')), TextField(controller:aC, decoration:InputDecoration(labelText:'金額')), CheckboxListTile(title:Text('啟用'), value:en, onChanged:(v){ setM(()=>en=v!); }), ]), actions:[ TextButton(onPressed:()=>Navigator.pop(ctx), child:Text('取消')), FilledButton(onPressed:(){ if(nC.text=='') return; setState((){ var na=Allowance(nC.text, sC.text, double.tryParse(aC.text)??0, en); if(old==null) allowances.add(na); else { int idx=allowances.indexOf(old); allowances[idx]=na; } save(); }); Navigator.pop(ctx); }, child:Text('保存')) ]); })); }
  void createPattern(){ var nameC=TextEditingController(text:'自定${patterns.length+1}'); var rowC=TextEditingController(text:'22'); showDialog(context:context, builder:(ctx)=>AlertDialog(title:Text('新增 7 x 自定行數'), content:Column(mainAxisSize:MainAxisSize.min, children:[ TextField(controller:nameC, decoration:InputDecoration(labelText:'名稱')), TextField(controller:rowC, decoration:InputDecoration(labelText:'行數 1-100'), keyboardType:TextInputType.number) ]), actions:[ TextButton(onPressed:()=>Navigator.pop(ctx), child:Text('取消')), FilledButton(onPressed:(){ int rows=int.tryParse(rowC.text)??22; if(rows<1) rows=1; if(rows>100) rows=100; Navigator.pop(ctx); var pat=Pattern(nameC.text, List.filled(rows*7, shifts.first.code)); editPattern(pat, -1); }, child:Text('去編輯')) ])); }
  void editPattern(Pattern pat, int idx){ List<String> temp=List.from(pat.codes); int rows=temp.length~/7; showDialog(context:context, builder:(ctx)=>StatefulBuilder(builder:(ctx,setM){ return AlertDialog(title:Text('編輯 ${pat.name} ${rows}行 x 7'), content:SizedBox(width:400, height:520, child:Column(children:[ Row(children:[ SizedBox(width:28, child:Text('行號',style:TextStyle(fontSize:10,fontWeight:FontWeight.bold))), Expanded(child:Row(children:[ for(var d in ['一','二','三','四','五','六','日']) Expanded(child:Center(child:Text(d,style:TextStyle(fontSize:12,fontWeight:FontWeight.bold)))) ])) ]), Divider(height:8), Expanded(child:ListView.builder(itemCount:rows, itemBuilder:(c,r){ return Padding(padding:EdgeInsets.only(bottom:6), child:Row(children:[ SizedBox(width:28, child:Text('R${r+1}',style:TextStyle(fontSize:11,fontWeight:FontWeight.bold,color:Colors.black54))), Expanded(child:Row(children:[ for(int col=0;col<7;col++) Builder(builder:(_){ int i=r*7+col; String code=temp[i]; var sh=getS(code); return Expanded(child:Container(height:36, margin:EdgeInsets.symmetric(horizontal:2), child:GestureDetector(onTap:(){ showModalBottomSheet(context:ctx, builder:(b)=>Container(padding:EdgeInsets.all(16), child:Wrap(spacing:8, children:[ for(var s in shifts) ChoiceChip(label:Text(s.code), selected:s.code==code, onSelected:(v){ setM(()=>temp[i]=s.code); Navigator.pop(b); }) ]))); }, child:Container(decoration:BoxDecoration(color:sh.color, borderRadius:BorderRadius.circular(8)), child:Center(child:Text(code,style:TextStyle(color:Colors.white,fontSize:11,fontWeight:FontWeight.bold))))))); }) ])) ])); })), ])), actions:[ TextButton(onPressed:()=>Navigator.pop(ctx), child:Text('取消')), FilledButton(onPressed:(){ setState((){ pat.codes=temp; if(idx==-1) patterns.add(pat); else patterns[idx]=pat; save(); }); Navigator.pop(ctx); }, child:Text('保存 ${temp.length}日')) ] ); })); }
  void applyPattern(){ if(patterns.isEmpty){ ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('請先新增模式'))); return; } Pattern sel=patterns.first; DateTime sD=DateTime(focused.year,focused.month,1); DateTime eD=DateTime(focused.year,focused.month+1,0); showDialog(context:context, builder:(ctx)=>StatefulBuilder(builder:(ctx,setM){ return AlertDialog(title:Text('套用排更'), content:Column(mainAxisSize:MainAxisSize.min, children:[ DropdownButton<Pattern>(value:sel, isExpanded:true, items:[ for(var p in patterns) DropdownMenuItem(value:p, child:Text('${p.name} ${p.codes.length~/7}行')) ], onChanged:(v){ if(v!=null) setM(()=>sel=v); }), ListTile(title:Text('開始 ${DateFormat('yyyy-MM-dd').format(sD)}'), onTap:()async{ DateTime? d=await showDatePicker(context:ctx, firstDate:DateTime(2000), lastDate:DateTime(2100), initialDate:sD); if(d!=null) setM(()=>sD=d); }), ListTile(title:Text('結束 ${DateFormat('yyyy-MM-dd').format(eD)}'), onTap:()async{ DateTime? d=await showDatePicker(context:ctx, firstDate:DateTime(2000), lastDate:DateTime(2100), initialDate:eD); if(d!=null) setM(()=>eD=d); }), ]), actions:[ TextButton(onPressed:()=>Navigator.pop(ctx), child:Text('取消')), FilledButton(onPressed:(){ setState((){ int i=0; for(DateTime d=sD;!d.isAfter(eD); d=d.add(Duration(days:1))){ roster[k(d)]=sel.codes[i%sel.codes.length]; i++; } save(); }); Navigator.pop(ctx); }, child:Text('排更')) ] ); })); }

  @override Widget build(BuildContext context){ return Scaffold(body: [buildCal(), buildReport(), buildSetting()][tab], bottomNavigationBar: NavigationBar(selectedIndex:tab, onDestinationSelected:(i)=>setState(()=>tab=i), destinations:[ NavigationDestination(icon:Icon(Icons.calendar_month), label:'月曆'), NavigationDestination(icon:Icon(Icons.bar_chart), label:'報表'), NavigationDestination(icon:Icon(Icons.settings), label:'設定'), ]), ); }

  Widget buildCal(){
    var days=days42(focused); String selKey=k(selected);
    return SafeArea(child:Column(children:[
      Padding(padding:EdgeInsets.symmetric(horizontal:8,vertical:6), child:Row(children:[
        IconButton(icon:Icon(Icons.today), onPressed:(){ setState((){ focused=DateTime.now(); selected=DateTime.now(); reportMonth=DateTime.now(); }); }),
        InkWell(onTap:(){ pickYM((d){ setState(()=>focused=d); }, focused); }, child:Row(children:[ Text('${focused.year}年${focused.month}月',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)), Icon(Icons.arrow_drop_down) ])),
        SizedBox(width:8),
        Container(decoration:BoxDecoration(color:Color(0xFFF1F3F4), borderRadius:BorderRadius.circular(22)), child:Row(mainAxisSize:MainAxisSize.min, children:[
          IconButton(icon:Icon(Icons.chevron_left), iconSize:22, padding:EdgeInsets.zero, constraints:BoxConstraints(minWidth:36,minHeight:36), onPressed:(){ setState(()=>focused=DateTime(focused.year,focused.month-1,1)); }),
          Container(width:1,height:18,color:Color(0xFFE0E0E0)),
          IconButton(icon:Icon(Icons.chevron_right), iconSize:22, padding:EdgeInsets.zero, constraints:BoxConstraints(minWidth:36,minHeight:36), onPressed:(){ setState(()=>focused=DateTime(focused.year,focused.month+1,1)); }),
        ])),
        Spacer(), IconButton(icon:Icon(Icons.grid_view), onPressed:createPattern), IconButton(icon:Icon(Icons.playlist_add_check), onPressed:applyPattern),
      ])),
      Padding(padding:EdgeInsets.symmetric(horizontal:8), child:Row(children:[ for(var w in ['Mon','Tue','Wed','Thu','Fri','Sat','Sun']) Expanded(child:Center(child:Text(w,style:TextStyle(fontWeight:FontWeight.bold,fontSize:11)))) ])),
      Padding(padding:EdgeInsets.symmetric(horizontal:6), child:Column(children:[
        for(int r=0;r<6;r++) Padding(padding:EdgeInsets.only(bottom:4), child:Row(children:[
          for(int c=0;c<7;c++) Builder(builder:(_){
            int idx=r*7+c; DateTime day=days[idx]; bool out=day.month!=focused.month; String dk=k(day); bool isHol=showHolidays&&hkHolidays.containsKey(dk); bool hasNote=notes[dk]!=null&&notes[dk]!=''; bool isToday=k(day)==k(DateTime.now()); bool isSel=dk==k(selected);
            if(out) return Expanded(child:Container(height:cellH, margin:EdgeInsets.symmetric(horizontal:2), decoration:BoxDecoration(color:Color(0xFFF5F5F5), borderRadius:BorderRadius.circular(12)), child:Center(child:Text(day.day.toString(),style:TextStyle(color:Colors.black26)))));
            String? code=roster[dk]; Shift? sh=code!=null?getS(code):null;
            // 1. 白底設計
            Color bg=Colors.white; if(isSel) bg=Color(0xFFEDE7F6); if(isToday) bg=Color(0xFFFFF8E1);
            return Expanded(child:GestureDetector(onTap:(){ setState(()=>selected=day); }, onLongPress:()=>editCell(day), child:Container(height:cellH, margin:EdgeInsets.symmetric(horizontal:2), decoration:BoxDecoration(color:bg, borderRadius:BorderRadius.circular(12), border:Border.all(color:isToday?Colors.black:isSel?Color(0xFF7C4DFF):Color(0xFFE0E0E0), width:isToday||isSel?1.8:0.8)), child:Stack(children:[
              if(sh!=null) Positioned(left:0, top:0, bottom:0, child:Container(width:5, decoration:BoxDecoration(color:sh.color, borderRadius:BorderRadius.only(topLeft:Radius.circular(12), bottomLeft:Radius.circular(12))))),
              if(day.weekday==1) Positioned(left:8, top:2, child:Text('W${isoWeek(day)}',style:TextStyle(fontSize:7,color:Colors.black38))),
              if(isHol) Positioned(right:4, top:3, child:Container(width:6,height:6, decoration:BoxDecoration(color:Colors.red, shape:BoxShape.circle))),
              if(hasNote) Positioned(right:4, top:isHol?10:3, child:Container(width:7,height:7, decoration:BoxDecoration(color:Colors.blue, shape:BoxShape.circle, border:Border.all(color:Colors.white,width:1)))),
              Center(child:Column(mainAxisAlignment:MainAxisAlignment.center, children:[
                Text(day.day.toString(),style:TextStyle(fontWeight:FontWeight.bold,fontSize:fs, color:Colors.black87)),
                if(sh!=null) Container(margin:EdgeInsets.only(top:2), padding:EdgeInsets.symmetric(horizontal:6,vertical:1), decoration:BoxDecoration(color:sh.color, borderRadius:BorderRadius.circular(8)), child:Text(sh.code,style:TextStyle(fontSize:10,color:Colors.white,fontWeight:FontWeight.bold))),
                if(isHol) Text(hkHolidays[dk]!.length>2?hkHolidays[dk]!.substring(0,2):hkHolidays[dk]!,style:TextStyle(fontSize:7,color:Colors.red)),
              ])),
            ]))));
          })
        ]))
      ])),
      Expanded(child:Container(width:double.infinity, color:Color(0xFFFAFAFA), padding:EdgeInsets.all(12), child:SingleChildScrollView(child:Column(crossAxisAlignment:CrossAxisAlignment.start, children:[
        Builder(builder:(_){ String selCode=roster[selKey]??''; Shift? selShift=roster[selKey]!=null?getS(roster[selKey]!):null; String noteStr=notes[selKey]??''; double extraH=extra[selKey]??0; String bottomTitle=DateFormat('MM/dd EEEE').format(selected)+' '+(selCode==''?'未排':selCode); String bottomDetail=''; if(selShift!=null) bottomDetail='${selShift.name} ${selShift.start}-${selShift.end} 津貼${allowFor(selShift).toStringAsFixed(0)}'; if(extraH>0) bottomDetail+=' +OT${extraH}h'; return Column(crossAxisAlignment:CrossAxisAlignment.start, children:[ Row(children:[ Expanded(child:Text(bottomTitle,style:TextStyle(fontWeight:FontWeight.bold,fontSize:16))), FilledButton.icon(onPressed:()=>editCell(selected), icon:Icon(Icons.edit,size:16), label:Text('編輯')), ]), if(bottomDetail!='') Text(bottomDetail,style:TextStyle(fontSize:12,color:Colors.black54)), if(noteStr!='') Container(margin:EdgeInsets.only(top:8), padding:EdgeInsets.all(12), width:double.infinity, decoration:BoxDecoration(color:Colors.white, borderRadius:BorderRadius.circular(12), border:Border.all(color:Colors.blueAccent)), child:Text(noteStr)), ]); }),
      ])))),
    ]));
  }

  Widget buildReport(){
    // 2. 每週工時統計
    Map<int,double> weekHours={}; Map<int,int> weekDays={};
    roster.forEach((kk,v){ DateTime? d=DateTime.tryParse(kk); if(d==null) return; if(d.year!=reportMonth.year||d.month!=reportMonth.month) return; var s=getS(v); double ex=extra[kk]??0; int wk=isoWeek(d); weekHours[wk]=(weekHours[wk]??0)+s.h+ex; weekDays[wk]=(weekDays[wk]??0)+1; });
    double totHours=weekHours.values.fold(0,(a,b)=>a+b);
    int totWorkDays=weekDays.values.fold(0,(a,b)=>a+b);
    Map<String,int> shiftCount={}; roster.forEach((kk,v){ DateTime? d=DateTime.tryParse(kk); if(d==null) return; if(d.year!=reportMonth.year||d.month!=reportMonth.month) return; shiftCount[v]=(shiftCount[v]??0)+1; });
    return SafeArea(child:ListView(padding:EdgeInsets.all(12), children:[
      Row(children:[ Expanded(child:InkWell(onTap:(){ pickYM((d){ setState(()=>reportMonth=d); }, reportMonth); }, child:Row(children:[ Text('${reportMonth.year}年${reportMonth.month}月 報表',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)), Icon(Icons.arrow_drop_down) ]))), FilledButton.tonal(onPressed:(){ pickYM((d){ setState(()=>reportMonth=d); }, reportMonth); }, child:Text('選擇年月')), ]),
      Card(child:ListTile(title:Text('本月總計'), subtitle:Text('返工 $totWorkDays日 / 總工時 ${totHours.toStringAsFixed(1)}h / 標準 ${weeklyStandard}h x ${(weekHours.length==0?1:weekHours.length)}週'))),
      Card(color:Color(0xFFE3F2FD), child:Column(children:[
        ListTile(title:Text('每週工時 vs 標準 ${weeklyStandard}h',style:TextStyle(fontWeight:FontWeight.bold))),
        for(var wk in weekHours.keys.toList()..sort()) ListTile(
          dense:true,
          leading:CircleAvatar(child:Text('W$wk',style:TextStyle(fontSize:10)), radius:18),
          title:Text('${weekHours[wk]!.toStringAsFixed(1)}h / ${weekDays[wk]}日'),
          trailing: Builder(builder:(_){
            double diff=weekHours[wk]!-weeklyStandard;
            return Text('${diff>=0?'+':''}${diff.toStringAsFixed(1)}h', style:TextStyle(color:diff>0?Colors.red:diff<0?Colors.green:Colors.black, fontWeight:FontWeight.bold));
          }),
        ),
        if(weekHours.isEmpty) Padding(padding:EdgeInsets.all(12), child:Text('本月無資料')),
        Divider(),
        ListTile(title:Text('總差額'), trailing:Text('${(totHours - weeklyStandard*weekHours.length).toStringAsFixed(1)}h',style:TextStyle(fontWeight:FontWeight.bold))),
      ])),
      Card(child:Column(children:[ ListTile(title:Text('班次統計',style:TextStyle(fontWeight:FontWeight.bold))), for(var e in shiftCount.entries) ListTile(dense:true, leading:Container(width:32,height:22,color:getS(e.key).color), title:Text(e.key), trailing:Text('${e.value}次')), ])),
    ]));
  }

  Widget buildSetting(){
    List<Shift> displayShifts=showAllShifts?shifts:shifts.take(3).toList();
    return SafeArea(child:ListView(padding:EdgeInsets.all(12), children:[
      Text('備份與同步',style:TextStyle(fontWeight:FontWeight.bold,fontSize:18)),
      Card(color:Color(0xFFE8F5E9), child:Column(children:[
        ListTile(title:Text('本地備份'), subtitle:Text('上次: $lastBackup')),
        Padding(padding:EdgeInsets.symmetric(horizontal:12), child:Row(children:[ Expanded(child:OutlinedButton.icon(onPressed:doLocalBackup, icon:Icon(Icons.save_alt), label:Text('備份到手機'))), SizedBox(width:8), Expanded(child:OutlinedButton.icon(onPressed:doLocalRestore, icon:Icon(Icons.restore), label:Text('從手機還原'))), ])),
        Divider(),
        ListTile(title:Text('網絡備份 Google Drive'), subtitle:Text('上次: $lastDriveBackup (appDataFolder)')),
        Padding(padding:EdgeInsets.symmetric(horizontal:12), child:Row(children:[ Expanded(child:ElevatedButton.icon(onPressed:doDriveBackup, icon:Icon(Icons.cloud_upload), label:Text('備份到Drive'))), SizedBox(width:8), Expanded(child:ElevatedButton.icon(onPressed:doDriveRestore, icon:Icon(Icons.cloud_download), label:Text('從Drive還原'))), ])),
        SizedBox(height:8),
      ])),
      SizedBox(height:12),
      Text('工時與顯示',style:TextStyle(fontWeight:FontWeight.bold,fontSize:18)),
      Card(child:Column(children:[
        ListTile(title:Text('每週標準工時'), subtitle:Text('用於報表計算差額'), trailing:SizedBox(width:110, child:TextField(controller:TextEditingController(text:weeklyStandard.toString()), keyboardType:TextInputType.number, decoration:InputDecoration(suffixText:'h', border:OutlineInputBorder(), isDense:true), onSubmitted:(v){ var vv=double.tryParse(v); if(vv!=null){ setState(()=>weeklyStandard=vv); save(); } }))),
        SwitchListTile(title:Text('在日曆顯示公眾假期'), subtitle:Text('香港假期紅點'), value:showHolidays, onChanged:(v){ setState(()=>showHolidays=v); save(); }),
        ListTile(title:Text('日曆日期文字大小 ${fs.toInt()}'), subtitle:Slider(value:fs, min:9, max:18, divisions:9, label:fs.toInt().toString(), onChanged:(v){ setState(()=>fs=v); save(); })),
      ])),
      Divider(),
      Row(children:[ Text('自定班次',style:TextStyle(fontWeight:FontWeight.bold,fontSize:18)), Spacer(), TextButton(onPressed:(){ setState(()=>showAllShifts=!showAllShifts); }, child:Text(showAllShifts?'收起':'顯示全部 ${shifts.length}個')) ]),
      for(var s in displayShifts) Card(child:ListTile(leading:CircleAvatar(backgroundColor:s.color, child:Text(s.code,style:TextStyle(color:Colors.white,fontSize:12))), title:Text('${s.code} - ${s.name} ${s.h}h'), subtitle:Text('津貼${allowFor(s).toStringAsFixed(0)}'), trailing:Row(mainAxisSize:MainAxisSize.min, children:[ IconButton(icon:Icon(Icons.edit), onPressed:()=>editShiftDialog(s)), IconButton(icon:Icon(Icons.delete), onPressed:(){ setState(()=>shifts.remove(s)); save(); }) ]), )),
      FilledButton.icon(onPressed:()=>editShiftDialog(null), icon:Icon(Icons.add), label:Text('新增自定班次')),
      Divider(),
      Text('津貼設定',style:TextStyle(fontWeight:FontWeight.bold,fontSize:18)),
      Card(color:Color(0xFFFFF8E1), child:Column(children:[
        ListTile(title:Text('OT時薪'), trailing:SizedBox(width:110, child:TextField(controller:TextEditingController(text:otR.toString()), decoration:InputDecoration(prefixText:'\$', border:OutlineInputBorder(), isDense:true), onSubmitted:(v){ var vv=double.tryParse(v); if(vv!=null){ setState(()=>otR=vv); save(); } }))),
        ListTile(title:Text('交通津貼'), trailing:SizedBox(width:110, child:TextField(controller:TextEditingController(text:transB.toString()), decoration:InputDecoration(prefixText:'\$', border:OutlineInputBorder(), isDense:true), onSubmitted:(v){ var vv=double.tryParse(v); if(vv!=null){ setState(()=>transB=vv); save(); } }))),
      ])),
      for(var a in allowances) Card(child:ListTile(title:Text('${a.name} ${a.start} \$${a.amount}'), trailing:Row(mainAxisSize:MainAxisSize.min, children:[ IconButton(icon:Icon(Icons.edit), onPressed:()=>editAllowDialog(a)), IconButton(icon:Icon(Icons.delete), onPressed:(){ setState(()=>allowances.remove(a)); save(); }) ]), )),
      Divider(),
      Text('輪班模式',style:TextStyle(fontWeight:FontWeight.bold,fontSize:18)),
      for(int i=0;i<patterns.length;i++) Card(child:ListTile(title:Text(patterns[i].name), subtitle:Text('${patterns[i].codes.length~/7}行'), trailing:Row(mainAxisSize:MainAxisSize.min, children:[ IconButton(icon:Icon(Icons.edit), onPressed:()=>editPattern(Pattern(patterns[i].name, List.from(patterns[i].codes)), i)), IconButton(icon:Icon(Icons.delete), onPressed:(){ setState(()=>patterns.removeAt(i)); save(); }), ]), )),
      FilledButton.icon(onPressed:createPattern, icon:Icon(Icons.add), label:Text('新增 7 x 自定行數')),
      SizedBox(height:80),
    ]));
  }
}
