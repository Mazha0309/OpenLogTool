import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:openlogtool/providers/log_provider.dart';
import 'package:openlogtool/models/log_entry.dart';

class ExportPanel extends StatelessWidget {
  const ExportPanel({super.key});

  Future<void> _exportJSON(BuildContext context) async {
    final logProvider = Provider.of<LogProvider>(context, listen: false);
    
    if (logProvider.logs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('没有数据可以导出'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    try {
      final jsonData = logProvider.logs.map((log) => log.toJson()).toList();
      final jsonString = JsonEncoder.withIndent('  ').convert(jsonData);
      
      final directory = await getApplicationDocumentsDirectory();
      final now = DateTime.now();
      final filename = 'Radio_Log_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.json';
      final file = File('${directory.path}/$filename');
      
      await file.writeAsString(jsonString);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('JSON文件已保存到: ${file.path}'),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: '打开',
            onPressed: () => OpenFile.open(file.path),
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('导出失败: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _importJSON(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        final content = String.fromCharCodes(file.bytes!);
        final jsonData = jsonDecode(content) as List;
        
        final logs = jsonData.map((item) => LogEntry.fromJson(item)).toList();
        
        final logProvider = Provider.of<LogProvider>(context, listen: false);
        await logProvider.importLogs(logs);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已导入 ${logs.length} 条记录'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('导入失败: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _exportExcel(BuildContext context) async {
    final logProvider = Provider.of<LogProvider>(context, listen: false);
    
    if (logProvider.logs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('没有数据可以导出'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    try {
      // 这里需要实现Excel导出逻辑
      // 由于excel包的复杂性，这里先提供一个占位实现
      // 在实际应用中，您需要安装excel包并实现完整的Excel导出功能
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Excel导出功能需要安装excel包并实现具体逻辑'),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 3),
        ),
      );
      
      // 示例代码（需要安装excel包）：
      /*
      final excel = Excel.createExcel();
      final sheet = excel['点名记录'];
      
      // 添加表头
      sheet.appendRow(['#', '时间', '点名主控', '呼号', '信号报告', 'QTH', '设备', '功率', '天线', '高度']);
      
      // 添加数据
      for (var i = 0; i < logProvider.logs.length; i++) {
        final log = logProvider.logs[i];
        sheet.appendRow([
          i + 1,
          log.time,
          log.controller,
          log.callsign,
          log.report,
          log.qth,
          log.device,
          log.power,
          log.antenna,
          log.height,
        ]);
      }
      
      final directory = await getApplicationDocumentsDirectory();
      final now = DateTime.now();
      final filename = '点名记录_${now.year}${now.month}${now.day}_${now.hour}${now.minute}.xlsx';
      final file = File('${directory.path}/$filename');
      
      final bytes = excel.save();
      await file.writeAsBytes(bytes!);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Excel文件已保存到: ${file.path}'),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: '打开',
            onPressed: () => OpenFile.open(file.path),
          ),
        ),
      );
      */
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('导出失败: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final logProvider = Provider.of<LogProvider>(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '导入导出',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        
        const SizedBox(height: 16),
        
        Text(
          '当前有 ${logProvider.logCount} 条记录',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        
        const SizedBox(height: 24),
        
        // 按钮网格
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 3,
          children: [
            // 导出JSON按钮
            ElevatedButton.icon(
              icon: const Icon(Icons.file_download),
              label: const Text('导出 JSON'),
              onPressed: () => _exportJSON(context),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            
            // 导入JSON按钮
            ElevatedButton.icon(
              icon: const Icon(Icons.file_upload),
              label: const Text('导入 JSON'),
              onPressed: () => _importJSON(context),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
              ),
            ),
            
            // 导出Excel按钮
            ElevatedButton.icon(
              icon: const Icon(Icons.table_chart),
              label: const Text('导出 Excel'),
              onPressed: () => _exportExcel(context),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
                foregroundColor: Theme.of(context).colorScheme.onTertiaryContainer,
              ),
            ),
            
            // 备份所有数据按钮
            ElevatedButton.icon(
              icon: const Icon(Icons.backup),
              label: const Text('备份所有数据'),
              onPressed: () async {
                // 这里可以实现完整的数据备份功能
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('备份功能开发中...'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 16),
        
        // 说明文本
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '说明:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '• JSON格式：用于数据交换和备份\n'
                '• Excel格式：用于数据分析和打印\n'
                '• 所有数据自动保存在本地存储中',
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}