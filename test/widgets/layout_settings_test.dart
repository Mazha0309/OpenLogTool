import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/providers/settings_provider.dart';
import 'package:openlogtool/widgets/settings/layout_settings.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('legacy wide-layout preference has no visible setting',
      (tester) async {
    SharedPreferences.setMockInitialValues(
      <String, Object>{'wideLayoutEnabled': true},
    );
    final settings = SettingsProvider();
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: const MaterialApp(
          locale: Locale('zh', 'CN'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: LayoutSettings(isNarrow: false, cardPadding: 16),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('宽屏平行布局'), findsNothing);
    expect(find.text('分页显示记录'), findsOneWidget);
    expect(find.text('呼号历史一键复用'), findsOneWidget);
    settings.dispose();
  });
}
