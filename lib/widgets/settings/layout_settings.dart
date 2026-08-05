import 'package:flutter/material.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/providers/settings_provider.dart';
import 'package:openlogtool/widgets/settings/settings_ui.dart';
import 'package:provider/provider.dart';

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
    final settingsProvider = context.watch<SettingsProvider>();
    final l10n = context.l10n;

    return SettingsSectionCard(
      icon: Icons.dashboard_customize_outlined,
      title: l10n.layoutSettingsTitle,
      description: l10n.layoutSettingsHint,
      padding: cardPadding,
      contentSpacing: isNarrow ? 10 : 14,
      child: SettingsTileGroup(
        children: [
          SettingsActionTile(
            icon: Icons.width_normal_outlined,
            title: l10n.limitWorkbenchWidthSetting,
            subtitle: l10n.limitWorkbenchWidthHint,
            trailing: Switch(
              key: const Key('limit-workbench-width-toggle'),
              value: settingsProvider.limitWorkbenchWidth,
              onChanged: settingsProvider.setLimitWorkbenchWidth,
            ),
          ),
          SettingsActionTile(
            icon: Icons.view_list_outlined,
            title: l10n.paginationSetting,
            subtitle: l10n.paginationSettingHint,
            trailing: Switch(
              key: const Key('pagination-enabled-toggle'),
              value: settingsProvider.paginationEnabled,
              onChanged: settingsProvider.setPaginationEnabled,
            ),
          ),
          SettingsActionTile(
            icon: Icons.format_list_numbered_outlined,
            title: l10n.tablePageSizeLabel,
            subtitle: l10n.tablePageSizeHint,
            trailing: DropdownButton<int>(
              key: const Key('table-page-size-select'),
              value: settingsProvider.tablePageSize,
              items: SettingsProvider.tablePageSizeOptions
                  .map(
                    (n) => DropdownMenuItem(
                      value: n,
                      child: Text('$n'),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) settingsProvider.setTablePageSize(v);
              },
            ),
          ),
          SettingsActionTile(
            icon: Icons.manage_search_outlined,
            title: l10n.callsignHistoryFillSetting,
            subtitle: l10n.callsignHistoryFillHint,
            trailing: Switch(
              value: settingsProvider.callSignQthLinkEnabled,
              onChanged: settingsProvider.setCallSignQthLink,
            ),
          ),
          SettingsActionTile(
            icon: Icons.content_copy_outlined,
            title: l10n.duplicateCallsignWarningSetting,
            subtitle: l10n.duplicateCallsignWarningHint,
            trailing: Switch(
              value: settingsProvider.duplicateCallsignWarningEnabled,
              onChanged: settingsProvider.setDuplicateCallsignWarningEnabled,
            ),
          ),
          SettingsActionTile(
            icon: Icons.open_in_full_outlined,
            title: l10n.recordEditorDialogSetting,
            subtitle: l10n.recordEditorDialogSettingHint,
            trailing: Switch(
              key: const Key('record-editor-dialog-toggle'),
              value: settingsProvider.recordEditorDialogEnabled,
              onChanged: settingsProvider.setRecordEditorDialogEnabled,
            ),
          ),
          SettingsActionTile(
            icon: Icons.electric_bolt_outlined,
            title: l10n.autoAppendPowerWSetting,
            subtitle: l10n.autoAppendPowerWHint,
            trailing: Switch(
              key: const Key('auto-append-power-w-switch'),
              value: settingsProvider.autoAppendPowerW,
              onChanged: settingsProvider.setAutoAppendPowerW,
            ),
          ),
        ],
      ),
    );
  }
}
