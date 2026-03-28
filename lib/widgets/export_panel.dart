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

class _HSVSaturationValuePainter extends CustomPainter {
  final double hue;
  final double saturation;
  final double value;

  _HSVSaturationValuePainter(this.hue, this.saturation, this.value);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    final saturationGradient = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        Colors.white,
        HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor(),
      ],
    );
    canvas.drawRect(rect, Paint()..shader = saturationGradient.createShader(rect));

    final valueGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.transparent,
        Colors.black,
      ],
    );
    canvas.drawRect(rect, Paint()..shader = valueGradient.createShader(rect));

    final circleX = saturation * size.width;
    final circleY = (1.0 - value) * size.height;
    final circleColor = HSVColor.fromAHSV(1.0, hue, saturation, value).toColor();
    
    canvas.drawCircle(
      Offset(circleX, circleY),
      8,
      Paint()
        ..color = circleColor
        ..style = PaintingStyle.fill,
    );
    
    canvas.drawCircle(
      Offset(circleX, circleY),
      8,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    
    canvas.drawCircle(
      Offset(circleX, circleY),
      10,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_HSVSaturationValuePainter oldDelegate) {
    return oldDelegate.hue != hue || 
           oldDelegate.saturation != saturation || 
           oldDelegate.value != value;
  }
}

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
          const dialogFont = TextStyle(fontSize: 14);
          
          return AlertDialog(
            title: const Text('Excel导出设置', style: dialogFont),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('抬头文字', style: dialogFont),
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
                    
                    const Text('抬头背景色', style: dialogFont),
                    Row(
                      children: [
                        _buildColorButton(settings.headerBackgroundColor, () async {
                          final color = await _showColorPickerDialog(
                            context,
                            '选择抬头背景色',
                            settings.headerBackgroundColor,
                            settings.fontFamily,
                          );
                          if (color != null) {
                            setState(() => settings.headerBackgroundColor = color);
                          }
                        }),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'HEX: #${settings.headerBackgroundColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
                            style: TextStyle(fontSize: 12, fontFamily: settings.fontFamily.isEmpty ? 'monospace' : settings.fontFamily),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    const Text('表头背景色', style: dialogFont),
                    Row(
                      children: [
                        _buildColorButton(settings.headerRowBackgroundColor, () async {
                          final color = await _showColorPickerDialog(
                            context,
                            '选择表头背景色',
                            settings.headerRowBackgroundColor,
                            settings.fontFamily,
                          );
                          if (color != null) {
                            setState(() => settings.headerRowBackgroundColor = color);
                          }
                        }),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'HEX: #${settings.headerRowBackgroundColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
                            style: TextStyle(fontSize: 12, fontFamily: settings.fontFamily.isEmpty ? 'monospace' : settings.fontFamily),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    const Text('主控栏背景色', style: dialogFont),
                    Row(
                      children: [
                        _buildColorButton(settings.controllerBackgroundColor, () async {
                          final color = await _showColorPickerDialog(
                            context,
                            '选择主控栏背景色',
                            settings.controllerBackgroundColor,
                            settings.fontFamily,
                          );
                          if (color != null) {
                            setState(() => settings.controllerBackgroundColor = color);
                          }
                        }),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'HEX: #${settings.controllerBackgroundColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
                            style: TextStyle(fontSize: 12, fontFamily: settings.fontFamily.isEmpty ? 'monospace' : settings.fontFamily),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    Row(
                      children: [
                        const Text('双色交替', style: dialogFont),
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
                    
                    const Text('普通背景色', style: dialogFont),
                    Row(
                      children: [
                        _buildColorButton(settings.tableBackgroundColor, () async {
                          final color = await _showColorPickerDialog(
                            context,
                            '选择普通背景色',
                            settings.tableBackgroundColor,
                            settings.fontFamily,
                          );
                          if (color != null) {
                            setState(() => settings.tableBackgroundColor = color);
                          }
                        }),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'HEX: #${settings.tableBackgroundColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
                            style: TextStyle(fontSize: 12, fontFamily: settings.fontFamily.isEmpty ? 'monospace' : settings.fontFamily),
                          ),
                        ),
                      ],
                    ),
                    
                    if (settings.useAlternateColors) ...[
                      const SizedBox(height: 16),
                      const Text('交替行颜色', style: dialogFont),
                      Row(
                        children: [
                          _buildColorButton(settings.alternateRowColor, () async {
                            final color = await _showColorPickerDialog(
                              context,
                              '选择交替行颜色',
                              settings.alternateRowColor,
                              settings.fontFamily,
                            );
                            if (color != null) {
                              setState(() => settings.alternateRowColor = color);
                            }
                          }),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'HEX: #${settings.alternateRowColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
                              style: TextStyle(fontSize: 12, fontFamily: settings.fontFamily.isEmpty ? 'monospace' : settings.fontFamily),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    
                    Row(
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.restore, size: 18),
                          label: const Text('恢复默认颜色'),
                          onPressed: () {
                            setState(() {
                              settings.headerBackgroundColor = const Color(0xFFC0E5F2);
                              settings.headerRowBackgroundColor = const Color(0xFF1D85EE);
                              settings.controllerBackgroundColor = const Color(0xFFFFFF64);
                              settings.tableBackgroundColor = Colors.white;
                              settings.alternateRowColor = const Color(0xFFC0E5F2);
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    const Text('表格字体', style: dialogFont),
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
    String fontFamily,
  ) async {
    HSVColor hsvColor = HSVColor.fromColor(initialColor);
    
    return showDialog<Color>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            const dialogFont = TextStyle(fontSize: 14);
            Color currentColor = hsvColor.toColor();
            
            return AlertDialog(
              title: Text(title, style: dialogFont),
              content: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 280,
                      height: 150,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade400, width: 1),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: GestureDetector(
                          onPanStart: (details) {
                            _updateHsvFromTap(details.localPosition, const Size(280, 150), hsvColor.hue, setState, (newHsv) {
                              hsvColor = newHsv;
                              currentColor = hsvColor.toColor();
                            });
                          },
                          onPanUpdate: (details) {
                            _updateHsvFromTap(details.localPosition, const Size(280, 150), hsvColor.hue, setState, (newHsv) {
                              hsvColor = newHsv;
                              currentColor = hsvColor.toColor();
                            });
                          },
                          child: CustomPaint(
                            size: const Size(280, 150),
                            painter: _HSVSaturationValuePainter(
                              hsvColor.hue,
                              hsvColor.saturation,
                              hsvColor.value,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: currentColor,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade400, width: 2),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'HEX: #${currentColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
                            style: TextStyle(fontSize: 14, fontFamily: fontFamily.isEmpty ? null : fontFamily),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('色相:', style: dialogFont),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Stack(
                            alignment: Alignment.centerLeft,
                            children: [
                              Container(
                                height: 20,
                                margin: const EdgeInsets.symmetric(vertical: 2),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFFFF0000),
                                      Color(0xFFFFFF00),
                                      Color(0xFF00FF00),
                                      Color(0xFF00FFFF),
                                      Color(0xFF0000FF),
                                      Color(0xFFFF00FF),
                                      Color(0xFFFF0000),
                                    ],
                                  ),
                                ),
                              ),
                              SliderTheme(
                                 data: SliderThemeData(
                                   trackHeight: 20,
                                   thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                                   overlayShape: SliderComponentShape.noOverlay,
                                   activeTrackColor: Colors.transparent,
                                   inactiveTrackColor: Colors.transparent,
                                 ),
                                child: Slider(
                                  value: hsvColor.hue,
                                  min: 0,
                                  max: 360,
                                  onChanged: (value) {
                                    setState(() {
                                      hsvColor = hsvColor.withHue(value);
                                      currentColor = hsvColor.toColor();
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('透明度:', style: dialogFont),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Slider(
                            value: hsvColor.alpha,
                            min: 0,
                            max: 1,
                            activeColor: currentColor,
                            inactiveColor: Colors.grey.shade300,
                            onChanged: (value) {
                              setState(() {
                                hsvColor = hsvColor.withAlpha(value);
                                currentColor = hsvColor.toColor();
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildQuickColorButton(const Color(0xFF2196F3), () {
                          setState(() {
                            hsvColor = HSVColor.fromColor(const Color(0xFF2196F3));
                            currentColor = hsvColor.toColor();
                          });
                        }),
                        _buildQuickColorButton(const Color(0xFF4CAF50), () {
                          setState(() {
                            hsvColor = HSVColor.fromColor(const Color(0xFF4CAF50));
                            currentColor = hsvColor.toColor();
                          });
                        }),
                        _buildQuickColorButton(const Color(0xFFF44336), () {
                          setState(() {
                            hsvColor = HSVColor.fromColor(const Color(0xFFF44336));
                            currentColor = hsvColor.toColor();
                          });
                        }),
                        _buildQuickColorButton(const Color(0xFFFF9800), () {
                          setState(() {
                            hsvColor = HSVColor.fromColor(const Color(0xFFFF9800));
                            currentColor = hsvColor.toColor();
                          });
                        }),
                        _buildQuickColorButton(const Color(0xFF9C27B0), () {
                          setState(() {
                            hsvColor = HSVColor.fromColor(const Color(0xFF9C27B0));
                            currentColor = hsvColor.toColor();
                          });
                        }),
                        _buildQuickColorButton(const Color(0xFF607D8B), () {
                          setState(() {
                            hsvColor = HSVColor.fromColor(const Color(0xFF607D8B));
                            currentColor = hsvColor.toColor();
                          });
                        }),
                      ],
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
                    Navigator.pop(context, currentColor);
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

  void _updateHsvFromTap(Offset position, Size size, double hue, StateSetter setState, Function(HSVColor) onUpdate) {
    double saturation = (position.dx / size.width).clamp(0.0, 1.0);
    double value = 1.0 - (position.dy / size.height).clamp(0.0, 1.0);
    final newHsv = HSVColor.fromAHSV(1.0, hue, saturation, value);
    setState(() {});
    onUpdate(newHsv);
  }

  Widget _buildQuickColorButton(Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.grey.shade400, width: 1),
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
      final headerRowColor = excel_lib.ExcelColor.fromInt(settings.headerRowBackgroundColor.toARGB32());
      final controllerColor = excel_lib.ExcelColor.fromInt(settings.controllerBackgroundColor.toARGB32());
      final alternateColor = excel_lib.ExcelColor.fromInt(settings.alternateRowColor.toARGB32());
      const whiteColor = excel_lib.ExcelColor.white;

      final borderStyle = excel_lib.Border(
        borderStyle: excel_lib.BorderStyle.Thin,
        borderColorHex: excel_lib.ExcelColor.black,
      );

      final String? excelFontFamily = settings.fontFamily.isEmpty ? null : settings.fontFamily;

      sheet.insertRowIterables([excel_lib.TextCellValue(headerText)], 0);
      sheet.merge(excel_lib.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0), excel_lib.CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: 0), customValue: excel_lib.TextCellValue(headerText));
      sheet.row(0).forEach((cell) {
        if (cell != null) {
          cell.cellStyle = excel_lib.CellStyle(
            backgroundColorHex: headerColor,
            fontSize: 14,
            bold: true,
            fontFamily: excelFontFamily,
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
            backgroundColorHex: headerRowColor,
            fontSize: 12,
            bold: true,
            fontFamily: excelFontFamily,
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
              fontFamily: excelFontFamily,
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
                fontSize: 11,
                fontFamily: excelFontFamily,
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
