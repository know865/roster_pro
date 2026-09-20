import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

void main() => runApp(MaterialApp(home: MainPage(), debugShowCheckedModeBanner: false));

class MainPage extends StatefulWidget { @override State<MainPage> createState() => _MainPageState(); }

class _MainPageState extends State<MainPage> {
  Map roster = {};
  DateTime focused = DateTime.now();
  DateTime selected = DateTime.now();
  List<String> codes = ['早','中','夜','O','AL','SL','PH'];

  String k(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  
  int isoWeek(DateTime d) {
    var thu = d.add(Duration(days: 4 - d.weekday));
    var jan1 = DateTime(thu.year, 1, 1);
    return (thu.difference(jan1).inDays / 7).floor() + 1;
  }

  void save() async {
    var p = await SharedPreferences.getInstance();
    p.setString('roster', jsonEncode(roster));
  }

  void load() async {
    var p = await SharedPreferences.getInstance();
    var r = p.getString('roster');
    if (r != null) {
      setState(() { roster = jsonDecode(r); });
    }
  }

  @override
  void initState() { super.initState(); load(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('W${isoWeek(focused)} ${DateFormat('yyyy年M月').format(focused)}')),
      body: Column(children: [
        TableCalendar(
          firstDay: DateTime(2024,1,1),
          lastDay: DateTime(2030,12,31),
          focusedDay: focused,
          startingDayOfWeek: StartingDayOfWeek.monday,
          headerStyle: HeaderStyle(formatButtonVisible: false),
          selectedDayPredicate: (d) => isSameDay(selected, d),
          onDaySelected: (s,f) { setState(() { selected=s; focused=f; }); },
          onPageChanged: (f) { setState(() { focused=f; }); },
          calendarBuilders: CalendarBuilders(
            defaultBuilder: (ctx, day, f) {
              var code = roster[k(day)];
              if (code == null) return null;
              return Container(margin: EdgeInsets.all(4), color: Colors.indigo, child: Center(child: Text('${day.day}\n$code', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 10))));
            },
          ),
        ),
        Expanded(child: Wrap(spacing: 8, children: codes.map((c) => ChoiceChip(label: Text(c), selected: roster[k(selected)]==c, onSelected: (v){ setState(() { roster[k(selected)]=c; save(); }); })).toList())),
      ]),
    );
  }
}
