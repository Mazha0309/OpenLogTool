import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/providers/settings_provider.dart';
import 'package:openlogtool/widgets/settings/theme_settings.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('changes the app language immediately and persists the choice',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    _usePlatformLocale(tester, const Locale('zh', 'CN'));
    final settings = SettingsProvider();
    addTearDown(settings.dispose);

    await tester.pumpWidget(_ThemeSettingsHarness(settings: settings));
    await tester.pumpAndSettle();

    expect(settings.appLocalePreference, AppLocalePreference.system);
    expect(_currentLocale(tester), const Locale('zh', 'CN'));
    expect(find.text('外观与语言'), findsOneWidget);
    expect(find.text('界面语言'), findsOneWidget);

    await _selectLanguage(tester, 'English');

    expect(settings.appLocalePreference, AppLocalePreference.english);
    expect(_currentLocale(tester), const Locale('en', 'US'));
    expect(find.text('Appearance & language'), findsOneWidget);
    expect(find.text('Interface language'), findsOneWidget);
    expect(find.text('Theme color'), findsOneWidget);
    expect(find.text('外观与语言'), findsNothing);
    expect(
      (await SharedPreferences.getInstance()).getString(
        'appLocalePreference',
      ),
      'english',
    );

    await _selectLanguage(tester, '简体中文');

    expect(
      settings.appLocalePreference,
      AppLocalePreference.simplifiedChinese,
    );
    expect(_currentLocale(tester), const Locale('zh', 'CN'));
    expect(find.text('外观与语言'), findsOneWidget);
    expect(find.text('界面语言'), findsOneWidget);
    expect(find.text('Appearance & language'), findsNothing);
    expect(
      (await SharedPreferences.getInstance()).getString(
        'appLocalePreference',
      ),
      'simplifiedChinese',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('language control remains scrollable on a narrow scaled screen',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    _usePlatformLocale(tester, const Locale('zh', 'CN'));
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final settings = SettingsProvider();
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      _ThemeSettingsHarness(
        settings: settings,
        textScaler: const TextScaler.linear(2),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('外观与语言'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final languagePicker = find.byKey(const Key('app-language-picker'));
    await tester.scrollUntilVisible(
      languagePicker,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(languagePicker.hitTestable(), findsOneWidget);

    await tester.tap(languagePicker);
    await tester.pumpAndSettle();
    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();

    expect(settings.appLocalePreference, AppLocalePreference.english);
    expect(find.text('Interface language'), findsOneWidget);
    expect(
      (await SharedPreferences.getInstance()).getString(
        'appLocalePreference',
      ),
      'english',
    );
    expect(tester.takeException(), isNull);
  });
}

void _usePlatformLocale(WidgetTester tester, Locale locale) {
  final dispatcher = tester.binding.platformDispatcher;
  dispatcher.localeTestValue = locale;
  dispatcher.localesTestValue = <Locale>[locale];
  addTearDown(() {
    dispatcher.clearLocaleTestValue();
    dispatcher.clearLocalesTestValue();
  });
}

Locale _currentLocale(WidgetTester tester) => Localizations.localeOf(
      tester.element(find.byKey(const Key('app-language-picker'))),
    );

Future<void> _selectLanguage(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const Key('app-language-picker')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

class _ThemeSettingsHarness extends StatelessWidget {
  const _ThemeSettingsHarness({
    required this.settings,
    this.textScaler = TextScaler.noScaling,
  });

  final SettingsProvider settings;
  final TextScaler textScaler;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<SettingsProvider>.value(
      value: settings,
      child: Consumer<SettingsProvider>(
        builder: (context, settings, child) => MaterialApp(
          locale: settings.locale,
          localeResolutionCallback: resolveAppLocale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            child: child!,
          ),
          home: const Scaffold(
            body: SingleChildScrollView(
              key: Key('theme-settings-scroll'),
              padding: EdgeInsets.all(12),
              child: ThemeSettings(
                isNarrow: true,
                cardPadding: 12,
                onPickColor: _ignore,
                onPickFont: _ignore,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void _ignore() {}
