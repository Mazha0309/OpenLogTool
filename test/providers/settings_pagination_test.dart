import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('pagination defaults on, preserves opt-out, and resets on', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = SettingsProvider();
    await _waitForInitialLoad(settings);

    expect(settings.paginationEnabled, isTrue);
    await settings.setPaginationEnabled(false);
    expect(settings.paginationEnabled, isFalse);
    settings.dispose();

    final restored = SettingsProvider();
    await _waitForInitialLoad(restored);
    expect(restored.paginationEnabled, isFalse);

    await restored.resetToDefaults();
    expect(restored.paginationEnabled, isTrue);
    expect(
      (await SharedPreferences.getInstance()).containsKey(
        'paginationEnabled',
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
