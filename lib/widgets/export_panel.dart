import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/providers/log_provider.dart';
import 'package:openlogtool/providers/session_provider.dart';
import 'package:openlogtool/providers/settings_provider.dart';
import 'package:openlogtool/models/export_settings.dart';
import 'package:openlogtool/services/export_service.dart';
import 'package:openlogtool/utils/app_snack_bar.dart';
import 'package:openlogtool/widgets/hsv_color_painter.dart';
import 'package:openlogtool/config/app_config.dart';

class ExportPanel extends StatefulWidget {
  const ExportPanel({super.key});

  @override
  State<ExportPanel> createState() => _ExportPanelState();
}

class _ExportPanelState extends State<ExportPanel> {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWideScreen = constraints.maxWidth > 700;
        final isNarrow = constraints.maxWidth < 400;
        final cardPadding = isNarrow ? 16.0 : 20.0;
        final sectionSpacing = isNarrow ? 16.0 : 20.0;

        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: isNarrow ? 12 : 16,
            vertical: isNarrow ? 8 : 12,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '数据导入导出',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              SizedBox(height: sectionSpacing),
              if (isWideScreen)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _buildQuickActionsCard(context, cardPadding),
                    ),
                    SizedBox(width: sectionSpacing),
                    Expanded(
                      child: _buildExcelSettingsCard(context, cardPadding),
                    ),
                  ],
                )
              else ...[
                _buildQuickActionsCard(context, cardPadding),
                SizedBox(height: sectionSpacing),
                _buildExcelSettingsCard(context, cardPadding),
              ],
              SizedBox(height: sectionSpacing),
              _buildFormatInfoCard(context, cardPadding),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuickActionsCard(BuildContext context, double cardPadding) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side:
            BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(128)),
      ),
      child: Padding(
        padding: EdgeInsets.all(cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.swap_horiz,
                    color: theme.colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  '导入 / 导出',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '支持 JSON（完整数据）和 Excel（可视化表格）两种格式。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(height: cardPadding),

            // Export section
            _buildActionGroup(
              context,
              title: '导出数据',
              icon: Icons.file_download,
              description: '将当前会话中的点名记录导出为文件',
              children: [
                _buildActionButton(
                  context,
                  label: '导出 JSON',
                  icon: Icons.code,
                  color: theme.colorScheme.primary,
                  onPressed: () => _exportJSON(context),
                ),
                const SizedBox(width: 12),
                _buildActionButton(
                  context,
                  label: '导出 Excel',
                  icon: Icons.table_chart,
                  color: theme.colorScheme.secondary,
                  onPressed: () => _exportExcel(context),
                ),
              ],
            ),
            SizedBox(height: cardPadding),

            // Import section
            _buildActionGroup(
              context,
              title: '导入数据',
              icon: Icons.file_upload,
              description: '从文件导入点名记录到当前会话',
              children: [
                _buildActionButton(
                  context,
                  label: '导入 JSON',
                  icon: Icons.code,
                  color: theme.colorScheme.tertiary,
                  onPressed: () => _importJSON(context),
                ),
                const SizedBox(width: 12),
                _buildActionButton(
                  context,
                  label: '导入 Excel',
                  icon: Icons.table_chart,
                  color: theme.colorScheme.outline,
                  onPressed: () => _importExcel(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionGroup(
    BuildContext context, {
    required String title,
    required IconData icon,
    required String description,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(title,
                style: theme.textTheme.bodyLarge
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 2),
        Padding(
          padding: const EdgeInsets.only(left: 22),
          child: Text(
            description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: children,
        ),
      ],
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        foregroundColor:
            color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
        backgroundColor: color,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildExcelSettingsCard(BuildContext context, double cardPadding) {
    final theme = Theme.of(context);
    final settingsProvider = Provider.of<SettingsProvider>(context);
    final settings = settingsProvider.exportSettings;
    final currentSessionTitle =
        Provider.of<SessionProvider>(context).currentSession?.title.trim();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side:
            BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(128)),
      ),
      child: Padding(
        padding: EdgeInsets.all(cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.settings,
                    color: theme.colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Excel 导出设置',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _showExportSettingsDialog(context),
                  icon: const Icon(Icons.open_in_full, size: 16),
                  label: const Text('高级设置'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '预览并快速调整最常用的导出选项，完整选项请进入高级设置。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(height: cardPadding),
            _buildSettingRow(
              context,
              label: '文件名模板',
              value: settings.fileNameTemplate,
              icon: Icons.insert_drive_file,
            ),
            const Divider(height: 24),
            _buildSettingRow(
              context,
              label: 'Excel 抬头',
              value: settings.useSessionTitleAsHeader
                  ? (currentSessionTitle?.isNotEmpty == true
                      ? currentSessionTitle!
                      : settings.headerText)
                  : settings.headerText,
              icon: Icons.title,
            ),
            const Divider(height: 24),
            _buildSettingRow(
              context,
              label: '导出路径',
              value:
                  settings.exportPath.isEmpty ? '默认下载文件夹' : settings.exportPath,
              icon: Icons.folder,
            ),
            const Divider(height: 24),
            Row(
              children: [
                _buildColorChip(
                    context, '抬头背景', settings.headerBackgroundColor),
                const SizedBox(width: 12),
                _buildColorChip(
                    context, '表头背景', settings.headerRowBackgroundColor),
                const SizedBox(width: 12),
                _buildColorChip(
                    context, '主控栏', settings.controllerBackgroundColor),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildToggleChip(
                    context,
                    label: '交替行',
                    value: settings.useAlternateColors,
                    onChanged: (v) {
                      final updated = settings.copyWith(useAlternateColors: v);
                      settingsProvider.updateExportSettings(updated);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingRow(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
  }) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: theme.textTheme.bodyMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildColorChip(BuildContext context, String label, Color color) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 40,
          height: 24,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
        ),
      ],
    );
  }

  Widget _buildToggleChip(
    BuildContext context, {
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
                value: value,
                onChanged: onChanged,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
            const SizedBox(width: 4),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormatInfoCard(BuildContext context, double cardPadding) {
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.all(cardPadding),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: theme.colorScheme.outlineVariant.withAlpha(128)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline,
                  size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                '文件格式说明',
                style: theme.textTheme.bodyLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '• JSON：标准 JSON 数组，包含所有字段数据，适合备份与跨应用迁移。\n'
            '• Excel：使用 .xlsx 格式，包含分组主控栏、颜色样式和底部信息，适合分享与打印。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  void _showExportSettingsDialog(BuildContext context) {
    final settingsProvider =
        Provider.of<SettingsProvider>(context, listen: false);
    ExportSettings settings =
        ExportSettings.fromJson(settingsProvider.exportSettings.toJson());

    final exportPathController =
        TextEditingController(text: settings.exportPath);
    final fileNameController =
        TextEditingController(text: settings.fileNameTemplate);
    final headerTextController =
        TextEditingController(text: settings.headerText);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          const dialogFont = TextStyle(fontSize: 14);

          return AlertDialog(
            title: const Text('Excel 导出设置', style: dialogFont),
            contentPadding: EdgeInsets.zero,
            content: SizedBox(
              width: 520,
              height: 620,
              child: DefaultTabController(
                length: 3,
                child: Column(
                  children: [
                    const TabBar(
                      tabs: [
                        Tab(icon: Icon(Icons.folder_outlined), text: '文件'),
                        Tab(icon: Icon(Icons.palette_outlined), text: '样式'),
                        Tab(icon: Icon(Icons.help_outline), text: '模板'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _buildFileSettingsTab(
                            context,
                            settings,
                            exportPathController,
                            fileNameController,
                            headerTextController,
                            setState,
                          ),
                          _buildStyleSettingsTab(context, settings, setState),
                          _buildTemplateHelpTab(context),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  exportPathController.dispose();
                  fileNameController.dispose();
                  headerTextController.dispose();
                  Navigator.pop(context);
                },
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () {
                  settings.exportPath = exportPathController.text;
                  settings.fileNameTemplate = fileNameController.text;
                  settings.headerText = headerTextController.text;
                  settingsProvider.updateExportSettings(settings);
                  exportPathController.dispose();
                  fileNameController.dispose();
                  headerTextController.dispose();
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

  Widget _buildFileSettingsTab(
    BuildContext context,
    ExportSettings settings,
    TextEditingController exportPathController,
    TextEditingController fileNameController,
    TextEditingController headerTextController,
    StateSetter setState,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTextFieldGroup(
            context,
            label: '导出路径',
            controller: exportPathController,
            hintText: '默认使用下载文件夹',
            readOnly: true,
            helperText: '留空则自动使用系统下载目录',
            trailing: FilledButton(
              onPressed: () async {
                final result = await FilePicker.platform.getDirectoryPath();
                if (result != null) {
                  exportPathController.text = result;
                  settings.exportPath = result;
                  setState(() {});
                }
              },
              child: const Text('选择'),
            ),
          ),
          const SizedBox(height: 20),
          _buildTextFieldGroup(
            context,
            label: '文件名模板',
            controller: fileNameController,
            hintText: '如：点名记录_{yyyy}-{MM}-{dd}',
            helperText: '使用模板变量自动生成文件名',
          ),
          const SizedBox(height: 20),
          _buildSwitchTile(
            context,
            title: context.l10n.excelUseSessionTitleAsHeader,
            subtitle: context.l10n.excelUseSessionTitleAsHeaderHint,
            value: settings.useSessionTitleAsHeader,
            onChanged: (value) {
              setState(() => settings.useSessionTitleAsHeader = value);
            },
          ),
          const SizedBox(height: 20),
          _buildTextFieldGroup(
            context,
            label: 'Excel 抬头文字',
            controller: headerTextController,
            hintText: '如：{yyyy}-{MM}-{dd}日点名记录',
            helperText: '支持模板变量',
          ),
        ],
      ),
    );
  }

  Widget _buildTextFieldGroup(
    BuildContext context, {
    required String label,
    required TextEditingController controller,
    String? hintText,
    String? helperText,
    bool readOnly = false,
    Widget? trailing,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                readOnly: readOnly,
                decoration: InputDecoration(
                  hintText: hintText,
                  helperText: helperText,
                  border: const OutlineInputBorder(),
                  suffixIcon: controller.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            controller.text = '';
                            setState(() {});
                          },
                        )
                      : null,
                ),
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing,
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildStyleSettingsTab(
      BuildContext context, ExportSettings settings, StateSetter setState) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
            (color) =>
                setState(() => settings.headerRowBackgroundColor = color),
            settings.fontFamily,
          ),
          const SizedBox(height: 16),
          _buildColorSetting(
            context,
            '主控栏背景色',
            settings.controllerBackgroundColor,
            (color) =>
                setState(() => settings.controllerBackgroundColor = color),
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
          const SizedBox(height: 20),
          _buildSwitchTile(
            context,
            title: '双色交替',
            subtitle: '启用交替行颜色',
            value: settings.useAlternateColors,
            onChanged: (value) =>
                setState(() => settings.useAlternateColors = value),
          ),
          _buildSwitchTile(
            context,
            title: '底部信息',
            subtitle: '在表格底部显示导出信息',
            value: settings.showFooter,
            onChanged: (value) => setState(() => settings.showFooter = value),
          ),
          const SizedBox(height: 16),
          _buildFontDropdown(context, settings, setState),
          const SizedBox(height: 16),
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
    );
  }

  Widget _buildSwitchTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 14)),
              Text(subtitle,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }

  Widget _buildFontDropdown(
      BuildContext context, ExportSettings settings, StateSetter setState) {
    final availableFonts =
        Provider.of<SettingsProvider>(context, listen: false).availableFonts;
    final normalizedFamily = AppConfig.normalizeFontFamily(settings.fontFamily);
    final initialValue =
        normalizedFamily.isEmpty ? 'SarasaGothicSC' : normalizedFamily;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('表格字体', style: TextStyle(fontSize: 14)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: initialValue,
          isExpanded: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          items: [
            const DropdownMenuItem(
                value: '',
                child: Text('系统默认', overflow: TextOverflow.ellipsis)),
            ...availableFonts.map((font) => DropdownMenuItem(
                  value: font,
                  child: Text(
                    font == 'SarasaGothicSC' ? '$font (内置)' : font,
                    overflow: TextOverflow.ellipsis,
                  ),
                )),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() => settings.fontFamily = value);
            }
          },
        ),
      ],
    );
  }

  Widget _buildTemplateHelpTab(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '模板变量说明',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _buildTemplateHelpItem(context, '{yyyy}', '四位年份，如：2024'),
          _buildTemplateHelpItem(context, '{MM}', '两位月份，如：01, 12'),
          _buildTemplateHelpItem(context, '{dd}', '两位日期，如：01, 31'),
          _buildTemplateHelpItem(context, '{HH}', '两位小时（24h），如：14'),
          _buildTemplateHelpItem(context, '{mm}', '两位分钟，如：30'),
          _buildTemplateHelpItem(context, '{ss}', '两位秒数，如：45'),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),
          Text(
            '使用示例',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _buildExampleItem(
              context, '文件名：点名记录_{yyyy}-{MM}-{dd}', '点名记录_2024-03-28.xlsx'),
          _buildExampleItem(context, '文件名：通联_{yyyy}-{MM}-{dd}_{HH}{mm}{ss}',
              '通联_2024-03-28_143045.xlsx'),
          _buildExampleItem(
              context, '抬头：{yyyy}年{MM}月{dd}日点名记录', '2024年03月28日点名记录'),
          const SizedBox(height: 16),
          _buildInfoBox(
            context,
            '提示：使用模板变量可以让文件名和抬头自动包含当前日期时间，方便文件管理。',
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBox(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withAlpha(128),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: theme.colorScheme.primary, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 12)),
          ),
        ],
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

  Widget _buildTemplateHelpItem(
      BuildContext context, String variable, String description) {
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

  Widget _buildExampleItem(
      BuildContext context, String template, String result) {
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
              Icon(Icons.arrow_forward,
                  size: 14, color: theme.colorScheme.primary),
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
                        border:
                            Border.all(color: Colors.grey.shade400, width: 1),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: GestureDetector(
                          onPanStart: (details) {
                            _updateHsvFromTap(
                                details.localPosition,
                                const Size(280, 150),
                                hsvColor.hue,
                                setState, (newHsv) {
                              hsvColor = newHsv;
                              currentColor = hsvColor.toColor();
                            });
                          },
                          onPanUpdate: (details) {
                            _updateHsvFromTap(
                                details.localPosition,
                                const Size(280, 150),
                                hsvColor.hue,
                                setState, (newHsv) {
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
                            border: Border.all(
                                color: Colors.grey.shade400, width: 2),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'HEX: #${currentColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
                            style: TextStyle(
                                fontSize: 14,
                                fontFamily:
                                    fontFamily.isEmpty ? null : fontFamily),
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
                                  thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 10),
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
                            hsvColor =
                                HSVColor.fromColor(const Color(0xFF2196F3));
                            currentColor = hsvColor.toColor();
                          });
                        }),
                        _buildQuickColorButton(const Color(0xFF4CAF50), () {
                          setState(() {
                            hsvColor =
                                HSVColor.fromColor(const Color(0xFF4CAF50));
                            currentColor = hsvColor.toColor();
                          });
                        }),
                        _buildQuickColorButton(const Color(0xFFF44336), () {
                          setState(() {
                            hsvColor =
                                HSVColor.fromColor(const Color(0xFFF44336));
                            currentColor = hsvColor.toColor();
                          });
                        }),
                        _buildQuickColorButton(const Color(0xFFFF9800), () {
                          setState(() {
                            hsvColor =
                                HSVColor.fromColor(const Color(0xFFFF9800));
                            currentColor = hsvColor.toColor();
                          });
                        }),
                        _buildQuickColorButton(const Color(0xFF9C27B0), () {
                          setState(() {
                            hsvColor =
                                HSVColor.fromColor(const Color(0xFF9C27B0));
                            currentColor = hsvColor.toColor();
                          });
                        }),
                        _buildQuickColorButton(const Color(0xFF607D8B), () {
                          setState(() {
                            hsvColor =
                                HSVColor.fromColor(const Color(0xFF607D8B));
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

  void _updateHsvFromTap(Offset position, Size size, double hue,
      StateSetter setState, Function(HSVColor) onUpdate) {
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
    final settingsProvider =
        Provider.of<SettingsProvider>(context, listen: false);
    final settings = settingsProvider.exportSettings;
    final logs = logProvider.logs;

    if (logs.isEmpty) {
      _showSnackBar('没有数据可以导出');
      return;
    }

    try {
      final jsonBytes = ExportService.generateJsonBytes(logs);
      final now = DateTime.now();
      String filename =
          ExportService.generateFileName(settings.fileNameTemplate, now);
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
        _showSnackBar('无法访问下载目录');
        return;
      }

      if (saveResult.usedSaf) {
        _showSnackBar('JSON 导出成功，已通过系统文件选择器保存');
      } else {
        _showSuccessDialog(
          'JSON 导出成功',
          '文件已保存到:\n${saveResult.path}',
          saveResult.path!,
        );
      }
    } catch (e) {
      _showSnackBar('导出失败: $e');
    }
  }

  Future<void> _exportExcel(BuildContext context) async {
    final logProvider = Provider.of<LogProvider>(context, listen: false);
    final settingsProvider =
        Provider.of<SettingsProvider>(context, listen: false);
    final sessionProvider =
        Provider.of<SessionProvider>(context, listen: false);
    final settings = settingsProvider.exportSettings;
    final logs = logProvider.logs;

    if (logs.isEmpty) {
      _showSnackBar('没有数据可以导出');
      return;
    }

    try {
      final now = DateTime.now();
      final bytes = ExportService.generateExcelBytes(
        logs,
        settings,
        now,
        sessionTitle: sessionProvider.currentSession?.title,
      );
      if (bytes == null) {
        _showSnackBar('导出失败: 无法生成 Excel 文件');
        return;
      }

      String filename =
          ExportService.generateFileName(settings.fileNameTemplate, now);
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
        _showSnackBar('无法访问下载目录');
        return;
      }

      if (saveResult.usedSaf) {
        _showSnackBar('Excel 导出成功，已通过系统文件选择器保存');
      } else {
        _showSuccessDialog(
          'Excel 导出成功',
          '文件已保存到:\n${saveResult.path}',
          saveResult.path!,
        );
      }
    } catch (e) {
      _showSnackBar('导出失败: $e');
    }
  }

  Future<void> _importJSON(BuildContext context) async {
    final logProvider = Provider.of<LogProvider>(context, listen: false);
    final sessionProvider =
        Provider.of<SessionProvider>(context, listen: false);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result == null || result.files.isEmpty) return;

      final file = File(result.files.single.path!);
      final content = await file.readAsString();

      final importResult = parseJsonImport(content);

      await logProvider.importLogs(importResult.logs,
          sessionId: sessionProvider.currentSessionId);
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('导入成功: ${importResult.logs.length} 条记录')),
      );
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('导入失败: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _importExcel(BuildContext context) async {
    _showSnackBar('Excel 导入功能开发中');
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    context.showLoggedSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showSuccessDialog(String title, String content, String path) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(content),
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
                    messenger.showSnackBar(
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
