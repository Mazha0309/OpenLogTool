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
        qth: '上海',
        device: 'ICOM 7300',
        power: '100W',
        antenna: 'Dipole',
        height: '10m',
      );
      entry.rstRcvd = '57';
      final json = entry.toJson();
      json['rstRcvd'] = entry.rstRcvd;
      final restored = LogEntry.fromJson(json);
      restored.rstRcvd = json['rstRcvd'] as String;
      expect(restored.id, entry.id);
      expect(restored.callsign, entry.callsign);
      expect(restored.rstRcvd, entry.rstRcvd);
    });
  });
}
