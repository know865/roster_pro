import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() { runApp(MaterialApp(debugShowCheckedModeBanner:false, theme: ThemeData(useMaterial3:true, colorSchemeSeed: Colors.indigo), home: MainPage())); }

class Shift {
  String code,name,start,end; int colorValue; double hours,bonus; bool isWork;
  Shift(this.code,this.name,this.start,this.end,this.colorValue,this.hours,this.bonus,this.isWork);
  Map toJson()=>{'code':code,'name':name,'start':start,'end':end,'colorValue':colorValue,'hours':hours,'bonus':bonus,'isWork':isWork};
  static Shift fromJson(Map m)=>Shift(m['code'],m['name'],m['start'],m['end'],m['colorValue'],(m['hours']as num).toDouble(),(m['bonus']as num).toDouble(),m['isWork']);
  Color get color=>Color(colorValue);
}
class RosterPattern{
  String name; List<String> codes; RosterPattern(this.name,this.codes);
  Map toJson()=>{'name':name,'codes':codes};
  static RosterPattern fromJson(Map m)=>RosterPattern(m['name'], List<String>.from(m['codes']));
}

class MainPage extends StatefulWidget{ @override State<MainPage> createState()=>MainPageState(); }

class MainPageState extends State<MainPage>{
  int tab=0;
  Map<String,String> roster={}, notes={}; Map<String,double> extra={};
  List<Shift> shifts=[]; List<RosterPattern> patterns=[];
  DateTime focused=DateTime.now(), selected=DateTime.now();
  double cellFontSize=11, standardWeekly=42;
  double otRate=100, earlyBonus=20, nightBonus=80, overnightBonus=120, transportBonus=20;

  MainPageState(){
    shifts=[
      Shift('早','早更','07:00','15:30',Colors.orange.value,8,20,true),
      Shift('中','中更','15:00','23:30',Colors.blue.value,8,0,true),
      Shift('夜','夜更','23:00','07:30',Colors.indigo.value,8,80,true),
      Shift('宵','通宵','23:30','08:00',Colors.deepPurple.value,8,120,true),
      Shift('O','例休','','',Colors.green.value,0,0,false),
      Shift('AL','年假','','',Colors.purple.value,0,0,false),
      Shift('SL','病假','','',Colors.pink.value,0,0,false),
      Shift('PH','紅日','','',Colors.red.value,0,0,false),
      Shift('OT','OT加班','','',Colors.brown.value,4,100,true),
    ];
  }
  String k(DateTime d)=>DateFormat('yyyy-MM-dd').format(d);
  int isoWeek(DateTime d){ DateTime thu=d.add(Duration(days:4-d.weekday)); DateTime jan1=DateTime(thu.year,1,1); return (thu.difference(jan1).inDays/7).floor()+1; }
  Shift getShiftByCode(String c){ for(var s in shifts){ if(s.code==c) return s; } return Shift('','','','',Colors.grey.value,0,0,false); }
  double hoursOf(DateTime d){ var key=k(d); if(!roster.containsKey(key)) return 0; return getShiftByCode(roster[key]!).hours + (extra[key]??0); }

  void save() async{
    var p=await SharedPreferences.getInstance();
    p.setString('roster', jsonEncode(roster)); p.setString('notes', jsonEncode(notes)); p.setString('extra', jsonEncode(extra));
    p.setString('shifts', jsonEncode(shifts.map((e)=>e.toJson()).toList())); p.setString('patterns', jsonEncode(patterns.map((e)=>e.toJson()).toList()));
    p.setDouble('std', standardWeekly); p.setDouble('cellFS', cellFontSize);
    p.setDouble('otR', otRate); p.setDouble('earlyB', earlyBonus); p.setDouble('nightB', nightBonus); p.setDouble('overB', overnightBonus); p.setDouble('transB', transportBonus);
  }
  void load() async{
    var p=await SharedPreferences.getInstance();
    var r=p.getString('roster'); if(r!=null&&r!=''){ var dec=jsonDecode(r); setState(()=>roster=(dec as Map).map((k,v)=>MapEntry(k.toString(),v.toString()))); }
    var n=p.getString('notes'); if(n!=null&&n!=''){ var dec=jsonDecode(n); setState(()=>notes=(dec as Map).map((k,v)=>MapEntry(k.toString(),v.toString()))); }
    var ex=p.getString('extra'); if(ex!=null&&ex!=''){ var dec=jsonDecode(ex); setState(()=>extra=(dec as Map).map((k,v)=>MapEntry(k.toString(),(v as num).toDouble()))); }
    var s=p.getString('shifts'); if(s!=null&&s!=''){ var dec=jsonDecode(s) as List; setState(()=>shifts=dec.map((e)=>Shift.fromJson(e)).toList()); }
    var pat=p.getString('patterns'); if(pat!=null&&pat!=''){ var dec=jsonDecode(pat) as List; setState(()=>patterns=dec.map((e)=>RosterPattern.fromJson(e)).toList()); }
    setState((){
      standardWeekly=p.getDouble('std')??42; cellFontSize=p.getDouble('cellFS')??11;
      otRate=p.getDouble('otR')??100; earlyBonus=p.getDouble('earlyB')??20; nightBonus=p.getDouble('nightB')??80; overnightBonus=p.getDouble('overB')??120; transportBonus=p.getDouble('transB')??20;
    });
  }
  @override void initState(){ super.initState(); load(); }

  void goToday(){ setState((){ focused=DateTime.now(); selected=DateTime.now(); }); }

  void pickYearMonth(){
    int selY=focused.year, selM=focused.month;
    showDialog(context: context, builder: (ctx){
      return StatefulBuilder(builder: (ctx,setM){
        return AlertDialog(title: Text('選擇年月', style: TextStyle(fontSize:22, fontWeight: FontWeight.bold)), content: SizedBox(width: 320, height: 380, child: Column(children: [
          Text('年份 2024-2030', style: TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: GridView.count(crossAxisCount:4, childAspectRatio:1.6, children: [ for(int y=2024;y<=2030;y++) Padding(padding: EdgeInsets.all(3), child: ChoiceChip(label: Text(y.toString(), style: TextStyle(fontSize:15)), selected: selY==y, onSelected: (v){ setM(()=>selY=y); })) ])),
          Divider(),
          Text('月份', style: TextStyle(fontWeight: FontWeight.bold)),
          GridView.count(shrinkWrap:true, crossAxisCount:4, childAspectRatio:1.6, children: [ for(int m=1;m<=12;m++) Padding(padding: EdgeInsets.all(3), child: ChoiceChip(label: Text('${m}月'), selected: selM==m, onSelected: (v){ setM(()=>selM=m); })) ]),
        ])), actions: [TextButton(onPressed: ()=>Navigator.pop(ctx), child: Text('取消')), FilledButton(onPressed: (){ setState(()=>focused=DateTime(selY,selM,1)); Navigator.pop(ctx); }, child: Text('跳轉', style: TextStyle(fontSize:16)))]);
      });
    });
  }

  void exportCsv(){
    StringBuffer sb=StringBuffer(); sb.writeln('日期,星期,班次,工時,額外,津貼,記事');
    var keys=roster.keys.toList()..sort();
    for(var key in keys){ var d=DateTime.parse(key); if(d.year==focused.year&&d.month==focused.month){ var code=roster[key]!; var s=getShiftByCode(code); double bon=s.bonus; if(s.code=='早') bon+=earlyBonus; if(s.code=='夜') bon+=nightBonus; if(s.code=='宵') bon+=overnightBonus; if(s.code=='OT') bon=otRate*(s.hours+(extra[key]??0)); sb.writeln('$key,${DateFormat('E').format(d)},${s.code},${s.hours},${extra[key]??0},$bon,${notes[key]??''}'); } }
    showDialog(context: context, builder: (c){ return AlertDialog(title: Text('分享匯出'), content: SingleChildScrollView(child: SelectableText(sb.toString())), actions: [TextButton(onPressed: ()=>Navigator.pop(c), child: Text('關閉'))]); });
  }

  void onCellEdit(DateTime d){
    TextEditingController noteC=TextEditingController(text: notes[k(d)]??'');
    TextEditingController exC=TextEditingController(text: (extra[k(d)]??0).toString());
    String curCode=roster[k(d)]??'';
    showModalBottomSheet(context: context, isScrollControlled:true, builder: (ctx){
      return StatefulBuilder(builder: (ctx,setM){
        return Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, top:16, left:16, right:16), child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(DateFormat('yyyy-MM-dd EEEE').format(d), style: TextStyle(fontWeight: FontWeight.bold, fontSize:18)),
          Wrap(spacing:6, children: [ for(var s in shifts) ChoiceChip(label: Text(s.code), selected: curCode==s.code, selectedColor: s.color.withOpacity(0.4), onSelected: (v){ setM(()=>curCode=v?s.code:''); }) ]),
          SizedBox(height:12),
          TextField(controller: noteC, decoration: InputDecoration(labelText:'記事 / OT詳情', border: OutlineInputBorder())),
          SizedBox(height:8),
          TextField(controller: exC, decoration: InputDecoration(labelText:'額外OT工時 (例如 2)', border: OutlineInputBorder()), keyboardType: TextInputType.number),
          SizedBox(height:12),
          FilledButton(onPressed: (){ setState((){ if(curCode=='') roster.remove(k(d)); else roster[k(d)]=curCode; if(noteC.text=='') notes.remove(k(d)); else notes[k(d)]=noteC.text; var vv=double.tryParse(exC.text); if(vv==null||vv==0) extra.remove(k(d)); else extra[k(d)]=vv; save(); }); Navigator.pop(ctx); }, child: Text('保存')),
          SizedBox(height:20),
        ]));
      });
    });
  }

  void createPattern(){
    TextEditingController nameC=TextEditingController(text:'我的22行${patterns.length+1}');
    showDialog(context: context, builder: (ctx){ return AlertDialog(title: Text('創造模式 7x22'), content: TextField(controller: nameC, decoration: InputDecoration(labelText:'名稱')), actions: [TextButton(onPressed: ()=>Navigator.pop(ctx), child: Text('取消')), FilledButton(onPressed: (){ Navigator.pop(ctx); openPatternEditor(RosterPattern(nameC.text, List.filled(22*7, shifts.first.code))); }, child: Text('下一步'))]); });
  }
  void openPatternEditor(RosterPattern pat){
    showDialog(context: context, builder: (ctx){
      return StatefulBuilder(builder: (ctx,setM){
        return AlertDialog(title: Text(pat.name+' 點格子選班'), content: SizedBox(width: double.maxFinite, height:420, child: GridView.builder(gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:7, childAspectRatio:0.9), itemCount: pat.codes.length, itemBuilder: (c,i){
          String code=pat.codes[i]; Shift s=getShiftByCode(code);
          return GestureDetector(onTap: (){
            showModalBottomSheet(context: ctx, builder: (b){ return Container(padding: EdgeInsets.all(16), child: Wrap(spacing:8, children: [ for(var ss in shifts) ChoiceChip(label: Text(ss.code), selected: ss.code==code, onSelected: (v){ setM(()=>pat.codes[i]=ss.code); Navigator.pop(b); }) ])); });
          }, child: Container(margin: EdgeInsets.all(2), decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(6)), child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text('${i+1}', style: TextStyle(color:Colors.white, fontSize:8)), Text(code, style: TextStyle(color:Colors.white, fontWeight: FontWeight.bold, fontSize:11))]))));
        })), actions: [TextButton(onPressed: ()=>Navigator.pop(ctx), child: Text('取消')), FilledButton(onPressed: (){ setState(()=>patterns.add(pat)); save(); Navigator.pop(ctx); }, child: Text('保存'))]);
      });
    });
  }
  void applyPattern(){
    if(patterns.isEmpty){ ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('請先創造模式'))); return; }
    RosterPattern sel=patterns.first; DateTime sDate=DateTime(focused.year,focused.month,1); DateTime eDate=DateTime(focused.year,focused.month+1,0);
    showDialog(context: context, builder: (ctx){ return StatefulBuilder(builder: (ctx,setM){ return AlertDialog(title: Text('套用模式排更'), content: Column(mainAxisSize: MainAxisSize.min, children: [ DropdownButton<RosterPattern>(value: sel, isExpanded:true, items: [for(var p in patterns) DropdownMenuItem(value:p, child: Text(p.name))], onChanged: (v){ if(v!=null) setM(()=>sel=v); }), ListTile(title: Text('開始 ${DateFormat('yyyy-MM-dd').format(sDate)}'), onTap: () async { DateTime? d=await showDatePicker(context: ctx, firstDate: DateTime(2024), lastDate: DateTime(2030), initialDate: sDate); if(d!=null) setM(()=>sDate=d); }), ListTile(title: Text('結束 ${DateFormat('yyyy-MM-dd').format(eDate)}'), onTap: () async { DateTime? d=await showDatePicker(context: ctx, firstDate: DateTime(2024), lastDate: DateTime(2030), initialDate: eDate); if(d!=null) setM(()=>eDate=d); }), ]), actions: [TextButton(onPressed: ()=>Navigator.pop(ctx), child: Text('取消')), FilledButton(onPressed: (){ setState((){ int idx=0; for(DateTime d=sDate;!d.isAfter(eDate); d=d.add(Duration(days:1))){ roster[k(d)]=sel.codes[idx%sel.codes.length]; idx++; } save(); }); Navigator.pop(ctx); }, child: Text('開始排更'))]); }); });
  }

  List<DateTime> daysInMonth(DateTime month){
    DateTime first=DateTime(month.year,month.month,1);
    int offset=first.weekday-1; DateTime start=first.subtract(Duration(days: offset));
    return List.generate(42, (i)=>start.add(Duration(days:i)));
  }

  @override Widget build(BuildContext context){
    return Scaffold(body: [buildCal(), buildReport(), buildSettings()][tab], bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (i){setState(()=>tab=i);}, destinations: [NavigationDestination(icon: Icon(Icons.calendar_month), label:'月曆'), NavigationDestination(icon: Icon(Icons.bar_chart), label:'報表'), NavigationDestination(icon: Icon(Icons.settings), label:'設定')]));
  }

  Widget buildCal(){
    Shift? selShift = roster.containsKey(k(selected))? getShiftByCode(roster[k(selected)]!) : null;
    var days=daysInMonth(focused);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: Icon(Icons.today), tooltip: '回今日', onPressed: goToday),
        title: InkWell(onTap: pickYearMonth, child: Row(mainAxisSize: MainAxisSize.min, children: [Text('W${isoWeek(focused).toString().padLeft(2,'0')} ${focused.year}年${focused.month}月', style: TextStyle(fontSize:22, fontWeight: FontWeight.w900)), Icon(Icons.arrow_drop_down)])),
        actions: [IconButton(onPressed: createPattern, icon: Icon(Icons.grid_view)), IconButton(onPressed: applyPattern, icon: Icon(Icons.playlist_play)), IconButton(onPressed: exportCsv, icon: Icon(Icons.share))],
      ),
      body: Column(children: [
        Row(children: [ for(var w in ['Mon','Tue','Wed','Thu','Fri','Sat','Sun']) Expanded(child: Center(child: Text(w, style: TextStyle(fontWeight: FontWeight.bold, fontSize:12)))) ]),
        SizedBox(height:4),
        Expanded(flex: 3, child: GridView.builder(padding: EdgeInsets.all(4), gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:7, childAspectRatio:0.85, crossAxisSpacing:4, mainAxisSpacing:4), itemCount: days.length, itemBuilder: (c,i){
          DateTime day=days[i]; bool outside=day.month!=focused.month; if(outside&&day.month>focused.month&&i<14) return SizedBox(); // hide top extra
          String key=k(day); String? code=roster[key]; Shift? sh=code!=null?getShiftByCode(code):null;
          bool isToday=DateFormat('yyyy-MM-dd').format(day)==DateFormat('yyyy-MM-dd').format(DateTime.now());
          bool isSel=DateFormat('yyyy-MM-dd').format(day)==DateFormat('yyyy-MM-dd').format(selected);
          bool isMon=day.weekday==1;
          if(outside) return Container(margin: EdgeInsets.all(2), child: Center(child: Text(day.day.toString(), style: TextStyle(color: Colors.grey.shade400))));
          return GestureDetector(
            onTap: (){ setState(()=>selected=day); },
            onLongPress: ()=>onCellEdit(day),
            child: Container(decoration: BoxDecoration(color: sh!=null?sh.color:Colors.grey.shade100, borderRadius: BorderRadius.circular(10), border: isToday?Border.all(color:Colors.amber, width:3): isSel?Border.all(color:Colors.indigo, width:2.5):null), child: Stack(children: [
              if(isMon) Positioned(top:2, left:2, child: Container(padding: EdgeInsets.symmetric(horizontal:3, vertical:1), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(3)), child: Text('W${isoWeek(day)}', style: TextStyle(color:Colors.white, fontSize:7)))),
              Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(day.day.toString(), style: TextStyle(fontSize: cellFontSize+3, fontWeight: FontWeight.bold, color: sh!=null?Colors.white:Colors.black87)),
                if(sh!=null) Text(sh.code, style: TextStyle(fontSize: cellFontSize, color:Colors.white, fontWeight: FontWeight.w600)),
                if(extra.containsKey(key)) Text('+${extra[key]}h', style: TextStyle(fontSize:8, color:Colors.white)),
              ])),
            ])),
          );
        })),
        Divider(height:1),
        Expanded(flex: 2, child: Container(width: double.infinity, color: Colors.white, padding: EdgeInsets.all(16), child: ListView(children: [
          Row(children: [
            Container(padding: EdgeInsets.symmetric(horizontal:14, vertical:8), decoration: BoxDecoration(color: selShift?.color??Colors.grey.shade300, borderRadius: BorderRadius.circular(24)), child: Text('${DateFormat('MM/dd EEEE').format(selected)} ${roster[k(selected)]??'未排'}', style: TextStyle(fontSize:18, fontWeight: FontWeight.bold, color: selShift!=null?Colors.white:Colors.black87))),
            Spacer(),
            FilledButton.icon(onPressed: ()=>onCellEdit(selected), icon: Icon(Icons.edit, size:16), label: Text('編輯'))
          ]),
          SizedBox(height:10),
          if(selShift!=null) Card(child: ListTile(leading: Icon(Icons.access_time), title: Text('${selShift.name} ${selShift.start}-${selShift.end}'), subtitle: Text('${selShift.hours}小時 + ${extra[k(selected)]??0} OT'))),
          if(selShift!=null) Card(color: Colors.green.shade50, child: ListTile(leading: Icon(Icons.payments), title: Text('津貼: \$${((){ double b=selShift.bonus; if(selShift.code=='早') b+=earlyBonus; if(selShift.code=='夜') b+=nightBonus; if(selShift.code=='宵') b+=overnightBonus; if(selShift.code=='OT') b=otRate*(selShift.hours+(extra[k(selected)]??0)); return b; })()}'))),
          if(notes[k(selected)]!=null) Card(color: Colors.amber.shade50, child: ListTile(leading: Icon(Icons.sticky_note_2), title: Text(notes[k(selected)]!, style: TextStyle(fontSize:16)))),
        ]))),
      ]),
    );
  }

  Widget buildReport(){
    // 統計當月
    DateTime month=focused; double totalH=0, totalOT=0, totalTrans=0, totalEarly=0, totalNight=0, totalOver=0, totalOTPay=0;
    int countEarly=0,countNight=0,countOver=0,countOT=0,countWork=0;
    for(var e in roster.entries){
      DateTime d=DateTime.parse(e.key); if(d.year!=month.year||d.month!=month.month) continue;
      var s=getShiftByCode(e.value); double ex=extra[e.key]??0;
      totalH+=s.hours+ex;
      if(s.isWork) { countWork++; totalTrans+=transportBonus; }
      if(s.code=='早'){ countEarly++; totalEarly+=earlyBonus; }
      if(s.code=='夜'){ countNight++; totalNight+=nightBonus; }
      if(s.code=='宵'){ countOver++; totalOver+=overnightBonus; }
      if(s.code=='OT' || ex>0){ double otH = (s.code=='OT'?s.hours:0)+ex; totalOT+=otH; totalOTPay+=otH*otRate; countOT++; }
    }
    double totalAll=totalTrans+totalEarly+totalNight+totalOver+totalOTPay;
    return Scaffold(appBar: AppBar(title: Text('${month.year}年${month.month}月 報表'), actions: [IconButton(onPressed: exportCsv, icon: Icon(Icons.share))]), body: ListView(padding: EdgeInsets.all(16), children: [
      Card(child: ListTile(title: Text('總工時'), subtitle: Text('${totalH}h / 標準 ${standardWeekly*4}h'), trailing: Text('${(totalH-standardWeekly*4).toStringAsFixed(1)}h', style: TextStyle(fontWeight: FontWeight.bold)))),
      Card(child: ListTile(title: Text('返工日數'), subtitle: Text('$countWork 日 早:$countEarly 夜:$countNight 宵:$countOver OT:$countOT'))),
      Card(color: Colors.orange.shade50, child: ListTile(title: Text('OT統計'), subtitle: Text('OT時數 ${totalOT}h x \$$otRate'), trailing: Text('\$${totalOTPay.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.bold)))),
      Card(child: ListTile(title: Text('交通津貼'), subtitle: Text('$countWork 日 x \$$transportBonus'), trailing: Text('\$${totalTrans.toStringAsFixed(0)}'))),
      Card(child: ListTile(title: Text('早班津貼'), subtitle: Text('$countEarly 次 x \$$earlyBonus'), trailing: Text('\$${totalEarly.toStringAsFixed(0)}'))),
      Card(child: ListTile(title: Text('夜班津貼'), subtitle: Text('$countNight 次 x \$$nightBonus'), trailing: Text('\$${totalNight.toStringAsFixed(0)}'))),
      Card(child: ListTile(title: Text('通宵津貼'), subtitle: Text('$countOver 次 x \$$overnightBonus'), trailing: Text('\$${totalOver.toStringAsFixed(0)}'))),
      Divider(),
      Card(color: Colors.indigo.shade50, child: ListTile(title: Text('本月津貼總額', style: TextStyle(fontWeight: FontWeight.bold, fontSize:18)), trailing: Text('\$${totalAll.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.bold, fontSize:22, color: Colors.indigo)))),
      SizedBox(height:12),
      Text('OT計算: OT班 + 額外工時都按 \$$otRate /小時 計', style: TextStyle(fontSize:12, color: Colors.grey)),
    ]));
  }

  Widget buildSettings(){
    return Scaffold(appBar: AppBar(title: Text('設定')), body: ListView(padding: EdgeInsets.all(16), children: [
      Text('顯示', style: TextStyle(fontWeight: FontWeight.bold)),
      Row(children: [Text('格子文字 ${cellFontSize.toStringAsFixed(0)}'), Expanded(child: Slider(value: cellFontSize, min:8, max:20, divisions:12, label: cellFontSize.toStringAsFixed(0), onChanged: (v){ setState(()=>cellFontSize=v); save(); }))]),
      Divider(),
      Text('津貼設定 (報表會自動計)', style: TextStyle(fontWeight: FontWeight.bold)),
      ListTile(title: Text('OT 時薪 \$${otRate.toStringAsFixed(0)}'), subtitle: Slider(value: otRate, min:0, max:300, divisions:30, label: otRate.toStringAsFixed(0), onChanged: (v){ setState(()=>otRate=v); save(); })),
      ListTile(title: Text('早班津貼 \$${earlyBonus.toStringAsFixed(0)}'), subtitle: Slider(value: earlyBonus, min:0, max:100, divisions:20, label: earlyBonus.toStringAsFixed(0), onChanged: (v){ setState(()=>earlyBonus=v); shifts.firstWhere((e)=>e.code=='早').bonus=v; save(); })),
      ListTile(title: Text('夜班津貼 \$${nightBonus.toStringAsFixed(0)}'), subtitle: Slider(value: nightBonus, min:0, max:200, divisions:20, label: nightBonus.toStringAsFixed(0), onChanged: (v){ setState(()=>nightBonus=v); save(); })),
      ListTile(title: Text('通宵津貼 \$${overnightBonus.toStringAsFixed(0)}'), subtitle: Slider(value: overnightBonus, min:0, max:300, divisions:30, label: overnightBonus.toStringAsFixed(0), onChanged: (v){ setState(()=>overnightBonus=v); save(); })),
      ListTile(title: Text('交通津貼 \$${transportBonus.toStringAsFixed(0)}'), subtitle: Slider(value: transportBonus, min:0, max:100, divisions:20, label: transportBonus.toStringAsFixed(0), onChanged: (v){ setState(()=>transportBonus=v); save(); })),
      Divider(),
      Text('班次', style: TextStyle(fontWeight: FontWeight.bold)),
      for(var s in shifts) Card(child: ListTile(leading: CircleAvatar(backgroundColor: s.color, child: Text(s.code, style: TextStyle(color:Colors.white, fontSize:10))), title: Text('${s.name} ${s.code} ${s.start}-${s.end} ${s.hours}h 津貼\$${s.bonus}'))),
      Divider(),
      Text('自訂模式', style: TextStyle(fontWeight: FontWeight.bold)),
      for(var p in patterns) Card(child: ListTile(title: Text(p.name), subtitle: Text('${p.codes.length}日'), trailing: IconButton(icon: Icon(Icons.delete), onPressed: (){ setState(()=>patterns.remove(p)); save(); }))),
      FilledButton.icon(onPressed: createPattern, icon: Icon(Icons.add), label: Text('新增 7x22 模式')),
    ]));
  }
}
