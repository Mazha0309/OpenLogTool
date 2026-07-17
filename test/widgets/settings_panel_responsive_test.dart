import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/providers/app_info_provider.dart';
import 'package:openlogtool/providers/server_provider.dart';
import 'package:openlogtool/providers/settings_provider.dart';
import 'package:openlogtool/providers/snackbar_log_provider.dart';
import 'package:openlogtool/widgets/settings/layout_settings.dart';
import 'package:openlogtool/widgets/settings/theme_settings.dart';
import 'package:openlogtool/widgets/settings_panel.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('categorized settings remain usable on a narrow scaled screen',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    _usePlatformLocale(tester, const Locale('en', 'US'));
    await _setSurface(tester, const Size(320, 568));
    final providers = _SettingsProviders();
    addTearDown(providers.dispose);

    await tester.pumpWidget(
      _SettingsPanelHarness(
        providers: providers,
        textScaler: const TextScaler.linear(2),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings-compact-layout')), findsOneWidget);
    expect(
      find.byKey(const Key('settings-category-appearance')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    final pageScrollable = find
        .descendant(
          of: find.byKey(const Key('settings-panel-scroll')),
          matching: find.byType(Scrollable),
        )
        .first;
    expect(pageScrollable, findsOneWidget);

    await tester.tap(
      find.byKey(const Key('settings-category-appearance')).hitTestable(),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-category-back')), findsOneWidget);

    final languagePicker = find.byKey(const Key('app-language-picker'));
    await tester.scrollUntilVisible(
      languagePicker,
      240,
      scrollable: pageScrollable,
    );
    expect(languagePicker.hitTestable(), findsOneWidget);
    await tester.tap(languagePicker);
    await tester.pumpAndSettle();
    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();
    expect(find.text('Appearance & language'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final back = find.byKey(const Key('settings-category-back'));
    await tester.scrollUntilVisible(
      back,
      -240,
      scrollable: pageScrollable,
    );
    await tester.tap(back);
    await tester.pumpAndSettle();

    final aboutEntry = find.byKey(const Key('about-app-entry'));
    final applicationCategory =
        find.byKey(const Key('settings-category-application'));
    await tester.scrollUntilVisible(
      applicationCategory,
      320,
      scrollable: pageScrollable,
    );
    await tester.tap(applicationCategory);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      aboutEntry,
      240,
      scrollable: pageScrollable,
    );
    expect(aboutEntry.hitTestable(), findsOneWidget);
    await tester.tap(aboutEntry);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('about-app-dialog')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('about-close')));
    await tester.pumpAndSettle();

    final restoreEntry =
        find.byKey(const Key('restore-default-settings-entry'));
    await tester.scrollUntilVisible(
      restoreEntry,
      160,
      scrollable: pageScrollable,
    );
    expect(restoreEntry.hitTestable(), findsOneWidget);
    await tester.tap(restoreEntry);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Restore default settings'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide settings use a category rail and one visible detail',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    _usePlatformLocale(tester, const Locale('en', 'US'));
    await _setSurface(tester, const Size(1200, 900));
    final providers = _SettingsProviders();
    addTearDown(providers.dispose);

    await tester.pumpWidget(_SettingsPanelHarness(providers: providers));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings-wide-layout')), findsOneWidget);
    final categoryNavigation =
        find.byKey(const Key('settings-category-navigation'));
    final appearanceSettings = find.byType(
      ThemeSettings,
      skipOffstage: false,
    );
    final layoutSettings = find.byType(
      LayoutSettings,
      skipOffstage: false,
    );
    final appearanceCard = find.descendant(
      of: appearanceSettings,
      matching: find.byType(Card, skipOffstage: false),
    );
    final layoutCard = find.descendant(
      of: layoutSettings,
      matching: find.byType(Card, skipOffstage: false),
    );
    expect(appearanceCard, findsOneWidget);
    expect(layoutCard, findsOneWidget);

    final appearanceOffstage = tester.widget<Offstage>(
      find.ancestor(
        of: appearanceSettings,
        matching: find.byType(Offstage, skipOffstage: false),
      ).first,
    );
    final layoutOffstage = tester.widget<Offstage>(
      find.ancestor(
        of: layoutSettings,
        matching: find.byType(Offstage, skipOffstage: false),
      ).first,
    );
    expect(appearanceOffstage.offstage, isFalse);
    expect(layoutOffstage.offstage, isTrue);
    final appearanceRect = tester.getRect(appearanceCard);
    expect(appearanceRect.size, isNot(Size.zero));
    expect(
      tester.getRect(categoryNavigation).right,
      lessThan(appearanceRect.left),
    );
    expect(find.text('Appearance & language'), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings-category-workbench')));
    await tester.pumpAndSettle();

    final layoutRect = tester.getRect(layoutCard);
    expect(layoutRect.size, isNot(Size.zero));
    expect(
      tester
          .widget<Offstage>(
            find.ancestor(
              of: appearanceSettings,
              matching: find.byType(Offstage, skipOffstage: false),
            ).first,
          )
          .offstage,
      isTrue,
    );
    expect(
      tester
          .widget<Offstage>(
            find.ancestor(
              of: layoutSettings,
              matching: find.byType(Offstage, skipOffstage: false),
            ).first,
          )
          .offstage,
      isFalse,
    );
    expect(find.text('Net Desk & layout'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _setSurface(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
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

class _SettingsProviders {
  _SettingsProviders()
      : settings = SettingsProvider(),
        server = ServerProvider(autoLoadSettings: false),
        appInfo = AppInfoProvider(),
        snackbarLog = SnackbarLogProvider();

  final SettingsProvider settings;
  final ServerProvider server;
  final AppInfoProvider appInfo;
  final SnackbarLogProvider snackbarLog;

  void dispose() {
    settings.dispose();
    server.dispose();
    appInfo.dispose();
    snackbarLog.dispose();
  }
}

class _SettingsPanelHarness extends StatelessWidget {
  const _SettingsPanelHarness({
    required this.providers,
    this.textScaler = TextScaler.noScaling,
  });

  final _SettingsProviders providers;
  final TextScaler textScaler;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>.value(
          value: providers.settings,
        ),
        ChangeNotifierProvider<ServerProvider>.value(value: providers.server),
        ChangeNotifierProvider<AppInfoProvider>.value(
          value: providers.appInfo,
        ),
        ChangeNotifierProvider<SnackbarLogProvider>.value(
          value: providers.snackbarLog,
        ),
      ],
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
          home: const Scaffold(body: _SettingsPanelHost()),
        ),
      ),
    );
  }
}

class _SettingsPanelHost extends StatelessWidget {
  const _SettingsPanelHost();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 600;
        return SingleChildScrollView(
          key: const Key('settings-panel-scroll'),
          padding: EdgeInsets.symmetric(
            horizontal: isNarrow ? 8 : 24,
            vertical: isNarrow ? 12 : 24,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: const SettingsPanel(),
            ),
          ),
        );
      },
    );
  }
}
