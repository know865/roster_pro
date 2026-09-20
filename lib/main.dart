import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const RosterApp());

class RosterApp extends StatelessWidget {
  const RosterApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const MainPage(),
    );
  }
}

class Shift {
  String code; String name; String start; String end; Color color; double hours; double nightBonus; bool isWork;
  Shift({required this.code, required this.name, required this.start, required this.end, required this.color, required this.hours, this.nightBonus=0, this.isWork=true});
  Map toJson() => {'code':code,'name':name,'start':start,'end':end,'color':color.value,'hours':hours,'nightBonus':nightBonus,'isWork':isWork};
  static Shift fromJson(Map m) => Shift(code:m['code'],name:m['name'],start:m['start'],end:m['end'],color:Color(m['color']),hours:(m['hours'] as num).toDouble(),nightBonus:(m['nightBonus']??0).toDouble(),isWork:m['isWork']??true);
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});
  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int tab = 0;
  Map<String,String> roster = {};
  List<Shift> shifts = [
    Shift(code:'早',name:'早更',start:'07:00',end:'15:30',color:Colors.orange,hours:8),
    Shift(code:'中',name:'中更',start:'15:00',end:'23:30',color:Colors.blue,hours:8),
    Shift(code:'夜',name:'夜更',start:'23:00',end:'07:30',color:Colors.indigo,hours:8,nightBonus:80),
    Shift(code:'O',name:'例休',start:'',end:'',color:Colors.green,hours:0,isWork:false),
    Shift(code:'AL',name:'年假',start:'',end:'',color:Colors.purple,hours:0,isWork:false),
    Shift(code:'SL',name:'病假',start:'',end:'',color:Colors.pink,hours:0,isWork:false),
    Shift(code:'PH',name:'紅日',start:'',end:'',color:Colors.red,hours:0,isWork:false),
  ];
  DateTime focused = DateTime.now();
  DateTime? selected;
  double standardWeekly = 42;

  @override
  void initState(){ super.initState(); selected=DateTime.now(); _load(); }

  String k(DateTime d)=>DateFormat('yyyy-MM-dd').format(d);
  int isoWeek(DateTime d){ final thu=d.add(Duration(days:4-d.weekday)); final jan1=DateTime(thu.year,1,1); return ((thu.difference(jan1).inDays)/7).floor()+1; }
  Shift? getShift(String code){ try{ return shifts.firstWhere((s)=>s.code==code);}catch(_){return null;}}

  Future<void> save() async { final p=await SharedPreferences.getInstance(); p.setString('roster', jsonEncode(roster)); p.setString('shifts', jsonEncode(shifts.map((e)=>e.toJson()).toList())); p.setDouble('std', standardWeekly); }
  Future<void> _load() async { final p=await SharedPreferences.getInstance(); final r=p.getString('roster'); if(r!=null) roster=Map<String,String>.from(jsonDecode(r)); final s=p.getString('shifts'); if(s!=null) shifts=(jsonDecode(s) as List).map((e)=>Shift.fromJson(e)).toList(); standardWeekly=p.getDouble('std')??42; setState((){}); }

  void autoRoster(){
    List<String> pattern = shifts.where((e)=>e.isWork).map((e)=>e.code).toList();
    DateTime start = DateTime(focused.year, focused.month, 1);
    DateTime end = DateTime(focused.year, focused.month+1, 0);
    int idx=0;
    setState((){
      for(var d=start; d.isBefore(end.add(const Duration(days:1))); d=d.add(const Duration(days:1))){
        if(roster[k(d)]==null){
          if(d.weekday==DateTime.sunday){ roster[k(d)]='O'; continue; }
          roster[k(d)]=pattern[idx % pattern.length]; idx++;
        }
      }
      save();
    });
  }

  double hoursOf(DateTime d){ return getShift
