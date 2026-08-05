import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/services/export_service.dart';

void main() {
  group('ExportService.generateFileName', () {
    final now = DateTime(2026, 8, 5, 14, 30, 45);

    test('replaces all time placeholders', () {
      final name = ExportService.generateFileName(
        '{yyyy}-{MM}-{dd}_{HH}{mm}{ss}',
        now,
      );
      expect(name, '2026-08-05_143045');
    });

    test('replaces {session} with the session title', () {
      final name = ExportService.generateFileName(
        '{session}_{yyyy}',
        now,
        sessionTitle: '2026年夏季点名',
      );
      expect(name, '2026年夏季点名_2026');
    });

    test('uses fallback when session title is missing', () {
      final name = ExportService.generateFileName(
        '{session}',
        now,
      );
      expect(name, 'session');
    });

    test('leaves the template unchanged when no placeholder matches', () {
      final name = ExportService.generateFileName('点名记录', now);
      expect(name, '点名记录');
    });

    test('uses the session title directly when the switch is on', () {
      final name = ExportService.generateFileName(
        '点名记录_{yyyy}-{MM}-{dd}',
        now,
        sessionTitle: '2026年夏季点名',
        useSessionTitle: true,
      );
      expect(name, '2026年夏季点名');
    });

    test('falls back to the template when the switch is on but title is blank',
        () {
      final name = ExportService.generateFileName(
        '{yyyy}-{MM}-{dd}',
        now,
        sessionTitle: '   ',
        useSessionTitle: true,
      );
      expect(name, '2026-08-05');
    });

    test('uses the template when the switch is off', () {
      final name = ExportService.generateFileName(
        '{session}_{yyyy}',
        now,
        sessionTitle: '2026年夏季点名',
        useSessionTitle: false,
      );
      expect(name, '2026年夏季点名_2026');
    });
  });
}
