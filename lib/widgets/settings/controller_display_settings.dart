import 'package:flutter/material.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/models/controller_display.dart';
import 'package:openlogtool/providers/settings_provider.dart';
import 'package:openlogtool/services/controller_window_service.dart';
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
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: EdgeInsets.all(cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cast, color: theme.colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  context.l10n.controllerDisplaySettingsTitle,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              key: const Key('controller-device-mode-switch'),
              contentPadding: EdgeInsets.zero,
              title: Text(context.l10n.enableControllerDeviceEntry),
              subtitle: Text(context.l10n.enableControllerDeviceEntryHint),
              value: settings.controllerDeviceModeEnabled,
              onChanged: settings.setControllerDeviceModeEnabled,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<ControllerDisplayDetail>(
              key: const Key('default-controller-detail-picker'),
              initialValue: settings.controllerDisplayPreferences.detail,
              decoration: InputDecoration(
                labelText: context.l10n.defaultInformationDetail,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              items: ControllerDisplayDetail.values
                  .map(
                    (detail) => DropdownMenuItem(
                      value: detail,
                      child: Text(
                        controllerDetailLabel(context.l10n, detail),
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
            const SizedBox(height: 8),
            Text(
              supportsControllerDesktopWindows
                  ? context.l10n.desktopControllerDisplayHint
                  : context.l10n.inAppControllerDisplayHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
