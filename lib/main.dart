import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(MaterialApp(debugShowCheckedModeBanner: false, home: MainPage()));
}

class Shift {
  String code; String name; String start; String end; int c; double h; bool work;
  Shift(this.code, this.name, this.start, this.end, this.c, this.h, this.work);
  Map toJson() => {'code': code, 'name': name, 'start': start, 'end': end, 'c': c, 'h': h, 'work': work};
  static Shift fromJson(Map m) => Shift(m['code'], m['name'], m['start'], m['end'], m['c'], (m['h'] as num).toDouble(), m['work']);
  Color get color => Color(c);
}

class Allowance {
  String name; String start; double amount; bool enabled;
  Allowance(this.name, this.start, this.amount, this.enabled);
  Map toJson() => {'name': name, 'start': start, 'amount': amount, 'enabled': enabled};
  static Allowance fromJson(Map m) => Allowance(m['name'], m['start'], (m['amount'] as num).toDouble(), m['enabled']);
  int get mins {
    try {
      var p = start.split(':');
      return int.parse(p[0]) * 60 + int.parse(p[1]);
    } catch (_) { return 0; }
  }
}

class MainPage extends StatefulWidget {
  @override State<MainPage> createState() => _MainState();
}

class _MainState extends State<MainPage> {
  int tab = 0;
  Map<String, String> roster = {};
  List<Shift> shifts = [];
  List<Allowance> allowances = [];
  DateTime focused = DateTime.now();
  DateTime selected = DateTime.now();
  double transB = 20;

  _MainState() {
    shifts = [
      Shift('早', '早更', '07:00', '15:30', 0xFFFF9800, 8, true),
      Shift('中', '中更', '15:00', '23:30', 0xFF2196F3, 8, true),
      Shift('夜', '夜更', '23:00', '07:30', 0xFF3F51B5, 8, true),
      Shift('宵', '通宵', '23:30', '08:00', 0xFF673AB7, 8, true),
      Shift('O', '例休', '', '', 0xFF4CAF50, 0, false),
      Shift('OT', 'OT', '', '', 0xFF795548, 4, true),
    ];
    allowances = [
      Allowance('早班津貼', '06:00', 20, true),
      Allowance('中班津貼', '14:00', 0, true),
      Allowance('夜班津貼', '22:00', 80, true),
      Allowance('通宵津貼', '23:30', 120, true),
    ];
  }

  String k(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  int isoWeek(DateTime d) {
    var thu = d.add(Duration(days: 4 - d.weekday));
    var jan1 = DateTime(thu.year, 1, 1);
    return (thu.difference(jan1).inDays / 7).floor() + 1;
  }

  Shift getS(String c) {
    for (var s in shifts) { if (s.code == c) return s; }
    return Shift('', '', '', '', 0xFF9E9E9E, 0, false);
  }

  int parseMins(String t) {
    try { var p = t.split(':'); return int.parse(p[0]) * 60 + int.parse(p[1]); } catch (_) { return -1; }
  }

  double allowanceForShift(Shift s) {
    if (!s.work || s.start == '') return 0;
    int sm = parseMins(s.start);
    if (sm < 0) return 0;
    Allowance? best;
    int bestDiff = 10000;
    for (var a in allowances) {
      if (!a.enabled) continue;
      int diff = sm - a.mins;
      if (diff < 0) diff += 1440;
      if (diff < bestDiff && diff < 720) { bestDiff = diff; best = a; }
    }
    return best!= null? best.amount : 0;
  }

  void save() async {
    var p = await SharedPreferences.getInstance();
    p.setString('roster', jsonEncode(roster));
    p.setString('shifts', jsonEncode(shifts.map((e) => e.toJson()).toList()));
    p.setString('allowances', jsonEncode(allowances.map((e) => e.toJson()).toList()));
  }

  void load() async {
    var p = await SharedPreferences.getInstance();
    var r = p.getString('roster');
    if (r!= null) { var d = jsonDecode(r); roster = (d as Map).map((k, v) => MapEntry(k.toString(), v.toString())); }
    var sh = p.getString('shifts');
    if (sh!= null) { var d = jsonDecode(sh) as List; shifts = d.map((e) => Shift.fromJson(e)).toList(); }
    var al = p.getString('allowances');
    if (al!= null) { var d = jsonDecode(al) as List; allowances = d.map((e) => Allowance.fromJson(e)).toList(); }
    setState(() {});
  }

  @override void initState() { super.initState(); load(); }

  List<DateTime> daysInMonth(DateTime mon) {
    var first = DateTime(mon.year, mon.month, 1);
    int off = first.weekday - 1;
    var start = first.subtract(Duration(days: off));
    return List.generate(42, (i) => start.add(Duration(days: i)));
  }

  @override Widget build(BuildContext context) {
    return Scaffold(
      body: tab == 0? buildCal() : buildSetting(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: tab,
        onTap: (i) => setState(() => tab = i),
        items: [BottomNavigationBarItem(icon: Icon(Icons.calendar_today), label: '月曆'), BottomNavigationBarItem(icon: Icon(Icons.settings), label: '設定')],
      ),
    );
  }

  Widget buildCal() {
    var days = daysInMonth(focused);
    return Column(children: [
      ColoredBox(
        color: Colors.indigo,
        child: SafeArea(child: SizedBox(height: 48, child: Row(children: [
          IconButton(icon: Icon(Icons.today, color: Colors.white), onPressed: () { setState(() { focused = DateTime.now(); selected = DateTime.now(); }); }),
          Text('${focused.year}年${focused.month}月', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
          Spacer(),
          IconButton(icon: Icon(Icons.chevron_left, color: Colors.white), onPressed: () { setState(() => focused = DateTime(focused.year, focused.month - 1, 1)); }),
          IconButton(icon: Icon(Icons.chevron_right, color: Colors.white), onPressed: () { setState(() => focused = DateTime(focused.year, focused.month + 1, 1)); }),
        ]))),
      ),
      ColoredBox(color: Color(0xFFEEEEEE), child: Row(children: [ for(var w in ['Mon','Tue','Wed','Thu','Fri','Sat','Sun']) Expanded(child: Center(child: Text(w, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)))) ])),
      Expanded(child: GridView.builder(padding: EdgeInsets.zero, physics: NeverScrollableScrollPhysics(), gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, childAspectRatio: 0.85, crossAxisSpacing: 1, mainAxisSpacing: 1), itemCount: 42, itemBuilder: (c, i) {
        DateTime day = days[i];
        bool out = day.month!= focused.month;
        String key = k(day);
        String? code = roster[key];
        Shift? sh = code!= null? getS(code) : null;
        bool isSel = k(day) == k(selected);
        bool isToday = k(day) == k(DateTime.now());
        bool isMon = day.weekday == 1;
        if (out) { return ColoredBox(color: Colors.white, child: Center(child: Text(day.day.toString(), style: TextStyle(color: Colors.grey)))); }
        Color bg = sh!= null? sh.color : Color(0xFFE0E0E0);
        if (isSel) bg = Color(0xFF1A237E);
        if (isToday) bg = Color(0xFFFFC107);
        double dayA = sh!= null? allowanceForShift(sh) + (sh.work? transB : 0) : 0;
        return GestureDetector(
          onTap: () { setState(() => selected = day); },
          onLongPress: () {
            String cur = roster[key]?? '';
            showModalBottomSheet(context: context, builder: (ctx) {
              return Container(color: Colors.white, padding: EdgeInsets.all(16), child: Wrap(spacing: 8, children: [
                for (var s in shifts) ChoiceChip(label: Text(s.code), selected: cur == s.code, onSelected: (v) { setState(() => roster[key] = s.code); save(); Navigator.pop(ctx); })
              ]));
            });
          },
          child: ColoredBox(
            color: bg,
            child: Column(children: [
              if (isMon) Align(alignment: Alignment.topLeft, child: ColoredBox(color: Colors.black54, child: Text('W${isoWeek(day)}', style: TextStyle(color: Colors.white, fontSize: 7)))),
              Expanded(child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(day.day.toString(), style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: sh!= null? Colors.white : Colors.black)),
                if (sh!= null) Text(sh.code, style: TextStyle(fontSize: 10, color: Colors.white)),
                if (sh!= null && dayA > 0) Text('\$${dayA.toStringAsFixed(0)}', style: TextStyle(fontSize: 7, color: Colors.white)),
              ]))),
            ]),
          ),
        );
      })),
    ]);
  }

  Widget buildSetting() {
    var showShifts = shifts.length > 5? shifts.sublist(0, 5) : shifts;
    var showAllow = allowances.length > 5? allowances.sublist(0, 5) : allowances;
    return ListView(padding: EdgeInsets.all(8), children: [
      Text('自定班次 (只顯示5行)', style: TextStyle(fontWeight: FontWeight.bold)),
      ColoredBox(color: Colors.white, child: Column(children: [
        for (var s in showShifts) ListTile(dense: true, leading: ColoredBox(color: s.color, child: SizedBox(width: 28, height: 28, child: Center(child: Text(s.code, style: TextStyle(color: Colors.white, fontSize: 10))))), title: Text('${s.code} ${s.name} ${s.start}-${s.end}', style: TextStyle(fontSize: 12)), subtitle: Text('自動津貼 \$${allowanceForShift(s).toStringAsFixed(0)}', style: TextStyle(fontSize: 10))),
        if (shifts.length > 5) TextButton(onPressed: () {
          showDialog(context: context, builder: (ctx) => AlertDialog(title: Text('全部班次 ${shifts.length}個'), content: SizedBox(width: 300, height: 400, child: ListView(children: [ for (var s in shifts) ListTile(title: Text('${s.code} ${s.name} ${s.start}')) ])), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text('關閉'))]));
        }, child: Text('還有 ${shifts.length - 5}個 查看全部')),
      ])),
      ElevatedButton(onPressed: () {
        TextEditingController codeC = TextEditingController(); TextEditingController nameC = TextEditingController(); TextEditingController startC = TextEditingController(text: '07:00'); TextEditingController endC = TextEditingController(text: '15:00');
        showDialog(context: context, builder: (ctx) => AlertDialog(title: Text('新增班次'), content: Column(mainAxisSize: MainAxisSize.min, children: [ TextField(controller: codeC, decoration: InputDecoration(labelText: '代號')), TextField(controller: nameC, decoration: InputDecoration(labelText: '名稱')), TextField(controller: startC, decoration: InputDecoration(labelText: '開始 HH:MM')), TextField(controller: endC, decoration: InputDecoration(labelText: '結束')) ]), actions: [TextButton(onPressed: () { if (codeC.text!= '') { setState(() => shifts.add(Shift(codeC.text, nameC.text, startC.text, endC.text, 0xFFFF9800, 8, true))); save(); } Navigator.pop(ctx); }, child: Text('新增'))]));
      }, child: Text('新增班次')),
      Divider(),
      Text('津貼設定 (可自定開始時間)', style: TextStyle(fontWeight: FontWeight.bold)),
      ColoredBox(color: Colors.white, child: Column(children: [
        for (var a in showAllow) ListTile(dense: true, title: Text('${a.name} 開始${a.start} \$${a.amount}', style: TextStyle(fontSize: 12))),
        if (allowances.length > 5) TextButton(onPressed: () {
          showDialog(context: context, builder: (ctx) => AlertDialog(title: Text('全部津貼'), content: SizedBox(width: 300, height: 400, child: ListView(children: [ for (var a in allowances) ListTile(title: Text('${a.name} ${a.start} \$${a.amount}')) ])), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text('關閉'))]));
        }, child: Text('還有 ${allowances.length - 5}個')),
      ])),
      Row(children: [
        Expanded(child: ElevatedButton(onPressed: () {
          TextEditingController nameC = TextEditingController(); TextEditingController startC = TextEditingController(text: '06:00'); TextEditingController amountC = TextEditingController(text: '20');
          showDialog(context: context, builder: (ctx) => AlertDialog(title: Text('新增津貼'), content: Column(mainAxisSize: MainAxisSize.min, children: [ TextField(controller: nameC, decoration: InputDecoration(labelText: '名稱')), TextField(controller: startC, decoration: InputDecoration(labelText: '開始 HH:MM')), TextField(controller: amountC, decoration: InputDecoration(labelText: '金額'), keyboardType: TextInputType.number) ]), actions: [TextButton(onPressed: () { if (nameC.text!= '') { setState(() => allowances.add(Allowance(nameC.text, startC.text, double.tryParse(amountC.text)?? 0, true))); save(); } Navigator.pop(ctx); }, child: Text('新增'))]));
        }, child: Text('新增津貼'))),
        SizedBox(width: 8),
        Expanded(child: OutlinedButton(onPressed: () { setState(() { allowances = [Allowance('早班津貼','06:00',20,true), Allowance('中班津貼','14:00',0,true), Allowance('夜班津貼','22:00',80,true), Allowance('通宵津貼','23:30',120,true)]; }); save(); }, child: Text('重置'))),
      ]),
      SizedBox(height: 40),
    ]);
  }
}
