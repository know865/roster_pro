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
    final thu = d.add(Duration(days: 4 - d.weekday));
    final jan1 = DateTime(thu.year, 1, 1);
    return ((thu.difference(jan1).inDays) / 7).floor() + 1;
  }

  int get weeklyHours {
    if (_selected == null) return 0;
    final mon = _selected!.subtract(Duration(days: _selected!.weekday - 1));
    int count = 0;
    for (int i = 0; i < 7; i++) {
      final v = _roster[_key(mon.add(Duration(days: i)))];
      if (v == '早' || v == '中' || v == '夜') count += 8;
    }
    return count;
  }

  @override
  void initState() {
    super.initState();
    _selected = DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('排更王 W${isoWeek(_focused).toString().padLeft(2,'0')} - ${DateFormat('yyyy年M月').format(_focused)}'),
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
            headerStyle: const HeaderStyle(formatButtonVisible: false),
            calendarStyle: const CalendarStyle(outsideDaysVisible: false),
            calendarBuilders: CalendarBuilders(
              defaultBuilder: (ctx, day, focused) {
                final v = _roster[_key(day)];
                if (v == null) return null;
                Color c = Colors.grey;
                if (v == '早') c = Colors.orange;
                if (v == '中') c = Colors.blue;
                if (v == '夜') c = Colors.indigo;
                if (v == 'O' || v == '休') c = Colors.green;
                return Container(
                  margin: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(8)),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('${day.day}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      Text(v, style: const TextStyle(color: Colors.white, fontSize: 10)),
                    ],
                  ),
                );
              },
              selectedBuilder: (ctx, day, focused) {
                final v = _roster[_key(day)];
                Color c = Colors.black87;
                if (v != null) {
                  if (v == '早') c = Colors.orange;
                  if (v == '中') c = Colors.blue;
                  if (v == '夜') c = Colors.indigo;
                  if (v == 'O') c = Colors.green;
                }
                return Container(
                  margin: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.yellow, width: 2)),
                  alignment: Alignment.center,
                  child: Text('${day.day}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Container(
            color: Colors.blue.shade50,
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('本週: $weeklyHours h / 44h', style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(weeklyHours > 44 ? '超時 ${weeklyHours-44}h' : '差 ${44-weeklyHours}h',
                    style: TextStyle(color: weeklyHours > 44 ? Colors.red : Colors.black54)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8, runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _btn('早更', '早', Colors.orange),
              _btn('中更', '中', Colors.blue),
              _btn('夜更', '夜', Colors.indigo),
              _btn('O 休', 'O', Colors.green),
              _btn('AL', 'AL', Colors.purple),
              _btn('清除', '', Colors.grey),
            ],
          ),
          const SizedBox(height: 14),
          Text('已選: ${DateFormat('MM-dd').format(_selected!)} -> ${_roster[_key(_selected!)] ?? '未排'}',
              style: const TextStyle(fontSize: 16)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => setState(() => _format = _format == CalendarFormat.month ? CalendarFormat.week : CalendarFormat.month),
        label: Text(_format == CalendarFormat.month ? '周視圖' : '月視圖'),
        icon: const Icon(Icons.calendar_view_week),
      ),
    );
  }

  Widget _btn(String label, String value, Color color) {
    final isSel = _roster[_key(_selected!)] == value && value != '';
    return FilterChip(
      label: Text(label),
      selected: isSel,
      backgroundColor: color.withOpacity(0.15),
      selectedColor: color.withOpacity(0.4),
      onSelected: (_) {
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
