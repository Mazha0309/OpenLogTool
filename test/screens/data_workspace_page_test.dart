import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/providers/dictionary_provider.dart';
import 'package:openlogtool/providers/log_provider.dart';
import 'package:openlogtool/providers/session_provider.dart';
import 'package:openlogtool/providers/settings_provider.dart';
import 'package:openlogtool/screens/data_workspace_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('data workspace exposes three embedded destinations',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final settings = SettingsProvider(systemFontsLoader: () async => []);
    final sessions = SessionProvider(sessionListLoader: () async => []);
    final logs = LogProvider(
      sessionListLoader: () async => [],
      sessionLogPageLoader: (_, __, ___) async => [],
    );
    final dictionaries = DictionaryProvider(autoload: false);
    addTearDown(settings.dispose);
    addTearDown(sessions.dispose);
    addTearDown(logs.dispose);
    addTearDown(dictionaries.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: sessions),
          ChangeNotifierProvider.value(value: logs),
          ChangeNotifierProvider.value(value: dictionaries),
        ],
        child: const MaterialApp(
          locale: Locale('en', 'US'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: DataWorkspacePage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('data-workspace-selector')), findsOneWidget);
    expect(find.byKey(const Key('data-transfer-page-header')), findsNothing);

    await tester.tap(find.text('Lookup libraries'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('export-library-json')), findsOneWidget);
    expect(find.byKey(const Key('dictionary-page-header')), findsNothing);

    await tester.tap(find.text('Local database'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('database-operation-status')), findsOneWidget);
  });
}
