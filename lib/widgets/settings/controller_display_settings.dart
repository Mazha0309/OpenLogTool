import 'package:flutter/material.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/models/controller_display.dart';
import 'package:openlogtool/providers/settings_provider.dart';
import 'package:openlogtool/services/controller_window_service.dart';
import 'package:openlogtool/theme/app_theme.dart';
import 'package:openlogtool/widgets/settings/settings_ui.dart';
import 'package:provider/provider.dart';

class ControllerDisplaySettings extends StatelessWidget {
  const ControllerDisplaySettings({
    super.key,
    required this.cardPadding,
  });

  final double cardPadding;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return SettingsSectionCard(
      icon: Icons.cast_outlined,
      title: context.l10n.controllerDisplaySettingsTitle,
      description: context.l10n.controllerDisplaySettingsHint,
      padding: cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsActionTile(
            key: const Key('controller-device-mode-switch'),
            icon: Icons.devices_outlined,
            title: context.l10n.enableControllerDeviceEntry,
            subtitle: context.l10n.enableControllerDeviceEntryHint,
            trailing: Switch(
              value: settings.controllerDeviceModeEnabled,
              onChanged: settings.setControllerDeviceModeEnabled,
            ),
            onTap: () => settings.setControllerDeviceModeEnabled(
              !settings.controllerDeviceModeEnabled,
            ),
          ),
          const Divider(height: AppSpace.lg),
          DropdownButtonFormField<ControllerDisplayDetail>(
            key: const Key('default-controller-detail-picker'),
            initialValue: settings.controllerDisplayPreferences.detail,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: context.l10n.defaultInformationDetail,
              border: const OutlineInputBorder(),
              isDense: true,
              prefixIcon: const Icon(Icons.tune_outlined, size: 20),
            ),
            items: ControllerDisplayDetail.values
                .map(
                  (detail) => DropdownMenuItem(
                    value: detail,
                    child: Text(
                      controllerDetailLabel(context.l10n, detail),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(growable: false),
            onChanged: (detail) {
              if (detail != null) {
                settings.setControllerDisplayPreferences(
                  settings.controllerDisplayPreferences.copyWith(
                    detail: detail,
                  ),
                );
              }
            },
          ),
          const SizedBox(height: AppSpace.sm),
          AppNotice(
            message: supportsControllerDesktopWindows
                ? context.l10n.desktopControllerDisplayHint
                : context.l10n.inAppControllerDisplayHint,
            tone: AppTone.primary,
          ),
        ],
      ),
    );
  }
}
