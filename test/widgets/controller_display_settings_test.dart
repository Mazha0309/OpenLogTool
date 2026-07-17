import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/providers/settings_provider.dart';
import 'package:openlogtool/widgets/settings/controller_display_settings.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('controller device entry is opt-in and persisted',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: const MaterialApp(
          locale: Locale('zh', 'CN'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ControllerDisplaySettings(cardPadding: 16),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(settings.controllerDeviceModeEnabled, isFalse);
    final toggle = find.byKey(const Key('controller-device-mode-switch'));
    expect(
      tester
          .widget<Switch>(
            find.descendant(of: toggle, matching: find.byType(Switch)),
          )
          .value,
      isFalse,
    );

    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(settings.controllerDeviceModeEnabled, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('controllerDeviceModeEnabled'), isTrue);
  });

  testWidgets('controller settings render in en_US', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: const MaterialApp(
          locale: Locale('en', 'US'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ControllerDisplaySettings(cardPadding: 16),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Controller display'), findsOneWidget);
    expect(find.text('Enable controller-device entry'), findsOneWidget);
    expect(find.text('Default information detail'), findsOneWidget);
  });
}
