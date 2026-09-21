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

void main() => runApp(const RosterProApp());

class ShiftDef {
  String code; String label; double hours; double allowance; double otHours; Color color;
  ShiftDef(this.code, this.label, this.hours, this.color, {this.allowance=0, this.otHours=0});
  Map<String,dynamic> toJson() => {'code':code,'label':label,'hours':hours,'allowance':allowance,'otHours':otHours,'color':color.value};
  static ShiftDef fromJson(Map<String,dynamic> j) => ShiftDef(j['code'], j['label']??j['code'], (j['hours']??8).toDouble(), Color(j['color']??0xFFFF9800), allowance:(j['allowance']??0).toDouble(), otHours:(j['otHours']??0).toDouble());
}

class RosterProApp extends StatelessWidget {
  const RosterProApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Roster Pro v6.19.1',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.deepPurple),
      home: const MainPage(),
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});
  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _index = 0;
  DateTime focused = DateTime(2026, 9, 1);
  Map<String, String> roster = {};
  Map<String, ShiftDef> defs = {
    '早': ShiftDef('早','早班 08-16',8, Colors.orange),
    '中': ShiftDef('中','中班 16-00',8, Colors.blue),
    '宵': ShiftDef('宵','宵班 00-08',8, Colors.purple, allowance: 60),
    'OT': ShiftDef('OT','OT 2小時',0, Colors.brown, otHours: 2),
    '早收': ShiftDef('早收','早收長代號測試',8, Colors.orange), // 測試不限制長度
    'O': ShiftDef('O','休',0, Colors.green),
  };
  bool googleSync = true;
  String customCalendarName = "我的排更";
  String? rosterCalendarId;
  double carryOver = 0.0;
  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: [drive.DriveApi.driveFileScope, cal.CalendarApi.calendarScope]);

  @override
  void initState(){ super.initState(); _load(); }
  Future<void> _load() async {
    var sp = await SharedPreferences.getInstance();
    var r = sp.getString('roster'); if(r!=null) roster = Map<String,String>.from(jsonDecode(r));
    var d = sp.getString('defs'); if(d!=null){ var m = Map<String,dynamic>.from(jsonDecode(d)); defs = m.map((k,v)=>MapEntry(k, ShiftDef.fromJson(v))); }
    setState((){
      customCalendarName = sp.getString('customCalName')?? "我的排更";
      rosterCalendarId = sp.getString('rosterCalId');
      carryOver = sp.getDouble('carry')?? 0;
      googleSync = sp.getBool('gSync')?? true;
    });
  }
  Future<void> _save() async {
    var sp = await SharedPreferences.getInstance();
    sp.setString('roster', jsonEncode(roster));
    sp.setString('defs', jsonEncode(defs.map((k,v)=>MapEntry(k, v.toJson()))));
    sp.setString('customCalName', customCalendarName);
    if(rosterCalendarId!=null) sp.setString('rosterCalId', rosterCalendarId!);
    sp.setDouble('carry', carryOver);
    sp.setBool('gSync', googleSync);
  }

  Map<String,String> _holidays = {'09-22':'秋分','09-25':'中秋翌日'};
  bool _isHoliday(DateTime d){ return _holidays.containsKey(DateFormat('MM-dd').format(d)); }
  String _holidayName(DateTime d){ return _holidays[DateFormat('MM-dd').format(d)]??''; }

  Map<String,dynamic> getReport(DateTime month){
    int dim = DateTime(month.year, month.month+1, 0).day;
    Map<String,int> count={}; double ot=0, allow=0, hrs=0;
    for(int i=1;i<=dim;i++){
      String key = DateFormat('yyyy-MM-dd').format(DateTime(month.year, month.month, i));
      String? code = roster[key]; if(code==null) continue;
      count[code]=(count[code]??0)+1;
      var def = defs[code]; if(def!=null){ hrs+=def.hours; ot+=def.otHours; allow+=def.allowance; }
    }
    return {'count':count,'ot':ot,'allow':allow,'hrs':hrs,'balance':carryOver+hrs-168};
  }

  Widget _buildDay(DateTime day, bool isThisMonth){
    if(!isThisMonth) return Container(margin: const EdgeInsets.all(4));
    String key = DateFormat('yyyy-MM-dd').format(day);
    String? code = roster[key];
    var def = code!=null? defs[code] : null;
    return GestureDetector(
      onTap: ()=>_pickShift(day),
      child: Container(
        margin: const EdgeInsets.all(3),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: def!=null? def.color.withOpacity(0.25) : const Color(0xFFF2F4E8), borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          Text('${day.day}', style: const TextStyle(fontWeight: FontWeight.bold)),
          if(_isHoliday(day)) Text(_holidayName(day), style: const TextStyle(fontSize:9, color: Colors.red)),
          if(code!=null) Container(
            margin: const EdgeInsets.only(top:2),
            padding: const EdgeInsets.symmetric(horizontal:6, vertical:2),
            decoration: BoxDecoration(color: def?.color?? Colors.orange, borderRadius: BorderRadius.circular(10)),
            child: FittedBox(fit: BoxFit.scaleDown, child: Text(code, maxLines:2, softWrap:true, overflow:TextOverflow.visible, style: const TextStyle(fontSize:12, color: Colors.white, fontWeight: FontWeight.bold))),
          )
        ]),
      ),
    );
  }

  Widget _buildCalendar(){
    DateTime first = DateTime(focused.year, focused.month, 1);
    int firstW = first.weekday; int dim = DateTime(focused.year, focused.month+1, 0).day;
    List<Widget> cells=[]; for(int i=1;i<firstW;i++) cells.add(Container(margin: const EdgeInsets.all(4)));
    for(int i=1;i<=dim;i++) cells.add(_buildDay(DateTime(focused.year, focused.month, i), true));
    var rep = getReport(focused);
    return CustomScrollView(slivers: [
      SliverAppBar(pinned:true, title: Text('${focused.year}年${focused.month}月'), actions: [
