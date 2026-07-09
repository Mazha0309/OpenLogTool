import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:openlogtool/providers/settings_provider.dart';

class LayoutSettings extends StatelessWidget {
  final bool isNarrow;
  final double cardPadding;

  const LayoutSettings({
    super.key,
    required this.isNarrow,
    required this.cardPadding,
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
                Icon(Icons.view_quilt, color: theme.colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  '布局设置',
                  style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            SizedBox(height: isNarrow ? 12 : 16),
            _buildSwitchRow(
              context: context,
              title: '启用宽屏平行布局',
              subtitle: '在窗口宽度足够时，将添加记录和已有记录并排显示',
              value: settingsProvider.wideLayoutEnabled,
              onChanged: (v) => settingsProvider.setWideLayout(v),
            ),
            const Divider(height: 16),
            _buildSwitchRow(
              context: context,
              title: '分页显示记录',
              subtitle: '每 5 条记录分为一页显示',
              value: settingsProvider.paginationEnabled,
              onChanged: (v) => settingsProvider.setPaginationEnabled(v),
            ),
            const Divider(height: 16),
            _buildSwitchRow(
              context: context,
              title: '呼号历史填充',
              subtitle: '输入已记录过的呼号时，显示历史记录并一键填充全部字段',
              value: settingsProvider.callSignQthLinkEnabled,
              onChanged: (v) => settingsProvider.setCallSignQthLink(v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchRow({
    required BuildContext context,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
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
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}
