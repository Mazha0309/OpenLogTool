import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/providers/settings_provider.dart';
import 'package:openlogtool/providers/app_info_provider.dart';
import 'package:openlogtool/providers/snackbar_log_provider.dart';
import 'package:openlogtool/src/bridge/rust_api.dart';
import 'package:openlogtool/utils/app_snack_bar.dart';
import 'package:openlogtool/widgets/settings/theme_settings.dart';
import 'package:openlogtool/widgets/settings/layout_settings.dart';
import 'package:openlogtool/widgets/settings/controller_display_settings.dart';
import 'package:openlogtool/widgets/settings/data_operations.dart';
import 'package:openlogtool/widgets/settings/server_account_settings.dart';
import 'package:openlogtool/widgets/about_app_dialog.dart';
import 'package:openlogtool/widgets/font_picker_dialog.dart';
import 'package:openlogtool/widgets/theme_color_picker_dialog.dart';

class SettingsPanel extends StatelessWidget {
  const SettingsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final appInfoProvider = Provider.of<AppInfoProvider>(context);
    return LayoutBuilder(builder: (context, constraints) {
      final isNarrow = constraints.maxWidth < 860;
      final cardPadding = constraints.maxWidth < 600 ? 12.0 : 16.0;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '应用设置',
            style: TextStyle(
              fontSize: isNarrow ? 18 : 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: isNarrow ? 16 : 24),
          if (isNarrow) ...[
            ThemeSettings(
              isNarrow: constraints.maxWidth < 600,
              cardPadding: cardPadding,
              onPickColor: () => _showColorPicker(context),
              onPickFont: () => _showFontPicker(context),
            ),
            const SizedBox(height: 16),
            LayoutSettings(
              isNarrow: constraints.maxWidth < 600,
              cardPadding: cardPadding,
            ),
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ThemeSettings(
                    isNarrow: false,
                    cardPadding: cardPadding,
                    onPickColor: () => _showColorPicker(context),
                    onPickFont: () => _showFontPicker(context),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: LayoutSettings(
                    isNarrow: false,
                    cardPadding: cardPadding,
                  ),
                ),
              ],
            ),
          const SizedBox(height: 16),
          ControllerDisplaySettings(cardPadding: cardPadding),
          const SizedBox(height: 16),
          ServerAccountSettings(cardPadding: cardPadding),
          const SizedBox(height: 16),
          DataOperations(
            isNarrow: isNarrow,
            cardPadding: cardPadding,
            onViewDatabaseLog: () => _showDatabaseLogDialog(context),
            onExportDatabase: () => _exportDatabase(context),
            onImportDatabase: () => _showImportDatabaseDialog(context),
            onViewSnackbarLog: () => _showSnackbarLogDialog(context),
            onClearAllData: () => _showClearDataConfirmation(context),
          ),
          const SizedBox(height: 16),
          Card(
            margin: EdgeInsets.zero,
            elevation: 0,
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: ListTile(
              key: const Key('about-app-entry'),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: cardPadding, vertical: 6),
              leading: Icon(
                Icons.info_outline,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: Text(
                context.l10n.aboutAppTitle,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                '${context.l10n.aboutAppTagline}\n'
                '${appInfoProvider.fullVersion} · '
                '${context.l10n.aboutLicenseName}',
              ),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showAboutDialog(context),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _showResetConfirmation(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
                side: BorderSide(color: Theme.of(context).colorScheme.error),
              ),
              icon: const Icon(Icons.restore_outlined),
              label: Text(context.l10n.restoreDefaultSettings),
            ),
          ),
        ],
      );
    });
  }

  void _showSnackbarLogDialog(BuildContext context) {
    final entries =
        Provider.of<SnackbarLogProvider>(context, listen: false).entries;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('弹窗日志'),
        content: SizedBox(
          width: double.maxFinite,
          child: entries.isEmpty
              ? const Text('当前没有弹窗日志')
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: entries.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 16),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final time =
                        '${entry.createdAt.hour.toString().padLeft(2, '0')}:${entry.createdAt.minute.toString().padLeft(2, '0')}:${entry.createdAt.second.toString().padLeft(2, '0')}';
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText(
                          entry.message,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$time · ${entry.type} · ${entry.source}',
                          style:
                              const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _showColorPicker(BuildContext context) async {
    final settingsProvider = context.read<SettingsProvider>();
    final selectedColor = await showDialog<Color>(
      context: context,
      builder: (_) => ThemeColorPickerDialog(
        initialColor: settingsProvider.themeColor,
      ),
    );
    if (selectedColor != null) {
      await settingsProvider.setThemeColor(selectedColor);
    }
  }

  void _showResetConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复默认设置'),
        content: const Text('确定要恢复所有设置为默认值吗？'),
        actions: [
          FilledButton(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(context),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Colors.white),
            onPressed: () {
              Provider.of<SettingsProvider>(context, listen: false)
                  .resetToDefaults();
              Navigator.pop(context);
              context.showLoggedSnackBar(
                const SnackBar(
                  content: Text('已恢复默认设置'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: const Text('确认恢复'),
          ),
        ],
      ),
    );
  }

  void _showClearDataConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空所有数据'),
        content: const Text(
            '⚠️ 警告：此操作不可恢复！\n\n将删除所有点名记录数据，包括：\n• 所有通联记录\n• 呼号、设备、天线词库\n• QTH 历史记录\n\n确定要继续吗？'),
        actions: [
          FilledButton(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(context),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(context);
              try {
                await RustApi.clearAllData();
                if (context.mounted) {
                  context.showLoggedSnackBar(
                    const SnackBar(
                      content: Text('已清空所有数据，请重启应用以重新加载。'),
                      duration: Duration(seconds: 3),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  context.showLoggedSnackBar(
                    SnackBar(
                      content: Text('清空失败: $e'),
                      duration: const Duration(seconds: 5),
                    ),
                  );
                }
              }
            },
            child: const Text('确认清空'),
          ),
        ],
      ),
    );
  }

  void _exportDatabase(BuildContext context) async {
    try {
      final jsonData = await RustApi.exportDatabase();

      final now = DateTime.now();
      final fileName =
          'openlogtool_backup_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}.json';

      final result = await FilePicker.platform.saveFile(
        dialogTitle: '保存数据库备份',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: utf8.encode(jsonData),
      );

      if (result != null) {
        if (!Platform.isAndroid) {
          final file = File(result);
          await file.writeAsString(jsonData);
        }

        if (context.mounted) {
          context.showLoggedSnackBar(
            const SnackBar(
              content: Text('数据库已导出！'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        context.showLoggedSnackBar(
          SnackBar(
            content: Text('导出失败: $e'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  void _showImportDatabaseDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('导入数据库'),
        content:
            const Text('⚠️ 警告：导入将覆盖所有现有数据！\n\n此操作不可恢复，建议先导出当前数据库。\n\n确定要继续吗？'),
        actions: [
          FilledButton(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(dialogContext),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(dialogContext);
              await _importDatabase(context);
            },
            child: const Text('继续导入'),
          ),
        ],
      ),
    );
  }

  Future<void> _importDatabase(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: '选择数据库备份文件',
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );

      if (result != null && result.files.single.bytes != null) {
        final jsonData = utf8.decode(result.files.single.bytes!);
        await RustApi.importDatabase(jsonData: jsonData);

        if (context.mounted) {
          context.showLoggedSnackBar(
            const SnackBar(
              content: Text('数据库导入成功！请重启应用以重新加载数据。'),
              duration: Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        context.showLoggedSnackBar(
          SnackBar(
            content: Text('导入失败: $e'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  void _showDatabaseLogDialog(BuildContext context) async {
    final status = await _buildDatabaseStatus(context);
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('数据库状态'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              status,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          FilledButton(
            child: const Text('关闭'),
            onPressed: () => Navigator.pop(dialogContext),
          ),
        ],
      ),
    );
  }

  Future<String> _buildDatabaseStatus(BuildContext ctx) async {
    try {
      return await RustApi.getDatabaseStatus();
    } catch (e) {
      return '读取数据库状态失败: $e';
    }
  }

  void _showAboutDialog(BuildContext context) {
    final appInfoProvider =
        Provider.of<AppInfoProvider>(context, listen: false);

    showDialog(
      context: context,
      builder: (dialogContext) => AboutAppDialog(
        appName: appInfoProvider.appName,
        fullVersion: appInfoProvider.fullVersion,
        buildNumber: appInfoProvider.buildNumber,
        commitHash: appInfoProvider.commitHash,
      ),
    );
  }

  Future<void> _showFontPicker(BuildContext context) async {
    final settingsProvider = context.read<SettingsProvider>();
    final result = await showDialog<FontPickerResult>(
      context: context,
      // A global font change rebuilds the whole app. Keeping this route
      // transition-free ensures the picker is fully gone before that rebuild
      // starts, instead of competing with the dialog's exit animation.
      animationStyle: AnimationStyle.noAnimation,
      builder: (_) => FontPickerDialog(
        availableFonts: settingsProvider.availableFonts,
        currentFont: settingsProvider.fontFamily,
      ),
    );
    if (result == null || !context.mounted) return;
    await WidgetsBinding.instance.endOfFrame;
    await settingsProvider.setFontFamily(result.fontFamily);
  }
}
