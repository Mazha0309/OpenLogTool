import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:openlogtool/providers/settings_provider.dart';
import 'package:openlogtool/providers/app_info_provider.dart';
import 'package:openlogtool/providers/snackbar_log_provider.dart';
import 'package:openlogtool/providers/server_provider.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/src/bridge/rust_api.dart';
import 'package:openlogtool/utils/app_snack_bar.dart';
import 'package:openlogtool/utils/server_connection_error.dart';
import 'package:openlogtool/widgets/settings/theme_settings.dart';
import 'package:openlogtool/widgets/settings/layout_settings.dart';
import 'package:openlogtool/widgets/settings/controller_display_settings.dart';
import 'package:openlogtool/widgets/settings/data_operations.dart';
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

          Consumer<ServerProvider>(
            builder: (context, serverProvider, _) {
              return Card(
                child: Padding(
                  padding: EdgeInsets.all(cardPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.cloud,
                              size: 18,
                              color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            '服务器设置',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        initialValue: serverProvider.serverUrl,
                        decoration: const InputDecoration(
                          labelText: '服务器地址',
                          hintText: 'http://your-server:3000',
                          border: OutlineInputBorder(),
                          isDense: true,
                          prefixIcon: Icon(Icons.link, size: 18),
                        ),
                        onChanged: (value) =>
                            serverProvider.setServerUrl(value),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: serverProvider.isBusy
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.wifi_tethering, size: 16),
                          label: const Text('保存并检测服务器'),
                          onPressed: serverProvider.isBusy
                              ? null
                              : () async {
                                  try {
                                    final info =
                                        await serverProvider.checkServer();
                                    if (context.mounted) {
                                      context.showLoggedSnackBar(
                                        SnackBar(
                                          content: Text(
                                            '连接成功 · 协议 v${info.protocolMin}-${info.protocolMax}',
                                          ),
                                        ),
                                      );
                                    }
                                  } catch (error) {
                                    if (context.mounted) {
                                      context.showLoggedSnackBar(
                                        SnackBar(
                                          content: Text(
                                            localizedServerConnectionError(
                                              l10n: context.l10n,
                                              serverUrl:
                                                  serverProvider.serverUrl,
                                              error: error,
                                            ),
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                },
                        ),
                      ),
                      if (serverProvider.serverInfo != null) ...[
                        const SizedBox(height: 8),
                        SelectableText(
                          '实例 ${serverProvider.serverInfo!.serverInstanceId}\n'
                          '能力 ${serverProvider.serverInfo!.features.join(', ')}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 12),
                      if (!serverProvider.isLoggedIn) ...[
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.login, size: 16),
                                label: const Text('登录'),
                                onPressed: () =>
                                    _showLoginDialog(context, serverProvider),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.person_add, size: 16),
                                label: const Text('注册'),
                                onPressed: () => _showRegisterDialog(
                                    context, serverProvider),
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        Row(
                          children: [
                            Icon(Icons.person,
                                size: 16,
                                color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 6),
                            Text(
                              serverProvider.username ?? '',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const Spacer(),
                            TextButton.icon(
                              icon: const Icon(Icons.logout, size: 16),
                              label: const Text('退出'),
                              onPressed: () async {
                                try {
                                  await serverProvider.logout();
                                } catch (error) {
                                  if (context.mounted) {
                                    context.showLoggedSnackBar(
                                      SnackBar(content: Text('退出失败: $error')),
                                    );
                                  }
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),

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

          // 操作按钮
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => _showResetConfirmation(context),
                  style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                      foregroundColor: Colors.white),
                  child: const Text('恢复默认设置'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  child: const Text('关于应用'),
                  onPressed: () => _showAboutDialog(context),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 版本信息
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '应用信息',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'OpenLogTool v${appInfoProvider.fullVersion}\n'
                  '© 2026 BG5CRL',
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
      builder: (context) => AlertDialog(
        title: const Text('关于 OpenLogTool'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '版本: ${appInfoProvider.fullVersion}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                '一个专为业余无线电爱好者设计的点名记录工具。'
                '支持快速记录通联信息，管理设备、天线、呼号词库，'
                '以及数据导入导出功能。',
              ),
              const SizedBox(height: 12),
              const Text(
                '主要功能:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Text('• 快速添加点名记录'),
              const Text('• 设备、天线、呼号、QTH 词库管理'),
              const Text('• 数据导入导出 (JSON, Excel)'),
              const Text('• 暗色/亮色主题切换'),
              const Text('• 自定义主题颜色'),
              const Text('• 一键清除数据库'),
              const SizedBox(height: 12),
              const Text(
                '© 2026 Mazha0309.',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            child: const Text('关闭'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
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

  void _showLoginDialog(BuildContext context, ServerProvider serverProvider) {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('登录'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: usernameController,
              decoration: const InputDecoration(
                  labelText: '用户名',
                  border: OutlineInputBorder(),
                  isDense: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passwordController,
              decoration: const InputDecoration(
                  labelText: '密码', border: OutlineInputBorder(), isDense: true),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              try {
                await serverProvider.login(
                    usernameController.text, passwordController.text);
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                }
              } catch (e) {
                if (context.mounted) {
                  scaffoldMessenger
                      .showSnackBar(SnackBar(content: Text('登录失败: $e')));
                }
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                }
              }
            },
            child: const Text('登录'),
          ),
        ],
      ),
    );
  }

  void _showRegisterDialog(
      BuildContext context, ServerProvider serverProvider) {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('注册'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: usernameController,
              decoration: const InputDecoration(
                  labelText: '用户名',
                  border: OutlineInputBorder(),
                  isDense: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passwordController,
              decoration: const InputDecoration(
                  labelText: '密码', border: OutlineInputBorder(), isDense: true),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              try {
                await serverProvider.register(
                    usernameController.text, passwordController.text);
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                }
              } catch (e) {
                if (context.mounted) {
                  scaffoldMessenger
                      .showSnackBar(SnackBar(content: Text('注册失败: $e')));
                }
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                }
              }
            },
            child: const Text('注册'),
          ),
        ],
      ),
    );
  }
}
