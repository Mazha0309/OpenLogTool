import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(128)),
      ),
      child: Padding(
        padding: EdgeInsets.all(cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.palette, color: theme.colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  '主题设置',
                  style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            SizedBox(height: isNarrow ? 12 : 16),
            _buildSettingTile(
              context,
              title: '主题颜色',
              subtitle: '选择应用主色调',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: settingsProvider.themeColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: theme.colorScheme.outlineVariant),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: onPickColor,
                    child: const Text('选择颜色'),
                  ),
                ],
              ),
            ),
            const Divider(height: 24),
            _buildSettingTile(
              context,
              title: '暗色模式',
              subtitle: '切换到暗色主题',
              trailing: Switch(
                value: settingsProvider.isDarkMode,
                onChanged: (value) => settingsProvider.setDarkMode(value),
              ),
            ),
            const Divider(height: 24),
            _buildSettingTile(
              context,
              title: '应用字体',
              subtitle: '选择显示字体',
              trailing: FilledButton(
                onPressed: onPickFont,
                child: Text(settingsProvider.fontFamily ?? '系统默认'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required Widget trailing,
  }) {
    final theme = Theme.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        trailing,
      ],
    );
  }
}
