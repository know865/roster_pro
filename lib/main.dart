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

void main() {
  tzData.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Hong_Kong'));
  WidgetsFlutterBinding.ensureInitialized();
  HomeWidget.setAppGroupId('group.rosterPro');
  runApp(const RosterApp());
}

class ShiftDef {
  String code;
  String label;
  double hours;
  double ot;
  Color color;
  String start;
  String end;
  bool hasAllowance;
  double allowance;
  bool isAllDay;
  ShiftDef(this.code, this.label, this.hours, this.color, {this.ot = 0, this.start = '07:00', this.end = '15:30', this.hasAllowance = false, this.allowance = 0, this.isAllDay = false});
  Map<String, dynamic> toJson() => {'code': code, 'label': label, 'hours': hours, 'ot': ot, 'color': color.value, 'start': start, 'end': end, 'hasAllowance': hasAllowance, 'allowance': allowance, 'isAllDay': isAllDay};
  factory ShiftDef.fromJson(Map<String, dynamic> j) => ShiftDef(j['code'], j['label'] ?? j['code'], (j['hours'] ?? 8).toDouble(), Color(j['color'] ?? 0xFFFF9800), ot: (j['ot'] ?? 0).toDouble(), start: j['start'] ?? '07:00', end: j['end'] ?? '15:30', hasAllowance: j['hasAllowance'] ?? ((j['allowance'] ?? 0) > 0), allowance: (j['allowance'] ?? 0).toDouble(), isAllDay: j['isAllDay'] ?? false);
  String get detailTime => isAllDay ? '全天 ${hours.toStringAsFixed(1)}h' : '${start}-${end} ${hours.toStringAsFixed(1)}h';
}

class ExtraAllowance {
  String name;
  double amount;
  ExtraAllowance(this.name, this.amount);
  Map<String, dynamic> toJson() => {'name': name, 'amount': amount};
  factory ExtraAllowance.fromJson(Map<String, dynamic> j) => ExtraAllowance(j['name'], (j['amount'] as num).toDouble());
}

class SavedPattern {
  String name;
  List<List<String>> data;
  SavedPattern(this.name, this.data);
  Map<String, dynamic> toJson() => {'name': name, 'data': data};
  factory SavedPattern.fromJson(Map<String, dynamic> j) => SavedPattern(j['name'], (j['data'] as List).map<List<String>>((r) => (r as List).map<String>((e) => e.toString()).toList()).toList());
}

class LunarHelper {
  static final List<int> lunarInfo = [
    0x04bd8, 0x04ae0, 0x0a570, 0x054d5, 0x0d260, 0x0d950, 0x16554, 0x056a0, 0x09ad0, 0x055d2,
    0x04ae0, 0x0a5b6, 0x0a4d0, 0x0d250, 0x1d255, 0x0b540, 0x0d6a0, 0x0ada2, 0x095b0, 0x14977,
    0x04970, 0x0a4b0, 0x0b4b5, 0x06a50, 0x06d40, 0x1ab54, 0x02b60, 0x09570, 0x052f2, 0x04970,
    0x06566, 0x0d4a0, 0x0ea50, 0x06e95, 0x05ad0, 0x02b60, 0x186e3, 0x092e0, 0x1c8d7, 0x0c950,
    0x0d4a0, 0x1d8a6, 0x0b550, 0x056a0, 0x1a5b4, 0x025d0, 0x092d0, 0x0d2b2, 0x0a950, 0x0b557,
    0x06ca0, 0x0b550, 0x15355, 0x04da0, 0x0a5b0, 0x14573, 0x052b0, 0x0a9a8, 0x0e950, 0x06aa0,
    0x0aea6, 0x0ab50, 0x04b60, 0x0aae4, 0x0a570, 0x05260, 0x0f263, 0x0d950, 0x05b57, 0x056a0,
    0x096d0, 0x04dd5, 0x04ad0, 0x0a4d0, 0x0d4d4, 0x0d250, 0x0d558, 0x0b540, 0x0b5a0, 0x195a6,
    0x095b0, 0x049b0, 0x0a974, 0x0a4b0, 0x0b27a, 0x06a50, 0x06d40, 0x0af46, 0x0ab60, 0x09570,
    0x04af5, 0x04970, 0x064b0, 0x074a3, 0x0ea50, 0x06b58, 0x055c0, 0x0ab60, 0x096d5, 0x092e0,
    0x0c960, 0x0d954, 0x0d4a0, 0x0da50, 0x07552, 0x056a0, 0x0abb7, 0x025d0, 0x092d0, 0x0cab5,
    0x0a950, 0x0b4a0, 0x0baa4, 0x0ad50, 0x055d9, 0x04ba0, 0x0a5b0, 0x15176, 0x052b0, 0x0a930,
    0x07954, 0x06aa0, 0x0ad50, 0x05b52, 0x04b60, 0x0a6e6, 0x0a4e0, 0x0d260, 0x0ea65, 0x0d530,
    0x05aa0, 0x076a3, 0x096d0, 0x04afb, 0x04ad0, 0x0a4d0, 0x1d0b6, 0x0d250, 0x0d520, 0x0dd45,
    0x0b5a0, 0x056d0, 0x055b2, 0x049b0, 0x0a577, 0x0a4b0, 0x0aa50, 0x1b255, 0x06d20, 0x0ada0,
  ];
  static final List<String> lunarMonths = ['正','二','三','四','五','六','七','八','九','十','冬','臘'];
  static final List<String> lunarDays = ['初一','初二','初三','初四','初五','初六','初七','初八','初九','初十','十一','十二','十三','十四','十五','十六','十七','十八','十九','二十','廿一','廿二','廿三','廿四','廿五','廿六','廿七','廿八','廿九','三十'];

  static int leapMonth(int y) => lunarInfo[y - 1900] & 0xf;
  static int leapDays(int y) { if (leapMonth(y) == 0) return 0; return ((lunarInfo[y - 1900] & 0x10000) != 0) ? 30 : 29; }
  static int monthDays(int y, int m) => ((lunarInfo[y - 1900] & (0x10000 >> m)) != 0) ? 30 : 29;
  static int lYearDays(int y) {
    int sum = 348;
    for (int i = 0x8000; i > 0x8; i >>= 1) sum += ((lunarInfo[y - 1900] & i) != 0) ? 1 : 0;
    return sum + leapDays(y);
  }
  static List<int> solarToLunar(DateTime date) {
    int offset = date.difference(DateTime(1900, 1, 31)).inDays;
    int year = 1900;
    while (year < 2100 && offset > lYearDays(year)) { offset -= lYearDays(year); year++; }
    int leap = leapMonth(year);
    bool isLeap = false;
    int month = 1;
    while (month < 13 && offset > 0) {
      int days;
      if (leap > 0 && month == leap + 1 && !isLeap) { isLeap = true; days = leapDays(year); } else { days = monthDays(year, month); }
      if (isLeap && month == leap + 1) isLeap = false;
      if (offset < days) break;
      offset -= days;
      if (isLeap && month == leap + 1) isLeap = true;
      month++;
    }
    int day = offset + 1;
    return [month, day, isLeap ? 1 : 0];
  }
  static String getLunarDayText(DateTime date) {
    try {
      if (date.year > 2100) return '超出範圍';
      final r = solarToLunar(date);
      int m = r[0], d = r[1], isLeap = r[2];
      if (d == 1) return '${isLeap == 1 ? '閏' : ''}${lunarMonths[m - 1]}月';
      return lunarDays[d - 1];
    } catch (_) { return ''; }
  }
}

class RosterApp extends StatelessWidget {
  const RosterApp({super.key});
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
  int tab = 0;
  DateTime focused = DateTime.now();
  DateTime selectedDay = DateTime.now();
  Map<String, String> roster = {};
  Map<String, String> rosterNote = {};
  Map<String, String> rosterExtraType = {};
  Map<String, double> rosterOt = {};
  Map<String, double> rosterExtra = {};
  Map<String, double> rosterExtraHrs = {};
  Map<String, ShiftDef> defs = {
    '早': ShiftDef('早', '早更', 8, Colors.orange, start: '07:00', end: '15:30', hasAllowance: true, allowance: 80),
    '中': ShiftDef('中', '中更', 8, Colors.blue, start: '14:00', end: '22:00'),
    '宵': ShiftDef('宵', '宵更', 8, Colors.purple, start: '22:00', end: '06:00', hasAllowance: true, allowance: 60),
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
  bool _needsFullSync = true;

  double widgetFontSize = 55;
  int widgetTextColor = 0xFF333333;
  int widgetBgColor = 0xFFFFFFFF;

  Timer? _autoSyncTimer;
  String appVersion = '載入中...';

  Future<void> _writeDebugLog(String message) async {
    try {
      final dir = await getExternalStorageDirectory();
      if (dir == null) return;
      final f = File('${dir.path}/roster_widget_debug.txt');
      final ts = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
      await f.writeAsString('[$ts]$message\n', mode: FileMode.append);
      if (await f.length() > 200 * 1024) {
        await f.writeAsString('[$ts] (log reset)\n');
      }
    } catch (_) {}
  }

  Future<void> updateWidget() async {
    try {
      String todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
      String tomorrowKey = DateFormat('yyyy-MM-dd').format(DateTime.now().add(const Duration(days: 1)));
      await _writeDebugLog('[Dart] --- updateWidget 開始 ---');
      await _writeDebugLog('[Dart] widgetFontSize=$widgetFontSize, widgetTextColor=0x${widgetTextColor.toRadixString(16)}');
      try { await HomeWidget.saveWidgetData<String>('today_code', roster[todayKey] ?? 'O'); } catch (e) { await _writeDebugLog('[Dart] today_code err: $e'); }
      try { await HomeWidget.saveWidgetData<String>('tomorrow_code', roster[tomorrowKey] ?? 'O'); } catch (_) {}
      try { await HomeWidget.saveWidgetData<String>('note', rosterNote[todayKey] ?? ''); } catch (_) {}
      try { await HomeWidget.saveWidgetData<String>('extraType', rosterExtraType[todayKey] ?? ''); } catch (_) {}
      try { await HomeWidget.saveWidgetData<double>('today_bg', todayBgColor.value.toDouble()); } catch (_) {}
      try { await HomeWidget.saveWidgetData<double>('today_border', todayBorderColor.value.toDouble()); } catch (_) {}
      try { await HomeWidget.saveWidgetData<String>('roster_json', jsonEncode(roster)); } catch (_) {}
      try { await HomeWidget.saveWidgetData<String>('defs_json', jsonEncode(defs.map((k, v) => MapEntry(k, v.toJson())))); } catch (_) {}
      try {
        await HomeWidget.saveWidgetData<double>('widgetFontSize', widgetFontSize);
        await _writeDebugLog('[Dart] 寫入 widgetFontSize=$widgetFontSize OK');
      } catch (e) { await _writeDebugLog('[Dart] 寫入 widgetFontSize 失敗: $e'); }
      try {
        await HomeWidget.saveWidgetData<double>('widgetTextColor', widgetTextColor.toDouble());
        await _writeDebugLog('[Dart] 寫入 widgetTextColor=$widgetTextColor OK');
      } catch (e) { await _writeDebugLog('[Dart] 寫入 widgetTextColor 失敗: $e'); }
      DateTime now = DateTime.now();
      try { await HomeWidget.saveWidgetData<int>('initial_year', now.year); } catch (_) {}
      try { await HomeWidget.saveWidgetData<int>('initial_month', now.month); } catch (_) {}
      
      // 【關鍵修改】使用完整類名，確保 Android 端能準確找到 Widget 類
      await HomeWidget.updateWidget(androidName: 'com.example.roster_pro.RosterWidgetProvider');
      await _writeDebugLog('[Dart] 觸發 Widget 更新 OK');
    } catch (e) {
      await _writeDebugLog('[Dart] updateWidget 整體失敗: $e');
    }
  }

  bool _isSyncing = false;
  String _lastBackupPath = '未備份';
  Color todayBgColor = const Color(0xFFFFF9C4);
  Color todayBorderColor = Colors.orange;
  Color holidayDotColor = Colors.red;

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
    m.addAll(manualHolidays);
    return m;
  }

  bool isHoliday(DateTime d) { var map = getHolidays(d.year, holidayRegion); return map.containsKey(DateFormat('yyyy-MM-dd').format(d)); }
  String holidayName(DateTime d) { var map = getHolidays(d.year, holidayRegion); return map[DateFormat('yyyy-MM-dd').format(d)] ?? ''; }

  @override
  void initState() {
    super.initState();
    nameCtrl.text = customName;
    _loadVersion();
    load().then((_) async {
      await Future.delayed(const Duration(milliseconds: 500));
      bool ok = await handleCalendarPermission(silent: false);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('需要日曆權限才能讀取日曆，請在設定中允許')));
      }
      try { await _realChannel.invokeMethod('requestManageStorage'); } catch (_) {}
      await updateWidget();
      
      // 【修改點 1】重裝後自動觸發一次全量同步，清理卸載前的殘留事件
      if (googleSyncEnabled) {
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            _syncToGoogle(silent: true, forceFullSync: true);
          }
        });
      }
    });
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      setState(() { appVersion = '${info.version}+${info.buildNumber}'; });
    } catch (_) { setState(() { appVersion = '7.1.9+71'; }); }
  }

  Future<void> load() async {
    var sp = await SharedPreferences.getInstance();
    var r = sp.getString('roster'); if (r != null) roster = Map<String, String>.from(jsonDecode(r));
    var rn = sp.getString('note'); if (rn != null) rosterNote = Map<String, String>.from(jsonDecode(rn));
    var rt = sp.getString('extraType'); if (rt != null) rosterExtraType = Map<String, String>.from(jsonDecode(rt));
    var ro = sp.getString('roOt'); if (ro != null) { try { rosterOt = Map<String, double>.from((jsonDecode(ro) as Map).map((k, v) => MapEntry(k as String, (v as num).toDouble()))); } catch (_) {} }
    var re = sp.getString('roEx'); if (re != null) { try { rosterExtra = Map<String, double>.from((jsonDecode(re) as Map).map((k, v) => MapEntry(k as String, (v as num).toDouble()))); } catch (_) {} }
    var reh = sp.getString('roExH'); if (reh != null) { try { rosterExtraHrs = Map<String, double>.from((jsonDecode(reh) as Map).map((k, v) => MapEntry(k as String, (v as num).toDouble()))); } catch (_) {} }
    var d = sp.getString('defs'); if (d != null) { try { var m = Map<String, dynamic>.from(jsonDecode(d)); defs = m.map((k, v) => MapEntry(k, ShiftDef.fromJson(Map<String, dynamic>.from(v)))); } catch (_) {} }
    var p = sp.getString('pattern'); if (p != null) { try { var l = jsonDecode(p) as List; pattern = l.map<List<String>>((row) => (row as List).map<String>((e) => e.toString()).toList()).toList(); } catch (_) {} }
    var ea = sp.getString('extraAllowNewV36'); if (ea != null) { try { extraAllowances = (jsonDecode(ea) as List).map((e) => ExtraAllowance.fromJson(Map<String, dynamic>.from(e))).toList(); } catch (_) {} }
    var spSaved = sp.getString('savedPatternsV40'); if (spSaved != null) { try { savedPatterns = (jsonDecode(spSaved) as List).map((e) => SavedPattern.fromJson(Map<String, dynamic>.from(e))).toList(); } catch (_) {} }
    var evMap = sp.getString('googleEventIdMap'); if (evMap != null) { try { _googleEventIdMap = Map<String, String>.from(jsonDecode(evMap)); } catch (_) {} }
    var mh = sp.getString('manualHolidays'); if (mh != null) { try { manualHolidays = Map<String, String>.from(jsonDecode(mh)); } catch (_) {} }
    var ddList = sp.getStringList('dirtyDates');
    if (ddList != null) _dirtyDates = ddList.toSet();
    _needsFullSync = sp.getBool('needsFullSync') ?? true;
    setState(() {
      carry = sp.getDouble('carry') ?? 0;
      customName = sp.getString('cName') ?? '我的排更-專屬日曆';
      nameCtrl.text = customName;
      standardWeeklyHours = sp.getDouble('stdWeek') ?? 42;
      overtimeRate = sp.getDouble('otRate') ?? 80;
      calendarFontSize = sp.getDouble('calFont') ?? 14;
      googleSyncEnabled = sp.getBool('gSync') ?? false;
      autoSync = sp.getBool('gAuto') ?? false;
      holidayRegion = sp.getString('holidayRegion') ?? '香港';
      _rosterCalendarId = sp.getString('rosterCalId');
      _rosterCalendarName = sp.getString('rosterCalName') ?? '未選';
      _rosterAccountName = sp.getString('rosterAccName') ?? '';
      _lastBackupPath = sp.getString('lastBackupPath') ?? '未備份';
      todayBgColor = Color(sp.getInt('todayBg') ?? 0xFFFFF9C4);
      todayBorderColor = Color(sp.getInt('todayBorder') ?? 0xFFFF9800);
      showLunar = sp.getBool('showLunar') ?? true;
      widgetFontSize = sp.getDouble('widgetFontSize') ?? 55;
      widgetTextColor = sp.getInt('widgetTextColor') ?? 0xFF333333;
    });
    updateWidget();
  }

  Future<void> save() async {
    var sp = await SharedPreferences.getInstance();
    sp.setString('roster', jsonEncode(roster));
    sp.setString('note', jsonEncode(rosterNote));
    sp.setString('extraType', jsonEncode(rosterExtraType));
    sp.setString('roOt', jsonEncode(rosterOt));
    sp.setString('roEx', jsonEncode(rosterExtra));
    sp.setString('roExH', jsonEncode(rosterExtraHrs));
    sp.setString('defs', jsonEncode(defs.map((k, v) => MapEntry(k, v.toJson()))));
    sp.setString('pattern', jsonEncode(pattern));
    sp.setDouble('carry', carry);
    sp.setString('cName', customName);
    sp.setDouble('stdWeek', standardWeeklyHours);
    sp.setDouble('otRate', overtimeRate);
    sp.setString('extraAllowNewV36', jsonEncode(extraAllowances.map((e) => e.toJson()).toList()));
    sp.setDouble('calFont', calendarFontSize);
    sp.setBool('gSync', googleSyncEnabled);
    sp.setBool('gAuto', autoSync);
    sp.setString('savedPatternsV40', jsonEncode(savedPatterns.map((e) => e.toJson()).toList()));
    sp.setString('holidayRegion', holidayRegion);
    sp.setString('googleEventIdMap', jsonEncode(_googleEventIdMap));
    sp.setString('manualHolidays', jsonEncode(manualHolidays));
    await sp.setStringList('dirtyDates', _dirtyDates.toList());
    await sp.setBool('needsFullSync', _needsFullSync);
    if (_rosterCalendarId != null) sp.setString('rosterCalId', _rosterCalendarId!);
    sp.setString('rosterCalName', _rosterCalendarName);
    sp.setString('rosterAccName', _rosterAccountName);
    sp.setString('lastBackupPath', _lastBackupPath);
    sp.setInt('todayBg', todayBgColor.value);
    sp.setInt('todayBorder', todayBorderColor.value);
    sp.setString('roster_json', jsonEncode(roster));
    sp.setString('defs_json', jsonEncode(defs.map((k, v) => MapEntry(k, v.toJson()))));
    sp.setBool('showLunar', showLunar);
    await sp.setDouble('widgetFontSize', widgetFontSize);
    await sp.setInt('widgetTextColor', widgetTextColor);
    await sp.setInt('widgetBgColor', widgetBgColor);
    await updateWidget();
    if (autoSync && googleSyncEnabled && !_isSyncing) {
      _autoSyncTimer?.cancel();
      _autoSyncTimer = Timer(const Duration(seconds: 3), () {
        if (!_isSyncing && autoSync && googleSyncEnabled) { _syncToGoogle(silent: true); }
      });
    }
  }
  int isoWeek(DateTime date) {
  DateTime thursday = date.add(Duration(days: 4 - date.weekday));
  DateTime jan1 = DateTime(thursday.year, 1, 1);
  int days = thursday.difference(jan1).inDays;
  return 1 + (days / 7).floor();
}

void quickJumpMonth({bool forReport = false}) {
  int y = focused.year;
  int m = focused.month;
  showDialog(context: context, builder: (ctx) {
    return StatefulBuilder(builder: (ctx2, setD) {
      return AlertDialog(
        title: Text(forReport ? '選擇報表年月' : '快速查找年月'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            IconButton(icon: const Icon(Icons.remove), onPressed: () => setD(() => y--)),
            Expanded(child: Text('${y}年', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            IconButton(icon: const Icon(Icons.add), onPressed: () => setD(() => y++))
          ]),
          Wrap(spacing: 8, children: List.generate(12, (i) {
            int mon = i + 1;
            return ChoiceChip(label: Text('${mon}月'), selected: mon == m, onSelected: (_) => setD(() => m = mon));
          }))
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx2), child: const Text('取消')),
          FilledButton(onPressed: () { setState(() => focused = DateTime(y, m, 1)); Navigator.pop(ctx2); }, child: const Text('跳轉'))
        ]
      );
    });
  });
}

Future<bool> handleCalendarPermission({bool silent = false}) async {
  try {
    var s1 = await Permission.calendar.request();
    var s2 = await Permission.calendarFullAccess.request();
    var s3 = await Permission.calendarWriteOnly.request();
    if (s1.isGranted || s2.isGranted || s3.isGranted) return true;
    if (!silent && s1.isPermanentlyDenied) {
      await showDialog(context: context, builder: (ctx) => AlertDialog(
        title: const Text('需要日曆權限'),
        content: const Text('新安裝App需允許存取日曆才能讀取，否則顯示空白(0)。請去設定>權限>允許日曆'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () { openAppSettings(); Navigator.pop(ctx); }, child: const Text('去設定'))
        ]
      ));
    }
  } catch (_) {}
  try {
    var devHas = await _calendarPlugin.hasPermissions();
    if (devHas.isSuccess && devHas.data == true) return true;
    var devReq = await _calendarPlugin.requestPermissions();
    if (devReq.isSuccess && devReq.data == true) return true;
  } catch (_) {}
  return false;
}

Future<List<Map<String, dynamic>>> _getRealCalendars() async {
  try {
    var res = await _realChannel.invokeMethod('getCalendars');
    return (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  } catch (e) {
    try {
      var r = await _calendarPlugin.retrieveCalendars();
      return (r.data ?? []).map((c) => {'id': c.id, 'displayName': c.name, 'accountName': c.accountName, 'isGoogle': (c.accountName ?? '').contains('gmail') || (c.accountType ?? '').contains('google')}).toList();
    } catch (_) { return []; }
  }
}

Future<String?> _pickGoogleCalendarDialog() async {
  bool ok = await handleCalendarPermission(silent: false);
  if (!ok) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未取得日曆權限，無法讀取日曆'))); return null; }
  var cals = await _getRealCalendars();
  if (cals.isEmpty) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未讀取到任何日曆，請檢查權限或新增Google帳號'))); return null; }
  var googleCals = cals.where((c) => c['isGoogle'] == true).toList();
  var otherCals = cals.where((c) => c['isGoogle'] != true).toList();
  var pickedMap = await showDialog<Map<String, dynamic>>(context: context, builder: (ctx) {
    return AlertDialog(
      title: Text('選擇寫入日曆 (${cals.length})'),
      content: SizedBox(width: 460, height: 560, child: ListView(children: [
        Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.green.withOpacity(0.12), borderRadius: BorderRadius.circular(8)), child: const Text('綠色=Google帳號 灰色=本機日曆', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green))),
        const SizedBox(height: 8),
        Text('Google 日曆 (${googleCals.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
        ...googleCals.map((cal) => Card(color: Colors.green.withOpacity(0.15), child: ListTile(leading: const Icon(Icons.cloud_done, color: Colors.green), title: Text('${cal['displayName']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)), subtitle: Text('帳號: ${cal['accountName']}\nID: ${cal['id']}', style: const TextStyle(fontSize: 9)), onTap: () => Navigator.pop(ctx, cal)))),
        const Divider(),
        Text('其他日曆 (${otherCals.length})'),
        ...otherCals.map((cal) => Card(child: ListTile(leading: const Icon(Icons.phone_android), title: Text('${cal['displayName']}', style: const TextStyle(fontSize: 13)), subtitle: Text('${cal['accountName']}', style: const TextStyle(fontSize: 9)), onTap: () => Navigator.pop(ctx, cal)))),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消'))],
    );
  });
  if (pickedMap != null && pickedMap['id'] != null) {
    _rosterCalendarId = pickedMap['id'].toString();
    _rosterCalendarName = pickedMap['displayName'].toString();
    _rosterAccountName = pickedMap['accountName'].toString();
    var sp = await SharedPreferences.getInstance();
    sp.setString('rosterCalId', _rosterCalendarId!);
    sp.setString('rosterCalName', _rosterCalendarName);
    sp.setString('rosterAccName', _rosterAccountName);
    setState(() {});
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已選 $_rosterCalendarId')));
    return _rosterCalendarId;
  }
  return null;
}

Future<void> _requestGooglePerm() async {
  String? id = await _pickGoogleCalendarDialog();
  if (id == null) return;
  bool? ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
    title: const Text('已選擇真 Google 日曆'),
    content: Text('將寫入：$_rosterCalendarName\nID: $id'),
    actions: [
      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('稍後')),
      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('立即同步'))
    ]
  ));
  if (ok == true) { setState(() => googleSyncEnabled = true); await _syncToGoogle(); save(); }
}

Future<void> _ensureCalendar() async {
  if (_rosterCalendarId != null && _rosterCalendarId!.isNotEmpty) return;
  await _pickGoogleCalendarDialog();
}

void _markDirty(String dateKey) { _dirtyDates.add(dateKey); }

void _markDirtyRange(DateTime start, DateTime end) {
  DateTime cur = DateTime(start.year, start.month, start.day);
  DateTime last = DateTime(end.year, end.month, end.day);
  while (!cur.isAfter(last)) {
    _dirtyDates.add(DateFormat('yyyy-MM-dd').format(cur));
    cur = cur.add(const Duration(days: 1));
  }
}

// ===== 動態掃描範圍（跟隨 roster 實際日期，並兜底至 2000 年，覆蓋所有遠古殘留）=====
DateTime _calcScanStart() {
  int currentYear = DateTime.now().year;
  int minYear = currentYear - 10;
  if (roster.isNotEmpty) {
    for (String k in roster.keys) {
      if (k.length >= 4) {
        int? y = int.tryParse(k.substring(0, 4));
        if (y != null && y - 2 < minYear) minYear = y - 2;
      }
    }
  }
  // 【關鍵】兜底至 2000 年，確保掃到任何遠古殘留
  if (minYear > 2000) minYear = 2000;
  return DateTime(minYear, 1, 1);
}

DateTime _calcScanEnd() {
  int currentYear = DateTime.now().year;
  int maxYear = currentYear + 30;
  if (roster.isNotEmpty) {
    for (String k in roster.keys) {
      if (k.length >= 4) {
        int? y = int.tryParse(k.substring(0, 4));
        if (y != null && y + 2 > maxYear) maxYear = y + 2;
      }
    }
  }
  return DateTime(maxYear, 12, 31);
}

Future<bool> _buildAndInsertEvent(String dateKey, String code, Duration offset) async {
  final def = defs[code];
  if (def == null) return false;
  final date = DateTime.parse(dateKey);
  final note = rosterNote[dateKey] ?? '';
  final tag = '[RosterPro]$dateKey';
  final allDayFlag = def.isAllDay || def.code == 'O';

  String desc, title;
  if (allDayFlag) {
    desc = '$tag\n$customName\n班次: ${def.code} ${def.label}\n類型: 全天${note.isNotEmpty ? '\n記事: $note' : ''}';
    title = '${def.code}${note.isNotEmpty ? ' | $note' : ''}';
  } else {
    desc = '$tag\n$customName\n班次: ${def.code} ${def.label}\n時間: ${def.start}-${def.end}${note.isNotEmpty ? '\n記事: $note' : ''}';
    title = '${def.code} ${def.start}-${def.end}${note.isNotEmpty ? ' | $note' : ''}';
  }

  Event ev;
  if (allDayFlag) {
    ev = Event(_rosterCalendarId!, title: title, description: desc,
      start: tz.TZDateTime(tz.local, date.year, date.month, date.day, 0, 0, 0),
      end: tz.TZDateTime(tz.local, date.year, date.month, date.day, 23, 59, 59),
      allDay: true);
  } else {
    final sp1 = def.start.split(':');
    final ep1 = def.end.split(':');
    DateTime sLocal = DateTime(date.year, date.month, date.day, int.parse(sp1[0]), int.parse(sp1[1]));
    DateTime eLocal = DateTime(date.year, date.month, date.day, int.parse(ep1[0]), int.parse(ep1[1]));
    if (!eLocal.isAfter(sLocal)) eLocal = eLocal.add(const Duration(days: 1));
    DateTime sUtc = sLocal.subtract(offset);
    DateTime eUtc = eLocal.subtract(offset);
    ev = Event(_rosterCalendarId!, title: title, description: desc,
      start: tz.TZDateTime.utc(sUtc.year, sUtc.month, sUtc.day, sUtc.hour, sUtc.minute),
      end: tz.TZDateTime.utc(eUtc.year, eUtc.month, eUtc.day, eUtc.hour, eUtc.minute),
      allDay: false);
  }

  final res = await _calendarPlugin.createOrUpdateEvent(ev);
  if (res != null && res.isSuccess && res.data != null) {
    _googleEventIdMap[dateKey] = res.data!;
    return true;
  }
  return false;
}

Future<void> _syncNow() async {
  if (!googleSyncEnabled) return;
  await _syncToGoogle(silent: true);
}

Future<void> _syncToGoogle({bool silent = false, bool forceFullSync = false}) async {
  if (!googleSyncEnabled && !silent) {
    bool? en = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('未開啟同步'),
      content: const Text('是否開啟同步並立即寫入？'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('開啟並同步'))
      ]
    ));
    if (en == true) setState(() => googleSyncEnabled = true); else return;
  }
  if (_isSyncing) return;

  bool needFull = forceFullSync || _needsFullSync;
  if (!needFull && _googleEventIdMap.isEmpty && roster.isNotEmpty) needFull = true;

  if (!needFull && _dirtyDates.isEmpty) {
    if (!silent && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('沒有變更需要同步'), duration: Duration(seconds: 2)));
    }
    return;
  }

  _isSyncing = true;
  _autoSyncTimer?.cancel();
  if (!silent && mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(needFull ? '開始完整同步...' : '開始增量同步...')));
  }

  try {
    if (_rosterCalendarId == null || _rosterCalendarId!.isEmpty) await _ensureCalendar();
    if (_rosterCalendarId == null || _rosterCalendarId!.isEmpty) throw '未選真 Google 日曆';

    final sp = await SharedPreferences.getInstance();
    final offset = DateTime.now().timeZoneOffset;
    int del = 0, add = 0, upd = 0;

    if (needFull) {
      DateTime scanStart = _calcScanStart();
      DateTime scanEnd = _calcScanEnd();

      final trackedIds = Map<String, String>.from(_googleEventIdMap);
      for (var e in trackedIds.entries) {
        try { await _calendarPlugin.deleteEvent(_rosterCalendarId!, e.value); del++; } catch (_) {}
      }
      _googleEventIdMap.clear();
      if (del > 0) await Future.delayed(const Duration(milliseconds: 1500));

      // 【修改點 2】按年分段清理，避免 CursorWindow 溢出導致刪除失敗
      DateTime current = scanStart;
      while (current.isBefore(scanEnd)) {
        DateTime next = DateTime(current.year + 1, 1, 1);
        if (next.isAfter(scanEnd)) next = scanEnd;

        for (int attempt = 0; attempt < 3; attempt++) { // 每年重試3次
          var existingEvents = await _calendarPlugin.retrieveEvents(
            _rosterCalendarId!,
            RetrieveEventsParams(startDate: current, endDate: next),
          );
          bool hasRemaining = false;
          for (var e in existingEvents.data ?? []) {
            final desc = e.description ?? '';
            final id = e.eventId;
            if (id == null || !desc.contains('[RosterPro]')) continue;
            try { await _calendarPlugin.deleteEvent(_rosterCalendarId!, id); del++; hasRemaining = true; } catch (_) {}
          }
          if (!hasRemaining) break;
          await Future.delayed(const Duration(milliseconds: 1000));
        }
        current = next;
      }
      await Future.delayed(const Duration(milliseconds: 500));

      for (var entry in roster.entries) {
        final added = await _buildAndInsertEvent(entry.key, entry.value, offset);
        if (added) add++;
      }

      _needsFullSync = false;
      _dirtyDates.clear();
    } else {
      final datesToSync = List<String>.from(_dirtyDates);
      for (var dateKey in datesToSync) {
        if (_googleEventIdMap.containsKey(dateKey)) {
          try { await _calendarPlugin.deleteEvent(_rosterCalendarId!, _googleEventIdMap[dateKey]!); del++; } catch (_) {}
          _googleEventIdMap.remove(dateKey);
        }

        try {
          final date = DateTime.parse(dateKey);
          var dayEvents = await _calendarPlugin.retrieveEvents(
            _rosterCalendarId!,
            RetrieveEventsParams(
              startDate: date.subtract(const Duration(days: 1)),
              endDate: date.add(const Duration(days: 2)),
            ),
          );
          for (var e in dayEvents.data ?? []) {
            final desc = e.description ?? '';
            final id = e.eventId;
            if (id == null) continue;
            if (!desc.contains('[RosterPro]$dateKey')) continue;
            try { await _calendarPlugin.deleteEvent(_rosterCalendarId!, id); del++; } catch (_) {}
          }
        } catch (_) {}

        if (roster.containsKey(dateKey)) {
          final added = await _buildAndInsertEvent(dateKey, roster[dateKey]!, offset);
          if (added) { add++; upd++; }
        }

        _dirtyDates.remove(dateKey);
      }
    }

    sp.setString('googleEventIdMap', jsonEncode(_googleEventIdMap));
    await sp.setStringList('dirtyDates', _dirtyDates.toList());
    await sp.setBool('needsFullSync', _needsFullSync);
    updateWidget();

    if (!silent && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(needFull ? '完整同步完成：刪$del / 建$add' : '增量同步完成：刪$del / 更新$upd'),
        duration: const Duration(seconds: 3),
      ));
    }
  } catch (e) {
    if (!silent && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('同步失敗 $e')));
  } finally {
    _isSyncing = false;
  }
}

Future<void> _forceFullResync() async {
  bool? confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
    title: const Text('⚠️ 全清重建確認'),
    content: const Text('這會刪除 Google 日曆上「所有」[RosterPro] 事件，並根據 App 現有排班重新建立。\n\n✅ App 排班資料不受影響\n✅ 你其他 Google 行程不會被刪除\n\n確定要執行嗎？'),
    actions: [
      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
      FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('確定執行'))
    ]
  ));
  if (confirm != true) return;
  _needsFullSync = true;
  _dirtyDates.clear();
  await _syncToGoogle(forceFullSync: true);
}

Future<String> _getBackupDir() async {
  try {
    Directory dir = Directory('/storage/emulated/0/RosterPro_Backups');
    if (!await dir.exists()) await dir.create(recursive: true);
    final testFile = File('${dir.path}/.test');
    await testFile.writeAsString('ok');
    await testFile.delete();
    return dir.path;
  } catch (_) {
    final appDir = await getApplicationDocumentsDirectory();
    Directory dir = Directory('${appDir.path}/RosterPro_Backups');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }
}

Future<void> restoreFromFile(String path) async {
  try {
    String c = await File(path).readAsString();
    var j = jsonDecode(c);
    setState(() {
      if (j['roster'] != null) roster = Map<String, String>.from(j['roster']);
      if (j['note'] != null) rosterNote = Map<String, String>.from(j['note']);
      if (j['extraType'] != null) rosterExtraType = Map<String, String>.from(j['extraType']);
      if (j['roOt'] != null) rosterOt = Map<String, double>.from((j['roOt'] as Map).map((k, v) => MapEntry(k as String, (v as num).toDouble())));
      if (j['roEx'] != null) rosterExtra = Map<String, double>.from((j['roEx'] as Map).map((k, v) => MapEntry(k as String, (v as num).toDouble())));
      if (j['roExH'] != null) rosterExtraHrs = Map<String, double>.from((j['roExH'] as Map).map((k, v) => MapEntry(k as String, (v as num).toDouble())));
      if (j['defs'] != null) defs = (j['defs'] as Map).map<String, ShiftDef>((k, v) => MapEntry(k as String, ShiftDef.fromJson(Map<String, dynamic>.from(v as Map))));
      if (j['pattern'] != null) pattern = (j['pattern'] as List).map<List<String>>((r) => (r as List).map<String>((e) => e.toString()).toList()).toList();
      if (j['carry'] != null) carry = (j['carry'] as num).toDouble();
      if (j['cName'] != null) { customName = j['cName']; nameCtrl.text = customName; }
      if (j['stdWeek'] != null) standardWeeklyHours = (j['stdWeek'] as num).toDouble();
      if (j['otRate'] != null) overtimeRate = (j['otRate'] as num).toDouble();
      if (j['extraNewV36'] != null) extraAllowances = (j['extraNewV36'] as List).map((e) => ExtraAllowance.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      if (j['calFont'] != null) calendarFontSize = (j['calFont'] as num).toDouble();
      if (j['savedPatterns'] != null) savedPatterns = (j['savedPatterns'] as List).map((e) => SavedPattern.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      if (j['holidayRegion'] != null) holidayRegion = j['holidayRegion'];
      if (j['manualHolidays'] != null) manualHolidays = Map<String, String>.from(j['manualHolidays']);
      if (j['rosterCalId'] != null) _rosterCalendarId = j['rosterCalId'];
      if (j['rosterCalName'] != null) _rosterCalendarName = j['rosterCalName'];
      if (j['rosterAccName'] != null) _rosterAccountName = j['rosterAccName'];
      if (j['googleEventIdMap'] != null) _googleEventIdMap = Map<String, String>.from(j['googleEventIdMap']);
      if (j['gSync'] != null) googleSyncEnabled = j['gSync'];
      if (j['gAuto'] != null) autoSync = j['gAuto'];
      if (j['todayBg'] != null) todayBgColor = Color(j['todayBg']);
      if (j['todayBorder'] != null) todayBorderColor = Color(j['todayBorder']);
      if (j['showLunar'] != null) showLunar = j['showLunar'];
      if (j['widgetFontSize'] != null) widgetFontSize = (j['widgetFontSize'] as num).toDouble();
      if (j['widgetTextColor'] != null) widgetTextColor = j['widgetTextColor'];
    });
    _needsFullSync = true;
    _dirtyDates.clear();
    await save();

    // 【關鍵】還原後立即觸發強制完整同步，徹底清除舊版殘留
    if (googleSyncEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('還原成功，正在完整同步至 Google 日曆...'),
          duration: Duration(seconds: 3),
        ));
      }
      await Future.delayed(const Duration(milliseconds: 800));
      await _syncToGoogle(forceFullSync: true, silent: false);
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('還原成功')));
    }
  } catch (e) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('還原失敗 $e')));
  }
}

Future<void> restoreLocalFile() async {
  var res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
  if (res == null) return;
  await restoreFromFile(res.files.single.path!);
}

Future<void> showBackupList() async {
  final dirPath = await _getBackupDir();
  final dir = Directory(dirPath);
  if (!await dir.exists()) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('沒有備份'))); return; }
  List<FileSystemEntity> entities = dir.listSync();
  List<File> files = entities.whereType<File>().where((f) => f.path.endsWith('.json')).toList();
  files.sort((a, b) => b.path.compareTo(a.path));
  if (files.isEmpty) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('沒有備份'))); return; }
  Set<String> selectedPaths = <String>{};
  bool multiSelectMode = false;
  await showDialog(context: context, builder: (ctx) {
    return StatefulBuilder(builder: (ctx2, setD) {
      return AlertDialog(
        title: Text(multiSelectMode ? '已選 ${selectedPaths.length} 個' : '備份清單 (${files.length})'),
        content: SizedBox(width: 500, height: 500, child: Column(children: [
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Text('目錄: $dirPath', style: const TextStyle(fontSize: 10))),
          const SizedBox(height: 8),
          Expanded(child: ListView.builder(
            itemCount: files.length,
            itemBuilder: (c, i) {
              final f = files[i];
              final name = f.path.split('/').last;
              final sizeKB = (f.statSync().size / 1024).toStringAsFixed(1);
              final isSelected = selectedPaths.contains(f.path);
              return ListTile(
                dense: true,
                leading: multiSelectMode ? Checkbox(value: isSelected, onChanged: (v) { setD(() { if (v == true) selectedPaths.add(f.path); else selectedPaths.remove(f.path); }); }) : const Icon(Icons.description, size: 20),
                title: Text(name, style: const TextStyle(fontSize: 12)),
                subtitle: Text('${sizeKB} KB', style: const TextStyle(fontSize: 10)),
                onTap: () async {
                  if (multiSelectMode) {
                    setD(() { if (isSelected) selectedPaths.remove(f.path); else selectedPaths.add(f.path); });
                  } else {
                    bool? c = await showDialog<bool>(context: context, builder: (c2) => AlertDialog(
                      title: const Text('確認還原'),
                      content: Text('將用此備份覆蓋目前資料：\n\n$name\n\n確定？'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(c2, false), child: const Text('取消')),
                        FilledButton(onPressed: () => Navigator.pop(c2, true), child: const Text('還原')),
                      ],
                    ));
                    if (c == true && mounted) { Navigator.pop(ctx2); await restoreFromFile(f.path); }
                  }
                },
              );
            },
          )),
        ])),
        actions: [
          if (!multiSelectMode) TextButton(onPressed: () => setD(() => multiSelectMode = true), child: const Text('多選刪除')),
          if (multiSelectMode) TextButton(
            onPressed: () async {
              if (selectedPaths.isEmpty) return;
              bool? c = await showDialog<bool>(context: context, builder: (c2) => AlertDialog(
                title: const Text('確認刪除'),
                content: Text('刪除 ${selectedPaths.length} 個備份？\n\n此操作無法復原。'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c2, false), child: const Text('取消')),
                  FilledButton(onPressed: () => Navigator.pop(c2, true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('刪除')),
                ],
              ));
              if (c == true) {
                int deleted = 0;
                for (var p in selectedPaths) { try { await File(p).delete(); deleted++; } catch (_) {} }
                if (mounted) { Navigator.pop(ctx2); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已刪除 $deleted 個備份'))); }
              }
            },
            child: const Text('刪除選中', style: TextStyle(color: Colors.red)),
          ),
          TextButton(onPressed: () { if (multiSelectMode) { setD(() { multiSelectMode = false; selectedPaths.clear(); }); } else { Navigator.pop(ctx2); } }, child: Text(multiSelectMode ? '取消多選' : '關閉')),
        ],
      );
    });
  });
}
  Future<void> showWidgetDebugLog() async {
  await _writeDebugLog('[Dart] === 手動觸發調試日誌 ===');
  await _writeDebugLog('[Dart] widgetFontSize=$widgetFontSize');
  await _writeDebugLog('[Dart] widgetTextColor=0x${widgetTextColor.toRadixString(16)}');

  String content = '';
  String usedPath = '';
  try {
    final dir = await getExternalStorageDirectory();
    if (dir != null) {
      final f = File('${dir.path}/roster_widget_debug.txt');
      if (await f.exists()) { content = await f.readAsString(); usedPath = f.path; }
    }
  } catch (_) {}
  if (content.isEmpty) {
    try {
      final dl = Directory('/storage/emulated/0/Download');
      final f = File('${dl.path}/roster_widget_debug.txt');
      if (await f.exists()) { content = await f.readAsString(); usedPath = f.path; }
    } catch (_) {}
  }
  if (content.isEmpty) {
    if (mounted) {
      final dir = await getExternalStorageDirectory();
      await showDialog(context: context, builder: (ctx) => AlertDialog(
        title: const Text('小工具調試日誌'),
        content: Text('尚未產生除錯日誌。\n\n檢查以下路徑：\n${dir?.path ?? '未知'}/roster_widget_debug.txt\n\n或點「立即備份」後再查看。', style: const TextStyle(fontSize: 12)),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('關閉'))],
      ));
    }
    return;
  }
  if (!mounted) return;
  await showDialog(context: context, builder: (ctx) => AlertDialog(
    title: const Text('小工具調試日誌'),
    content: SizedBox(width: 500, height: 500, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(6)), child: Text('路徑: $usedPath', style: const TextStyle(fontSize: 9))),
      const SizedBox(height: 8),
      Expanded(child: SingleChildScrollView(child: SelectableText(content, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')))),
    ])),
    actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('關閉'))],
  ));
}

Future<void> backupAnywhere() async {
  try {
    final dirPath = await _getBackupDir();
    String fileName = 'roster_pro_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.json';
    var backup = {
      'version': appVersion, 'exportTime': DateTime.now().toIso8601String(),
      'roster': roster, 'note': rosterNote, 'extraType': rosterExtraType,
      'roOt': rosterOt, 'roEx': rosterExtra, 'roExH': rosterExtraHrs,
      'defs': defs.map((k, v) => MapEntry(k, v.toJson())),
      'pattern': pattern, 'carry': carry, 'cName': customName,
      'stdWeek': standardWeeklyHours, 'otRate': overtimeRate,
      'extraNewV36': extraAllowances.map((e) => e.toJson()).toList(),
      'calFont': calendarFontSize,
      'savedPatterns': savedPatterns.map((e) => e.toJson()).toList(),
      'holidayRegion': holidayRegion, 'manualHolidays': manualHolidays,
      'rosterCalId': _rosterCalendarId, 'rosterCalName': _rosterCalendarName,
      'rosterAccName': _rosterAccountName, 'googleEventIdMap': _googleEventIdMap,
      'gSync': googleSyncEnabled, 'gAuto': autoSync,
      'todayBg': todayBgColor.value, 'todayBorder': todayBorderColor.value,
      'showLunar': showLunar, 'widgetFontSize': widgetFontSize,
      'widgetTextColor': widgetTextColor,
    };
    var f = File('$dirPath/$fileName');
    await f.writeAsString(jsonEncode(backup));
    setState(() => _lastBackupPath = '$dirPath/$fileName');
    await save();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已備份: $fileName'), duration: const Duration(seconds: 3)));
  } catch (e) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('備份失敗 $e')));
  }
}

Future<void> clearRosterByRange() async {
  DateTimeRange? range = await showDateRangePicker(context: context, firstDate: DateTime(2023), lastDate: DateTime(DateTime.now().year + 30, 12, 31), helpText: '選擇要清除的排更範圍');
  if (range == null) return;
  int count = 0;
  for (DateTime d = range.start; !d.isAfter(range.end); d = d.add(const Duration(days: 1))) {
    String k = DateFormat('yyyy-MM-dd').format(d);
    _markDirty(k);
    if (roster.containsKey(k)) {
      count++;
      roster.remove(k); rosterOt.remove(k); rosterExtra.remove(k); rosterExtraHrs.remove(k); rosterExtraType.remove(k);
      if (_googleEventIdMap.containsKey(k) && _rosterCalendarId != null) {
        try { await _calendarPlugin.deleteEvent(_rosterCalendarId!, _googleEventIdMap[k]); } catch (_) {}
        _googleEventIdMap.remove(k);
      }
    }
  }
  await save();
  setState(() {});
  await _syncNow();
  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已清除 $count 天排更')));
}

Future<void> shareScreenshotDialog() async { exportShareImage(); }

Future<void> exportShareImage() async {
  try {
    RenderRepaintBoundary? b = calKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    ui.Image? calImg;
    if (b != null) { calImg = await b.toImage(pixelRatio: 3); }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    double width = 1080;
    double y = 0;
    final paintWhite = Paint()..color = Colors.white;
    double calHeight = calImg != null ? width * calImg.height / calImg.width : 0;
    Set<String> usedCodes = {};
    int dim = DateTime(focused.year, focused.month + 1, 0).day;
    for (int i = 1; i <= dim; i++) {
      String k = DateFormat('yyyy-MM-dd').format(DateTime(focused.year, focused.month, i));
      if (roster[k] != null) usedCodes.add(roster[k]!);
    }
    List<ShiftDef> legendDefs = defs.entries.where((e) => usedCodes.contains(e.key)).map((e) => e.value).toList();
    double legendHeight = legendDefs.length * 44 + 80;
    double totalHeight = calHeight + legendHeight + 40;
    canvas.drawRect(Rect.fromLTWH(0, 0, width, totalHeight), paintWhite);
    if (calImg != null) {
      canvas.drawImageRect(calImg, Rect.fromLTWH(0, 0, calImg.width.toDouble(), calImg.height.toDouble()), Rect.fromLTWH(0, 0, width, calHeight), Paint());
      y = calHeight + 16;
    }
    TextPainter tp = TextPainter(textDirection: ui.TextDirection.ltr);
    tp.text = TextSpan(text: '班次詳細時間圖例 (本月使用)：', style: TextStyle(color: Colors.black, fontSize: 32, fontWeight: FontWeight.bold));
    tp.layout(maxWidth: width);
    tp.paint(canvas, Offset(24, y));
    y += 54;
    for (var v in legendDefs) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(24, y, 32, 32), const Radius.circular(8)), Paint()..color = v.color);
      tp.text = TextSpan(text: ' ${v.code} ${v.label} ${v.isAllDay ? '全天' : '${v.start}-${v.end}'} ${v.hours.toStringAsFixed(1)}h${v.hasAllowance ? ' 津貼\$${v.allowance}' : ''}', style: const TextStyle(color: Colors.black87, fontSize: 28, fontWeight: FontWeight.w600));
      tp.layout(maxWidth: width - 80);
      tp.paint(canvas, Offset(64, y));
      y += 46;
    }
    final pic = recorder.endRecording();
    final img0 = await pic.toImage(width.toInt(), (y + 20).toInt());
    final byte = await img0.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes = byte!.buffer.asUint8List();
    Uint8List jpgBytes;
    try {
      final decoded = img.decodeImage(pngBytes);
      if (decoded != null) jpgBytes = Uint8List.fromList(img.encodeJpg(decoded, quality: 90));
      else jpgBytes = pngBytes;
    } catch (_) { jpgBytes = pngBytes; }
    Directory dcimDir = Directory('/storage/emulated/0/DCIM/Screenshots');
    if (!await dcimDir.exists()) await dcimDir.create(recursive: true);
    String path = '${dcimDir.path}/Roster_${focused.year}${focused.month.toString().padLeft(2, '0')}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.jpg';
    File f = File(path);
    await f.writeAsBytes(jpgBytes);
    try { await _realChannel.invokeMethod('scanImage', {'path': path}); } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('截圖已保存到相冊')));
      await Share.shareXFiles([XFile(path)], text: '${focused.year}年${focused.month}月 $customName');
    }
  } catch (e) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('截圖失敗 $e')));
  }
}

Future<void> exportReport() async {
  try {
    StringBuffer sb = StringBuffer();
    if (!isYearReport) {
      int dim = DateTime(focused.year, focused.month + 1, 0).day;
      double hrs = 0, ot = 0, allow = 0;
      SplayTreeMap<String, int> shiftCount = SplayTreeMap();
      SplayTreeMap<String, double> extraByType = SplayTreeMap();
      Map<int, double> weeklyHours = {};
      for (int i = 1; i <= dim; i++) {
        DateTime dt = DateTime(focused.year, focused.month, i);
        String k = DateFormat('yyyy-MM-dd').format(dt);
        String? c = roster[k];
        if (c == null) continue;
        var d = defs[c];
        if (d != null) {
          hrs += d.hours;
          shiftCount[c] = (shiftCount[c] ?? 0) + 1;
          if (d.hasAllowance) allow += d.allowance;
          int w = isoWeek(dt);
          weeklyHours[w] = (weeklyHours[w] ?? 0) + d.hours;
        }
        ot += (rosterOt[k] ?? d?.ot ?? 0);
        allow += (rosterExtra[k] ?? 0);
        if (rosterExtraType.containsKey(k) && rosterExtra.containsKey(k)) {
          extraByType[rosterExtraType[k]!] = (extraByType[rosterExtraType[k]!] ?? 0) + rosterExtra[k]!;
        }
        hrs += (rosterExtraHrs[k] ?? 0);
      }
      sb.writeln('${focused.year}年${focused.month}月 報表');
      sb.writeln('班次統計:');
      shiftCount.forEach((k, v) => sb.writeln('$k, $v次'));
      if (extraByType.isNotEmpty) { sb.writeln('津貼類別:'); extraByType.forEach((t, a) => sb.writeln('$t, \$$a')); }
      sb.writeln('總工時, $hrs');
      sb.writeln('OT, $ot');
      sb.writeln('津貼, ${allow + ot * overtimeRate}');
      sb.writeln('');
      sb.writeln('每週工時統計:');
      sb.writeln('週次, 工時, 標準, 差額');
      for (var e in weeklyHours.entries) {
        double diff = e.value - standardWeeklyHours;
        sb.writeln('W${e.key}, ${e.value.toStringAsFixed(1)}h, ${standardWeeklyHours}h, ${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(1)}h');
      }
    } else {
      sb.writeln('${focused.year}年 全年統計');
      for (int mon = 1; mon <= 12; mon++) {
        int dim = DateTime(focused.year, mon + 1, 0).day;
        double hrs = 0;
        for (int d = 1; d <= dim; d++) {
          DateTime dt = DateTime(focused.year, mon, d);
          String k = DateFormat('yyyy-MM-dd').format(dt);
          String? c = roster[k];
          if (c == null) continue;
          var def = defs[c];
          if (def != null) hrs += def.hours;
        }
        sb.writeln('$mon月, ${hrs}h');
      }
    }
    String? dir = await FilePicker.platform.getDirectoryPath(dialogTitle: '選擇匯出資料夾');
    if (dir == null) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已取消'))); return; }
    String fileName = 'report_${isYearReport ? 'year${focused.year}' : '${focused.year}${focused.month.toString().padLeft(2, '0')}'}.csv';
    String path = '$dir/$fileName';
    final bytes = <int>[0xEF, 0xBB, 0xBF, ...utf8.encode(sb.toString())];
    await File(path).writeAsBytes(bytes);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已匯出 $path')));
  } catch (e) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('匯出失敗 $e')));
  }
}

Future<void> showNotesListDialog() async {
  int queryYear = focused.year;
  int queryMonth = focused.month;
  bool yearMode = false;
  await showDialog(context: context, builder: (ctx) {
    return StatefulBuilder(builder: (ctx2, setD) {
      List<MapEntry<String, String>> notes = [];
      if (yearMode) {
        for (int m = 1; m <= 12; m++) {
          int dim = DateTime(queryYear, m + 1, 0).day;
          for (int d = 1; d <= dim; d++) {
            String k = DateFormat('yyyy-MM-dd').format(DateTime(queryYear, m, d));
            if (rosterNote.containsKey(k) && rosterNote[k]!.isNotEmpty) notes.add(MapEntry(k, rosterNote[k]!));
          }
        }
      } else {
        for (int i = 1; i <= 31; i++) {
          try {
            DateTime dt = DateTime(queryYear, queryMonth, i);
            if (dt.month != queryMonth) break;
            String k = DateFormat('yyyy-MM-dd').format(dt);
            if (rosterNote.containsKey(k) && rosterNote[k]!.isNotEmpty) notes.add(MapEntry(k, rosterNote[k]!));
          } catch (_) {}
        }
      }
      notes.sort((a, b) => a.key.compareTo(b.key));
      return AlertDialog(
        title: Text(yearMode ? '$queryYear年 全年記事清單' : '$queryYear年$queryMonth月 記事清單'),
        content: SizedBox(width: 500, height: 500, child: Column(children: [
          Row(children: [
            Expanded(child: SegmentedButton<bool>(
              segments: const [ButtonSegment(value: false, label: Text('指定月')), ButtonSegment(value: true, label: Text('全年'))],
              selected: {yearMode},
              onSelectionChanged: (s) => setD(() => yearMode = s.first),
            )),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            IconButton(icon: const Icon(Icons.chevron_left), onPressed: () { setD(() { if (yearMode) { queryYear--; } else { queryMonth--; if (queryMonth < 1) { queryMonth = 12; queryYear--; } } }); }),
            Expanded(child: Text(yearMode ? '$queryYear年' : '$queryYear年$queryMonth月', textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
            IconButton(icon: const Icon(Icons.chevron_right), onPressed: () { setD(() { if (yearMode) { queryYear++; } else { queryMonth++; if (queryMonth > 12) { queryMonth = 1; queryYear++; } } }); }),
          ]),
          const Divider(),
          Expanded(child: notes.isEmpty ? const Center(child: Text('沒有記事')) : ListView.builder(itemCount: notes.length, itemBuilder: (c, i) {
            return ListTile(
              dense: true,
              title: Text(notes[i].key, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(notes[i].value),
              onTap: () { Navigator.pop(ctx2); setState(() { selectedDay = DateTime.parse(notes[i].key); focused = DateTime(selectedDay.year, selectedDay.month, 1); }); showDetail(selectedDay); },
            );
          })),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx2), child: const Text('關閉')),
          FilledButton(onPressed: () async {
            try {
              StringBuffer sb = StringBuffer();
              sb.writeln('日期,記事');
              for (var n in notes) sb.writeln('${n.key},"${n.value.replaceAll('"', '""')}"');
              String? dir = await FilePicker.platform.getDirectoryPath(dialogTitle: '選擇匯出資料夾');
              if (dir != null) {
                String path = '$dir/notes_${queryYear}${yearMode ? '' : queryMonth.toString().padLeft(2, '0')}.csv';
                final bytes = <int>[0xEF, 0xBB, 0xBF, ...utf8.encode(sb.toString())];
                await File(path).writeAsBytes(bytes);
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已匯出 $path')));
              }
            } catch (_) {}
          }, child: const Text('匯出CSV')),
        ]
      );
    });
  });
}

Future<void> smartSchedule() async {
  if (savedPatterns.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請先建立至少一個已存模式'))); return; }
  int? selectedIdx = await showDialog<int>(context: context, builder: (ctx) {
    return AlertDialog(
      title: const Text('選擇要使用的模式'),
      content: SizedBox(width: 300, child: ListView(shrinkWrap: true, children: [
        ...savedPatterns.asMap().entries.map((en) => ListTile(title: Text(en.value.name), subtitle: Text('${en.value.data.length}行 (${en.value.data.length * 7}天)'), leading: const Icon(Icons.folder), onTap: () => Navigator.pop(ctx, en.key))),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消'))]
    );
  });
  if (selectedIdx == null) return;
  var selectedPattern = savedPatterns[selectedIdx].data;
  int rows = selectedPattern.length;
  int cycleDays = rows * 7;
  int totalDays = 4 * cycleDays;
  DateTime? startDate = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2023), lastDate: DateTime(DateTime.now().year + 30, 12, 31), helpText: '選擇開始日期');
  if (startDate == null) return;
  DateTime endDate = startDate.add(Duration(days: totalDays - 1));
  bool? confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
    title: const Text('智能排班確認'),
    content: Text('模式: ${savedPatterns[selectedIdx].name}\n模式行數: $rows 行\n一個週期: $cycleDays 天 (${rows} 週)\n開始日期: ${DateFormat('yyyy-MM-dd').format(startDate)}\n結束日期: ${DateFormat('yyyy-MM-dd').format(endDate)}\n總共排班: $totalDays 天 (4 個週期)\n\n確定要執行嗎？'),
    actions: [
      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('確認排班')),
    ]
  ));
  if (confirm != true) return;
  List<String> flat = [];
  for (var row in selectedPattern) flat.addAll(row);
  setState(() {
    for (int i = 0; i < totalDays; i++) {
      DateTime d = startDate.add(Duration(days: i));
      String dateKey = DateFormat('yyyy-MM-dd').format(d);
      roster[dateKey] = flat[i % flat.length];
      _markDirty(dateKey);
    }
  });
  await save();
  setState(() => tab = 0);
  await _syncNow();
  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('智能排班完成：$totalDays 天'), duration: const Duration(seconds: 4)));
}

void _goToPrevMonth() { setState(() { focused = DateTime(focused.year, focused.month - 1, 1); }); }
void _goToNextMonth() { setState(() { focused = DateTime(focused.year, focused.month + 1, 1); }); }

Widget calTab() {
  DateTime first = DateTime(focused.year, focused.month, 1);
  DateTime start = first.subtract(Duration(days: first.weekday - 1));
  int daysInMonth = DateTime(focused.year, focused.month + 1, 0).day;
  int neededCells = first.weekday - 1 + daysInMonth;
  int weeks = (neededCells / 7).ceil();
  if (weeks < 5) weeks = 5;
  if (weeks > 6) weeks = 6;
  List<DateTime> days = List.generate(weeks * 7, (i) => start.add(Duration(days: i)));
  String selKey = DateFormat('yyyy-MM-dd').format(selectedDay);
  var selDef = roster[selKey] != null ? defs[roster[selKey]] : null;
  String note = rosterNote[selKey] ?? '無';
  String extraType = rosterExtraType[selKey] ?? '';
  DateTime today = DateTime.now();
  return SafeArea(
    child: Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
        child: Row(children: [
          Flexible(flex: 2, child: InkWell(onTap: () => quickJumpMonth(), child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text('${focused.year}年${focused.month}月', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)))),
            const Icon(Icons.arrow_drop_down)
          ]))),
          const Spacer(),
          IconButton(icon: const Icon(Icons.list_alt), tooltip: '記事查詢', onPressed: showNotesListDialog, visualDensity: VisualDensity.compact),
          IconButton(icon: const Icon(Icons.camera_alt_outlined), tooltip: '整月截圖分享', onPressed: shareScreenshotDialog, visualDensity: VisualDensity.compact),
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: _goToPrevMonth, visualDensity: VisualDensity.compact),
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: _goToNextMonth, visualDensity: VisualDensity.compact),
          FilledButton.tonal(
            onPressed: () { setState(() { focused = DateTime(today.year, today.month, 1); selectedDay = DateTime(today.year, today.month, today.day); }); },
            style: FilledButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 8)),
            child: const Text('今天', style: TextStyle(fontSize: 12)),
          ),
        ]),
      ),
      Expanded(
        child: GestureDetector(
          onHorizontalDragEnd: (details) {
            if (details.primaryVelocity == null) return;
            if (details.primaryVelocity! < -100) _goToNextMonth();
            else if (details.primaryVelocity! > 100) _goToPrevMonth();
          },
          behavior: HitTestBehavior.opaque,
          child: RepaintBoundary(
            key: calKey,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(children: [
                  Container(width: 32, child: const Text('週', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.deepPurple))),
                  Expanded(child: Row(children: ["一", "二", "三", "四", "五", "六", "日"].map((w) => Expanded(child: Text(w, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11)))).toList()))
                ]),
              ),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), padding: EdgeInsets.zero, itemCount: weeks,
                  itemBuilder: (ctx, row) {
                    return Row(children: [
                      Container(width: 32, alignment: Alignment.center, child: Text('W${isoWeek(days[row * 7])}', style: const TextStyle(fontSize: 11, color: Colors.deepPurple, fontWeight: FontWeight.bold))),
                      Expanded(
                        child: GridView.builder(
                          shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), padding: const EdgeInsets.all(2),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, childAspectRatio: 0.55, mainAxisSpacing: 3, crossAxisSpacing: 3),
                          itemCount: 7,
                          itemBuilder: (ctx2, col) {
                            int idx = row * 7 + col;
                            DateTime day = days[idx];
                            bool inM = day.month == focused.month;
                            String k = DateFormat('yyyy-MM-dd').format(day);
                            String? code = roster[k];
                            var def = code != null ? defs[code] : null;
                            bool sel = k == selKey;
                            bool isToday = day.year == today.year && day.month == today.month && day.day == today.day;
                            bool hasNote = rosterNote.containsKey(k) && rosterNote[k]!.isNotEmpty;
                            bool isHol = isHoliday(day);
                            String lunarText = showLunar ? LunarHelper.getLunarDayText(day) : '';
                            Color bg;
                            if (isToday) bg = todayBgColor;
                            else if (!inM) bg = const Color(0xFFF5F5F0);
                            else if (sel) bg = Colors.white;
                            else if (def != null) bg = def.color.withOpacity(0.18);
                            else bg = const Color(0xFFFFF0D0);

                            return GestureDetector(
                              onTap: () { setState(() => selectedDay = day); },
                              onLongPress: () { setState(() => selectedDay = day); showDetail(day); },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: bg, borderRadius: BorderRadius.circular(10),
                                  border: isToday ? Border.all(width: 2.5, color: todayBorderColor) : sel ? Border.all(width: 2, color: Colors.deepPurple) : null
                                ),
                                child: Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                                  FittedBox(fit: BoxFit.scaleDown, child: Text('${day.day}', style: TextStyle(fontWeight: isToday ? FontWeight.w900 : FontWeight.bold, fontSize: calendarFontSize, color: inM ? Colors.black : Colors.grey))),
                                  if (code != null)
                                    FittedBox(fit: BoxFit.scaleDown, child: Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1), decoration: BoxDecoration(color: def?.color ?? Colors.orange, borderRadius: BorderRadius.circular(4)), child: Text(code, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))))
                                  else const SizedBox(height: 14),
                                  if (showLunar && lunarText.isNotEmpty && inM)
                                    FittedBox(fit: BoxFit.scaleDown, child: Text(lunarText, style: TextStyle(fontSize: 9, color: Colors.grey[700])))
                                  else const SizedBox(height: 10),
                                  SizedBox(height: 6, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                    if (isHol) Container(width: 5, height: 5, margin: const EdgeInsets.symmetric(horizontal: 0.5), decoration: BoxDecoration(color: holidayDotColor, shape: BoxShape.circle)),
                                    if (hasNote) Container(width: 5, height: 5, margin: const EdgeInsets.symmetric(horizontal: 0.5), decoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle)),
                                  ])),
                                ])
                              )
                            );
                          }
                        )
                      )
                    ]);
                  }
                )
              )
            ])
          )
        )
      ),
      Container(
        width: double.infinity, padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFE0E0E0)))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('${roster[selKey] ?? '未排班'}${isHoliday(selectedDay) ? ' [${holidayName(selectedDay)}]' : ''} ${extraType.isNotEmpty ? '[$extraType]' : ''}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
            if (selDef != null) Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: selDef.color, borderRadius: BorderRadius.circular(10)), child: Text(selDef.code, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(onPressed: () { showDetail(selectedDay); }, icon: const Icon(Icons.edit, size: 16), label: const Text('編輯', style: TextStyle(fontSize: 12)), style: FilledButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 12))),
          ]),
          const SizedBox(height: 10),
          Container(
            width: double.infinity, padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('1. 班次：${selDef != null ? '(${selDef.code}) ${selDef.label}' : ''} ${isHoliday(selectedDay) ? '[${holidayName(selectedDay)}]' : ''}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('2. 時間：${selDef != null ? (selDef.isAllDay ? '全天' : '${selDef.start}-${selDef.end}') : ''} | 工時：${selDef?.hours ?? 0}h', style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 4),
              Text('3. 班次津貼：${selDef != null && selDef.hasAllowance ? '有 \$${selDef.allowance}' : '無'}', style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 4),
              Text('4. 額外津貼名稱：${extraType.isNotEmpty ? extraType : '無'}  金額：\$${(rosterExtra[selKey] ?? 0).toStringAsFixed(1)}', style: const TextStyle(fontSize: 12, color: Colors.deepPurple, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('5. OT：${(rosterOt[selKey] ?? 0).toStringAsFixed(1)}h | 額外工時：${(rosterExtraHrs[selKey] ?? 0).toStringAsFixed(1)}h', style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 4),
              Text('6. 記事：${note.isEmpty ? '無' : note}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.deepPurple), maxLines: 6, overflow: TextOverflow.ellipsis),
            ])
          )
        ])
      )
    ])
  );
}

void showDetail(DateTime day) {
  String k = DateFormat('yyyy-MM-dd').format(day);
  String cur = roster[k] ?? '';
  var nc = TextEditingController(text: rosterNote[k] ?? '');
  var otc = TextEditingController(text: (rosterOt[k] ?? 0).toString());
  var exCtrl = TextEditingController(text: (rosterExtra[k] ?? 0).toString());
  var exHCtrl = TextEditingController(text: (rosterExtraHrs[k] ?? 0).toString());
  var exTypeCtrl = TextEditingController(text: rosterExtraType[k] ?? '');
  showModalBottomSheet(context: context, isScrollControlled: true, builder: (ctx) {
    return StatefulBuilder(builder: (ctx2, setM) {
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx2).viewInsets.bottom),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${DateFormat('yyyy-MM-dd EEE').format(day)} ${isHoliday(day) ? ' [${holidayName(day)}]' : ''}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Wrap(spacing: 8, children: defs.keys.map((c) => ChoiceChip(label: Text(c), selected: cur == c, onSelected: (_) => setM(() => cur = c))).toList()),
            Padding(padding: const EdgeInsets.only(top: 6), child: TextField(controller: nc, minLines: 2, maxLines: 6, keyboardType: TextInputType.multiline, textInputAction: TextInputAction.newline, decoration: const InputDecoration(labelText: '記事 (可換行多行)', alignLabelWithHint: true, isDense: true, border: OutlineInputBorder()))),
            Row(children: [
              Expanded(child: SizedBox(height: 56, child: TextField(controller: otc, decoration: const InputDecoration(labelText: 'OT時數', isDense: true, border: OutlineInputBorder()), keyboardType: TextInputType.number))),
              const SizedBox(width: 8),
              Expanded(child: SizedBox(height: 56, child: TextField(controller: exHCtrl, decoration: const InputDecoration(labelText: '額外工時', isDense: true, border: OutlineInputBorder()), keyboardType: TextInputType.number))),
            ]),
            Row(children: [
              Expanded(child: SizedBox(height: 56, child: TextField(controller: exTypeCtrl, decoration: const InputDecoration(labelText: '額外津貼名稱', isDense: true, border: OutlineInputBorder())))),
              const SizedBox(width: 8),
              Expanded(child: SizedBox(height: 56, child: TextField(controller: exCtrl, decoration: const InputDecoration(labelText: '額外津貼金額', isDense: true, border: OutlineInputBorder()), keyboardType: TextInputType.number))),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () async {
                final eventId = _googleEventIdMap[k];
                final calId = _rosterCalendarId;
                Navigator.pop(ctx2);
                setState(() { roster.remove(k); rosterOt.remove(k); rosterExtra.remove(k); rosterExtraHrs.remove(k); rosterExtraType.remove(k); });
                if (eventId != null && calId != null) {
                  try { await _calendarPlugin.deleteEvent(calId, eventId); } catch (_) {}
                  _googleEventIdMap.remove(k);
                }
                _markDirty(k);
                await save();
                await _syncNow();
              }, child: const Text('清除班次(保留記事)', style: TextStyle(color: Colors.orange)))),
              const SizedBox(width: 8),
              Expanded(child: FilledButton(onPressed: () async {
                final otVal = double.tryParse(otc.text);
                final exVal = double.tryParse(exCtrl.text);
                final exHVal = double.tryParse(exHCtrl.text);
                final noteText = nc.text;
                final exTypeText = exTypeCtrl.text.trim();
                final curCode = cur;
                Navigator.pop(ctx2);
                setState(() {
                  if (curCode.isNotEmpty) roster[k] = curCode;
                  if (noteText.isNotEmpty) rosterNote[k] = noteText; else rosterNote.remove(k);
                  if (exTypeText.isNotEmpty) rosterExtraType[k] = exTypeText; else rosterExtraType.remove(k);
                  if (otVal != null) rosterOt[k] = otVal;
                  if (exVal != null && exVal != 0) rosterExtra[k] = exVal; else if (exVal == 0) rosterExtra.remove(k);
                  if (exHVal != null && exHVal != 0) rosterExtraHrs[k] = exHVal; else rosterExtraHrs.remove(k);
                });
                _markDirty(k);
                await save();
                await _syncNow();
              }, child: const Text('儲存'))),
            ]),
          ])
        )
      );
    });
  });
}
    Future<TimeOfDay?> _pickWheelTime(BuildContext ctx, TimeOfDay init) async {
    return await showTimePicker(context: ctx, initialTime: init, builder: (ctx, child) {
      return MediaQuery(data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true), child: child!);
    });
  }

  void editShiftDialog({ShiftDef? oldDef}) {
    var codeCtrl = TextEditingController(text: oldDef?.code ?? '');
    var labelCtrl = TextEditingController(text: oldDef?.label ?? '');
    var hoursCtrl = TextEditingController(text: oldDef?.hours.toString() ?? '8');
    var otCtrl = TextEditingController(text: oldDef?.ot.toString() ?? '0');
    var startCtrl = TextEditingController(text: oldDef?.start ?? '07:00');
    var endCtrl = TextEditingController(text: oldDef?.end ?? '15:30');
    var allowCtrl = TextEditingController(text: oldDef?.allowance.toString() ?? '0');
    bool hasAllow = oldDef?.hasAllowance ?? false;
    bool isAllDay = oldDef?.isAllDay ?? false;
    Color picked = oldDef?.color ?? Colors.orange;
    String oldKey = oldDef?.code ?? '';
    List<Color> palette = [Colors.orange, Colors.blue, Colors.purple, Colors.green, Colors.red, Colors.teal, Colors.brown, Colors.pink, Colors.indigo, Colors.amber, Colors.cyan, Colors.lime, Colors.deepOrange, Colors.lightBlue, Colors.deepPurple, Colors.blueGrey];
    showDialog(context: context, builder: (ctx) {
      return StatefulBuilder(builder: (ctx2, setS) {
        void calcHours() {
          if (isAllDay) return;
          try {
            var s = DateFormat('HH:mm').parse(startCtrl.text);
            var e = DateFormat('HH:mm').parse(endCtrl.text);
            var diff = e.difference(s).inMinutes / 60.0;
            if (diff < 0) diff += 24;
            setS(() => hoursCtrl.text = diff.toStringAsFixed(1));
          } catch (_) {}
        }
        return AlertDialog(
          title: Text(oldDef == null ? '新增班次' : '編輯 ${oldDef.code}'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(controller: codeCtrl, decoration: const InputDecoration(labelText: '代號')),
            TextField(controller: labelCtrl, decoration: const InputDecoration(labelText: '名稱')),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: InkWell(onTap: () async {
                if (isAllDay) return;
                TimeOfDay? t = await _pickWheelTime(ctx2, TimeOfDay(hour: int.parse(startCtrl.text.split(':')[0]), minute: int.parse(startCtrl.text.split(':')[1])));
                if (t != null) { setS(() => startCtrl.text = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}'); calcHours(); }
              }, child: InputDecorator(decoration: const InputDecoration(labelText: '開始 HH:mm', border: OutlineInputBorder()), child: Text(startCtrl.text)))),
              const SizedBox(width: 8),
              Expanded(child: InkWell(onTap: () async {
                if (isAllDay) return;
                TimeOfDay? t = await _pickWheelTime(ctx2, TimeOfDay(hour: int.parse(endCtrl.text.split(':')[0]), minute: int.parse(endCtrl.text.split(':')[1])));
                if (t != null) { setS(() => endCtrl.text = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}'); calcHours(); }
              }, child: InputDecorator(decoration: const InputDecoration(labelText: '結束 HH:mm', border: OutlineInputBorder()), child: Text(endCtrl.text)))),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Checkbox(value: isAllDay, onChanged: (v) { setS(() { isAllDay = v ?? false; if (isAllDay) { startCtrl.text = '00:00'; endCtrl.text = '00:00'; } else { calcHours(); } }); }),
              const Text('全天', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              const Expanded(child: Text('核實全天後時間變00:00，工時可任意輸入', style: TextStyle(fontSize: 10, color: Colors.grey))),
            ]),
            Row(children: [
              Expanded(child: SizedBox(height: 78, child: TextField(controller: hoursCtrl, decoration: InputDecoration(labelText: '工時', border: const OutlineInputBorder(), helperText: isAllDay ? '全天可任意輸入' : ' ', helperStyle: const TextStyle(fontSize: 10)), keyboardType: TextInputType.number))),
              const SizedBox(width: 8),
              Expanded(child: SizedBox(height: 78, child: TextField(controller: otCtrl, decoration: const InputDecoration(labelText: 'OT', border: OutlineInputBorder(), helperText: ' ', helperStyle: TextStyle(fontSize: 10)), keyboardType: TextInputType.number))),
            ]),
            const SizedBox(height: 12),
            Row(children: [Checkbox(value: hasAllow, onChanged: (v) => setS(() => hasAllow = v ?? false)), const Text('有津貼核實', style: TextStyle(fontWeight: FontWeight.bold))]),
            if (hasAllow) TextField(controller: allowCtrl, decoration: const InputDecoration(labelText: '津貼金額', prefixText: '\$ ', border: OutlineInputBorder()), keyboardType: TextInputType.number),
            const SizedBox(height: 12),
            const Text('自定班次顏色', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: palette.map((c) => GestureDetector(onTap: () => setS(() => picked = c), child: Container(width: 36, height: 36, decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: picked == c ? Border.all(width: 3, color: Colors.black) : null), child: picked == c ? const Icon(Icons.check, color: Colors.white, size: 18) : null))).toList()),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx2), child: const Text('取消')),
            FilledButton(onPressed: () async {
              String newCode = codeCtrl.text.trim();
              if (newCode.isEmpty) return;
              double hrs = double.tryParse(hoursCtrl.text) ?? 8;
              double allowVal = double.tryParse(allowCtrl.text) ?? 0;
              Set<String> affectedDates = <String>{};
              Navigator.pop(ctx2);
              setState(() {
                if (oldKey.isNotEmpty && oldKey != newCode) {
                  defs.remove(oldKey);
                  roster.forEach((k, v) { if (v == oldKey) { roster[k] = newCode; affectedDates.add(k); } });
                  for (int i = 0; i < pattern.length; i++) {
                    for (int j = 0; j < pattern[i].length; j++) {
                      if (pattern[i][j] == oldKey) pattern[i][j] = newCode;
                    }
                  }
                }
                defs[newCode] = ShiftDef(newCode, labelCtrl.text.isEmpty ? newCode : labelCtrl.text, hrs, picked, ot: double.tryParse(otCtrl.text) ?? 0, start: startCtrl.text, end: endCtrl.text, hasAllowance: hasAllow, allowance: hasAllow ? allowVal : 0, isAllDay: isAllDay);
                for (var entry in roster.entries) {
                  if (entry.value == newCode) affectedDates.add(entry.key);
                }
              });
              affectedDates.forEach(_markDirty);
              await save();
              await _syncNow();
            }, child: const Text('儲存'))
          ]
        );
      });
    });
  }

  Future<void> pickRangeAndApply() async {
    List<List<String>> chosenPattern = pattern;
    if (savedPatterns.isNotEmpty) {
      int? selected = await showDialog<int>(context: context, builder: (ctx) {
        return AlertDialog(
          title: const Text('選擇排更模式'),
          content: SizedBox(width: 300, child: ListView(shrinkWrap: true, children: [
            ListTile(title: const Text('當前版面'), subtitle: Text('${pattern.length}行'), leading: const Icon(Icons.edit), onTap: () => Navigator.pop(ctx, -1)),
            const Divider(),
            ...savedPatterns.asMap().entries.map((en) => ListTile(title: Text(en.value.name), subtitle: Text('${en.value.data.length}行'), leading: const Icon(Icons.folder), onTap: () => Navigator.pop(ctx, en.key))),
          ])),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消'))]
        );
      });
      if (selected == null) return;
      if (selected == -1) chosenPattern = pattern; else chosenPattern = savedPatterns[selected].data.map((r) => List<String>.from(r)).toList();
    }
    DateTimeRange? p = await showDateRangePicker(context: context, firstDate: DateTime(2023), lastDate: DateTime(DateTime.now().year + 30, 12, 31));
    if (p == null) return;
    var flat = chosenPattern.expand((e) => e).toList();
    setState(() {
      int i = 0;
      for (DateTime d = p.start; !d.isAfter(p.end); d = d.add(const Duration(days: 1))) {
        String dateKey = DateFormat('yyyy-MM-dd').format(d);
        roster[dateKey] = flat[i % flat.length];
        _markDirty(dateKey);
        i++;
      }
    });
    await save();
    setState(() => tab = 0);
    await _syncNow();
  }

  Widget patternTab() {
    return SafeArea(child: Column(children: [
      const Padding(padding: EdgeInsets.only(top: 12), child: Center(child: Text('排更模式', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)))),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            FilledButton.tonalIcon(icon: const Icon(Icons.playlist_add), label: const Text('自定行數'), onPressed: () {
              var c = TextEditingController(text: '3');
              showDialog(context: context, builder: (ctx) => AlertDialog(
                title: const Text('自定行數'),
                content: SizedBox(height: 56, child: TextField(controller: c, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '行數', isDense: true, border: OutlineInputBorder()))),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                  FilledButton(onPressed: () { int n = int.tryParse(c.text) ?? 1; setState(() => pattern.addAll(List.generate(n, (_) => List.filled(7, 'O')))); save(); Navigator.pop(ctx); }, child: const Text('確定'))
                ]
              ));
            }),
            const SizedBox(width: 8),
            FilledButton(onPressed: () async { await pickRangeAndApply(); }, child: const Text('自動排班')),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(icon: const Icon(Icons.auto_awesome), label: const Text('智能排班'), onPressed: smartSchedule, style: FilledButton.styleFrom(backgroundColor: Colors.amber.shade200)),
          ]),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            FilledButton.tonalIcon(icon: const Icon(Icons.folder), label: Text('已存模式${savedPatterns.isEmpty ? '' : '(${savedPatterns.length})'}'), onPressed: () {
              if (savedPatterns.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未有已存模式'))); return; }
              showModalBottomSheet(context: context, builder: (ctx) => SafeArea(child: ListView(children: [
                const ListTile(title: Text('已存排班模式', style: TextStyle(fontWeight: FontWeight.bold))),
                ...savedPatterns.asMap().entries.map((en) => ListTile(
                  title: Text(en.value.name),
                  subtitle: Text('${en.value.data.length}行 (${en.value.data.length * 7}天)'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(icon: const Icon(Icons.upload), tooltip: '載入', onPressed: () { setState(() { pattern = en.value.data.map((r) => List<String>.from(r)).toList(); editingPatternName = en.value.name; editingPatternIndex = en.key; }); save(); Navigator.pop(ctx); }),
                    IconButton(icon: const Icon(Icons.edit), tooltip: '改名', onPressed: () {
                      var ctrl = TextEditingController(text: en.value.name);
                      showDialog(context: context, builder: (ctx2) => AlertDialog(
                        title: const Text('改排班名稱'),
                        content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: '自定義名稱')),
                        actions: [FilledButton(onPressed: () { String nn = ctrl.text.trim(); if (nn.isNotEmpty) { setState(() => savedPatterns[en.key] = SavedPattern(nn, en.value.data)); save(); Navigator.pop(ctx2); Navigator.pop(ctx); } }, child: const Text('保存'))]
                      ));
                    }),
                    IconButton(icon: const Icon(Icons.delete), onPressed: () { setState(() => savedPatterns.removeAt(en.key)); save(); Navigator.pop(ctx); }),
                  ])
                )),
              ])));
            }),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(icon: const Icon(Icons.save_as), label: const Text('另存為新模式'), onPressed: () {
              var ctrl = TextEditingController(text: '模式_${DateFormat('MMdd_HHmm').format(DateTime.now())}');
              showDialog(context: context, builder: (ctx) => AlertDialog(
                title: const Text('另存排更模式 自定義名稱'),
                content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: '模式名稱', border: OutlineInputBorder())),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                  FilledButton(onPressed: () {
                    String n = ctrl.text.trim();
                    if (n.isEmpty) return;
                    if (savedPatterns.any((e) => e.name == n)) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('名稱 $n 已存在'))); return; }
                    setState(() {
                      savedPatterns.add(SavedPattern(n, pattern.map((r) => List<String>.from(r)).toList()));
                      pattern = _defaultPattern.map((r) => List<String>.from(r)).toList();
                      editingPatternName = null; editingPatternIndex = null;
                    });
                    save();
                    Navigator.pop(ctx);
                  }, child: const Text('保存'))
                ]
              ));
            }),
          ]),
          if (editingPatternName != null) Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: Colors.orange.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('正在編輯: $editingPatternName', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                FilledButton.tonal(onPressed: () { if (editingPatternIndex != null) { setState(() => savedPatterns[editingPatternIndex!] = SavedPattern(editingPatternName!, pattern.map((r) => List<String>.from(r)).toList())); save(); } }, child: const Text('更新同名')),
                IconButton(icon: const Icon(Icons.close, size: 16), onPressed: () { setState(() { editingPatternName = null; editingPatternIndex = null; }); })
              ])
            )
          ),
        ])
      ),
      Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: defs.keys.map((k) {
            var d = defs[k]!;
            bool isSelected = selectedPatternCode == k;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () { setState(() => selectedPatternCode = k); },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? d.color : d.color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: isSelected ? Colors.black : d.color, width: isSelected ? 3 : 1.5),
                  ),
                  child: Row(children: [
                    if (isSelected) Padding(padding: const EdgeInsets.only(right: 4), child: Icon(Icons.check_circle, color: Colors.white, size: 16)),
                    Text(k, style: TextStyle(color: isSelected ? Colors.white : d.color, fontWeight: FontWeight.bold, fontSize: 16)),
                  ]),
                ),
              ),
            );
          }).toList()),
        ),
      ),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), child: Text('已選班次: $selectedPatternCode (點下方格子填入)', style: const TextStyle(fontSize: 12, color: Colors.grey))),
      Expanded(child: ListView.builder(itemCount: pattern.length, itemBuilder: (ctx, r) {
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Row(children: [
              SizedBox(width: 28, child: Text('${r + 1}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold))),
              Expanded(child: Row(children: List.generate(7, (c) {
                String code = pattern[r][c];
                var def = defs[code];
                Color chipColor = def?.color ?? Colors.grey;
                return Expanded(child: GestureDetector(
                  onTap: () { setState(() => pattern[r][c] = selectedPatternCode); save(); },
                  onLongPress: () {
                    showModalBottomSheet(context: context, builder: (ctx) => Wrap(children: defs.keys.map((k) => ListTile(
                      leading: CircleAvatar(backgroundColor: defs[k]!.color, child: Text(k, style: const TextStyle(color: Colors.white, fontSize: 12))),
                      title: Text(k),
                      onTap: () { setState(() => pattern[r][c] = k); save(); Navigator.pop(ctx); },
                    )).toList()));
                  },
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    height: 60,
                    decoration: BoxDecoration(color: chipColor.withOpacity(0.3), borderRadius: BorderRadius.circular(8), border: Border.all(color: chipColor, width: 2)),
                    child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: Text(code, style: TextStyle(fontSize: calendarFontSize, fontWeight: FontWeight.bold)))),
                  )
                ));
              }))),
              IconButton(icon: const Icon(Icons.delete), onPressed: () { setState(() => pattern.removeAt(r)); save(); })
            ])
          )
        );
      })),
    ]));
  }

  Widget reportTab() {
    int year = focused.year;
    int month = focused.month;
    double totalYearHrs = 0;
    Map<String, int> yearShiftCount = {};
    Map<int, double> yearMonthlyHrs = {};
    if (isYearReport) {
      for (int m = 1; m <= 12; m++) {
        int dim = DateTime(year, m + 1, 0).day;
        double hrs = 0;
        for (int d = 1; d <= dim; d++) {
          String k = DateFormat('yyyy-MM-dd').format(DateTime(year, m, d));
          String? c = roster[k];
          if (c == null) continue;
          var def = defs[c];
          if (def != null) { hrs += def.hours; totalYearHrs += def.hours; yearShiftCount[c] = (yearShiftCount[c] ?? 0) + 1; }
        }
        yearMonthlyHrs[m] = hrs;
      }
    }
    int dim = DateTime(year, month + 1, 0).day;
    double hrs = 0, ot = 0, allow = 0;
    Map<String, int> shiftCount = {};
    Map<String, double> shiftHours = {};
    Map<int, double> weeklyHours = {};
    Map<String, double> extraByType = {};
    for (int i = 1; i <= dim; i++) {
      DateTime dt = DateTime(year, month, i);
      String k = DateFormat('yyyy-MM-dd').format(dt);
      String? c = roster[k];
      if (c == null) continue;
      var d = defs[c];
      double curOt = rosterOt[k] ?? d?.ot ?? 0;
      if (d != null) {
        hrs += d.hours;
        shiftCount[c] = (shiftCount[c] ?? 0) + 1;
        shiftHours[c] = (shiftHours[c] ?? 0) + d.hours;
        if (d.hasAllowance) allow += d.allowance;
        int w = isoWeek(dt);
        weeklyHours[w] = (weeklyHours[w] ?? 0) + d.hours;
      }
      ot += curOt;
      allow += (rosterExtra[k] ?? 0);
      if (rosterExtra.containsKey(k) && rosterExtraType.containsKey(k)) { String t = rosterExtraType[k]!; extraByType[t] = (extraByType[t] ?? 0) + rosterExtra[k]!; }
      hrs += (rosterExtraHrs[k] ?? 0);
    }
    double otAmount = ot * overtimeRate;
    double totalAllow = allow + otAmount + extraAllowances.fold(0.0, (a, b) => a + b.amount);
    return SafeArea(child: ListView(padding: const EdgeInsets.all(12), children: [
      Row(children: [
        FilledButton.icon(onPressed: exportReport, icon: const Icon(Icons.ios_share, size: 18), label: const Text('匯出', style: TextStyle(fontSize: 14)), style: FilledButton.styleFrom(backgroundColor: Colors.deepPurple, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8))),
        const SizedBox(width: 8),
        Expanded(child: InkWell(onTap: () => quickJumpMonth(forReport: true), child: Container(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Flexible(child: Text('${year}年${isYearReport ? ' 全年' : ' ${month}月'}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
          const Icon(Icons.arrow_drop_down, size: 22),
        ])))),
        const SizedBox(width: 4),
        SegmentedButton<bool>(
          segments: const [ButtonSegment(value: false, label: Text('本月')), ButtonSegment(value: true, label: Text('全年'))],
          selected: {isYearReport},
          onSelectionChanged: (s) { setState(() => isYearReport = s.first); },
          style: ButtonStyle(padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 8)), textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 13)), visualDensity: VisualDensity.compact),
        ),
      ]),
      const SizedBox(height: 8),
      if (isYearReport) Card(color: const Color(0xFFE3F2FD), child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('全年總工時 ${totalYearHrs.toStringAsFixed(1)}h', style: const TextStyle(fontWeight: FontWeight.bold)),
        const Divider(),
        ...yearMonthlyHrs.entries.map((e) => Row(children: [Text('${e.key}月'), const Spacer(), Text('${e.value.toStringAsFixed(1)}h')])),
      ]))),
      if (!isYearReport) Card(color: const Color(0xFFE3F2FD), child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('班次統計', style: TextStyle(fontWeight: FontWeight.bold)),
        const Divider(),
        ...shiftCount.entries.map((e) {
          double h = shiftHours[e.key] ?? 0;
          var d = defs[e.key];
          return Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(children: [
            Container(width: 28, height: 28, decoration: BoxDecoration(color: d?.color ?? Colors.grey, borderRadius: BorderRadius.circular(6)), child: Center(child: Text(e.key, style: const TextStyle(color: Colors.white, fontSize: 11)))),
            const SizedBox(width: 8),
            Text('${d?.label ?? e.key} ${(d?.hasAllowance == true) ? '有津貼' : ''}'),
            const Spacer(),
            Text('${e.value}次 / ${h.toStringAsFixed(1)}h', style: const TextStyle(fontWeight: FontWeight.bold)),
          ]));
        }),
        const Divider(),
        Text('總工時 ${hrs.toStringAsFixed(1)}h / 承上 ${carry}h / 合計 ${(hrs + carry).toStringAsFixed(1)}h'),
      ]))),
      Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('承上 $carry h + 本月 $hrs h = ${carry + hrs}h', style: const TextStyle(fontWeight: FontWeight.bold)),
        const Divider(),
        Text(isYearReport ? '每週工時統計 全年' : '每週工時統計 (標準 & 承上) 週數', style: const TextStyle(fontWeight: FontWeight.bold)),
        ...weeklyHours.entries.map((e) {
          double avgCarry = weeklyHours.isEmpty ? 0 : carry / weeklyHours.length;
          double adjusted = e.value + avgCarry;
          double diff = adjusted - standardWeeklyHours;
          return Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [
            Text('W${e.key}', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Text('${e.value.toStringAsFixed(1)}h +承上${avgCarry.toStringAsFixed(1)} = ${adjusted.toStringAsFixed(1)}h'),
            const Spacer(),
            Text('${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(1)}h', style: TextStyle(color: diff > 0 ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
          ]));
        }),
        const Divider(),
        Text('標準 ${standardWeeklyHours}h/週 | 總差額 ${(carry + hrs - standardWeeklyHours * weeklyHours.length).toStringAsFixed(1)}h'),
      ]))),
      Card(color: const Color(0xFFE8F5E9), child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('津貼類別 (含自定義類別)', style: TextStyle(fontWeight: FontWeight.bold)),
        Row(children: [const Text('班次津貼+單日額外'), const Spacer(), Text('\$${allow.toStringAsFixed(1)}')]),
        if (extraByType.isNotEmpty) const Divider(),
        ...extraByType.entries.map((e) => Row(children: [Text('類別: ${e.key}'), const Spacer(), Text('\$${e.value.toStringAsFixed(1)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple))])),
        Row(children: [Text('OT${ot.toStringAsFixed(1)}h x ${overtimeRate.toStringAsFixed(0)}'), const Spacer(), Text('\$${otAmount.toStringAsFixed(1)}')]),
        const Divider(),
        ...extraAllowances.map((e) => Row(children: [Text(e.name), const Spacer(), Text('\$${e.amount}'), IconButton(icon: const Icon(Icons.delete, size: 16), onPressed: () { setState(() => extraAllowances.removeAt(extraAllowances.indexOf(e))); save(); })])),
        const Divider(),
        Row(children: [const Text('津貼總額 (含自定+類別)'), const Spacer(), Text('\$${totalAllow.toStringAsFixed(1)}', style: const TextStyle(fontWeight: FontWeight.bold))]),
      ]))),
    ]));
  }

  Widget settingsTab() {
    var stdCtrl = TextEditingController(text: standardWeeklyHours.toString());
    var carryCtrl = TextEditingController(text: carry.toString());
    var otRateCtrl = TextEditingController(text: overtimeRate.toString());
    List<MapEntry<String, ShiftDef>> shiftList = defs.entries.toList();
    List<MapEntry<String, ShiftDef>> shiftShow = showAllShift ? shiftList : shiftList.take(5).toList();
    List<ExtraAllowance> allowShow = showAllExtra ? extraAllowances : extraAllowances.take(5).toList();
    return SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('排更日曆自定名稱', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
        TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '日曆名稱', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        SizedBox(width: double.infinity, child: FilledButton(onPressed: () { setState(() => customName = nameCtrl.text.trim().isEmpty ? '我的排更' : nameCtrl.text.trim()); save(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('日曆名已改為 $customName'))); }, child: const Text('保存日曆名稱')))
      ]))),
      const SizedBox(height: 16),
      const Text('自定班次', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      Card(child: Column(children: [
        ...shiftShow.map((e) {
          var d = e.value;
          return ListTile(
            leading: CircleAvatar(backgroundColor: d.color, child: Text(d.code, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
            title: Text('${d.code} - ${d.label}', style: const TextStyle(fontWeight: FontWeight.bold)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(icon: const Icon(Icons.edit), onPressed: () => editShiftDialog(oldDef: d)),
              IconButton(icon: const Icon(Icons.delete), onPressed: () { setState(() => defs.remove(e.key)); save(); })
            ])
          );
        }),
        if (shiftList.length > 5) TextButton(onPressed: () { setState(() => showAllShift = !showAllShift); }, child: Text(showAllShift ? '收起' : '顯示全部 ${shiftList.length}項')),
        ListTile(leading: const Icon(Icons.add), title: const Text('新增班次'), onTap: () => editShiftDialog()),
      ])),
      const SizedBox(height: 16),
      const Text('公眾假期地區 (自動更新多年 2024-2030)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
        DropdownButtonFormField<String>(
          value: holidayRegion,
          decoration: const InputDecoration(labelText: '地區 (已自動更新多年)', border: OutlineInputBorder()),
          items: ['無', '香港', '中國內地', '台灣', '美國'].map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
          onChanged: (v) { setState(() => holidayRegion = v!); save(); }
        ),
        const SizedBox(height: 8),
        Text('本年 ${focused.year} 假期數: ${getHolidays(focused.year, holidayRegion).length} 個', style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.refresh, size: 18), label: const Text('手動更新'), onPressed: () { setState(() {}); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('假期已手動更新'))); })),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.add, size: 18), label: const Text('農曆添加'), onPressed: () {
            var dCtrl = TextEditingController(text: '${focused.year}-');
            var nCtrl = TextEditingController(text: '農曆節日');
            showDialog(context: context, builder: (ctx) => AlertDialog(
              title: const Text('新增農曆/手動假期'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(height: 56, child: TextField(controller: dCtrl, decoration: const InputDecoration(labelText: '日期 (yyyy-MM-dd)', isDense: true, border: OutlineInputBorder()))),
                const SizedBox(height: 8),
                SizedBox(height: 56, child: TextField(controller: nCtrl, decoration: const InputDecoration(labelText: '假期名稱', isDense: true, border: OutlineInputBorder()))),
              ]),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                FilledButton(onPressed: () { if (dCtrl.text.isNotEmpty && nCtrl.text.isNotEmpty) { setState(() => manualHolidays[dCtrl.text.trim()] = nCtrl.text.trim()); save(); Navigator.pop(ctx); } }, child: const Text('新增')),
              ]
            ));
          })),
        ]),
        if (manualHolidays.isNotEmpty) ...[
          const Divider(),
          const Text('已添加的手動假期:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ...manualHolidays.entries.map((e) => ListTile(dense: true, title: Text('${e.key} - ${e.value}', style: const TextStyle(fontSize: 12)), trailing: IconButton(icon: const Icon(Icons.delete, size: 18), onPressed: () { setState(() => manualHolidays.remove(e.key)); save(); }))),
        ],
        SwitchListTile(title: const Text('顯示農曆'), value: showLunar, onChanged: (v) { setState(() => showLunar = v); save(); }),
      ]))),
      const SizedBox(height: 16),
      const Text('日曆同步', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
        SwitchListTile(title: const Text('啟用日曆同步'), subtitle: Text(googleSyncEnabled ? '已授權' : '未授權'), value: googleSyncEnabled, onChanged: (v) async { if (v) { await _requestGooglePerm(); } else { setState(() => googleSyncEnabled = false); save(); } }),
        SwitchListTile(title: const Text('自動同步'), value: autoSync, onChanged: googleSyncEnabled ? (v) { setState(() => autoSync = v); save(); } : null),
        Row(children: [
          Expanded(child: OutlinedButton.icon(onPressed: googleSyncEnabled ? () => _syncToGoogle() : null, icon: const Icon(Icons.sync), label: const Text('手動同步'))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(onPressed: () { setState(() => googleSyncEnabled = false); save(); }, icon: const Icon(Icons.link_off), label: const Text('取消')))
        ]),
        Text('當前: $_rosterCalendarName\nID: ${_rosterCalendarId ?? '未選'}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 8),
        SizedBox(width: double.infinity, child: OutlinedButton.icon(icon: const Icon(Icons.list), label: const Text('選擇日曆'), onPressed: () async { await _pickGoogleCalendarDialog(); })),
        SizedBox(width: double.infinity, child: OutlinedButton.icon(icon: const Icon(Icons.security), label: const Text('重新請求日曆權限'), onPressed: () async { await handleCalendarPermission(silent: false); setState(() {}); })),
        const Divider(),
        Container(width: double.infinity, padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.red.withOpacity(0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red.withOpacity(0.3))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('⚠️ 全清重建（救援用）', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 13)),
            const Text('• 刪除所有 [RosterPro] 事件\n• App 排班資料不受影響', style: TextStyle(fontSize: 10, color: Colors.black54)),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: FilledButton.icon(
              onPressed: googleSyncEnabled ? _forceFullResync : null,
              icon: const Icon(Icons.cleaning_services, size: 18),
              label: const Text('執行全清重建'),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
            )),
          ])
        ),
      ]))),
      const SizedBox(height: 16),
      const Text('清除排更 - 按日期範圍', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red)),
      Card(color: const Color(0xFFFFEBEE), child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
        SizedBox(width: double.infinity, child: FilledButton.icon(icon: const Icon(Icons.delete_sweep), style: FilledButton.styleFrom(backgroundColor: Colors.red), label: const Text('按日期範圍清除'), onPressed: clearRosterByRange))
      ]))),
      const SizedBox(height: 16),
      const Text('標準工時 & 承上 & 超時金額', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
        Row(children: [
          Expanded(child: TextField(controller: stdCtrl, decoration: const InputDecoration(labelText: '標準工時', suffixText: 'h/週', border: OutlineInputBorder()))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: carryCtrl, decoration: const InputDecoration(labelText: '承上餘額', border: OutlineInputBorder())))
        ]),
        const SizedBox(height: 10),
        TextField(controller: otRateCtrl, decoration: const InputDecoration(labelText: '超時金額 /h', prefixText: '\$ ', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        SizedBox(width: double.infinity, child: FilledButton(onPressed: () {
          double? v1 = double.tryParse(stdCtrl.text);
          double? v2 = double.tryParse(carryCtrl.text);
          double? v3 = double.tryParse(otRateCtrl.text);
          if (v1 != null) standardWeeklyHours = v1;
          if (v2 != null) carry = v2;
          if (v3 != null) overtimeRate = v3;
          setState(() {});
          save();
        }, child: const Text('保存設定')))
      ]))),
      const SizedBox(height: 16),
      const Text('日曆顯示設定', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
        Row(children: [
          const Text('小'),
          Expanded(child: Slider(value: calendarFontSize, min: 8, max: 20, divisions: 12, onChanged: (v) { setState(() => calendarFontSize = v); })),
          const Text('大')
        ]),
        FilledButton.tonal(onPressed: () { save(); }, child: const Text('保存文字大小')),
        const Divider(),
        ListTile(title: const Text('當天日期格背景顏色'), leading: CircleAvatar(backgroundColor: todayBgColor), trailing: const Icon(Icons.color_lens), onTap: () {
          showDialog(context: context, builder: (ctx) => AlertDialog(
            title: const Text('選擇當天背景'),
            content: Wrap(spacing: 8, children: [Colors.yellow.shade100, Colors.orange.shade100, Colors.green.shade100, Colors.blue.shade100, Colors.pink.shade100, const Color(0xFFFFF9C4)].map((c) => GestureDetector(onTap: () { setState(() => todayBgColor = c); save(); Navigator.pop(ctx); }, child: Container(width: 40, height: 40, decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all())))).toList())
          ));
        }),
        ListTile(title: const Text('當天日期格邊框顏色'), leading: CircleAvatar(backgroundColor: todayBorderColor), trailing: const Icon(Icons.border_color), onTap: () {
          showDialog(context: context, builder: (ctx) => AlertDialog(
            title: const Text('選擇當天邊框'),
            content: Wrap(spacing: 8, children: [Colors.orange, Colors.red, Colors.green, Colors.blue, Colors.purple, Colors.black].map((c) => GestureDetector(onTap: () { setState(() => todayBorderColor = c); save(); Navigator.pop(ctx); }, child: Container(width: 40, height: 40, decoration: BoxDecoration(color: c, shape: BoxShape.circle)))).toList())
          ));
        }),
      ]))),
      const SizedBox(height: 16),
      const Text('額外津貼 (自定名)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      Card(child: Column(children: [
        ...allowShow.map((e) {
          int idx = extraAllowances.indexOf(e);
          return ListTile(title: Text(e.name), subtitle: Text('\$${e.amount}'), trailing: IconButton(icon: const Icon(Icons.delete, size: 18, color: Colors.red), onPressed: () { setState(() => extraAllowances.removeAt(idx)); save(); }));
        }),
        ListTile(leading: const Icon(Icons.add), title: const Text('新增額外津貼'), onTap: () {
          var nCtrl = TextEditingController();
          var vCtrl = TextEditingController(text: '0');
          showDialog(context: context, builder: (ctx) => AlertDialog(
            title: const Text('新增額外津貼'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(height: 56, child: TextField(controller: nCtrl, decoration: const InputDecoration(labelText: '名稱', isDense: true, border: OutlineInputBorder()))),
              const SizedBox(height: 8),
              SizedBox(height: 56, child: TextField(controller: vCtrl, decoration: const InputDecoration(labelText: '金額', isDense: true, border: OutlineInputBorder()), keyboardType: TextInputType.number)),
            ]),
            actions: [FilledButton(onPressed: () { String name = nCtrl.text.trim(); double? val = double.tryParse(vCtrl.text); if (name.isEmpty || val == null) return; setState(() => extraAllowances.add(ExtraAllowance(name, val))); save(); Navigator.pop(ctx); }, child: const Text('新增'))]
          ));
        }),
        if (extraAllowances.length > 5) TextButton(onPressed: () => setState(() => showAllExtra = !showAllExtra), child: Text(showAllExtra ? '收起' : '顯示全部 ${extraAllowances.length}項')),
      ])),
      const SizedBox(height: 16),
      const Text('全部備份與還原', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: FilledButton.icon(onPressed: backupAnywhere, icon: const Icon(Icons.backup), label: const Text('立即備份'))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(onPressed: showBackupList, icon: const Icon(Icons.folder_open), label: const Text('備份清單'))),
        ]),
        const SizedBox(height: 8),
        SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: restoreLocalFile, icon: const Icon(Icons.restore), label: const Text('從檔案還原 (.json)'))),
        const SizedBox(height: 8),
        SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: showWidgetDebugLog, icon: const Icon(Icons.bug_report), label: const Text('查看小工具調試日誌'), style: OutlinedButton.styleFrom(foregroundColor: Colors.deepPurple))),
        const SizedBox(height: 8),
        Container(width: double.infinity, padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('最近備份路徑:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            Text(_lastBackupPath, style: const TextStyle(fontSize: 10, color: Colors.black87)),
          ])),
      ]))),
      const SizedBox(height: 16),
      const Text('桌面小工具設定 (Widget)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      Card(color: const Color(0xFFE8F5E9), child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
        Row(children: [
          const Text('文字大小', style: TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Slider(
            value: widgetFontSize,
            min: 20, max: 100, divisions: 16,
            label: widgetFontSize.toStringAsFixed(0),
            onChanged: (v) async {
              setState(() => widgetFontSize = v);
              try { await HomeWidget.saveWidgetData<double>('widgetFontSize', v); } catch (_) {}
              try { await HomeWidget.updateWidget(androidName: 'com.example.roster_pro.RosterWidgetProvider'); } catch (_) {}
            },
            onChangeEnd: (v) async { await save(); },
          )),
          Text(widgetFontSize.toStringAsFixed(0), style: const TextStyle(fontWeight: FontWeight.bold)),
        ]),
        ListTile(
          title: const Text('文字顏色', style: TextStyle(fontWeight: FontWeight.bold)),
          leading: CircleAvatar(backgroundColor: Color(widgetTextColor)),
          trailing: const Icon(Icons.color_lens),
          onTap: () {
            showDialog(context: context, builder: (ctx) => AlertDialog(
              title: const Text('選擇桌面小工具文字顏色'),
              content: Wrap(spacing: 8, runSpacing: 8, children: [
                Colors.black, Colors.white, Colors.red, Colors.blue, Colors.green, Colors.orange, Colors.purple, Colors.grey, Colors.pink, Colors.teal
              ].map((c) => GestureDetector(
                onTap: () async {
                  Navigator.pop(ctx);
                  setState(() => widgetTextColor = c.value);
                  try { await HomeWidget.saveWidgetData<double>('widgetTextColor', c.value.toDouble()); } catch (_) {}
                  try { await HomeWidget.updateWidget(androidName: 'com.example.roster_pro.RosterWidgetProvider'); } catch (_) {}
                  await save();
                },
                child: Container(width: 40, height: 40, decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: Colors.black26)))
              )).toList())
            ));
          },
        ),
        const Padding(padding: EdgeInsets.only(top: 8), child: Text('提示：修改後，桌面小工具可能需要幾秒鐘重新整理才會生效', style: TextStyle(fontSize: 11, color: Colors.grey))),
      ]))),
      const SizedBox(height: 16),
      const Text('應用資訊', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      Card(child: ListTile(leading: const Icon(Icons.info_outline), title: const Text('版本號'), subtitle: Text(appVersion))),
      const SizedBox(height: 16),
    ]));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: [calTab(), patternTab(), reportTab(), settingsTab()][tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.calendar_month), label: '月曆'),
          NavigationDestination(icon: Icon(Icons.pattern), label: '模式'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: '報表'),
          NavigationDestination(icon: Icon(Icons.settings), label: '設定'),
        ]
      ),
    );
  }
}
