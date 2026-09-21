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
  double standardWeekly=42; double cellFontSize=11; double transportBonus=20; double holidayBonus=100;

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
  double hoursOf(DateTime d){ var key=k(d); if(!roster.containsKey(key)) return 0; return getShiftByCode(roster[key]!).hours + (extra[key]??0); }

  void save() async{
    var p=await SharedPreferences.getInstance();
    p.setString('roster', jsonEncode(roster)); p.setString('notes', jsonEncode(notes));
    p.setString('extra', jsonEncode(extra)); p.setString('shifts', jsonEncode(shifts.map((e)=>e.toJson()).toList()));
    p.setString('patterns', jsonEncode(patterns.map((e)=>e.toJson()).toList()));
    p.setDouble('std', standardWeekly); p.setDouble('cellFS', cellFontSize);
    p.setDouble('trans', transportBonus); p.setDouble('hol', holidayBonus);
  }
  void load() async{
    var p=await SharedPreferences.getInstance();
    String? r=p.getString('roster'); if(r!=null&&r!=''){ var dec=jsonDecode(r); setState(()=>roster=(dec as Map).map((k,v)=>MapEntry(k.toString(),v.toString()))); }
    String? n=p.getString('notes'); if(n!=null&&n!=''){ var dec=jsonDecode(n); setState(()=>notes=(dec as Map).map((k,v)=>MapEntry(k.toString(),v.toString()))); }
    String? ex=p.getString('extra'); if(ex!=null&&ex!=''){ var dec=jsonDecode(ex); setState(()=>extra=(dec as Map).map((k,v)=>MapEntry(k.toString(),(v as num).toDouble()))); }
    String? s=p.getString('shifts'); if(s!=null&&s!=''){ var dec=jsonDecode(s) as List; setState(()=>shifts=dec.map((e)=>Shift.fromJson(e)).toList()); }
    String? pat=p.getString('patterns'); if(pat!=null&&pat!=''){ var dec=jsonDecode(pat) as List; setState(()=>patterns=dec.map((e)=>RosterPattern.fromJson(e)).toList()); }
    var std=p.getDouble('std'); if(std!=null) standardWeekly=std;
    var fs=p.getDouble('cellFS'); if(fs!=null) cellFontSize=fs;
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
    showDialog(context: context, builder: (c){ return AlertDialog(title: Text('Excel分享匯出'), content: SingleChildScrollView(child: SelectableText(sb.toString())), actions: [TextButton(onPressed: ()=>Navigator.pop(c), child: Text('關閉'))]); });
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
          TextField(controller: noteC, decoration: InputDecoration(labelText:'記事 / OT', border: OutlineInputBorder())),
          SizedBox(height:8),
          TextField(controller: exC, decoration: InputDecoration(labelText:'額外工時', border: OutlineInputBorder()), keyboardType: TextInputType.number),
          SizedBox(height:12),
          FilledButton(onPressed: (){ setState((){ if(curCode=='') roster.remove(k(d)); else roster[k(d)]=curCode; if(noteC.text=='') notes.remove(k(d)); else notes[k(d)]=noteC.text; double? vv=double.tryParse(exC.text); if(vv==null||vv==0) extra.remove(k(d)); else extra[k(d)]=vv; save(); }); Navigator.pop(ctx); }, child: Text('保存')),
          SizedBox(height:20),
        ]));
      });
    });
  }

  void autoRosterSimple(){ List<String> pat=[]; for(var s in shifts){ if(s.isWork&&s.code!='OT') pat.add(s.code); } DateTime start=DateTime(focused.year,focused.month,1); DateTime end=DateTime(focused.year,focused.month+1,0); int idx=0; setState((){ for(DateTime d=start;!d.isAfter(end); d=d.add(Duration(days:1))){ String key=k(d); if(!roster.containsKey(key)){ if(d.weekday==7) roster[key]='O'; else if(pat.isNotEmpty){ roster[key]=pat[idx%pat.length]; idx++; } } } save(); }); }
  void createPattern(){
    TextEditingController nameC=TextEditingController(text:'我的22行${patterns.length+1}'); int rows=22;
    showDialog(context: context, builder: (ctx){ return AlertDialog(title: Text('創造特別模式 7x22'), content: TextField(controller: nameC, decoration: InputDecoration(labelText:'模式名稱')), actions: [TextButton(onPressed: ()=>Navigator.pop(ctx), child: Text('取消')), FilledButton(onPressed: (){ Navigator.pop(ctx); openPatternEditor(RosterPattern(nameC.text, List.filled(rows*7, shifts.first.code))); }, child: Text('下一步'))]); });
  }
  void openPatternEditor(RosterPattern pat){
    showDialog(context: context, builder: (ctx){ return StatefulBuilder(builder: (ctx,setM){ return AlertDialog(title: Text('編輯 ${pat.name}'), content: SizedBox(width: double.maxFinite, height:400, child: GridView.builder(gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:7), itemCount: pat.codes.length, itemBuilder: (c,i){ String code=pat.codes[i]; Shift s=getShiftByCode(code); return GestureDetector(onTap: (){ int idx=shifts.indexWhere((e)=>e.code==code); int next=(idx+1)%shifts.length; setM(()=>pat.codes[i]=shifts[next].code); }, child: Container(margin: EdgeInsets.all(2), decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(4)), child: Center(child: Text('${i+1}\n$code', textAlign:TextAlign.center, style: TextStyle(color:Colors.white, fontSize:9))))); })), actions: [TextButton(onPressed: ()=>Navigator.pop(ctx), child: Text('取消')), FilledButton(onPressed: (){ setState(()=>patterns.add(pat)); save(); Navigator.pop(ctx); }, child: Text('保存'))]); }); });
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
    return Scaffold(
      appBar: AppBar(title: GestureDetector(onTap: pickYearMonth, child: Row(children: [Text('W${isoWeek(focused).toString().padLeft(2,'0')} ${DateFormat('yyyy年M月').format(focused)}'), Icon(Icons.arrow_drop_down)])), actions: [
        IconButton(onPressed: autoRosterSimple, icon: Icon(Icons.auto_awesome)),
        IconButton(onPressed: createPattern, icon: Icon(Icons.grid_view)),
        IconButton(onPressed: applyPattern, icon: Icon(Icons.playlist_play)),
        IconButton(onPressed: exportCsv, icon: Icon(Icons.share)),
      ]),
      body: Column(children: [
        Expanded(child: SingleChildScrollView(child: TableCalendar(
          firstDay: DateTime(2024,1,1), lastDay: DateTime(2030,12,31), focusedDay: focused,
          rowHeight: 75, daysOfWeekHeight: 22,
          startingDayOfWeek: StartingDayOfWeek.monday, headerVisible:false,
          selectedDayPredicate: (d)=>isSameDay(selected,d),
          onDaySelected: (s,f){ setState((){selected=s; focused=f;}); onCellTap(s); },
          onPageChanged: (f){ setState(()=>focused=f); },
          calendarBuilders: CalendarBuilders(
            defaultBuilder: (ctx,day,f){
              String key=k(day); String? code=roster[key]; Shift? sh=code!=null?getShiftByCode(code):null; bool isToday=isSameDay(day, DateTime.now()); bool isSel=isSameDay(day, selected); bool isMon=day.weekday==1;
              return GestureDetector(onTap: ()=>onCellTap(day), child: Container(margin: EdgeInsets.all(2), decoration: BoxDecoration(color: sh!=null?sh.color:Colors.grey.shade100, borderRadius: BorderRadius.circular(8), border: isToday?Border.all(color:Colors.amber, width:3): isSel?Border.all(color:Colors.indigo, width:2):null), child: Stack(children: [
                if(isMon) Positioned(top:2, left:2, child: Container(padding: EdgeInsets.symmetric(horizontal:3, vertical:1), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(3)), child: Text('W${isoWeek(day)}', style: TextStyle(color:Colors.white, fontSize:7)))),
                Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(day.day.toString(), style: TextStyle(fontSize: cellFontSize+2, fontWeight: FontWeight.bold, color: sh!=null?Colors.white:Colors.black87)),
                  if(sh!=null) Text(sh.code, style: TextStyle(fontSize: cellFontSize, color:Colors.white)),
                  if(notes.containsKey(key)) Icon(Icons.sticky_note_2, size:10, color:Colors.white),
                  if(extra.containsKey(key)) Text('+${extra[key]}h', style: TextStyle(fontSize:8, color:Colors.white)),
                ])),
              ])));
            },
          ),
        ))),
        Container(color: Colors.indigo.shade50, padding: EdgeInsets.all(8), child: Text('${DateFormat('MM/dd E').format(selected)} ${roster[k(selected)]??'未排'} ${(extra[k(selected)]!=null)?'+${extra[k(selected)]}h':''} ${notes[k(selected)]??''}', style: TextStyle(fontWeight: FontWeight.bold))),
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
      FilledButton.icon(onPressed: applyPattern, icon: Icon(Icons.play_arrow), label: Text('套用模式排更')),
    ]));
  }
}
