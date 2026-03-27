import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:forui/forui.dart';
import 'package:openlogtool/providers/settings_provider.dart';
import 'package:openlogtool/providers/app_info_provider.dart';
import 'package:openlogtool/providers/log_provider.dart';
import 'package:openlogtool/providers/dictionary_provider.dart';
import 'package:openlogtool/database/database_helper.dart';

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
                      onChanged: (value) => settingsProvider.setWideLayout(value),
                    ),
                  ],
                ),
                
                const Divider(),
                
              ],
            ),
          ),
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
            color: Theme.of(context).colorScheme.surfaceVariant.withValues(alpha: 0.3),
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
    final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    
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
                  _buildColorOption(context, const Color(0xFF2196F3), '淡蓝色', settingsProvider),
                  _buildColorOption(context, const Color(0xFF4CAF50), '绿色', settingsProvider),
                  _buildColorOption(context, const Color(0xFFF44336), '红色', settingsProvider),
                  _buildColorOption(context, const Color(0xFFFF9800), '橙色', settingsProvider),
                  _buildColorOption(context, const Color(0xFF9C27B0), '紫色', settingsProvider),
                  _buildColorOption(context, const Color(0xFF607D8B), '灰色', settingsProvider),
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

  Widget _buildColorOption(BuildContext context, Color color, String label, SettingsProvider provider) {
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
    final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    Color selectedColor = settingsProvider.themeColor;
    int red = selectedColor.red;
    int green = selectedColor.green;
    int blue = selectedColor.blue;
    
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('自定义颜色'),
              content: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 颜色预览
                    Container(
                      width: 120,
                      height: 120,
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
                      child: Center(
                        child: Text(
                          'RGB: $red, $green, $blue',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // RGB滑块
                    _buildColorSlider(
                      label: '红色 (R)',
                      value: red.toDouble(),
                      color: Colors.red,
                      onChanged: (value) {
                        setState(() {
                          red = value.toInt();
                        });
                      },
                    ),
                    
                    _buildColorSlider(
                      label: '绿色 (G)',
                      value: green.toDouble(),
                      color: Colors.green,
                      onChanged: (value) {
                        setState(() {
                          green = value.toInt();
                        });
                      },
                    ),
                    
                    _buildColorSlider(
                      label: '蓝色 (B)',
                      value: blue.toDouble(),
                      color: Colors.blue,
                      onChanged: (value) {
                        setState(() {
                          blue = value.toInt();
                        });
                      },
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // 颜色值显示
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('RGB: $red, $green, $blue'),
                        Text('HEX: #${red.toRadixString(16).padLeft(2, '0')}${green.toRadixString(16).padLeft(2, '0')}${blue.toRadixString(16).padLeft(2, '0')}'),
                      ],
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // 快速颜色选择
                    const Text('快速选择:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildQuickColorOption(
                          context,
                          const Color(0xFF2196F3),
                          setState,
                          () {
                            red = 33;
                            green = 150;
                            blue = 243;
                          },
                        ),
                        _buildQuickColorOption(
                          context,
                          const Color(0xFF4CAF50),
                          setState,
                          () {
                            red = 76;
                            green = 175;
                            blue = 80;
                          },
                        ),
                        _buildQuickColorOption(
                          context,
                          const Color(0xFFF44336),
                          setState,
                          () {
                            red = 244;
                            green = 67;
                            blue = 54;
                          },
                        ),
                        _buildQuickColorOption(
                          context,
                          const Color(0xFFFF9800),
                          setState,
                          () {
                            red = 255;
                            green = 152;
                            blue = 0;
                          },
                        ),
                        _buildQuickColorOption(
                          context,
                          const Color(0xFF9C27B0),
                          setState,
                          () {
                            red = 156;
                            green = 39;
                            blue = 176;
                          },
                        ),
                        _buildQuickColorOption(
                          context,
                          const Color(0xFF607D8B),
                          setState,
                          () {
                            red = 96;
                            green = 125;
                            blue = 139;
                          },
                        ),
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
                    settingsProvider.setThemeColor(Color.fromARGB(255, red, green, blue));
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

  Widget _buildColorSlider({
    required String label,
    required double value,
    required Color color,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
            Text(value.toInt().toString()),
          ],
        ),
        Slider(
          value: value,
          min: 0,
          max: 255,
          divisions: 255,
          activeColor: color,
          inactiveColor: color.withValues(alpha: 0.3),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildQuickColorOption(
    BuildContext context,
    Color color,
    StateSetter setState,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: () {
        onTap();
        setState(() {});
      },
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.grey.shade400),
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
              Provider.of<SettingsProvider>(context, listen: false).resetToDefaults();
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
        body: '⚠️ 警告：此操作不可恢复！\n\n将删除所有点名记录数据，包括：\n• 所有通联记录\n• 呼号、设备、天线词典\n\n确定要继续吗？',
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
                final dictionaryProvider = Provider.of<DictionaryProvider>(context, listen: false);
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
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
      );
      info.writeln('');
      info.writeln('=== 数据库表 ===');
      for (final table in tables) {
        final name = table['name'] as String;
        info.writeln('表: $name');
        try {
          final count = await database.rawQuery('SELECT COUNT(*) as c FROM "$name"');
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
    final appInfoProvider = Provider.of<AppInfoProvider>(context, listen: false);
    
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
    final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    
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
                final isSelected = settingsProvider.fontFamily == null || settingsProvider.fontFamily!.isEmpty;
                return ListTile(
                  title: const Text('系统默认'),
                  trailing: isSelected
                      ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
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
              
              return ListTile(
                title: Text(font, style: TextStyle(fontFamily: font)),
                trailing: isSelected
                    ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
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
}
