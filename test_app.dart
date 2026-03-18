import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:openlogtool/providers/log_provider.dart';
import 'package:openlogtool/models/log_entry.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 创建测试应用
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LogProvider()),
      ],
      child: MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('表格测试')),
          body: TableTestPage(),
        ),
      ),
    ),
  );
}

class TableTestPage extends StatefulWidget {
  @override
  _TableTestPageState createState() => _TableTestPageState();
}

class _TableTestPageState extends State<TableTestPage> {
  @override
  void initState() {
    super.initState();
    _addTestData();
  }

  void _addTestData() async {
    final logProvider = Provider.of<LogProvider>(context, listen: false);
    
    // 添加一些测试数据
    final testLogs = [
      LogEntry(
        time: '14:30',
        controller: 'BG5CRL',
        callsign: 'BH4ABC',
        report: '59',
        qth: '杭州',
        device: 'IC-7300',
        power: '100W',
        antenna: 'DP',
        height: '10m',
      ),
      LogEntry(
        time: '15:45',
        controller: 'BG5CRL',
        callsign: 'BH8DEF',
        report: '57',
        qth: '上海',
        device: 'FT-991A',
        power: '50W',
        antenna: 'GP',
        height: '8m',
      ),
      LogEntry(
        time: '16:20',
        controller: 'BG5CRL',
        callsign: 'BH0GHI',
        report: '59+',
        qth: '北京',
        device: 'IC-705',
        power: '10W',
        antenna: 'YAGI',
        height: '15m',
      ),
    ];
    
    for (final log in testLogs) {
      await logProvider.addLog(log);
    }
    
    // 等待一下让界面更新
    await Future.delayed(const Duration(milliseconds: 500));
    
    // 打印日志数量
    print('已添加 ${logProvider.logCount} 条测试记录');
    for (var i = 0; i < logProvider.logs.length; i++) {
      final log = logProvider.logs[i];
      print('记录 $i: ${log.controller} - ${log.callsign} - ${log.time}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final logProvider = Provider.of<LogProvider>(context);
    
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            '测试表格数据显示 - 共 ${logProvider.logCount} 条记录',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('#')),
                DataColumn(label: Text('时间')),
                DataColumn(label: Text('点名主控')),
                DataColumn(label: Text('呼号')),
                DataColumn(label: Text('信号报告')),
                DataColumn(label: Text('QTH')),
                DataColumn(label: Text('设备')),
                DataColumn(label: Text('功率')),
                DataColumn(label: Text('天线')),
                DataColumn(label: Text('高度')),
              ],
              rows: logProvider.logs.asMap().entries.map((entry) {
                final index = entry.key;
                final log = entry.value;
                
                return DataRow(
                  cells: [
                    DataCell(Text('${index + 1}')),
                    DataCell(Text(log.time)),
                    DataCell(Text(log.controller)),
                    DataCell(Text(log.callsign)),
                    DataCell(Text(log.report)),
                    DataCell(Text(log.qth)),
                    DataCell(Text(log.device)),
                    DataCell(Text(log.power)),
                    DataCell(Text(log.antenna)),
                    DataCell(Text(log.height)),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: ElevatedButton(
            onPressed: () => _addTestData(),
            child: const Text('添加更多测试数据'),
          ),
        ),
      ],
    );
  }
}