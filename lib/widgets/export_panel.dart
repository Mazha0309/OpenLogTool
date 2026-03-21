import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:forui/forui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:excel/excel.dart' as excel_lib;
import 'package:openlogtool/providers/log_provider.dart';
import 'package:openlogtool/models/log_entry.dart';

class ExportPanel extends StatelessWidget {
  const ExportPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 根据可用宽度判断是否使用横向排列
        final isWideScreen = constraints.maxWidth > 600;
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '数据导入导出',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            
            const SizedBox(height: 24),
            
            // 根据屏幕宽度选择横向或纵向排列
            if (isWideScreen)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildExportCard(context)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildImportCard(context)),
                ],
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildExportCard(context),
                  const SizedBox(height: 16),
                  _buildImportCard(context),
                ],
              ),
            
            const SizedBox(height: 16),
            
            // 文件信息
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
                    '文件格式说明',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '• JSON: 标准JSON格式，包含所有记录数据\n'
                    '• Excel: 使用index.html中的样式，包含分组和样式\n'
                    '• PNG: 表格截图，适合分享和打印',
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
      },
    );
  }

  Widget _buildExportCard(BuildContext context) {
    return FCard(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '导出数据',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            
            // 导出按钮
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.file_download),
                  label: const Text('导出 JSON'),
                  onPressed: () => _exportJSON(context),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.table_chart),
                  label: const Text('导出 Excel'),
                  onPressed: () => _exportExcel(context),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.image),
                  label: const Text('导出 PNG'),
                  onPressed: () => _exportPNG(context),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImportCard(BuildContext context) {
    return FCard(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '导入数据',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            
            // 导入按钮
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.file_upload),
                  label: const Text('导入 JSON'),
                  onPressed: () => _importJSON(context),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.table_chart),
                  label: const Text('导入 Excel'),
                  onPressed: () => _importExcel(context),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportJSON(BuildContext context) async {
    final logProvider = Provider.of<LogProvider>(context, listen: false);
    final logs = logProvider.logs;
    
    if (logs.isEmpty) {
      _showSnackBar(context, '没有数据可以导出');
      return;
    }
    
    try {
      final jsonData = logs.map((log) => log.toJson()).toList();
      final jsonString = const JsonEncoder.withIndent('  ').convert(jsonData);
      
      final directory = await getDownloadsDirectory();
      if (directory == null) {
        _showSnackBar(context, '无法访问下载目录');
        return;
      }
      
      final now = DateTime.now();
      final filename = '点名记录_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}.json';
      final file = File('${directory.path}/$filename');
      
      await file.writeAsString(jsonString);
      
      _showSuccessDialog(context, 'JSON导出成功', '文件已保存到:\n${file.path}', file.path);
    } catch (e) {
      _showSnackBar(context, '导出失败: $e');
    }
  }

  Future<void> _exportExcel(BuildContext context) async {
    final logProvider = Provider.of<LogProvider>(context, listen: false);
    final logs = logProvider.logs;

    if (logs.isEmpty) {
      _showSnackBar(context, '没有数据可以导出');
      return;
    }

    try {
      final excel = excel_lib.Excel.createExcel();
      final sheet = excel['点名记录'];

      final defaultSheet = excel.getDefaultSheet();
      if (defaultSheet != null && defaultSheet != '点名记录') {
        excel.delete(defaultSheet);
      }

      final headers = ['#', '时间', '呼号', '信号报告', 'QTH', '设备', '功率', '天线', '高度', '备注'];

      sheet.insertRowIterables(headers.map((e) => excel_lib.TextCellValue(e)).toList(), 0);

      final grouped = <String, List<LogEntry>>{};
      for (final log in logs) {
        final controller = log.controller;
        grouped.putIfAbsent(controller, () => []).add(log);
      }

      int globalIndex = 1;
      int currentRow = 1;

      for (final controller in grouped.keys) {
        final controllerLogs = grouped[controller]!;

        final firstTime = controllerLogs.isNotEmpty ? controllerLogs.first.time : '';
        final controllerTime = _calculateControllerTime(firstTime);

        final controllerRow = <String>['点名主控:', controllerTime, controller, '', '', '', '', '', '', ''];
        sheet.insertRowIterables(controllerRow.map((e) => excel_lib.TextCellValue(e)).toList(), currentRow);
        currentRow++;

        for (final log in controllerLogs) {
          final rowData = [
            excel_lib.TextCellValue(globalIndex.toString()),
            excel_lib.TextCellValue(log.time),
            excel_lib.TextCellValue(log.callsign),
            excel_lib.TextCellValue(log.report),
            excel_lib.TextCellValue(log.qth),
            excel_lib.TextCellValue(log.device),
            excel_lib.TextCellValue(log.power),
            excel_lib.TextCellValue(log.antenna),
            excel_lib.TextCellValue(log.height),
            excel_lib.TextCellValue(''),
          ];
          sheet.insertRowIterables(rowData, currentRow);
          globalIndex++;
          currentRow++;
        }
      }

      final colWidths = <double>[10, 10, 15, 12, 18, 15, 10, 18, 10, 10];
      for (var i = 0; i < colWidths.length; i++) {
        sheet.setColumnWidth(i, colWidths[i]);
      }

      final directory = await getDownloadsDirectory();
      if (directory == null) {
        _showSnackBar(context, '无法访问下载目录');
        return;
      }

      final now = DateTime.now();
      final filename = '点名记录_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}.xlsx';
      final file = File('${directory.path}/$filename');

      final bytes = excel.save();
      if (bytes != null) {
        await file.writeAsBytes(bytes);
        _showSuccessDialog(context, 'Excel导出成功', '文件已保存到:\n${file.path}', file.path);
      } else {
        _showSnackBar(context, '导出失败: 无法生成Excel文件');
      }
    } catch (e) {
      _showSnackBar(context, '导出失败: $e');
    }
  }

  String _calculateControllerTime(String timeStr) {
    if (timeStr.isEmpty) return '';

    final parts = timeStr.split(':');
    if (parts.length < 2) return timeStr;

    var hours = int.tryParse(parts[0]) ?? 0;
    var minutes = int.tryParse(parts[1]) ?? 0;

    minutes -= 1;
    if (minutes < 0) {
      minutes = 59;
      hours = (hours - 1) % 24;
    }

    if (minutes % 5 == 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
    }

    final nearestFive = (minutes / 5).round() * 5;
    final nearestTen = (minutes / 10).round() * 10;

    final diffToFive = (minutes - nearestFive).abs();
    final diffToTen = (minutes - nearestTen).abs();

    if (diffToTen == 1 || nearestTen == 60) {
      minutes = nearestTen == 60 ? 0 : nearestTen;
      if (nearestTen == 60) {
        hours = (hours + 1) % 24;
      }
    } else if (diffToFive == 1) {
      minutes = nearestFive % 60;
      if (nearestFive == 60) {
        hours = (hours + 1) % 24;
        minutes = 0;
      }
    }

    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
  }

  Future<void> _exportPNG(BuildContext context) async {
    _showSnackBar(context, 'PNG导出功能开发中');
  }

  Future<void> _importJSON(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      
      if (result == null || result.files.isEmpty) return;
      
      final file = File(result.files.single.path!);
      final content = await file.readAsString();
      
      final jsonData = json.decode(content) as List;
      final logProvider = Provider.of<LogProvider>(context, listen: false);
      
      // 解析JSON数据
      final importedLogs = jsonData.map((item) {
        return LogEntry(
          time: item['time'] ?? '',
          controller: item['controller'] ?? '',
          callsign: item['callsign'] ?? '',
          report: item['report'] ?? '',
          qth: item['qth'] ?? '',
          device: item['device'] ?? '',
          power: item['power'] ?? '',
          antenna: item['antenna'] ?? '',
          height: item['height'] ?? '',
        );
      }).toList();
      
      await logProvider.importLogs(importedLogs);
      _showSnackBar(context, '导入成功: ${importedLogs.length} 条记录');
    } catch (e) {
      _showSnackBar(context, '导入失败: $e');
    }
  }

  Future<void> _importExcel(BuildContext context) async {
    _showSnackBar(context, 'Excel导入功能开发中');
  }

  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showSuccessDialog(BuildContext context, String title, String message, String filePath) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
          ElevatedButton(
            onPressed: () {
              OpenFile.open(filePath);
              Navigator.pop(context);
            },
            child: const Text('打开文件'),
          ),
        ],
      ),
    );
  }
}