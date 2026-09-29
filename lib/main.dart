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
import 'package:http/http.dart' as http;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzData.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Hong_Kong'));
  HomeWidget.setAppGroupId('group.rosterPro');
  runApp(const RosterApp());
}

class LeaveDef {
  String name;
  String fullName;
  Color color;
  bool isCustom;
  LeaveDef(this.name, this.fullName, this.color, {this.isCustom = false});
  Map<String, dynamic> toJson() => {'name': name, 'fullName': fullName, 'color': color.value, 'isCustom': isCustom};
  factory LeaveDef.fromJson(Map<String, dynamic> j) => LeaveDef(j['name'], j['fullName'] ?? j['name'], Color(j['color'] ?? 0xFF9C27B0), isCustom: j['isCustom'] ?? false);
}

class ShiftDef {
  String code; String label; double hours; double ot; Color color; String start; String end;
  bool hasMorningAllow; bool hasNightAllow; bool hasMealAllow; bool isAllDay; bool hasLunch;
  bool hasAL; bool hasSH; bool hasGH; bool hasWB;
  bool hasCustomLeave; String? customLeaveCode;
  bool alarmEnabled;
  int alarmMinutesBefore;
  String? alarmSoundUri;
  String? alarmSoundName;

  ShiftDef(this.code, this.label, this.hours, this.color, {
    this.ot = 0, this.start = '07:00', this.end = '15:30',
    this.hasMorningAllow = false, this.hasNightAllow = false, this.hasMealAllow = false,
    this.isAllDay = false, this.hasLunch = false,
    this.hasAL = false, this.hasSH = false, this.hasGH = false, this.hasWB = false,
    this.hasCustomLeave = false, this.customLeaveCode,
    this.alarmEnabled = false,
    this.alarmMinutesBefore = 30,
    this.alarmSoundUri,
    this.alarmSoundName,
  });
  Map<String, dynamic> toJson() => {
    'code': code, 'label': label, 'hours': hours, 'ot': ot, 'color': color.value,
    'start': start, 'end': end,
    'hasMorningAllow': hasMorningAllow, 'hasNightAllow': hasNightAllow, 'hasMealAllow': hasMealAllow,
    'isAllDay': isAllDay, 'hasLunch': hasLunch,
    'hasAL': hasAL, 'hasSH': hasSH, 'hasGH': hasGH, 'hasWB': hasWB,
    'hasCustomLeave': hasCustomLeave, 'customLeaveCode': customLeaveCode,
    'alarmEnabled': alarmEnabled,
    'alarmMinutesBefore': alarmMinutesBefore,
    'alarmSoundUri': alarmSoundUri,
    'alarmSoundName': alarmSoundName,
  };
  factory ShiftDef.fromJson(Map<String, dynamic> j) => ShiftDef(
    j['code'], j['label'] ?? j['code'], (j['hours'] ?? 8).toDouble(), Color(j['color'] ?? 0xFFFF9800),
    ot: (j['ot'] ?? 0).toDouble(), start: j['start'] ?? '07:00', end: j['end'] ?? '15:30',
    hasMorningAllow: j['hasMorningAllow'] ?? false, hasNightAllow: j['hasNightAllow'] ?? false,
    hasMealAllow: j['hasMealAllow'] ?? false, isAllDay: j['isAllDay'] ?? false, hasLunch: j['hasLunch'] ?? false,
    hasAL: j['hasAL'] ?? false, hasSH: j['hasSH'] ?? false, hasGH: j['hasGH'] ?? false, hasWB: j['hasWB'] ?? false,
    hasCustomLeave: j['hasCustomLeave'] ?? false, customLeaveCode: j['customLeaveCode'],
    alarmEnabled: j['alarmEnabled'] ?? false,
    alarmMinutesBefore: j['alarmMinutesBefore'] ?? 30,
    alarmSoundUri: j['alarmSoundUri'],
    alarmSoundName: j['alarmSoundName'],
  );
  String get detailTime => isAllDay ? '全天 ${hours.toStringAsFixed(1)}h' : '${start}-${end} ${hours.toStringAsFixed(1)}h';
}

class ExtraAllowance {
  String name;
  double amount;
  double multiplier;
  ExtraAllowance(this.name, this.amount, {this.multiplier = 1.0});
  double get total => amount;
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
    0x14b63, 0x09370, 0x049f8, 0x04970, 0x064b0, 0x168a6, 0x0ea50, 0x06b20, 0x1a6c4, 0x0aae0,
    0x0a2e0, 0x0d2e3, 0x0c960, 0x0d557, 0x0d4a0, 0x0da50, 0x05d55, 0x056a0, 0x0a6d0, 0x055d4,
    0x052d0, 0x0a9b8, 0x0a950, 0x0b4a0, 0x0b6a6, 0x0ad50, 0x055a0, 0x0aba4, 0x0a5b0, 0x052b0,
    0x0b273, 0x06930, 0x07337, 0x06aa0, 0x0ad50, 0x14b55, 0x04b60, 0x0a570, 0x054e4, 0x0d160,
    0x0e968, 0x0d520, 0x0daa0, 0x16aa6, 0x056d0, 0x04ae0, 0x0a9d4, 0x0a2d0, 0x0d150, 0x0f252,
    0x0d520,
  ];
  static final List<String> lunarMonths = ['正','二','三','四','五','六','七','八','九','十','冬','臘'];
  static final List<String> lunarDays = ['初一','初二','初三','初四','初五','初六','初七','初八','初九','初十','十一','十二','十三','十四','十五','十六','十七','十八','十九','二十','廿一','廿二','廿三','廿四','廿五','廿六','廿七','廿八','廿九','三十'];
  static bool _isYearSupported(int y) => y >= 1900 && y <= 2100;
  static int leapMonth(int y) { if (!_isYearSupported(y)) return 0; return lunarInfo[y - 1900] & 0xf; }
  static int leapDays(int y) { if (!_isYearSupported(y)) return 0; if (leapMonth(y) == 0) return 0; return ((lunarInfo[y - 1900] & 0x10000) != 0) ? 30 : 29; }
  static int monthDays(int y, int m) { if (!_isYearSupported(y)) return 30; return ((lunarInfo[y - 1900] & (0x10000 >> m)) != 0) ? 30 : 29; }
  static int lYearDays(int y) { if (!_isYearSupported(y)) return 365; int sum = 348; for (int i = 0x8000; i > 0x8; i >>= 1) sum += ((lunarInfo[y - 1900] & i) != 0) ? 1 : 0; return sum + leapDays(y); }
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
      if (!_isYearSupported(date.year)) return '';
      final r = solarToLunar(date);
      int m = r[0], d = r[1], isLeap = r[2];
      if (d == 1) return '${isLeap == 1 ? '閏' : ''}${lunarMonths[m - 1]}月';
      return lunarDays[d - 1];
    } catch (_) { return ''; }
  }
  static String getFullLunarText(DateTime date) {
    try {
      if (!_isYearSupported(date.year)) return '';
      final r = solarToLunar(date);
      int m = r[0], d = r[1], isLeap = r[2];
      final monthStr = '${isLeap == 1 ? '閏' : ''}${lunarMonths[m - 1]}月';
      if (d == 1) return monthStr;
      return '$monthStr${lunarDays[d - 1]}';
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
  Map<String, bool> rosterAlarmMuted = {};

  List<LeaveDef> leaveDefs = [
    LeaveDef('AL', 'Annual Leave', Colors.teal),
    LeaveDef('GH', 'General Holiday', Colors.indigo),
    LeaveDef('SH', 'Statutory Holiday', Colors.deepOrange),
    LeaveDef('WB', 'Well-being Leave', Colors.lightBlue),
  ];
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
  String carryAnchorWeekKey = '';
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
  static const _ringtoneChannel = MethodChannel('com.roster/ringtone');
  String? _rosterCalendarId;
  String _rosterCalendarName = '未選';
  String _rosterAccountName = '';
  Map<String, String> _googleEventIdMap = {};

  Set<String> _dirtyDates = <String>{};
  bool _needsFullSync = false;

  Map<int, Map<String, String>> _holidayCache = {};
  bool _holidayLoading = false;
  String _holidayLastUpdate = '';

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

  // ==================== 鈴聲相關方法 ====================

  Future<List<Map<String, String>>> _getSystemRingtones() async {
    try {
      if (await Permission.audio.isDenied) {
        final status = await Permission.audio.request();
        if (status.isDenied || status.isPermanentlyDenied) {
          if (mounted) {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('需要音訊權限'),
                content: const Text('請允許存取音訊權限，才能讀取系統鈴聲列表。\n\n前往設定 > 應用程式 > Roster Pro > 權限 > 音樂和音訊，允許存取。'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                  FilledButton(onPressed: () { openAppSettings(); Navigator.pop(ctx); }, child: const Text('去設定')),
                ],
              ),
            );
          }
          return [];
        }
      }
      final List<dynamic>? result = await _ringtoneChannel.invokeMethod('getRingtones');
      return result?.map((e) => Map<String, String>.from(e as Map)).toList() ?? [];
    } catch (e) {
      await _writeDebugLog('[鈴聲] 獲取系統鈴聲失敗: $e');
      return [];
    }
  }

  Future<void> _playRingtonePreview(String uri) async {
    try {
      await _ringtoneChannel.invokeMethod('playRingtone', {'uri': uri});
    } catch (e) {
      await _writeDebugLog('[鈴聲] 播放預覽失敗: $e');
    }
  }

  Future<void> _stopRingtonePreview() async {
    try {
      await _ringtoneChannel.invokeMethod('stopRingtone');
    } catch (e) {
      await _writeDebugLog('[鈴聲] 停止預覽失敗: $e');
    }
  }

  // ==================== 權限請求 ====================

  Future<void> _requestAllPermissions() async {
    await handleCalendarPermission(silent: false);
    if (!await Permission.notification.isGranted) await Permission.notification.request();
    if (await Permission.scheduleExactAlarm.isDenied) await Permission.scheduleExactAlarm.request();
    if (!await Permission.manageExternalStorage.isGranted) await Permission.manageExternalStorage.request();
    if (await Permission.audio.isDenied) await Permission.audio.request();
  }

  // ==================== 原有方法 ====================

  String _requireCalendarId() {
    final id = _rosterCalendarId;
    if (id == null || id.isEmpty) throw '尚未選擇日曆，請至「設定 → 選擇日曆」指定目標日曆';
    return id;
  }

  Future<bool> _safeDeleteEvent(String eventId) async {
    final calId = _requireCalendarId();
    try {
      final bool? ok = await _realChannel.invokeMethod('deleteEvent', {'calendarId': calId, 'eventId': eventId});
      if (ok == true) return true;
    } catch (e) { await _writeDebugLog('[原生 deleteEvent 失敗] $e'); }
    try {
      final ok = await _calendarPlugin.deleteEvent(calId, eventId);
      return ok == true;
    } catch (e) { return false; }
  }

  Future<List<Event>> _safeRetrieveEvents(DateTime start, DateTime end) async {
    final calId = _requireCalendarId();
    try {
      final List<dynamic>? res = await _realChannel.invokeMethod('queryEvents', {
        'calendarId': calId, 'startMillis': start.millisecondsSinceEpoch, 'endMillis': end.millisecondsSinceEpoch,
      }).timeout(const Duration(seconds: 10), onTimeout: () { return null; });
      if (res != null) {
        return res.map((e) {
          final map = Map<String, dynamic>.from(e as Map);
          final int? startMs = map['startMillis'] as int?;
          final int? endMs = map['endMillis'] as int?;
          return Event(calId, eventId: map['eventId']?.toString(), title: map['title']?.toString(), description: map['description']?.toString(),
            start: startMs != null ? tz.TZDateTime.fromMillisecondsSinceEpoch(tz.UTC, startMs) : null,
            end: endMs != null ? tz.TZDateTime.fromMillisecondsSinceEpoch(tz.UTC, endMs) : null, allDay: map['allDay'] == true);
        }).toList();
      }
    } catch (e) { await _writeDebugLog('[原生 queryEvents 失敗] $e'); }
    final res = await _calendarPlugin.retrieveEvents(calId, RetrieveEventsParams(startDate: start, endDate: end));
    if (!res.isSuccess) throw 'device_calendar retrieveEvents 失敗';
    return res.data ?? [];
  }

  Future<void> _writeDebugLog(String message) async {
    try {
      final dir = await getExternalStorageDirectory();
      if (dir == null) return;
      final f = File('${dir.path}/roster_widget_debug.txt');
      final ts = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
      await f.writeAsString('[$ts][Dart] $message\n', mode: FileMode.append);
      if (await f.length() > 200 * 1024) await f.writeAsString('[$ts] (log reset)\n');
    } catch (_) {}
  }

  String _getCountryCode(String region) {
    switch (region) { case '香港': return 'HK'; case '中國內地': return 'CN'; case '台灣': return 'TW'; case '美國': return 'US'; default: return 'HK'; }
  }

  static const Map<String, String> _holidayNameMap = {
    "New Year's Day": "元旦", "Lunar New Year's Day": "農曆年初一", "Second Day of Lunar New Year": "農曆年初二", "Third Day of Lunar New Year": "農曆年初三",
    "Good Friday": "耶穌受難節", "Easter Monday": "復活節星期一", "The day following Good Friday": "耶穌受難節翌日", "Ching Ming Festival": "清明節",
    "Labour Day": "勞動節", "The Birthday of the Buddha": "佛誕", "Tuen Ng Festival": "端午節", "Hong Kong Special Administrative Region Establishment Day": "香港特區成立紀念日",
    "National Day": "國慶日", "The day following the Chinese Mid-Autumn Festival": "中秋翌日", "Chinese Mid-Autumn Festival": "中秋節",
    "Chung Yeung Festival": "重陽節", "Christmas Day": "聖誕節", "Boxing Day": "聖誕節後第一個周日", "The first weekday after Christmas Day": "聖誕節後第一個周日",
    "First Weekday After Christmas Day": "聖誕節後第一個周日", "New Year's Day (observed)": "元旦（補假）", "Chinese New Year": "農曆新年",
  };

  String _translateHolidayName(String raw) {
    if (_holidayNameMap.containsKey(raw)) return _holidayNameMap[raw]!;
    for (var entry in _holidayNameMap.entries) { if (raw.toLowerCase().contains(entry.key.toLowerCase())) return entry.value; }
    return raw;
  }

  Future<bool> fetchHolidaysFromApi(int year, {bool force = false}) async {
    if (holidayRegion == '無') return false;
    if (_holidayLoading && !force) return false;
    if (force) _holidayLoading = true;
    try {
      final sp = await SharedPreferences.getInstance();
      final cacheKey = 'holidays_${_getCountryCode(holidayRegion)}_$year';
      if (!force) {
        final cached = sp.getString(cacheKey);
        if (cached != null && cached.isNotEmpty) {
          try {
            final map = Map<String, String>.from(jsonDecode(cached));
            if (map.isNotEmpty) { _holidayCache[year] = map; _holidayLoading = false; return true; }
          } catch (_) {}
        }
      }
      final url = Uri.parse('https://date.nager.at/api/v3/PublicHolidays/$year/${_getCountryCode(holidayRegion)}');
      final res = await http.get(url).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) { _holidayLoading = false; return false; }
      final list = jsonDecode(res.body) as List;
      final map = <String, String>{};
      for (var item in list) {
        final dateStr = item['date']?.toString() ?? '';
        if (dateStr.isEmpty) continue;
        map[dateStr] = _translateHolidayName((item['localName'] ?? item['name'] ?? '').toString());
      }
      if (map.isEmpty) { _holidayLoading = false; return false; }
      _holidayCache[year] = map;
      await sp.setString(cacheKey, jsonEncode(map));
      _holidayLastUpdate = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
      await sp.setString('holidayLastUpdate', _holidayLastUpdate);
      _holidayLoading = false;
      return true;
    } catch (e) { _holidayLoading = false; return false; }
  }

  Future<void> _autoFetchHolidays() async {
    if (holidayRegion == '無') return;
    final now = DateTime.now();
    for (int offset = 0; offset <= 2; offset++) { await fetchHolidaysFromApi(now.year + offset); }
    if (mounted) setState(() {});
  }

  Future<void> _manualRefreshHolidays() async {
    if (holidayRegion == '無') { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('目前地區設為「無」，不會抓取假期'))); return; }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在從網路更新公眾假期...'), duration: Duration(seconds: 1)));
    final now = DateTime.now();
    int success = 0;
    for (int offset = -1; offset <= 3; offset++) { final ok = await fetchHolidaysFromApi(now.year + offset, force: true); if (ok) success++; }
    if (mounted) setState(() {});
    if (mounted) {
      final count = getHolidays(focused.year, holidayRegion).length;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已更新 $success 年假期，${focused.year} 年共 $count 個假期'), duration: const Duration(seconds: 3), backgroundColor: success > 0 ? Colors.green : Colors.red));
    }
  }

  Map<String, String> _getBuiltinHolidays(int year, String region) {
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
    return m;
  }

  Map<String, String> getHolidays(int year, String region) {
    if (region == '無') return Map<String, String>.from(manualHolidays);
    final cached = _holidayCache[year];
    if (cached != null && cached.isNotEmpty) { final result = Map<String, String>.from(cached); result.addAll(manualHolidays); return result; }
    final m = _getBuiltinHolidays(year, region); m.addAll(manualHolidays); return m;
  }

  bool isHoliday(DateTime d) { return getHolidays(d.year, holidayRegion).containsKey(DateFormat('yyyy-MM-dd').format(d)); }
  String holidayName(DateTime d) { return getHolidays(d.year, holidayRegion)[DateFormat('yyyy-MM-dd').format(d)] ?? ''; }

  String _calcAlarmTimeText(String startStr, int minutesBefore) {
    try {
      final parts = startStr.split(':');
      if (parts.length != 2) return '--:--';
      int total = int.parse(parts[0]) * 60 + int.parse(parts[1]) - minutesBefore;
      while (total < 0) total += 24 * 60;
      return '${(total ~/ 60).toString().padLeft(2, '0')}:${(total % 60).toString().padLeft(2, '0')}';
    } catch (_) { return '--:--'; }
  }

  Future<void> _rescheduleAllAlarms() async {
    try { await _realChannel.invokeMethod('cancelAllAlarms'); } catch (e) { await _writeDebugLog('[鬧鐘] 取消全部鬧鐘失敗: $e'); }
    DateTime now = DateTime.now();
    DateTime today = DateTime(now.year, now.month, now.day);
    int count = 0, skipped = 0, mutedCount = 0;

    for (var entry in roster.entries) {
      final dateKey = entry.key;
      final def = defs[entry.value];
      if (def == null || !def.alarmEnabled) continue;
      if (def.isAllDay) { skipped++; continue; }
      if (rosterAlarmMuted[dateKey] == true) { mutedCount++; continue; }

      DateTime date;
      try { date = DateTime.parse(dateKey); } catch (_) { continue; }
      if (date.isBefore(today)) continue;

      final parts = def.start.split(':');
      if (parts.length != 2) continue;
      final startH = int.tryParse(parts[0]); final startM = int.tryParse(parts[1]);
      if (startH == null || startM == null) continue;

      DateTime alarmTime = DateTime(date.year, date.month, date.day, startH, startM).subtract(Duration(minutes: def.alarmMinutesBefore));
      if (alarmTime.isBefore(now)) { skipped++; continue; }

      int requestCode = dateKey.hashCode & 0x7FFFFFFF;
      try {
        await _realChannel.invokeMethod('scheduleAlarm', {
          'alarmMillis': alarmTime.millisecondsSinceEpoch,
          'requestCode': requestCode,
          'title': '上班提醒：${def.code} ${def.label}',
          'body': '${def.start} 上班，還有 ${def.alarmMinutesBefore} 分鐘',
          'soundUri': def.alarmSoundUri,
        });
        count++;
      } catch (e) { await _writeDebugLog('[鬧鐘] 排程失敗 $dateKey: $e'); }
    }
    await _writeDebugLog('[鬧鐘] 已排程 $count 個、跳過 $skipped 個、單日靜音 $mutedCount 個');
  }

  Future<bool> _confirmAction() async {
    bool? r = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('⚠️ 確認操作'), content: const Text('相關數據會被刪除或覆蓋，確定繼續進行？'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('確定繼續')),
      ],
    ));
    return r == true;
  }

  Future<void> updateWidget() async {
    try {
      String todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
      String tomorrowKey = DateFormat('yyyy-MM-dd').format(DateTime.now().add(const Duration(days: 1)));
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
    } catch (e) { await _writeDebugLog('updateWidget 整體失敗: $e'); }
  }

  @override
  void initState() {
    super.initState();
    nameCtrl.text = customName;
    _loadVersion();

    _realChannel.setMethodCallHandler((call) async {
      if (call.method == 'onWidgetDateSelected') {
        final dateStr = call.arguments as String?;
        if (dateStr != null && dateStr.isNotEmpty) {
          try {
            final dt = DateTime.parse(dateStr);
            if (mounted) {
              setState(() {
                selectedDay = dt;
                focused = DateTime(dt.year, dt.month, 1);
                tab = 0;
              });
            }
          } catch (e) {
            await _writeDebugLog('[widget] 解析日期失敗: $dateStr, $e');
          }
        }
      }
      return null;
    });

    Future.delayed(const Duration(milliseconds: 800), () async {
      try {
        final d = await _realChannel.invokeMethod('getPendingWidgetDate');
        if (d is String && d.isNotEmpty) {
          final dt = DateTime.parse(d);
          if (mounted) {
            setState(() {
              selectedDay = dt;
              focused = DateTime(dt.year, dt.month, 1);
              tab = 0;
            });
          }
        }
      } catch (_) {}
    });

    HomeWidget.registerInteractivityCallback(backgroundCallback);

    load().then((_) async {
      await Future.delayed(const Duration(milliseconds: 500));
      await _requestAllPermissions();
      try { await _realChannel.invokeMethod('requestManageStorage'); } catch (_) {}
      await updateWidget();
      Future.microtask(() => _autoFetchHolidays());
      if (googleSyncEnabled) {
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) { _syncToGoogle(silent: true, forceFullSync: false); }
        });
      }
    });
  }

  @pragma('vm:entry-point')
  static Future<void> backgroundCallback(Uri? uri) async { if (uri != null) debugPrint('小工具點擊: $uri'); }

  Future<void> _loadVersion() async {
    try { final info = await PackageInfo.fromPlatform(); setState(() { appVersion = '${info.version}+${info.buildNumber}'; }); } catch (_) { setState(() { appVersion = '未知版本'; }); }
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

    var ld = sp.getString('leaveDefs'); if (ld != null) { try { leaveDefs = (jsonDecode(ld) as List).map((e) => LeaveDef.fromJson(Map<String, dynamic>.from(e))).toList(); } catch (_) {} }
    var lr = sp.getString('leaveRecords'); if (lr != null) { try { leaveRecords = Map<String, Map<String, dynamic>>.from((jsonDecode(lr) as Map).map((k, v) => MapEntry(k as String, Map<String, dynamic>.from(v as Map)))); } catch (_) {} }
    var rl = sp.getString('rosterLeave'); if (rl != null) { try { rosterLeave = Map<String, String>.from(jsonDecode(rl)); } catch (_) {} }
    var ram = sp.getString('rosterAlarmMuted'); if (ram != null) { try { rosterAlarmMuted = Map<String, bool>.from((jsonDecode(ram) as Map).map((k, v) => MapEntry(k as String, v as bool))); } catch (_) {} }

    var ddList = sp.getStringList('dirtyDates'); if (ddList != null) _dirtyDates = ddList.toSet();
    _needsFullSync = sp.getBool('needsFullSync') ?? false;

    setState(() {
      carry = sp.getDouble('carry') ?? 0; carryAnchorWeekKey = sp.getString('carryAnchorWeekKey') ?? '';
      customName = sp.getString('cName') ?? '我的排更-專屬日曆'; nameCtrl.text = customName;
      standardWeeklyHours = sp.getDouble('stdWeek') ?? 42; overtimeRate = sp.getDouble('otRate') ?? 80;
      monthlySalary = sp.getDouble('monthlySalary') ?? 0; hourlyDivisor = sp.getDouble('hourlyDivisor') ?? 182; otMultiplier = sp.getDouble('otMultiplier') ?? 1.5;
      morningAllowance = sp.getDouble('morningAllow') ?? 0; nightAllowance = sp.getDouble('nightAllow') ?? 0; mealAllowance = sp.getDouble('mealAllow') ?? 0; nightAllowMultiplier = sp.getDouble('nightAllowMultiplier') ?? 0.4;
      calendarFontSize = sp.getDouble('calFont') ?? 14; googleSyncEnabled = sp.getBool('gSync') ?? false; autoSync = sp.getBool('gAuto') ?? false;
      holidayRegion = sp.getString('holidayRegion') ?? '香港'; _rosterCalendarId = sp.getString('rosterCalId'); _rosterCalendarName = sp.getString('rosterCalName') ?? '未選'; _rosterAccountName = sp.getString('rosterAccName') ?? '';
      _lastBackupPath = sp.getString('lastBackupPath') ?? '未備份'; todayBgColor = Color(sp.getInt('todayBg') ?? 0xFFFFF9C4); todayBorderColor = Color(sp.getInt('todayBorder') ?? 0xFFFF9800);
      showLunar = sp.getBool('showLunar') ?? true; widgetFontSize = sp.getDouble('widgetFontSize') ?? 14.0; widgetTextColor = sp.getInt('widgetTextColor') ?? 0xFF000000; widgetBgColor = sp.getInt('widgetBgColor') ?? 0xFFFFFFFF; iconIndex = sp.getInt('iconIndex') ?? 0;
    });
    _ensureAnchorWeek();
    _holidayLastUpdate = sp.getString('holidayLastUpdate') ?? '';
    Future.microtask(() => _rescheduleAllAlarms());
    updateWidget();
  }

  Future<void> save() async {
    var sp = await SharedPreferences.getInstance();
    sp.setString('roster', jsonEncode(roster)); sp.setString('note', jsonEncode(rosterNote)); sp.setString('extraType', jsonEncode(rosterExtraType));
    sp.setString('roOt', jsonEncode(rosterOt)); sp.setString('roEx', jsonEncode(rosterExtra)); sp.setString('roExH', jsonEncode(rosterExtraHrs));
    sp.setString('defs', jsonEncode(defs.map((k, v) => MapEntry(k, v.toJson())))); sp.setString('pattern', jsonEncode(pattern));
    sp.setDouble('carry', carry); sp.setString('carryAnchorWeekKey', carryAnchorWeekKey); sp.setString('cName', customName); sp.setDouble('stdWeek', standardWeeklyHours); sp.setDouble('otRate', overtimeRate);
    await sp.setDouble('monthlySalary', monthlySalary); await sp.setDouble('hourlyDivisor', hourlyDivisor); await sp.setDouble('otMultiplier', otMultiplier);
    await sp.setDouble('morningAllow', morningAllowance); await sp.setDouble('nightAllow', nightAllowance); await sp.setDouble('mealAllow', mealAllowance); await sp.setDouble('nightAllowMultiplier', nightAllowMultiplier);
    sp.setString('extraAllowNewV36', jsonEncode(extraAllowances.map((e) => e.toJson()).toList())); sp.setDouble('calFont', calendarFontSize); sp.setBool('gSync', googleSyncEnabled); sp.setBool('gAuto', autoSync);
    sp.setString('savedPatternsV40', jsonEncode(savedPatterns.map((e) => e.toJson()).toList())); sp.setString('holidayRegion', holidayRegion);
    sp.setString('googleEventIdMap', jsonEncode(_googleEventIdMap)); sp.setString('manualHolidays', jsonEncode(manualHolidays));
    await sp.setString('leaveDefs', jsonEncode(leaveDefs.map((e) => e.toJson()).toList())); await sp.setString('leaveRecords', jsonEncode(leaveRecords)); await sp.setString('rosterLeave', jsonEncode(rosterLeave)); await sp.setString('rosterAlarmMuted', jsonEncode(rosterAlarmMuted));
    await sp.setStringList('dirtyDates', _dirtyDates.toList()); await sp.setBool('needsFullSync', _needsFullSync);
    if (_rosterCalendarId != null) sp.setString('rosterCalId', _rosterCalendarId!); sp.setString('rosterCalName', _rosterCalendarName); sp.setString('rosterAccName', _rosterAccountName);
    sp.setString('lastBackupPath', _lastBackupPath); sp.setInt('todayBg', todayBgColor.value); sp.setInt('todayBorder', todayBorderColor.value);
    sp.setString('roster_json', jsonEncode(roster)); sp.setString('defs_json', jsonEncode(defs.map((k, v) => MapEntry(k, v.toJson()))));
    sp.setBool('showLunar', showLunar); await sp.setDouble('widgetFontSize', widgetFontSize); await sp.setInt('widgetTextColor', widgetTextColor); await sp.setInt('widgetBgColor', widgetBgColor); await sp.setInt('iconIndex', iconIndex);
    await updateWidget();
    if (autoSync && googleSyncEnabled && !_isSyncing) { _autoSyncTimer?.cancel(); _autoSyncTimer = Timer(const Duration(seconds: 3), () { if (!_isSyncing && autoSync && googleSyncEnabled) _syncToGoogle(silent: true); }); }
    Future.microtask(() => _rescheduleAllAlarms());
  }

  int isoWeek(DateTime date) { DateTime thursday = date.add(Duration(days: 4 - date.weekday)); return 1 + (thursday.difference(DateTime(thursday.year, 1, 1)).inDays / 7).floor(); }
  String isoWeekKey(DateTime date) { DateTime thursday = date.add(Duration(days: 4 - date.weekday)); int week = 1 + (thursday.difference(DateTime(thursday.year, 1, 1)).inDays / 7).floor(); return '${thursday.year}-W${week.toString().padLeft(2, '0')}'; }

  DateTime? _parseWeekKey(String key) {
    final m = RegExp(r'^(\d{4})-W(\d{2})$').firstMatch(key);
    if (m == null) return null;
    final year = int.parse(m.group(1)!); final week = int.parse(m.group(2)!);
    if (week < 1 || week > 53) return null;
    DateTime jan4 = DateTime(year, 1, 4); DateTime week1Monday = jan4.subtract(Duration(days: jan4.weekday - 1));
    return week1Monday.add(Duration(days: (week - 1) * 7));
  }

  DateTime _effectiveCalcStart(DateTime fallback) {
    if (carryAnchorWeekKey.isNotEmpty) { final parsed = _parseWeekKey(carryAnchorWeekKey); if (parsed != null) return parsed; }
    DateTime? globalStart;
    for (String k in roster.keys) { try { DateTime dt = DateTime.parse(k); if (globalStart == null || dt.isBefore(globalStart)) globalStart = dt; } catch (_) {} }
    if (globalStart != null) return globalStart.subtract(Duration(days: globalStart.weekday - 1));
    return fallback;
  }

  void _ensureAnchorWeek() {
    if (roster.isEmpty) return;
    DateTime? globalStart;
    for (String k in roster.keys) { try { DateTime dt = DateTime.parse(k); if (globalStart == null || dt.isBefore(globalStart)) globalStart = dt; } catch (_) {} }
    if (globalStart == null) return;
    final earliestKey = isoWeekKey(globalStart);
    if (carryAnchorWeekKey.isEmpty) { carryAnchorWeekKey = earliestKey; return; }
    final anchorDate = _parseWeekKey(carryAnchorWeekKey);
    if (anchorDate != null && anchorDate.isAfter(globalStart)) carryAnchorWeekKey = earliestKey;
  }

  void quickJumpMonth({bool forReport = false}) {
    int y = focused.year; int m = focused.month;
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
        await showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('需要日曆權限'), content: const Text('新安裝App需允許存取日曆才能讀取，否則顯示空白(0)。請去設定>權限>允許日曆'), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')), FilledButton(onPressed: () { openAppSettings(); Navigator.pop(ctx); }, child: const Text('去設定'))]));
      }
    } catch (_) {}
    try { var devHas = await _calendarPlugin.hasPermissions(); if (devHas.isSuccess && devHas.data == true) return true; var devReq = await _calendarPlugin.requestPermissions(); if (devReq.isSuccess && devReq.data == true) return true; } catch (_) {}
    return false;
  }

  Future<List<Map<String, dynamic>>> _getRealCalendars() async {
    try { var res = await _realChannel.invokeMethod('getCalendars'); return (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList(); }
    catch (e) { try { var r = await _calendarPlugin.retrieveCalendars(); return (r.data ?? []).map((c) => {'id': c.id, 'displayName': c.name, 'accountName': c.accountName, 'isGoogle': (c.accountName ?? '').contains('gmail') || (c.accountType ?? '').contains('google')}).toList(); } catch (_) { return []; } }
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
      final newId = pickedMap['id'].toString();
      final oldId = _rosterCalendarId;
      _rosterCalendarId = newId;
      _rosterCalendarName = pickedMap['displayName'].toString();
      _rosterAccountName = pickedMap['accountName'].toString();
      if (oldId != null && oldId != newId) { _googleEventIdMap.clear(); await _writeDebugLog('切換日曆 $oldId → $newId，已清空 googleEventIdMap'); }
      var sp = await SharedPreferences.getInstance();
      sp.setString('rosterCalId', _rosterCalendarId!); sp.setString('rosterCalName', _rosterCalendarName); sp.setString('rosterAccName', _rosterAccountName);
      await sp.setString('googleEventIdMap', jsonEncode(_googleEventIdMap));
      setState(() {});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已選 $_rosterCalendarId')));
      return _rosterCalendarId;
    }
    return null;
  }

  Future<String?> _createCustomCalendarDialog() async {
    if (!await handleCalendarPermission(silent: false)) return null;
    var nameCtrl = TextEditingController(text: '我的排更專屬日曆');
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('建立自訂日曆'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('請輸入日曆名稱（例如：nnnn）\n建立後將以此獨立日曆作同步之用'),
            const SizedBox(height: 12),
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '日曆名稱', border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('建立')),
        ],
      ),
    );
    if (confirm != true || nameCtrl.text.trim().isEmpty) return null;
    try {
      final result = await _calendarPlugin.createCalendar(nameCtrl.text.trim());
      if (result.isSuccess && result.data != null) {
        _rosterCalendarId = result.data;
        _rosterCalendarName = nameCtrl.text.trim();
        var sp = await SharedPreferences.getInstance();
        await sp.setString('rosterCalId', _rosterCalendarId!); await sp.setString('rosterCalName', _rosterCalendarName); await sp.setString('rosterAccName', 'local');
        setState(() {});
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已成功建立日曆：$_rosterCalendarName (ID: ${_rosterCalendarId})')));
        return _rosterCalendarId;
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('建立日曆失敗，請確認日曆權限或稍後再試')));
        return null;
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('建立日曆時發生錯誤：$e')));
      return null;
    }
  }

  Future<void> _requestGooglePerm() async {
    int? choice = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('選擇日曆來源'),
        content: const Text('您想要如何設定同步用的日曆？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 1), child: const Text('選擇已有日曆')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 2), child: const Text('建立自訂日曆')),
        ],
      ),
    );
    if (choice == null) return;
    String? id;
    if (choice == 1) id = await _pickGoogleCalendarDialog();
    else id = await _createCustomCalendarDialog();
    if (id == null) return;
    bool? ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('已選擇日曆'),
      content: Text('將寫入：$_rosterCalendarName\nID: $id'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('稍後')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('立即同步'))
      ]
    ));
    if (ok == true) {
      setState(() => googleSyncEnabled = true);
      await _syncToGoogle();
      save();
    }
  }

  Future<void> _ensureCalendar() async {
    if (_rosterCalendarId != null && _rosterCalendarId!.isNotEmpty) return;
    await _pickGoogleCalendarDialog();
  }

  void _markDirty(String dateKey) { _dirtyDates.add(dateKey); }

  DateTime _calcScanStart() {
    int currentYear = DateTime.now().year;
    int minYear = currentYear - 2;
    if (roster.isNotEmpty) {
      for (String k in roster.keys) {
        if (k.length >= 4) {
          int? y = int.tryParse(k.substring(0, 4));
          if (y != null && y - 1 < minYear) minYear = y - 1;
        }
      }
    }
    if (minYear < 2000) minYear = 2000;
    return DateTime(minYear, 1, 1);
  }

  DateTime _calcScanEnd() {
    int currentYear = DateTime.now().year;
    int maxYear = currentYear + 2;
    if (roster.isNotEmpty) {
      for (String k in roster.keys) {
        if (k.length >= 4) {
          int? y = int.tryParse(k.substring(0, 4));
          if (y != null && y + 1 > maxYear) maxYear = y + 1;
        }
      }
    }
    return DateTime(maxYear, 12, 31);
  }

  Map<String, String>? _parseShiftFromDesc(String? desc, {String? title}) {
    try {
      if (desc != null && desc.isNotEmpty) {
        // 純記事事件沒有班次信息
        if (desc.contains('類型: 純記事')) return null;

        final shiftMatch = RegExp(r'班次:\s*(\S+)').firstMatch(desc);
        if (shiftMatch != null) {
          final code = shiftMatch.group(1)?.trim() ?? '';
          if (code.isNotEmpty) {
            final timeMatch = RegExp(r'時間:\s*(\d{1,2}:\d{2})-(\d{1,2}:\d{2})').firstMatch(desc);
            if (timeMatch != null) {
              return {
                'code': code,
                'start': _padTime(timeMatch.group(1)!),
                'end': _padTime(timeMatch.group(2)!),
              };
            }
            if (desc.contains('類型: 全天') || desc.contains('全天')) {
              return {'code': code, 'start': '全天', 'end': '全天'};
            }
          }
        }
      }

      if (title != null && title.trim().isNotEmpty) {
        String t = title.trim();
        final pipeIdx = t.indexOf(' | ');
        if (pipeIdx >= 0) t = t.substring(0, pipeIdx).trim();

        // 支援新格式 "T 碼頭早更 07:00-15:30" 與舊格式 "T 07:00-15:30"
        final m = RegExp(r'^(\S+)\s+.*?(\d{1,2}:\d{2})-(\d{1,2}:\d{2})').firstMatch(t);
        if (m != null) {
          return {
            'code': m.group(1)!,
            'start': _padTime(m.group(2)!),
            'end': _padTime(m.group(3)!),
          };
        }

        final s = RegExp(r'^(\S+)').firstMatch(t);
        if (s != null) {
          return {'code': s.group(1)!, 'start': '全天', 'end': '全天'};
        }
      }
    } catch (_) {}
    return null;
  }

  String _padTime(String t) {
    final parts = t.split(':');
    if (parts.length != 2) return t;
    final h = parts[0].padLeft(2, '0');
    final m = parts[1].padLeft(2, '0');
    return '$h:$m';
  }

  Future<bool> _buildAndInsertEvent(String dateKey, String code, Duration offset, {String? existingEventId}) async {
    final calId = _requireCalendarId();
    final def = defs[code];
    final date = DateTime.parse(dateKey);
    final note = rosterNote[dateKey] ?? '';
    final tag = '[RosterPro]$dateKey';

    // 純記事（無班次）
    if (def == null) {
      if (note.isEmpty) {
        await _writeDebugLog('[createEvent] ❌ 無班次且無記事: $dateKey');
        return false;
      }
      final desc = '$tag\n$customName\n類型: 純記事\n記事: $note';
      final title = '📝 $note';
      final ev = Event(calId, eventId: existingEventId, title: title, description: desc,
        start: tz.TZDateTime(tz.local, date.year, date.month, date.day, 0, 0, 0),
        end: tz.TZDateTime(tz.local, date.year, date.month, date.day, 23, 59, 59),
        allDay: true);
      try {
        final res = await _calendarPlugin.createOrUpdateEvent(ev);
        if (res == null || !res.isSuccess || res.data == null) {
          await _writeDebugLog('[createEvent] ❌ $dateKey 純記事建立失敗');
          return false;
        }
        _googleEventIdMap[dateKey] = res.data!;
        await _writeDebugLog('[createEvent] ✅ $dateKey 純記事 → eventId=${res.data}');
        return true;
      } catch (e) {
        await _writeDebugLog('[createEvent] ❌ $dateKey 純記事例外: $e');
        return false;
      }
    }

    // 有班次
    final allDayFlag = def.isAllDay || def.code == 'O';
    String desc, title;
    if (allDayFlag) {
      desc = '$tag\n$customName\n班次: ${def.code} ${def.label}\n類型: 全天${note.isNotEmpty ? '\n記事: $note' : ''}';
      title = '${def.code} ${def.label}${note.isNotEmpty ? ' | $note' : ''}';
    } else {
      desc = '$tag\n$customName\n班次: ${def.code} ${def.label}\n時間: ${def.start}-${def.end}${note.isNotEmpty ? '\n記事: $note' : ''}';
      title = '${def.code} ${def.label} ${def.start}-${def.end}${note.isNotEmpty ? ' | $note' : ''}';
    }

    Event ev;
    if (allDayFlag) {
      ev = Event(calId, eventId: existingEventId, title: title, description: desc,
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
      ev = Event(calId, eventId: existingEventId, title: title, description: desc,
        start: tz.TZDateTime.utc(sUtc.year, sUtc.month, sUtc.day, sUtc.hour, sUtc.minute),
        end: tz.TZDateTime.utc(eUtc.year, eUtc.month, eUtc.day, eUtc.hour, eUtc.minute),
        allDay: false);
    }

    try {
      final res = await _calendarPlugin.createOrUpdateEvent(ev);
      if (res == null) {
        await _writeDebugLog('[createEvent] ❌ $dateKey res 為 null');
        return false;
      }
      if (!res.isSuccess) {
        await _writeDebugLog('[createEvent] ❌ $dateKey 失敗: ${res.toString()}');
        return false;
      }
      if (res.data == null) {
        await _writeDebugLog('[createEvent] ❌ $dateKey 成功但 eventId 為 null');
        return false;
      }
      _googleEventIdMap[dateKey] = res.data!;
      await _writeDebugLog('[createEvent] ✅ $dateKey → eventId=${res.data} (existing=$existingEventId)');
      return true;
    } catch (e) {
      await _writeDebugLog('[createEvent] ❌ $dateKey 例外: $e');
      return false;
    }
  }

  Future<void> _syncNow() async {
    if (!googleSyncEnabled) return;
    await _syncToGoogle(silent: true);
  }

  Future<void> syncDateRange() async {
    if (!googleSyncEnabled) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請先啟用日曆同步')));
      return;
    }
    DateTimeRange? range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 30, 12, 31),
      helpText: '選擇要同步的日期範圍',
      saveText: '同步',
    );
    if (range == null) return;
    Set<String> inRange = <String>{};
    DateTime cur = DateTime(range.start.year, range.start.month, range.start.day);
    DateTime last = DateTime(range.end.year, range.end.month, range.end.day);
    while (!cur.isAfter(last)) {
      String k = DateFormat('yyyy-MM-dd').format(cur);
      if (_dirtyDates.contains(k)) inRange.add(k);
      cur = cur.add(const Duration(days: 1));
    }
    if (inRange.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('所選範圍內沒有變更需要同步'), duration: Duration(seconds: 3)));
      return;
    }
    if (!await _confirmAction()) return;
    Set<String> others = Set<String>.from(_dirtyDates)..removeAll(inRange);
    _dirtyDates = inRange;
    await _syncToGoogle(silent: false);
    _dirtyDates.addAll(others);
    var sp = await SharedPreferences.getInstance();
    await sp.setStringList('dirtyDates', _dirtyDates.toList());
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
    if (_isSyncing) {
      await _writeDebugLog('[同步] 已在同步中，略過此次請求');
      return;
    }

    if (_rosterCalendarId == null || _rosterCalendarId!.isEmpty) {
      await _writeDebugLog('[同步] 尚未選擇日曆，中止');
      if (mounted && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ 尚未選擇日曆')));
      }
      if (!silent) await _ensureCalendar();
      if (_rosterCalendarId == null || _rosterCalendarId!.isEmpty) return;
    }

    bool needFull = forceFullSync || _needsFullSync;

    if (!needFull && _dirtyDates.isEmpty && rosterNote.isEmpty) {
      await _writeDebugLog('[同步] 沒有變更 (dirtyDates 為空)');
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('沒有變更需要同步'), duration: Duration(seconds: 2)));
      }
      return;
    }

    _isSyncing = true;
    _autoSyncTimer?.cancel();
    await _writeDebugLog('[同步] ====== 開始同步 ====== calId=$_rosterCalendarId needFull=$needFull dirtyCount=${_dirtyDates.length}');

    try {
      final calId = _requireCalendarId();
      final sp = await SharedPreferences.getInstance();
      final offset = DateTime.now().timeZoneOffset;
      int del = 0, delFailed = 0, add = 0, upd = 0;
      int zombieFixed = 0;

      if (needFull) {
        await _writeDebugLog('[同步] 全量重建：分批掃描清理 [RosterPro]');

        final Set<String> deletedIds = <String>{};
        for (int year = 2000; year <= 2100; year++) {
          DateTime startScan = DateTime(year, 1, 1);
          DateTime endScan = DateTime(year, 12, 31);

          List<Event> events = [];
          try {
            events = await _safeRetrieveEvents(startScan, endScan);
          } catch (e) {
            await _writeDebugLog('[同步] ⚠️ 掃描 $year 年失敗，跳過該年：$e');
            continue;
          }

          for (var e in events) {
            final desc = e.description ?? '';
            if (!desc.contains('[RosterPro]')) continue;
            if (e.eventId == null) continue;
            if (deletedIds.contains(e.eventId)) continue;

            final ok = await _safeDeleteEvent(e.eventId!);
            if (ok) { deletedIds.add(e.eventId!); del++; } else { delFailed++; }
          }
        }

        _googleEventIdMap.clear();

        // 建立所有排班事件
        for (var entry in roster.entries) {
          final added = await _buildAndInsertEvent(entry.key, entry.value, offset, existingEventId: null);
          if (added) add++;
        }
        // 建立所有純記事事件（無排班但有記事）
        for (var dateKey in rosterNote.keys) {
          if (!roster.containsKey(dateKey) && rosterNote[dateKey]!.isNotEmpty) {
            final added = await _buildAndInsertEvent(dateKey, '', offset, existingEventId: null);
            if (added) add++;
          }
        }

        _needsFullSync = false;
        _dirtyDates.clear();

        sp.setString('googleEventIdMap', jsonEncode(_googleEventIdMap));
        await sp.setStringList('dirtyDates', _dirtyDates.toList());
        await sp.setBool('needsFullSync', _needsFullSync);
        updateWidget();

        await _writeDebugLog('[同步] ====== 全量重建完成 del=$del delFailed=$delFailed add=$add ======');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('✅ 完整同步完成：刪 $del / 失敗 $delFailed / 建立 $add'),
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ));
        }
        return;
      } else {
        if (_googleEventIdMap.isEmpty) {
          await _writeDebugLog('[同步] googleEventIdMap 為空，開始掃描現有日曆事件');
          DateTime scanStart = _calcScanStart();
          DateTime scanEnd = _calcScanEnd();
          try {
            var existingEvents = await _safeRetrieveEvents(scanStart, scanEnd);
            if (existingEvents.isNotEmpty) {
              for (var e in existingEvents) {
                if (e.description != null && e.description!.contains('[RosterPro]')) {
                  RegExp regExp = RegExp(r'\[RosterPro\](\d{4}-\d{2}-\d{2})');
                  var match = regExp.firstMatch(e.description!);
                  if (match != null && e.eventId != null) {
                    _googleEventIdMap[match.group(1)!] = e.eventId!;
                  }
                }
              }
            }
            await _writeDebugLog('[同步] 掃描完成，共找到 ${_googleEventIdMap.length} 條現有事件');
          } catch (e) {
            await _writeDebugLog('[同步] ⚠️ 掃描重建失敗，保留現有 map：$e');
          }
        }

        // ====== 修改重點：確保排班開始前的純記事也能被同步 ======
        // 原本的 datesToSync 只包含 _dirtyDates，會漏掉早期未編輯過的純記事。
        // 這裡強制掃描所有 rosterNote 中，尚未在日曆中建立事件（不在 _googleEventIdMap 中）的日期。
        final Set<String> syncSet = <String>{};
        syncSet.addAll(_dirtyDates);
        for (var noteKey in rosterNote.keys) {
          if (rosterNote[noteKey]!.isNotEmpty && !_googleEventIdMap.containsKey(noteKey)) {
            syncSet.add(noteKey);
          }
        }
        final datesToSync = syncSet.toList()..sort();
        // =========================================================

        await _writeDebugLog('[同步] 增量同步：待處理 ${datesToSync.length} 天 → $datesToSync');

        for (var dateKey in datesToSync) {
          DateTime date = DateTime.parse(dateKey);
          DateTime queryStart = DateTime(date.year, date.month, date.day, 0, 0, 0).subtract(const Duration(hours: 24));
          DateTime queryEnd = DateTime(date.year, date.month, date.day, 23, 59, 59).add(const Duration(hours: 24));

          List<Event> eventsInRange;
          try {
            eventsInRange = await _safeRetrieveEvents(queryStart, queryEnd);
          } catch (e) {
            await _writeDebugLog('[同步] ⚠️ $dateKey 查詢失敗，跳過該天並保留 dirty：$e');
            continue;
          }

          List<Event> rosterEvents = eventsInRange.where((e) {
            final desc = e.description ?? '';
            if (desc.contains('[RosterPro]')) {
              final m = RegExp(r'\[RosterPro\](\d{4}-\d{2}-\d{2})').firstMatch(desc);
              return m == null || m.group(1) == dateKey;
            }
            final title = (e.title ?? '').trim();
            if (title.isEmpty) return false;
            final eDateKey = e.start != null ? DateFormat('yyyy-MM-dd').format(e.start!.toLocal()) : null;
            if (eDateKey != dateKey) return false;
            String t = title.contains(' | ') ? title.split(' | ')[0].trim() : title;
            if (RegExp(r'^\S+\s+.*?\d{1,2}:\d{2}-\d{1,2}:\d{2}').hasMatch(t)) return true;
            return RegExp(r'^\S+$').hasMatch(t);
          }).toList();

          // 沒有排班
          if (!roster.containsKey(dateKey)) {
            final hasNote = rosterNote.containsKey(dateKey) && rosterNote[dateKey]!.isNotEmpty;
            if (hasNote) {
              // 只保留/建立純記事事件，刪除班次事件
              String? matchedEventId;
              for (var e in rosterEvents) {
                if (e.eventId == null) continue;
                final desc = e.description ?? '';
                if (desc.contains('類型: 純記事')) {
                  if (matchedEventId == null) {
                    matchedEventId = e.eventId;
                  } else {
                    final ok = await _safeDeleteEvent(e.eventId!);
                    if (ok) del++; else delFailed++;
                  }
                } else {
                  final ok = await _safeDeleteEvent(e.eventId!);
                  if (ok) del++; else delFailed++;
                }
              }
              final updated = await _buildAndInsertEvent(dateKey, '', offset, existingEventId: matchedEventId);
              if (updated) {
                upd++;
                if (matchedEventId != null) _googleEventIdMap[dateKey] = matchedEventId;
              }
              _dirtyDates.remove(dateKey);
              continue;
            } else {
              for (var e in rosterEvents) {
                if (e.eventId != null) {
                  final ok = await _safeDeleteEvent(e.eventId!);
                  if (ok) del++; else delFailed++;
                }
              }
              _googleEventIdMap.remove(dateKey);
              _dirtyDates.remove(dateKey);
              continue;
            }
          }

          // 有排班
          final newCode = roster[dateKey]!;
          final newDef = defs[newCode];
          if (newDef == null) { _dirtyDates.remove(dateKey); continue; }
          final isAllDayNow = newDef.isAllDay || newDef.code == 'O';
          final newStart = isAllDayNow ? '全天' : newDef.start;
          final newEnd = isAllDayNow ? '全天' : newDef.end;

          String? matchedEventId = _googleEventIdMap[dateKey];
          if (matchedEventId != null) {
            final stillExists = rosterEvents.any((e) => e.eventId == matchedEventId);
            if (!stillExists) {
              await _writeDebugLog('[同步] ⚠️ eventId=$matchedEventId 已被外部刪除 (dateKey=$dateKey)，清除記錄並改為新建');
              _googleEventIdMap.remove(dateKey);
              matchedEventId = null;
              zombieFixed++;
            }
          }

          for (var e in rosterEvents) {
            if (e.eventId == null) continue;
            if (e.eventId == matchedEventId) continue;

            final parsed = _parseShiftFromDesc(e.description, title: e.title);
            final isMatch = parsed != null && parsed['code'] == newCode && parsed['start'] == newStart && parsed['end'] == newEnd;

            if (isMatch && matchedEventId == null) {
              matchedEventId = e.eventId;
            } else {
              final ok = await _safeDeleteEvent(e.eventId!);
              if (ok) del++; else delFailed++;
            }
          }

          if (matchedEventId != null) {
            final updated = await _buildAndInsertEvent(dateKey, newCode, offset, existingEventId: matchedEventId);
            if (updated) { upd++; _googleEventIdMap[dateKey] = matchedEventId; }
            else {
              final added = await _buildAndInsertEvent(dateKey, newCode, offset);
              if (added) { add++; upd++; }
            }
          } else {
            final added = await _buildAndInsertEvent(dateKey, newCode, offset);
            if (added) { add++; upd++; }
          }
          _dirtyDates.remove(dateKey);
        }
      }

      sp.setString('googleEventIdMap', jsonEncode(_googleEventIdMap));
      await sp.setStringList('dirtyDates', _dirtyDates.toList());
      await sp.setBool('needsFullSync', _needsFullSync);
      updateWidget();

      await _writeDebugLog('[同步] ====== 同步完成 del=$del delFailed=$delFailed add=$add upd=$upd zombieFixed=$zombieFixed ======');

      if (mounted) {
        String msg = needFull
            ? '✅ 完整同步完成：刪 $del / 失敗 $delFailed / 建立 $add'
            : '✅ 已同步：刪 $del / 失敗 $delFailed / 更新 $upd / 建立 $add';
        if (zombieFixed > 0) {
          msg += ' / 修復僵屍 $zombieFixed';
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      await _writeDebugLog('[同步] ❌ 同步失敗: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('❌ 同步失敗：$e'),
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      _isSyncing = false;
    }
  }
  Future<void> _forceCleanDuplicates() async {
  if (_isSyncing) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在同步中，請稍候...')));
    return;
  }
  if (_rosterCalendarId == null || _rosterCalendarId!.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('尚未選擇日曆')));
    return;
  }
  bool? confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
    title: const Text('⚠️ 強制清理重複事件'),
    content: const Text('這會逐日掃描 [RosterPro] 事件：\n• 可解析的：按（代號+開始+結束）分組，每組保留 1 條\n• 無法解析的殘留：若該日已有可解析事件，全部刪除\n\n確定要執行嗎？'),
    actions: [
      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
      FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('確定清理'))
    ]
  ));
  if (confirm != true) return;
  if (_isSyncing) return;
  if (!await _confirmAction()) return;

  _isSyncing = true;
  final calId = _requireCalendarId();

  final ValueNotifier<double> progressNotifier = ValueNotifier(0.0);
  final ValueNotifier<String> statusNotifier = ValueNotifier('正在準備掃描...');

  BuildContext? loadingCtx;
  if (mounted) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        loadingCtx = ctx;
        return PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Text('清理進行中'),
            content: ValueListenableBuilder<double>(
              valueListenable: progressNotifier,
              builder: (context, progress, child) {
                return ValueListenableBuilder<String>(
                  valueListenable: statusNotifier,
                  builder: (context, status, child) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LinearProgressIndicator(value: progress <= 0 ? null : progress),
                        const SizedBox(height: 16),
                        Text(status, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        if (progress > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text('${(progress * 100).toStringAsFixed(1)}%', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  int cleaned = 0;
  int scannedDates = 0;
  int matchedDatesWithDup = 0;
  try {
    await _writeDebugLog('===== 開始強制清理重複（逐日掃描）calId=$calId =====');

    final Set<String> allKeys = <String>{};
    allKeys.addAll(roster.keys);
    allKeys.addAll(rosterNote.keys);
    allKeys.addAll(_googleEventIdMap.keys);
    final List<String> sortedKeys = allKeys.toList()..sort();

    if (sortedKeys.isEmpty) {
      statusNotifier.value = '沒有可掃描的日期';
      await _writeDebugLog('沒有可掃描的日期');
    } else {
      int total = sortedKeys.length;
      int current = 0;

      for (var dateKey in sortedKeys) {
        current++;
        progressNotifier.value = current / total;
        statusNotifier.value = '正在掃描 ($current/$total)：$dateKey';
        scannedDates++;

        DateTime date;
        try { date = DateTime.parse(dateKey); } catch (_) { continue; }
        DateTime startOfDay = DateTime(date.year, date.month, date.day, 0, 0, 0)
            .subtract(const Duration(hours: 24));
        DateTime endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59);

        List<Event> eventsOnDay;
        try {
          eventsOnDay = await _safeRetrieveEvents(startOfDay, endOfDay);
        } catch (e) {
          await _writeDebugLog('[強制清理] $dateKey 查詢失敗，跳過該天：$e');
          continue;
        }

        List<Event> rosterEvents = eventsOnDay.where((e) {
          final desc = e.description ?? '';
          if (!desc.contains('[RosterPro]')) return false;
          final m = RegExp(r'\[RosterPro\](\d{4}-\d{2}-\d{2})').firstMatch(desc);
          return m == null || m.group(1) == dateKey;
        }).toList();

        if (rosterEvents.length <= 1) continue;

        await _writeDebugLog('【$dateKey】查到 ${rosterEvents.length} 條 [RosterPro] 事件 (calId=$calId)');

        Map<String, List<Event>> byKey = {};
        List<Event> unparsed = [];
        for (var e in rosterEvents) {
          final parsed = _parseShiftFromDesc(e.description, title: e.title);
          if (parsed == null) {
            unparsed.add(e);
          } else {
            final key = '${parsed['code']}|${parsed['start']}|${parsed['end']}';
            byKey.putIfAbsent(key, () => []).add(e);
          }
        }

        bool hadDup = false;
        int parsedGroupCount = 0;

        for (var entry in byKey.entries) {
          parsedGroupCount++;
          if (entry.value.length <= 1) continue;
          hadDup = true;
          for (int i = 1; i < entry.value.length; i++) {
            final ev = entry.value[i];
            if (ev.eventId != null) {
              final ok = await _safeDeleteEvent(ev.eventId!);
              if (ok) cleaned++;
            }
          }
        }

        if (unparsed.isNotEmpty) {
          if (parsedGroupCount > 0) {
            for (var ev in unparsed) {
              if (ev.eventId != null) {
                final ok = await _safeDeleteEvent(ev.eventId!);
                if (ok) { cleaned++; hadDup = true; }
              }
            }
          } else if (unparsed.length > 1) {
            for (int i = 1; i < unparsed.length; i++) {
              final ev = unparsed[i];
              if (ev.eventId != null) {
                final ok = await _safeDeleteEvent(ev.eventId!);
                if (ok) { cleaned++; hadDup = true; }
              }
            }
          }
        }

        if (hadDup) matchedDatesWithDup++;
      }

      await _writeDebugLog('===== 清理完成: calId=$calId 掃描 $scannedDates 天, 有重複 $matchedDatesWithDup 天, 共刪 $cleaned 條 =====');
    }

    _needsFullSync = false;
    statusNotifier.value = '清理完成，正在同步最新狀態...';
    progressNotifier.value = 1.0;
    await _syncToGoogle(silent: true, forceFullSync: false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('清理完成：掃描 $scannedDates 天，有重複 $matchedDatesWithDup 天，共刪除 $cleaned 條'),
        duration: const Duration(seconds: 5),
      ));
    }
  } catch (e) {
    await _writeDebugLog('強制清理失敗: $e');
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('清理失敗 $e')));
  } finally {
    _isSyncing = false;
    final ctx = loadingCtx;
    if (ctx != null && ctx.mounted) {
      Navigator.pop(ctx);
    }
  }
}

Future<void> _purgeRosterProInRange() async {
  if (_isSyncing) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在同步中，請稍候...')));
    return;
  }
  if (_rosterCalendarId == null || _rosterCalendarId!.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('尚未選擇日曆')));
    return;
  }

  DateTimeRange? range = await showDateRangePicker(
    context: context,
    firstDate: DateTime(2020),
    lastDate: DateTime(DateTime.now().year + 30, 12, 31),
    helpText: '選擇要清除 [RosterPro] 事件的日期範圍',
  );
  if (range == null) return;

  bool? confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
    title: const Text('⚠️ 清除範圍內所有排班事件'),
    content: Text('這會刪除 ${DateFormat('yyyy-MM-dd').format(range.start)} ~ ${DateFormat('yyyy-MM-dd').format(range.end)} 範圍內所有帶 [RosterPro] 標籤的事件。\n\n✅ App 排班資料不受影響\n✅ 之後會自動重新同步\n\n確定要執行嗎？'),
    actions: [
      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
      FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('確定清除'))
    ]
  ));
  if (confirm != true) return;
  if (_isSyncing) return;
  if (!await _confirmAction()) return;

  _isSyncing = true;
  final calId = _requireCalendarId();

  final ValueNotifier<double> progressNotifier = ValueNotifier(0.0);
  final ValueNotifier<String> statusNotifier = ValueNotifier('正在準備掃描...');

  BuildContext? loadingCtx;
  if (mounted) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        loadingCtx = ctx;
        return PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Text('清除進行中'),
            content: ValueListenableBuilder<double>(
              valueListenable: progressNotifier,
              builder: (context, progress, child) {
                return ValueListenableBuilder<String>(
                  valueListenable: statusNotifier,
                  builder: (context, status, child) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LinearProgressIndicator(value: progress <= 0 ? null : progress),
                        const SizedBox(height: 16),
                        Text(status, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        if (progress > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text('${(progress * 100).toStringAsFixed(1)}%', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  int deletedCount = 0;
  int scannedDates = 0;
  try {
    await _writeDebugLog('===== 開始按範圍清除 [RosterPro] calId=$calId =====');

    List<String> dateKeys = [];
    DateTime cur = DateTime(range.start.year, range.start.month, range.start.day);
    DateTime last = DateTime(range.end.year, range.end.month, range.end.day);
    while (!cur.isAfter(last)) {
      dateKeys.add(DateFormat('yyyy-MM-dd').format(cur));
      cur = cur.add(const Duration(days: 1));
    }

    int total = dateKeys.length;
    int current = 0;
    final Set<String> alreadyDeletedIds = <String>{};

    for (var dateKey in dateKeys) {
      current++;
      progressNotifier.value = current / total;
      statusNotifier.value = '正在掃描 ($current/$total)：$dateKey';
      scannedDates++;

      DateTime date;
      try { date = DateTime.parse(dateKey); } catch (_) { continue; }
      DateTime startOfDay = DateTime(date.year, date.month, date.day, 0, 0, 0)
          .subtract(const Duration(hours: 24));
      DateTime endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59);

      List<Event> eventsOnDay;
      try {
        eventsOnDay = await _safeRetrieveEvents(startOfDay, endOfDay);
      } catch (e) {
        await _writeDebugLog('[按範圍清除] $dateKey 查詢失敗，跳過該天：$e');
        continue;
      }

      final Map<String, Event> toDelete = {};
      for (var e in eventsOnDay) {
        final desc = e.description ?? '';
        if (!desc.contains('[RosterPro]')) continue;
        if (e.eventId == null) continue;
        if (alreadyDeletedIds.contains(e.eventId)) continue;

        final m = RegExp(r'\[RosterPro\](\d{4}-\d{2}-\d{2})').firstMatch(desc);
        if (m != null && m.group(1) != dateKey) continue;

        toDelete[e.eventId!] = e;
      }

      for (var ev in toDelete.values) {
        final ok = await _safeDeleteEvent(ev.eventId!);
        if (ok) {
          alreadyDeletedIds.add(ev.eventId!);
          deletedCount++;
        }
      }
    }

    await _writeDebugLog('===== 完成: calId=$calId 掃描 $scannedDates 天, 共刪 $deletedCount 條 =====');

    _googleEventIdMap.clear();
    final sp = await SharedPreferences.getInstance();
    await sp.setString('googleEventIdMap', jsonEncode(_googleEventIdMap));

    statusNotifier.value = '清除完成，正在重新同步...';
    progressNotifier.value = 1.0;

    await _syncToGoogle(silent: true, forceFullSync: false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('清除完成：掃描 $scannedDates 天，共刪除 $deletedCount 條 [RosterPro] 事件'),
        duration: const Duration(seconds: 5),
      ));
    }
  } catch (e) {
    await _writeDebugLog('清除失敗: $e');
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('清除失敗 $e')));
  } finally {
    _isSyncing = false;
    final ctx = loadingCtx;
    if (ctx != null && ctx.mounted) {
      Navigator.pop(ctx);
    }
  }
}

Future<void> _forceFullResync() async {
  if (_isSyncing) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在同步中，請稍候...')));
    return;
  }

  if (_rosterCalendarId == null || _rosterCalendarId!.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('尚未選擇日曆')));
    return;
  }

  if (roster.isEmpty && rosterNote.isEmpty) {
    bool? stillProceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('⚠️ 排班資料為空'),
        content: const Text('目前 App 內沒有任何排班資料。\n\n「全清重建」會刪除掃描範圍內所有 [RosterPro] 事件，然後因為沒排班資料可重建，結果就是日曆變空。\n\n確定要執行嗎？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('仍要執行'),
          ),
        ],
      ),
    );
    if (stillProceed != true) return;
  }

  bool? confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
    title: const Text('⚠️ 全清重建確認'),
    content: const Text('這會掃描範圍內所有帶 [RosterPro] 的事件並刪除，然後根據 App 排班重新建立。\n\n掃描範圍：\n• App 排班有資料的所有日期\n• 2000年 ~ 2100年（強制）\n\n✅ App 排班資料不受影響\n✅ 你其他 Google 行程不會被刪除\n✅ 只會影響選定日曆\n\n確定要執行嗎？'),
    actions: [
      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
      FilledButton(
        onPressed: () => Navigator.pop(ctx, true),
        style: FilledButton.styleFrom(backgroundColor: Colors.red),
        child: const Text('確定執行'),
      ),
    ]
  ));
  if (confirm != true) return;
  if (_isSyncing) return;
  if (!await _confirmAction()) return;
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
      if (j['carryAnchorWeekKey'] != null) carryAnchorWeekKey = j['carryAnchorWeekKey'];
      if (j['cName'] != null) { customName = j['cName']; nameCtrl.text = customName; }
      if (j['stdWeek'] != null) standardWeeklyHours = (j['stdWeek'] as num).toDouble();
      if (j['otRate'] != null) overtimeRate = (j['otRate'] as num).toDouble();
      if (j['monthlySalary'] != null) monthlySalary = (j['monthlySalary'] as num).toDouble();
      if (j['hourlyDivisor'] != null) hourlyDivisor = (j['hourlyDivisor'] as num).toDouble();
      if (j['otMultiplier'] != null) otMultiplier = (j['otMultiplier'] as num).toDouble();
      if (j['morningAllow'] != null) morningAllowance = (j['morningAllow'] as num).toDouble();
      if (j['nightAllow'] != null) nightAllowance = (j['nightAllow'] as num).toDouble();
      if (j['mealAllow'] != null) mealAllowance = (j['mealAllow'] as num).toDouble();
      if (j['nightAllowMultiplier'] != null) nightAllowMultiplier = (j['nightAllowMultiplier'] as num).toDouble();
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
      if (j['widgetBgColor'] != null) widgetBgColor = j['widgetBgColor'];
      if (j['iconIndex'] != null) iconIndex = j['iconIndex'];
      if (j['leaveDefs'] != null) leaveDefs = (j['leaveDefs'] as List).map((e) => LeaveDef.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      if (j['leaveRecords'] != null) leaveRecords = Map<String, Map<String, dynamic>>.from((j['leaveRecords'] as Map).map((k, v) => MapEntry(k as String, Map<String, dynamic>.from(v as Map))));
      if (j['rosterLeave'] != null) rosterLeave = Map<String, String>.from(j['rosterLeave']);
      if (j['rosterAlarmMuted'] != null) rosterAlarmMuted = Map<String, bool>.from(j['rosterAlarmMuted']);
    });

    _needsFullSync = false;
    _ensureAnchorWeek();

    _dirtyDates.clear();
    for (var key in roster.keys) {
      _dirtyDates.add(key);
    }
    for (var key in rosterNote.keys) {
      _dirtyDates.add(key);
    }

    await save();

    if (googleSyncEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('還原成功，正在增量同步至 Google 日曆...'),
          duration: Duration(seconds: 3),
        ));
      }
      await Future.delayed(const Duration(milliseconds: 800));
      await _syncToGoogle(forceFullSync: false, silent: false);
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
  if (!await _confirmAction()) return;
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
                if (!await _confirmAction()) return;
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

Future<void> showExportListManager() async {
  final dirPath = await _getBackupDir();
  final dir = Directory(dirPath);
  if (!await dir.exists()) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('沒有匯出檔案'))); return; }
  List<FileSystemEntity> entities = dir.listSync();
  List<File> files = entities.whereType<File>().where((f) => f.path.endsWith('.csv') || f.path.endsWith('.json')).toList();
  files.sort((a, b) => b.path.compareTo(a.path));
  if (files.isEmpty) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('沒有匯出檔案'))); return; }
  Map<String, List<File>> categorized = {};
  for (var f in files) {
    String name = f.path.split('/').last;
    String cat = '其他';
    if (name.startsWith('report_')) cat = '報表';
    else if (name.startsWith('leaves_')) cat = '假期清單';
    else if (name.startsWith('notes_')) cat = '記事清單';
    else if (name.startsWith('roster_pro_')) cat = '備份檔案';
    categorized.putIfAbsent(cat, () => []).add(f);
  }
  Set<String> selectedPaths = <String>{};
  bool multiSelectMode = false;
  await showDialog(context: context, builder: (ctx) {
    return StatefulBuilder(builder: (ctx2, setD) {
      return AlertDialog(
        title: Text(multiSelectMode ? '已選 ${selectedPaths.length} 個' : '匯出清單管理 (${files.length})'),
        content: SizedBox(width: 550, height: 550, child: Column(children: [
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Text('目錄: $dirPath', style: const TextStyle(fontSize: 10))),
          const SizedBox(height: 8),
          Expanded(child: ListView(
            children: categorized.entries.map((entry) {
              return ExpansionTile(
                title: Text('${entry.key} (${entry.value.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
                initiallyExpanded: true,
                children: entry.value.map((f) {
                  final name = f.path.split('/').last;
                  final sizeKB = (f.statSync().size / 1024).toStringAsFixed(1);
                  final isSelected = selectedPaths.contains(f.path);
                  return ListTile(
                    dense: true,
                    leading: multiSelectMode ? Checkbox(value: isSelected, onChanged: (v) { setD(() { if (v == true) selectedPaths.add(f.path); else selectedPaths.remove(f.path); }); }) : const Icon(Icons.insert_drive_file, size: 20),
                    title: Text(name, style: const TextStyle(fontSize: 12)),
                    subtitle: Text('${sizeKB} KB', style: const TextStyle(fontSize: 10)),
                    onTap: () async {
                      if (multiSelectMode) {
                        setD(() { if (isSelected) selectedPaths.remove(f.path); else selectedPaths.add(f.path); });
                      } else {
                        try { await OpenFilex.open(f.path); } catch (e) { await Share.shareXFiles([XFile(f.path)], text: '開啟檔案: $name'); }
                      }
                    },
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(icon: const Icon(Icons.share, size: 18, color: Colors.blue), onPressed: () async {
                        try { await Share.shareXFiles([XFile(f.path)], text: '分享檔案: $name'); } catch (_) {}
                      }),
                      IconButton(icon: const Icon(Icons.delete, size: 18, color: Colors.red), onPressed: () async {
                        bool? c = await showDialog<bool>(context: context, builder: (c2) => AlertDialog(
                          title: const Text('確認刪除'),
                          content: Text('刪除 $name ？'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(c2, false), child: const Text('取消')),
                            FilledButton(onPressed: () => Navigator.pop(c2, true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('刪除')),
                          ],
                        ));
                        if (c == true) { try { await f.delete(); setD(() { files.remove(f); }); } catch (_) {} }
                      }),
                    ]),
                  );
                }).toList(),
              );
            }).toList(),
          )),
        ])),
        actions: [
          if (!multiSelectMode) TextButton(onPressed: () => setD(() => multiSelectMode = true), child: const Text('多選')),
          if (multiSelectMode) TextButton(onPressed: () async {
            if (selectedPaths.isEmpty) return;
            int deleted = 0;
            for (var p in selectedPaths) { try { await File(p).delete(); deleted++; } catch (_) {} }
            if (mounted) { Navigator.pop(ctx2); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已刪除 $deleted 個檔案'))); }
          }, child: const Text('刪除選中', style: TextStyle(color: Colors.red))),
          if (multiSelectMode) TextButton(onPressed: () async {
            if (selectedPaths.isEmpty) return;
            List<XFile> xFiles = selectedPaths.map((p) => XFile(p)).toList();
            try { await Share.shareXFiles(xFiles, text: '批量分享檔案'); } catch (_) {}
          }, child: const Text('批量分享', style: TextStyle(color: Colors.blue))),
          TextButton(onPressed: () { if (multiSelectMode) { setD(() { multiSelectMode = false; selectedPaths.clear(); }); } else { Navigator.pop(ctx2); } }, child: Text(multiSelectMode ? '取消多選' : '關閉')),
        ],
      );
    });
  });
}

Future<void> _showExportResultDialog(String path) async {
  String fileName = path.split('/').last;
  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Row(children: [Icon(Icons.check_circle, color: Colors.green), SizedBox(width: 8), Text('已完成匯出')]),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('檔案已成功匯出至：', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)), child: SelectableText(path, style: const TextStyle(fontSize: 12, color: Colors.blue))),
          const SizedBox(height: 8),
          Text('檔名：$fileName', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('關閉')),
        FilledButton(onPressed: () async { Navigator.pop(ctx); await Share.shareXFiles([XFile(path)], text: '分享檔案: $fileName'); }, child: const Text('分享檔案')),
      ],
    ),
  );
}

Future<void> showWidgetDebugLog() async {
  await _writeDebugLog('=== 手動觸發調試日誌 ===');
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
      'pattern': pattern, 'carry': carry,
      'carryAnchorWeekKey': carryAnchorWeekKey,
      'cName': customName,
      'stdWeek': standardWeeklyHours, 'otRate': overtimeRate,
      'monthlySalary': monthlySalary, 'hourlyDivisor': hourlyDivisor, 'otMultiplier': otMultiplier,
      'morningAllow': morningAllowance, 'nightAllow': nightAllowance, 'mealAllow': mealAllowance,
      'nightAllowMultiplier': nightAllowMultiplier,
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
      'widgetBgColor': widgetBgColor,
      'iconIndex': iconIndex,
      'leaveDefs': leaveDefs.map((e) => e.toJson()).toList(),
      'leaveRecords': leaveRecords,
      'rosterLeave': rosterLeave,
      'rosterAlarmMuted': rosterAlarmMuted,
    };
    var f = File('$dirPath/$fileName');
    await f.writeAsString(jsonEncode(backup));
    setState(() => _lastBackupPath = '$dirPath/$fileName');
    await save();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已備份: $fileName'), duration: const Duration(seconds: 3)));
      await _showExportResultDialog('$dirPath/$fileName');
    }
  } catch (e) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('備份失敗 $e')));
  }
}

Future<void> clearRosterByRange() async {
  if (_rosterCalendarId == null || _rosterCalendarId!.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('尚未選擇日曆')));
    return;
  }
  DateTimeRange? range = await showDateRangePicker(context: context, firstDate: DateTime(2023), lastDate: DateTime(DateTime.now().year + 30, 12, 31), helpText: '選擇要清除的排更範圍');
  if (range == null) return;
  if (!await _confirmAction()) return;

  final calId = _requireCalendarId();
  int count = 0;
  for (DateTime d = range.start; !d.isAfter(range.end); d = d.add(const Duration(days: 1))) {
    String k = DateFormat('yyyy-MM-dd').format(d);
    _markDirty(k);
    if (roster.containsKey(k) || rosterNote.containsKey(k)) {
      count++;
      roster.remove(k); rosterOt.remove(k); rosterExtra.remove(k); rosterExtraHrs.remove(k); rosterExtraType.remove(k); rosterLeave.remove(k); rosterAlarmMuted.remove(k); rosterNote.remove(k);
      if (_googleEventIdMap.containsKey(k)) {
        await _safeDeleteEvent(_googleEventIdMap[k]!);
        _googleEventIdMap.remove(k);
      }
    }
  }
  await _writeDebugLog('clearRosterByRange: calId=$calId 清除 $count 天');
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
      tp.text = TextSpan(text: ' ${v.code} ${v.label} ${v.isAllDay ? '全天' : '${v.start}-${v.end}'} ${v.hours.toStringAsFixed(1)}h${v.hasMorningAllow ? ' 早/夜班津貼' : ''}${v.hasNightAllow ? ' 通宵津貼' : ''}${v.hasMealAllow ? ' 膳食津貼' : ''}', style: const TextStyle(color: Colors.black87, fontSize: 28, fontWeight: FontWeight.w600));
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
      int year = focused.year;
      int month = focused.month;
      DateTime firstDayOfMonth = DateTime(year, month, 1);
      DateTime lastDayOfMonth = DateTime(year, month + 1, 0);
      DateTime calStart = firstDayOfMonth.subtract(Duration(days: firstDayOfMonth.weekday - 1));
      DateTime calEnd = lastDayOfMonth.add(Duration(days: 7 - lastDayOfMonth.weekday));

      DateTime calcStart = _effectiveCalcStart(calStart);

      Map<String, double> allWeeklyHours = {};
      DateTime tempDt = calcStart;
      while (!tempDt.isAfter(calEnd)) {
        String k = DateFormat('yyyy-MM-dd').format(tempDt);
        String? c = roster[k];
        if (c != null) {
          var d = defs[c];
          if (d != null) {
            String wk = isoWeekKey(tempDt);
            allWeeklyHours[wk] = (allWeeklyHours[wk] ?? 0) + d.hours;
          }
        }
        tempDt = tempDt.add(const Duration(days: 1));
      }

      List<String> sortedAllWeeks = allWeeklyHours.keys.toList()..sort();
      double lastCarryExport = carry;
      Map<String, double> weekCarryMap = {};
      Map<String, double> weekDiffMap = {};
      for (var wk in sortedAllWeeks) {
        double weekHours = allWeeklyHours[wk]!;
        weekCarryMap[wk] = lastCarryExport;
        double diff = lastCarryExport + weekHours - standardWeeklyHours;
        weekDiffMap[wk] = diff;
        lastCarryExport = diff;
      }

      Set<String> currentMonthWeeksSet = {};
      for (DateTime dt = calStart; !dt.isAfter(calEnd); dt = dt.add(const Duration(days: 1))) {
        currentMonthWeeksSet.add(isoWeekKey(dt));
      }

      double hrs = 0, ot = 0, allow = 0;
      SplayTreeMap<String, int> shiftCount = SplayTreeMap();
      SplayTreeMap<String, double> extraByType = SplayTreeMap();

      for (DateTime dt = firstDayOfMonth; !dt.isAfter(lastDayOfMonth); dt = dt.add(const Duration(days: 1))) {
        String k = DateFormat('yyyy-MM-dd').format(dt);
        String? c = roster[k];
        if (c == null) continue;
        var d = defs[c];
        if (d != null) {
          hrs += d.hours;
          shiftCount[c] = (shiftCount[c] ?? 0) + 1;
          if (d.hasMorningAllow) allow += morningAllowance;
          if (d.hasNightAllow) allow += nightAllowance * d.hours;
          if (d.hasMealAllow) allow += mealAllowance;
        }
        ot += (rosterOt[k] ?? d?.ot ?? 0);
        allow += (rosterExtra[k] ?? 0);
        if (rosterExtraType.containsKey(k) && rosterExtra.containsKey(k)) {
          extraByType[rosterExtraType[k]!] = (extraByType[rosterExtraType[k]!] ?? 0) + rosterExtra[k]!;
        }
        hrs += (rosterExtraHrs[k] ?? 0);
      }

      sb.writeln('========================================');
      sb.writeln('       ${focused.year}年${focused.month}月 排更報表');
      sb.writeln('========================================');
      sb.writeln('');
      sb.writeln('【一、班次統計】');
      sb.writeln('班次代號, 班次名稱, 次數, 總工時');
      double totalShiftHours = 0;
      shiftCount.forEach((k, v) {
        var d = defs[k];
        double h = (d?.hours ?? 0) * v;
        totalShiftHours += h;
        sb.writeln('$k, ${d?.label ?? k}, $v次, ${h.toStringAsFixed(1)}h');
      });
      sb.writeln('小計, , ${shiftCount.values.fold(0, (a, b) => a + b)}次, ${totalShiftHours.toStringAsFixed(1)}h');
      sb.writeln('');
      sb.writeln('【二、每週工時統計】');
      sb.writeln('週次, 本週工時, 標準工時, 承上餘額, 累計差額');

      for (var wk in sortedAllWeeks) {
        if (!currentMonthWeeksSet.contains(wk)) continue;
        double weekHours = allWeeklyHours[wk]!;
        double displayCarry = weekCarryMap[wk]!;
        double diff = weekDiffMap[wk]!;
        sb.writeln('$wk, ${weekHours.toStringAsFixed(1)}h, ${standardWeeklyHours}h, ${displayCarry.toStringAsFixed(1)}h, ${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(1)}h');
      }

      sb.writeln('');
      sb.writeln('【三、津貼類別統計】');
      sb.writeln('類別, 金額');
      double totalExtra = 0;
      if (extraByType.isNotEmpty) {
        extraByType.forEach((t, a) { sb.writeln('$t, \$${a.toStringAsFixed(1)}'); totalExtra += a; });
      } else {
        sb.writeln('無, \$0.0');
      }
      sb.writeln('小計, \$${totalExtra.toStringAsFixed(1)}');
      sb.writeln('');
      sb.writeln('【四、OT 統計】');
      sb.writeln('OT 總時數, $ot h');
      sb.writeln('OT 時薪, \$${overtimeRate.toStringAsFixed(0)}/h');
      sb.writeln('OT 總金額, \$${(ot * overtimeRate).toStringAsFixed(1)}');
      sb.writeln('');
      sb.writeln('【五、總計】');
      sb.writeln('總工時, ${hrs.toStringAsFixed(1)}h');
      sb.writeln('班次津貼+單日額外, \$${allow.toStringAsFixed(1)}');
      sb.writeln('OT 津貼, \$${(ot * overtimeRate).toStringAsFixed(1)}');
      sb.writeln('津貼總額, \$${(allow + ot * overtimeRate).toStringAsFixed(1)}');
    } else {
      int year = focused.year;
      DateTime rangeStart = DateTime(year, 1, 1);
      DateTime rangeEnd = DateTime(year, 12, 31);
      DateTime calStart = rangeStart.subtract(Duration(days: rangeStart.weekday - 1));
      DateTime calEnd = rangeEnd.add(Duration(days: 7 - rangeEnd.weekday));
      DateTime calcStart = _effectiveCalcStart(calStart);

      Map<String, double> allWeeklyHours = {};
      DateTime tempDt = calcStart;
      while (!tempDt.isAfter(calEnd)) {
        String k = DateFormat('yyyy-MM-dd').format(tempDt);
        String? c = roster[k];
        if (c != null) {
          var d = defs[c];
          if (d != null) {
            String wk = isoWeekKey(tempDt);
            allWeeklyHours[wk] = (allWeeklyHours[wk] ?? 0) + d.hours;
          }
        }
        tempDt = tempDt.add(const Duration(days: 1));
      }
      List<String> sortedAllWeeks = allWeeklyHours.keys.toList()..sort();
      double lastCarryExport = carry;
      Map<String, double> weekDiffMap = {};
      for (var wk in sortedAllWeeks) {
        double weekHours = allWeeklyHours[wk]!;
        double diff = lastCarryExport + weekHours - standardWeeklyHours;
        weekDiffMap[wk] = diff;
        lastCarryExport = diff;
      }
      String endWeekKey = isoWeekKey(calEnd);
      double totalDiff = carry;
      for (var wk in sortedAllWeeks) {
        if (wk.compareTo(endWeekKey) <= 0) totalDiff = weekDiffMap[wk]!;
        else break;
      }

      double hrs = 0, ot = 0, allow = 0;
      SplayTreeMap<String, int> shiftCount = SplayTreeMap();
      SplayTreeMap<String, double> extraByType = SplayTreeMap();
      double totalYearHrs = 0;

      for (DateTime dt = rangeStart; !dt.isAfter(rangeEnd); dt = dt.add(const Duration(days: 1))) {
        String k = DateFormat('yyyy-MM-dd').format(dt);
        String? c = roster[k];
        if (c == null) continue;
        var d = defs[c];
        if (d != null) {
          hrs += d.hours;
          totalYearHrs += d.hours;
          shiftCount[c] = (shiftCount[c] ?? 0) + 1;
          if (d.hasMorningAllow) allow += morningAllowance;
          if (d.hasNightAllow) allow += nightAllowance * d.hours;
          if (d.hasMealAllow) allow += mealAllowance;
        }
        ot += (rosterOt[k] ?? d?.ot ?? 0);
        allow += (rosterExtra[k] ?? 0);
        if (rosterExtraType.containsKey(k) && rosterExtra.containsKey(k)) {
          extraByType[rosterExtraType[k]!] = (extraByType[rosterExtraType[k]!] ?? 0) + rosterExtra[k]!;
        }
        hrs += (rosterExtraHrs[k] ?? 0);
      }

      sb.writeln('========================================');
      sb.writeln('       ${year}年 全年排更報表');
      sb.writeln('========================================');
      sb.writeln('');
      sb.writeln('【一、班次統計】');
      sb.writeln('班次代號, 班次名稱, 次數, 總工時');
      double totalShiftHours = 0;
      shiftCount.forEach((k, v) {
        var d = defs[k];
        double h = (d?.hours ?? 0) * v;
        totalShiftHours += h;
        sb.writeln('$k, ${d?.label ?? k}, $v次, ${h.toStringAsFixed(1)}h');
      });
      sb.writeln('小計, , ${shiftCount.values.fold(0, (a, b) => a + b)}次, ${totalShiftHours.toStringAsFixed(1)}h');
      sb.writeln('');
      sb.writeln('【二、年度累計工時差額】');
      sb.writeln('標準工時, ${standardWeeklyHours}h/週');
      sb.writeln('總差額, ${totalDiff >= 0 ? '+' : ''}${totalDiff.toStringAsFixed(1)}h');
      sb.writeln('');
      sb.writeln('【三、津貼類別統計】');
      sb.writeln('類別, 金額');
      double totalExtra = 0;
      if (extraByType.isNotEmpty) {
        extraByType.forEach((t, a) { sb.writeln('$t, \$${a.toStringAsFixed(1)}'); totalExtra += a; });
      } else {
        sb.writeln('無, \$0.0');
      }
      sb.writeln('小計, \$${totalExtra.toStringAsFixed(1)}');
      sb.writeln('');
      sb.writeln('【四、OT 統計】');
      sb.writeln('OT 總時數, $ot h');
      sb.writeln('OT 時薪, \$${overtimeRate.toStringAsFixed(0)}/h');
      sb.writeln('OT 總金額, \$${(ot * overtimeRate).toStringAsFixed(1)}');
      sb.writeln('');
      sb.writeln('【五、總計】');
      sb.writeln('總工時, ${hrs.toStringAsFixed(1)}h');
      sb.writeln('班次津貼+單日額外, \$${allow.toStringAsFixed(1)}');
      sb.writeln('OT 津貼, \$${(ot * overtimeRate).toStringAsFixed(1)}');
      sb.writeln('津貼總額, \$${(allow + ot * overtimeRate).toStringAsFixed(1)}');
    }
    String dir = await _getBackupDir();
    String fileName = 'report_${isYearReport ? 'year${focused.year}' : '${focused.year}${focused.month.toString().padLeft(2, '0')}'}.csv';
    String path = '$dir/$fileName';
    final bytes = <int>[0xEF, 0xBB, 0xBF, ...utf8.encode(sb.toString())];
    await File(path).writeAsBytes(bytes);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已匯出 $path')));
      await _showExportResultDialog(path);
    }
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
              String dir = await _getBackupDir();
              String path = '$dir/notes_${queryYear}${yearMode ? '' : queryMonth.toString().padLeft(2, '0')}.csv';
              final bytes = <int>[0xEF, 0xBB, 0xBF, ...utf8.encode(sb.toString())];
              await File(path).writeAsBytes(bytes);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已匯出 $path')));
                Navigator.pop(ctx2);
                await _showExportResultDialog(path);
              }
            } catch (_) {}
          }, child: const Text('匯出CSV')),
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
  if (!await _confirmAction()) return;
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
  _ensureAnchorWeek();
  await save();
  setState(() => tab = 0);
  await _syncNow();
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
  if (!await _confirmAction()) return;
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
  _ensureAnchorWeek();
  await save();
  setState(() => tab = 0);
  await _syncNow();
  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('智能排班完成：$totalDays 天'), duration: const Duration(seconds: 4)));
}

void _goToPrevMonth() { setState(() { focused = DateTime(focused.year, focused.month - 1, 1); }); }
void _goToNextMonth() { setState(() { focused = DateTime(focused.year, focused.month + 1, 1); }); }
void _goToPrevYear()  { setState(() { focused = DateTime(focused.year - 1, focused.month, 1); }); }
void _goToNextYear()  { setState(() { focused = DateTime(focused.year + 1, focused.month, 1); }); }

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
      final currentDef = defs[cur];
      final bool alarmApplicable = currentDef != null && currentDef.alarmEnabled && !currentDef.isAllDay;
      final bool isMuted = rosterAlarmMuted[k] == true;
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx2).viewInsets.bottom),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${DateFormat('yyyy-MM-dd EEE').format(day)} ${isHoliday(day) ? ' [${holidayName(day)}]' : ''}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: defs.keys.map((c) => ChoiceChip(label: Text(c), selected: cur == c, onSelected: (_) => setM(() => cur = c))).toList()),

            if (alarmApplicable) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: isMuted ? Colors.grey.shade200 : Colors.pink.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isMuted ? Colors.grey.shade400 : Colors.pink.shade300,
                    width: 1.2,
                  ),
                ),
                child: Row(children: [
                  Icon(
                    isMuted ? Icons.alarm_off : Icons.alarm_on,
                    color: isMuted ? Colors.grey.shade600 : Colors.pink,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isMuted ? '此日鬧鐘已臨時關閉' : '此日鬧鐘將正常提醒',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: isMuted ? Colors.grey.shade700 : Colors.pink.shade700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isMuted
                              ? '僅影響本日，其他日期不受影響'
                              : '提醒時間 ${_calcAlarmTimeText(currentDef.start, currentDef.alarmMinutesBefore)}（提前 ${currentDef.alarmMinutesBefore} 分）',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: !isMuted,
                    activeColor: Colors.pink,
                    onChanged: (v) {
                      setM(() {
                        if (v) {
                          rosterAlarmMuted.remove(k);
                        } else {
                          rosterAlarmMuted[k] = true;
                        }
                      });
                    },
                  ),
                ]),
              ),
            ],

            const SizedBox(height: 8),
            Padding(padding: const EdgeInsets.only(top: 6), child: TextField(controller: nc, minLines: 2, maxLines: 6, keyboardType: TextInputType.multiline, textInputAction: TextInputAction.newline, decoration: const InputDecoration(labelText: '記事 (可換行多行)', alignLabelWithHint: true, isDense: true, border: OutlineInputBorder()))),
            Row(children: [
              Expanded(child: SizedBox(height: 56, child: TextField(controller: otc, decoration: const InputDecoration(labelText: 'OT時數', isDense: true, border: OutlineInputBorder()), keyboardType: TextInputType.number))),
              const SizedBox(width: 8),
              Expanded(child: SizedBox(height: 56, child: TextField(controller: exHCtrl, decoration: const InputDecoration(labelText: '額外工時', isDense: true, border: OutlineInputBorder()), keyboardType: TextInputType.number))),
            ]),
            Row(children: [
              Expanded(
                child: SizedBox(
                  height: 56,
                  child: TextField(
                    controller: exTypeCtrl,
                    onChanged: (v) {
                      if (v.trim().isEmpty) { exCtrl.text = '0.0'; setM(() {}); }
                    },
                    decoration: InputDecoration(
                      labelText: '額外津貼名稱',
                      isDense: true,
                      border: const OutlineInputBorder(),
                      suffixIcon: extraAllowances.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.arrow_drop_down),
                              tooltip: '從清單選擇',
                              onPressed: () async {
                                final selected = await showModalBottomSheet<String>(
                                  context: context,
                                  builder: (ctx) => SafeArea(
                                    child: ListView(shrinkWrap: true, children: [
                                      const ListTile(title: Text('選擇額外津貼', style: TextStyle(fontWeight: FontWeight.bold))),
                                      ListTile(leading: const Icon(Icons.block, color: Colors.grey), title: const Text('無', style: TextStyle(fontWeight: FontWeight.bold)), subtitle: const Text('清除額外津貼'), onTap: () => Navigator.pop(ctx, '__NONE__')),
                                      const Divider(),
                                      ...extraAllowances.map((e) => ListTile(title: Text(e.name), subtitle: Text('倍數 ${e.multiplier} → \$${e.amount.toStringAsFixed(1)}'), onTap: () => Navigator.pop(ctx, e.name))),
                                    ]),
                                  ),
                                );
                                if (selected != null) {
                                  if (selected == '__NONE__') { exTypeCtrl.text = ''; exCtrl.text = '0.0'; }
                                  else {
                                    exTypeCtrl.text = selected;
                                    final match = extraAllowances.firstWhere((e) => e.name == selected, orElse: () => ExtraAllowance('', 0));
                                    exCtrl.text = match.amount.toStringAsFixed(1);
                                  }
                                  setM(() {});
                                }
                              },
                            )
                          : null,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: SizedBox(height: 56, child: TextField(controller: exCtrl, decoration: const InputDecoration(labelText: '額外津貼金額', isDense: true, border: OutlineInputBorder()), keyboardType: TextInputType.number))),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () async {
                final eventId = _googleEventIdMap[k];
                Navigator.pop(ctx2);
                setState(() { roster.remove(k); rosterLeave.remove(k); rosterOt.remove(k); rosterExtra.remove(k); rosterExtraHrs.remove(k); rosterExtraType.remove(k); rosterAlarmMuted.remove(k); });
                if (eventId != null) {
                  await _safeDeleteEvent(eventId);
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
                  if (curCode.isNotEmpty) roster[k] = curCode; else roster.remove(k);
                  if (noteText.isNotEmpty) rosterNote[k] = noteText; else rosterNote.remove(k);
                  if (exTypeText.isNotEmpty) rosterExtraType[k] = exTypeText; else rosterExtraType.remove(k);
                  if (otVal != null) rosterOt[k] = otVal;
                  if (exVal != null && exVal != 0) rosterExtra[k] = exVal; else if (exVal == 0) rosterExtra.remove(k);
                  if (exHVal != null && exHVal != 0) rosterExtraHrs[k] = exHVal; else rosterExtraHrs.remove(k);
                });
                _markDirty(k);
                _ensureAnchorWeek();
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

  bool hasMorningAllow = oldDef?.hasMorningAllow ?? false;
  bool hasNightAllow = oldDef?.hasNightAllow ?? false;
  bool hasMealAllow = oldDef?.hasMealAllow ?? false;
  bool hasLunch = oldDef?.hasLunch ?? false;
  bool isAllDay = oldDef?.isAllDay ?? false;
  bool hasAL = oldDef?.hasAL ?? false;
  bool hasSH = oldDef?.hasSH ?? false;
  bool hasGH = oldDef?.hasGH ?? false;
  bool hasWB = oldDef?.hasWB ?? false;
  bool hasCustomLeave = oldDef?.hasCustomLeave ?? false;
  String? customLeaveCode = oldDef?.customLeaveCode;
  bool alarmEnabled = oldDef?.alarmEnabled ?? false;
  int alarmMinutesBefore = oldDef?.alarmMinutesBefore ?? 30;
  String? alarmSoundUri = oldDef?.alarmSoundUri;
  String? alarmSoundName = oldDef?.alarmSoundName;

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
          if (hasLunch) diff -= 1.0;
          if (diff < 0) diff = 0;
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
          Column(
            children: [
              Row(
                children: [
                  Expanded(child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Checkbox(value: hasAL, onChanged: (v) => setS(() { hasAL = v ?? false; if (hasAL) { hasSH = false; hasGH = false; hasWB = false; hasCustomLeave = false; customLeaveCode = null; } }), visualDensity: VisualDensity.compact, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    const Flexible(child: Text('AL', style: TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                  ])),
                  Expanded(child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Checkbox(value: hasSH, onChanged: (v) => setS(() { hasSH = v ?? false; if (hasSH) { hasAL = false; hasGH = false; hasWB = false; hasCustomLeave = false; customLeaveCode = null; } }), visualDensity: VisualDensity.compact, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    const Flexible(child: Text('SH', style: TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                  ])),
                  Expanded(child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Checkbox(value: hasGH, onChanged: (v) => setS(() { hasGH = v ?? false; if (hasGH) { hasAL = false; hasSH = false; hasWB = false; hasCustomLeave = false; customLeaveCode = null; } }), visualDensity: VisualDensity.compact, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    const Flexible(child: Text('GH', style: TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                  ])),
                  Expanded(child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Checkbox(value: hasWB, onChanged: (v) => setS(() { hasWB = v ?? false; if (hasWB) { hasAL = false; hasSH = false; hasGH = false; hasCustomLeave = false; customLeaveCode = null; } }), visualDensity: VisualDensity.compact, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    const Flexible(child: Text('WB', style: TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                  ])),
                ],
              ),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Checkbox(value: hasCustomLeave, onChanged: (v) => setS(() { hasCustomLeave = v ?? false; if (hasCustomLeave) { hasAL = false; hasSH = false; hasGH = false; hasWB = false; } }), visualDensity: VisualDensity.compact, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  const Flexible(child: Text('自訂假期', style: TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                ])),
                if (hasCustomLeave)
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: customLeaveCode,
                      decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                      items: leaveDefs.where((e) => e.isCustom).map((e) => DropdownMenuItem(value: e.name, child: Text(e.name, style: const TextStyle(fontSize: 12)))).toList(),
                      onChanged: (v) { setS(() => customLeaveCode = v); },
                    ),
                  )
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Checkbox(value: hasMorningAllow, onChanged: (v) => setS(() => hasMorningAllow = v ?? false)),
                  const Flexible(child: Text('早/夜班津貼', style: TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                ])),
                Expanded(child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Checkbox(value: hasNightAllow, onChanged: (v) => setS(() => hasNightAllow = v ?? false)),
                  const Flexible(child: Text('通宵津貼', style: TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                ])),
              ]),
              Row(children: [
                Expanded(child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Checkbox(value: hasMealAllow, onChanged: (v) => setS(() => hasMealAllow = v ?? false)),
                  const Flexible(child: Text('膳食津貼', style: TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                ])),
                Expanded(child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Checkbox(value: hasLunch, onChanged: (v) { setS(() => hasLunch = v ?? false); calcHours(); }),
                  const Flexible(child: Text('午飯時間', style: TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                ])),
              ]),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.pink.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.pink.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.alarm, color: Colors.pink, size: 18),
                  const SizedBox(width: 6),
                  const Text('上班鬧鐘提醒', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const Spacer(),
                  Switch(value: alarmEnabled, onChanged: (v) => setS(() => alarmEnabled = v)),
                ]),
                if (alarmEnabled) ...[
                  const SizedBox(height: 6),
                  Row(children: [
                    const Icon(Icons.schedule, size: 16, color: Colors.pink),
                    const SizedBox(width: 4),
                    const Text('鬧鐘時間', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Text('（提前 $alarmMinutesBefore 分）', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  ]),
                  const SizedBox(height: 6),
                  if (!isAllDay)
                    InkWell(
                      onTap: () async {
                        int startH = 7, startM = 0;
                        try {
                          final parts = startCtrl.text.split(':');
                          startH = int.parse(parts[0]);
                          startM = int.parse(parts[1]);
                        } catch (_) {}
                        int alarmTotal = startH * 60 + startM - alarmMinutesBefore;
                        while (alarmTotal < 0) alarmTotal += 24 * 60;
                        TimeOfDay init = TimeOfDay(hour: alarmTotal ~/ 60, minute: alarmTotal % 60);
                        TimeOfDay? picked = await _pickWheelTime(ctx2, init);
                        if (picked != null) {
                          int startTotal = startH * 60 + startM;
                          int pickedTotal = picked.hour * 60 + picked.minute;
                          int diff = startTotal - pickedTotal;
                          if (diff < 0) diff += 24 * 60;
                          setS(() => alarmMinutesBefore = diff);
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                        child: Row(children: [
                          const Text('⏰', style: TextStyle(fontSize: 16)),
                          const SizedBox(width: 8),
                          Text(
                            _calcAlarmTimeText(startCtrl.text, alarmMinutesBefore),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.pink,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '點擊修改',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                          ),
                          const Icon(Icons.arrow_drop_down, color: Colors.grey),
                        ]),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(children: [
                        Text('⏰', style: TextStyle(fontSize: 16)),
                        SizedBox(width: 8),
                        Text('--:--', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.5)),
                        Spacer(),
                        Text('全天班次不適用', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      ]),
                    ),
                  const SizedBox(height: 6),
                  Row(children: [
                    const Icon(Icons.music_note, size: 16, color: Colors.pink),
                    const SizedBox(width: 4),
                    const Text('鬧鐘鈴聲', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    TextButton(
                      onPressed: () async {
                        final ringtones = await _getSystemRingtones();
                        if (ringtones.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('無法獲取系統鈴聲，請確認權限'))); return; }
                        if (!ctx2.mounted) return;
                        showDialog(context: ctx2, builder: (ctx3) {
                          String? tempUri = alarmSoundUri;
                          String? tempName = alarmSoundName;
                          return StatefulBuilder(builder: (ctx4, setRing) {
                            return AlertDialog(
                              title: const Text('選擇鬧鐘鈴聲'),
                              content: SizedBox(width: 400, height: 400, child: ListView.builder(
                                itemCount: ringtones.length,
                                itemBuilder: (c, i) {
                                  final r = ringtones[i];
                                  final uri = r['uri'] ?? '';
                                  final name = r['name'] ?? '未知';
                                  final selected = tempUri == uri;
                                  return ListTile(
                                    dense: true,
                                    title: Text(name, style: TextStyle(fontSize: 13, fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
                                    trailing: selected ? const Icon(Icons.check, color: Colors.pink) : null,
                                    onTap: () async {
                                      await _playRingtonePreview(uri);
                                      setRing(() { tempUri = uri; tempName = name; });
                                    },
                                  );
                                },
                              )),
                              actions: [
                                TextButton(onPressed: () { _stopRingtonePreview(); Navigator.pop(ctx4); }, child: const Text('取消')),
                                FilledButton(onPressed: () {
                                  _stopRingtonePreview();
                                  setS(() { alarmSoundUri = tempUri; alarmSoundName = tempName; });
                                  Navigator.pop(ctx4);
                                }, child: const Text('確定')),
                              ],
                            );
                          });
                        });
                      },
                      child: Text(alarmSoundName ?? '系統預設', style: const TextStyle(fontSize: 12, color: Colors.pink)),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Text('💡 點擊上方時間可修改；全天班次不會觸發鬧鐘；排班有變動會自動重新排程',
                      style: TextStyle(fontSize: 10, color: Colors.grey)),
                  ),
                ],
              ],
            ),
          ),
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
              defs[newCode] = ShiftDef(newCode, labelCtrl.text.isEmpty ? newCode : labelCtrl.text, hrs, picked,
                ot: double.tryParse(otCtrl.text) ?? 0, start: startCtrl.text, end: endCtrl.text,
                hasMorningAllow: hasMorningAllow, hasNightAllow: hasNightAllow, hasMealAllow: hasMealAllow,
                isAllDay: isAllDay, hasLunch: hasLunch,
                hasAL: hasAL, hasSH: hasSH, hasGH: hasGH, hasWB: hasWB,
                hasCustomLeave: hasCustomLeave, customLeaveCode: customLeaveCode,
                alarmEnabled: alarmEnabled, alarmMinutesBefore: alarmMinutesBefore,
                alarmSoundUri: alarmSoundUri, alarmSoundName: alarmSoundName
              );
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

Future<void> showLeaveListDialog() async {
  int queryYear = focused.year;
  int queryMonth = focused.month;
  bool yearMode = false;
  await showDialog(context: context, builder: (ctx) {
    return StatefulBuilder(builder: (ctx2, setD) {
      List<MapEntry<String, String>> leaveEntries = [];
      if (yearMode) {
        roster.forEach((k, v) {
          if (k.startsWith('$queryYear')) {
            var d = defs[v];
            if (d != null) {
              String? code;
              if (d.hasAL) code = 'AL'; else if (d.hasSH) code = 'SH'; else if (d.hasGH) code = 'GH'; else if (d.hasWB) code = 'WB';
              else if (d.hasCustomLeave && d.customLeaveCode != null && d.customLeaveCode!.isNotEmpty) code = d.customLeaveCode;
              if (code != null) leaveEntries.add(MapEntry(k, code));
            }
          }
        });
        rosterLeave.forEach((k, v) {
          if (k.startsWith('$queryYear')) {
            if (!leaveEntries.any((e) => e.key == k)) leaveEntries.add(MapEntry(k, v));
          }
        });
      } else {
        roster.forEach((k, v) {
          if (k.startsWith('$queryYear-${queryMonth.toString().padLeft(2, '0')}')) {
            var d = defs[v];
            if (d != null) {
              String? code;
              if (d.hasAL) code = 'AL'; else if (d.hasSH) code = 'SH'; else if (d.hasGH) code = 'GH'; else if (d.hasWB) code = 'WB';
              else if (d.hasCustomLeave && d.customLeaveCode != null && d.customLeaveCode!.isNotEmpty) code = d.customLeaveCode;
              if (code != null) leaveEntries.add(MapEntry(k, code));
            }
          }
        });
        rosterLeave.forEach((k, v) {
          if (k.startsWith('$queryYear-${queryMonth.toString().padLeft(2, '0')}')) {
            if (!leaveEntries.any((e) => e.key == k)) leaveEntries.add(MapEntry(k, v));
          }
        });
      }
      leaveEntries.sort((a, b) => a.key.compareTo(b.key));

      Map<String, double> yearUsed = {};
      roster.forEach((k, v) {
        if (k.startsWith('$queryYear')) {
          var d = defs[v];
          if (d != null) {
            if (d.hasAL) yearUsed['AL'] = (yearUsed['AL'] ?? 0) + 1;
            if (d.hasSH) yearUsed['SH'] = (yearUsed['SH'] ?? 0) + 1;
            if (d.hasGH) yearUsed['GH'] = (yearUsed['GH'] ?? 0) + 1;
            if (d.hasWB) yearUsed['WB'] = (yearUsed['WB'] ?? 0) + 1;
            if (d.hasCustomLeave && d.customLeaveCode != null && d.customLeaveCode!.isNotEmpty) {
              yearUsed[d.customLeaveCode!] = (yearUsed[d.customLeaveCode!] ?? 0) + 1;
            }
          }
        }
      });

      return AlertDialog(
        title: Text(yearMode ? '$queryYear年 全年假期清單' : '$queryYear年$queryMonth月 假期清單'),
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
          Expanded(child: leaveEntries.isEmpty ? const Center(child: Text('沒有假期記錄')) : ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: leaveEntries.length,
            itemBuilder: (c, i) {
              var leave = leaveDefs.firstWhere((e) => e.name == leaveEntries[i].value, orElse: () => LeaveDef('', '', Colors.grey));
              return ListTile(
                dense: true,
                leading: CircleAvatar(backgroundColor: leave.color, child: Text(leave.name, style: const TextStyle(color: Colors.white, fontSize: 10))),
                title: Text(leaveEntries[i].key, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(leave.fullName),
                onTap: () { Navigator.pop(ctx2); setState(() { selectedDay = DateTime.parse(leaveEntries[i].key); focused = DateTime(selectedDay.year, selectedDay.month, 1); }); showDetail(selectedDay); },
              );
            })),
          const Divider(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$queryYear年假期餘額結算', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 4),
                ...leaveDefs.map((leave) {
                  double used = yearUsed[leave.name] ?? 0.0;
                  var rec = leaveRecords['$queryYear']?[leave.name] ?? {'carry': 0.0};
                  double balance = (rec['carry'] as num).toDouble() - used;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text(leave.name, style: TextStyle(fontWeight: FontWeight.bold, color: leave.color)),
                      Text('已用: ${used.toStringAsFixed(1)} 天 / 結餘: ${balance.toStringAsFixed(1)} 天', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ]),
                  );
                }),
              ],
            ),
          ),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx2), child: const Text('關閉')),
          FilledButton(onPressed: () async {
            try {
              StringBuffer sb = StringBuffer();
              sb.writeln('年份,月份,日期,假期代號,假期名稱,已用天數,結餘天數');
              var yrRecords = leaveRecords['$queryYear'] ?? {};
              for (var n in leaveEntries) {
                var leave = leaveDefs.firstWhere((e) => e.name == n.value, orElse: () => LeaveDef('', '', Colors.grey));
                double used = yearUsed[leave.name] ?? 0.0;
                var rec = yrRecords[leave.name] ?? {'carry': 0.0};
                double balance = (rec['carry'] as num).toDouble() - used;
                String dateStr = n.key;
                String yearStr = dateStr.substring(0, 4);
                String monthStr = dateStr.substring(5, 7);
                sb.writeln('$yearStr,$monthStr,$dateStr,${leave.name},${leave.fullName},$used,${balance.toStringAsFixed(1)}');
              }
              String dir = await _getBackupDir();
              String path = '$dir/leaves_${queryYear}${yearMode ? '' : queryMonth.toString().padLeft(2, '0')}.csv';
              final bytes = <int>[0xEF, 0xBB, 0xBF, ...utf8.encode(sb.toString())];
              await File(path).writeAsBytes(bytes);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已匯出 $path')));
                Navigator.pop(ctx2);
                await _showExportResultDialog(path);
              }
            } catch (_) {}
          }, child: const Text('匯出CSV')),
        ]
      );
    });
  });
}

void showLeaveManagementDialog() {
  int selectedYear = DateTime.now().year;

  final Map<String, TextEditingController> totalCtrls = {};
  final Map<String, TextEditingController> adjustCtrls = {};
  final Map<String, TextEditingController> nameCtrls = {};
  final Map<String, TextEditingController> fullNameCtrls = {};

  showDialog(context: context, builder: (ctx) {
    return StatefulBuilder(builder: (ctx2, setD) {
      if (!leaveRecords.containsKey('$selectedYear')) leaveRecords['$selectedYear'] = {};
      var yearRecords = leaveRecords['$selectedYear']!;
      for (var def in leaveDefs) {
        if (!yearRecords.containsKey(def.name)) yearRecords[def.name] = {'total': 0.0, 'adjust': 0.0, 'carry': 0.0};
      }

      for (var def in leaveDefs) {
        var record = yearRecords[def.name]!;
        double prevCarry = 0.0;
        if (selectedYear > 2000) {
          prevCarry = (leaveRecords['${selectedYear - 1}']?[def.name]?['carry'] as num?)?.toDouble() ?? 0.0;
        }
        double total = (record['total'] as num?)?.toDouble() ?? 0.0;
        double adjust = (record['adjust'] as num?)?.toDouble() ?? 0.0;
        record['carry'] = prevCarry + total + adjust;
      }

      return AlertDialog(
        title: Text('假期數據管理 - $selectedYear年'),
        content: SizedBox(width: 600, height: 500, child: Column(children: [
          Row(children: [
            IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => setD(() => selectedYear--)),
            Expanded(child: Text('$selectedYear年', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => setD(() => selectedYear++)),
          ]),
          const Divider(),
          Expanded(child: ListView(children: [
            ...leaveDefs.where((e) => !e.isCustom).map((leave) {
              var record = yearRecords[leave.name]!;
              String key = '${selectedYear}_${leave.name}';
              if (!totalCtrls.containsKey(key)) {
                totalCtrls[key] = TextEditingController(text: (record['total'] ?? 0.0).toString());
              }
              var totalCtrl = totalCtrls[key]!;
              if (!adjustCtrls.containsKey(key)) {
                adjustCtrls[key] = TextEditingController(text: (record['adjust'] ?? 0.0).toString());
              }
              var adjustCtrl = adjustCtrls[key]!;
              double prevCarry = 0.0;
              if (selectedYear > 2000) {
                prevCarry = (leaveRecords['${selectedYear - 1}']?[leave.name]?['carry'] as num?)?.toDouble() ?? 0.0;
              }
              double total = (record['total'] as num?)?.toDouble() ?? 0.0;
              double adjust = (record['adjust'] as num?)?.toDouble() ?? 0.0;
              double autoCarry = prevCarry + total + adjust;

              return Card(margin: const EdgeInsets.symmetric(vertical: 4), child: Padding(padding: const EdgeInsets.all(8.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${leave.name} (${leave.fullName})', style: TextStyle(fontWeight: FontWeight.bold, color: leave.color)),
                const SizedBox(height: 4),
                Row(children: [
                  Expanded(child: TextField(
                    controller: totalCtrl,
                    decoration: const InputDecoration(labelText: '天數', isDense: true, border: OutlineInputBorder()),
                    keyboardType: TextInputType.number,
                    onChanged: (v) {
                      record['total'] = double.tryParse(v) ?? 0.0;
                      setD(() {});
                    }
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(
                    controller: adjustCtrl,
                    decoration: const InputDecoration(labelText: '微調 +/-', isDense: true, border: OutlineInputBorder()),
                    keyboardType: TextInputType.number,
                    onChanged: (v) {
                      record['adjust'] = double.tryParse(v) ?? 0.0;
                      setD(() {});
                    }
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: AbsorbPointer(
                    child: TextField(
                      controller: TextEditingController(text: autoCarry.toStringAsFixed(1)),
                      enabled: false,
                      decoration: const InputDecoration(labelText: '餘額 (自動計算)', isDense: true, border: OutlineInputBorder(), filled: true, fillColor: Color(0xFFEEEEEE)),
                    ),
                  )),
                ]),
              ])));
            }),
            const SizedBox(height: 16),
            const Text('自訂假期', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ...leaveDefs.where((e) => e.isCustom).map((leave) {
              var record = yearRecords[leave.name]!;
              String key = '${selectedYear}_${leave.name}';
              if (!totalCtrls.containsKey(key)) {
                totalCtrls[key] = TextEditingController(text: (record['total'] ?? 0.0).toString());
              }
              var totalCtrl = totalCtrls[key]!;
              if (!adjustCtrls.containsKey(key)) {
                adjustCtrls[key] = TextEditingController(text: (record['adjust'] ?? 0.0).toString());
              }
              var adjustCtrl = adjustCtrls[key]!;
              if (!nameCtrls.containsKey(key)) {
                nameCtrls[key] = TextEditingController(text: leave.name);
              }
              var nameCtrl = nameCtrls[key]!;
              if (!fullNameCtrls.containsKey(key)) {
                fullNameCtrls[key] = TextEditingController(text: leave.fullName);
              }
              var fullNameCtrl = fullNameCtrls[key]!;
              double prevCarry = 0.0;
              if (selectedYear > 2000) {
                prevCarry = (leaveRecords['${selectedYear - 1}']?[leave.name]?['carry'] as num?)?.toDouble() ?? 0.0;
              }
              double total = (record['total'] as num?)?.toDouble() ?? 0.0;
              double adjust = (record['adjust'] as num?)?.toDouble() ?? 0.0;
              double autoCarry = prevCarry + total + adjust;

              return Card(margin: const EdgeInsets.symmetric(vertical: 4), child: Padding(padding: const EdgeInsets.all(8.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '代號', isDense: true, border: OutlineInputBorder()), onChanged: (v) { leave.name = v; })),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: fullNameCtrl, decoration: const InputDecoration(labelText: '全名', isDense: true, border: OutlineInputBorder()), onChanged: (v) { leave.fullName = v; })),
                  IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () { setD(() { leaveDefs.remove(leave); }); }),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  Expanded(child: TextField(
                    controller: totalCtrl,
                    decoration: const InputDecoration(labelText: '天數', isDense: true, border: OutlineInputBorder()),
                    keyboardType: TextInputType.number,
                    onChanged: (v) { record['total'] = double.tryParse(v) ?? 0.0; setD(() {}); }
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(
                    controller: adjustCtrl,
                    decoration: const InputDecoration(labelText: '微調 +/-', isDense: true, border: OutlineInputBorder()),
                    keyboardType: TextInputType.number,
                    onChanged: (v) { record['adjust'] = double.tryParse(v) ?? 0.0; setD(() {}); }
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: AbsorbPointer(
                    child: TextField(
                      controller: TextEditingController(text: autoCarry.toStringAsFixed(1)),
                      enabled: false,
                      decoration: const InputDecoration(labelText: '餘額 (自動計算)', isDense: true, border: OutlineInputBorder(), filled: true, fillColor: Color(0xFFEEEEEE)),
                    ),
                  )),
                ]),
              ])));
            }),
            TextButton.icon(icon: const Icon(Icons.add), label: const Text('新增自訂假期'), onPressed: () {
              setD(() { var newDef = LeaveDef('Custom', '自訂假期', Colors.purple, isCustom: true); leaveDefs.add(newDef); yearRecords[newDef.name] = {'total': 0.0, 'adjust': 0.0, 'carry': 0.0}; });
            }),
          ])),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx2), child: const Text('關閉')),
          FilledButton(onPressed: () async {
            await save();
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('假期數據已儲存')));
            Navigator.pop(ctx2);
          }, child: const Text('儲存')),
        ],
      );
    });
  });
}
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

    String? selLeaveCode;
    if (selDef != null) {
      if (selDef.hasAL) selLeaveCode = 'AL';
      else if (selDef.hasSH) selLeaveCode = 'SH';
      else if (selDef.hasGH) selLeaveCode = 'GH';
      else if (selDef.hasWB) selLeaveCode = 'WB';
      else if (selDef.hasCustomLeave && selDef.customLeaveCode != null && selDef.customLeaveCode!.isNotEmpty) selLeaveCode = selDef.customLeaveCode;
    }
    var selLeave = selLeaveCode != null ? leaveDefs.firstWhere((e) => e.name == selLeaveCode, orElse: () => LeaveDef('', '', Colors.grey)) : null;

    String note = rosterNote[selKey] ?? '無';
    String extraType = rosterExtraType[selKey] ?? '';
    DateTime today = DateTime.now();

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Row(
              children: [
                Flexible(
                  flex: 2,
                  child: InkWell(
                    onTap: () => quickJumpMonth(),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${focused.year}年${focused.month}月',
                          style: TextStyle(fontSize: calendarFontSize * 2, fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Icon(Icons.arrow_drop_down, size: calendarFontSize * 1.5),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _goToPrevMonth,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _goToNextMonth,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
                FilledButton.tonal(
                  onPressed: () {
                    setState(() {
                      focused = DateTime(today.year, today.month, 1);
                      selectedDay = DateTime(today.year, today.month, today.day);
                    });
                  },
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('今天', style: TextStyle(fontSize: 12)),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onSelected: (value) {
                    if (value == 'notes') showNotesListDialog();
                    else if (value == 'leaves') showLeaveListDialog();
                    else if (value == 'screenshot') shareScreenshotDialog();
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'notes', child: Text('記事查詢')),
                    const PopupMenuItem(value: 'leaves', child: Text('假期清單')),
                    const PopupMenuItem(value: 'screenshot', child: Text('整月截圖分享')),
                  ],
                ),
              ],
            ),
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
                child: SingleChildScrollView(
                  child: Column(children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Row(children: [
                        Container(width: 32, child: const Text('週', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.deepPurple))),
                        Expanded(child: Row(children: ["一", "二", "三", "四", "五", "六", "日"].map((w) => Expanded(child: Text(w, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11)))).toList()))
                      ]),
                    ),
                    ...List.generate(weeks, (row) {
                      return Row(children: [
                        Container(width: 32, alignment: Alignment.center, child: Text('W${isoWeek(days[row * 7])}', style: const TextStyle(fontSize: 11, color: Colors.deepPurple, fontWeight: FontWeight.bold))),
                        Expanded(
                          child: GridView.builder(
                            shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), padding: const EdgeInsets.all(2),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 7,
                              childAspectRatio: 0.65,
                              mainAxisSpacing: 2,
                              crossAxisSpacing: 2
                            ),
                            itemCount: 7,
                            itemBuilder: (ctx2, col) {
                              int idx = row * 7 + col;
                              DateTime day = days[idx];
                              bool inM = day.month == focused.month;

                              String k = DateFormat('yyyy-MM-dd').format(day);
                              String? code = roster[k];
                              var def = code != null ? defs[code] : null;
                              String? leaveCode;
                              if (def != null) {
                                if (def.hasAL) leaveCode = 'AL';
                                else if (def.hasSH) leaveCode = 'SH';
                                else if (def.hasGH) leaveCode = 'GH';
                                else if (def.hasWB) leaveCode = 'WB';
                                else if (def.hasCustomLeave && def.customLeaveCode != null && def.customLeaveCode!.isNotEmpty) leaveCode = def.customLeaveCode;
                              }
                              var leaveDef = leaveCode != null ? leaveDefs.firstWhere((e) => e.name == leaveCode, orElse: () => LeaveDef('', '', Colors.grey)) : null;
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
                                    else if (leaveDef != null)
                                      FittedBox(fit: BoxFit.scaleDown, child: Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1), decoration: BoxDecoration(color: leaveDef.color, borderRadius: BorderRadius.circular(4)), child: Text(leaveDef.name, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))))
                                    else const SizedBox(height: 14),
                                    if (showLunar && lunarText.isNotEmpty)
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
                    })
                  ])
                )
              )
            )
          ),
          Container(
            height: MediaQuery.of(context).size.height * 0.24,
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              boxShadow: [
                BoxShadow(color: Colors.black12, blurRadius: 10, spreadRadius: 2, offset: Offset(0, -5))
              ]
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(DateFormat('yyyy年M月d日').format(selectedDay), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
                                if (showLunar) ...[
                                  const SizedBox(width: 4),
                                  Text(' ' + LunarHelper.getFullLunarText(selectedDay), style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                                ]
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                if (selDef != null)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(color: selDef.color, borderRadius: BorderRadius.circular(6)),
                                        child: Text('${selDef.code} ${selDef.label}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                      ),
                                      if (selDef.alarmEnabled && !selDef.isAllDay) ...[
                                        const SizedBox(width: 6),
                                        Icon(
                                          rosterAlarmMuted[selKey] == true ? Icons.alarm_off : Icons.alarm_on,
                                          color: rosterAlarmMuted[selKey] == true ? Colors.grey : Colors.pink,
                                          size: 18,
                                        ),
                                      ],
                                    ],
                                  )
                                else if (selLeave != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(color: selLeave.color, borderRadius: BorderRadius.circular(6)),
                                    child: Text('${selLeave.name} ${selLeave.fullName}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                  )
                                else
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(6)),
                                    child: const Text('未排班', style: TextStyle(color: Colors.black54, fontSize: 12, fontWeight: FontWeight.bold)),
                                  ),
                                const SizedBox(width: 8),
                                if (extraType.isNotEmpty)
                                  Text('[$extraType]', style: const TextStyle(fontSize: 12, color: Colors.deepPurple, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          Container(
                            decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade200)),
                            child: IconButton(
                              icon: const Icon(Icons.date_range, size: 18, color: Colors.blue),
                              tooltip: '範圍同步',
                              onPressed: googleSyncEnabled ? syncDateRange : null,
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                            ),
                          ),
                          const SizedBox(width: 6),
                          FilledButton.tonalIcon(
                            onPressed: () { showDetail(selectedDay); },
                            icon: const Icon(Icons.edit, size: 16),
                            label: const Text('編輯', style: TextStyle(fontSize: 12)),
                            style: FilledButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 12)),
                          ),
                        ],
                      )
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity, padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(8)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('1. 班次：${selDef != null ? '(${selDef.code}) ${selDef.label}' : ''} ${isHoliday(selectedDay) ? '[${holidayName(selectedDay)}]' : ''}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('2. 時間：${selDef != null ? (selDef.isAllDay ? '全天' : '${selDef.start}-${selDef.end}') : ''} | 工時：${selDef?.hours ?? 0}h', style: const TextStyle(fontSize: 12)),
                      const SizedBox(height: 4),
                      Text('3. 班次津貼：${selDef != null ? ((selDef.hasMorningAllow ? '早/夜班 \$${morningAllowance.toStringAsFixed(0)} ' : '') + (selDef.hasNightAllow ? '通宵 \$${(nightAllowance * selDef.hours).toStringAsFixed(0)} ' : '') + (selDef.hasMealAllow ? '膳食 \$${mealAllowance.toStringAsFixed(0)}' : '')).trim() : '無'} | 午飯時間：${selDef != null && selDef.hasLunch ? '有 (已扣1h)' : '無'}', style: const TextStyle(fontSize: 12)),
                      const SizedBox(height: 4),
                      Text('4. 額外津貼名稱：${extraType.isNotEmpty ? extraType : '無'}  金額：\$${(rosterExtra[selKey] ?? 0).toStringAsFixed(1)}', style: const TextStyle(fontSize: 12, color: Colors.deepPurple, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text('5. OT：${(rosterOt[selKey] ?? 0).toStringAsFixed(1)}h | 額外工時：${(rosterExtraHrs[selKey] ?? 0).toStringAsFixed(1)}h', style: const TextStyle(fontSize: 12)),
                      const SizedBox(height: 4),
                      Text('6. 記事：${note.isEmpty ? '無' : note}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                      if (selLeave != null) ...[
                        const SizedBox(height: 4),
                        Text('7. 假期：${selLeave.fullName} (${selLeave.name})', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: selLeave.color)),
                      ]
                    ])
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
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
                FilledButton.tonal(onPressed: () {
                  if (editingPatternIndex != null) {
                    setState(() {
                      savedPatterns[editingPatternIndex!] = SavedPattern(editingPatternName!, pattern.map((r) => List<String>.from(r)).toList());
                      editingPatternName = null;
                      editingPatternIndex = null;
                      pattern = _defaultPattern.map((r) => List<String>.from(r)).toList();
                    });
                    save();
                  }
                }, child: const Text('更新同名')),
                IconButton(icon: const Icon(Icons.close, size: 16), onPressed: () {
                  setState(() {
                    editingPatternName = null;
                    editingPatternIndex = null;
                    pattern = _defaultPattern.map((r) => List<String>.from(r)).toList();
                  });
                })
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

    DateTime rangeStart = isYearReport ? DateTime(year, 1, 1) : DateTime(year, month, 1);
    DateTime rangeEnd = isYearReport ? DateTime(year, 12, 31) : DateTime(year, month + 1, 0);

    double totalYearHrs = 0;
    Map<int, double> yearMonthlyHrs = {};
    Map<String, int> yearShiftCount = {};
    Map<String, double> yearShiftHours = {};
    if (isYearReport) {
      for (int m = 1; m <= 12; m++) {
        int dim = DateTime(year, m + 1, 0).day;
        double hrsM = 0;
        for (int d = 1; d <= dim; d++) {
          String k = DateFormat('yyyy-MM-dd').format(DateTime(year, m, d));
          String? c = roster[k];
          if (c == null) continue;
          var def = defs[c];
          if (def != null) {
            hrsM += def.hours;
            totalYearHrs += def.hours;
            yearShiftCount[c] = (yearShiftCount[c] ?? 0) + 1;
            yearShiftHours[c] = (yearShiftHours[c] ?? 0) + def.hours;
          }
        }
        yearMonthlyHrs[m] = hrsM;
      }
    }

    double hrs = 0, ot = 0, allow = 0;
    Map<String, int> shiftCount = {};
    Map<String, double> shiftHours = {};
    Map<String, double> extraByType = {};

    for (DateTime dt = rangeStart; !dt.isAfter(rangeEnd); dt = dt.add(const Duration(days: 1))) {
      String k = DateFormat('yyyy-MM-dd').format(dt);
      String? c = roster[k];
      if (c == null) continue;
      var d = defs[c];
      if (d != null) {
        hrs += d.hours;
        shiftCount[c] = (shiftCount[c] ?? 0) + 1;
        shiftHours[c] = (shiftHours[c] ?? 0) + d.hours;
        if (d.hasMorningAllow) allow += morningAllowance;
        if (d.hasNightAllow) allow += nightAllowance * d.hours;
        if (d.hasMealAllow) allow += mealAllowance;
      }
      ot += (rosterOt[k] ?? d?.ot ?? 0);
      allow += (rosterExtra[k] ?? 0);
      if (rosterExtra.containsKey(k) && rosterExtraType.containsKey(k)) {
        String t = rosterExtraType[k]!;
        extraByType[t] = (extraByType[t] ?? 0) + rosterExtra[k]!;
      }
      hrs += (rosterExtraHrs[k] ?? 0);
    }

    double otAmount = ot * overtimeRate;
    double totalAllow = allow + otAmount;

    DateTime calStart = rangeStart.subtract(Duration(days: rangeStart.weekday - 1));
    DateTime calEnd = rangeEnd.add(Duration(days: 7 - rangeEnd.weekday));
    DateTime calcStart = _effectiveCalcStart(calStart);

    Map<String, double> allWeeklyHours = {};
    DateTime tempDt = calcStart;
    while (!tempDt.isAfter(calEnd)) {
      String k = DateFormat('yyyy-MM-dd').format(tempDt);
      String? c = roster[k];
      if (c != null) {
        var d = defs[c];
        if (d != null) {
          String wk = isoWeekKey(tempDt);
          allWeeklyHours[wk] = (allWeeklyHours[wk] ?? 0) + d.hours;
        }
      }
      tempDt = tempDt.add(const Duration(days: 1));
    }

    List<String> sortedAllWeeks = allWeeklyHours.keys.toList()..sort();
    double lastCarry = carry;
    Map<String, double> weekCarryMap = {};
    Map<String, double> weekDiffMap = {};
    for (var wk in sortedAllWeeks) {
      double weekHours = allWeeklyHours[wk]!;
      weekCarryMap[wk] = lastCarry;
      double diff = lastCarry + weekHours - standardWeeklyHours;
      weekDiffMap[wk] = diff;
      lastCarry = diff;
    }

    Set<String> currentRangeWeeksSet = {};
    for (DateTime dt = calStart; !dt.isAfter(calEnd); dt = dt.add(const Duration(days: 1))) {
      currentRangeWeeksSet.add(isoWeekKey(dt));
    }

    List<Map<String, dynamic>> weeklyStats = [];
    for (String wk in sortedAllWeeks) {
      if (currentRangeWeeksSet.contains(wk)) {
        weeklyStats.add({
          'week': wk,
          'hours': allWeeklyHours[wk]!,
          'carry': weekCarryMap[wk]!,
          'diff': weekDiffMap[wk]!,
        });
      }
    }

    double totalDiff;
    if (isYearReport) {
      String endWeekKey = isoWeekKey(calEnd);
      double lastDiff = carry;
      for (var wk in sortedAllWeeks) {
        if (wk.compareTo(endWeekKey) <= 0) lastDiff = weekDiffMap[wk]!;
        else break;
      }
      totalDiff = lastDiff;
    } else {
      totalDiff = weeklyStats.isNotEmpty ? (weeklyStats.last['diff'] as double) : 0.0;
    }

    return SafeArea(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity == null) return;
          if (details.primaryVelocity! < -100) {
            if (isYearReport) { _goToNextYear(); } else { _goToNextMonth(); }
          } else if (details.primaryVelocity! > 100) {
            if (isYearReport) { _goToPrevYear(); } else { _goToPrevMonth(); }
          }
        },
        child: ListView(padding: const EdgeInsets.all(12), children: [
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
          if (isYearReport) Card(color: const Color(0xFFE3F2FD), child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('班次統計 (全年)', style: TextStyle(fontWeight: FontWeight.bold)),
            const Divider(),
            if (yearShiftCount.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text('本年度尚未排班', style: TextStyle(color: Colors.grey))),
            ...yearShiftCount.entries.map((e) {
              double h = yearShiftHours[e.key] ?? 0;
              var d = defs[e.key];
              return Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(children: [
                Container(width: 28, height: 28, decoration: BoxDecoration(color: d?.color ?? Colors.grey, borderRadius: BorderRadius.circular(6)), child: Center(child: Text(e.key, style: const TextStyle(color: Colors.white, fontSize: 11)))),
                const SizedBox(width: 8),
                Text('${d?.label ?? e.key}'),
                const Spacer(),
                Text('${e.value}次 / ${h.toStringAsFixed(1)}h', style: const TextStyle(fontWeight: FontWeight.bold)),
              ]));
            }),
            const Divider(),
            Text('全年總工時 ${totalYearHrs.toStringAsFixed(1)}h'),
          ]))),
          if (!isYearReport) Card(color: const Color(0xFFE3F2FD), child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('班次統計', style: TextStyle(fontWeight: FontWeight.bold)),
            const Divider(),
            if (shiftCount.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text('本月尚未排班', style: TextStyle(color: Colors.grey))),
            ...shiftCount.entries.map((e) {
              double h = shiftHours[e.key] ?? 0;
              var d = defs[e.key];
              return Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(children: [
                Container(width: 28, height: 28, decoration: BoxDecoration(color: d?.color ?? Colors.grey, borderRadius: BorderRadius.circular(6)), child: Center(child: Text(e.key, style: const TextStyle(color: Colors.white, fontSize: 11)))),
                const SizedBox(width: 8),
                Text('${d?.label ?? e.key}'),
                const Spacer(),
                Text('${e.value}次 / ${h.toStringAsFixed(1)}h', style: const TextStyle(fontWeight: FontWeight.bold)),
              ]));
            }),
            const Divider(),
            Text('總工時 ${hrs.toStringAsFixed(1)}h'),
          ]))),
          if (!isYearReport) Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('每週工時統計 (標準 & 承上) 週數', style: TextStyle(fontWeight: FontWeight.bold)),
            const Divider(),
            if (weeklyStats.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text('本月無排班資料', style: TextStyle(color: Colors.grey))),
            ...weeklyStats.map((stat) {
              String week = stat['week'];
              double weekHours = stat['hours'];
              double displayCarry = stat['carry'];
              double diff = stat['diff'];
              return Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [
                Text(week, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(width: 8),
                Expanded(child: Text('${weekHours.toStringAsFixed(1)}h + 承上${displayCarry.toStringAsFixed(1)} = ${diff.toStringAsFixed(1)}h', style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                Text('${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(1)}h', style: TextStyle(color: diff > 0 ? Colors.green : Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
              ]));
            }),
            const Divider(),
            Row(children: [
              Text('標準 ${standardWeeklyHours}h/週 | 總差額 ', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('${totalDiff >= 0 ? '+' : ''}${totalDiff.toStringAsFixed(1)}h', style: TextStyle(fontWeight: FontWeight.bold, color: totalDiff > 0 ? Colors.green : (totalDiff < 0 ? Colors.red : Colors.black))),
            ]),
          ]))),
          if (isYearReport) Card(color: const Color(0xFFF3E5F5), child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('年度累計工時差額', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(children: [
              Text('標準 ${standardWeeklyHours}h/週 | 總差額 ', style: const TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              Text('${totalDiff >= 0 ? '+' : ''}${totalDiff.toStringAsFixed(1)}h', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: totalDiff > 0 ? Colors.green : (totalDiff < 0 ? Colors.red : Colors.black))),
            ]),
            const SizedBox(height: 4),
            Text('（截至 ${year}年12月，累計差額）', style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ]))),
          Card(color: const Color(0xFFE8F5E9), child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(isYearReport ? '津貼類別 (含自定義類別) - 全年' : '津貼類別 (含自定義類別)', style: const TextStyle(fontWeight: FontWeight.bold)),
            Row(children: [const Text('班次津貼+單日額外'), const Spacer(), Text('\$${allow.toStringAsFixed(1)}')]),
            if (extraByType.isNotEmpty) const Divider(),
            ...extraByType.entries.map((e) => Row(children: [Text('類別: ${e.key}'), const Spacer(), Text('\$${e.value.toStringAsFixed(1)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple))])),
            Row(children: [Text('OT${ot.toStringAsFixed(1)}h x ${overtimeRate.toStringAsFixed(0)}'), const Spacer(), Text('\$${otAmount.toStringAsFixed(1)}')]),
            const Divider(),
            Row(children: [const Text('津貼總額'), const Spacer(), Text('\$${totalAllow.toStringAsFixed(1)}', style: const TextStyle(fontWeight: FontWeight.bold))]),
          ]))),
        ]),
      ),
    );
  }

  Widget settingsTab() {
    var stdCtrl = TextEditingController(text: standardWeeklyHours.toString());
    var carryCtrl = TextEditingController(text: carry.toString());
    List<MapEntry<String, ShiftDef>> shiftList = defs.entries.toList();
    List<MapEntry<String, ShiftDef>> shiftShow = showAllShift ? shiftList : shiftList.take(2).toList();
    List<ExtraAllowance> allowShow = showAllExtra ? extraAllowances : extraAllowances.take(5).toList();
    return SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('排更日曆自定名稱', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
        TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '日曆名稱', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        SizedBox(width: double.infinity, child: FilledButton(onPressed: () { setState(() => customName = nameCtrl.text.trim().isEmpty ? '我的排更' : nameCtrl.text.trim()); save(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('日曆名已改為 $customName'))); }, child: const Text('保存日曆名稱')))
      ]))),
      const SizedBox(height: 16),
      const Text('假期數據管理', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
        SizedBox(width: double.infinity, child: FilledButton.icon(icon: const Icon(Icons.beach_access), label: const Text('開啟假期數據管理'), onPressed: showLeaveManagementDialog)),
        const SizedBox(height: 8),
        SizedBox(width: double.infinity, child: FilledButton.icon(icon: const Icon(Icons.folder_open), label: const Text('匯出清單管理'), onPressed: showExportListManager, style: FilledButton.styleFrom(backgroundColor: Colors.blueGrey))),
      ]))),
      const SizedBox(height: 16),
      const Text('自定班次', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      Card(child: Column(children: [
        ...shiftShow.map((e) {
          var d = e.value;
          return ListTile(
            leading: CircleAvatar(backgroundColor: d.color, child: Text(d.code, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
            title: Text('${d.code} - ${d.label}', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: (d.hasLunch || d.hasMorningAllow || d.hasNightAllow || d.hasMealAllow || d.hasAL || d.hasSH || d.hasGH || d.hasWB || d.hasCustomLeave || d.alarmEnabled) ? Text('${d.hasMorningAllow ? '早/夜班 ' : ''}${d.hasNightAllow ? '通宵 ' : ''}${d.hasMealAllow ? '膳食 ' : ''}${d.hasLunch ? '午飯1h ' : ''}${d.hasAL ? 'AL ' : ''}${d.hasSH ? 'SH ' : ''}${d.hasGH ? 'GH ' : ''}${d.hasWB ? 'WB ' : ''}${d.hasCustomLeave ? '自訂假期(${d.customLeaveCode}) ' : ''}${d.alarmEnabled ? '鬧鐘(${d.alarmMinutesBefore}分前)' : ''}', style: const TextStyle(fontSize: 11, color: Colors.deepPurple)) : null,
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(icon: const Icon(Icons.edit), onPressed: () => editShiftDialog(oldDef: d)),
              IconButton(icon: const Icon(Icons.delete), onPressed: () { setState(() => defs.remove(e.key)); save(); })
            ])
          );
        }),
        if (shiftList.length > 2) TextButton(onPressed: () { setState(() => showAllShift = !showAllShift); }, child: Text(showAllShift ? '收起' : '顯示全部 ${shiftList.length}項')),
        ListTile(leading: const Icon(Icons.add), title: const Text('新增班次'), onTap: () => editShiftDialog()),
      ])),
      const SizedBox(height: 16),
      const Text('公眾假期地區 (自動從網路更新)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
        DropdownButtonFormField<String>(
          value: holidayRegion,
          decoration: const InputDecoration(labelText: '地區 (自動從網路抓取)', border: OutlineInputBorder()),
          items: ['無', '香港', '中國內地', '台灣', '美國'].map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
          onChanged: (v) {
            setState(() => holidayRegion = v!);
            save();
            if (v != '無') Future.microtask(() => _autoFetchHolidays());
          }
        ),
        const SizedBox(height: 8),
        Text('本年 ${focused.year} 假期數: ${getHolidays(focused.year, holidayRegion).length} 個', style: const TextStyle(fontSize: 12, color: Colors.grey)),
        if (_holidayLastUpdate.isNotEmpty)
          Text('上次更新: $_holidayLastUpdate', style: const TextStyle(fontSize: 10, color: Colors.grey)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: OutlinedButton.icon(
            icon: _holidayLoading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh, size: 18),
            label: Text(_holidayLoading ? '更新中...' : '從網路更新'),
            onPressed: _holidayLoading ? null : _manualRefreshHolidays,
          )),
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
          Expanded(child: OutlinedButton.icon(onPressed: googleSyncEnabled ? () async { if (await _confirmAction()) _syncToGoogle(); } : null, icon: const Icon(Icons.sync), label: const Text('手動同步'))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(onPressed: googleSyncEnabled ? () => syncDateRange() : null, icon: const Icon(Icons.date_range), label: const Text('範圍同步'))),
        ]),
        const SizedBox(height: 8),
        Row(children: [Expanded(child: OutlinedButton.icon(onPressed: () { setState(() => googleSyncEnabled = false); save(); }, icon: const Icon(Icons.link_off), label: const Text('取消')))]),
        Text('當前: $_rosterCalendarName\nID: ${_rosterCalendarId ?? '未選'}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 8),
        SizedBox(width: double.infinity, child: OutlinedButton.icon(icon: const Icon(Icons.list), label: const Text('選擇日曆'), onPressed: () async { await _pickGoogleCalendarDialog(); })),
        SizedBox(width: double.infinity, child: OutlinedButton.icon(icon: const Icon(Icons.security), label: const Text('重新請求日曆權限'), onPressed: () async { await handleCalendarPermission(silent: false); setState(() {}); })),
        const Divider(),
        Container(width: double.infinity, padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.red.withOpacity(0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red.withOpacity(0.3))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('⚠️ 全清重建（救援用）', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 13)),
            const Text('• 掃描範圍：2000年 ~ 2100年 (徹底清理)\n• 只刪 [RosterPro] 事件，個人行程不受影響\n• 全部操作使用當前日曆 ID + eventId', style: TextStyle(fontSize: 10, color: Colors.black54)),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: FilledButton.icon(
              onPressed: (googleSyncEnabled && !_isSyncing) ? _forceFullResync : null,
              icon: _isSyncing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.cleaning_services, size: 18),
              label: Text(_isSyncing ? '正在同步中...' : '執行全清重建'),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
            )),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: FilledButton.icon(
              onPressed: (googleSyncEnabled && !_isSyncing) ? _forceCleanDuplicates : null,
              icon: _isSyncing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.cleaning_services, size: 18),
              label: Text(_isSyncing ? '正在清理中...' : '強制清理重複事件'),
              style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            )),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: FilledButton.icon(
              onPressed: (googleSyncEnabled && !_isSyncing) ? _purgeRosterProInRange : null,
              icon: _isSyncing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.delete_forever, size: 18),
              label: Text(_isSyncing ? '正在清除中...' : '按範圍清除所有排班事件'),
              style: FilledButton.styleFrom(backgroundColor: Colors.deepOrange),
            )),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: OutlinedButton.icon(
              onPressed: () async {
                final calId = _rosterCalendarId;
                if (calId == null || calId.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('尚未選擇日曆'))); return; }
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('正在查詢日曆 ID: $calId ...'), duration: const Duration(seconds: 2)));
                final start = DateTime.now().subtract(const Duration(days: 365));
                final end = DateTime.now().add(const Duration(days: 365));
                List<Event> all;
                try {
                  all = await _safeRetrieveEvents(start, end);
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('查詢失敗：$e'), backgroundColor: Colors.red));
                  }
                  return;
                }
                final total = all.length;
                final withTag = all.where((e) => (e.description ?? '').contains('[RosterPro]')).length;
                final descNull = all.where((e) => e.description == null || e.description!.isEmpty).length;
                final descNotNull = total - descNull;

                StringBuffer samples = StringBuffer();
                int n = 0;
                for (var e in all) {
                  if (n >= 8) break;
                  n++;
                  final d = (e.description ?? '').replaceAll('\n', ' / ');
                  final isEmpty = e.description == null || e.description!.isEmpty;
                  final shortD = d.length > 60 ? '${d.substring(0, 60)}...' : d;
                  samples.writeln('[$n] title: ${e.title}');
                  samples.writeln('     desc : ${isEmpty ? '<<空>>' : shortD}');
                  samples.writeln('     id   : ${e.eventId}');
                  samples.writeln();
                }

                if (mounted) {
                  showDialog(context: context, builder: (ctx) => AlertDialog(
                    title: const Text('診斷結果'),
                    content: SizedBox(
                      width: 520,
                      height: 560,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('日曆 ID: $calId\n名稱: $_rosterCalendarName', style: const TextStyle(fontSize: 12)),
                          const Divider(),
                          Text('總事件數: $total', style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text('description 為空: $descNull', style: TextStyle(color: descNull > 0 ? Colors.red : Colors.green, fontWeight: FontWeight.bold)),
                          Text('description 有值: $descNotNull'),
                          Text('含 [RosterPro]: $withTag', style: TextStyle(color: withTag > 0 ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
                          const Divider(),
                          const Text('前 8 條事件樣本:', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Expanded(
                            child: SingleChildScrollView(
                              child: Text(
                                samples.toString(),
                                style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('關閉'))],
                  ));
                }
              },
              icon: const Icon(Icons.bug_report, size: 18),
              label: const Text('診斷日曆查詢'),
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
      const Text('標準工時 & 承上 & 標準時薪', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
        Row(children: [
          Expanded(child: TextField(controller: stdCtrl, decoration: const InputDecoration(labelText: '標準工時', suffixText: 'h/週', border: OutlineInputBorder()))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: carryCtrl, decoration: const InputDecoration(labelText: '承上餘額', border: OutlineInputBorder())))
        ]),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.amber.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('累計起始週 (承上基準)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 4),
              Text(
                carryAnchorWeekKey.isEmpty ? '未設定（將自動取最早排班週）' : carryAnchorWeekKey,
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.edit_calendar, size: 16),
                    label: const Text('修改起始週', style: TextStyle(fontSize: 12)),
                    onPressed: () async {
                      DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        helpText: '選擇要當作「累計起始」的日期\n該日期所在的 ISO 週將成為新的計算起點',
                      );
                      if (picked == null) return;
                      final newKey = isoWeekKey(picked);
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('修改累計起始週'),
                          content: Text(
                            '新的起始週：$newKey\n\n'
                            '目前承上餘額：${carry.toStringAsFixed(1)}h\n\n'
                            '⚠️ 這個設定會改變所有報表的累計差額起算點。\n'
                            '若只是刪除了早排班，不想改變基準，請選「取消」。',
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('確定修改')),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        setState(() { carryAnchorWeekKey = newKey; });
                        save();
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('累計起始週已改為 $newKey')));
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.restore, size: 16),
                    label: const Text('重設為最早排班', style: TextStyle(fontSize: 12)),
                    onPressed: () {
                      setState(() { carryAnchorWeekKey = ''; });
                      _ensureAnchorWeek();
                      save();
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已重設為 $carryAnchorWeekKey')));
                    },
                  ),
                ),
              ]),
              const SizedBox(height: 4),
              const Text(
                '💡 提示：刪除早排班時，若不想改變累計基準，保持此欄位不動即可。',
                style: TextStyle(fontSize: 10, color: Colors.black54),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              var salaryCtrl = TextEditingController(text: monthlySalary.toStringAsFixed(0));
              var divisorCtrl = TextEditingController(text: hourlyDivisor.toStringAsFixed(0));
              var multCtrl = TextEditingController(text: otMultiplier.toStringAsFixed(1));
              var mAllowCtrl = TextEditingController(text: morningAllowance.toStringAsFixed(0));
              var nAllowCtrl = TextEditingController(text: nightAllowance.toStringAsFixed(0));
              var mealCtrl = TextEditingController(text: mealAllowance.toStringAsFixed(0));
              var nightMultCtrl = TextEditingController(text: nightAllowMultiplier.toString());
              showDialog(context: context, builder: (ctx) {
                return StatefulBuilder(builder: (ctx2, setD) {
                  double calcHourly() { final s = double.tryParse(salaryCtrl.text) ?? 0; double d = double.tryParse(divisorCtrl.text) ?? 182; if (d <= 0) d = 182; return s / d; }
                  double calcOT() { final m = double.tryParse(multCtrl.text) ?? 1.5; return calcHourly() * m; }
                  double calcNightAllow() { final mult = double.tryParse(nightMultCtrl.text) ?? 0.4; return calcHourly() * (mult <= 0 ? 0 : mult); }
                  nAllowCtrl.text = calcNightAllow().toStringAsFixed(0);
                  return AlertDialog(
                    title: const Text('標準時薪設定'),
                    content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(controller: salaryCtrl, decoration: const InputDecoration(labelText: '每月月薪', prefixText: '\$ ', border: OutlineInputBorder()), keyboardType: TextInputType.number, onChanged: (_) => setD(() {})),
                      const SizedBox(height: 10),
                      TextField(controller: divisorCtrl, decoration: const InputDecoration(labelText: '每月工作時數 (預設 182)', border: OutlineInputBorder()), keyboardType: TextInputType.number, onChanged: (_) => setD(() {})),
                      const SizedBox(height: 10),
                      Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)), child: Row(children: [const Text('計算時薪：', style: TextStyle(fontWeight: FontWeight.bold)), const Spacer(), Text('\$${calcHourly().toStringAsFixed(0)}/h', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue))])),
                      const SizedBox(height: 10),
                      TextField(controller: multCtrl, decoration: const InputDecoration(labelText: '超時倍數 (預設 1.5)', border: OutlineInputBorder()), keyboardType: TextInputType.number, onChanged: (_) => setD(() {})),
                      const SizedBox(height: 10),
                      Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)), child: Row(children: [const Text('超時時薪：', style: TextStyle(fontWeight: FontWeight.bold)), const Spacer(), Text('\$${calcOT().toStringAsFixed(0)}/h', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.orange))])),
                      const SizedBox(height: 16),
                      const Text('固定津貼設定', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                      const SizedBox(height: 8),
                      Row(children: [Expanded(child: TextField(controller: mAllowCtrl, decoration: const InputDecoration(labelText: '早/夜班津貼', prefixText: '\$ ', isDense: true, border: OutlineInputBorder()), keyboardType: TextInputType.number, onChanged: (_) => setD(() {}))), const SizedBox(width: 8), Expanded(child: TextField(controller: mealCtrl, decoration: const InputDecoration(labelText: '膳食津貼', prefixText: '\$ ', isDense: true, border: OutlineInputBorder()), keyboardType: TextInputType.number, onChanged: (_) => setD(() {})))]),
                      const SizedBox(height: 8),
                      Row(children: [Expanded(child: TextField(controller: nightMultCtrl, decoration: const InputDecoration(labelText: '通宵倍數 (預設0.4)', isDense: true, border: OutlineInputBorder()), keyboardType: TextInputType.number, onChanged: (_) => setD(() {}))), const SizedBox(width: 8), Expanded(child: TextField(controller: nAllowCtrl, readOnly: true, enabled: false, decoration: const InputDecoration(labelText: '通宵時薪津貼 (自動計算)', prefixText: '\$ ', isDense: true, border: OutlineInputBorder(), filled: true, fillColor: Color(0xFFEEEEEE))))]),
                    ])),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx2), child: const Text('取消')),
                      FilledButton(onPressed: () {
                        final s = double.tryParse(salaryCtrl.text) ?? 0;
                        final d = double.tryParse(divisorCtrl.text) ?? 182;
                        final m = double.tryParse(multCtrl.text) ?? 1.5;
                        final mA = double.tryParse(mAllowCtrl.text) ?? 0;
                        final mealA = double.tryParse(mealCtrl.text) ?? 0;
                        final nMult = double.tryParse(nightMultCtrl.text) ?? 0.4;
                        final nA = (s / (d > 0 ? d : 182)) * (nMult <= 0 ? 0 : nMult);
                        setState(() {
                          monthlySalary = s; hourlyDivisor = d > 0 ? d : 182; otMultiplier = m > 0 ? m : 1.5;
                          overtimeRate = (monthlySalary / hourlyDivisor) * otMultiplier;
                          morningAllowance = mA; nightAllowance = nA; mealAllowance = mealA; nightAllowMultiplier = nMult;
                          for (var i = 0; i < extraAllowances.length; i++) { extraAllowances[i].amount = standardHourlyRate * extraAllowances[i].multiplier; }
                        });
                        save(); Navigator.pop(ctx2);
                      }, child: const Text('儲存')),
                    ],
                  );
                });
              });
            },
            icon: const Icon(Icons.calculate),
            label: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('標準時薪與固定津貼', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 2),
              Text('時薪 \$${standardHourlyRate.toStringAsFixed(0)}/h  ·  超時 \$${overtimeHourlyRate.toStringAsFixed(0)}/h', style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ])),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(width: double.infinity, child: FilledButton(onPressed: () {
          final v1 = double.tryParse(stdCtrl.text); final v2 = double.tryParse(carryCtrl.text);
          if (v1 != null) standardWeeklyHours = v1; if (v2 != null) carry = v2;
          setState(() {}); save();
        }, child: const Text('保存設定')))
      ]))),
      const SizedBox(height: 16),
      const Text('日曆顯示設定', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
        Row(children: [const Text('小'), Expanded(child: Slider(value: calendarFontSize, min: 8, max: 20, divisions: 12, onChanged: (v) { setState(() => calendarFontSize = v); })), const Text('大')]),
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
      const Text('App 圖標', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('使用系統預設圖標，或從相冊選擇圖片建立自訂圖標快捷方式', style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: FilledButton.icon(onPressed: () { setState(() => iconIndex = 0); save(); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已恢復預設圖標'))); }, icon: const Icon(Icons.apps), label: const Text('使用預設圖標'), style: FilledButton.styleFrom(backgroundColor: Colors.deepPurple))),
          const SizedBox(width: 8),
          Expanded(child: FilledButton.icon(onPressed: () async {
            try {
              final result = await _realChannel.invokeMethod('pickAndPinIcon');
              if (result == true) { setState(() => iconIndex = 1); save(); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已建立自訂圖標快捷方式，請到桌面查看'))); }
              else { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未選擇圖片'))); }
            } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('操作失敗 $e'))); }
          }, icon: const Icon(Icons.image), label: const Text('選擇相冊圖片'), style: FilledButton.styleFrom(backgroundColor: Colors.orange))),
        ]),
        const SizedBox(height: 8),
        Text(iconIndex == 0 ? '目前：系統預設圖標' : '目前：自訂圖標快捷方式', style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ]))),
      const SizedBox(height: 16),
      const Text('額外津貼 (自定名)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      Card(child: Column(children: [
        ...allowShow.map((e) {
          final int idx = extraAllowances.indexOf(e);
          return ListTile(
            title: Text(e.name),
            subtitle: Text('時薪 × ${e.multiplier} 倍 = \$${e.amount.toStringAsFixed(1)}'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(icon: const Icon(Icons.edit, size: 18, color: Colors.blue), onPressed: () {
                final nCtrl = TextEditingController(text: e.name);
                final mCtrl = TextEditingController(text: e.multiplier.toString());
                showDialog(context: context, builder: (ctx) {
                  return StatefulBuilder(builder: (ctx2, setD) {
                    double calcAmt() { final m = double.tryParse(mCtrl.text) ?? 1; return standardHourlyRate * (m <= 0 ? 1 : m); }
                    return AlertDialog(
                      title: const Text('編輯額外津貼'),
                      content: Column(mainAxisSize: MainAxisSize.min, children: [
                        SizedBox(height: 56, child: TextField(controller: nCtrl, decoration: const InputDecoration(labelText: '名稱', isDense: true, border: OutlineInputBorder()))),
                        const SizedBox(height: 8),
                        SizedBox(height: 56, child: TextField(controller: mCtrl, decoration: const InputDecoration(labelText: '倍數 (預設 1)', isDense: true, border: OutlineInputBorder()), keyboardType: TextInputType.number, onChanged: (_) => setD(() {}))),
                        const SizedBox(height: 8),
                        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)), child: Row(children: [const Text('計算金額：'), const Spacer(), Text('\$${calcAmt().toStringAsFixed(1)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green))])),
                      ]),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx2), child: const Text('取消')),
                        FilledButton(onPressed: () {
                          final name = nCtrl.text.trim();
                          final mulParsed = double.tryParse(mCtrl.text);
                          if (name.isEmpty) return;
                          final mulVal = (mulParsed == null || mulParsed <= 0) ? 1.0 : mulParsed;
                          final amt = standardHourlyRate * mulVal;
                          setState(() { extraAllowances[idx] = ExtraAllowance(name, amt, multiplier: mulVal); });
                          save(); Navigator.pop(ctx2);
                        }, child: const Text('儲存')),
                      ],
                    );
                  });
                });
              }),
              IconButton(icon: const Icon(Icons.delete, size: 18, color: Colors.red), onPressed: () { setState(() { extraAllowances.removeAt(idx); }); save(); }),
            ]),
          );
        }),
        ListTile(leading: const Icon(Icons.add), title: const Text('新增額外津貼'), onTap: () {
          final nCtrl = TextEditingController();
          final mCtrl = TextEditingController(text: '1');
          showDialog(context: context, builder: (ctx) {
            return StatefulBuilder(builder: (ctx2, setD) {
              double calcAmt() { final m = double.tryParse(mCtrl.text) ?? 1; return standardHourlyRate * (m <= 0 ? 1 : m); }
              return AlertDialog(
                title: const Text('新增額外津貼'),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(height: 56, child: TextField(controller: nCtrl, decoration: const InputDecoration(labelText: '名稱', isDense: true, border: OutlineInputBorder()))),
                  const SizedBox(height: 8),
                  SizedBox(height: 56, child: TextField(controller: mCtrl, decoration: const InputDecoration(labelText: '倍數 (預設 1)', isDense: true, border: OutlineInputBorder()), keyboardType: TextInputType.number, onChanged: (_) => setD(() {}))),
                  const SizedBox(height: 8),
                  Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)), child: Row(children: [const Text('計算金額：'), const Spacer(), Text('\$${calcAmt().toStringAsFixed(1)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green))])),
                  const SizedBox(height: 4),
                  Text('（時薪 \$${standardHourlyRate.toStringAsFixed(0)}/h × 倍數）', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                ]),
                actions: [
                  FilledButton(onPressed: () {
                    final name = nCtrl.text.trim();
                    final mulParsed = double.tryParse(mCtrl.text);
                    if (name.isEmpty) return;
                    final mulVal = (mulParsed == null || mulParsed <= 0) ? 1.0 : mulParsed;
                    final amt = standardHourlyRate * mulVal;
                    setState(() { extraAllowances.add(ExtraAllowance(name, amt, multiplier: mulVal)); });
                    save(); Navigator.pop(ctx2);
                  }, child: const Text('新增')),
                ],
              );
            });
          });
        }),
        if (extraAllowances.length > 5)
          TextButton(onPressed: () { setState(() => showAllExtra = !showAllExtra); }, child: Text(showAllExtra ? '收起' : '顯示全部 ${extraAllowances.length}項')),
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
        const Text('字體大小與顏色已自動優化至最佳狀態（不溢出格子）', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 13)),
        const SizedBox(height: 8),
        SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () { save(); }, icon: const Icon(Icons.refresh), label: const Text('強制刷新小工具'))),
      ]))),
      const SizedBox(height: 16),
      const Text('應用資訊', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      Card(child: ListTile(
        leading: const Icon(Icons.info_outline),
        title: const Text('版本號'),
        subtitle: Text(appVersion),
        trailing: TextButton.icon(onPressed: showUserManual, icon: const Icon(Icons.help_outline, size: 18), label: const Text('操作說明', style: TextStyle(fontSize: 12))),
      )),
      const SizedBox(height: 16),
    ]));
  }

  void showUserManual() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [Icon(Icons.menu_book, color: Colors.deepPurple), SizedBox(width: 8), Text('App 操作說明書')]),
        content: SizedBox(
          width: 500,
          height: 600,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('1. 月曆主頁', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.deepPurple)),
                SizedBox(height: 4),
                Text('• 點擊日期可查看詳情，長按可直接編輯。\n• 左右滑動可切換月份。\n• 點擊上方「今天」按鈕可快速回到當天。\n• 點擊「相機」圖標可截圖整月排班並分享。\n• 點擊「記事」圖標可查詢所有帶有備註的日期。\n• 點擊「海灘」圖標可查詢假期清單與餘額結算。', style: TextStyle(fontSize: 13)),
                SizedBox(height: 16),
                Text('2. 模式設定', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.deepPurple)),
                SizedBox(height: 4),
                Text('• 點擊下方色塊選擇班次，再點擊上方格子填入。\n• 「自定行數」可增加排班週期行數。\n• 「自動排班」可選擇已存模式套用到指定日期範圍。\n• 「智能排班」可選擇模式並自動排 4 個週期的班。\n• 可將常用模式「另存為新模式」方便下次使用。', style: TextStyle(fontSize: 13)),
                SizedBox(height: 16),
                Text('3. 報表與統計', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.deepPurple)),
                SizedBox(height: 4),
                Text('• 顯示本月或全年的工時統計、班次次數。\n• 自動計算 OT 時數與津貼總額。\n• 顯示每週工時與標準工時的差額。\n• 點擊「匯出」可將報表存為 CSV 檔案。\n• 左右滑動可切換上/下月份（或上/下年份）。', style: TextStyle(fontSize: 13)),
                SizedBox(height: 16),
                Text('4. 設定與同步', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.deepPurple)),
                SizedBox(height: 4),
                Text('• 「假期數據管理」：可設定每年的假期天數、微調，系統會自動計算餘額。\n• 「匯出清單管理」：可查看、刪除、分享所有匯出的檔案。\n• 「自定班次」：可修改班次名稱、顏色、時間、津貼及假期設定（AL/SH/GH/WB）。\n• 「上班鬧鐘」：在班次編輯卡內開啟鬧鐘，點擊時間框選一個時間，系統會自動計算提前分鐘數。\n  - 可自訂鈴聲：點擊「鬧鐘鈴聲」可選擇系統鈴聲並試聽。\n  - 單日臨時關閉：在日期編輯卡內可針對單獨一日臨時關閉鬧鐘，不影響其他日期。\n• 「公眾假期」：自動從網路 API 抓取（date.nager.at），覆蓋當年+明年+後年，切換地區自動更新。\n  - 點「從網路更新」可強制重新抓取前 1 年 ~ 後 3 年。\n  - 離線時降級使用內建假期（2024~2030）。\n• 「農曆」：本地計算支援 1900~2100 年，超出範圍顯示空白（不崩潰）。\n• 「日曆同步」：開啟後可選擇已有日曆或建立自訂日曆來寫入排班。\n  - 手動同步：立即同步所有變更。\n  - 範圍同步：只同步指定日期範圍內的變更。\n  - 全清重建：掃描範圍 2000~2100 年，只刪 [RosterPro] 事件。\n• 「備份與還原」：可將所有設定備份為 JSON 檔案，或從檔案還原。\n• 「桌面小工具」：字體與顏色已自動優化。', style: TextStyle(fontSize: 13)),
                SizedBox(height: 16),
                Text('5. 常見問題', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.deepPurple)),
                SizedBox(height: 4),
                Text('• Q: 小工具剛加入時字體很大？\n  A: 已優化，若仍出現請重新整理小工具。\n\n• Q: 同步失敗？\n  A: 請確認已選擇正確的日曆，並檢查權限。\n\n• Q: 換手機如何轉移資料？\n  A: 使用「備份」功能將 JSON 檔案匯出，再到新手機「從檔案還原」。', style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('關閉'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: [calTab(), patternTab(), reportTab(), settingsTab()][tab],
      bottomNavigationBar: NavigationBar(
        height: 55,
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
