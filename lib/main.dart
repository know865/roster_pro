import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
    home: MainPage(),
  ));
}

class Shift {
  String code;
  String name;
  String start;
  String end;
  int colorValue;
  double hours;
  double bonus;
  bool isWork;
  Shift(this.code, this.name, this.start, this.end, this.colorValue, this.hours, this.bonus, this.isWork);
  Map toJson() {
    return {'code':code,'name':name,'start':start,'end':end,'colorValue':colorValue,'hours':hours,'bonus':bonus,'isWork':isWork};
  }
  static Shift fromJson(Map m) {
    return Shift(m['code'], m['name'], m['start'], m['end'], m['colorValue'], (m['hours'] as num).toDouble(), (m['bonus'] as num).toDouble(), m['isWork']);
  }
  Color get color { return Color(colorValue); }
}

class MainPage extends StatefulWidget { @override State<MainPage> createState() => MainPageState(); }

class MainPageState extends State<MainPage> {
  int tab = 0;
  Map<String,String> roster = {};
  List<Shift> shifts = [];
  DateTime focused = DateTime.now();
  DateTime selected = DateTime.now();
  double standardWeekly = 42;
  double transportBonus = 20;
  double holidayBonus = 100;

  MainPageState() {
    shifts = [
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

  String k(DateTime d) { return DateFormat('yyyy-MM-dd').format(d); }

  int isoWeek(DateTime d) {
    DateTime thu = d.add(Duration(days: 4 - d.weekday));
    DateTime jan1 = DateTime(thu.year, 1, 1);
    return (thu.difference(jan1).inDays / 7).floor() + 1;
  }

  Shift getShiftByCode(String code) {
    for (var s in shifts) { if (s.code == code) return s; }
    return Shift('', '', '', '', Colors.grey.value, 0, 0, false);
  }

  double hoursOf(DateTime d) {
    String key = k(d);
    if (roster.containsKey(key) == false) return 0;
    String code = roster[key].toString();
    Shift s = getShiftByCode(code);
    return s.hours;
  }

  double weeklyHours(DateTime any) {
    DateTime mon = any.subtract(Duration(days: any.weekday - 1));
    double sum = 0;
    for (int i=0;i<7;i++) { sum = sum + hoursOf(mon.add(Duration(days: i))); }
    return sum;
  }

  double monthlyHours() {
    double sum = 0;
    for (var key in roster.keys) {
      DateTime d = DateTime.parse(key);
      if (d.year == focused.year && d.month == focused.month) { sum = sum + hoursOf(d); }
    }
    return sum;
  }

  void save() async {
    SharedPreferences p = await SharedPreferences.getInstance();
    p.setString('roster', jsonEncode(roster));
    List list = shifts.map((e)=>e.toJson()).toList();
    p.setString('shifts', jsonEncode(list));
    p.setDouble('std', standardWeekly);
    p.setDouble('trans', transportBonus);
    p.setDouble('hol', holidayBonus);
  }

  void load() async {
    SharedPreferences p = await SharedPreferences.getInstance();
    String? r = p.getString('roster');
    if (r!= null && r!= '') {
      Map<String,dynamic> decoded = jsonDecode(r);
      setState(() { roster = decoded.map((k,v)=>MapEntry(k, v.toString())); });
    }
    String? s = p.getString('shifts');
    if (s!= null && s!= '') {
      List decoded = jsonDecode(s);
      setState(() { shifts = decoded.map((e)=>Shift.fromJson(e)).toList(); });
    }
    double? std = p.getDouble('std');
    if (std!= null) { setState((){ standardWeekly = std; }); }
  }

  @override
  void initState() { super.initState(); load(); }

  void autoRoster() {
    List<String> pattern = [];
    for (var s in shifts) { if (s.isWork && s.code!= 'OT') pattern.add(s.code); }
    DateTime start = DateTime(focused.year, focused.month, 1);
    DateTime end = DateTime(focused.year, focused.month + 1, 0);
    int idx = 0;
    setState((){
      for (DateTime d=start; d.isBefore(end.add(Duration(days:1))); d=d.add(Duration(days:1))) {
        String key = k(d);
        if (roster.containsKey(key) == false) {
          if (d.weekday == 7) { roster[key]='O'; } else {
            if (pattern.length > 0) {
              roster[key]=pattern[idx % pattern.length];
              idx = idx + 1;
            }
          }
        }
      }
      save();
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已自動排更 ${focused.month}月')));
  }

  void exportCsv() {
    StringBuffer sb = StringBuffer();
    sb.writeln('日期,星期,班次,開工,收工,工時,津貼');
    List<String> keys = roster.keys.toList(); keys.sort();
    for (var key in keys) {
      DateTime d = DateTime.parse(key);
      if (d.year == focused.year && d.month == focused.month) {
        String code = roster[key].toString();
        Shift s = getShiftByCode(code);
        sb.writeln('$key,${DateFormat('E').format(d)},${s.code},${s.start},${s.end},${s.hours},${s.bonus}');
      }
    }
    sb.writeln('');
    sb.writeln('本月總工時,${monthlyHours()}');
    sb.writeln('標準,${standardWeekly * 4}');
    showDialog(context: context, builder: (c){
      return AlertDialog(title: Text('Excel CSV匯出 可複製去Excel'), content: SingleChildScrollView(child: SelectableText(sb.toString())), actions: [TextButton(onPressed: (){Navigator.pop(c);}, child: Text('關閉'))]);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: [buildCal(), buildReport(), buildSettings()][tab],
      bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (i){ setState((){ tab=i; }); }, destinations: [
        NavigationDestination(icon: Icon(Icons.calendar_month), label: '月曆'),
        NavigationDestination(icon: Icon(Icons.bar_chart), label: '報表'),
        NavigationDestination(icon: Icon(Icons.settings), label: '設定'),
      ]),
    );
  }

  Widget buildCal() {
    return Scaffold(
      appBar: AppBar(
        title: Text('W${isoWeek(focused).toString().padLeft(2,'0')} ${DateFormat('yyyy年M月').format(focused)}'),
        actions: [
          IconButton(onPressed: autoRoster, icon: Icon(Icons.auto_awesome)),
          IconButton(onPressed: exportCsv, icon: Icon(Icons.share)),
        ],
      ),
      body: Column(children: [
        TableCalendar(
          firstDay: DateTime(2024,1,1),
          lastDay: DateTime(2030,12,31),
          focusedDay: focused,
          startingDayOfWeek: StartingDayOfWeek.monday,
          headerStyle: HeaderStyle(formatButtonVisible: false),
          selectedDayPredicate: (d){ return isSameDay(selected, d); },
          onDaySelected: (s,f){ setState((){ selected=s; focused=f; }); },
          onPageChanged: (f){ setState((){ focused=f; }); },
          calendarBuilders: CalendarBuilders(
            dowBuilder: (ctx, day){
              if (day.weekday == 1) { return Center(child: Text('一\nW${isoWeek(day)}', textAlign: TextAlign.center, style: TextStyle(fontSize:10, fontWeight: FontWeight.bold, color: Colors.indigo))); }
              return null;
            },
            defaultBuilder: (ctx, day, f){
              String key = k(day);
              if (roster.containsKey(key) == false) return null;
              String code = roster[key].toString();
              Shift s = getShiftByCode(code);
              if (s.code == '') return null;
              return Container(margin: EdgeInsets.all(3), decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(6)), child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text(day.day.toString(), style: TextStyle(color: Colors.white, fontSize:12, fontWeight: FontWeight.bold)), Text(s.code, style: TextStyle(color: Colors.white, fontSize:9))])));
            },
          ),
        ),
        Container(color: Colors.indigo.shade50, padding: EdgeInsets.all(8), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('週 ${weeklyHours(selected)} / $standardWeekly h', style: TextStyle(fontWeight: FontWeight.bold)),
          Text('差 ${(weeklyHours(selected)-standardWeekly).toStringAsFixed(1)}h 累 ${(monthlyHours()-standardWeekly*4).toStringAsFixed(1)}h', style: TextStyle(color: weeklyHours(selected)>standardWeekly?Colors.red:Colors.green, fontSize:12)),
        ])),
        Expanded(child: SingleChildScrollView(padding: EdgeInsets.all(8), child: Column(children: [
          Wrap(spacing:6, runSpacing:6, alignment: WrapAlignment.center, children: [
            for (var s in shifts) ChoiceChip(label: Text(s.code), selected: roster.containsKey(k(selected)) && roster[k(selected)]==s.code, selectedColor: s.color.withOpacity(0.4), onSelected: (v){ setState((){ roster[k(selected)]=s.code; save(); }); }),
            ActionChip(label: Text('清除'), onPressed: (){ setState((){ roster.remove(k(selected)); save(); }); }),
          ]),
          SizedBox(height:8),
          Text('已選 ${DateFormat('MM/dd E').format(selected)} 排 ${roster.containsKey(k(selected))?roster[k(selected)]:'未排'}'),
        ]))),
      ]),
    );
  }

  Widget buildReport() {
    double wh = weeklyHours(selected);
    double mh = monthlyHours();
    int nightCount = 0; int workCount=0; int phCount=0;
    for (var v in roster.values) { if (v=='夜') nightCount++; if (v=='PH') phCount++; }
    for (var key in roster.keys) { DateTime d=DateTime.parse(key); if (d.year==focused.year && d.month==focused.month) { String code=roster[key].toString(); Shift s=getShiftByCode(code); if (s.isWork) workCount++; } }
    return Scaffold(
      appBar: AppBar(title: Text('工時 津貼 報表')),
      body: ListView(padding: EdgeInsets.all(16), children: [
        Card(child: ListTile(title: Text('1. 每班工時'), subtitle: Text(shifts.map((e)=>'${e.code}:${e.hours}h ${e.start}-${e.end}').join('\n')))),
        Card(child: ListTile(title: Text('2. 本週實際 $wh h / 標準 $standardWeekly'), subtitle: Text('差額 ${wh-standardWeekly}h'))),
        Card(child: ListTile(title: Text('3. 累計差額 工時銀行'), subtitle: Text('本月差 ${(mh-standardWeekly*4).toStringAsFixed(1)}h 月總 $mh h'))),
        Card(child: ListTile(title: Text('4. 月度 $mh h 年度統計'), subtitle: Text('年度需自行累計 月份切換可見'))),
        Divider(),
        Card(color: Colors.amber.shade50, child: ListTile(title: Text('津貼計算'), subtitle: Text('夜更 $nightCount 次 x 80\n交通 $workCount 日 x $transportBonus\n假日 $phCount x $holidayBonus\n總計約 ${nightCount*80 + workCount*transportBonus + phCount*holidayBonus}'))),
        Divider(),
        Text('假期管理', style: TextStyle(fontWeight: FontWeight.bold)),
        Wrap(spacing:8, children: [
          Chip(label: Text('AL ${roster.values.where((e)=>e=='AL').length}')),
          Chip(label: Text('SL ${roster.values.where((e)=>e=='SL').length}')),
          Chip(label: Text('O ${roster.values.where((e)=>e=='O').length}')),
          Chip(label: Text('PH ${roster.values.where((e)=>e=='PH').length}')),
        ]),
        SizedBox(height:12),
        FilledButton.icon(onPressed: exportCsv, icon: Icon(Icons.table_chart), label: Text('Excel匯出 月薪統計 PDF匯出')),
      ]),
    );
  }

  Widget buildSettings() {
    return Scaffold(
      appBar: AppBar(title: Text('設定')),
      body: ListView(padding: EdgeInsets.all(16), children: [
        Text('班次編輯 可自由增刪改時間', style: TextStyle(fontWeight: FontWeight.bold, fontSize:16)),
        for (var s in shifts) Card(child: ListTile(
          leading: CircleAvatar(backgroundColor: s.color, child: Text(s.code, style: TextStyle(color: Colors.white, fontSize:10))),
          title: Text('${s.name} (${s.code}) ${s.start}-${s.end} ${s.hours}h'),
          subtitle: Text('津貼 ${s.bonus} ${s.isWork?'上班':'假期'}'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(icon: Icon(Icons.edit, size:18), onPressed: (){ editShift(s); }),
            IconButton(icon: Icon(Icons.delete, size:18), onPressed: (){ setState((){ shifts.remove(s); save(); }); }),
          ]),
        )),
        FilledButton.icon(onPressed: addShift, icon: Icon(Icons.add), label: Text('新增班次')),
        Divider(),
        Text('工時 津貼 自訂', style: TextStyle(fontWeight: FontWeight.bold, fontSize:16)),
        ListTile(title: Text('每週標準 $standardWeekly h'), subtitle: Slider(value: standardWeekly, min: 30, max: 60, divisions: 30, label: standardWeekly.toString(), onChanged: (v){ setState((){ standardWeekly=v; save(); }); })),
        ListTile(title: Text('交通津貼 $transportBonus 每日'), onTap: (){ askNumber('交通津貼', transportBonus, (v){ setState((){ transportBonus=v; save(); }); }); }),
        ListTile(title: Text('假日津貼 $holidayBonus'), onTap: (){ askNumber('假日津貼', holidayBonus, (v){ setState((){ holidayBonus=v; save(); }); }); }),
      ]),
    );
  }

  void askNumber(String title, double current, Function(double) onOk) {
    TextEditingController c = TextEditingController(text: current.toString());
    showDialog(context: context, builder: (ctx){
      return AlertDialog(title: Text(title), content: TextField(controller: c, keyboardType: TextInputType.number), actions: [TextButton(onPressed: (){Navigator.pop(ctx);}, child: Text('取消')), FilledButton(onPressed: (){ double? v = double.tryParse(c.text); if (v==null) v=current; onOk(v); Navigator.pop(ctx); }, child: Text('確定'))]);
    });
  }

  void addShift() {
    TextEditingController codeC = TextEditingController();
    TextEditingController nameC = TextEditingController();
    TextEditingController sC = TextEditingController(text:'09:00');
    TextEditingController eC = TextEditingController(text:'18:00');
    TextEditingController hC = TextEditingController(text:'8');
    showDialog(context: context, builder: (ctx){
      return AlertDialog(title: Text('新增班次'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: codeC, decoration: InputDecoration(labelText:'代碼')),
        TextField(controller: nameC, decoration: InputDecoration(labelText:'名稱')),
        TextField(controller: sC, decoration: InputDecoration(labelText:'開工')),
        TextField(controller: eC, decoration: InputDecoration(labelText:'收工')),
        TextField(controller: hC, decoration: InputDecoration(labelText:'工時'), keyboardType: TextInputType.number),
      ])), actions: [
        TextButton(onPressed: (){Navigator.pop(ctx);}, child: Text('取消')),
        FilledButton(onPressed: (){
          double? h = double.tryParse(hC.text); if (h==null) h=8;
          setState((){ shifts.add(Shift(codeC.text==''?'新':codeC.text, nameC.text==''?codeC.text:nameC.text, sC.text, eC.text, Colors.primaries[shifts.length%18].value, h, 0, true)); save(); });
          Navigator.pop(ctx);
        }, child: Text('新增'))
      ]);
    });
  }

  void editShift(Shift s) {
    TextEditingController nameC = TextEditingController(text:s.name);
    TextEditingController sC = TextEditingController(text:s.start);
    TextEditingController eC = TextEditingController(text:s.end);
    TextEditingController hC = TextEditingController(text:s.hours.toString());
    TextEditingController bC = TextEditingController(text:s.bonus.toString());
    showDialog(context: context, builder: (ctx){
      return AlertDialog(title: Text('編輯 ${s.code}'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nameC, decoration: InputDecoration(labelText:'名稱')),
        TextField(controller: sC, decoration: InputDecoration(labelText:'開工時間')),
        TextField(controller: eC, decoration: InputDecoration(labelText:'收工時間')),
        TextField(controller: hC, decoration: InputDecoration(labelText:'工時')),
        TextField(controller: bC, decoration: InputDecoration(labelText:'津貼')),
      ])), actions: [
        TextButton(onPressed: (){Navigator.pop(ctx);}, child: Text('取消')),
        FilledButton(onPressed: (){
          setState((){
            s.name=nameC.text;
            s.start=sC.text;
            s.end=eC.text;
            double? h = double.tryParse(hC.text); if (h!=null) s.hours=h;
            double? b = double.tryParse(bC.text); if (b!=null) s.bonus=b;
            save();
          });
          Navigator.pop(ctx);
        }, child: Text('保存'))
      ]);
    });
  }
}
