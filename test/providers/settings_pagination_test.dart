import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/models/export_settings.dart';
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

  test('table page size defaults to 10 and falls back on illegal stored value',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'tablePageSize': 3,
    });
    final settings = SettingsProvider();
    await _waitForInitialLoad(settings);

    expect(settings.tablePageSize, 10);
    await settings.setTablePageSize(12);
    expect(settings.tablePageSize, 10);
    settings.dispose();

    SharedPreferences.setMockInitialValues(<String, Object>{
      'tablePageSize': 100,
    });
    final restored = SettingsProvider();
    await _waitForInitialLoad(restored);
    expect(restored.tablePageSize, 10);
    restored.dispose();
  });

  test('table page size persists across load and resets to 10', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = SettingsProvider();
    await _waitForInitialLoad(settings);

    expect(settings.tablePageSize, 10);
    await settings.setTablePageSize(25);
    expect(settings.tablePageSize, 25);
    settings.dispose();

    final restored = SettingsProvider();
    await _waitForInitialLoad(restored);
    expect(restored.tablePageSize, 25);

    await restored.resetToDefaults();
    expect(restored.tablePageSize, 10);
    expect(
      (await SharedPreferences.getInstance()).containsKey('tablePageSize'),
      isFalse,
    );
    restored.dispose();
  });

  test('auto-append-W defaults on, preserves opt-out, and resets on', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = SettingsProvider();
    await _waitForInitialLoad(settings);

    expect(settings.autoAppendPowerW, isTrue);
    await settings.setAutoAppendPowerW(false);
    expect(settings.autoAppendPowerW, isFalse);
    settings.dispose();

    final restored = SettingsProvider();
    await _waitForInitialLoad(restored);
    expect(restored.autoAppendPowerW, isFalse);

    await restored.resetToDefaults();
    expect(restored.autoAppendPowerW, isTrue);
    expect(
      (await SharedPreferences.getInstance()).containsKey('autoAppendPowerW'),
      isFalse,
    );
    restored.dispose();
  });

  test('migrates old session-title export defaults only once', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'exportSettings': json.encode(<String, Object>{
        'useSessionTitleAsHeader': false,
        'useSessionTitleAsFileName': false,
      }),
    });
    final settings = SettingsProvider();
    await _waitForInitialLoad(settings);

    expect(settings.exportSettings.useSessionTitleAsHeader, isTrue);
    expect(settings.exportSettings.useSessionTitleAsFileName, isTrue);
    expect(
      (await SharedPreferences.getInstance())
          .getBool('sessionTitleExportDefaultsV1'),
      isTrue,
    );

    await settings.updateExportSettings(ExportSettings(
      useSessionTitleAsHeader: false,
      useSessionTitleAsFileName: false,
    ));
    settings.dispose();

    final restored = SettingsProvider();
    await _waitForInitialLoad(restored);
    expect(restored.exportSettings.useSessionTitleAsHeader, isFalse);
    expect(restored.exportSettings.useSessionTitleAsFileName, isFalse);
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
