import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/utils/log_time.dart';

void main() {
  test('blank submission captures one full UTC timestamp including seconds',
      () {
    final capturedAt = DateTime.parse('2026-07-13T20:42:37.456+08:00');

    final submitted = resolveLogTimeForSubmission(
      '  ',
      capturedAt: capturedAt,
    );

    expect(submitted, '2026-07-13T12:42:37.456Z');
    expect(DateTime.parse(submitted).isUtc, isTrue);
  });

  test('manual clock input remains unchanged for submission', () {
    expect(
      resolveLogTimeForSubmission(
        ' 20:42 ',
        capturedAt: DateTime.utc(2026, 7, 13, 12, 42, 37),
      ),
      '20:42',
    );
  });

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
    expect(formatLogTimeForDisplay(''), '');
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

  test('ISO timestamps with a space or lowercase t display locally', () {
    const canonical = '2026-07-13T12:30:00Z';
    final expected = formatLogTimeForDisplay(canonical);

    expect(formatLogTimeForDisplay('2026-07-13 12:30:00Z'), expected);
    expect(formatLogTimeForDisplay('2026-07-13t12:30:00Z'), expected);
  });
}
