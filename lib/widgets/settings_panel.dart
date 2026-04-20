import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:forui/forui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:openlogtool/providers/settings_provider.dart';
import 'package:openlogtool/providers/app_info_provider.dart';
import 'package:openlogtool/providers/log_provider.dart';
import 'package:openlogtool/providers/dictionary_provider.dart';
import 'package:openlogtool/providers/sync_provider.dart';
import 'package:openlogtool/database/database_helper.dart';

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
    canvas.drawRect(
        rect, Paint()..shader = saturationGradient.createShader(rect));

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
    final circleColor =
        HSVColor.fromAHSV(1.0, hue, saturation, value).toColor();

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

class SettingsPanel extends StatelessWidget {
  const SettingsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context);
    final appInfoProvider = Provider.of<AppInfoProvider>(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '应用设置',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 24),

        // 主题设置
        FCard(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '主题设置',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),

                // 主题色选择器
                Row(
                  children: [
                    const Text('主题颜色:'),
                    const Spacer(),
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: settingsProvider.themeColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FButton(
                      label: '选择颜色',
                      onPress: () => _showColorPicker(context),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // 暗色模式开关
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('暗色模式'),
                          SizedBox(height: 2),
                          Text(
                            '切换到暗色主题',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: settingsProvider.isDarkMode,
                      onChanged: (value) => settingsProvider.setDarkMode(value),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // 字体选择
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('字体'),
                          SizedBox(height: 2),
                          Text(
                            '选择应用字体',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    FButton(
                      label: settingsProvider.fontFamily ?? '系统默认',
                      onPress: () => _showFontPicker(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // 布局设置
        FCard(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '布局设置',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),

                // 宽屏布局开关
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('启用宽屏平行布局'),
                          SizedBox(height: 2),
                          Text(
                            '在窗口宽度足够时，将添加记录和已有记录并排显示',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: settingsProvider.wideLayoutEnabled,
                      onChanged: (value) =>
                          settingsProvider.setWideLayout(value),
                    ),
                  ],
                ),

                const Divider(),

                // 分页显示开关
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('分页显示记录'),
                          SizedBox(height: 2),
                          Text(
                            '每5条记录分为一页显示',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: settingsProvider.paginationEnabled,
                      onChanged: (value) =>
                          settingsProvider.setPaginationEnabled(value),
                    ),
                  ],
                ),

                const Divider(),

                // QTH联动开关
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('呼号-QTH联动'),
                          SizedBox(height: 2),
                          Text(
                            '自动关联呼号和QTH，输入呼号时显示历史QTH',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: settingsProvider.callSignQthLinkEnabled,
                      onChanged: (value) =>
                          settingsProvider.setCallSignQthLink(value),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // 服务器同步设置
        Consumer<SyncProvider>(
          builder: (context, syncProvider, _) {
            if (syncProvider.settings.syncEnabled && syncProvider.isLoggedIn) {
              WidgetsBinding.instance.addPostFrameCallback((_) async {
                final stillValid = await syncProvider.validateCurrentLogin();
                if (!stillValid && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('登录状态已失效，请重新登录')),
                  );
                }
              });
            }
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
                          '服务器同步',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Switch(
                          value: syncProvider.settings.syncEnabled,
                          onChanged: (value) =>
                              syncProvider.setSyncEnabled(value),
                        ),
                      ],
                    ),
                    if (syncProvider.settings.syncEnabled) ...[
                      const SizedBox(height: 12),
                      _ServerSettingsFields(syncProvider: syncProvider),
                      const SizedBox(height: 8),
                      if (!syncProvider.isLoggedIn) ...[
                        if (syncProvider.isLoggingIn)
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          FButton(
                            label: '子账号登录',
                            onPress: () async {
                              final result = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => _LoginDialog(),
                              );
                              if (result == true) {
                                final ok = await syncProvider.login(
                                  _LoginDialog.username ?? '',
                                  _LoginDialog.password ?? '',
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(ok
                                          ? '登录成功'
                                          : '登录失败: ${syncProvider.lastError ?? "未知错误"}'),
                                    ),
                                  );
                                }
                              }
                            },
                          ),
                      ] else ...[
                        Row(
                          children: [
                            const Icon(Icons.check_circle,
                                color: Colors.green, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              '已登录 (${syncProvider.settings.userId ?? ""})',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.green),
                            ),
                            const Spacer(),
                            FButton(
                              label: '退出登录',
                              style: FButtonStyle.destructive,
                              onPress: () async {
                                await syncProvider.logout();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('已退出登录')),
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          decoration: const InputDecoration(
                            labelText: '同步方式',
                            border: OutlineInputBorder(),
                          ),
                          value: syncProvider.settings.syncMode,
                          items: const [
                            DropdownMenuItem(
                                value: 'realtime', child: Text('实时同步')),
                            DropdownMenuItem(
                                value: 'interval', child: Text('间隔同步')),
                            DropdownMenuItem(
                                value: 'manual', child: Text('手动同步')),
                          ],
                          onChanged: (value) {
                            if (value != null) syncProvider.setSyncMode(value);
                          },
                        ),
                        if (syncProvider.settings.syncMode == 'interval') ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<int>(
                                  decoration: const InputDecoration(
                                    labelText: '同步间隔',
                                    border: OutlineInputBorder(),
                                  ),
                                  value:
                                      syncProvider.settings.syncIntervalMinutes,
                                  items: const [
                                    DropdownMenuItem(
                                        value: 1, child: Text('1 分钟')),
                                    DropdownMenuItem(
                                        value: 5, child: Text('5 分钟')),
                                    DropdownMenuItem(
                                        value: 10, child: Text('10 分钟')),
                                    DropdownMenuItem(
                                        value: 15, child: Text('15 分钟')),
                                    DropdownMenuItem(
                                        value: 30, child: Text('30 分钟')),
                                    DropdownMenuItem(
                                        value: 60, child: Text('1 小时')),
                                  ],
                                  onChanged: (value) {
                                    if (value != null)
                                      syncProvider
                                          .setSyncIntervalMinutes(value);
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            FButton(
                              label: '测试连接',
                              onPress: () async {
                                final ok = await syncProvider.testConnection();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text(ok ? '连接成功' : '连接失败')),
                                  );
                                }
                              },
                            ),
                            const SizedBox(width: 8),
                            if (syncProvider.settings.syncMode != 'manual')
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: syncProvider.settings.syncMode ==
                                          'realtime'
                                      ? Colors.green.withValues(alpha: 0.2)
                                      : Colors.blue.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  syncProvider.settings.syncMode == 'realtime'
                                      ? '实时同步'
                                      : '间隔 ${syncProvider.settings.syncIntervalMinutes} 分钟',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: syncProvider.settings.syncMode ==
                                            'realtime'
                                        ? Colors.green
                                        : Colors.blue,
                                  ),
                                ),
                              )
                            else if (syncProvider.isSyncing)
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            else
                              FButton(
                                label: '立即同步',
                                onPress: syncProvider.isConfigured
                                    ? () => _performSync(context, syncProvider)
                                    : null,
                              ),
                          ],
                        ),
                        if (syncProvider.settings.lastSyncTime != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            '上次同步: ${_formatDateTime(syncProvider.settings.lastSyncTime!)}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                        ],
                        if (syncProvider.lastError != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            syncProvider.lastError!,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.red),
                          ),
                        ],
                      ],
                    ],
                  ],
                ),
              ),
            );
          },
        ),

        const SizedBox(height: 16),

        // 数据操作
        FCard(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '数据操作',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                _buildSettingsListTile(
                  icon: Icons.storage,
                  title: '数据库状态',
                  subtitle: '查看数据库详细信息和日志',
                  onTap: () => _showDatabaseLogDialog(context),
                ),
                _buildSettingsListTile(
                  icon: Icons.upload,
                  title: '导出数据库',
                  subtitle: '将数据库导出为JSON文件',
                  onTap: () => _exportDatabase(context),
                ),
                _buildSettingsListTile(
                  icon: Icons.download,
                  title: '导入数据库',
                  subtitle: '从JSON文件导入数据库',
                  textColor: Colors.orange,
                  onTap: () => _showImportDatabaseDialog(context),
                ),
                const Divider(),
                _buildSettingsListTile(
                  icon: Icons.delete_forever,
                  title: '清空所有数据',
                  subtitle: '删除所有点名记录和词典数据',
                  textColor: Colors.red,
                  onTap: () => _showClearDataConfirmation(context),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // 操作按钮
        Row(
          children: [
            Expanded(
              child: FButton(
                label: '恢复默认设置',
                onPress: () => _showResetConfirmation(context),
                style: FButtonStyle.destructive,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FButton(
                label: '关于应用',
                onPress: () => _showAboutDialog(context),
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
                .surfaceVariant
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
  }

  Widget _buildSettingsListTile({
    required IconData icon,
    required String title,
    String? subtitle,
    Color? textColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, color: textColor ?? Colors.grey[700]),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      color: textColor,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: textColor ?? Colors.grey,
                      ),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  void _showColorPicker(BuildContext context) {
    final settingsProvider =
        Provider.of<SettingsProvider>(context, listen: false);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择主题颜色'),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 预设颜色
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildColorOption(context, const Color(0xFF2196F3), '淡蓝色',
                      settingsProvider),
                  _buildColorOption(
                      context, const Color(0xFF4CAF50), '绿色', settingsProvider),
                  _buildColorOption(
                      context, const Color(0xFFF44336), '红色', settingsProvider),
                  _buildColorOption(
                      context, const Color(0xFFFF9800), '橙色', settingsProvider),
                  _buildColorOption(
                      context, const Color(0xFF9C27B0), '紫色', settingsProvider),
                  _buildColorOption(
                      context, const Color(0xFFFF93B7), '粉色', settingsProvider),
                ],
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => _showCustomColorPicker(context),
                child: const Text('自定义颜色'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  Widget _buildColorOption(BuildContext context, Color color, String label,
      SettingsProvider provider) {
    return GestureDetector(
      onTap: () {
        provider.setThemeColor(color);
        Navigator.pop(context);
      },
      child: Column(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  void _showCustomColorPicker(BuildContext context) {
    final settingsProvider =
        Provider.of<SettingsProvider>(context, listen: false);
    HSVColor hsvColor = HSVColor.fromColor(settingsProvider.themeColor);

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            Color currentColor = hsvColor.toColor();

            return AlertDialog(
              title: const Text('自定义颜色'),
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
                                hsvColor,
                                setState, (newHsv) {
                              hsvColor = newHsv;
                              currentColor = hsvColor.toColor();
                            });
                          },
                          onPanUpdate: (details) {
                            _updateHsvFromTap(
                                details.localPosition,
                                const Size(280, 150),
                                hsvColor,
                                setState, (newHsv) {
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
                            border: Border.all(
                                color: Colors.grey.shade400, width: 2),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'HEX: #${currentColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
                            style: const TextStyle(
                                fontFamily: 'monospace', fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('色相:', style: TextStyle(fontSize: 14)),
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
                        const Text('透明度:', style: TextStyle(fontSize: 14)),
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
                    settingsProvider.setThemeColor(currentColor);
                    Navigator.pop(context);
                  },
                  child: const Text('应用颜色'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _updateHsvFromTap(Offset position, Size size, HSVColor hsvColor,
      StateSetter setState, Function(HSVColor) onUpdate) {
    double saturation = (position.dx / size.width).clamp(0.0, 1.0);
    double value = 1.0 - (position.dy / size.height).clamp(0.0, 1.0);
    final newHsv =
        HSVColor.fromAHSV(hsvColor.alpha, hsvColor.hue, saturation, value);
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

  void _showResetConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => FDialog(
        title: '恢复默认设置',
        body: '确定要恢复所有设置为默认值吗？',
        actions: [
          FButton(
            label: '取消',
            onPress: () => Navigator.pop(context),
          ),
          FButton(
            label: '确认恢复',
            style: FButtonStyle.destructive,
            onPress: () {
              Provider.of<SettingsProvider>(context, listen: false)
                  .resetToDefaults();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('已恢复默认设置'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showClearDataConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => FDialog(
        title: '清空所有数据',
        body:
            '⚠️ 警告：此操作不可恢复！\n\n将删除所有点名记录数据，包括：\n• 所有通联记录\n• 呼号、设备、天线词典\n• QTH 历史记录\n\n确定要继续吗？',
        actions: [
          FButton(
            label: '取消',
            onPress: () => Navigator.pop(context),
          ),
          FButton(
            label: '确认清空',
            style: FButtonStyle.destructive,
            onPress: () async {
              Navigator.pop(context);
              try {
                final dictionaryProvider =
                    Provider.of<DictionaryProvider>(context, listen: false);
                await dictionaryProvider.resetAllData();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('已清空所有数据'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('清空失败: $e'),
                      duration: const Duration(seconds: 5),
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  void _exportDatabase(BuildContext context) async {
    try {
      final db = DatabaseHelper();
      final jsonData = await db.exportDatabase();
      final stats = await db.getDatabaseStats();

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
        final file = File(result);
        await file.writeAsString(jsonData);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  '数据库已导出！\n记录: ${stats['logs']} 条\n设备: ${stats['device_dictionary']} 个\n天线: ${stats['antenna_dictionary']} 个\nQTH: ${stats['qth_dictionary']} 个\n呼号: ${stats['callsign_dictionary']} 个\n历史: ${stats['history']} 条'),
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
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
          FButton(
            label: '取消',
            onPress: () => Navigator.pop(dialogContext),
          ),
          FButton(
            label: '继续导入',
            style: FButtonStyle.destructive,
            onPress: () async {
              Navigator.pop(dialogContext);
              await _importDatabase(context);
            },
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
        final db = DatabaseHelper();
        await db.importDatabase(jsonData);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('数据库导入成功！'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
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
          FButton(
            label: '关闭',
            onPress: () => Navigator.pop(dialogContext),
          ),
        ],
      ),
    );
  }

  Future<String> _buildDatabaseStatus(BuildContext ctx) async {
    final StringBuffer info = StringBuffer();
    info.writeln('=== 应用状态 ===');

    try {
      final logProvider = Provider.of<LogProvider>(ctx, listen: false);
      final dictProvider = Provider.of<DictionaryProvider>(ctx, listen: false);

      info.writeln('点名记录数: ${logProvider.logs.length}');
      info.writeln('设备词典数: ${dictProvider.deviceDict.length}');
      info.writeln('天线词典数: ${dictProvider.antennaDict.length}');
      info.writeln('QTH词典数: ${dictProvider.qthDict.length}');
      info.writeln('呼号词典数: ${dictProvider.callsignDict.length}');

      final db = DatabaseHelper();
      final database = await db.database;
      final tables = await database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name");
      info.writeln('');
      info.writeln('=== 数据库表 ===');
      for (final table in tables) {
        final name = table['name'] as String;
        info.writeln('表: $name');
        try {
          final count =
              await database.rawQuery('SELECT COUNT(*) as c FROM "$name"');
          info.writeln('  行数: ${count.first['c']}');
        } catch (_) {
          info.writeln('  无法读取行数');
        }
      }
    } catch (e) {
      info.writeln('');
      info.writeln('=== 错误 ===');
      info.writeln('$e');
    }

    return info.toString();
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
                '支持快速记录通联信息，管理设备、天线、呼号词典，'
                '以及数据导入导出功能。',
              ),
              const SizedBox(height: 12),
              const Text(
                '主要功能:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Text('• 快速添加点名记录'),
              const Text('• 设备、天线、呼号、QTH词典管理'),
              const Text('• 数据导入导出 (JSON, Excel)'),
              const Text('• 暗色/亮色主题切换'),
              const Text('• 宽屏平行布局'),
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
          FButton(
            label: '关闭',
            onPress: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  void _showFontPicker(BuildContext context) {
    final settingsProvider =
        Provider.of<SettingsProvider>(context, listen: false);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择字体'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: settingsProvider.availableFonts.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                final isSelected = settingsProvider.fontFamily == null ||
                    settingsProvider.fontFamily!.isEmpty;
                return ListTile(
                  title: const Text('系统默认'),
                  trailing: isSelected
                      ? Icon(Icons.check,
                          color: Theme.of(context).colorScheme.primary)
                      : null,
                  selected: isSelected,
                  onTap: () {
                    settingsProvider.setFontFamily(null);
                    Navigator.pop(context);
                  },
                );
              }

              final font = settingsProvider.availableFonts[index - 1];
              final isSelected = font == settingsProvider.fontFamily;
              final isBuiltin = font == 'SarasaGothicSC';

              return ListTile(
                title: Text(
                  isBuiltin ? '$font (内置)' : font,
                  style: TextStyle(fontFamily: font),
                ),
                trailing: isSelected
                    ? Icon(Icons.check,
                        color: Theme.of(context).colorScheme.primary)
                    : null,
                selected: isSelected,
                onTap: () {
                  settingsProvider.setFontFamily(font);
                  Navigator.pop(context);
                },
              );
            },
          ),
        ),
        actions: [
          FButton(
            label: '取消',
            onPress: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Future<void> _performSync(
      BuildContext context, SyncProvider syncProvider) async {
    final ok = await syncProvider.runBidirectionalSync();

    if (context.mounted) {
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('同步成功！')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('同步失败: ${syncProvider.lastError ?? "未知错误"}')),
        );
      }
    }
  }

  String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class _ServerSettingsFields extends StatefulWidget {
  final SyncProvider syncProvider;

  const _ServerSettingsFields({required this.syncProvider});

  @override
  State<_ServerSettingsFields> createState() => _ServerSettingsFieldsState();
}

class _ServerSettingsFieldsState extends State<_ServerSettingsFields> {
  late TextEditingController _serverUrlController;
  late TextEditingController _deviceIdController;

  @override
  void initState() {
    super.initState();
    _serverUrlController =
        TextEditingController(text: widget.syncProvider.settings.serverUrl);
    _deviceIdController =
        TextEditingController(text: widget.syncProvider.settings.deviceId);
  }

  @override
  void didUpdateWidget(_ServerSettingsFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.syncProvider.settings.serverUrl != _serverUrlController.text) {
      _serverUrlController.text = widget.syncProvider.settings.serverUrl;
    }
    if (widget.syncProvider.settings.deviceId != _deviceIdController.text) {
      _deviceIdController.text = widget.syncProvider.settings.deviceId;
    }
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _deviceIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          decoration: const InputDecoration(
            labelText: '服务器地址',
            hintText: 'http://localhost:3000',
            border: OutlineInputBorder(),
          ),
          controller: _serverUrlController,
          onChanged: (value) => widget.syncProvider.setServerUrl(value),
        ),
        const SizedBox(height: 8),
        TextField(
          decoration: const InputDecoration(
            labelText: '设备ID',
            hintText: 'device-001',
            border: OutlineInputBorder(),
          ),
          controller: _deviceIdController,
          onChanged: (value) => widget.syncProvider.setDeviceId(value),
        ),
      ],
    );
  }
}

class _LoginDialog extends StatefulWidget {
  static String? username;
  static String? password;

  @override
  State<_LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<_LoginDialog> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('子账号登录'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            decoration: const InputDecoration(
              labelText: '用户名',
              border: OutlineInputBorder(),
            ),
            controller: _usernameController,
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(
              labelText: '密码',
              border: OutlineInputBorder(),
            ),
            obscureText: true,
            controller: _passwordController,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () {
            _LoginDialog.username = _usernameController.text;
            _LoginDialog.password = _passwordController.text;
            Navigator.pop(context, true);
          },
          child: const Text('登录'),
        ),
      ],
    );
  }
}
