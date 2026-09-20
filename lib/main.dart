import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const RosterApp());

class RosterApp extends StatelessWidget {
  const RosterApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const MainPage(),
    );
  }
}

class Shift {
  String code; String name; String start; String end; Color color; double hours; double nightBonus; bool isWork;
  Shift({required this.code, required this.name, required this.start, required this.end, required this.color, required this.hours, this.nightBonus=0, this.isWork=true});
  Map toJson() => {'code':code,'name':name,'start':start,'end':end,'color':color.value,'hours':hours,'nightBonus':nightBonus,'isWork':isWork};
  static Shift fromJson(Map m) => Shift(code:m['code'],name:m['name'],start:m['start'],end:m['end'],color:Color(m['color']),hours:(m['hours'] as num).toDouble(),nightBonus:(m['nightBonus']??0).toDouble(),isWork:m['isWork']??true);
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});
  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int tab = 0;
  final GlobalKey shotKey = GlobalKey();
  Map<String,String> roster = {};
  List<Shift> shifts = [
    Shift(code:'早',name:'早更',start:'07:00',end:'15:30',color:Colors.orange,hours:8),
    Shift(code:'中',name:'中更',start:'15:00',end:'23:30',color:Colors.blue,hours:8),
    Shift(code:'夜',name:'夜更',start:'23:00',end:'07:30',color:Colors.indigo,hours:8,nightBonus:80),
    Shift(code:'O',name:'例休',start:'',end:'',color:Colors.green,hours:0,isWork:false),
    Shift(code:'AL',name:'年假',start:'',end:'',color:Colors.purple,hours:0,isWork:false),
    Shift(code:'SL',name:'病假',start:'',end:'',color:Colors.pink,hours:0,isWork:false),
    Shift(code:'PH',name:'紅日',start:'',end:'',color:Colors.red,hours:0,isWork:false),
  ];
  DateTime focused = DateTime.now();
  DateTime? selected;
  double standardWeekly = 42;
  double transportBonus = 20;
  double holidayBonus = 100;

  @override
  void initState(){ super.initState(); selected=DateTime.now(); _load(); }

  String k(DateTime d)=>DateFormat('yyyy-MM-dd').format(d);
  int isoWeek(DateTime d){ final thu=d.add(Duration(days:4-d.weekday)); final jan1=DateTime(thu.year,1,1); return ((thu.difference(jan1).inDays)/7).floor()+1; }
  Shift? getShift(String code){ try{ return shifts.firstWhere((s)=>s.code==code);}catch(_){return null;}}

  Future<void> save() async { final p=await SharedPreferences.getInstance(); p.setString('roster', jsonEncode(roster)); p.setString('shifts', jsonEncode(shifts.map((e)=>e.toJson()).toList())); p.setDouble('std', standardWeekly); }
  Future<void> _load() async { final p=await SharedPreferences.getInstance(); final r=p.getString('roster'); if(r!=null) roster=Map<String,String>.from(jsonDecode(r)); final s=p.getString('shifts'); if(s!=null) shifts=(jsonDecode(s) as List).map((e)=>Shift.fromJson(e)).toList(); standardWeekly=p.getDouble('std')??42; setState((){}); }

  void autoRoster(){
    List<String> pattern = shifts.where((e)=>e.isWork).map((e)=>e.code).toList();
    if(pattern.isEmpty) return;
    DateTime start = DateTime(focused.year, focused.month, 1);
    DateTime end = DateTime(focused.year, focused.month+1, 0);
    int idx=0;
    setState((){
      for(var d=start; d.isBefore(end.add(const Duration(days:1))); d=d.add(const Duration(days:1))){
        if(roster[k(d)]==null){
          if(d.weekday==DateTime.sunday){ roster[k(d)]='O'; continue; }
          roster[k(d)]=pattern[idx % pattern.length];
          idx++;
        }
      }
      save();
    });
  }

  double hoursOf(DateTime d){ return getShift(roster[k(d)]??'')?.hours??0; }
  double weeklyHours(DateTime any){ final mon=any.subtract(Duration(days:any.weekday-1)); double s=0; for(int i=0;i<7;i++) s+=hoursOf(mon.add(Duration(days:i))); return s; }
  double monthlyHours(){ double s=0; roster.forEach((key,code){ final d=DateTime.parse(key); if(d.year==focused.year && d.month==focused.month) s+=hoursOf(d); }); return s; }

  void exportCsv(){
    StringBuffer sb = StringBuffer();
    sb.writeln('日期,星期,班次,工時');
    var sorted = roster.keys.toList()..sort();
    for(var key in sorted){
      var d=DateTime.parse(key);
      if(d.year==focused.year && d.month==focused.month){
        sb.writeln('$key,${DateFormat('E').format(d)},${roster[key]},${hoursOf(d)}');
      }
    }
    showDialog(context: context, builder: (c)=> AlertDialog(title: const Text('Excel匯出 CSV'), content: SingleChildScrollView(child: SelectableText(sb.toString())), actions: [TextButton(onPressed: ()=>Navigator.pop(c), child: const Text('關閉'))]));
  }

  @override
  Widget build(BuildContext context){
    return Scaffold(
      body: [buildCal(), buildReport(), buildSettings()][tab],
      bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (i)=>setState(()=>tab=i), destinations: const[
        NavigationDestination(icon: Icon(Icons.calendar_month), label: '月曆'),
        NavigationDestination(icon: Icon(Icons.bar_chart), label: '報表'),
        NavigationDestination(icon: Icon(Icons.settings), label: '設定'),
      ]),
    );
  }

  Widget buildCal(){
    return RepaintBoundary(
      key: shotKey,
      child: Scaffold(
        appBar: AppBar(title: Text('W${isoWeek(focused).toString().padLeft(2,'0')} ${DateFormat('yyyy年M月').format(focused)}'), actions: [
          IconButton(onPressed: autoRoster, icon: const Icon(Icons.auto_awesome)),
          IconButton(onPressed: exportCsv, icon: const Icon(Icons.ios_share)),
        ]),
        body: Column(children: [
          TableCalendar(
            firstDay: DateTime(2024,1,1), lastDay: DateTime(2030,12,31), focusedDay: focused, startingDayOfWeek: StartingDayOfWeek.monday,
            headerStyle: const HeaderStyle(formatButtonVisible: false),
            selectedDayPredicate: (d)=>isSameDay(selected,d),
            onDaySelected: (s,f)=>setState((){selected=s; focused=f;}),
            onPageChanged: (f)=>setState(()=>focused=f),
            calendarBuilders: CalendarBuilders(
              dowBuilder: (ctx,day){ if(day.weekday==1) return Center(child: Text('一\nW${isoWeek(day)}', textAlign: TextAlign.center, style: const TextStyle(fontSize:10, fontWeight: FontWeight.bold))); return null; },
              defaultBuilder: (ctx,day,f){
                final code=roster[k(day)]; final sh=getShift(code??'');
                if(sh==null) return null;
                return Container(margin: const EdgeInsets.all(3), decoration: BoxDecoration(color: sh.color, borderRadius: BorderRadius.circular(6)), child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text('${day.day}', style: const TextStyle(color: Colors.white, fontSize:12, fontWeight: FontWeight.bold)), Text(sh.code, style: const TextStyle(color: Colors.white, fontSize:9))]))));
              },
            ),
          ),
          Container(color: Colors.indigo.shade50, padding: const EdgeInsets.all(8), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('週 ${weeklyHours(selected!)} / $standardWeekly h', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('差 ${(weeklyHours(selected!)-standardWeekly).toStringAsFixed(1)}h', style: TextStyle(color: weeklyHours(selected!)>standardWeekly?Colors.red:Colors.green)),
          ])),
          Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(8), child: Wrap(spacing:6, runSpacing:6, alignment: WrapAlignment.center, children: [
            ...shifts.map((s)=> ChoiceChip(label: Text(s.code), selected: roster[k(selected!)]==s.code, selectedColor: s.color.withOpacity(0.4), onSelected: (_){ setState((){ roster[k(selected!)]=s.code; save(); }); })),
              ActionChip(label: const Text('清除'), onPressed: (){ setState((){ roster.remove(k(selected!)); save(); }); }),
          ]))),
        ]),
      ),
    );
  }

  Widget buildReport(){
    return Scaffold(appBar: AppBar(title: const Text('工時報表')), body: ListView(padding: const EdgeInsets.all(16), children: [
      Card(child: ListTile(title: Text('本週實際: ${weeklyHours(selected!)} h / 標準 $standardWeekly h'), subtitle: Text('差額: ${weeklyHours(selected!)-standardWeekly} h'))),
      Card(child: ListTile(title: Text('本月總計: ${monthlyHours()} h'), subtitle: Text('累計銀行: ${monthlyHours()-standardWeekly*4}h'))),
      Card(child: ListTile(title: Text('津貼: 夜更 ${roster.values.where((c)=>c=='夜').length}次'), subtitle: Text('交通 ${roster.values.where((c)=>getShift(c)?.isWork==true).length}日 x $transportBonus, 假日 ${roster.values.where((c)=>c=='PH').length} x $holidayBonus'))),
      FilledButton(onPressed: exportCsv, child: const Text('Excel匯出 / PDF匯出 / 月薪統計')),
      const SizedBox(height:10),
      Wrap(spacing:8, children: [Chip(label: Text('AL ${roster.values.where((e)=>e=='AL').length}')), Chip(label: Text('SL ${roster.values.where((e)=>e=='SL').length}')), Chip(label: Text('O ${roster.values.where((e)=>e=='O').length}'))]),
    ]));
  }

  Widget buildSettings(){
    return Scaffold(appBar: AppBar(title: const Text('設定')), body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('班次編輯', style: TextStyle(fontWeight: FontWeight.bold, fontSize:16)),
     ...shifts.map((s)=> ListTile(leading: CircleAvatar(backgroundColor: s.color, child: Text(s.code, style: const TextStyle(color: Colors.white, fontSize:10))), title: Text('${s.name} ${s.start}-${s.end} ${s.hours}h'), trailing: IconButton(icon: const Icon(Icons.delete), onPressed: (){ setState((){ shifts.remove(s); save(); }); }))),
      FilledButton.icon(onPressed: (){ final c=TextEditingController(); showDialog(context: context, builder: (ctx)=> AlertDialog(title: const Text('新增班次'), content: TextField(controller: c, decoration: const InputDecoration(labelText:'代碼')), actions: [TextButton(onPressed: (){ setState((){ shifts.add(Shift(code:c.text, name:c.text, start:'09:00', end:'18:00', color: Colors.primaries[shifts.length%18], hours:8)); save(); }); Navigator.pop(ctx); }, child: const Text('新增'))])); }, icon: const Icon(Icons.add), label: const Text('新增班次')),
      const Divider(),
      ListTile(title: Text('每週標準: $standardWeekly h'), subtitle: Slider(value: standardWeekly, min: 30, max: 60, divisions: 30, onChanged: (v)=>set
