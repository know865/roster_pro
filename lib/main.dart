import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/calendar/v3.dart' as cal;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:device_calendar/device_calendar.dart';

void main() { runApp(const RosterProApp()); }

class ShiftDef {
  String code; String label; double hours; double allowance; double ot; Color color;
  ShiftDef(this.code, this.label, this.hours, this.color, {this.allowance = 0, this.ot = 0});
  Map<String, dynamic> toJson() => {'code':code,'label':label,'hours':hours,'allowance':allowance,'ot':ot,'color':color.value};
  factory ShiftDef.fromJson(Map<String, dynamic> j) => ShiftDef(j['code'], j['label']?? j['code'], (j['hours']?? 8).toDouble(), Color(j['color']?? 0xFFFF9800), allowance: (j['allowance']?? 0).toDouble(), ot: (j['otHours']?? j['ot']?? 0).toDouble());
}

class RosterProApp extends StatelessWidget {
  const RosterProApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(title: 'Roster Pro', theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.deepPurple), home: const MainPage());
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});
  @override
  State<MainPage> createState() => MainPageState();
}

class MainPageState extends State<MainPage> {
  int tabIndex = 0;
  DateTime focused = DateTime(2026, 9, 1);
  Map<String, String> roster = {};
  Map<String, ShiftDef> defs = {
    '早': ShiftDef('早', '早班', 8, Colors.orange),
    '中': ShiftDef('中', '中班', 8, Colors.blue),
    '宵': ShiftDef('宵', '宵班', 8, Colors.purple, allowance: 60),
    'OT': ShiftDef('OT', 'OT', 0, Colors.brown, ot: 2),
    'O': ShiftDef('O', '休', 0, Colors.green),
  };
  String customCalName = '我的排更';
  String? rosterCalId;
  double carry = 0;
  bool gSync = true;
  final GoogleSignIn googleSignIn = GoogleSignIn(scopes: [drive.DriveApi.driveFileScope, cal.CalendarApi.calendarScope]);
  final DeviceCalendarPlugin deviceCal = DeviceCalendarPlugin();
  final Map<String, String> holidays = {'09-22': '秋分', '09-25': '中秋翌日'};

  @override
  void initState() { super.initState(); loadData(); }

  Future<void> loadData() async {
    var sp = await SharedPreferences.getInstance();
    var r = sp.getString('roster');
    if (r!= null) { roster = Map<String, String>.from(jsonDecode(r)); }
    var d = sp.getString('defs');
    if (d!= null) { var m = Map<String, dynamic>.from(jsonDecode(d)); defs = m.map((k, v) => MapEntry(k, ShiftDef.fromJson(v))); }
    setState(() {
      customCalName = sp.getString('customCalName')?? '我的排更';
      rosterCalId = sp.getString('rosterCalId');
      carry = sp.getDouble('carry')?? 0;
      gSync = sp.getBool('gSync')?? true;
    });
  }

  Future<void> saveData() async {
    var sp = await SharedPreferences.getInstance();
    sp.setString('roster', jsonEncode(roster));
    sp.setString('defs', jsonEncode(defs.map((k, v) => MapEntry(k, v.toJson()))));
    sp.setString('customCalName', customCalName);
    if (rosterCalId!= null) sp.setString('rosterCalId', rosterCalId!);
    sp.setDouble('carry', carry);
    sp.setBool('gSync', gSync);
  }

  Map<String, dynamic> getReport(DateTime month) {
    int dim = DateTime(month.year, month.month + 1, 0).day;
    Map<String, int> count = {};
    double ot = 0; double allow = 0; double hrs = 0;
    for (int i = 1; i <= dim; i++) {
      String key = DateFormat('yyyy-MM-dd').format(DateTime(month.year, month.month, i));
      String? code = roster[key];
      if (code == null) continue;
      count[code] = (count[code]?? 0) + 1;
      var def = defs[code];
      if (def!= null) { hrs += def.hours; ot += def.ot; allow += def.allowance; }
    }
    return {'count': count, 'ot': ot, 'allow': allow, 'hrs': hrs, 'balance': carry + hrs - 168};
  }

  bool isHoliday(DateTime d) { return holidays.containsKey(DateFormat('MM-dd').format(d)); }
  String holidayName(DateTime d) { return holidays[DateFormat('MM-dd').format(d)]?? ''; }

  Widget buildDay(DateTime day, bool inMonth) {
    if (!inMonth) return Container();
