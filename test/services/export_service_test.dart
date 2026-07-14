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
      expect(_cellText(rows[3], 2), 'A1');
      expect(_cellText(rows[4], 2), 'BG5BBB');
      expect(_cellText(rows[5], 2), 'B1');
      expect(_cellText(rows[6], 2), 'BG5AAA');
      expect(_cellText(rows[6], 1), '19:30');
      expect(_cellText(rows[7], 2), 'A2');
    });

    test('uses controller section rows instead of a repeated controller column',
        () {
      final bytes = ExportService.generateExcelBytes(
        [
          _log(
            time: '19:00',
            controller: 'BG5AAA',
            callsign: 'BG5BBB',
            rstSent: '58',
            rstRcvd: '47',
            qth: '杭州滨江浦沿',
            device: 'ICOM IC-9700',
            power: '25W',
            antenna: '华鸿 1.2米玻璃钢',
            height: '30米',
            remarks: '测试备注',
          ),
        ],
        ExportSettings(showFooter: false),
        DateTime(2026, 7, 13, 19),
      );

      final sheet = excel_lib.Excel.decodeBytes(bytes!).tables['点名记录']!;
      expect(
        List.generate(11, (index) => _cellText(sheet.rows[1], index)),
        ['#', '时间', '呼号', 'RST发', 'RST收', 'QTH', '设备', '功率', '天线', '高度', '备注'],
      );
      expect(_cellText(sheet.rows[2], 0), '点名主控:');
      expect(_cellText(sheet.rows[2], 2), 'BG5AAA');
      expect(
        List.generate(11, (index) => _cellText(sheet.rows[3], index)),
        [
          '1',
          '19:00',
          'BG5BBB',
          '58',
          '47',
          '杭州滨江浦沿',
          'ICOM IC-9700',
          '25W',
          '华鸿 1.2米玻璃钢',
          '30米',
          '测试备注',
        ],
      );

      const expectedWidths = <double>[10, 8, 10, 8, 8, 22, 20, 7, 22, 7, 10];
      for (var column = 0; column < expectedWidths.length; column++) {
        expect(
          sheet.getColumnWidth(column),
          closeTo(expectedWidths[column], 0.01),
          reason: 'column $column',
        );
      }
    });

    test('exports canonical UTC timestamps in the device timezone', () {
      final localTime = DateTime(2026, 7, 13, 20, 30);
      final bytes = ExportService.generateExcelBytes(
        [
          _log(
            time: localTime.toUtc().toIso8601String(),
            controller: 'BG5AAA',
            callsign: 'A1',
          ),
        ],
        ExportSettings(showFooter: false),
        localTime,
      );

      final rows = excel_lib.Excel.decodeBytes(bytes!).tables['点名记录']!.rows;
      final logRow = rows.singleWhere((row) => _cellText(row, 2) == 'A1');
      final controllerRow =
          rows.singleWhere((row) => _cellText(row, 0) == '点名主控:');

      expect(_cellText(logRow, 1), '20:30');
      expect(_cellText(controllerRow, 1), '20:30');
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
  String rstSent = '59',
  String rstRcvd = '',
  String qth = '',
  String device = '',
  String power = '',
  String antenna = '',
  String height = '',
  String remarks = '',
}) {
  return LogEntry(
    time: time,
    controller: controller,
    callsign: callsign,
    report: rstSent,
    rstRcvd: rstRcvd,
    qth: qth,
    device: device,
    power: power,
    antenna: antenna,
    height: height,
    remarks: remarks,
  );
}
