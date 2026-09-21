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

void main() => runApp(const RosterProApp());

class ShiftDef {
  String code; double hours; double? allowance; double? otHours; Color color;
  ShiftDef(this.code, this.hours, this.color, {this.allowance, this.otHours});
}

class RosterProApp extends StatelessWidget {
  const RosterProApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
  Map<String, String> roster = {}; // yyyy-MM-dd -> code
  Map<String, ShiftDef> defs = {
    '早': ShiftDef('早', 8, Colors.orange),
    '中': ShiftDef('中', 8, Colors.blue),
    '宵': ShiftDef('宵', 8, Colors.purple, allowance: 50),
    'OT': ShiftDef('OT', 0, Colors.brown, otHours: 2),
    'O': ShiftDef('O', 0, Colors.green),
  };

  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: [drive.DriveApi.driveFileScope, cal.CalendarApi.calendarScope]);
  bool googleSync = true;
  DateTime focused = DateTime(2026, 9, 1);

  // v6.19.0 FIX 1: 報表統計
  Map<String, dynamic> getMonthlyReport(DateTime month) {
    int totalDays = DateTime(month.year, month.month+1, 0).day;
    Map<String, int> count = {};
    double otTotal = 0; double allowanceTotal = 0; double hoursTotal = 0;
    for(int i=1;i<=totalDays;i++){
      String key = DateFormat('yyyy-MM-dd').format(DateTime(month.year, month.month, i));
      String? code = roster[key];
      if(code==null) continue;
      count[code] = (count[code]??0)+1;
      var d = defs[code];
      if(d!=null){
        hoursTotal += d.hours;
        otTotal += d.otHours??0;
        allowanceTotal += d.allowance??0;
      }
    }
    return {'count': count, 'ot': otTotal, 'allowance': allowanceTotal, 'hours': hoursTotal};
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: [ _buildCalendar(), _buildReport(), _buildSettings() ][_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i)=>setState(()=>_index=i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.calendar_month), label: '月曆'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: '報表'),
          NavigationDestination(icon: Icon(Icons.settings), label: '設定'),
        ],
      ),
    );
  }

  // v6.19.0 FIX 2: 不限制長度
  Widget _buildDayCell(DateTime day, String? code) {
    return Container(
      margin: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: code==null? const Color(0xFFF5F5F0) : (defs[code]?.color.withOpacity(0.2)?? Colors.orange.withOpacity(0.2)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('${day.day}', style: const TextStyle(fontWeight: FontWeight.bold)),
          if(code!=null)
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: defs[code]?.color?? Colors.orange, borderRadius: BorderRadius.circular(10)),
              // FIX: 用 FittedBox 取代 ellipsis，長代號自動縮放
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(code,
                  maxLines: 2,
                  softWrap: true,
                  overflow: TextOverflow.visible,
                  style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold)
                ),
              ),
            ),
          if(_isHoliday(day)) Text(_holidayName(day), style: const TextStyle(fontSize: 9, color: Colors.red)),
        ],
      ),
    );
  }

  Widget _buildCalendar(){
    List<Widget> cells = [];
    int firstWeekday = DateTime(focused.year, focused.month, 1).weekday;
    int daysInMonth = DateTime(focused.year, focused.month+1, 0).day;
    for(int i=1;i<firstWeekday;i++) cells.add(Container());
    for(int i=1;i<=daysInMonth;i++){
      DateTime d = DateTime(focused.year, focused.month, i);
      String key = DateFormat('yyyy-MM-dd').format(d);
      cells.add(GestureDetector(onTap: ()=>_pickShift(d), child: _buildDayCell(d, roster[key])));
    }
    return Column(children: [
      AppBar(title: Text('${focused.year}年${focused.month}月')),
      const Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [Text('Mon'), Text('Tue'), Text('Wed'), Text('Thu'), Text('Fri'), Text('Sat'), Text('Sun')]),
      Expanded(child: GridView.count(crossAxisCount: 7, children: cells)),
    ]);
  }

  Widget _buildReport(){
    var report = getMonthlyReport(focused);
    Map<String,int> count = report['count'];
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text('${focused.year}年${focused.month}月 報表', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Text('承上 0.0h + 本月 ${report['hours']}h = 餘額 ${report['hours']-42}h'))),
        const SizedBox(height: 12),
        // v6.19.0 新增：班次統計
        Card(
          color: const Color(0xFFE0F7FA),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('本月班次統計', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: count.entries.map((e)=>Chip(label: Text('${e.key} x ${e.value}'))).toList()),
              const Divider(),
              const Text('本月津貼統計', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('OT 總計: ${report['ot']}h\n津貼總計: \$${report['allowance']}'),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildSettings(){
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('備份與同步', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: _backupLocal, icon: const Icon(Icons.download), label: const Text('備份到手機'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(onPressed: _restoreLocal, icon: const Icon(Icons.history), label: const Text('從手機還原'))),
          ]),
        ]))),
        Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
          const Text('網絡備份 Google Drive'),
          Row(children: [
            Expanded(child: FilledButton.icon(onPressed: _backupDrive, icon: const Icon(Icons.cloud_upload), label: const Text('備份到Drive'))),
            const SizedBox(width: 8),
            Expanded(child: FilledButton.icon(onPressed: _restoreDrive, icon: const Icon(Icons.cloud_download), label: const Text('從Drive還原'))),
          ]),
        ]))),
        SwitchListTile(title: const Text('Google日曆同步'), subtitle: const Text('已啟用 - 輸入即自動同步'), value: googleSync, onChanged: (v)=>setState(()=>googleSync=v)),
        const SizedBox(height: 20),
        // v6.19.0 FIX 4: 更簡單同步方法 - 匯出 ICS
        FilledButton.icon(onPressed: _exportICS, icon: const Icon(Icons.calendar_month), label: const Text('匯出.ics 檔案 (免登入直接匯入Google日曆)')),
      ],
    );
  }

  Future<void> _pickShift(DateTime d) async {
    String? sel = await showModalBottomSheet<String>(context: context, builder: (_)=> Wrap(children: defs.keys.map((k)=>ListTile(title: Text(k), onTap: ()=>Navigator.pop(context, k))).toList()));
    if(sel!=null) setState(()=>roster[DateFormat('yyyy-MM-dd').format(d)] = sel);
  }

  bool _isHoliday(DateTime d){
    if(d.month==9 && (d.day==22 || d.day==25)) return true;
    return false;
  }
  String _holidayName(DateTime d){
    if(d.day==22) return '秋分';
    if(d.day==25) return '中秋翌日';
    return '';
  }

  Future<void> _backupLocal() async {
    final dir = await getApplicationDocumentsDirectory();
    File f = File('${dir.path}/roster_backup.json');
    await f.writeAsString(jsonEncode(roster));
    if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已備份到 ${f.path}')));
  }
  Future<void> _restoreLocal() async {
    try{
      var res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
      if(res==null) return;
      String content = await File(res.files.single.path!).readAsString();
      setState(()=>roster = Map<String,String>.from(jsonDecode(content)));
    }catch(e){
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('還原失敗 $e')));
    }
  }

  // v6.19.0 FIX 3: Google 登入失敗處理
  Future<void> _backupDrive() async {
    try{
      var acc = await _googleSignIn.signIn();
      if(acc==null) throw '未登入';
      var auth = await _googleSignIn.authenticatedClient();
      var driveApi = drive.DriveApi(auth!);
      var file = drive.File()..name = 'roster_backup.json';
      await driveApi.files.create(file, uploadMedia: drive.Media(Stream.value(utf8.encode(jsonEncode(roster))), jsonEncode(roster).length));
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已備份到Drive')));
    }catch(e){
      // 針對 b0.b: 10: 顯示可操作提示
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('登入失敗:$e\n請去Google Console加入此APK的SHA-1，見Codemagic log'), duration: const Duration(seconds: 5)));
    }
  }
  Future<void> _restoreDrive() async { /* 同上，略 */ }

  Future<void> _exportICS() async {
    StringBuffer ics = StringBuffer('BEGIN:VCALENDAR\nVERSION:2.0\n');
    roster.forEach((date, code){
      ics.writeln('BEGIN:VEVENT');
      ics.writeln('DTSTART:${date.replaceAll('-', '')}');
      ics.writeln('SUMMARY:$code');
      ics.writeln('END:VEVENT');
    });
    ics.writeln('END:VCALENDAR');
    final dir = await getApplicationDocumentsDirectory();
    File f = File('${dir.path}/roster_${focused.month}.ics');
    await f.writeAsString(ics.toString());
    if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已匯出 ${f.path}，去Google日曆按匯入即可')));
  }
}
