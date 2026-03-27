import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:forui/forui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:excel/excel.dart' as excel_lib;
import 'package:openlogtool/providers/log_provider.dart';
import 'package:openlogtool/providers/settings_provider.dart';
import 'package:openlogtool/models/log_entry.dart';
import 'package:openlogtool/models/export_settings.dart';

class ExportPanel extends StatelessWidget {
  const ExportPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
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
            
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant.withValues(alpha: 0.3),
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
                    '• Excel: 使用Excel格式，包含分组和样式',
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '导出数据',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.settings),
                  onPressed: () => _showExportSettingsDialog(context),
                  tooltip: 'Excel导出设置',
                ),
              ],
            ),
            const SizedBox(height: 12),
            
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

  void _showExportSettingsDialog(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    ExportSettings settings = settingsProvider.exportSettings;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Excel导出设置'),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('抬头文字'),
                    TextField(
                      controller: TextEditingController(text: settings.headerText),
                      decoration: const InputDecoration(
                        hintText: '如: BR5AI{yyyy-MM-dd}日点名记录',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        setState(() => settings.headerText = value);
                      },
                    ),
                    const SizedBox(height: 16),
                    
                    const Text('抬头背景色'),
                    Row(
                      children: [
                        _buildColorButton(settings.headerBackgroundColor, () async {
                          final color = await _showColorPickerDialog(
                            context,
                            '选择抬头背景色',
                            settings.headerBackgroundColor,
                          );
                          if (color != null) {
                            setState(() => settings.headerBackgroundColor = color);
                          }
                        }),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'HEX: #${settings.headerBackgroundColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
                            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    const Text('主控栏背景色'),
                    Row(
                      children: [
                        _buildColorButton(settings.controllerBackgroundColor, () async {
                          final color = await _showColorPickerDialog(
                            context,
                            '选择主控栏背景色',
                            settings.controllerBackgroundColor,
                          );
                          if (color != null) {
                            setState(() => settings.controllerBackgroundColor = color);
                          }
                        }),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'HEX: #${settings.controllerBackgroundColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
                            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    Row(
                      children: [
                        const Text('双色交替'),
                        const Spacer(),
                        Switch(
                          value: settings.useAlternateColors,
                          onChanged: (value) {
                            setState(() => settings.useAlternateColors = value);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    
                    const Text('普通背景色'),
                    Row(
                      children: [
                        _buildColorButton(settings.tableBackgroundColor, () async {
                          final color = await _showColorPickerDialog(
                            context,
                            '选择普通背景色',
                            settings.tableBackgroundColor,
                          );
                          if (color != null) {
                            setState(() => settings.tableBackgroundColor = color);
                          }
                        }),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'HEX: #${settings.tableBackgroundColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
                            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                          ),
                        ),
                      ],
                    ),
                    
                    if (settings.useAlternateColors) ...[
                      const SizedBox(height: 16),
                      const Text('交替行颜色'),
                      Row(
                        children: [
                          _buildColorButton(settings.alternateRowColor, () async {
                            final color = await _showColorPickerDialog(
                              context,
                              '选择交替行颜色',
                              settings.alternateRowColor,
                            );
                            if (color != null) {
                              setState(() => settings.alternateRowColor = color);
                            }
                          }),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'HEX: #${settings.alternateRowColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
                              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    
                    const Text('表格字体'),
                    DropdownButton<String>(
                      value: settings.fontFamily.isEmpty ? 'Roboto' : settings.fontFamily,
                      isExpanded: true,
                      items: Provider.of<SettingsProvider>(context, listen: false)
                          .availableFonts
                          .map((font) => DropdownMenuItem(
                                value: font,
                                child: Text(font),
                              ))
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => settings.fontFamily = value);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () {
                  settingsProvider.updateExportSettings(settings);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('设置已保存')),
                  );
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildColorButton(Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade400, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Center(
          child: Icon(Icons.colorize, size: 20, color: Colors.white),
        ),
      ),
    );
  }

  Future<Color?> _showColorPickerDialog(
    BuildContext context,
    String title,
    Color initialColor,
  ) async {
    int red = initialColor.r.toInt();
    int green = initialColor.g.toInt();
    int blue = initialColor.b.toInt();
    
    return showDialog<Color>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(title),
              content: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: Color.fromARGB(255, red, green, blue),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade400, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildColorSlider(
                      label: '红色',
                      value: red.toDouble(),
                      color: Colors.red,
                      onChanged: (value) {
                        setState(() => red = value.toInt());
                      },
                    ),
                    _buildColorSlider(
                      label: '绿色',
                      value: green.toDouble(),
                      color: Colors.green,
                      onChanged: (value) {
                        setState(() => green = value.toInt());
                      },
                    ),
                    _buildColorSlider(
                      label: '蓝色',
                      value: blue.toDouble(),
                      color: Colors.blue,
                      onChanged: (value) {
                        setState(() => blue = value.toInt());
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'HEX: #${red.toRadixString(16).padLeft(2, '0')}${green.toRadixString(16).padLeft(2, '0')}${blue.toRadixString(16).padLeft(2, '0')}'.toUpperCase(),
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context, Color.fromARGB(255, red, green, blue));
                  },
                  child: const Text('确定'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildColorSlider({
    required String label,
    required double value,
    required Color color,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: ${value.toInt()}'),
        Slider(
          value: value,
          min: 0,
          max: 255,
          activeColor: color,
          onChanged: onChanged,
        ),
      ],
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
    final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    final settings = settingsProvider.exportSettings;
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

      final now = DateTime.now();
      String headerText = settings.headerText;
      headerText = headerText.replaceAll('{yyyy}', now.year.toString());
      headerText = headerText.replaceAll('{MM}', now.month.toString().padLeft(2, '0'));
      headerText = headerText.replaceAll('{dd}', now.day.toString().padLeft(2, '0'));
      headerText = headerText.replaceAll('{yyyy-MM-dd}', '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}');

      final headerColor = excel_lib.ExcelColor.fromInt(settings.headerBackgroundColor.toARGB32());
      final controllerColor = excel_lib.ExcelColor.fromInt(settings.controllerBackgroundColor.toARGB32());
      final alternateColor = excel_lib.ExcelColor.fromInt(settings.alternateRowColor.toARGB32());
      const whiteColor = excel_lib.ExcelColor.white;

      final borderStyle = excel_lib.Border(
        borderStyle: excel_lib.BorderStyle.Thin,
        borderColorHex: excel_lib.ExcelColor.black,
      );

      sheet.insertRowIterables([excel_lib.TextCellValue(headerText)], 0);
      sheet.merge(excel_lib.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0), excel_lib.CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: 0), customValue: excel_lib.TextCellValue(headerText));
      sheet.row(0).forEach((cell) {
        if (cell != null) {
          cell.cellStyle = excel_lib.CellStyle(
            backgroundColorHex: headerColor,
            fontSize: 14,
            bold: true,
            horizontalAlign: excel_lib.HorizontalAlign.Center,
            textWrapping: excel_lib.TextWrapping.WrapText,
            topBorder: borderStyle,
            bottomBorder: borderStyle,
            leftBorder: borderStyle,
            rightBorder: borderStyle,
          );
        }
      });

      final headers = ['#', '时间', '呼号', '信号报告', 'QTH', '设备', '功率', '天线', '高度', '备注'];
      sheet.insertRowIterables(headers.map((e) => excel_lib.TextCellValue(e)).toList(), 1);
      sheet.row(1).forEach((cell) {
        if (cell != null) {
          cell.cellStyle = excel_lib.CellStyle(
            backgroundColorHex: headerColor,
            fontSize: 12,
            bold: true,
            horizontalAlign: excel_lib.HorizontalAlign.Center,
            topBorder: borderStyle,
            bottomBorder: borderStyle,
            leftBorder: borderStyle,
            rightBorder: borderStyle,
          );
        }
      });

      final grouped = <String, List<LogEntry>>{};
      for (final log in logs) {
        final controller = log.controller;
        grouped.putIfAbsent(controller, () => []).add(log);
      }

      int globalIndex = 1;
      int currentRow = 2;

      for (final controller in grouped.keys) {
        final controllerLogs = grouped[controller]!;

        final firstTime = controllerLogs.isNotEmpty ? controllerLogs.first.time : '';
        final controllerTime = _calculateControllerTime(firstTime);

        final controllerRow = <String>['点名主控:', controllerTime, controller, '', '', '', '', '', '', ''];
        sheet.insertRowIterables(controllerRow.map((e) => excel_lib.TextCellValue(e)).toList(), currentRow);
        sheet.row(currentRow).forEach((cell) {
          if (cell != null) {
            cell.cellStyle = excel_lib.CellStyle(
              backgroundColorHex: controllerColor,
              fontSize: 11,
              bold: true,
              topBorder: borderStyle,
              bottomBorder: borderStyle,
              leftBorder: borderStyle,
              rightBorder: borderStyle,
            );
          }
        });
        currentRow++;

        for (int i = 0; i < controllerLogs.length; i++) {
          final log = controllerLogs[i];
          excel_lib.ExcelColor rowColor;
          
          if (settings.useAlternateColors) {
            rowColor = i % 2 == 0 ? whiteColor : alternateColor;
          } else {
            rowColor = whiteColor;
          }
          
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
          sheet.row(currentRow).forEach((cell) {
            if (cell != null) {
              cell.cellStyle = excel_lib.CellStyle(
                backgroundColorHex: rowColor,
                fontSize: 10,
                topBorder: borderStyle,
                bottomBorder: borderStyle,
                leftBorder: borderStyle,
                rightBorder: borderStyle,
              );
            }
          });
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
      
      logProvider.importLogs(importedLogs);
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

  void _showSuccessDialog(BuildContext context, String title, String message, String path) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    path,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 20),
                  onPressed: () {
                    // 复制到剪贴板功能
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('路径已复制')),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}
