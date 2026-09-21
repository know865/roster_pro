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

void main(){runApp(const RosterApp());}

class ShiftDef{
  String code;String label;double hours;double allowance;double ot;Color color;
  ShiftDef(this.code,this.label,this.hours,this.color,{this.allowance=0,this.ot=0});
  Map<String,dynamic> toJson()=>{'code':code,'label':label,'hours':hours,'allowance':allowance,'ot':ot,'color':color.value};
  factory ShiftDef.fromJson(Map<String,dynamic> j)=>ShiftDef(j['code'],j['label']??j['code'],(j['hours']??8).toDouble(),Color(j['color']??0xFFFF9800),allowance:(j['allowance']??0).toDouble(),ot:(j['ot']??0).toDouble());
}

class RosterApp extends StatelessWidget{
  const RosterApp({super.key});
  @override
  Widget build(BuildContext context){
    return MaterialApp(title:'Roster Pro v6.19.2',theme:ThemeData(useMaterial3:true,colorSchemeSeed:Colors.deepPurple),home:const MainPage());
  }
}

class MainPage extends StatefulWidget{
  const MainPage({super.key});
  @override
  State<MainPage> createState()=>MainPageState();
}

class MainPageState extends State<MainPage>{
  int tab=0;
  DateTime focused=DateTime(2026,9,1);
  Map<String,String> roster={};
  Map<String,ShiftDef> defs={
    'early':ShiftDef('early','early',8,Colors.orange),
    'mid':ShiftDef('mid','mid',8,Colors.blue),
    'night':ShiftDef('night','night',8,Colors.purple,allowance:60),
    'OT':ShiftDef('OT','OT',0,Colors.brown,ot:2),
    'O':ShiftDef('O','OFF',0,Colors.green),
  };
  String customName='My Roster';
  String? calId;
  double carry=0;
  bool gSync=true;
  final GoogleSignIn gSign=GoogleSignIn(scopes:[drive.DriveApi.driveFileScope,cal.CalendarApi.calendarScope]);
  final DeviceCalendarPlugin dCal=DeviceCalendarPlugin();
  final Map<String,String> hols={'09-22':'Autumn','09-25':'MidAutumn'};

  @override
  void initState(){super.initState();load();}
  Future<void> load() async{
    var sp=await SharedPreferences.getInstance();
    var r=sp.getString('roster');
    if(r!=null){roster=Map<String,String>.from(jsonDecode(r));}
    setState((){
      customName=sp.getString('cName')??'My Roster';
      calId=sp.getString('calId');
      carry=sp.getDouble('carry')??0;
    });
  }
  Future<void> save() async{
    var sp=await SharedPreferences.getInstance();
    sp.setString('roster',jsonEncode(roster));
    sp.setString('cName',customName);
    if(calId!=null) sp.setString('calId',calId!);
    sp.setDouble('carry',carry);
  }
  Map<String,dynamic> report(DateTime m){
    int dim=DateTime(m.year,m.month+1,0).day;
    Map<String,int> cnt={};
    double hrs=0,ot=0,allow=0;
    for(int i=1;i<=dim;i++){
      String k=DateFormat('yyyy-MM-dd').format(DateTime(m.year,m.month,i));
      String? code=roster[k];
      if(code==null) continue;
      cnt[code]=(cnt[code]??0)+1;
      var d=defs[code];
      if(d!=null){hrs+=d.hours;ot+=d.ot;allow+=d.allowance;}
    }
    return {'cnt':cnt,'hrs':hrs,'ot':ot,'allow':allow,'bal':carry+hrs-168};
  }
  Widget dayCell(DateTime day,bool inMonth){
    if(!inMonth) return Container();
    String k=DateFormat('yyyy-MM-dd').format(day);
    String? code=roster[k];
    var def=code!=null?defs[code]:null;
    String mmdd=DateFormat('MM-dd').format(day);
    bool hol=hols.containsKey(mmdd);
    return GestureDetector(
      onTap:(){pick(day);},
      child:Container(
        margin:const EdgeInsets.all(3),
        padding:const EdgeInsets.all(4),
        decoration:BoxDecoration(color:def!=null?def.color.withOpacity(0.25):const Color(0xFFF2F4E8),borderRadius:BorderRadius.circular(12)),
        child:Column(children:[
          Text('${day.day}',style:TextStyle(fontWeight:FontWeight.bold,color:hol?Colors.red:null)),
          if(hol) Text(hols[mmdd]!,style:const TextStyle(fontSize:9,color:Colors.red)),
          if(code!=null) Container(
            margin:const EdgeInsets.only(top:2),
            padding:const EdgeInsets.symmetric(horizontal:6,vertical:2),
            decoration:BoxDecoration(color:def?.color??Colors.orange,borderRadius:BorderRadius.circular(10)),
            child:FittedBox(child:Text(code,style:const TextStyle(fontSize:12,color:Colors.white,fontWeight:FontWeight.bold))),
          ),
        ]),
      ),
    );
  }
  Widget calTab(){
    DateTime first=DateTime(focused.year,focused.month,1);
    int fw=first.weekday;
    int dim=DateTime(focused.year,focused.month+1,0).day;
    List<Widget> cells=[];
    for(int i=1;i<fw;i++){cells.add(Container());}
    for(int i=1;i<=dim;i++){cells.add(dayCell(DateTime(focused.year,focused.month,i),true));}
    var rep=report(focused);
    return Column(children:[
      AppBar(title:Text('${focused.year} ${focused.month}'),actions:[
        IconButton(icon:const Icon(Icons.chevron_left),onPressed:(){setState((){focused=DateTime(focused.year,focused.month-1,1);});}),
        IconButton(icon:const Icon(Icons.chevron_right),onPressed:(){setState((){focused=DateTime(focused.year,focused.month+1,1);});}),
      ]),
      const Padding(padding:EdgeInsets.all(8),child:Row(mainAxisAlignment:MainAxisAlignment.spaceAround,children:[Text('Mon'),Text('Tue'),Text('Wed'),Text('Thu'),Text('Fri'),Text('Sat'),Text('Sun')])),
      Expanded(child:GridView.count(crossAxisCount:7,childAspectRatio:0.9,children:cells)),
      Card(child:ListTile(title:Text('Carry ${carry}h + Month ${rep['hrs']}h = Bal ${rep['bal']}h'))),
    ]);
  }
  Widget reportTab(){
    var rep=report(focused);
    Map<String,int> cnt=rep['cnt'] as Map<String,int>;
    return ListView(padding:const EdgeInsets.all(12),children:[
      Text('${focused.year}-${focused.month} Report',style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
      const SizedBox(height:12),
      Card(color:const Color(0xFFE0F7FA),child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('Shift Count',style:TextStyle(fontWeight:FontWeight.bold)),
        const SizedBox(height:8),
        cnt.isEmpty?const Text('No data'):Wrap(spacing:8,children:cnt.entries.map((e)=>Chip(label:Text('${e.key} x ${e.value}'))).toList()),
        const Divider(),
        Text('OT ${rep['ot']}h Allow \$${rep['allow']} Hrs ${rep['hrs']}h'),
      ]))),
    ]);
  }
  Widget settingsTab(){
    return ListView(padding:const EdgeInsets.all(16),children:[
      const Text('Backup',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold)),
      Card(child:Padding(padding:const EdgeInsets.all(12),child:Row(children:[
        Expanded(child:OutlinedButton.icon(onPressed:backupLocal,icon:const Icon(Icons.download),label:const Text('Backup Local'))),
        const SizedBox(width:8),
        Expanded(child:OutlinedButton.icon(onPressed:restoreLocal,icon:const Icon(Icons.history),label:const Text('Restore Local'))),
      ]))),
      Card(child:Padding(padding:const EdgeInsets.all(12),child:Row(children:[
        Expanded(child:FilledButton.icon(onPressed:backupDrive,icon:const Icon(Icons.cloud_upload),label:const Text('To Drive'))),
        const SizedBox(width:8),
        Expanded(child:FilledButton.icon(onPressed:restoreDrive,icon:const Icon(Icons.cloud_download),label:const Text('From Drive'))),
      ]))),
      Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('Dedicated Calendar - Custom Name',style:TextStyle(fontWeight:FontWeight.bold)),
        const SizedBox(height:8),
        TextField(decoration:InputDecoration(labelText:'Calendar Name',hintText:customName),onChanged:(v){customName=v;save();}),
        const SizedBox(height:8),
        Text('Event title = shift code: ${defs.keys.join(', ')}'),
        const SizedBox(height:8),
        FilledButton.icon(onPressed:createCal,icon:const Icon(Icons.calendar_month),label:Text('Create/Sync to $customName')),
        FilledButton.icon(onPressed:exportICS,icon:const Icon(Icons.file_download),label:const Text('Export.ics')),
        if(calId!=null) Text('CalID $calId',style:const TextStyle(fontSize:10)),
      ]))),
    ]);
  }
  void pick(DateTime d) async{
    String? sel=await showModalBottomSheet<String>(context:context,builder:(ctx){
      return SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[
       ...defs.keys.map((k){
          var def=defs[k]!;
          return ListTile(leading:CircleAvatar(backgroundColor:def.color,radius:12),title:Text(def.code),onTap:(){Navigator.pop(ctx,k);});
        }),
        ListTile(title:const Text('Clear'),onTap:(){Navigator.pop(ctx,'');}),
      ]));
    });
    if(sel==null) return;
    String key=DateFormat('yyyy-MM-dd').format(d);
    setState((){if(sel.isEmpty){roster.remove(key);}else{roster[key]=sel;}});
    save();
  }
  Future<void> backupLocal() async{
    var dir=await getApplicationDocumentsDirectory();
    var f=File('${dir.path}/roster_backup.json');
    await f.writeAsString(jsonEncode(roster));
    if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Backup ${f.path}')));
  }
  Future<void> restoreLocal() async{
    var res=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['json']);
    if(res==null) return;
    String c=await File(res.files.single.path!).readAsString();
    setState((){roster=Map<String,String>.from(jsonDecode(c));});
    save();
  }
  Future<void> backupDrive() async{
    try{
      var acc=await gSign.signIn();
      if(acc==null) return;
      var client=await gSign.authenticatedClient();
      var api=drive.DriveApi(client!);
      var file=drive.File()..name='roster_pro.json';
      await api.files.create(file,uploadMedia:drive.Media(Stream.value(utf8.encode(jsonEncode(roster))),utf8.encode(jsonEncode(roster)).length));
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Backup to Drive OK')));
    }catch(e){
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Fail $e')));
    }
  }
  Future<void> restoreDrive() async{
    try{
      var acc=await gSign.signIn();
      if(acc==null) return;
      var client=await gSign.authenticatedClient();
      var api=drive.DriveApi(client!);
      var list=await api.files.list(q:"name contains 'roster_pro'",orderBy:'createdTime desc');
      var id=list.files!.first.id!;
      var media=await api.files.get(id,downloadOptions:drive.DownloadOptions.fullMedia) as drive.Media;
      String s=await utf8.decodeStream(media.stream);
      setState((){roster=Map<String,String>.from(jsonDecode(s));});
      save();
    }catch(e){
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Fail $e')));
    }
  }
  Future<void> createCal() async{
    try{
      var client=await gSign.authenticatedClient();
      if(client==null){var acc=await gSign.signIn();client=await gSign.authenticatedClient();}
      var api=cal.CalendarApi(client!);
      var list=await api.calendarList.list();
      var exist=list.items?.where((c)=>c.summary==customName).toList();
      String cid;
      if(exist!=null&&exist.isNotEmpty){cid=exist.first.id!;}
      else{var nc=cal.Calendar()..summary=customName..timeZone='Asia/Hong_Kong';var cr=await api.calendars.insert(nc);cid=cr.id!;}
      calId=cid;
      await save();
      for(var e in roster.entries){
        DateTime d=DateFormat('yyyy-MM-dd').parse(e.key);
        if(d.month!=focused.month) continue;
        var ev=cal.Event()..summary=e.value..description=defs[e.value]?.label..start=(cal.EventDateTime()..date=DateTime(d.year,d.month,d.day))..end=(cal.EventDateTime()..date=DateTime(d.year,d.month,d.day+1));
        await api.events.insert(cid,ev);
      }
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Synced to $customName')));
    }catch(e){
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Fail $e')));
    }
  }
  Future<void> exportICS() async{
    StringBuffer ics=StringBuffer('BEGIN:VCALENDAR\nVERSION:2.0\n');
    roster.forEach((k,v){
      try{
        DateTime d=DateFormat('yyyy-MM-dd').parse(k);
        String dt=DateFormat('yyyyMMdd').format(d);
        ics.writeln('BEGIN:VEVENT');
        ics.writeln('DTSTART;VALUE=DATE:$dt');
        ics.writeln('SUMMARY:$v');
        ics.writeln('END:VEVENT');
      }catch(_){}
    });
    ics.writeln('END:VCALENDAR');
    var dir=await getApplicationDocumentsDirectory();
    var f=File('${dir.path}/$customName.ics');
    await f.writeAsString(ics.toString());
    if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Export ${f.path}')));
  }
  @override
  Widget build(BuildContext context){
    return Scaffold(
      body:[calTab(),reportTab(),settingsTab()][tab],
      bottomNavigationBar:NavigationBar(selectedIndex:tab,onDestinationSelected:(i){setState((){tab=i;});},destinations:const[
        NavigationDestination(icon:Icon(Icons.calendar_month),label:'Calendar'),
        NavigationDestination(icon:Icon(Icons.bar_chart),label:'Report'),
        NavigationDestination(icon:Icon(Icons.settings),label:'Settings'),
      ]),
    );
  }
}
