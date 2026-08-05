import 'dart:typed_data';

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

  group('ExportService web download metadata', () {
    test('web download uses exact filename and json mime', () {
      final meta = ExportService.webDownloadMeta(
        '点名记录_2026-08-05.json',
        Uint8List.fromList([1, 2, 3]),
        mimeType: 'application/json',
      );
      expect(meta.filename, '点名记录_2026-08-05.json');
      expect(meta.mimeType, 'application/json');
      expect(meta.bytes, [1, 2, 3]);
    });

    test('appends extension when filename lacks it', () {
      final meta = ExportService.webDownloadMeta(
        '点名记录',
        Uint8List.fromList([1]),
        mimeType: 'application/json',
        extension: '.json',
      );
      expect(meta.filename, '点名记录.json');
    });

    test('does not append extension when already present', () {
      final meta = ExportService.webDownloadMeta(
        '点名记录.xlsx',
        Uint8List.fromList([1]),
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        extension: '.xlsx',
      );
      expect(meta.filename, '点名记录.xlsx');
    });
  });
}
