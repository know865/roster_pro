import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() { runApp(MaterialApp(debugShowCheckedModeBanner:false, theme: ThemeData(useMaterial3:true, colorSchemeSeed: Colors.indigo), home: MainPage())); }

class Shift {
  String code,name,start,end; int colorValue; double hours,bonus; bool isWork;
  Shift(this.code,this.name,this.start,this.end,this.colorValue,this.hours,this.bonus,this.isWork);
  Map toJson()=>{'code':code,'name':name,'start':start,'end':end,'colorValue':colorValue,'hours':hours,'bonus':bonus,'isWork':isWork};
  static Shift fromJson(Map m)=>Shift(m['code'],m['name'],m['start'],m['end'],m['colorValue'],(m['hours']as num).toDouble(),(m['bonus']as num).toDouble(),m['isWork']);
  Color get color=>Color(colorValue);
}
class RosterPattern{
  String name; List<String> codes;
  RosterPattern(this.name,this.codes);
  Map toJson()=>{'name':name,'codes':codes};
  static RosterPattern fromJson(Map m)=>RosterPattern(m['name'], List<String>.from(m['codes']));
}

class MainPage extends StatefulWidget{ @override State<MainPage> createState()=>MainPageState(); }

class MainPageState extends State<MainPage>{
  int tab=0;
  Map<String,String> roster={}, notes={}; Map<String,double> extra={};
  List<Shift> shifts=[]; List<RosterPattern> patterns=[];
  DateTime focused=DateTime.now(), selected=DateTime.now();
  double standardWeekly=42, cellFontSize=11;

  MainPageState(){
    shifts=[
      Shift('早','早更','07:00','15:30',Colors.orange.value,8,0,true),
      Shift('中','中更','15:00','23:30',Colors.blue.value,8,0,true),
      Shift('夜','夜更','23:00','07:30',Colors.indigo.value,8,80,true),
      Shift('O','例休','','',Colors.green.value,0,0,false),
      Shift('AL','年假','','',Colors.purple.value,0,0,false),
      Shift('SL','病假','','',Colors.pink.value,0,0,false),
      Shift('PH','紅日','','',Colors.red.value,0,0,false),
      Shift('OT','OT加班','','',Colors.brown.value,4,100,true),
    ];
  }
  String k(DateTime d)=>DateFormat('yyyy-MM-dd').format(d);
  int isoWeek(DateTime d){ DateTime thu=d.add(Duration(days:4-d.weekday)); DateTime jan1=DateTime(thu.year,1,1); return (thu.difference(jan1).inDays/7).floor()+1; }
  Shift getShiftByCode(String c){ for(var s in shifts){ if(s.code==c) return s; } return Shift('','','','',Colors.grey.value,0,0,false); }
  void save() async{
    var p=await SharedPreferences.getInstance();
    p.setString('roster', jsonEncode(roster)); p.setString('notes', jsonEncode(notes));
    p.setString('extra', jsonEncode(extra)); p.setString('shifts', jsonEncode(shifts.map((e)=>e.toJson()).toList()));
    p.setString('patterns', jsonEncode(patterns.map((e)=>e.toJson()).toList()));
    p.setDouble('std', standardWeekly); p.setDouble('cellFS', cellFontSize);
  }
  void load() async{
    var p=await SharedPreferences.getInstance();
    var r=p.getString('roster'); if(r!=null&&r!=''){ var dec=jsonDecode(r); setState(()=>roster=(dec as Map).map((k,v)=>MapEntry(k.toString(),v.toString()))); }
    var n=p.getString('notes'); if(n!=null&&n!=''){ var dec=jsonDecode(n); setState(()=>notes=(dec as Map).map((k,v)=>MapEntry(k.toString(),v.toString()))); }
    var ex=p.getString('extra'); if(ex!=null&&ex!=''){ var dec=jsonDecode(ex); setState(()=>extra=(dec as Map).map((k,v)=>MapEntry(k.toString(),(v as num).toDouble()))); }
    var s=p.getString('shifts'); if(s!=null&&s!=''){ var dec=jsonDecode(s) as List; setState(()=>shifts=dec.map((e)=>Shift.fromJson(e)).toList()); }
    var pat=p.getString('patterns'); if(pat!=null&&pat!=''){ var dec=jsonDecode(pat) as List; setState(()=>patterns=dec.map((e)=>RosterPattern.fromJson(e)).toList()); }
  }
  @override void initState(){ super.initState(); load(); }

  // 修復：年月選擇器
  void pickYearMonth(){
    int selY=focused.year, selM=focused.month;
    showDialog(context: context, builder: (ctx){
      return StatefulBuilder(builder: (ctx,setM){
        return AlertDialog(title: Text('快速選擇年月'), content: SizedBox(width: 300, height: 340, child: Column(children: [
          Text('年份', style: TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: GridView.count(crossAxisCount:4, children: [ for(int y=2024;y<=2030;y++) ChoiceChip(label: Text(y.toString()), selected: selY==y, onSelected: (v){ setM(()=>selY=y); }) ])),
          Divider(),
          Text('月份', style: TextStyle(fontWeight: FontWeight.bold)),
          GridView.count(shrinkWrap:true, crossAxisCount:4, children: [ for(int m=1;m<=12;m++) ChoiceChip(label: Text('${m}月'), selected: selM==m, onSelected: (v){ setM(()=>selM=m); }) ]),
        ])), actions: [
          TextButton(onPressed: ()=>Navigator.pop(ctx), child: Text('取消')),
          FilledButton(onPressed: (){ setState(()=>focused=DateTime(selY,selM,1)); Navigator.pop(ctx); }, child: Text('跳轉'))
        ]);
      });
    });
  }

  void exportCsv(){
    StringBuffer sb=StringBuffer(); sb.writeln('日期,星期,班次,開工,收工,工時,額外,記事');
    var keys=roster.keys.toList()..sort();
    for(var key in keys){ var d=DateTime.parse(key); if(d.year==focused.year&&d.month==focused.month){ var code=roster[key]!; var s=getShiftByCode(code); sb.writeln('$key,${DateFormat('E').format(d)},${s.code},${s.start},${s.end},${s.hours},${extra[key]??0},${notes[key]??''}'); } }
    showDialog(context: context, builder: (c){ return AlertDialog(title: Text('分享匯出'), content: SingleChildScrollView(child: SelectableText(sb.toString())), actions: [TextButton(onPressed: ()=>Navigator.pop(c), child: Text('關閉'))]); });
  }

  void onCellEdit(DateTime d){
    TextEditingController noteC=TextEditingController(text: notes[k(d)]??'');
    TextEditingController exC=TextEditingController(text: (extra[k(d)]??0).toString());
    String curCode=roster[k(d)]??'';
    showModalBottomSheet(context: context, isScrollControlled:true, builder: (ctx){
      return StatefulBuilder(builder: (ctx,setM){
        return Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, top:16, left:16, right:16), child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(DateFormat('yyyy-MM-dd EEEE').format(d), style: TextStyle(fontWeight: FontWeight.bold, fontSize:18)),
          Wrap(spacing:6, children: [ for(var s in shifts) ChoiceChip(label: Text(s.code), selected: curCode==s.code, selectedColor: s.color.withOpacity(0.4), onSelected: (v){ setM(()=>curCode=v?s.code:''); }) ]),
          SizedBox(height:12),
          TextField(controller: noteC, decoration: InputDecoration(labelText:'記事 / OT詳情', border: OutlineInputBorder())),
          SizedBox(height:8),
          TextField(controller: exC, decoration: InputDecoration(labelText:'額外工時', border: OutlineInputBorder()), keyboardType: TextInputType.number),
          SizedBox(height:12),
          FilledButton(onPressed: (){ setState((){ if(curCode=='') roster.remove(k(d)); else roster[k(d)]=curCode; if(noteC.text=='') notes.remove(k(d)); else notes[k(d)]=noteC.text; var vv=double.tryParse(exC.text); if(vv==null||vv==0) extra.remove(k(d)); else extra[k(d)]=vv; save(); }); Navigator.pop(ctx); }, child: Text('保存')),
          SizedBox(height:20),
        ]));
      });
    });
  }

  void createPattern(){
    TextEditingController nameC=TextEditingController(text:'我的22行${patterns.length+1}');
    showDialog(context: context, builder: (ctx){ return AlertDialog(title: Text('創造模式 7x22'), content: TextField(controller: nameC, decoration: InputDecoration(labelText:'名稱')), actions: [TextButton(onPressed: ()=>Navigator.pop(ctx), child: Text('取消')), FilledButton(onPressed: (){ Navigator.pop(ctx); openPatternEditor(RosterPattern(nameC.text, List.filled(22*7, shifts.first.code))); }, child: Text('下一步'))]); });
  }
  void openPatternEditor(RosterPattern pat){
    showDialog(context: context, builder: (ctx){
      return StatefulBuilder(builder: (ctx,setM){
        return AlertDialog(title: Text(pat.name), content: SizedBox(width: double.maxFinite, height:420, child: GridView.builder(gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:7, childAspectRatio:0.9), itemCount: pat.codes.length, itemBuilder: (c,i){
          String code=pat.codes[i]; Shift s=getShiftByCode(code);
          return GestureDetector(onTap: (){
            showModalBottomSheet(context: ctx, builder: (b){ return Container(padding: EdgeInsets.all(16), child: Wrap(spacing:8, children: [ for(var ss in shifts) ChoiceChip(label: Text(ss.code), selected: ss.code==code, onSelected: (v){ setM(()=>pat.codes[i]=ss.code); Navigator.pop(b); }) ])); });
          }, child: Container(margin: EdgeInsets.all(2), decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(6)), child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text('${i+1}', style: TextStyle(color:Colors.white, fontSize:8)), Text(code, style: TextStyle(color:Colors.white, fontWeight: FontWeight.bold, fontSize:11))]))));
        })), actions: [TextButton(onPressed: ()=>Navigator.pop(ctx), child: Text('取消')), FilledButton(onPressed: (){ setState(()=>patterns.add(pat)); save(); Navigator.pop(ctx); }, child: Text('保存'))]);
      });
    });
  }
  void applyPattern(){
    if(patterns.isEmpty){ ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('請先創造模式'))); return; }
    RosterPattern sel=patterns.first; DateTime sDate=DateTime(focused.year,focused.month,1); DateTime eDate=DateTime(focused.year,focused.month+1,0);
    showDialog(context: context, builder: (ctx){ return StatefulBuilder(builder: (ctx,setM){ return AlertDialog(title: Text('套用模式'), content: Column(mainAxisSize: MainAxisSize.min, children: [ DropdownButton<RosterPattern>(value: sel, isExpanded:true, items: [for(var p in patterns) DropdownMenuItem(value:p, child: Text(p.name))], onChanged: (v){ if(v!=null) setM(()=>sel=v); }), ListTile(title: Text('開始 ${DateFormat('yyyy-MM-dd').format(sDate)}'), onTap: () async { DateTime? d=await showDatePicker(context: ctx, firstDate: DateTime(2024), lastDate: DateTime(2030), initialDate: sDate); if(d!=null) setM(()=>sDate=d); }), ListTile(title: Text('結束 ${DateFormat('yyyy-MM-dd').format(eDate)}'), onTap: () async { DateTime? d=await showDatePicker(context: ctx, firstDate: DateTime(2024), lastDate: DateTime(2030), initialDate: eDate); if(d!=null) setM(()=>eDate=d); }), ]), actions: [TextButton(onPressed: ()=>Navigator.pop(ctx), child: Text('取消')), FilledButton(onPressed: (){ setState((){ int idx=0; for(DateTime d=sDate;!d.isAfter(eDate); d=d.add(Duration(days:1))){ roster[k(d)]=sel.codes[idx%sel.codes.length]; idx++; } save(); }); Navigator.pop(ctx); }, child: Text('開始'))]); }); });
  }

  @override Widget build(BuildContext context){
    return Scaffold(body: [buildCal(), buildReport(), buildSettings()][tab], bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (i){setState(()=>tab=i);}, destinations: [NavigationDestination(icon: Icon(Icons.calendar_month), label:'月曆'), NavigationDestination(icon: Icon(Icons.bar_chart), label:'報表'), NavigationDestination(icon: Icon(Icons.settings), label:'設定')]));
  }

  Widget buildCal(){
    Shift? selShift = roster.containsKey(k(selected))? getShiftByCode(roster[k(selected)]!) : null;
    return Scaffold(
      appBar: AppBar(title: InkWell(onTap: pickYearMonth, child: Row(mainAxisSize: MainAxisSize.min, children: [Text('W${isoWeek(focused).toString().padLeft(2,'0')} ${DateFormat('yyyy年M月').format(focused)}'), Icon(Icons.arrow_drop_down)])), actions: [
        IconButton(onPressed: createPattern, icon: Icon(Icons.grid_view)),
        IconButton(onPressed: applyPattern, icon: Icon(Icons.playlist_play)),
        IconButton(onPressed: exportCsv, icon: Icon(Icons.share)),
      ]),
      body: Column(children: [
        TableCalendar(
          firstDay: DateTime(2024,1,1), lastDay: DateTime(2030,12,31), focusedDay: focused,
          rowHeight: 68, daysOfWeekHeight: 20,
          startingDayOfWeek: StartingDayOfWeek.monday, headerVisible:false,
          selectedDayPredicate: (d)=>isSameDay(selected,d),
          onDaySelected: (s,f){ setState((){ selected=s; focused=f; }); },
          onPageChanged: (f){ setState(()=>focused=f); },
          calendarBuilders: CalendarBuilders(
            defaultBuilder: (ctx,day,f){
              String key=k(day); String? code=roster[key]; Shift? sh=code!=null?getShiftByCode(code):null;
              bool isToday=isSameDay(day, DateTime.now()); bool isSel=isSameDay(day, selected); bool isMon=day.weekday==1;
              return GestureDetector(
                onTap: (){ setState(()=>selected=day); },
                onLongPress: ()=>onCellEdit(day),
                child: Container(margin: EdgeInsets.all(3), decoration: BoxDecoration(color: sh!=null?sh.color:Colors.grey.shade100, borderRadius: BorderRadius.circular(8), border: isToday?Border.all(color:Colors.amber, width:3): isSel?Border.all(color:Colors.indigo, width:2.5):null), child: Stack(children: [
                  if(isMon) Positioned(top:2, left:2, child: Container(padding: EdgeInsets.symmetric(horizontal:3, vertical:1), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(3)), child: Text('W${isoWeek(day)}', style: TextStyle(color:Colors.white, fontSize:7)))),
                  Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(day.day.toString(), style: TextStyle(fontSize: cellFontSize+2, fontWeight: FontWeight.bold, color: sh!=null?Colors.white:Colors.black87)),
                    if(sh!=null) Text(sh.code, style: TextStyle(fontSize: cellFontSize, color:Colors.white)),
                  ])),
                ])));
            },
          ),
        ),
        Divider(height:1),
        // 放大顯示
        Expanded(child: Container(width: double.infinity, color: Colors.white, padding: EdgeInsets.all(16), child: ListView(children: [
          Row(children: [
            Container(padding: EdgeInsets.symmetric(horizontal:14, vertical:8), decoration: BoxDecoration(color: selShift?.color??Colors.grey.shade300, borderRadius: BorderRadius.circular(24)), child: Text('${DateFormat('MM/dd EEEE').format(selected)} ${roster[k(selected)]??'未排'}', style: TextStyle(fontSize:18, fontWeight: FontWeight.bold, color: selShift!=null?Colors.white:Colors.black87))),
            Spacer(),
            FilledButton.icon(onPressed: ()=>onCellEdit(selected), icon: Icon(Icons.edit, size:16), label: Text('編輯'))
          ]),
          SizedBox(height:14),
          if(selShift!=null) Card(child: ListTile(leading: Icon(Icons.access_time), title: Text('${selShift.name} ${selShift.start}-${selShift.end}'), subtitle: Text('${selShift.hours}小時 津貼 \$${selShift.bonus}'))),
          if(extra[k(selected)]!=null) Card(color: Colors.orange.shade50, child: ListTile(leading: Icon(Icons.timer, color: Colors.orange), title: Text('額外工時 +${extra[k(selected)]}h', style: TextStyle(fontWeight: FontWeight.bold)))),
          if(notes[k(selected)]!=null) Card(color: Colors.amber.shade50, child: ListTile(leading: Icon(Icons.sticky_note_2), title: Text('記事'), subtitle: Text(notes[k(selected)]!, style: TextStyle(fontSize:16)))),
          if(selShift==null && notes[k(selected)]==null && extra[k(selected)]==null) Text('此日未有資料，長按格子或按編輯新增', style: TextStyle(color: Colors.grey)),
          SizedBox(height:12),
          Text('當日 ${DateFormat('yyyy-MM-dd').format(DateTime.now())} 選中 ${k(selected)}', style: TextStyle(fontSize:12, color: Colors.grey)),
        ]))),
      ]),
    );
  }
  Widget buildReport(){ return Scaffold(appBar: AppBar(title: Text('報表')), body: ListView(padding: EdgeInsets.all(16), children: [Text('本月已排 ${roster.keys.where((e){ var d=DateTime.parse(e); return d.year==focused.year&&d.month==focused.month; }).length} 日')])); }
  Widget buildSettings(){
    return Scaffold(appBar: AppBar(title: Text('設定')), body: ListView(padding: EdgeInsets.all(16), children: [
      Text('格子文字大小 ${cellFontSize.toStringAsFixed(0)}'), Slider(value: cellFontSize, min:8, max:20, divisions:12, label: cellFontSize.toStringAsFixed(0), onChanged: (v){ setState(()=>cellFontSize=v); save(); }),
      Divider(),
      for(var s in shifts) Card(child: ListTile(leading: CircleAvatar(backgroundColor: s.color, child: Text(s.code, style: TextStyle(color:Colors.white, fontSize:10))), title: Text('${s.name} ${s.code}'))),
      Divider(),
      for(var p in patterns) Card(child: ListTile(title: Text(p.name), subtitle: Text('${p.codes.length}日週期'), trailing: IconButton(icon: Icon(Icons.delete), onPressed: (){ setState(()=>patterns.remove(p)); save(); }))),
      FilledButton.icon(onPressed: createPattern, icon: Icon(Icons.add), label: Text('新增 7x22 模式')),
    ]));
  }
}
