import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/models/dictionary_item.dart';
import 'package:openlogtool/models/sync_callsign_qth_record.dart';
import 'package:openlogtool/models/sync_history_record.dart';

void main() {
  group('sync-capable models', () {
    test('DictionaryItem round-trips source device id', () {
      final item = DictionaryItem.fromMap({
        'id': 1,
        'raw': 'IC-705',
        'pinyin': 'ic',
        'abbreviation': '705',
        'sync_id': 'dict-001',
        'type': 'device',
        'created_at': '2026-04-21T09:00:00.000Z',
        'updated_at': '2026-04-21T09:10:00.000Z',
        'source_device_id': 'device-001',
      });

      expect(item.sourceDeviceId, 'device-001');
      expect(item.toMap()['source_device_id'], 'device-001');
      expect(item.toJson()['sourceDeviceId'], 'device-001');
    });

    test('SyncHistoryRecord round-trips source device id', () {
      final item = SyncHistoryRecord.fromMap({
        'id': 1,
        'sync_id': 'history-001',
        'name': 'archive',
        'logs_data': '[]',
        'log_count': 0,
        'created_at': '2026-04-21T09:00:00.000Z',
        'updated_at': '2026-04-21T09:10:00.000Z',
        'source_device_id': 'device-001',
      });

      expect(item.sourceDeviceId, 'device-001');
      expect(item.toMap()['source_device_id'], 'device-001');
      expect(item.toJson()['sourceDeviceId'], 'device-001');
    });

    test('SyncCallsignQthRecord round-trips source device id', () {
      final item = SyncCallsignQthRecord.fromMap({
        'id': 1,
        'sync_id': 'cqth-001',
        'callsign': 'BG5CRL',
        'qth': 'Shanghai',
        'recorded_at': '2026-04-21T09:00:00.000Z',
        'created_at': '2026-04-21T09:00:00.000Z',
        'updated_at': '2026-04-21T09:10:00.000Z',
        'source_device_id': 'device-001',
      });

      expect(item.sourceDeviceId, 'device-001');
      expect(item.toMap()['source_device_id'], 'device-001');
      expect(item.toJson()['sourceDeviceId'], 'device-001');
    });
  });
}
