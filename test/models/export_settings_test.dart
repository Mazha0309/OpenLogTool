import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/models/export_settings.dart';

void main() {
  test('session title export options default on', () {
    final settings = ExportSettings();
    expect(settings.useSessionTitleAsHeader, isTrue);
    expect(settings.useSessionTitleAsFileName, isTrue);
  });

  test('legacy JSON adopts defaults while explicit opt-outs survive', () {
    final migrated = ExportSettings.fromJson(const <String, dynamic>{});
    expect(migrated.useSessionTitleAsHeader, isTrue);
    expect(migrated.useSessionTitleAsFileName, isTrue);

    final optedOut = ExportSettings.fromJson(const <String, dynamic>{
      'useSessionTitleAsHeader': false,
      'useSessionTitleAsFileName': false,
    });
    expect(optedOut.useSessionTitleAsHeader, isFalse);
    expect(optedOut.useSessionTitleAsFileName, isFalse);
  });
}
