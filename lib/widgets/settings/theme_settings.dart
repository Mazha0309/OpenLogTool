import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:forui/forui.dart';
import 'package:openlogtool/providers/settings_provider.dart';

class ThemeSettings extends StatelessWidget {
  final bool isNarrow;
  final double cardPadding;
  final VoidCallback onPickColor;
  final VoidCallback onPickFont;

  const ThemeSettings({
    super.key,
    required this.isNarrow,
    required this.cardPadding,
    required this.onPickColor,
    required this.onPickFont,
  });

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context);

    return FCard(
      child: Padding(
        padding: EdgeInsets.all(cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '主题设置',
              style: TextStyle(
                fontSize: isNarrow ? 14 : 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: isNarrow ? 8 : 12),
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
                FButton(label: '选择颜色', onPress: onPickColor),
              ],
            ),
            const SizedBox(height: 12),
            // 暗色模式
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('暗色模式'),
                      SizedBox(height: 2),
                      Text('切换到暗色主题',
                          style: TextStyle(fontSize: 12, color: Colors.grey)),
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
            // 字体
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('字体'),
                      SizedBox(height: 2),
                      Text('选择应用字体',
                          style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
                FButton(
                  label: settingsProvider.fontFamily ?? '系统默认',
                  onPress: onPickFont,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
