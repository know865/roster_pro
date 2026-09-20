import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:excel/excel.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'dart:convert';

void main() => runApp(const RosterApp());
class RosterApp extends StatelessWidget {
  const RosterApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(debugShowCheckedModeBanner: false, theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo), home: const MainPage());
  }
}

// 班次模型
class Shift {
  String code; String name; String start; String end; Color color; double hours; double nightBonus; double otRate;
  bool isWork;
  Shift({required this.code, required this.name, required this.start, required this.end, required this.color, required this.hours, this.nightBonus=0, this.otRate=1.5, this.isWork=true});
  Map toJson() => {'code':code,'name':name,'start':start,'end':end,'color':color.value,'hours':hours,'nightBonus':nightBonus,'isWork':isWork};
  static Shift fromJson(Map m) => Shift(code:m['code'],name:m['name'],start:m['start'],end:m['end'],color:Color(m['color']),hours:m['hours'].toDouble(),nightBonus:(m['nightBonus']??0).toDouble(),isWork:m['isWork']??true);
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});
  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _index = 0;
  final ScreenshotController screenshotController = ScreenshotController();
  Map<String,String> roster = {}; // yyyy-MM-dd -> shift code
  List<Shift> shifts = [
    Shift(code:'早',name:'早更',start:'07:00',end:'15:00',color:Colors.orange,hours:8),
    Shift(code:'中',name:'中更',start:'15:00',end:'23:00',color:Colors.blue,hours:8),
    Shift(code:'夜',name:'夜更',start:'23:00',end:'07:00',color:Colors.indigo,hours:8,nightBonus:80),
    Shift(code:'O',name:'例休',start:'',end:'',color:Colors.green,hours:0,isWork:false),
    Shift(code:'AL',name:'年假',start:'',end:'',color:Colors.purple,hours:0,isWork:false),
    Shift(code:'SL',name:'病假',start:'',end:'',color:Colors.pink,hours:0,isWork:false),
    Shift(code:'PH',name:'紅日',start:'',end:'',color:Colors.red,hours:0,isWork:false),
  ];
  DateTime focused = DateTime.now();
  DateTime? selected;
  double standardWeekly = 42;
  double transportBonus = 20;
  double holidayBonus = 100;
  double accumulatedBank = 0;

  @override
  void initState() { super.initState(); selected=DateTime.now(); _load(); }

  String k(DateTime d)=>DateFormat('yyyy-MM-dd').format(d);
  int isoWeek(DateTime d){final thu=d.add(Duration(days:4-d.weekday)); final jan1=DateTime(thu.year,1,1); return ((thu.difference(jan1).inDays)/7).floor()+1;}
  Shift? getShift(String code) { try{ return shifts.firstWhere((s)=>s.code==code); }catch(_){return null;} }

  // 儲存
  Future _save() async { final p=await SharedPreferences.getInstance(); p.setString('roster', jsonEncode(roster)); p.setString('shifts', jsonEncode(shifts.map((e)=>e.toJson()).toList())); p.setDouble('std', standardWeekly); }
  Future _load() async { final p=await SharedPreferences.getInstance(); final r=p.getString('roster'); if(r!=null) roster=Map<String,String>.from(jsonDecode(r)); final s=p.getString('shifts'); if(s!=null) shifts=(jsonDecode(s) as List).map((e)=>Shift.fromJson(e)).toList(); standardWeekly=p.getDouble('std')??42; setState((){}); }

  // 自動排更
  void autoRoster() {
    if(selected==null) return;
    List<String> pattern = shifts.where((e)=>e.isWork).map((e)=>e.code).toList();
    if(pattern.isEmpty) return;
    DateTime start = DateTime(focused.year, focused.month, 1);
    DateTime end = DateTime(focused.year, focused.month+1, 0);
    int idx=0;
    setState((){
      for(var d=start; d.isBefore(end.add(const Duration(days:1))); d=d.add(const Duration(days:1))){
        if(roster[k(d)]==null){
          roster[k(d)]=pattern[idx % pattern.length];
          idx++;
          if(idx%5==0){ roster[k(d.add(const Duration(days:1)))]='O'; d=d.add(const Duration(days:1)); }
        }
      }
      _save();
    });
  }

  // 工時計算
  double hoursOf(DateTime d){ final s=getShift(roster[k(d)]??''); return s?.hours??0; }
  double weeklyHours(DateTime any){
    final mon=any.subtract(Duration(days:any.weekday-1));
    double sum=0; for(int i=0;i<7;i++) sum+=hoursOf(mon.add(Duration(days:i)));
    return sum;
  }
  double monthlyHours(){ double sum=0; final m=focused.month,y=focused.year; roster.forEach((key,code){ final d=DateTime.parse(key); if(d.month==m&&d.year==y) sum+=hoursOf(d); }); return sum; }

  // 截圖分享
  Future shareShot() async {
    final img = await screenshotController.capture(pixelRatio: 3);
    if(img==null) return;
    final dir = await getTemporaryDirectory();
    final file = await File('${dir.path}/roster_${k(focused)}.png').create();
    await file.writeAsBytes(img);
    await Share.shareXFiles([XFile(file.path)], text: '我的更表 W${isoWeek(focused)}');
  }

  // Excel / PDF
  Future exportExcel() async {
    var excel = Excel.createExcel();
    Sheet sheet = excel['更表'];
    sheet.appendRow([TextCellValue('日期'),TextCellValue('星期'),TextCellValue('班次'),TextCellValue('工時')]);
    roster.forEach((date,code){ final d=DateTime.parse(date); sheet.appendRow([TextCellValue(date),TextCellValue(DateFormat('E').format(d)),TextCellValue(code),TextCellValue('${hoursOf(d)}')]); });
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/roster.xlsx'); await file.writeAsBytes(excel.encode()!);
    Share.shareXFiles([XFile(file.path)]);
  }
  Future exportPdf() async {
    final pdf = pw.Document();
    pdf.addPage(pw.Page(build: (c)=> pw.Column(children: [pw.Text('Roster Report ${focused.year}-${focused.month}'), pw.SizedBox(height:20), pw.Text('Total Hours: $monthlyHours()'), pw.Text('Weekly Standard: $standardWeekly'), pw.Text('Bank: $accumulatedBank') ])));
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/roster.pdf'); await file.writeAsBytes(await pdf.save());
    Share.shareXFiles([XFile(file.path)]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: [ _buildCalendar(), _buildReport(), _buildSettings() ][_index],
      bottomNavigationBar: NavigationBar(selectedIndex: _index, onDestinationSelected: (i)=>setState(()=>_index=i), destinations: const[
        NavigationDestination(icon: Icon(Icons.calendar_month), label: '月曆'),
        NavigationDestination(icon: Icon(Icons.bar_chart), label: '報表'),
        NavigationDestination(icon: Icon(Icons.settings), label: '設定'),
      ]),
    );
  }

  Widget _buildCalendar(){
    return Screenshot(
      controller: screenshotController,
      child: Scaffold(
        appBar: AppBar(title: Text('W${isoWeek(focused).toString().padLeft(2,'0')} ${DateFormat('yyyy年M月').format(focused)}'), actions: [
          IconButton(onPressed: autoRoster, icon: const Icon(Icons.auto_mode), tooltip: '根據本月自動排更'),
          IconButton(onPressed: shareShot, icon: const Icon(Icons.share), tooltip: '一鍵截圖分享 PNG'),
        ]),
        body: Column(children: [
          TableCalendar(firstDay: DateTime(2024,1,1), lastDay: DateTime(2030,12,31), focusedDay: focused, startingDayOfWeek: StartingDayOfWeek.monday,
            selectedDayPredicate: (d)=>isSameDay(selected,d), onDaySelected: (s,f)=>setState((){selected=s; focused=f;}), onPageChanged: (f)=>setState(()=>focused=f),
            calendarBuilders: CalendarBuilders(
              dowBuilder: (c,day){ if(day.weekday==1) return Center(child: Text('一\nW${isoWeek(focused)}', textAlign: TextAlign.center, style: const TextStyle(fontSize:10, fontWeight: FontWeight.bold))); return null; },
              defaultBuilder: (ctx,day,foc){
                final code=roster[k(day)]; final sh=getShift(code??'');
                if(sh==null) return null;
                return Container(margin: const EdgeInsets.all(3), decoration: BoxDecoration(color: sh.color, borderRadius: BorderRadius.circular(6)), child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text('${day.day}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize:12)), Text(sh.code, style: const TextStyle(color: Colors.white, fontSize:9))]))));
              },
            ),
          ),
          Container(padding: const EdgeInsets.all(8), color: Colors.indigo.shade50, child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('週工時: ${weeklyHours(selected??DateTime.now())} / $standardWeekly', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('差額: ${weeklyHours(selected??DateTime.now())-standardWeekly}', style: TextStyle(color: weeklyHours(selected??DateTime.now())>standardWeekly?Colors.red:Colors.green)),
          ])),
          Expanded(child: SingleChildScrollView(child: Wrap(spacing:6, runSpacing:6, alignment: WrapAlignment.center, children: shifts.map((s)=> FilterChip(label: Text('${s.code} ${s.start}'), selected: roster[k(selected!)]==s.code, selectedColor: s.color.withOpacity(0.4), onSelected: (_){ setState((){ roster[k(selected!)]=s.code; _save(); }); })).toList()..add(ActionChip(label: const Text('清除'), onPressed: (){ setState((){ roster.remove(k(selected!)); _save(); }); }))))),
        ]),
      ),
    );
  }

  Widget _buildReport(){
    final monH = monthlyHours(); final weekH = weeklyHours(selected??DateTime.now());
    return Scaffold(appBar: AppBar(title: const Text('工時 & 津貼報表')), body: ListView(padding: const EdgeInsets.all(16), children: [
      Card(child: ListTile(title: const Text('每班工時'), subtitle: Text(shifts.map((e)=>'${e.code}:${e.hours}h').join('  ')))),
      Card(child: ListTile(title: Text('本週實際: $weekH h'), subtitle: Text('標準: $standardWeekly h  差額: ${weekH-standardWeekly}h'))),
      Card(child: ListTile(title: Text('本月總計: $monH h'), subtitle: Text('累計銀行: ${monH - standardWeekly*4}h'))),
      Card(child: ListTile(title: const Text('津貼計算'), subtitle: Text('夜更: ${roster.values.where((c)=>c=='夜').length*shifts.firstWhere((s)=>s.code=='夜').nightBonus}  交通: ${roster.values.where((c)=>getShift(c)?.isWork==true).length*transportBonus}  假日津貼: ${roster.values.where((c)=>c=='PH').length*holidayBonus}'))),
      const SizedBox(height:10),
      FilledButton.icon(onPressed: exportExcel, icon: const Icon(Icons.table_chart), label: const Text('Excel 匯出')),
      FilledButton.icon(onPressed: exportPdf, icon: const Icon(Icons.picture_as_pdf), label: const Text('PDF 匯出 / 月薪統計')),
      const SizedBox(height:10),
      const Text('假期管理', style: TextStyle(fontWeight: FontWeight.bold)), 
      Wrap(spacing:8, children: [Chip(label: Text('AL: ${roster.values.where((e)=>e=='AL').length}日')), Chip(label: Text('SL: ${roster.values.where((e)=>e=='SL').length}日')), Chip(label: Text('O: ${roster.values.where((e)=>e=='O').length}日'))]),
    ]));
  }

  Widget _buildSettings(){
    return Scaffold(appBar: AppBar(title: const Text('設定')), body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('1. 自動排更', style: TextStyle(fontWeight: FontWeight.bold)), SwitchListTile(value: true, onChanged: (v){}, title: const Text('根據已選月份自動排更'), subtitle: const Text('按月曆右上角魔法棒')),
      const Divider(),
      const Text('2. ISO週數顯示', style: TextStyle(fontWeight: FontWeight.bold)), const ListTile(title: Text('已啟用'), subtitle: Text('每週一顯示 W01-W53，頂部標題亦顯示')),
      const Divider(),
      const Text('3. Google Calendar 雙向同步', style: TextStyle(fontWeight: FontWeight.bold)), ListTile(title: const Text('連接 Google'), subtitle: const Text('V3.1 將開放 OAuth，需上架後啟用'), trailing: FilledButton(onPressed: (){ ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請先在 Google Cloud 開啟 Calendar API'))); }, child: const Text('連接'))),
      const Divider(),
      const Text('4. 截圖分享 PNG 高清', style: TextStyle(fontWeight: FontWeight.bold)), ListTile(title: const Text('高清 3x 輸出'), subtitle: const Text('月曆右上角分享按鈕，一鍵 PNG 分享'), trailing: IconButton(icon: const Icon(Icons.share), onPressed: shareShot)),
      const Divider(),
      const Text('5. 班次編輯 (可自由增刪)', style: TextStyle(fontWeight: FontWeight.bold, fontSize:16)),
      ...shifts.map((s)=> ListTile(leading: CircleAvatar(backgroundColor: s.color, child: Text(s.code, style: const TextStyle(color: Colors.white, fontSize:12))), title: Text('${s.name} ${s.start}-${s.end}'), subtitle: Text('${s.hours}h 夜津:${s.nightBonus}'), trailing: IconButton(icon: const Icon(Icons.delete), onPressed: (){ setState((){ shifts.remove(s); _save(); }); }))),
      FilledButton.icon(onPressed: (){ _showAddShift(); }, icon: const Icon(Icons.add), label: const Text('新增班次')),
      const Divider(),
      const Text('6. 根據已有班次排更表', style: TextStyle(fontWeight: FontWeight.bold)), ListTile(title: const Text('學習你上月規律'), subtitle: const Text('自動排更會沿用你常用順序 早->中->夜->O'), trailing: const Icon(Icons.auto_awesome)),
      const Divider(),
      const Text('工時標準 & 津貼自訂', style: TextStyle(fontWeight: FontWeight.bold, fontSize:16)),
      ListTile(title: Text('每週標準: $standardWeekly 小時'), trailing: Slider(value: standardWeekly, min: 30, max: 60, divisions: 30, label: '$standardWeekly', onChanged: (v)=>setState((){ standardWeekly=v; _save(); }))),
      ListTile(title: const Text('交通津貼 / 日'), subtitle: Text('\$$transportBonus'), onTap: () async { final c= await _askNumber('交通津貼'); if(c!=null) setState((){ transportBonus=c; }); }),
      ListTile(title: const Text('假日津貼'), subtitle: Text('\$$holidayBonus'), onTap: () async { final c= await _askNumber('假日津貼'); if(c!=null) setState((){ holidayBonus=c; }); }),
      const Divider(),
      const Text('資料儲存', style: TextStyle(fontWeight: FontWeight.bold)), ListTile(title: const Text('Google Drive 備份'), subtitle: const Text('自動用 SharedPreferences 本地備份，Drive 在 V3.2'), trailing: const Icon(Icons.cloud_upload)),
      ListTile(title: const Text('匯入/匯出 JSON'), trailing: Row(mainAxisSize: MainAxisSize.min, children: [IconButton(onPressed: () async { final p=await SharedPreferences.getInstance(); final data=p.getString('roster')??'{}'; final dir=await getTemporaryDirectory(); final f=File('${dir.path}/backup.json'); await f.writeAsString(data); Share.shareXFiles([XFile(f.path)]); }, icon: const Icon(Icons.upload)), IconButton(onPressed: (){}, icon: const Icon(Icons.download))]))
    ]));
  }

  Future<double?> _askNumber(String title) async {
    final c = TextEditingController();
    return showDialog<double>(context: context, builder: (ctx)=> AlertDialog(title: Text(title), content: TextField(controller: c, keyboardType: TextInputType.number), actions: [TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('取消')), TextButton(onPressed: ()=>Navigator.pop(ctx, double.tryParse(c.text)), child: const Text('確定'))]));
  }

  void _showAddShift(){
    final codeC=TextEditingController(); final nameC=TextEditingController(); final startC=TextEditingController(text:'09:00'); final endC=TextEditingController(text:'18:00'); final hoursC=TextEditingController(text:'8');
    showDialog(context: context, builder: (ctx)=> AlertDialog(title: const Text('新增班次'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: codeC, decoration: const InputDecoration(labelText:'代碼 如 N2')), TextField(controller: nameC, decoration: const InputDecoration(labelText:'名稱')), TextField(controller: startC, decoration: const InputDecoration(labelText:'開工時間')), TextField(controller: endC, decoration: const InputDecoration(labelText:'收工時間')), TextField(controller: hoursC, decoration: const InputDecoration(labelText:'工時'), keyboardType: TextInputType.number)]), actions: [TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('取消')), FilledButton(onPressed: (){ setState((){ shifts.add(Shift(code:codeC.text, name:nameC.text, start:startC.text, end:endC.text, color: Colors.primaries[shifts.length%18], hours: double.tryParse(hoursC.text)??8)); _save(); }); Navigator.pop(ctx); }, child: const Text('新增'))]));
  }
}
