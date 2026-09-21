import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
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
  String name; List<String> codes;
  RosterPattern(this.name,this.codes);
  Map toJson()=>{'name':name,'codes':codes};
  static RosterPattern fromJson(Map m)=>RosterPattern(m['name'], List<String>.from(m['codes']));
}

class MainPage extends StatefulWidget{ @override State<MainPage> createState()=>MainPageState(); }

class MainPageState extends State<MainPage>{
  int tab=0;
  Map<String,String> roster={}; Map<String,String> notes={}; Map<String,double> extra={};
  List<Shift> shifts=[]; List<RosterPattern> patterns=[];
  DateTime focused=DateTime.now(); DateTime selected=DateTime.now();
  double standardWeekly=42; double cellFontSize=11;

  MainPageState(){
    shifts=[
      Shift('早','早更','07:00','15:30',Colors.orange.value,8,0,true),
      Shift('中','中更','15:00','23:30',Colors.blue.value,8,0,true),
      Shift('夜','夜更','23:00','07:30',Colors.indigo.value,8,80,true),
      Shift('O','例休','','',Colors.green.value,0,0,false),
      Shift('AL','年假','','',Colors.purple.value,0,0,false),
      Shift('SL','病假','','',Colors.pink.value,0,0,false),
      Shift('PH','紅日','','',Colors.red.value,0,0,false),
      Shift('OT','OT加班','','',Colors.brown.value,4,100,true),
    ];
  }

  String k(DateTime d)=>DateFormat('yyyy-MM-dd').format(d);
  int isoWeek(DateTime d){ DateTime thu=d.add(Duration(days:4-d.weekday)); DateTime jan1=DateTime(thu.year,1,1); return (thu.difference(jan1).inDays/7).floor()+1; }
  Shift getShiftByCode(String code){ for(var s in shifts){ if(s.code==code) return s; } return Shift('','','','',Colors.grey.value,0,0,false); }

  void save() async{
    var p=await SharedPreferences.getInstance();
    p.setString('roster', jsonEncode(roster)); p.setString('notes', jsonEncode(notes));
    p.setString('extra', jsonEncode(extra)); p.setString('shifts', jsonEncode(shifts.map((e)=>e.toJson()).toList()));
    p.setString('patterns', jsonEncode(patterns.map((e)=>e.toJson()).toList()));
    p.setDouble('std', standardWeekly); p.setDouble('cellFS', cellFontSize);
  }
  void load() async{
    var p=await SharedPreferences.getInstance();
    String? r=p.getString('roster'); if(r!=null&&r!=''){ var dec=jsonDecode(r); setState(()=>roster=(dec as Map).map((k,v)=>MapEntry(k.toString(),v.toString()))); }
    String? n=p.getString('notes'); if(n!=null&&n!=''){ var dec=jsonDecode(n); setState(()=>notes=(dec as Map).map((k,v)=>MapEntry(k.toString(),v.toString()))); }
    String? ex=p.getString('extra'); if(ex!=null&&ex!=''){ var dec=jsonDecode(ex); setState(()=>extra=(dec as Map).map((k,v)=>MapEntry(k.toString(),(v as num).toDouble()))); }
    String? s=p.getString('shifts'); if(s!=null&&s!=''){ var dec=jsonDecode(s) as List; setState(()=>shifts=dec.map((e)=>Shift.fromJson(e)).toList()); }
    String? pat=p.getString('patterns'); if(pat!=null&&pat!=''){ var dec=jsonDecode(pat) as List; setState(()=>patterns=dec.map((e)=>RosterPattern.fromJson(e)).toList()); }
  }
  @override void initState(){ super.initState(); load(); }

  void pickYearMonth(){
    int y=focused.year; int m=focused.month;
    showDialog(context: context, builder: (ctx){
      return AlertDialog(title: Text('快速跳至'), content: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [Text('年'), Expanded(child: Slider(value: y.toDouble(), min:2024, max:2030, divisions:6, label:y.toString(), onChanged: (v){ setState(()=>y=v.toInt()); })), Text(y.toString())]),
        Row(children: [Text('月'), Expanded(child: Slider(value: m.toDouble(), min:1, max:12, divisions:11, label:m.toString(), onChanged: (v){ setState(()=>m=v.toInt()); })), Text(m.toString())]),
      ]), actions: [TextButton(onPressed: ()=>Navigator.pop(ctx), child: Text('取消')), FilledButton(onPressed: (){ setState(()=>focused=DateTime(y,m,1)); Navigator.pop(ctx); }, child: Text('確定'))]);
    });
  }

  void exportCsv(){
    StringBuffer sb=StringBuffer(); sb.writeln('日期,星期,班次,開工,收工,工時,額外,記事,津貼');
    var keys=roster.keys.toList(); keys.sort();
    for(var key in keys){ DateTime d=DateTime.parse(key); if(d.year==focused.year&&d.month==focused.month){ var code=roster[key]!; var s=getShiftByCode(code); sb.writeln('$key,${DateFormat('E').format(d)},${s.code},${s.start},${s.end},${s.hours},${extra[key]??0},${notes[key]??''},${s.bonus}'); } }
    showDialog(context: context, builder: (c){ return AlertDialog(title: Text('分享匯出'), content: SingleChildScrollView(child: SelectableText(sb.toString())), actions: [TextButton(onPressed: ()=>Navigator.pop(c), child: Text('關閉'))]); });
  }

  void onCellTap(DateTime d){
    setState(()=>selected=d);
    TextEditingController noteC=TextEditingController(text: notes[k(d)]??'');
    TextEditingController exC=TextEditingController(text: (extra[k(d)]??0).toString());
    String curCode=roster[k(d)]??'';
    showModalBottomSheet(context: context, isScrollControlled:true, builder: (ctx){
      return StatefulBuilder(builder: (ctx,setM){
        return Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, top:16, left:16, right:16), child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(DateFormat('yyyy-MM-dd E').format(d), style: TextStyle(fontWeight: FontWeight.bold, fontSize:18)),
          SizedBox(height:8),
          Wrap(spacing:6, runSpacing:6, children: [ for(var s in shifts) ChoiceChip(label: Text(s.code), selected: curCode==s.code, selectedColor: s.color.withOpacity(0.4), onSelected: (v){ setM(()=>curCode=v?s.code:''); }), ]),
          SizedBox(height:12),
          TextField(controller: noteC, decoration: InputDecoration(labelText:'記事 / OT詳情', border: OutlineInputBorder())),
          SizedBox(height:8),
          TextField(controller: exC, decoration: InputDecoration(labelText:'額外工時', border: OutlineInputBorder()), keyboardType: TextInputType.number),
          SizedBox(height:12),
          FilledButton(onPressed: (){ setState((){ if(curCode=='') roster.remove(k(d)); else roster[k(d)]=curCode; if(noteC.text=='') notes.remove(k(d)); else notes[k(d)]=noteC.text; double? vv=double.tryParse(exC.text); if(vv==null||vv==0) extra.remove(k(d)); else extra[k(d)]=vv; save(); }); Navigator.pop(ctx); }, child: Text('保存')),
          SizedBox(height:20),
        ]));
      });
    });
  }

  void createPattern(){
    TextEditingController nameC=TextEditingController(text:'我的22行${patterns.length+1}');
    showDialog(context: context, builder: (ctx){ return AlertDialog(title: Text('創造特別模式 7x22'), content: TextField(controller: nameC, decoration: InputDecoration(labelText:'模式名稱')), actions: [TextButton(onPressed: ()=>Navigator.pop(ctx), child: Text('取消')), FilledButton(onPressed: (){ Navigator.pop(ctx); openPatternEditor(RosterPattern(nameC.text, List.filled(22*7, shifts.first.code))); }, child: Text('下一步'))]); });
  }

  // 新版：點格子彈出選擇班次，唔使狂撳循環
  void openPatternEditor(RosterPattern pat){
    showDialog(context: context, builder: (ctx){
      return StatefulBuilder(builder: (ctx,setM){
        return AlertDialog(
          title: Text('${pat.name} 點格子選擇班次'),
          content: SizedBox(width: double.maxFinite, height:420, child: Column(children: [
            Wrap(spacing:4, children: [ for(var s in shifts) Container(padding: EdgeInsets.symmetric(horizontal:6, vertical:2), decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(4)), child: Text(s.code, style: TextStyle(color:Colors.white, fontSize:10))) ]),
            SizedBox(height:8),
            Expanded(child: GridView.builder(gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:7, childAspectRatio:0.9), itemCount: pat.codes.length, itemBuilder: (c,i){
              String code=pat.codes[i]; Shift s=getShiftByCode(code);
              return GestureDetector(onTap: (){
                // 彈出選擇班次
                showModalBottomSheet(context: ctx, builder: (b){
                  return Container(padding: EdgeInsets.all(16), child: Wrap(spacing:8, runSpacing:8, children: [
                    for(var ss in shifts) ChoiceChip(label: Text(ss.code), selected: ss.code==code, onSelected: (v){ setM(()=>pat.codes[i]=ss.code); Navigator.pop(b); }, selectedColor: ss.color.withOpacity(0.4)),
                  ]));
                });
              }, child: Container(margin: EdgeInsets.all(2), decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.white)), child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text('${i+1}', style: TextStyle(color:Colors.white, fontSize:9)), Text(code, style: TextStyle(color:Colors.white, fontWeight: FontWeight.bold, fontSize:11))]))));
            })),
          ])),
          actions: [TextButton(onPressed: ()=>Navigator.pop(ctx), child: Text('取消')), FilledButton(onPressed: (){ setState(()=>patterns.add(pat)); save(); Navigator.pop(ctx); }, child: Text('保存模式'))]
        );
      });
    });
  }

  void applyPattern(){
    if(patterns.isEmpty){ ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('請先創造模式'))); return; }
    RosterPattern sel=patterns.first; DateTime sDate=DateTime(focused.year,focused.month,1); DateTime eDate=DateTime(focused.year,focused.month+1,0);
    showDialog(context: context, builder: (ctx){ return StatefulBuilder(builder: (ctx,setM){ return AlertDialog(title: Text('套用模式排更'), content: Column(mainAxisSize: MainAxisSize.min, children: [ DropdownButton<RosterPattern>(value: sel, isExpanded:true, items: [for(var p in patterns) DropdownMenuItem(value:p, child: Text(p.name))], onChanged: (v){ if(v!=null) setM(()=>sel=v); }), ListTile(title: Text('開始 ${DateFormat('yyyy-MM-dd').format(sDate)}'), onTap: () async { DateTime? d=await showDatePicker(context: ctx, firstDate: DateTime(2024), lastDate: DateTime(2030), initialDate: sDate); if(d!=null) setM(()=>sDate=d); }), ListTile(title: Text('結束 ${DateFormat('yyyy-MM-dd').format(eDate)}'), onTap: () async { DateTime? d=await showDatePicker(context: ctx, firstDate: DateTime(2024), lastDate: DateTime(2030), initialDate: eDate); if(d!=null) setM(()=>eDate=d); }), ]), actions: [TextButton(onPressed: ()=>Navigator.pop(ctx), child: Text('取消')), FilledButton(onPressed: (){ setState((){ int idx=0; for(DateTime d=sDate;!d.isAfter(eDate); d=d.add(Duration(days:1))){ roster[k(d)]=sel.codes[idx%sel.codes.length]; idx++; } save(); }); Navigator.pop(ctx); }, child: Text('開始排更'))]); }); });
  }

  @override Widget build(BuildContext context){
    return Scaffold(body: [buildCal(), buildReport(), buildSettings()][tab], bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (i){setState(()=>tab=i);}, destinations: [NavigationDestination(icon: Icon(Icons.calendar_month), label:'月曆'), NavigationDestination(icon: Icon(Icons.bar_chart), label:'報表'), NavigationDestination(icon: Icon(Icons.settings), label:'設定')]));
  }

  Widget buildCal(){
    Shift? selShift = roster.containsKey(k(selected))? getShiftByCode(roster[k(selected)]!) : null;
    return Scaffold(
      appBar: AppBar(title: GestureDetector(onTap: pickYearMonth, child: Row(children: [Text('W${isoWeek(focused).toString().padLeft(2,'0')} ${DateFormat('yyyy年M月').format(focused)}'), Icon(Icons.arrow_drop_down)])), actions: [
        IconButton(onPressed: createPattern, icon: Icon(Icons.grid_view), tooltip: '新增模式'),
        IconButton(onPressed: applyPattern, icon: Icon(Icons.playlist_play), tooltip: '套用模式'),
        IconButton(onPressed: exportCsv, icon: Icon(Icons.share), tooltip: '分享'),
      ]),
      body: Column(children: [
        Expanded(flex: 3, child: SingleChildScrollView(child: TableCalendar(
          firstDay: DateTime(2024,1,1), lastDay: DateTime(2030,12,31), focusedDay: focused,
          rowHeight: 72, daysOfWeekHeight: 22,
          startingDayOfWeek: StartingDayOfWeek.monday, headerVisible:false,
          selectedDayPredicate: (d)=>isSameDay(selected,d),
          onDaySelected: (s,f){ setState((){selected=s; focused=f;}); },
          onPageChanged: (f){ setState(()=>focused=f); },
          calendarBuilders: CalendarBuilders(
            defaultBuilder: (ctx,day,f){
              String key=k(day); String? code=roster[key]; Shift? sh=code!=null?getShiftByCode(code):null; bool isToday=isSameDay(day, DateTime.now()); bool isSel=isSameDay(day, selected); bool isMon=day.weekday==1;
              return GestureDetector(
                onTap: ()=>setState(()=>selected=day),
                onLongPress: ()=>onCellTap(day),
                child: Container(margin: EdgeInsets.all(2), decoration: BoxDecoration(color: sh!=null?sh.color:Colors.grey.shade100, borderRadius: BorderRadius.circular(8), border: isToday?Border.all(color:Colors.amber, width:3): isSel?Border.all(color:Colors.indigo, width:2.5):null), child: Stack(children: [
                  if(isMon) Positioned(top:2, left:2, child: Container(padding: EdgeInsets.symmetric(horizontal:3, vertical:1), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(3)), child: Text('W${isoWeek(day)}', style: TextStyle(color:Colors.white, fontSize:7)))),
                  Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(day.day.toString(), style: TextStyle(fontSize: cellFontSize+2, fontWeight: FontWeight.bold, color: sh!=null?Colors.white:Colors.black87)),
                    if(sh!=null) Text(sh.code, style: TextStyle(fontSize: cellFontSize, color:Colors.white)),
                  ])),
                ])));
            },
          ),
        ))),
        // 下方白色空位放大顯示所有內容
        Expanded(flex: 2, child: Container(width: double.infinity, color: Colors.white, padding: EdgeInsets.all(16), child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Container(padding: EdgeInsets.symmetric(horizontal:12, vertical:6), decoration: BoxDecoration(color: selShift?.color??Colors.grey.shade200, borderRadius: BorderRadius.circular(20)), child: Text('${DateFormat('MM/dd EEEE').format(selected)} ${roster[k(selected)]??'未排班'}', style: TextStyle(fontSize:18, fontWeight: FontWeight.bold, color: selShift!=null?Colors.white:Colors.black87))), Spacer(), IconButton(onPressed: ()=>onCellTap(selected), icon: Icon(Icons.edit))]),
          SizedBox(height:12),
          if(selShift!=null)...[
            Row(children: [Icon(Icons.access_time, size:18), SizedBox(width:6), Text('${selShift.start} - ${selShift.end} ${selShift.hours}小時 津貼 \$${selShift.bonus}', style: TextStyle(fontSize:15))]),
            SizedBox(height:8),
          ],
          if(extra[k(selected)]!=null) Row(children: [Icon(Icons.timer, size:18, color: Colors.orange), SizedBox(width:6), Text('額外工時: +${extra[k(selected)]}h', style: TextStyle(fontSize:15, color: Colors.orange, fontWeight: FontWeight.bold))]),
          if(notes[k(selected)]!=null)...[
            SizedBox(height:8),
            Container(width: double.infinity, padding: EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amber.shade200)), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.sticky_note_2, size:18), SizedBox(width:6), Expanded(child: Text('${notes[k(selected)]}', style: TextStyle(fontSize:15)))])),
          ],
          if(notes[k(selected)]==null && extra[k(selected)]==null && selShift==null) Text('輕按上方日期選擇，長按編輯記事/OT/額外工時', style: TextStyle(color: Colors.grey)),
          SizedBox(height:12),
          Text('週 ${isoWeek(selected)} 工時: ${((){ DateTime mon=selected.subtract(Duration(days:selected.weekday-1)); double sum=0; for(int i=0;i<7;i++){ String kk=k(mon.add(Duration(days:i))); if(roster.containsKey(kk)) sum+=getShiftByCode(roster[kk]!).hours + (extra[kk]??0); } return sum; })()}h / $standardWeekly h', style: TextStyle(fontSize:13, color: Colors.grey.shade700)),
        ])))),
      ]),
    );
  }
  Widget buildReport(){ return Scaffold(appBar: AppBar(title: Text('報表')), body: ListView(padding: EdgeInsets.all(16), children: [Text('本月 ${roster.keys.where((e){ var d=DateTime.parse(e); return d.year==focused.year&&d.month==focused.month; }).length} 日已排')])) ;}
  Widget buildSettings(){
    return Scaffold(appBar: AppBar(title: Text('設定')), body: ListView(padding: EdgeInsets.all(16), children: [
      Text('格子文字大小 ${cellFontSize.toStringAsFixed(0)}'), Slider(value: cellFontSize, min:8, max:20, divisions:12, label: cellFontSize.toStringAsFixed(0), onChanged: (v){ setState(()=>cellFontSize=v); save(); }),
      Divider(),
      for(var s in shifts) Card(child: ListTile(leading: CircleAvatar(backgroundColor: s.color, child: Text(s.code, style: TextStyle(color:Colors.white, fontSize:10))), title: Text('${s.name} ${s.code}'))),
      Divider(),
      Text('自訂排更模式', style: TextStyle(fontWeight: FontWeight.bold)),
      for(var p in patterns) Card(child: ListTile(title: Text(p.name), subtitle: Text('${p.codes.length}日'), trailing: IconButton(icon: Icon(Icons.delete), onPressed: (){ setState(()=>patterns.remove(p)); save(); }))),
      FilledButton.icon(onPressed: createPattern, icon: Icon(Icons.add), label: Text('新增 7x22 模式')),
    ]));
  }
}
