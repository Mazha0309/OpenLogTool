import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/models/database_status.dart';

void main() {
  test('parses semantic database status independently from raw table counts',
      () {
    final status = DatabaseStatus.parse(jsonEncode(_statusFixture));

    expect(status.statusVersion, 2);
    expect(status.schemaVersion, 7);
    expect(status.backupFormatVersion, 7);
    expect(status.localContent.sessions.available, 6);
    expect(status.localContent.logs.active, 615);
    expect(status.localContent.activeDictionaryItems, 304);
    expect(status.localContent.deletedDictionaryItems, 2);
    expect(status.collaboration.hasPendingWork, isTrue);
    expect(status.tables.single.name, 'sync_outbox');
    expect(status.tables.single.rowCount, 0);
  });

  test('rejects malformed semantic counts instead of presenting raw JSON', () {
    final invalid = Map<String, dynamic>.from(_statusFixture);
    invalid['collaboration'] = {
      ...invalid['collaboration'] as Map<String, dynamic>,
      'pendingOutbox': -1,
    };

    expect(
      () => DatabaseStatus.fromJson(invalid),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('collaboration.pendingOutbox'),
        ),
      ),
    );
  });
}

final Map<String, dynamic> _statusFixture = {
  'statusVersion': 2,
  'schemaVersion': 7,
  'backupFormatVersion': 7,
  'collectedAt': '2026-07-19T12:34:56Z',
  'localContent': {
    'sessions': {'active': 1, 'closed': 3, 'archived': 2, 'deleted': 1},
    'logs': {'active': 615, 'deleted': 4},
    'dictionaries': {
      'device': {'active': 100, 'deleted': 1},
      'antenna': {'active': 80, 'deleted': 0},
      'qth': {'active': 64, 'deleted': 1},
      'callsign': {'active': 60, 'deleted': 0},
    },
  },
  'collaboration': {
    'bindings': 2,
    'pendingOutbox': 1,
    'openConflicts': 0,
    'offlineRecords': 0,
    'draftCaches': 1,
  },
  'tables': [
    {'name': 'sync_outbox', 'rowCount': 0},
  ],
};
