import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:device_calendar/device_calendar.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzData;
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:home_widget/home_widget.dart';
import 'package:image/image.dart' as img;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzData.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Hong_Kong'));
  HomeWidget.setAppGroupId('group.rosterPro');
  runApp(const RosterApp());
}

class LeaveDef {
  String name; String fullName; Color color; bool isCustom;
  LeaveDef(this.name, this.fullName, this.color, {this.isCustom = false});
  Map<String, dynamic> toJson() => {'name': name, 'fullName': fullName, 'color': color.value, 'isCustom': isCustom};
  factory LeaveDef.fromJson(Map<String, dynamic> j) => LeaveDef(j['name'], j['fullName'] ?? j['name'], Color(j['color'] ?? 0xFF9C27B0), isCustom: j['isCustom'] ?? false);
}

class ShiftDef {
  String code; String label; double hours; double ot; Color color; String start; String end;
  bool hasMorningAllow; bool hasNightAllow; bool hasMealAllow; bool isAllDay; bool hasLunch;
  bool hasAL; bool hasSH; bool hasGH; bool hasWB; bool hasCustomLeave; String? customLeaveCode;
  ShiftDef(this.code, this.label, this.hours, this.color, {this.ot = 0, this.start = '07:00', this.end = '15:30', this.hasMorningAllow = false, this.hasNightAllow = false, this.hasMealAllow = false, this.isAllDay = false, this.hasLunch = false, this.hasAL = false, this.hasSH = false, this.hasGH = false, this.hasWB = false, this.hasCustomLeave = false, this.customLeaveCode});
  Map<String, dynamic> toJson() => {'code': code, 'label': label, 'hours': hours, 'ot': ot, 'color': color.value, 'start': start, 'end': end, 'hasMorningAllow': hasMorningAllow, 'hasNightAllow': hasNightAllow, 'hasMealAllow': hasMealAllow, 'isAllDay': isAllDay, 'hasLunch': hasLunch, 'hasAL': hasAL, 'hasSH': hasSH, 'hasGH': hasGH, 'hasWB': hasWB, 'hasCustomLeave': hasCustomLeave, 'customLeaveCode': customLeaveCode};
  factory ShiftDef.fromJson(Map<String, dynamic> j) => ShiftDef(j['code'], j['label'] ?? j['code'], (j['hours'] ?? 8).toDouble(), Color(j['color'] ?? 0xFFFF9800), ot: (j['ot'] ?? 0).toDouble(), start: j['start'] ?? '07:00', end: j['end'] ?? '15:30', hasMorningAllow: j['hasMorningAllow'] ?? false, hasNightAllow: j['hasNightAllow'] ?? false, hasMealAllow: j['hasMealAllow'] ?? false, isAllDay: j['isAllDay'] ?? false, hasLunch: j['hasLunch'] ?? false, hasAL: j['hasAL'] ?? false, hasSH: j['hasSH'] ?? false, hasGH: j['hasGH'] ?? false, hasWB: j['hasWB'] ?? false, hasCustomLeave: j['hasCustomLeave'] ?? false, customLeaveCode: j['customLeaveCode']);
}

class ExtraAllowance {
  String name; double amount; double multiplier;
  ExtraAllowance(this.name, this.amount, {this.multiplier = 1.0});
  Map<String, dynamic> toJson() => {'name': name, 'amount': amount, 'multiplier': multiplier};
  factory ExtraAllowance.fromJson(Map<String, dynamic> j) => ExtraAllowance(j['name'], (j['amount'] as num).toDouble(), multiplier: ((j['multiplier'] ?? 1.0) as num).toDouble());
}

class SavedPattern {
  String name; List<List<String>> data;
  SavedPattern(this.name, this.data);
  Map<String, dynamic> toJson() => {'name': name, 'data': data};
  factory SavedPattern.fromJson(Map<String, dynamic> j) => SavedPattern(j['name'], (j['data'] as List).map<List<String>>((r) => (r as List).map<String>((e) => e.toString()).toList()).toList());
}

class LunarHelper {
  static final List<int> lunarInfo = [0x04bd8, 0x04ae0, 0x0a570, 0x054d5, 0x0d260, 0x0d950, 0x16554, 0x056a0, 0x09ad0, 0x055d2, 0x04ae0, 0x0a5b6, 0x0a4d0, 0x0d250, 0x1d255, 0x0b540, 0x0d6a0, 0x0ada2, 0x095b0, 0x14977, 0x04970, 0x0a4b0, 0x0b4b5, 0x06a50, 0x06d40, 0x1ab54, 0x02b60, 0x09570, 0x052f2, 0x04970, 0x06566, 0x0d4a0, 0x0ea50, 0x06e95, 0x05ad0, 0x02b60, 0x186e3, 0x092e0, 0x1c8d7, 0x0c950, 0x0d4a0, 0x1d8a6, 0x0b550, 0x056a0, 0x1a5b4, 0x025d0, 0x092d0, 0x0d2b2, 0x0a950, 0x0b557, 0x06ca0, 0x0b550, 0x15355, 0x04da0, 0x0a5b0, 0x14573, 0x052b0, 0x0a9a8, 0x0e950, 0x06aa0, 0x0aea6, 0x0ab50, 0x04b60, 0x0aae4, 0x0a570, 0x05260, 0x0f263, 0x0d950, 0x05b57, 0x056a0, 0x096d0, 0x04dd5, 0x04ad0, 0x0a4d0, 0x0d4d4, 0x0d250, 0x0d558, 0x0b540, 0x0b5a0, 0x195a6, 0x095b0, 0x049b0, 0x0a974, 0x0a4b0, 0x0b27a, 0x06a50, 0x06d40, 0x0af46, 0x0ab60, 0x09570, 0x04af5, 0x04970, 0x064b0, 0x074a3, 0x0ea50, 0x06b58, 0x055c0, 0x0ab60, 0x096d5, 0x092e0, 0x0c960, 0x0d954, 0x0d4a0, 0x0da50, 0x07552, 0x056a0, 0x0abb7, 0x025d0, 0x092d0, 0x0cab5, 0x0a950, 0x0b4a0, 0x0baa4, 0x0ad50, 0x055d9, 0x04ba0, 0x0a5b0, 0x15176, 0x052b0, 0x0a930, 0x07954, 0x06aa0, 0x0ad50, 0x05b52, 0x04b60, 0x0a6e6, 0x0a4e0, 0x0d260, 0x0ea65, 0x0d530, 0x05aa0, 0x076a3, 0x096d0, 0x04afb, 0x04ad0, 0x0a4d0, 0x1d0b6, 0x0d250, 0x0d520, 0x0dd45, 0x0b5a0, 0x056d0, 0x055b2, 0x049b0, 0x0a577, 0x0a4b0, 0x0aa50, 0x1b255, 0x06d20, 0x0ada0];
  static final List<String> lunarMonths = ['正','二','三','四','五','六','七','八','九','十','冬','臘'];
  static final List<String> lunarDays = ['初一','初二','初三','初四','初五','初六','初七','初八','初九','初十','十一','十二','十三','十四','十五','十六','十七','十八','十九','二十','廿一','廿二','廿三','廿四','廿五','廿六','廿七','廿八','廿九','三十'];
  static int leapMonth(int y) => lunarInfo[y - 1900] & 0xf;
  static int leapDays(int y) { if (leapMonth(y) == 0) return 0; return ((lunarInfo[y - 1900] & 0x10000) != 0) ? 30 : 29; }
  static int monthDays(int y, int m) => ((lunarInfo[y - 1900] & (0x10000 >> m)) != 0) ? 30 : 29;
  static int lYearDays(int y) { int sum = 348; for (int i = 0x8000; i > 0x8; i >>= 1) sum += ((lunarInfo[y - 1900] & i) != 0) ? 1 : 0; return sum + leapDays(y); }
  static List<int> solarToLunar(DateTime date) {
    int offset = date.difference(DateTime(1900, 1, 31)).inDays; int year = 1900;
    while (year < 2100 && offset > lYearDays(year)) { offset -= lYearDays(year); year++; }
    int leap = leapMonth(year); bool isLeap = false; int month = 1;
    while (month < 13 && offset > 0) {
      int days;
      if (leap > 0 && month == leap + 1 && !isLeap) { isLeap = true; days = leapDays(year); } else { days = monthDays(year, month); }
      if (isLeap && month == leap + 1) isLeap = false;
      if (offset < days) break;
      offset -= days;
      if (isLeap && month == leap + 1) isLeap = true;
      month++;
    }
    return [month, offset + 1, isLeap ? 1 : 0];
  }
  static String getLunarDayText(DateTime date) {
    try { if (date.year > 2100) return '超出範圍'; final r = solarToLunar(date); if (r[1] == 1) return '${r[2] == 1 ? '閏' : ''}${lunarMonths[r[0] - 1]}月'; return lunarDays[r[1] - 1]; } catch (_) { return ''; }
  }
  static String getFullLunarText(DateTime date) {
    try { if (date.year > 2100) return ''; final r = solarToLunar(date); final ms = '${r[2] == 1 ? '閏' : ''}${lunarMonths[r[0] - 1]}月'; return r[1] == 1 ? ms : '$ms${lunarDays[r[1] - 1]}'; } catch (_) { return ''; }
  }
}

class RosterApp extends StatelessWidget {
  const RosterApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(title: 'Roster Pro', theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.deepPurple), home: const MainPage());
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});
  @override
  State<MainPage> createState() => MainPageState();
}

class MainPageState extends State<MainPage> {
  int tab = 0;
  DateTime focused = DateTime.now();
  DateTime selectedDay = DateTime.now();
  Map<String, String> roster = {};
  Map<String, String> rosterNote = {};
  Map<String, String> rosterExtraType = {};
  Map<String, double> rosterOt = {};
  Map<String, double> rosterExtra = {};
  Map<String, double> rosterExtraHrs = {};
  List<LeaveDef> leaveDefs = [LeaveDef('AL', 'Annual Leave', Colors.teal), LeaveDef('GH', 'General Holiday', Colors.indigo), LeaveDef('SH', 'Statutory Holiday', Colors.deepOrange), LeaveDef('WB', 'Well-being Leave', Colors.lightBlue)];
  Map<String, Map<String, dynamic>> leaveRecords = {};
  Map<String, String> rosterLeave = {};
  Map<String, ShiftDef> defs = {
    '早': ShiftDef('早', '早更', 8, Colors.orange, start: '07:00', end: '15:30', hasMorningAllow: true),
    '中': ShiftDef('中', '中更', 8, Colors.blue, start: '14:00', end: '22:00'),
    '宵': ShiftDef('宵', '宵更', 8, Colors.purple, start: '22:00', end: '06:00', hasNightAllow: true),
    'O': ShiftDef('O', '休', 0, Colors.green, start: '00:00', end: '00:00', isAllDay: true),
  };
  List<List<String>> pattern = [["早", "早", "中", "中", "宵", "宵", "O"], ["早", "早", "早", "中", "中", "O", "O"]];
  List<List<String>> get _defaultPattern => [["早", "早", "中", "中", "宵", "宵", "O"], ["早", "早", "早", "中", "中", "O", "O"]];
  List<SavedPattern> savedPatterns = [];
  String selectedPatternCode = "O";
  double carry = 0;
  String customName = '我的排更-專屬日曆';
  TextEditingController nameCtrl = TextEditingController();
  double standardWeeklyHours = 42;
  double overtimeRate = 80;
  double monthlySalary = 0;
  double hourlyDivisor = 182;
  double otMultiplier = 1.5;
  double get standardHourlyRate => (monthlySalary > 0 && hourlyDivisor > 0) ? monthlySalary / hourlyDivisor : 0.0;
  double get overtimeHourlyRate => standardHourlyRate * otMultiplier;
  double morningAllowance = 0;
  double nightAllowance = 0;
  double mealAllowance = 0;
  double nightAllowMultiplier = 0.4;
  List<ExtraAllowance> extraAllowances = [];
  double calendarFontSize = 14;
  bool googleSyncEnabled = false;
  bool autoSync = false;
  bool isYearReport = false;
  bool showAllShift = false;
  bool showAllExtra = false;
  bool showLunar = true;
  String? editingPatternName;
  int? editingPatternIndex;
  String holidayRegion = '香港';
  Map<String, String> manualHolidays = {};
  GlobalKey calKey = GlobalKey();
  DeviceCalendarPlugin _calendarPlugin = DeviceCalendarPlugin();
  static const _realChannel = MethodChannel('com.roster/calendar_real');
  String? _rosterCalendarId;
  String _rosterCalendarName = '未選';
  String _rosterAccountName = '';
  Map<String, String> _googleEventIdMap = {};
  Set<String> _dirtyDates = <String>{};
  bool _needsFullSync = false;
  double widgetFontSize = 14.0;
  int widgetTextColor = 0xFF000000;
  int widgetBgColor = 0xFFFFFFFF;
  int iconIndex = 0;
  Timer? _autoSyncTimer;
  String appVersion = '載入中...';
  bool _isSyncing = false;
  String _lastBackupPath = '未備份';
  Color todayBgColor = const Color(0xFFFFF9C4);
  Color todayBorderColor = Colors.orange;
  Color holidayDotColor = Colors.red;

  String _requireCalendarId() {
    final id = _rosterCalendarId;
    if (id == null || id.isEmpty) throw '尚未選擇日曆，請至「設定 → 選擇日曆」指定目標日曆';
    return id;
  }

  Future<bool> _safeDeleteEvent(String eventId) async {
    final calId = _requireCalendarId();
    try {
      final bool? ok = await _realChannel.invokeMethod('deleteEvent', {'calendarId': calId, 'eventId': eventId});
      await _writeDebugLog('[原生 deleteEvent] calId=$calId eventId=$eventId ok=$ok');
      if (ok == true) return true;
    } catch (e) { await _writeDebugLog('[原生 deleteEvent 失敗] $e，降級使用 device_calendar'); }
    try {
      final ok = await _calendarPlugin.deleteEvent(calId, eventId);
      await _writeDebugLog('[device_calendar deleteEvent] ok=$ok');
      return ok == true;
    } catch (e) { return false; }
  }

  // ✅ 修改：優先使用原生通道，並加入超時保護（解決首次同步卡死）
  Future<List<Event>> _safeRetrieveEvents(DateTime start, DateTime end) async {
    final calId = _requireCalendarId();
    try {
      final List<dynamic>? res = await _realChannel.invokeMethod('queryEvents', {
        'calendarId': calId, 'startMillis': start.millisecondsSinceEpoch, 'endMillis': end.millisecondsSinceEpoch,
      }).timeout(const Duration(seconds: 10), onTimeout: () {
        _writeDebugLog('[原生 queryEvents 超時] $start ~ $end'); return null;
      });
      if (res != null) {
        return res.map((e) {
          final map = Map<String, dynamic>.from(e as Map);
          return Event(calId, eventId: map['eventId']?.toString(), title: map['title']?.toString(), description: map['description']?.toString(),
            start: map['startMillis'] != null ? tz.TZDateTime.fromMillisecondsSinceEpoch(tz.UTC, map['startMillis']) : null,
            end: map['endMillis'] != null ? tz.TZDateTime.fromMillisecondsSinceEpoch(tz.UTC, map['endMillis']) : null,
            allDay: map['allDay'] == true);
        }).toList();
      }
    } catch (e) { await _writeDebugLog('[原生 queryEvents 失敗] $e'); }
    try {
      final res = await _calendarPlugin.retrieveEvents(calId, RetrieveEventsParams(startDate: start, endDate: end));
      return res.data ?? [];
    } catch (e) { return []; }
  }

  Future<void> _writeDebugLog(String message) async {
    try {
      final dir = await getExternalStorageDirectory(); if (dir == null) return;
      final f = File('${dir.path}/roster_widget_debug.txt');
      final ts = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
      await f.writeAsString('[$ts][Dart] $message\n', mode: FileMode.append);
      if (await f.length() > 200 * 1024) await f.writeAsString('[$ts] (log reset)\n');
    } catch (_) {}
  }

  Future<bool> _confirmAction() async {
    bool? r = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('⚠️ 確認操作'), content: const Text('相關數據會被刪除或覆蓋，確定繼續進行？'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('確定繼續'))],
    )); return r == true;
  }
  Future<void> updateWidget() async {
  try {
    String todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
    String tomorrowKey = DateFormat('yyyy-MM-dd').format(DateTime.now().add(const Duration(days: 1)));
    await _writeDebugLog('--- updateWidget 開始 ---');
    try { await HomeWidget.saveWidgetData<String>('today_code', roster[todayKey] ?? 'O'); } catch (_) {}
    try { await HomeWidget.saveWidgetData<String>('tomorrow_code', roster[tomorrowKey] ?? 'O'); } catch (_) {}
    try { await HomeWidget.saveWidgetData<String>('note', rosterNote[todayKey] ?? ''); } catch (_) {}
    try { await HomeWidget.saveWidgetData<String>('extraType', rosterExtraType[todayKey] ?? ''); } catch (_) {}
    try { await HomeWidget.saveWidgetData<String>('today_bg', todayBgColor.value.toString()); } catch (_) {}
    try { await HomeWidget.saveWidgetData<String>('today_border', todayBorderColor.value.toString()); } catch (_) {}
    try { await HomeWidget.saveWidgetData<String>('roster_json', jsonEncode(roster)); } catch (_) {}
    try { await HomeWidget.saveWidgetData<String>('defs_json', jsonEncode(defs.map((k, v) => MapEntry(k, v.toJson())))); } catch (_) {}
    try {
      Map<String, String> lunarMap = {};
      DateTime startLunar = DateTime(DateTime.now().year - 1, 1, 1);
      DateTime endLunar = DateTime(DateTime.now().year + 1, 12, 31);
      for (DateTime d = startLunar; !d.isAfter(endLunar); d = d.add(const Duration(days: 1))) {
        lunarMap[DateFormat('yyyy-MM-dd').format(d)] = LunarHelper.getLunarDayText(d);
      }
      await HomeWidget.saveWidgetData<String>('lunar_json', jsonEncode(lunarMap));
    } catch (_) {}
    try { await HomeWidget.saveWidgetData<double>('widgetFontSize', widgetFontSize); } catch (_) {}
    try { await HomeWidget.saveWidgetData<String>('widgetTextColor', widgetTextColor.toString()); } catch (_) {}
    try { await HomeWidget.saveWidgetData<String>('widgetBgColor', widgetBgColor.toString()); } catch (_) {}
    DateTime now = DateTime.now();
    try { await HomeWidget.saveWidgetData<int>('initial_year', now.year); } catch (_) {}
    try { await HomeWidget.saveWidgetData<int>('initial_month', now.month); } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 300));
    try { await HomeWidget.updateWidget(androidName: 'RosterWidgetProvider'); } catch (_) {}
    try { await _realChannel.invokeMethod('updateWidget'); } catch (_) {}
  } catch (_) {}
}

Map<String, String> getHolidays(int year, String region) {
  Map<String, String> m = {};
  if (region == '無') return m;
  if (region == '香港') {
    m['${year}-01-01'] = '元旦'; m['${year}-05-01'] = '勞動節'; m['${year}-07-01'] = '回歸'; m['${year}-10-01'] = '國慶'; m['${year}-12-25'] = '聖誕';
    if (year == 2024) { m.addAll({'2024-02-10': '初一', '2024-02-11': '初二', '2024-02-12': '初三', '2024-04-04': '清明', '2024-05-15': '佛誕', '2024-06-10': '端午', '2024-09-18': '中秋翌日', '2024-10-11': '重陽', '2024-12-26': '聖誕後'}); }
    else if (year == 2025) { m.addAll({'2025-01-29': '初一', '2025-01-30': '初二', '2025-01-31': '初三', '2025-04-04': '清明', '2025-05-05': '佛誕', '2025-05-31': '端午', '2025-10-07': '中秋翌日', '2025-10-29': '重陽'}); }
    else if (year == 2026) { m.addAll({'2026-02-17': '初一', '2026-02-18': '初二', '2026-02-19': '初三', '2026-04-05': '清明', '2026-05-24': '佛誕', '2026-06-19': '端午', '2026-09-26': '中秋翌日', '2026-10-18': '重陽'}); }
    else if (year == 2027) { m.addAll({'2027-02-06': '初一', '2027-02-07': '初二', '2027-02-08': '初三', '2027-04-05': '清明', '2027-05-13': '佛誕', '2027-06-09': '端午', '2027-09-16': '中秋翌日', '2027-10-08': '重陽'}); }
    else if (year == 2028) { m.addAll({'2028-01-26': '初一', '2028-01-27': '初二', '2028-01-28': '初三', '2028-04-04': '清明', '2028-05-01': '佛誕', '2028-05-27': '端午', '2028-10-04': '中秋翌日', '2028-10-26': '重陽'}); }
    else if (year == 2029) { m.addAll({'2029-02-13': '初一', '2029-02-14': '初二', '2029-02-15': '初三', '2029-04-05': '清明', '2029-05-20': '佛誕', '2029-06-16': '端午', '2029-09-23': '中秋翌日', '2029-10-15': '重陽'}); }
    else if (year == 2030) { m.addAll({'2030-02-03': '初一', '2030-02-04': '初二', '2030-02-05': '初三', '2030-04-05': '清明', '2030-05-09': '佛誕', '2030-06-05': '端午', '2030-09-12': '中秋翌日', '2030-10-04': '重陽'}); }
  }
  if (region == '中國內地') { m['${year}-01-01'] = '元旦'; m['${year}-05-01'] = '勞動節'; m['${year}-10-01'] = '國慶'; }
  if (region == '台灣') { m['${year}-01-01'] = '元旦'; m['${year}-02-28'] = '和平紀念'; m['${year}-10-10'] = '國慶'; }
  if (region == '美國') { m['${year}-01-01'] = 'New Year'; m['${year}-07-04'] = 'Independence'; m['${year}-11-11'] = 'Veterans'; m['${year}-12-25'] = 'Christmas'; }
  m.addAll(manualHolidays); return m;
}

bool isHoliday(DateTime d) { var map = getHolidays(d.year, holidayRegion); return map.containsKey(DateFormat('yyyy-MM-dd').format(d)); }
String holidayName(DateTime d) { var map = getHolidays(d.year, holidayRegion); return map[DateFormat('yyyy-MM-dd').format(d)] ?? ''; }

@override
void initState() {
  super.initState(); nameCtrl.text = customName; _loadVersion();
  if (!Permission.manageExternalStorage.isGranted) Permission.manageExternalStorage.request();
  HomeWidget.registerInteractivityCallback(backgroundCallback);
  load().then((_) async {
    await Future.delayed(const Duration(milliseconds: 500));
    bool ok = await handleCalendarPermission(silent: false);
    if (!ok && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('需要日曆權限才能讀取日曆')));
    try { await _realChannel.invokeMethod('requestManageStorage'); } catch (_) {}
    await updateWidget();
    if (googleSyncEnabled) Future.delayed(const Duration(seconds: 2), () { if (mounted) _syncToGoogle(silent: true, forceFullSync: false); });
  });
}

@pragma('vm:entry-point')
static Future<void> backgroundCallback(Uri? uri) async { if (uri != null) debugPrint('小工具點擊: $uri'); }

Future<void> _loadVersion() async {
  try { final info = await PackageInfo.fromPlatform(); setState(() => appVersion = '${info.version}+${info.buildNumber}'); } catch (_) { setState(() => appVersion = '7.1.9+71'); }
}

Future<void> load() async {
  var sp = await SharedPreferences.getInstance();
  var r = sp.getString('roster'); if (r != null) roster = Map<String, String>.from(jsonDecode(r));
  var rn = sp.getString('note'); if (rn != null) rosterNote = Map<String, String>.from(jsonDecode(rn));
  var rt = sp.getString('extraType'); if (rt != null) rosterExtraType = Map<String, String>.from(jsonDecode(rt));
  var ro = sp.getString('roOt'); if (ro != null) { try { rosterOt = Map<String, double>.from((jsonDecode(ro) as Map).map((k, v) => MapEntry(k as String, (v as num).toDouble()))); } catch (_) {} }
  var re = sp.getString('roEx'); if (re != null) { try { rosterExtra = Map<String, double>.from((jsonDecode(re) as Map).map((k, v) => MapEntry(k as String, (v as num).toDouble()))); } catch (_) {} }
  var reh = sp.getString('roExH'); if (reh != null) { try { rosterExtraHrs = Map<String, double>.from((jsonDecode(reh) as Map).map((k, v) => MapEntry(k as String, (v as num).toDouble()))); } catch (_) {} }
  var d = sp.getString('defs'); if (d != null) { try { defs = (jsonDecode(d) as Map).map((k, v) => MapEntry(k as String, ShiftDef.fromJson(Map<String, dynamic>.from(v)))); } catch (_) {} }
  var p = sp.getString('pattern'); if (p != null) { try { pattern = (jsonDecode(p) as List).map<List<String>>((row) => (row as List).map<String>((e) => e.toString()).toList()).toList(); } catch (_) {} }
  var ea = sp.getString('extraAllowNewV36'); if (ea != null) { try { extraAllowances = (jsonDecode(ea) as List).map((e) => ExtraAllowance.fromJson(Map<String, dynamic>.from(e))).toList(); } catch (_) {} }
  var spSaved = sp.getString('savedPatternsV40'); if (spSaved != null) { try { savedPatterns = (jsonDecode(spSaved) as List).map((e) => SavedPattern.fromJson(Map<String, dynamic>.from(e))).toList(); } catch (_) {} }
  var evMap = sp.getString('googleEventIdMap'); if (evMap != null) { try { _googleEventIdMap = Map<String, String>.from(jsonDecode(evMap)); } catch (_) {} }
  var mh = sp.getString('manualHolidays'); if (mh != null) { try { manualHolidays = Map<String, String>.from(jsonDecode(mh)); } catch (_) {} }
  var ld = sp.getString('leaveDefs'); if (ld != null) { try { leaveDefs = (jsonDecode(ld) as List).map((e) => LeaveDef.fromJson(Map<String, dynamic>.from(e))).toList(); } catch (_) {} }
  var lr = sp.getString('leaveRecords'); if (lr != null) { try { leaveRecords = Map<String, Map<String, dynamic>>.from((jsonDecode(lr) as Map).map((k, v) => MapEntry(k as String, Map<String, dynamic>.from(v as Map)))); } catch (_) {} }
  var rl = sp.getString('rosterLeave'); if (rl != null) { try { rosterLeave = Map<String, String>.from(jsonDecode(rl)); } catch (_) {} }
  var ddList = sp.getStringList('dirtyDates'); if (ddList != null) _dirtyDates = ddList.toSet();
  _needsFullSync = sp.getBool('needsFullSync') ?? false;
  setState(() {
    carry = sp.getDouble('carry') ?? 0; customName = sp.getString('cName') ?? '我的排更-專屬日曆'; nameCtrl.text = customName;
    standardWeeklyHours = sp.getDouble('stdWeek') ?? 42; overtimeRate = sp.getDouble('otRate') ?? 80;
    monthlySalary = sp.getDouble('monthlySalary') ?? 0; hourlyDivisor = sp.getDouble('hourlyDivisor') ?? 182;
    otMultiplier = sp.getDouble('otMultiplier') ?? 1.5; morningAllowance = sp.getDouble('morningAllow') ?? 0;
    nightAllowance = sp.getDouble('nightAllow') ?? 0; mealAllowance = sp.getDouble('mealAllow') ?? 0;
    nightAllowMultiplier = sp.getDouble('nightAllowMultiplier') ?? 0.4; calendarFontSize = sp.getDouble('calFont') ?? 14;
    googleSyncEnabled = sp.getBool('gSync') ?? false; autoSync = sp.getBool('gAuto') ?? false;
    holidayRegion = sp.getString('holidayRegion') ?? '香港'; _rosterCalendarId = sp.getString('rosterCalId');
    _rosterCalendarName = sp.getString('rosterCalName') ?? '未選'; _rosterAccountName = sp.getString('rosterAccName') ?? '';
    _lastBackupPath = sp.getString('lastBackupPath') ?? '未備份'; todayBgColor = Color(sp.getInt('todayBg') ?? 0xFFFFF9C4);
    todayBorderColor = Color(sp.getInt('todayBorder') ?? 0xFFFF9800); showLunar = sp.getBool('showLunar') ?? true;
    widgetFontSize = sp.getDouble('widgetFontSize') ?? 14.0; widgetTextColor = sp.getInt('widgetTextColor') ?? 0xFF000000;
    iconIndex = sp.getInt('iconIndex') ?? 0;
  });
  updateWidget();
}

Future<void> save() async {
  var sp = await SharedPreferences.getInstance();
  sp.setString('roster', jsonEncode(roster)); sp.setString('note', jsonEncode(rosterNote));
  sp.setString('extraType', jsonEncode(rosterExtraType)); sp.setString('roOt', jsonEncode(rosterOt));
  sp.setString('roEx', jsonEncode(rosterExtra)); sp.setString('roExH', jsonEncode(rosterExtraHrs));
  sp.setString('defs', jsonEncode(defs.map((k, v) => MapEntry(k, v.toJson())))); sp.setString('pattern', jsonEncode(pattern));
  sp.setDouble('carry', carry); sp.setString('cName', customName); sp.setDouble('stdWeek', standardWeeklyHours);
  sp.setDouble('otRate', overtimeRate); await sp.setDouble('monthlySalary', monthlySalary);
  await sp.setDouble('hourlyDivisor', hourlyDivisor); await sp.setDouble('otMultiplier', otMultiplier);
  await sp.setDouble('morningAllow', morningAllowance); await sp.setDouble('nightAllow', nightAllowance);
  await sp.setDouble('mealAllow', mealAllowance); await sp.setDouble('nightAllowMultiplier', nightAllowMultiplier);
  sp.setString('extraAllowNewV36', jsonEncode(extraAllowances.map((e) => e.toJson()).toList()));
  sp.setDouble('calFont', calendarFontSize); sp.setBool('gSync', googleSyncEnabled); sp.setBool('gAuto', autoSync);
  sp.setString('savedPatternsV40', jsonEncode(savedPatterns.map((e) => e.toJson()).toList()));
  sp.setString('holidayRegion', holidayRegion); sp.setString('googleEventIdMap', jsonEncode(_googleEventIdMap));
  sp.setString('manualHolidays', jsonEncode(manualHolidays));
  await sp.setString('leaveDefs', jsonEncode(leaveDefs.map((e) => e.toJson()).toList()));
  await sp.setString('leaveRecords', jsonEncode(leaveRecords)); await sp.setString('rosterLeave', jsonEncode(rosterLeave));
  await sp.setStringList('dirtyDates', _dirtyDates.toList()); await sp.setBool('needsFullSync', _needsFullSync);
  if (_rosterCalendarId != null) sp.setString('rosterCalId', _rosterCalendarId!);
  sp.setString('rosterCalName', _rosterCalendarName); sp.setString('rosterAccName', _rosterAccountName);
  sp.setString('lastBackupPath', _lastBackupPath); sp.setInt('todayBg', todayBgColor.value);
  sp.setInt('todayBorder', todayBorderColor.value); sp.setString('roster_json', jsonEncode(roster));
  sp.setString('defs_json', jsonEncode(defs.map((k, v) => MapEntry(k, v.toJson())))); sp.setBool('showLunar', showLunar);
  await sp.setDouble('widgetFontSize', widgetFontSize); await sp.setInt('widgetTextColor', widgetTextColor);
  await sp.setInt('widgetBgColor', widgetBgColor); await sp.setInt('iconIndex', iconIndex);
  await updateWidget();
  if (autoSync && googleSyncEnabled && !_isSyncing) {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer(const Duration(seconds: 3), () { if (!_isSyncing && autoSync && googleSyncEnabled) _syncToGoogle(silent: true); });
  }
}

int isoWeek(DateTime date) { DateTime thursday = date.add(Duration(days: 4 - date.weekday)); return 1 + (thursday.difference(DateTime(thursday.year, 1, 1)).inDays / 7).floor(); }

void quickJumpMonth({bool forReport = false}) {
  int y = focused.year, m = focused.month;
  showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) => AlertDialog(
    title: Text(forReport ? '選擇報表年月' : '快速查找年月'),
    content: Column(mainAxisSize: MainAxisSize.min, children: [
      Row(children: [IconButton(icon: const Icon(Icons.remove), onPressed: () => setD(() => y--)), Expanded(child: Text('${y}年', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))), IconButton(icon: const Icon(Icons.add), onPressed: () => setD(() => y++))]),
      Wrap(spacing: 8, children: List.generate(12, (i) { int mon = i + 1; return ChoiceChip(label: Text('${mon}月'), selected: mon == m, onSelected: (_) => setD(() => m = mon)); }))
    ]),
    actions: [TextButton(onPressed: () => Navigator.pop(ctx2), child: const Text('取消')), FilledButton(onPressed: () { setState(() => focused = DateTime(y, m, 1)); Navigator.pop(ctx2); }, child: const Text('跳轉'))]
  )));
}

Future<bool> handleCalendarPermission({bool silent = false}) async {
  try {
    var s1 = await Permission.calendar.request(); var s2 = await Permission.calendarFullAccess.request(); var s3 = await Permission.calendarWriteOnly.request();
    if (s1.isGranted || s2.isGranted || s3.isGranted) return true;
    if (!silent && s1.isPermanentlyDenied) await showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('需要日曆權限'), content: const Text('請去設定>權限>允許日曆'), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')), FilledButton(onPressed: () { openAppSettings(); Navigator.pop(ctx); }, child: const Text('去設定'))]));
  } catch (_) {}
  try { var devHas = await _calendarPlugin.hasPermissions(); if (devHas.isSuccess && devHas.data == true) return true; var devReq = await _calendarPlugin.requestPermissions(); if (devReq.isSuccess && devReq.data == true) return true; } catch (_) {}
  return false;
}

Future<List<Map<String, dynamic>>> _getRealCalendars() async {
  try { var res = await _realChannel.invokeMethod('getCalendars'); return (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList(); } catch (e) {
    try { var r = await _calendarPlugin.retrieveCalendars(); return (r.data ?? []).map((c) => {'id': c.id, 'displayName': c.name, 'accountName': c.accountName, 'isGoogle': (c.accountName ?? '').contains('gmail') || (c.accountType ?? '').contains('google')}).toList(); } catch (_) { return []; }
  }
}

Future<String?> _pickGoogleCalendarDialog() async {
  if (!await handleCalendarPermission(silent: false)) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未取得日曆權限'))); return null; }
  var cals = await _getRealCalendars(); if (cals.isEmpty) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未讀取到任何日曆'))); return null; }
  var googleCals = cals.where((c) => c['isGoogle'] == true).toList(); var otherCals = cals.where((c) => c['isGoogle'] != true).toList();
  var pickedMap = await showDialog<Map<String, dynamic>>(context: context, builder: (ctx) => AlertDialog(
    title: Text('選擇寫入日曆 (${cals.length})'),
    content: SizedBox(width: 460, height: 560, child: ListView(children: [
      Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.green.withOpacity(0.12), borderRadius: BorderRadius.circular(8)), child: const Text('綠色=Google帳號 灰色=本機日曆', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green))),
      const SizedBox(height: 8), Text('Google 日曆 (${googleCals.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
      ...googleCals.map((cal) => Card(color: Colors.green.withOpacity(0.15), child: ListTile(leading: const Icon(Icons.cloud_done, color: Colors.green), title: Text('${cal['displayName']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)), subtitle: Text('帳號: ${cal['accountName']}\nID: ${cal['id']}', style: const TextStyle(fontSize: 9)), onTap: () => Navigator.pop(ctx, cal)))),
      const Divider(), Text('其他日曆 (${otherCals.length})'),
      ...otherCals.map((cal) => Card(child: ListTile(leading: const Icon(Icons.phone_android), title: Text('${cal['displayName']}', style: const TextStyle(fontSize: 13)), subtitle: Text('${cal['accountName']}', style: const TextStyle(fontSize: 9)), onTap: () => Navigator.pop(ctx, cal)))),
    ])),
    actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消'))],
  ));
  if (pickedMap != null && pickedMap['id'] != null) {
    final newId = pickedMap['id'].toString(), oldId = _rosterCalendarId;
    _rosterCalendarId = newId; _rosterCalendarName = pickedMap['displayName'].toString(); _rosterAccountName = pickedMap['accountName'].toString();
    if (oldId != null && oldId != newId) { _googleEventIdMap.clear(); await _writeDebugLog('切換日曆 $oldId → $newId，已清空 googleEventIdMap'); }
    var sp = await SharedPreferences.getInstance();
    sp.setString('rosterCalId', _rosterCalendarId!); sp.setString('rosterCalName', _rosterCalendarName); sp.setString('rosterAccName', _rosterAccountName); await sp.setString('googleEventIdMap', jsonEncode(_googleEventIdMap));
    setState(() {}); if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已選 $_rosterCalendarId'))); return _rosterCalendarId;
  }
  return null;
}

Future<String?> _createCustomCalendarDialog() async {
  if (!await handleCalendarPermission(silent: false)) return null;
  var nameCtrl = TextEditingController(text: '我的排更專屬日曆');
  bool? confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
    title: const Text('建立自訂日曆'), content: Column(mainAxisSize: MainAxisSize.min, children: [const Text('請輸入日曆名稱'), const SizedBox(height: 12), TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '日曆名稱', border: OutlineInputBorder()))]),
    actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('建立'))],
  ));
  if (confirm != true || nameCtrl.text.trim().isEmpty) return null;
  try {
    final result = await _calendarPlugin.createCalendar(nameCtrl.text.trim());
    if (result.isSuccess && result.data != null) {
      _rosterCalendarId = result.data; _rosterCalendarName = nameCtrl.text.trim();
      var sp = await SharedPreferences.getInstance(); await sp.setString('rosterCalId', _rosterCalendarId!); await sp.setString('rosterCalName', _rosterCalendarName); await sp.setString('rosterAccName', 'local');
      setState(() {}); if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已成功建立日曆：$_rosterCalendarName'))); return _rosterCalendarId;
    }
  } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('建立錯誤：$e'))); }
  return null;
}

Future<void> _requestGooglePerm() async {
  int? choice = await showDialog<int>(context: context, builder: (ctx) => AlertDialog(title: const Text('選擇日曆來源'), content: const Text('您想要如何設定同步用的日曆？'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, 1), child: const Text('選擇已有日曆')), FilledButton(onPressed: () => Navigator.pop(ctx, 2), child: const Text('建立自訂日曆'))]));
  if (choice == null) return; String? id;
  if (choice == 1) id = await _pickGoogleCalendarDialog(); else id = await _createCustomCalendarDialog();
  if (id == null) return;
  bool? ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('已選擇日曆'), content: Text('將寫入：$_rosterCalendarName\nID: $id'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('稍後')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('立即同步'))]));
  if (ok == true) { setState(() => googleSyncEnabled = true); await _syncToGoogle(); save(); }
}

Future<void> _ensureCalendar() async { if (_rosterCalendarId == null || _rosterCalendarId!.isEmpty) await _pickGoogleCalendarDialog(); }
void _markDirty(String dateKey) { _dirtyDates.add(dateKey); }

Map<String, String>? _parseShiftFromDesc(String? desc, {String? title}) {
  try {
    if (desc != null && desc.isNotEmpty) {
      final shiftMatch = RegExp(r'班次:\s*(\S+)').firstMatch(desc);
      if (shiftMatch != null) {
        final code = shiftMatch.group(1)?.trim() ?? '';
        if (code.isNotEmpty) {
          final timeMatch = RegExp(r'時間:\s*(\d{1,2}:\d{2})-(\d{1,2}:\d{2})').firstMatch(desc);
          if (timeMatch != null) return {'code': code, 'start': _padTime(timeMatch.group(1)!), 'end': _padTime(timeMatch.group(2)!)};
          if (desc.contains('類型: 全天') || desc.contains('全天')) return {'code': code, 'start': '全天', 'end': '全天'};
        }
      }
    }
    if (title != null && title.trim().isNotEmpty) {
      String t = title.trim(); final pipeIdx = t.indexOf(' | '); if (pipeIdx >= 0) t = t.substring(0, pipeIdx).trim();
      final m = RegExp(r'^(\S+)\s+(\d{1,2}:\d{2})-(\d{1,2}:\d{2})').firstMatch(t);
      if (m != null) return {'code': m.group(1)!, 'start': _padTime(m.group(2)!), 'end': _padTime(m.group(3)!)};
      final s = RegExp(r'^(\S+)$').firstMatch(t); if (s != null) return {'code': s.group(1)!, 'start': '全天', 'end': '全天'};
    }
  } catch (_) {}
  return null;
}

String _padTime(String t) { final parts = t.split(':'); if (parts.length != 2) return t; return '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}'; }

Future<bool> _buildAndInsertEvent(String dateKey, String code, Duration offset, {String? existingEventId}) async {
  final calId = _requireCalendarId(); final def = defs[code]; if (def == null) return false;
  final date = DateTime.parse(dateKey); final note = rosterNote[dateKey] ?? ''; final tag = '[RosterPro]$dateKey'; final allDayFlag = def.isAllDay || def.code == 'O';
  String desc, title;
  if (allDayFlag) { desc = '$tag\n$customName\n班次: ${def.code} ${def.label}\n類型: 全天${note.isNotEmpty ? '\n記事: $note' : ''}'; title = '${def.code}${note.isNotEmpty ? ' | $note' : ''}'; }
  else { desc = '$tag\n$customName\n班次: ${def.code} ${def.label}\n時間: ${def.start}-${def.end}${note.isNotEmpty ? '\n記事: $note' : ''}'; title = '${def.code} ${def.start}-${def.end}${note.isNotEmpty ? ' | $note' : ''}'; }
  Event ev;
  if (allDayFlag) { ev = Event(calId, eventId: existingEventId, title: title, description: desc, start: tz.TZDateTime(tz.local, date.year, date.month, date.day, 0, 0, 0), end: tz.TZDateTime(tz.local, date.year, date.month, date.day, 23, 59, 59), allDay: true); }
  else {
    final sp1 = def.start.split(':'), ep1 = def.end.split(':');
    DateTime sLocal = DateTime(date.year, date.month, date.day, int.parse(sp1[0]), int.parse(sp1[1]));
    DateTime eLocal = DateTime(date.year, date.month, date.day, int.parse(ep1[0]), int.parse(ep1[1]));
    if (!eLocal.isAfter(sLocal)) eLocal = eLocal.add(const Duration(days: 1));
    DateTime sUtc = sLocal.subtract(offset), eUtc = eLocal.subtract(offset);
    ev = Event(calId, eventId: existingEventId, title: title, description: desc, start: tz.TZDateTime.utc(sUtc.year, sUtc.month, sUtc.day, sUtc.hour, sUtc.minute), end: tz.TZDateTime.utc(eUtc.year, eUtc.month, eUtc.day, eUtc.hour, eUtc.minute), allDay: false);
  }
  try {
    final res = await _calendarPlugin.createOrUpdateEvent(ev);
    if (res != null && res.isSuccess && res.data != null) { _googleEventIdMap[dateKey] = res.data!; await _writeDebugLog('[createOrUpdateEvent] ok dateKey=$dateKey'); return true; }
  } catch (e) { await _writeDebugLog('[createOrUpdateEvent] 例外: $e'); }
  return false;
}

Future<void> _syncNow() async { if (!googleSyncEnabled) return; await _syncToGoogle(silent: true); }

Future<void> syncDateRange() async {
  if (!googleSyncEnabled) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請先啟用日曆同步'))); return; }
  DateTimeRange? range = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(DateTime.now().year + 30, 12, 31), helpText: '選擇要同步的日期範圍', saveText: '同步');
  if (range == null) return;
  Set<String> inRange = <String>{}; DateTime cur = DateTime(range.start.year, range.start.month, range.start.day); DateTime last = DateTime(range.end.year, range.end.month, range.end.day);
  while (!cur.isAfter(last)) { String k = DateFormat('yyyy-MM-dd').format(cur); if (_dirtyDates.contains(k)) inRange.add(k); cur = cur.add(const Duration(days: 1)); }
  if (inRange.isEmpty) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('所選範圍內沒有變更需要同步'))); return; }
  if (!await _confirmAction()) return;
  Set<String> others = Set<String>.from(_dirtyDates)..removeAll(inRange); _dirtyDates = inRange; await _syncToGoogle(silent: false); _dirtyDates.addAll(others);
  var sp = await SharedPreferences.getInstance(); await sp.setStringList('dirtyDates', _dirtyDates.toList());
}

// ✅ 核心修改：全量重建改為按年份迴圈分批掃描，避免卡死
Future<void> _syncToGoogle({bool silent = false, bool forceFullSync = false}) async {
  if (!googleSyncEnabled && !silent) {
    bool? en = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('未開啟同步'), content: const Text('是否開啟同步並立即寫入？'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('開啟並同步'))]));
    if (en == true) setState(() => googleSyncEnabled = true); else return;
  }
  if (_isSyncing) return;
  if (_rosterCalendarId == null || _rosterCalendarId!.isEmpty) { if (!silent) await _ensureCalendar(); if (_rosterCalendarId == null || _rosterCalendarId!.isEmpty) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('尚未選擇日曆'))); return; } }
  bool needFull = forceFullSync || _needsFullSync;
  if (!needFull && _dirtyDates.isEmpty) { if (!silent && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('沒有變更需要同步'))); return; }
  _isSyncing = true; _autoSyncTimer?.cancel();
  if (!silent && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(needFull ? '開始完整同步...' : '開始增量同步...')));
  final ValueNotifier<double> progressNotifier = ValueNotifier(0.0);
  final ValueNotifier<String> statusNotifier = ValueNotifier(needFull ? '正在準備全清重建...' : '正在準備增量同步...');
  BuildContext? loadingCtx;
  if (mounted) {
    showDialog(context: context, barrierDismissible: false, builder: (ctx) { loadingCtx = ctx; return PopScope(canPop: false, child: AlertDialog(title: const Text('同步進行中'), content: ValueListenableBuilder<double>(valueListenable: progressNotifier, builder: (context, progress, child) => ValueListenableBuilder<String>(valueListenable: statusNotifier, builder: (context, status, child) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [LinearProgressIndicator(value: progress == -1 ? null : progress), const SizedBox(height: 16), Text(status, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)), if (progress >= 0) Padding(padding: const EdgeInsets.only(top: 8), child: Text('${(progress * 100).toStringAsFixed(1)}%', style: const TextStyle(fontSize: 12, color: Colors.grey)))])))); });
  }
  try {
    final calId = _requireCalendarId(); await _writeDebugLog('=== 開始同步，日曆ID: $calId, needFull=$needFull ===');
    final sp = await SharedPreferences.getInstance(); final offset = DateTime.now().timeZoneOffset; int del = 0, delFailed = 0, add = 0, upd = 0;
    if (needFull) {
      // ===== 全量重建：按年份迴圈分批掃描，徹底清理舊的 [RosterPro] 事件 =====
      await _writeDebugLog('=== 全量重建：分批掃描清理 [RosterPro] calId=$calId ===');
      statusNotifier.value = '正在掃描並刪除舊排班...'; progressNotifier.value = -1;
      final Set<String> deletedIds = <String>{};
      for (int year = 2000; year <= 2100; year++) {
        statusNotifier.value = '正在掃描 $year 年...';
        DateTime startScan = DateTime(year, 1, 1); DateTime endScan = DateTime(year, 12, 31);
        List<Event> events = [];
        try { events = await _safeRetrieveEvents(startScan, endScan); } catch (e) { await _writeDebugLog('掃描 $year 年失敗: $e'); }
        for (var e in events) {
          final desc = e.description ?? ''; if (!desc.contains('[RosterPro]') || e.eventId == null || deletedIds.contains(e.eventId)) continue;
          final ok = await _safeDeleteEvent(e.eventId!); if (ok) { deletedIds.add(e.eventId!); del++; } else { delFailed++; }
        }
      }
      _googleEventIdMap.clear(); statusNotifier.value = '舊排班已清理（刪除 $del 條），正在重建事件...'; progressNotifier.value = 0.0;
      int total = roster.length, current = 0;
      for (var entry in roster.entries) { current++; progressNotifier.value = total == 0 ? 1.0 : current / total; statusNotifier.value = '正在建立事件 ($current/$total)...'; final added = await _buildAndInsertEvent(entry.key, entry.value, offset, existingEventId: null); if (added) add++; }
      _needsFullSync = false; _dirtyDates.clear();
      sp.setString('googleEventIdMap', jsonEncode(_googleEventIdMap)); await sp.setStringList('dirtyDates', _dirtyDates.toList()); await sp.setBool('needsFullSync', _needsFullSync); updateWidget();
      await _writeDebugLog('=== 全量重建完成 calId=$calId del=$del delFailed=$delFailed add=$add ===');
      if (!silent && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('完整同步完成：刪除舊事件 $del / 失敗 $delFailed / 建立新事件 $add'), duration: const Duration(seconds: 4)));
      return;
    } else {
      // ===== 增量同步 =====
      if (_googleEventIdMap.isEmpty) {
        statusNotifier.value = '正在掃描現有日曆事件...'; progressNotifier.value = -1;
        DateTime scanStart = _calcScanStart(); DateTime scanEnd = _calcScanEnd();
        try {
          var existingEvents = await _safeRetrieveEvents(scanStart, scanEnd);
          if (existingEvents.isNotEmpty) {
            for (var e in existingEvents) {
              if (e.description != null && e.description!.contains('[RosterPro]')) {
                var match = RegExp(r'\[RosterPro\](\d{4}-\d{2}-\d{2})').firstMatch(e.description!);
                if (match != null && e.eventId != null) _googleEventIdMap[match.group(1)!] = e.eventId!;
              }
            }
          }
        } catch (e) { await _writeDebugLog('掃描重建失敗: $e'); }
      }
      final datesToSync = List<String>.from(_dirtyDates)..sort();
      statusNotifier.value = '正在同步變更...'; progressNotifier.value = 0.0; int total = datesToSync.length, current = 0;
      for (var dateKey in datesToSync) {
        current++; progressNotifier.value = current / total; statusNotifier.value = '正在處理 ($current/$total)...';
        DateTime date = DateTime.parse(dateKey); DateTime queryStart = DateTime(date.year, date.month, date.day, 0, 0, 0).subtract(const Duration(hours: 24)); DateTime queryEnd = DateTime(date.year, date.month, date.day, 23, 59, 59).add(const Duration(hours: 24));
        final eventsInRange = await _safeRetrieveEvents(queryStart, queryEnd);
        List<Event> rosterEvents = eventsInRange.where((e) {
          final desc = e.description ?? '';
          if (desc.contains('[RosterPro]')) { final m = RegExp(r'\[RosterPro\](\d{4}-\d{2}-\d{2})').firstMatch(desc); return m == null || m.group(1) == dateKey; }
          final title = (e.title ?? '').trim(); if (title.isEmpty) return false; String t = title.contains(' | ') ? title.split(' | ')[0].trim() : title;
          if (RegExp(r'^\S+\s+\d{1,2}:\d{2}-\d{1,2}:\d{2}').hasMatch(t)) return true; return RegExp(r'^\S+$').hasMatch(t);
        }).toList();
        if (!roster.containsKey(dateKey)) { for (var e in rosterEvents) { if (e.eventId != null) { final ok = await _safeDeleteEvent(e.eventId!); if (ok) del++; else delFailed++; } } _googleEventIdMap.remove(dateKey); _dirtyDates.remove(dateKey); continue; }
        final newCode = roster[dateKey]!; final newDef = defs[newCode]; if (newDef == null) { _dirtyDates.remove(dateKey); continue; }
        final isAllDayNow = newDef.isAllDay || newDef.code == 'O'; final newStart = isAllDayNow ? '全天' : newDef.start; final newEnd = isAllDayNow ? '全天' : newDef.end;
        String? matchedEventId = _googleEventIdMap[dateKey];
        for (var e in rosterEvents) {
          if (e.eventId == null || e.eventId == matchedEventId) continue;
          final parsed = _parseShiftFromDesc(e.description, title: e.title);
          final isMatch = parsed != null && parsed['code'] == newCode && parsed['start'] == newStart && parsed['end'] == newEnd;
          if (isMatch && matchedEventId == null) matchedEventId = e.eventId;
          else { final ok = await _safeDeleteEvent(e.eventId!); if (ok) del++; else delFailed++; }
        }
        if (matchedEventId != null) { final updated = await _buildAndInsertEvent(dateKey, newCode, offset, existingEventId: matchedEventId); if (updated) { upd++; _googleEventIdMap[dateKey] = matchedEventId; } else { final added = await _buildAndInsertEvent(dateKey, newCode, offset); if (added) { add++; upd++; } } }
        else { final added = await _buildAndInsertEvent(dateKey, newCode, offset); if (added) { add++; upd++; } }
        _dirtyDates.remove(dateKey);
      }
    }
    sp.setString('googleEventIdMap', jsonEncode(_googleEventIdMap)); await sp.setStringList('dirtyDates', _dirtyDates.toList()); await sp.setBool('needsFullSync', _needsFullSync); updateWidget();
    if (!silent && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(needFull ? '完整同步完成：刪$del / 失敗$delFailed / 建$add' : '增量同步完成：刪$del / 失敗$delFailed / 更新$upd / 建$add'), duration: const Duration(seconds: 4)));
  } catch (e) { await _writeDebugLog('同步失敗: $e'); if (mounted && !silent) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('同步失敗 $e'))); }
  finally { _isSyncing = false; final ctx = loadingCtx; if (ctx != null && ctx.mounted) Navigator.pop(ctx); }
}

DateTime _calcScanStart() { int currentYear = DateTime.now().year; int minYear = currentYear - 10; if (roster.isNotEmpty) { for (String k in roster.keys) { if (k.length >= 4) { int? y = int.tryParse(k.substring(0, 4)); if (y != null && y - 2 < minYear) minYear = y - 2; } } } if (minYear > 2000) minYear = 2000; return DateTime(minYear, 1, 1); }
DateTime _calcScanEnd() { int currentYear = DateTime.now().year; int maxYear = currentYear + 30; if (roster.isNotEmpty) { for (String k in roster.keys) { if (k.length >= 4) { int? y = int.tryParse(k.substring(0, 4)); if (y != null && y + 2 > maxYear) maxYear = y + 2; } } } return DateTime(maxYear, 12, 31); }
                 Future<void> _forceCleanDuplicates() async {
    if (_isSyncing) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在同步中，請稍候...'))); return; }
    if (_rosterCalendarId == null || _rosterCalendarId!.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('尚未選擇日曆'))); return; }
    bool? confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('⚠️ 強制清理重複事件'), content: const Text('這會逐日掃描 [RosterPro] 事件：\n• 可解析的：按（代號+開始+結束）分組，每組保留 1 條\n• 無法解析的殘留：若該日已有可解析事件，全部刪除\n\n確定要執行嗎？'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('確定清理'))]));
    if (confirm != true || _isSyncing || !await _confirmAction()) return;
    _isSyncing = true; final calId = _requireCalendarId();
    final progressNotifier = ValueNotifier<double>(0.0); final statusNotifier = ValueNotifier<String>('正在準備掃描...'); BuildContext? loadingCtx;
    if (mounted) showDialog(context: context, barrierDismissible: false, builder: (ctx) { loadingCtx = ctx; return PopScope(canPop: false, child: AlertDialog(title: const Text('清理進行中'), content: ValueListenableBuilder<double>(valueListenable: progressNotifier, builder: (context, progress, child) => ValueListenableBuilder<String>(valueListenable: statusNotifier, builder: (context, status, child) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [LinearProgressIndicator(value: progress <= 0 ? null : progress), const SizedBox(height: 16), Text(status, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)), if (progress > 0) Padding(padding: const EdgeInsets.only(top: 8), child: Text('${(progress * 100).toStringAsFixed(1)}%', style: const TextStyle(fontSize: 12, color: Colors.grey)))])))); });
    int cleaned = 0, scannedDates = 0, matchedDatesWithDup = 0;
    try {
      final Set<String> allKeys = <String>{}..addAll(roster.keys)..addAll(_googleEventIdMap.keys); final sortedKeys = allKeys.toList()..sort();
      if (sortedKeys.isNotEmpty) {
        int total = sortedKeys.length, current = 0;
        for (var dateKey in sortedKeys) {
          current++; progressNotifier.value = current / total; statusNotifier.value = '正在掃描 ($current/$total)：$dateKey'; scannedDates++;
          DateTime date; try { date = DateTime.parse(dateKey); } catch (_) { continue; }
          final eventsOnDay = await _safeRetrieveEvents(DateTime(date.year, date.month, date.day, 0, 0, 0).subtract(const Duration(hours: 24)), DateTime(date.year, date.month, date.day, 23, 59, 59));
          List<Event> rosterEvents = eventsOnDay.where((e) { final desc = e.description ?? ''; if (!desc.contains('[RosterPro]')) return false; final m = RegExp(r'\[RosterPro\](\d{4}-\d{2}-\d{2})').firstMatch(desc); return m == null || m.group(1) == dateKey; }).toList();
          if (rosterEvents.length <= 1) continue;
          Map<String, List<Event>> byKey = {}; List<Event> unparsed = [];
          for (var e in rosterEvents) { final parsed = _parseShiftFromDesc(e.description, title: e.title); if (parsed == null) unparsed.add(e); else byKey.putIfAbsent('${parsed['code']}|${parsed['start']}|${parsed['end']}', () => []).add(e); }
          bool hadDup = false; int parsedGroupCount = 0;
          for (var entry in byKey.entries) { parsedGroupCount++; if (entry.value.length <= 1) continue; hadDup = true; for (int i = 1; i < entry.value.length; i++) { if (entry.value[i].eventId != null) { final ok = await _safeDeleteEvent(entry.value[i].eventId!); if (ok) cleaned++; } } }
          if (unparsed.isNotEmpty) {
            if (parsedGroupCount > 0) { for (var ev in unparsed) { if (ev.eventId != null) { final ok = await _safeDeleteEvent(ev.eventId!); if (ok) { cleaned++; hadDup = true; } } } }
            else if (unparsed.length > 1) { for (int i = 1; i < unparsed.length; i++) { if (unparsed[i].eventId != null) { final ok = await _safeDeleteEvent(unparsed[i].eventId!); if (ok) { cleaned++; hadDup = true; } } } }
          }
          if (hadDup) matchedDatesWithDup++;
        }
      }
      _needsFullSync = false; statusNotifier.value = '清理完成，正在同步最新狀態...'; progressNotifier.value = 1.0; await _syncToGoogle(silent: true, forceFullSync: false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('清理完成：掃描 $scannedDates 天，有重複 $matchedDatesWithDup 天，共刪除 $cleaned 條'), duration: const Duration(seconds: 5)));
    } catch (e) { await _writeDebugLog('強制清理失敗: $e'); if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('清理失敗 $e'))); }
    finally { _isSyncing = false; final ctx = loadingCtx; if (ctx != null && ctx.mounted) Navigator.pop(ctx); }
  }

  Future<void> _purgeRosterProInRange() async {
    if (_isSyncing) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在同步中，請稍候...'))); return; }
    if (_rosterCalendarId == null || _rosterCalendarId!.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('尚未選擇日曆'))); return; }
    DateTimeRange? range = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(DateTime.now().year + 30, 12, 31), helpText: '選擇要清除 [RosterPro] 事件的日期範圍');
    if (range == null) return;
    bool? confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('⚠️ 清除範圍內所有排班事件'), content: Text('這會刪除 ${DateFormat('yyyy-MM-dd').format(range.start)} ~ ${DateFormat('yyyy-MM-dd').format(range.end)} 範圍內所有帶 [RosterPro] 標籤的事件。\n\n確定要執行嗎？'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('確定清除'))]));
    if (confirm != true || _isSyncing || !await _confirmAction()) return;
    _isSyncing = true; final calId = _requireCalendarId();
    final progressNotifier = ValueNotifier<double>(0.0); final statusNotifier = ValueNotifier<String>('正在準備掃描...'); BuildContext? loadingCtx;
    if (mounted) showDialog(context: context, barrierDismissible: false, builder: (ctx) { loadingCtx = ctx; return PopScope(canPop: false, child: AlertDialog(title: const Text('清除進行中'), content: ValueListenableBuilder<double>(valueListenable: progressNotifier, builder: (context, progress, child) => ValueListenableBuilder<String>(valueListenable: statusNotifier, builder: (context, status, child) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [LinearProgressIndicator(value: progress <= 0 ? null : progress), const SizedBox(height: 16), Text(status, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)), if (progress > 0) Padding(padding: const EdgeInsets.only(top: 8), child: Text('${(progress * 100).toStringAsFixed(1)}%', style: const TextStyle(fontSize: 12, color: Colors.grey)))])))); });
    int deletedCount = 0, scannedDates = 0;
    try {
      List<String> dateKeys = []; DateTime cur = DateTime(range.start.year, range.start.month, range.start.day), last = DateTime(range.end.year, range.end.month, range.end.day);
      while (!cur.isAfter(last)) { dateKeys.add(DateFormat('yyyy-MM-dd').format(cur)); cur = cur.add(const Duration(days: 1)); }
      int total = dateKeys.length, current = 0; final Set<String> alreadyDeletedIds = <String>{};
      for (var dateKey in dateKeys) {
        current++; progressNotifier.value = current / total; statusNotifier.value = '正在掃描 ($current/$total)：$dateKey'; scannedDates++;
        DateTime date; try { date = DateTime.parse(dateKey); } catch (_) { continue; }
        final eventsOnDay = await _safeRetrieveEvents(DateTime(date.year, date.month, date.day, 0, 0, 0).subtract(const Duration(hours: 24)), DateTime(date.year, date.month, date.day, 23, 59, 59));
        final Map<String, Event> toDelete = {};
        for (var e in eventsOnDay) {
          final desc = e.description ?? ''; if (!desc.contains('[RosterPro]') || e.eventId == null || alreadyDeletedIds.contains(e.eventId)) continue;
          final m = RegExp(r'\[RosterPro\](\d{4}-\d{2}-\d{2})').firstMatch(desc); if (m != null && m.group(1) != dateKey) continue;
          toDelete[e.eventId!] = e;
        }
        for (var ev in toDelete.values) { final ok = await _safeDeleteEvent(ev.eventId!); if (ok) { alreadyDeletedIds.add(ev.eventId!); deletedCount++; } }
      }
      _googleEventIdMap.clear(); final sp = await SharedPreferences.getInstance(); await sp.setString('googleEventIdMap', jsonEncode(_googleEventIdMap));
      statusNotifier.value = '清除完成，正在重新同步...'; progressNotifier.value = 1.0; await _syncToGoogle(silent: true, forceFullSync: false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('清除完成：掃描 $scannedDates 天，共刪除 $deletedCount 條 [RosterPro] 事件'), duration: const Duration(seconds: 5)));
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('清除失敗 $e'))); }
    finally { _isSyncing = false; final ctx = loadingCtx; if (ctx != null && ctx.mounted) Navigator.pop(ctx); }
  }

  Future<void> _forceFullResync() async {
    if (_isSyncing) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在同步中，請稍候...'))); return; }
    if (_rosterCalendarId == null || _rosterCalendarId!.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('尚未選擇日曆'))); return; }
    if (roster.isEmpty) {
      bool? stillProceed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('⚠️ 排班資料為空'), content: const Text('目前 App 內沒有任何排班資料。\n\n「全清重建」會刪除掃描範圍內所有 [RosterPro] 事件，然後因為沒排班資料可重建，結果就是日曆變空。\n\n確定要執行嗎？'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('仍要執行'))]));
      if (stillProceed != true) return;
    }
    bool? confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('⚠️ 全清重建確認'), content: const Text('這會掃描範圍內所有帶 [RosterPro] 的事件並刪除，然後根據 App 排班重新建立。\n\n掃描範圍：2000年 ~ 2100年\n\n✅ App 排班資料不受影響\n✅ 你其他 Google 行程不會被刪除\n✅ 只會影響選定日曆\n\n確定要執行嗎？'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('確定執行'))]));
    if (confirm != true || _isSyncing || !await _confirmAction()) return;
    _needsFullSync = true; _dirtyDates.clear(); await _syncToGoogle(forceFullSync: true);
  }

  Future<String> _getBackupDir() async {
    try { Directory dir = Directory('/storage/emulated/0/RosterPro_Backups'); if (!await dir.exists()) await dir.create(recursive: true); return dir.path; }
    catch (_) { final appDir = await getApplicationDocumentsDirectory(); Directory dir = Directory('${appDir.path}/RosterPro_Backups'); if (!await dir.exists()) await dir.create(recursive: true); return dir.path; }
  }

  Future<void> restoreFromFile(String path) async {
    try {
      var j = jsonDecode(await File(path).readAsString());
      setState(() {
        if (j['roster'] != null) roster = Map<String, String>.from(j['roster']); if (j['note'] != null) rosterNote = Map<String, String>.from(j['note']);
        if (j['extraType'] != null) rosterExtraType = Map<String, String>.from(j['extraType']);
        if (j['roOt'] != null) rosterOt = Map<String, double>.from((j['roOt'] as Map).map((k, v) => MapEntry(k as String, (v as num).toDouble())));
        if (j['roEx'] != null) rosterExtra = Map<String, double>.from((j['roEx'] as Map).map((k, v) => MapEntry(k as String, (v as num).toDouble())));
        if (j['roExH'] != null) rosterExtraHrs = Map<String, double>.from((j['roExH'] as Map).map((k, v) => MapEntry(k as String, (v as num).toDouble())));
        if (j['defs'] != null) defs = (j['defs'] as Map).map<String, ShiftDef>((k, v) => MapEntry(k as String, ShiftDef.fromJson(Map<String, dynamic>.from(v as Map))));
        if (j['pattern'] != null) pattern = (j['pattern'] as List).map<List<String>>((r) => (r as List).map<String>((e) => e.toString()).toList()).toList();
        if (j['carry'] != null) carry = (j['carry'] as num).toDouble(); if (j['cName'] != null) { customName = j['cName']; nameCtrl.text = customName; }
        if (j['stdWeek'] != null) standardWeeklyHours = (j['stdWeek'] as num).toDouble(); if (j['otRate'] != null) overtimeRate = (j['otRate'] as num).toDouble();
        if (j['extraNewV36'] != null) extraAllowances = (j['extraNewV36'] as List).map((e) => ExtraAllowance.fromJson(Map<String, dynamic>.from(e as Map))).toList();
        if (j['calFont'] != null) calendarFontSize = (j['calFont'] as num).toDouble();
        if (j['savedPatterns'] != null) savedPatterns = (j['savedPatterns'] as List).map((e) => SavedPattern.fromJson(Map<String, dynamic>.from(e as Map))).toList();
        if (j['holidayRegion'] != null) holidayRegion = j['holidayRegion']; if (j['manualHolidays'] != null) manualHolidays = Map<String, String>.from(j['manualHolidays']);
        if (j['rosterCalId'] != null) _rosterCalendarId = j['rosterCalId']; if (j['rosterCalName'] != null) _rosterCalendarName = j['rosterCalName'];
        if (j['rosterAccName'] != null) _rosterAccountName = j['rosterAccName']; if (j['googleEventIdMap'] != null) _googleEventIdMap = Map<String, String>.from(j['googleEventIdMap']);
        if (j['gSync'] != null) googleSyncEnabled = j['gSync']; if (j['gAuto'] != null) autoSync = j['gAuto'];
        if (j['todayBg'] != null) todayBgColor = Color(j['todayBg']); if (j['todayBorder'] != null) todayBorderColor = Color(j['todayBorder']);
        if (j['showLunar'] != null) showLunar = j['showLunar']; if (j['widgetFontSize'] != null) widgetFontSize = (j['widgetFontSize'] as num).toDouble();
        if (j['widgetTextColor'] != null) widgetTextColor = j['widgetTextColor']; if (j['iconIndex'] != null) iconIndex = j['iconIndex'];
        if (j['morningAllow'] != null) morningAllowance = (j['morningAllow'] as num).toDouble(); if (j['nightAllow'] != null) nightAllowance = (j['nightAllow'] as num).toDouble();
        if (j['mealAllow'] != null) mealAllowance = (j['mealAllow'] as num).toDouble(); if (j['nightAllowMultiplier'] != null) nightAllowMultiplier = (j['nightAllowMultiplier'] as num).toDouble();
        if (j['leaveDefs'] != null) leaveDefs = (j['leaveDefs'] as List).map((e) => LeaveDef.fromJson(Map<String, dynamic>.from(e as Map))).toList();
        if (j['leaveRecords'] != null) leaveRecords = Map<String, Map<String, dynamic>>.from((j['leaveRecords'] as Map).map((k, v) => MapEntry(k as String, Map<String, dynamic>.from(v as Map))));
        if (j['rosterLeave'] != null) rosterLeave = Map<String, String>.from(j['rosterLeave']);
      });
      _needsFullSync = false; _dirtyDates.clear(); for (var key in roster.keys) _dirtyDates.add(key);
      await save();
      if (googleSyncEnabled) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('還原成功，正在增量同步...'), duration: Duration(seconds: 3))); await Future.delayed(const Duration(milliseconds: 800)); await _syncToGoogle(forceFullSync: false, silent: false); }
      else { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('還原成功'))); }
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('還原失敗 $e'))); }
  }

  Future<void> restoreLocalFile() async { var res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json']); if (res == null) return; if (!await _confirmAction()) return; await restoreFromFile(res.files.single.path!); }
  Future<void> shareScreenshotDialog() async { exportShareImage(); }
  void _goToPrevMonth() { setState(() => focused = DateTime(focused.year, focused.month - 1, 1)); }
  void _goToNextMonth() { setState(() => focused = DateTime(focused.year, focused.month + 1, 1)); }

  // 以下省略部分輔助 UI 方法（如備份清單、報表匯出等），請保留原有的實作
  // 請將本部分結束後，接上你原本 main.dart 中剩下所有未修改的 UI 方法即可。

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: [calTab(), patternTab(), reportTab(), settingsTab()][tab],
      bottomNavigationBar: NavigationBar(
        height: 55, selectedIndex: tab, onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [NavigationDestination(icon: Icon(Icons.calendar_month), label: '月曆'), NavigationDestination(icon: Icon(Icons.pattern), label: '模式'), NavigationDestination(icon: Icon(Icons.bar_chart), label: '報表'), NavigationDestination(icon: Icon(Icons.settings), label: '設定')]
      ),
    );
  }
}
