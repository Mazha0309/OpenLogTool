import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('desktop sidebar preference defaults expanded and persists', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await _waitForInitialLoad(settings);

    expect(settings.primarySidebarExpanded, isTrue);
    await settings.setPrimarySidebarExpanded(false);
    expect(settings.primarySidebarExpanded, isFalse);
    expect(
      (await SharedPreferences.getInstance()).getBool(
        'primarySidebarExpanded',
      ),
      isFalse,
    );
    settings.dispose();

    final restored = SettingsProvider();
    await _waitForInitialLoad(restored);
    expect(restored.primarySidebarExpanded, isFalse);
    restored.dispose();
  });

  test('workbench width limit defaults on and persists', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await _waitForInitialLoad(settings);

    expect(settings.limitWorkbenchWidth, isTrue);
    await settings.setLimitWorkbenchWidth(false);
    expect(settings.limitWorkbenchWidth, isFalse);
    expect(
      (await SharedPreferences.getInstance()).getBool(
        'limitWorkbenchWidth',
      ),
      isFalse,
    );
    settings.dispose();

    final restored = SettingsProvider();
    await _waitForInitialLoad(restored);
    expect(restored.limitWorkbenchWidth, isFalse);

    await restored.resetToDefaults();
    expect(restored.limitWorkbenchWidth, isTrue);
    expect(
      (await SharedPreferences.getInstance()).containsKey(
        'limitWorkbenchWidth',
      ),
      isFalse,
    );
    restored.dispose();
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
