import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/models/log_entry.dart';

void main() {
  group('LogEntry', () {
    test('preserves provided sync id', () {
      final entry = LogEntry(
        id: 'log-abc-123',
        time: '2026-07-09T14:30:00Z',
        controller: 'BG5CRL',
        callsign: 'BA4AAA',
        report: '59',
        qth: '上海',
        device: 'ICOM 7300',
        power: '100W',
        antenna: 'Dipole',
        height: '10m',
      );
      expect(entry.id, 'log-abc-123');
    });

    test('generates id when not provided', () {
      final entry = LogEntry(
        time: '14:30',
        controller: 'BG5CRL',
        callsign: 'BA4AAA',
        report: '59',
        qth: '上海',
        device: 'ICOM 7300',
        power: '100W',
        antenna: 'Dipole',
        height: '10m',
      );
      expect(entry.id.isNotEmpty, true);
      expect(entry.id.startsWith('log-'), true);
    });

    test('round-trips JSON', () {
      final entry = LogEntry(
        id: 'log-abc-123',
        time: '14:30',
        controller: 'BG5CRL',
        callsign: 'BA4AAA',
        report: '59',
        rstRcvd: '57',
        qth: '上海',
        device: 'ICOM 7300',
        power: '100W',
        antenna: 'Dipole',
        height: '10m',
      );
      final json = entry.toJson();
      expect((json['rstSent'], json['rstRcvd']), ('59', '57'));
      final restored = LogEntry.fromJson(json);
      expect(restored.id, entry.id);
      expect(restored.callsign, entry.callsign);
      expect(restored.rstRcvd, entry.rstRcvd);
      expect(restored.report, entry.report);
      expect(entry.copyWith().rstRcvd, '57');
      expect(entry.copyWith(rstRcvd: '46').rstRcvd, '46');
    });

    test('accepts canonical and snake-case RST field names', () {
      final canonical = LogEntry.fromJson({
        'time': '14:30',
        'controller': 'BG5CRL',
        'callsign': 'BA4AAA',
        'rstSent': '58',
        'rstRcvd': '47',
      });
      final snakeCase = LogEntry.fromMap({
        'time': '14:31',
        'controller': 'BG5CRL',
        'callsign': 'BA4BBB',
        'rst_sent': '56',
        'rst_rcvd': '45',
      });

      expect((canonical.report, canonical.rstRcvd), ('58', '47'));
      expect((snakeCase.report, snakeCase.rstRcvd), ('56', '45'));
    });
  });
}
