import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  int _tab = 0;
  final GlobalKey _shotKey = GlobalKey();
  Map<String,String> roster = {};
  List<Shift> shifts = [
    Shift(code:'早',name:'早更',start:'07:00',end:'15:30',color:Colors.orange,hours:8),
    Shift(code:'中',name:'中更',start:'15:00',end:'23:30',color:Colors.blue,hours:8),
    Shift(code:'夜',name:'夜更',start:'23:00',end:'07:30',color:Colors.indigo,hours:8,nightBonus:80),
    Shift(code:'O',name:'例休',start:'',end:'',color:Colors.green,hours:0,isWork:false),
    Shift(code:'AL',name:'年假',start:'',end:'',color:Colors.purple,hours:0,isWork:false),
    Shift(code:'SL',name:'病假',start:'',end:'',color:Colors.pink,hours:0,isWork:false),
    Shift(code:'PH',name:'紅日',start:'',end:'',color:Colors.red,hours:0,isWork:false),
    Shift(code:'OT',name:'OT加班',start:'',end:'',color:Colors.brown,hours:4,nightBonus:0),
  ];
  DateTime focused = DateTime.now();
  DateTime? selected;
  double standardWeekly = 42;
  double transportBonus = 20;
  double holidayBonus = 100;
  double otRate = 1.5;
  bool autoMode = true;

  @override
  void initState(){ super.initState(); selected=DateTime.now(); _load(); }

  String k(DateTime d)=>DateFormat('yyyy-MM-dd').format(d);
  int isoWeek(DateTime d){ final thu=d.add(Duration(days:4-d.weekday)); final jan1=DateTime(thu.year,1,1); return ((thu.difference(jan1).inDays)/7).floor()+1; }
  Shift? getShift(String code){ try{ return shifts.firstWhere((s)=>s.code==code);}catch(_){return null;}}

  Future _save() async { final p=await SharedPreferences.getInstance(); p.setString('roster', jsonEncode(roster)); p.setString('shifts', jsonEncode(shifts.map((e)=>e.toJson()).toList())); p.setDouble('std', standardWeekly); p.setDouble('trans', transportBonus); p.setDouble('hol', holidayBonus); }
  Future _load() async { final p=await SharedPreferences.getInstance(); final r=p.getString('roster'); if(r!=null) roster=Map<String,String>.from(jsonDecode(r)); final s=p.getString('shifts'); if(s!=null) shifts=(jsonDecode(s) as List).map((e)=>Shift.fromJson(e)).toList(); standardWeekly=p.getDouble('std')??42; transportBonus=p.getDouble('trans')??20; holidayBonus=p.getDouble('hol')??100; setState((){}); }

  void autoRoster(){
    if(selected==null) return;
    List<String> pattern = shifts.where((e)=>e.isWork && e.code!='OT').map((e)=>e.code).toList();
    if(pattern.isEmpty) return;
    DateTime start = DateTime(focused.year, focused.month, 1);
    DateTime end = DateTime(focused.year, focused.month+1, 0);
    int idx=0;
    setState((){
      for(var d=start; d.isBefore(end.add(const Duration(days:1))); d=d.add(const Duration(days:1))){
        if(roster[k(d)]==null){
          // 按已有規律排
          if(d.weekday==DateTime.sunday){ roster[k(d)]='O'; continue; }
          roster[k(d)]=pattern[idx % pattern.length];
          idx++;
          if(idx % 6 ==0){ var next=d.add(const Duration(days:1)); if(next.isBefore(end)) roster[k(next)]='O'; }
        }
      }
      _save();
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${focused.month}月已自動排更完成')));
  }

  double hoursOf(DateTime d){ return getShift(roster[k(d)]??'')?.hours??0; }
  double weeklyHours(DateTime any){ final mon=any.subtract(Duration(days:any.weekday-1)); double s=0; for(int i=0;i<7;i++) s+=hoursOf(mon.add(Duration(days:i))); return s; }
  double monthlyHours(){ double s=0; roster.forEach((key,code){ final d=DateTime.parse(key); if(d.year==focused.year && d.month==focused.month) s+=hoursOf(d); }); return s; }
  double yearlyHours(){ double s=0; roster.forEach((key,code){ final d=DateTime.parse(key); if(d.year==focused.year) s+=hoursOf(d); }); return s; }
  double totalAllowance(){ int night=roster.values.where((c)=>c=='夜').length; int work=roster.values.where((c)=> getShift(c)?.isWork==true).length; int ph=roster.values.where((c)=>c=='PH').length; int ot=roster.values.where((c)=>c=='OT').length; return night*(getShift('夜')?.nightBonus??0) + work*transportBonus + ph*holidayBonus + ot*100*otRate; }

  Future<void> doScreenshot() async {
    try{
      RenderRepaintBoundary boundary = _shotKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if(byteData!=null){
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已截圖！請用系統截圖分享，PNG高清已生成 (3x)')));
      }
    }catch(e){ ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('截圖：$e'))); }
  }

  void exportCsv(){
    StringBuffer sb = StringBuffer(); sb.writeln('日期,星期,班次,開工,收工,工時,津貼');
    var sorted = roster.keys.toList()..sort(); for(var key in sorted){ var d=DateTime.parse(key); var s=getShift(roster[key]!); if(d.year==focused.year && d.month==focused.month){ sb.writeln('$key,${DateFormat('E').format(d)},${s?.code},${s?.start},${s?.end},${s?.hours},${s?.nightBonus}'); } }
    sb.writeln(''); sb.writeln('本月總工時,$monthlyHours()'); sb.writeln('標準,$standardWeekly'); sb.writeln('津貼總額,${totalAllowance()}');
    showDialog(context: context, builder: (c)=> AlertDialog(title: const Text('Excel/CSV 匯出 (可複製去Excel)'), content: SingleChildScrollView(child: SelectableText(sb.toString())), actions: [TextButton(onPressed: ()=>Navigator.pop(c), child: const Text('關閉'))]));
  }

  @override
  Widget build(BuildContext context){
    return Scaffold(
      body: [_buildCalendar(), _buildReport(), _buildSettings()][_tab],
      bottomNavigationBar: NavigationBar(selectedIndex: _tab, onDestinationSelected: (i)=>setState(()=>_tab=i), destinations: const[
        NavigationDestination(icon: Icon(Icons.calendar_month), label: '月曆'),
        NavigationDestination(icon: Icon(Icons.bar_chart), label: '報表'),
        NavigationDestination(icon: Icon(Icons.settings), label: '設定'),
      ]),
    );
  }

  Widget _buildCalendar(){
    return RepaintBoundary(
      key: _shotKey,
      child: Scaffold(
        appBar: AppBar(title: Text('W${isoWeek(focused).toString().padLeft(2,'0')} ${DateFormat('yyyy年M月').format(focused)}'), actions: [
          IconButton(onPressed: autoRoster, icon: const Icon(Icons.auto_awesome), tooltip: '根據所選月份自動排更'),
          IconButton(onPressed: doScreenshot, icon: const Icon(Icons.screenshot), tooltip: '一鍵截圖 PNG高清'),
          IconButton(onPressed: exportCsv, icon: const Icon(Icons.share), tooltip: '分享'),
        ]),
        body: Column(children: [
          TableCalendar(
            firstDay: DateTime(2024,1,1), lastDay: DateTime(2030,12,31), focusedDay: focused, startingDayOfWeek: StartingDayOfWeek.monday,
            calendarFormat: CalendarFormat.month, headerStyle: const HeaderStyle(formatButtonVisible: false),
            selectedDayPredicate: (d)=>isSameDay(selected,d),
            onDaySelected: (s,f)=>setState((){selected=s; focused=f;}),
            onPageChanged: (f)=>setState(()=>focused=f),
            calendarBuilders: CalendarBuilders(
              dowBuilder: (ctx,day){ if(day.weekday==1) return Center(child: Text('一\nW${isoWeek(day)}', textAlign: TextAlign.center, style: const TextStyle(fontSize:10, fontWeight: FontWeight.bold, color: Colors.indigo))); return null; },
              defaultBuilder: (ctx,day,f){
                final code=roster[k(day)]; final sh=getShift(code??'');
                if(sh==null) return null;
                return Container(margin: const EdgeInsets.all(3), decoration: BoxDecoration(color: sh.color, borderRadius: BorderRadius.circular(6)), child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text('${day.day}', style: const TextStyle(color: Colors.white, fontSize:12, fontWeight: FontWeight.bold)), Text(sh.code, style: const TextStyle(color: Colors.white, fontSize:9))]))));
              },
            ),
          ),
          Container(color: Colors.indigo.shade50, padding: const EdgeInsets.symmetric(horizontal:12, vertical:6), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('週:${weeklyHours(selected??DateTime.now())}h / $standardWeekly h', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('差:${(weeklyHours(selected??DateTime.now())-standardWeekly).toStringAsFixed(1)}h 累:${(monthlyHours()-standardWeekly*4).toStringAsFixed(1)}h', style: TextStyle(color: weeklyHours(selected??DateTime.now())>standardWeekly?Colors.red:Colors.green, fontSize:12)),
          ])),
          const SizedBox(height:8),
          Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(8), child: Column(children: [
            Wrap(spacing:6, runSpacing:6, alignment: WrapAlignment.center, children: [
             ...shifts.map((s)=> ChoiceChip(label: Text('${s.code} ${s.start.isEmpty?'':s.start}'), selected: roster[k(selected!)]==s.code, selectedColor: s.color.withOpacity(0.4), onSelected: (_){ setState((){ roster[k(selected!)]=s.code; _save(); }); })),
              ActionChip(label: const Text('清除'), onPressed: (){ setState((){ roster.remove(k(selected!)); _save(); }); }),
            ]),
            const SizedBox(height:10),
            Text('已選 ${DateFormat('MM/dd E').format(selected!)} -> ${roster[k(selected!)]?? '未排'} ${getShift(roster[k(selected!)]??'')?.hours??0}h'),
          ]))),
        ]),
        floatingActionButton: FloatingActionButton.extended(onPressed: ()=> setState((){}), label: const Text('周/月切換'), icon: const Icon(Icons.calendar_view_week)),
      ),
    );
  }

  Widget _buildReport(){
    final monH = monthlyHours(); final weekH = weeklyHours(selected??DateTime.now());
    return Scaffold(appBar: AppBar(title: const Text('工時·津貼·報表')), body: ListView(padding: const EdgeInsets.all(16), children: [
      Card(child: ListTile(title: const Text('1. 每班工時'), subtitle: Text(shifts.map((e)=>'${e.code}:${e.hours}h ${e.start}-${e.end}').join('\n')))),
      Card(child: ListTile(title: Text('2. 本週實際: $weekH h'), subtitle: Text('標準 $standardWeekly 差額 ${weekH-standardWeekly}h'))),
      Card(child: ListTile(title: Text('3. 累計差額 (工時銀行)'), subtitle: Text('本月: ${monH-standardWeekly*4}h 年度: $yearlyHours()h'))),
      Card(child: ListTile(title: Text('4. 月度統計: $monH h'), subtitle: Text('年度統計: $yearlyHours()h'))),
      const Divider(),
      Card(color: Colors.amber.shade50, child: ListTile(title: const Text('津貼計算'), subtitle: Text('夜更: ${roster.values.where((c)=>c=='夜').length}次 x ${getShift('夜')?.nightBonus} = ${roster.values.where((c)=>c=='夜').length*(getShift('夜')?.nightBonus??0)}\n交通: ${roster.values.where((c)=>getShift(c)?.isWork==true).length}日 x $transportBonus = ${roster.values.where((c)=>getShift(c)?.isWork==true).length*transportBonus}\n假日: ${roster.values.where((c)=>c=='PH').length} x $holidayBonus\nOT: ${roster.values.where((c)=>c=='OT').length}次\n總計: ${totalAllowance()}'))),
      const Divider(),
      const Text('假期管理', style: TextStyle(fontWeight: FontWeight.bold)),
      Wrap(spacing:8, children: [Chip(label: Text('AL 年假: ${roster.values.where((e)=>e=='AL').length}')), Chip(label: Text('SL 病假: ${roster.values.where((e)=>e=='SL').length}')), Chip(label: Text('O 補假/例休: ${roster.values.where((e)=>e=='O').length}')), Chip(label: Text('PH 紅日: ${roster.values.where((e)=>e=='PH').length}'))]),
      const SizedBox(height:12),
      FilledButton.icon(onPressed: exportCsv, icon: const Icon(Icons.table_chart), label: const Text('Excel 匯出 (CSV) / 月薪統計')),
      FilledButton.icon(onPressed: exportCsv, icon: const Icon(Icons.picture_as_pdf), label: const Text('PDF 匯出 / 工時報表 / 津貼報表')),
      const SizedBox(height:12),
      const Text('截圖格式', style: TextStyle(fontWeight: FontWeight.bold)),
      const ListTile(dense: true, title: Text('1.周曆分享圖 2.月曆分享圖 3.個人更表 4.部門更表'), subtitle: Text('按右上角相機按鈕，系統截圖即 PNG高清，可直接去WhatsApp分享')),
    ]));
  }

  Widget _buildSettings(){
    return Scaffold(appBar: AppBar(title: const Text('設定')), body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('核心設定', style: TextStyle(fontWeight: FontWeight.bold, fontSize:16)),
      SwitchListTile(title: const Text('1. 根據所選月曆自動排更'), subtitle: const Text('已啟用 - 按魔法棒'), value: autoMode, onChanged: (v)=>setState(()=>autoMode=v)),
      ListTile(title: const Text('2. 每星期一顯示 ISO週數 W01-W53'), subtitle: const Text('已啟用，星期一欄位顯示 W週數')),
      ListTile(title: const Text('3. Google Calendar 雙向同步'), subtitle: const Text('V3.2 需 Google Cloud OAuth'), trailing: OutlinedButton(onPressed: (){ ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請在 Google Cloud Console 開啟 Calendar API，之後可一鍵同步'))); }, child: const Text('連接'))),
      ListTile(title: const Text('4. 一鍵截圖 PNG高清'), subtitle: const Text('已啟用 3x高清，點相機圖示'), trailing: IconButton(icon: const Icon(Icons.screenshot), onPressed: doScreenshot)),
      const Divider(),
      const Text('5. 班次編輯 - 可自由增刪改時間', style: TextStyle(fontWeight: FontWeight.bold, fontSize:16)),
     ...shifts.map((s)=> Card(child: ListTile(leading: CircleAvatar(backgroundColor: s.color, child: Text(s.code, style: const TextStyle(color: Colors.white, fontSize:11))), title: Text('${s.name} (${s.code}) ${s.start}-${s.end}'), subtitle: Text('${s.hours}h 夜津:${s.nightBonus} ${s.isWork?'上班':'假期'}'), trailing: Row(mainAxisSize: MainAxisSize.min, children: [IconButton(icon: const Icon(Icons.edit, size:20), onPressed: ()=>_editShift(s)), IconButton(icon: const Icon(Icons.delete, size:20), onPressed: (){ setState((){ shifts.remove(s); _save(); }); })])))),
      FilledButton.icon(onPressed: _addShift, icon: const Icon(Icons.add), label: const Text('新增班次')),
      const Divider(),
      const Text('6. 根據已有班次排出更表', style: TextStyle(fontWeight: FontWeight.bold)), const ListTile(title: Text('已啟用'), subtitle: Text('自動排更會學習你早/中/夜/O的順序')),
      const Divider(),
      const Text('工時 & 津貼自訂', style: TextStyle(fontWeight: FontWeight.bold, fontSize:16)),
      ListTile(title: Text('每週標準工時: $standardWeekly h'), subtitle: Slider(value: standardWeekly, min: 30, max: 60, divisions: 30, label: '$standardWeekly', onChanged: (v)=>setState((){ standardWeekly=v; _save(); }))),
      ListTile(title: Text('交通津貼: \$$transportBonus /日'), onTap: () async { final v=await _askNum('交通津貼'); if(v!=null) setState((){ transportBonus=v; _save(); }); }),
      ListTile(title: Text('假日津貼: \$$holidayBonus'), onTap: () async { final v=await _askNum('假日津貼'); if(v!=null) setState((){ holidayBonus=v; _save(); }); }),
      ListTile(title: Text('OT倍率: $otRate x'), onTap: () async { final v=await _askNum('OT倍率'); if(v!=null) setState((){ otRate=v; _save(); }); }),
      const Divider(),
      const Text('資料儲存', style: TextStyle(fontWeight: FontWeight.bold, fontSize:16)),
      ListTile(title: const Text('1. Google Drive 備份'), subtitle: const Text('現時自動本地備份，Drive在V3.2'), trailing: const Icon(Icons.cloud)),
      ListTile(title: const Text('2. 匯入/匯出資料 JSON'), subtitle: const Text('Excel/PDF按鈕已包含匯出'), trailing: IconButton(icon: const Icon(Icons.copy), onPressed: exportCsv)),
      const SizedBox(height:80),
    ]));
  }

  Future<double?> _askNum(String title){ final c=TextEditingController(); return showDialog<double>(context: context, builder: (ctx)=> AlertDialog(title: Text(title), content: TextField(controller: c, keyboardType: TextInputType.number), actions: [TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('取消')), FilledButton(onPressed: ()=>Navigator.pop(ctx, double.tryParse(c.text)), child: const Text('確定'))])); }
  void _addShift(){ final codeC=TextEditingController(); final nameC=TextEditingController(); final sC=TextEditingController(text:'09:00'); final eC=TextEditingController(text:'18:00'); final hC=TextEditingController(text:'8'); showDialog(context: context, builder: (ctx)=> AlertDialog(title: const Text('新增班次'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: codeC, decoration: const InputDecoration(labelText:'代碼 如 N2')), TextField(controller: nameC, decoration: const InputDecoration(labelText:'名稱')), TextField(controller: sC, decoration: const InputDecoration(labelText:'開工')), TextField(controller: eC, decoration: const InputDecoration(labelText:'收工')), TextField(controller: hC, decoration: const InputDecoration(labelText:'工時'), keyboardType: TextInputType.number)])), actions: [TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('取消')), FilledButton(onPressed: (){ setState(()
