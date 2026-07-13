import 'package:excel/excel.dart' as excel_lib;
import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/models/export_settings.dart';
import 'package:openlogtool/models/log_entry.dart';
import 'package:openlogtool/services/export_service.dart';

void main() {
  group('ExportService.generateExcelBytes', () {
    test('creates a new timed section when a controller appears again later',
        () {
      final logs = [
        _log(time: '2026-07-13T19:00:00', controller: 'BG5AAA', callsign: 'A1'),
        _log(time: '2026-07-13T19:05:00', controller: 'BG5BBB', callsign: 'B1'),
        _log(time: '2026-07-13T19:30:00', controller: 'BG5AAA', callsign: 'A2'),
      ];

      final bytes = ExportService.generateExcelBytes(
        logs,
        ExportSettings(showFooter: false),
        DateTime(2026, 7, 13, 19),
      );

      expect(bytes, isNotNull);
      final sheet = excel_lib.Excel.decodeBytes(bytes!).tables['点名记录']!;
      final rows = sheet.rows;
      final controllerRows =
          rows.where((row) => _cellText(row, 0) == '点名主控:').toList();

      expect(controllerRows, hasLength(3));
      expect(
        controllerRows.where((row) => _cellText(row, 2) == 'BG5AAA'),
        hasLength(2),
      );
      expect(
        controllerRows.where((row) => _cellText(row, 2) == 'BG5BBB'),
        hasLength(1),
      );

      // A → B → A preserves natural order and starts a fresh timed A block.
      expect(_cellText(rows[2], 2), 'BG5AAA');
      expect(_cellText(rows[3], 3), 'A1');
      expect(_cellText(rows[4], 2), 'BG5BBB');
      expect(_cellText(rows[5], 3), 'B1');
      expect(_cellText(rows[6], 2), 'BG5AAA');
      expect(_cellText(rows[6], 1), '19:30');
      expect(_cellText(rows[7], 3), 'A2');
    });

    test('uses the current session title when the option is enabled', () {
      final bytes = ExportService.generateExcelBytes(
        [_log(time: '19:00', controller: 'BG5AAA', callsign: 'A1')],
        ExportSettings(
          headerText: '{yyyy}-fallback',
          useSessionTitleAsHeader: true,
          showFooter: false,
        ),
        DateTime(2026, 7, 13),
        sessionTitle: '  Sunday Net  ',
      );

      final sheet = excel_lib.Excel.decodeBytes(bytes!).tables['点名记录']!;
      expect(_cellText(sheet.rows[0], 0), 'Sunday Net');
    });

    test('falls back to the header template when the session title is blank',
        () {
      final bytes = ExportService.generateExcelBytes(
        [_log(time: '19:00', controller: 'BG5AAA', callsign: 'A1')],
        ExportSettings(
          headerText: '{yyyy}-fallback',
          useSessionTitleAsHeader: true,
          showFooter: false,
        ),
        DateTime(2026, 7, 13),
        sessionTitle: '   ',
      );

      final sheet = excel_lib.Excel.decodeBytes(bytes!).tables['点名记录']!;
      expect(_cellText(sheet.rows[0], 0), '2026-fallback');
    });

    test('keeps the header template when the option is disabled', () {
      final bytes = ExportService.generateExcelBytes(
        [_log(time: '19:00', controller: 'BG5AAA', callsign: 'A1')],
        ExportSettings(
          headerText: '{yyyy}-template',
          showFooter: false,
        ),
        DateTime(2026, 7, 13),
        sessionTitle: 'Sunday Net',
      );

      final sheet = excel_lib.Excel.decodeBytes(bytes!).tables['点名记录']!;
      expect(_cellText(sheet.rows[0], 0), '2026-template');
    });
  });

  test('ExportSettings persists the session-title header option', () {
    final encoded = ExportSettings(useSessionTitleAsHeader: true).toJson();
    final decoded = ExportSettings.fromJson(encoded);

    expect(decoded.useSessionTitleAsHeader, isTrue);
    expect(ExportSettings.fromJson(const {}).useSessionTitleAsHeader, isFalse);
  });

  test('native JSON import preserves separate RST sent and received values',
      () {
    const source = '''
      [{
        "time": "19:00",
        "controller": "BG5AAA",
        "callsign": "BG5BBB",
        "rstSent": "58",
        "rstRcvd": "47"
      }]
    ''';

    final log = parseJsonImport(source).logs.single;

    expect((log.report, log.rstRcvd), ('58', '47'));
  });
}

String _cellText(List<excel_lib.Data?> row, int column) {
  if (column >= row.length) return '';
  return row[column]?.value?.toString() ?? '';
}

LogEntry _log({
  required String time,
  required String controller,
  required String callsign,
}) {
  return LogEntry(
    time: time,
    controller: controller,
    callsign: callsign,
    report: '59',
    qth: '',
    device: '',
    power: '',
    antenna: '',
    height: '',
  );
}
