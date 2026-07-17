import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('locale preference defaults to the system locale', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await _waitForInitialLoad(settings);

    expect(settings.appLocalePreference, AppLocalePreference.system);
    expect(settings.locale, isNull);
    settings.dispose();
  });

  test('locale preference applies immediately and persists', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await _waitForInitialLoad(settings);
    var notifications = 0;
    settings.addListener(() => notifications += 1);

    final saving = settings.setAppLocalePreference(
      AppLocalePreference.english,
    );

    expect(settings.appLocalePreference, AppLocalePreference.english);
    expect(settings.locale, const Locale('en', 'US'));
    expect(notifications, 1);
    await saving;
    expect(
      (await SharedPreferences.getInstance()).getString(
        'appLocalePreference',
      ),
      AppLocalePreference.english.name,
    );
    settings.dispose();

    final restored = SettingsProvider();
    await _waitForInitialLoad(restored);
    expect(restored.appLocalePreference, AppLocalePreference.english);
    expect(restored.locale, const Locale('en', 'US'));
    restored.dispose();
  });

  test('invalid locale preference falls back to system and reset removes it',
      () async {
    SharedPreferences.setMockInitialValues({
      'appLocalePreference': 'not-supported',
      'paginationEnabled': true,
    });
    final settings = SettingsProvider();
    await _waitForInitialLoad(settings);

    expect(settings.appLocalePreference, AppLocalePreference.system);
    expect(settings.locale, isNull);
    expect(settings.paginationEnabled, isTrue);

    await settings.setAppLocalePreference(
      AppLocalePreference.simplifiedChinese,
    );
    expect(settings.locale, const Locale('zh', 'CN'));

    await settings.resetToDefaults();
    expect(settings.appLocalePreference, AppLocalePreference.system);
    expect(settings.locale, isNull);
    expect(settings.paginationEnabled, isTrue);
    expect(
      (await SharedPreferences.getInstance()).containsKey(
        'appLocalePreference',
      ),
      isFalse,
    );
    expect(
      (await SharedPreferences.getInstance()).containsKey(
        'paginationEnabled',
      ),
      isFalse,
    );
    settings.dispose();
  });

  test('explicit system choice is not replaced by late persisted locale',
      () async {
    SharedPreferences.setMockInitialValues({
      'appLocalePreference': AppLocalePreference.english.name,
    });
    final prefs = await SharedPreferences.getInstance();
    final preferences = Completer<SharedPreferences>();
    final fonts = Completer<List<String>>();
    final settings = SettingsProvider(
      preferencesLoader: () => preferences.future,
      systemFontsLoader: () => fonts.future,
    );
    var notifications = 0;
    settings.addListener(() => notifications += 1);

    final saving = settings.setAppLocalePreference(
      AppLocalePreference.system,
    );
    expect(settings.appLocalePreference, AppLocalePreference.system);
    expect(notifications, 1);

    preferences.complete(prefs);
    await saving;
    expect(settings.appLocalePreference, AppLocalePreference.system);
    expect(
      prefs.getString('appLocalePreference'),
      AppLocalePreference.system.name,
    );

    fonts.complete(const ['Test Font']);
    await Future<void>.delayed(Duration.zero);
    expect(settings.availableFonts, const ['Test Font']);
    settings.dispose();
  });

  test('late font discovery does not notify a disposed provider', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final fonts = Completer<List<String>>();
    final settings = SettingsProvider(
      preferencesLoader: () async => prefs,
      systemFontsLoader: () => fonts.future,
    );
    await _waitForInitialLoad(settings);

    settings.dispose();
    fonts.complete(const ['Late Font']);
    await Future<void>.delayed(Duration.zero);

    expect(settings.availableFonts, isEmpty);
  });
}

Future<void> _waitForInitialLoad(SettingsProvider settings) {
  final completer = Completer<void>();
  void listener() {
    if (!completer.isCompleted) completer.complete();
  }

  settings.addListener(listener);
  return completer.future.timeout(const Duration(seconds: 10)).whenComplete(
        () => settings.removeListener(listener),
      );
}
