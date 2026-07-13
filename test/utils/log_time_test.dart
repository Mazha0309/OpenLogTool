import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/utils/log_time.dart';

void main() {
  test('local wall-clock time round-trips through canonical UTC storage', () {
    final localReference = DateTime(2026, 7, 13, 16, 49);

    final stored = normalizeLogTimeForStorage(
      '16:49',
      reference: localReference,
    );

    expect(DateTime.parse(stored).isUtc, isTrue);
    expect(formatLogTimeForDisplay(stored), '16:49');
    expect(
      formatLogTimeForDisplay(stored, includeDate: true),
      '2026-07-13 16:49',
    );
  });

  test('legacy wall-clock values remain readable', () {
    expect(formatLogTimeForDisplay('8:05'), '08:05');
    expect(formatLogTimeForDisplay('16:49'), '16:49');
    expect(isValidLogTimeInput('16:49'), isTrue);
    expect(isValidLogTimeInput('24:00'), isFalse);
    expect(isValidLogTimeInput('not-a-time'), isFalse);
  });

  test('an existing timestamp keeps its instant and displays locally', () {
    final local = DateTime(2026, 7, 13, 20, 30);
    final stored = local.toUtc().toIso8601String();

    expect(formatLogTimeForDisplay(stored), '20:30');
    expect(normalizeLogTimeForStorage(stored), stored);
  });
}
