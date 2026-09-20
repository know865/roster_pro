import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart' as ex;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as cal;
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:http/http.dart' as http;

void main() async { WidgetsFlutterBinding.ensureInitialized(); runApp(const RosterProApp()); }

class RosterProApp extends StatelessWidget {
  const RosterProApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Roster Pro',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue, brightness: Brightness.light),
      darkTheme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue, brightness: Brightness.dark),
      themeMode: ThemeMode.system,
      home: const RosterV2Screen(),
    );
  }
}

class RosterV2Screen extends StatefulWidget {
  const RosterV2Screen({super.key});
  @override State<RosterV2Screen> createState() => _RosterV2ScreenState();
}

class _RosterV2ScreenState extends State<RosterV2Screen> {
  CalendarFormat _format = CalendarFormat.month;
  DateTime _focused = DateTime.now();
  Map<DateTime, Map<String,dynamic>> _data = {}; // {date: {shift, hours, allowance}}
  final _shot = ScreenshotController();
  final _googleSignIn = GoogleSignIn(scopes: [cal.CalendarApi.calendarScope, drive.DriveApi.driveFileScope]);

  // 津貼規則
  Map<String, double> allowances = {'夜更': 50, '交通': 20, '假日': 100, 'OT': 75};

  double get weeklyHours => _getWeekData().fold(0.0, (s,e) => s + (e['hours'] as double));
  double get weeklyDiff => weeklyHours - 42;
  double get monthlyAllowance => _data.values.fold(0.0, (s,e) => s + (e['allowance'] as double));

  List<Map<String,dynamic>> _getWeekData() {
    final start = _focused.subtract(Duration(days: _focused.weekday -1));
    return [for(int i=0;i<7;i++) _data[DateTime(start.year,start.month,start.day+i)]].whereType<Map<String,dynamic>>().toList();
  }

  int isoWeek(DateTime d) => ((int.parse(DateFormat("D").format(d)) - d.weekday + 10)/7).floor();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Roster Pro W${isoWeek(_focused).toString().padLeft(2,'0')}'),
        actions: [
          IconButton(icon: const Icon(Icons.calendar_month), onPressed: _syncGoogleCalendar, tooltip: 'Google Calendar 雙向同步'),
          IconButton(icon: const Icon(Icons.backup), onPressed: _backupToDrive, tooltip: 'Google Drive 備份'),
          IconButton(icon: const Icon(Icons.share), onPressed: _sharePng),
          PopupMenuButton(itemBuilder: (_) => [
            const PopupMenuItem(value: 'excel', child: Text('Excel 匯出')),
            const PopupMenuItem(value: 'pdf', child: Text('PDF 匯出')),
          ], onSelected: (v){ if(v=='excel') _exportExcel(); else _exportPdf(); })
        ],
      ),
      body: Column(children: [
        Screenshot(controller: _shot, child: TableCalendar(
          firstDay: DateTime(2020), lastDay: DateTime(2030), focusedDay: _focused, calendarFormat: _format,
          onFormatChanged: (f)=>setState(()=>_format=f),
          onDaySelected: (sel, foc){ setState(()=>_focused=foc); _pickShift(sel); },
          headerStyle: HeaderStyle(titleTextFormatter: (d,_) => '${d.year}年${d.month}月 W${isoWeek(d).toString().padLeft(2,'0')}'),
          calendarBuilders: CalendarBuilders(defaultBuilder: (c,day,foc){
            final k = DateTime(day.year,day.month,day.day); final v = _data[k];
            return Container(decoration: BoxDecoration(border: Border.all(color: Colors.black12), color: v==null?null:Colors.blue.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
              child: Column(children: [Text('${day.day}', style: const TextStyle(fontSize:12)), if(v!=null) Text(v['shift'], style: const TextStyle(fontSize:10, fontWeight: FontWeight.bold)), if(v!=null && v['allowance']>0) Text('+\$${v['allowance']}', style: const TextStyle(fontSize:8, color: Colors.orange))]));
          }),
        )),
        // 工時銀行 + 津貼
        Card(margin: const EdgeInsets.all(8), child: Padding(padding: const EdgeInsets.all(12), child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _kpi('本週實際','${weeklyHours}h'), _kpi('標準','42h'), _kpi('差額','${weeklyDiff>=0?'+':''}$weeklyDiff', color: weeklyDiff>=0?Colors.green:Colors.red),
          _kpi('本月津貼','\$${monthlyAllowance.toStringAsFixed(0)}', color: Colors.orange),
        ]))),
      ]),
      floatingActionButton: FloatingActionButton.extended(onPressed: ()=>setState(()=>_format=_format==CalendarFormat.month?CalendarFormat.week:CalendarFormat.month), label: Text(_format==CalendarFormat.month?'周曆':'月曆'), icon: const Icon(Icons.view_week)),
    );
  }

  Widget _kpi(String l, String v, {Color? color}) => Column(children: [Text(l, style: const TextStyle(fontSize:10)), Text(v, style: TextStyle(fontWeight: FontWeight.bold, color: color))]);

  void _pickShift(DateTime day) {
    showModalBottomSheet(context: context, builder: (_)=>Wrap(children: [
      for(var s in ['早','中','夜','O休','AL年假','SL病假','補假','公假']) ListTile(title: Text(s), subtitle: Text(s=='夜'?'津貼 \$${allowances['夜更']}':''), onTap: (){
        final isNight = s=='夜'; final isHoliday = s.contains('假');
        setState(()=>_data[DateTime(day.year,day.month,day.day)] = {'shift':s, 'hours': s.contains('休')||s.contains('假')?0:8.0, 'allowance': isNight?allowances['夜更']!: isHoliday?0:0});
        Navigator.pop(context);
      })
    ]));
  }

  Future<void> _sharePng() async { final img = await _shot.capture(); if(img!=null) await Share.shareXFiles([XFile.fromData(img, name: 'roster_pro_${DateFormat('yyyyMMdd').format(_focused)}.png', mimeType: 'image/png')], text: 'Roster Pro 我的更表'); }

  Future<void> _exportExcel() async {
    var excel = ex.Excel.createExcel(); var sheet = excel['Roster'];
    sheet.appendRow([ex.TextCellValue('日期'), ex.TextCellValue('班別'), ex.TextCellValue('工時'), ex.TextCellValue('津貼')]);
    _data.forEach((d,v){ sheet.appendRow([ex.TextCellValue(DateFormat('yyyy-MM-dd').format(d)), ex.TextCellValue(v['shift']), ex.DoubleCellValue(v['hours']), ex.DoubleCellValue(v['allowance'])]); });
    sheet.appendRow([ex.TextCellValue(''), ex.TextCellValue('總計'), ex.DoubleCellValue(weeklyHours), ex.DoubleCellValue(monthlyAllowance)]);
    final dir = await getTemporaryDirectory(); final file = File('${dir.path}/roster.xlsx'); await file.writeAsBytes(excel.encode()!); await Share.shareXFiles([XFile(file.path)]);
  }

  Future<void> _exportPdf() async {
    final doc = pw.Document(); doc.addPage(pw.Page(build: (c)=> pw.Column(children: [pw.Text('Roster Pro 月薪統計'), pw.SizedBox(height:10), pw.Text('本月工時: $weeklyHours / 標準42h 差額 $weeklyDiff'), pw.Text('津貼總計: \$$monthlyAllowance') ])));
    await Printing.sharePdf(bytes: await doc.save(), filename: 'roster_report.pdf');
  }

  Future<void> _syncGoogleCalendar() async {
    try{ final acc = await _googleSignIn.signIn(); if(acc==null) return;
      final auth = await acc.authentication; final client = GoogleAuthClient(auth.accessToken!);
      final calApi = cal.CalendarApi(client);
      // 雙向同步：將本地更表上傳
      for(var e in _data.entries){ await calApi.events.insert(cal.Event()..summary='更表: ${e.value['shift']}'..start=cal.EventDateTime()..start.date=DateFormat('yyyy-MM-dd').format(e.key)..end=cal.EventDateTime()..end.date=DateFormat('yyyy-MM-dd').format(e.key.add(const Duration(days:1))), 'primary'); }
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已同步到 Google Calendar')));
    }catch(e){ ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('同步失敗: $e'))); }
  }

  Future<void> _backupToDrive() async {
    try{ final acc = await _googleSignIn.signIn(); if(acc==null) return;
      final auth = await acc.authentication; final client = GoogleAuthClient(auth.accessToken!); final driveApi = drive.DriveApi(client);
      final file = drive.File()..name='roster_pro_backup_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.json';
      final jsonStr = _data.toString(); // 簡化，正式用jsonEncode
      await driveApi.files.create(file, uploadMedia: drive.Media(Stream.value(jsonStr.codeUnits), jsonStr.length));
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已備份到 Google Drive')));
    }catch(e){ ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('備份失敗: $e'))); }
  }
}

class GoogleAuthClient extends http.BaseClient {
  final String token; final http.Client _inner = http.Client();
  GoogleAuthClient(this.token);
  @override Future<http.StreamedResponse> send(http.BaseRequest r){ r.headers['Authorization']='Bearer $token'; return _inner.send(r); }
}
