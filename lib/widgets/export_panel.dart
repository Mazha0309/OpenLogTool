import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:openlogtool/providers/log_provider.dart';
import 'package:openlogtool/providers/session_provider.dart';
import 'package:openlogtool/providers/settings_provider.dart';
import 'package:openlogtool/models/export_settings.dart';
import 'package:openlogtool/database/database_helper.dart';
import 'package:openlogtool/services/export_service.dart';
import 'package:openlogtool/utils/app_snack_bar.dart';
import 'package:openlogtool/widgets/hsv_color_painter.dart';

class ExportPanel extends StatelessWidget {
  const ExportPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWideScreen = constraints.maxWidth > 600;
        final isNarrow = constraints.maxWidth < 400;
        final cardPadding = isNarrow ? 12.0 : 16.0;
        final screenPadding = isNarrow ? 8.0 : 16.0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(left: isNarrow ? 4 : 0),
              child: Text(
                '数据导入导出',
                style: TextStyle(
                  fontSize: isNarrow ? 18 : 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            SizedBox(height: isNarrow ? 16 : 24),

            if (isWideScreen)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: screenPadding),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _buildExportCard(context, cardPadding)),
                    const SizedBox(width: 16),
                    Expanded(child: _buildImportCard(context, cardPadding)),
                  ],
                ),
              )
            else
              Padding(
                padding: EdgeInsets.symmetric(horizontal: screenPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildExportCard(context, cardPadding),
                    SizedBox(height: isNarrow ? 12 : 16),
                    _buildImportCard(context, cardPadding),
                  ],
                ),
              ),

            SizedBox(height: isNarrow ? 12 : 16),

            Padding(
              padding: EdgeInsets.symmetric(horizontal: screenPadding),
              child: Container(
                padding: EdgeInsets.all(cardPadding),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '文件格式说明',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: isNarrow ? 13 : 14,
                      ),
                    ),
                    SizedBox(height: isNarrow ? 6 : 8),
                    Text(
                      '• JSON: 标准JSON格式，包含所有记录数据\n'
                      '• Excel: 使用Excel格式，包含分组和样式',
                      style: TextStyle(
                        fontSize: isNarrow ? 12 : 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildExportCard(BuildContext context, double cardPadding) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
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
                FilledButton.icon(
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
                FilledButton.icon(
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

  Widget _buildImportCard(BuildContext context, double cardPadding) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
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
                FilledButton.icon(
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
                FilledButton.icon(
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
    // 创建设置的副本，避免直接修改原设置
    ExportSettings settings = ExportSettings.fromJson(settingsProvider.exportSettings.toJson());
    
    // 创建持久的文本控制器
    final exportPathController = TextEditingController(text: settings.exportPath);
    final fileNameController = TextEditingController(text: settings.fileNameTemplate);
    final headerTextController = TextEditingController(text: settings.headerText);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          const dialogFont = TextStyle(fontSize: 14);

          return AlertDialog(
            title: const Text('Excel导出设置', style: dialogFont),
            content: SizedBox(
              width: 500,
              height: 600,
              child: DefaultTabController(
                length: 3,
                child: Column(
                  children: [
                    const TabBar(
                      tabs: [
                        Tab(text: '文件设置'),
                        Tab(text: '样式设置'),
                        Tab(text: '模板说明'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          // 文件设置
                          SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 导出路径
                                const Text('导出路径', style: dialogFont),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: exportPathController,
                                        decoration: InputDecoration(
                                          hintText: '默认使用下载文件夹',
                                          border: const OutlineInputBorder(),
                                          suffixIcon: exportPathController.text.isNotEmpty
                                            ? IconButton(
                                                icon: const Icon(Icons.clear, size: 18),
                                                onPressed: () {
                                                  exportPathController.text = '';
                                                  settings.exportPath = '';
                                                  setState(() {});
                                                },
                                              )
                                            : null,
                                        ),
                                        readOnly: true,
                                        onTap: null,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    FilledButton(
                                      child: const Text('选择'),
                                      onPressed: () async {
                                        final result = await FilePicker.platform.getDirectoryPath();
                                        if (result != null) {
                                          exportPathController.text = result;
                                          settings.exportPath = result;
                                          setState(() {});
                                        }
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 24),

                                // 文件名模板
                                const Text('文件名模板', style: dialogFont),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: fileNameController,
                                  decoration: const InputDecoration(
                                    hintText: '如: 点名记录_{yyyy}-{MM}-{dd}',
                                    border: OutlineInputBorder(),
                                    helperText: '使用模板变量自动生成文件名',
                                  ),
                                  onChanged: (value) {
                                    settings.fileNameTemplate = value;
                                  },
                                ),
                                const SizedBox(height: 24),

                                // 抬头文字
                                const Text('Excel抬头文字', style: dialogFont),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: headerTextController,
                                  decoration: const InputDecoration(
                                    hintText: '如: {yyyy}-{MM}-{dd}日点名记录',
                                    border: OutlineInputBorder(),
                                    helperText: '支持模板变量',
                                  ),
                                  onChanged: (value) {
                                    settings.headerText = value;
                                  },
                                ),
                              ],
                            ),
                          ),

                          // 样式设置
                          SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 颜色设置
                                _buildColorSetting(
                                  context,
                                  '抬头背景色',
                                  settings.headerBackgroundColor,
                                  (color) => setState(() => settings.headerBackgroundColor = color),
                                  settings.fontFamily,
                                ),
                                const SizedBox(height: 16),

                                _buildColorSetting(
                                  context,
                                  '表头背景色',
                                  settings.headerRowBackgroundColor,
                                  (color) => setState(() => settings.headerRowBackgroundColor = color),
                                  settings.fontFamily,
                                ),
                                const SizedBox(height: 16),

                                _buildColorSetting(
                                  context,
                                  '主控栏背景色',
                                  settings.controllerBackgroundColor,
                                  (color) => setState(() => settings.controllerBackgroundColor = color),
                                  settings.fontFamily,
                                ),
                                const SizedBox(height: 16),

                                _buildColorSetting(
                                  context,
                                  '普通背景色',
                                  settings.tableBackgroundColor,
                                  (color) => setState(() => settings.tableBackgroundColor = color),
                                  settings.fontFamily,
                                ),

                                if (settings.useAlternateColors) ...[
                                  const SizedBox(height: 16),
                                  _buildColorSetting(
                                    context,
                                    '交替行颜色',
                                    settings.alternateRowColor,
                                    (color) => setState(() => settings.alternateRowColor = color),
                                    settings.fontFamily,
                                  ),
                                ],

                                const SizedBox(height: 16),

                                // 开关设置
                                Row(
                                  children: [
                                    const Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('双色交替', style: dialogFont),
                                          Text(
                                            '启用交替行颜色',
                                            style: TextStyle(fontSize: 12, color: Colors.grey),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Switch(
                                      value: settings.useAlternateColors,
                                      onChanged: (value) {
                                        setState(() => settings.useAlternateColors = value);
                                      },
                                    ),
                                  ],
                                ),

                                Row(
                                  children: [
                                    const Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('底部信息', style: dialogFont),
                                          Text(
                                            '在表格底部显示导出信息',
                                            style: TextStyle(fontSize: 12, color: Colors.grey),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Switch(
                                      value: settings.showFooter,
                                      onChanged: (value) {
                                        setState(() => settings.showFooter = value);
                                      },
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 16),

                                // 字体选择
                                const Text('表格字体', style: dialogFont),
                                const SizedBox(height: 8),
                                DropdownButton<String>(
                                  value: settings.fontFamily.isEmpty ? 'SarasaGothicSC' : settings.fontFamily,
                                  isExpanded: true,
                                  items: [
                                    // 系统默认选项
                                    const DropdownMenuItem(
                                      value: '',
                                      child: Text('系统默认'),
                                    ),
                                    // 可用字体列表
                                    ...Provider.of<SettingsProvider>(context, listen: false)
                                        .availableFonts
                                        .map((font) => DropdownMenuItem(
                                              value: font,
                                              child: Text(font == 'SarasaGothicSC' ? '$font (内置)' : font),
                                            )),
                                  ],
                                  onChanged: (value) {
                                    if (value != null) {
                                      setState(() => settings.fontFamily = value);
                                    }
                                  },
                                ),

                                const SizedBox(height: 16),

                                // 恢复默认颜色
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.restore, size: 18),
                                  label: const Text('恢复默认颜色'),
                                  onPressed: () {
                                    setState(() {
                                      settings.headerBackgroundColor = const Color(0xFF1E84D2);
                                      settings.headerRowBackgroundColor = const Color(0xFFCFE7FF);
                                      settings.controllerBackgroundColor = const Color(0xFFFFFFC3);
                                      settings.tableBackgroundColor = Colors.white;
                                      settings.alternateRowColor = const Color(0xFFC0E5F2);
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),

                          // 模板说明
                          SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '模板变量说明',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 16),

                                _buildTemplateHelpItem(context, '{yyyy}', '四位年份，如: 2024'),
                                _buildTemplateHelpItem(context, '{MM}', '两位月份，如: 01, 12'),
                                _buildTemplateHelpItem(context, '{dd}', '两位日期，如: 01, 31'),
                                _buildTemplateHelpItem(context, '{HH}', '两位小时(24h)，如: 14'),
                                _buildTemplateHelpItem(context, '{mm}', '两位分钟，如: 30'),
                                _buildTemplateHelpItem(context, '{ss}', '两位秒数，如: 45'),

                                const SizedBox(height: 16),
                                const Divider(),
                                const SizedBox(height: 16),

                                const Text(
                                  '使用示例',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),

                                _buildExampleItem(
                                  context,
                                  '文件名: 点名记录_{yyyy}-{MM}-{dd}',
                                  '点名记录_2024-03-28.xlsx',
                                ),
                                _buildExampleItem(
                                  context,
                                  '文件名: 通联_{yyyy}-{MM}-{dd}_{HH}{mm}{ss}',
                                  '通联_2024-03-28_143045.xlsx',
                                ),
                                _buildExampleItem(
                                  context,
                                  '抬头: {yyyy}年{MM}月{dd}日点名记录',
                                  '2024年03月28日点名记录',
                                ),

                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.primaryContainer.withAlpha(128),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.info_outline,
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                      const SizedBox(width: 8),
                                      const Expanded(
                                        child: Text(
                                          '提示：使用模板变量可以让文件名和抬头自动包含当前日期时间，方便文件管理。',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
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
                  // 从控制器获取最新值，确保所有更改都被保存
                  settings.exportPath = exportPathController.text;
                  settings.fileNameTemplate = fileNameController.text;
                  settings.headerText = headerTextController.text;
                  settingsProvider.updateExportSettings(settings);
                  Navigator.pop(context);
                  context.showLoggedSnackBar(
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

  Widget _buildColorSetting(
    BuildContext context,
    String label,
    Color color,
    Function(Color) onColorChanged,
    String fontFamily,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 100,
          child: Text(label, style: const TextStyle(fontSize: 14)),
        ),
        _buildColorButton(color, () async {
          final newColor = await _showColorPickerDialog(
            context,
            '选择$label',
            color,
            fontFamily,
          );
          if (newColor != null) {
            onColorChanged(newColor);
          }
        }),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
            style: TextStyle(
              fontSize: 12,
              fontFamily: fontFamily.isEmpty ? 'monospace' : fontFamily,
              color: Colors.grey,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTemplateHelpItem(BuildContext context, String variable, String description) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: theme.colorScheme.outline.withAlpha(128),
                width: 1,
              ),
            ),
            child: Text(
              variable,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              description,
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExampleItem(BuildContext context, String template, String result) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(180),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outline.withAlpha(100),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            template,
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurfaceVariant,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.arrow_forward, size: 14, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  result,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ],
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
                            painter: HsvSaturationValuePainter(
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
    final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    final settings = settingsProvider.exportSettings;
    final logs = logProvider.logs;

    if (logs.isEmpty) {
      _showSnackBar(context, '没有数据可以导出');
      return;
    }

    try {
      final jsonBytes = ExportService.generateJsonBytes(logs);
      final now = DateTime.now();
      String filename = ExportService.generateFileName(
          settings.fileNameTemplate, now);
      if (!filename.endsWith('.json')) {
        filename += '.json';
      }

      final saveResult = await ExportService.saveFile(
        configuredPath: settings.exportPath,
        filename: filename,
        bytes: jsonBytes,
        dialogTitle: '保存 JSON 导出文件',
        allowedExtensions: const ['json'],
      );

      if (saveResult.cancelled) return;
      if (saveResult.path == null) {
        _showSnackBar(context, '无法访问下载目录');
        return;
      }

      if (saveResult.usedSaf) {
        _showSnackBar(context, 'JSON导出成功，已通过系统文件选择器保存');
      } else {
        _showSuccessDialog(
            context, 'JSON导出成功', '文件已保存到:\n${saveResult.path}', saveResult.path!);
      }
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
      final now = DateTime.now();
      final bytes = ExportService.generateExcelBytes(logs, settings, now);
      if (bytes == null) {
        _showSnackBar(context, '导出失败: 无法生成Excel文件');
        return;
      }

      String filename = ExportService.generateFileName(
          settings.fileNameTemplate, now);
      if (!filename.endsWith('.xlsx')) {
        filename += '.xlsx';
      }

      final saveResult = await ExportService.saveFile(
        configuredPath: settings.exportPath,
        filename: filename,
        bytes: Uint8List.fromList(bytes),
        dialogTitle: '保存 Excel 导出文件',
        allowedExtensions: const ['xlsx'],
      );

      if (saveResult.cancelled) return;
      if (saveResult.path == null) {
        _showSnackBar(context, '无法访问下载目录');
        return;
      }

      if (saveResult.usedSaf) {
        _showSnackBar(context, 'Excel导出成功，已通过系统文件选择器保存');
      } else {
        _showSuccessDialog(
            context, 'Excel导出成功', '文件已保存到:\n${saveResult.path}', saveResult.path!);
      }
    } catch (e) {
      _showSnackBar(context, '导出失败: $e');
    }
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

      final logProvider = Provider.of<LogProvider>(context, listen: false);
      final sessionProvider = Provider.of<SessionProvider>(context, listen: false);
      final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);

      final importResult = parseJsonImport(
        content,
        recordCallsignQth: settingsProvider.importCallsignQthHistoryEnabled,
      );

      // Insert callsign-qth history records
      if (importResult.callsignQthPairs.isNotEmpty) {
        final db = DatabaseHelper();
        for (final pair in importResult.callsignQthPairs) {
          await db.addCallsignQthRecord(pair[0], pair[1]);
        }
      }

      logProvider.importLogs(importResult.logs, sessionId: sessionProvider.currentSessionId);
      _showSnackBar(context, '导入成功: ${importResult.logs.length} 条记录');
    } catch (e) {
      _showSnackBar(context, '导入失败: $e');
    }
  }

  Future<void> _importExcel(BuildContext context) async {
    _showSnackBar(context, 'Excel导入功能开发中');
  }

  void _showSnackBar(BuildContext context, String message) {
    context.showLoggedSnackBar(
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
                    Clipboard.setData(ClipboardData(text: path));
                    context.showLoggedSnackBar(
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
