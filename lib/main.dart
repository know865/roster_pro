import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';

void main() => runApp(const RosterApp());

class RosterApp extends StatelessWidget {
  const RosterApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: const RosterPage(),
    );
  }
}

class RosterPage extends StatefulWidget {
  const RosterPage({super.key});
  @override
  State<RosterPage> createState() => _RosterPageState();
}

class _RosterPageState extends State<RosterPage> {
  final Map<String, String> _roster = {};
  DateTime _focused = DateTime.now();
  DateTime? _selected;
  CalendarFormat _format = CalendarFormat.month;

  String _key(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  int isoWeek(DateTime d) {
    final thursday = d.add(Duration(days: 4 - d.weekday));
    final firstJan = DateTime(thursday.year, 1, 1);
    return ((thursday.difference(firstJan).inDays) / 7).floor() + 1;
  }

  int get weeklyHours {
    if (_selected == null) return 0;
    final monday = _selected!.subtract(Duration(days: _selected!.weekday - 1));
    int count = 0;
    for (int i = 0; i < 7; i++) {
      final k = _key(monday.add(Duration(days: i)));
      final v = _roster[k];
      if (v == '早' || v == '中' || v == '夜') count += 8;
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    _selected??= DateTime.now();
    return Scaffold(
      appBar: AppBar(
        title: Text('排更王 W${isoWeek(_focused).toString().padLeft(2, '0')}'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          TableCalendar(
            firstDay: DateTime(2024, 1, 1),
            lastDay: DateTime(2030, 12, 31),
            focusedDay: _focused,
            calendarFormat: _format,
            startingDayOfWeek: StartingDayOfWeek.monday,
            selectedDayPredicate: (d) => isSameDay(_selected, d),
            onDaySelected: (s, f) => setState(() { _selected = s; _focused = f; }),
            onPageChanged: (f) => setState(() => _focused = f),
            calendarBuilders: CalendarBuilders(
              defaultBuilder: (ctx, day, focused) {
                final v = _roster[_key(day)];
                if (v == null) return null;
                Color c = Colors.grey;
                if (v == '早') c = Colors.orange;
                if (v == '中') c = Colors.blue;
                if (v == '夜') c = Colors.indigo;
                if (v == '休' || v == 'O') c = Colors.green;
                return Container(
                  margin: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(8)),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('${day.day}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      Text(v, style: const TextStyle(color: Colors.white, fontSize: 10)),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('本週: ${weeklyHours}h / 42h', style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(weeklyHours > 42? '+${weeklyHours - 42}h 超時' : '${42 - weeklyHours}h 不足',
                    style: TextStyle(color: weeklyHours > 42? Colors.red : Colors.grey)),
              ],
            ),
          ),
          const Divider(),
          Wrap(
            spacing: 8,
            children: [
              _btn('早更', '早', Colors.orange),
              _btn('中更', '中', Colors.blue),
              _btn('夜更', '夜', Colors.indigo),
              _btn('例休', 'O', Colors.green),
              _btn('年假', 'AL', Colors.purple),
              _btn('清除', '', Colors.grey),
            ],
          ),
          const SizedBox(height: 12),
          Text('已選: ${DateFormat('M月d日 E', 'zh').format(_selected!)} -> ${_roster[_key(_selected!)]?? '未排'}'),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => setState(() => _format = _format == CalendarFormat.month? CalendarFormat.week : CalendarFormat.month),
        label: Text(_format == CalendarFormat.month? '切換周視圖' : '切換月視圖'),
        icon: const Icon(Icons.calendar_view_month),
      ),
    );
  }

  Widget _btn(String label, String value, Color color) {
    return ChoiceChip(
      label: Text(label),
      selected: _selected!= null && _roster[_key(_selected!)] == value,
      selectedColor: color.withOpacity(0.3),
      onSelected: (_) {
        if (_selected == null) return;
        setState(() {
          if (value == '') {
            _roster.remove(_key(_selected!));
          } else {
            _roster[_key(_selected!)] = value;
          }
        });
      },
    );
  }
}
