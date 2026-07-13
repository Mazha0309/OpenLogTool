import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:openlogtool/l10n/l10n.dart';
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
                Icon(Icons.view_quilt,
                    color: theme.colorScheme.primary, size: 20),
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
              switchKey: const Key('limit-workbench-width-toggle'),
              title: context.l10n.limitWorkbenchWidthSetting,
              subtitle: context.l10n.limitWorkbenchWidthHint,
              value: settingsProvider.limitWorkbenchWidth,
              onChanged: settingsProvider.setLimitWorkbenchWidth,
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
              title: context.l10n.callsignHistoryFillSetting,
              subtitle: context.l10n.callsignHistoryFillHint,
              value: settingsProvider.callSignQthLinkEnabled,
              onChanged: (v) => settingsProvider.setCallSignQthLink(v),
            ),
            const Divider(height: 16),
            _buildSwitchRow(
              context: context,
              title: context.l10n.duplicateCallsignWarningSetting,
              subtitle: context.l10n.duplicateCallsignWarningHint,
              value: settingsProvider.duplicateCallsignWarningEnabled,
              onChanged: settingsProvider.setDuplicateCallsignWarningEnabled,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchRow({
    required BuildContext context,
    Key? switchKey,
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
                style: theme.textTheme.bodyLarge
                    ?.copyWith(fontWeight: FontWeight.w500),
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
        Switch(key: switchKey, value: value, onChanged: onChanged),
      ],
    );
  }
}
