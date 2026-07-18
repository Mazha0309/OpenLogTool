import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/models/database_backup_summary.dart';

void main() {
  test('previews local and collaboration backup contents', () {
    final summary = DatabaseBackupSummary.parse(jsonEncode({
      'version': 6,
      'exportedAt': '2026-07-17T08:00:00Z',
      'sessions': [
        {'session_id': 'one'},
        {'session_id': 'two'},
        {'session_id': 'deleted', 'deleted_at': '2026-07-17T07:00:00Z'},
      ],
      'logs': [
        {'sync_id': 'one'},
        {'sync_id': 'two'},
        {'sync_id': 'three'},
        {'sync_id': 'deleted', 'deleted_at': '2026-07-17T07:00:00Z'},
      ],
      'dictionary_items': [
        {'sync_id': 'one'},
        {'sync_id': 'deleted', 'deleted_at': '2026-07-17T07:00:00Z'},
      ],
      'settings': [],
      'oplog': [],
      'collaboration_bindings': [
        {'session_id': 'one'},
      ],
      'entity_shadows': [],
      'sync_outbox': [
        {'mutation_id': 'one'},
        {'mutation_id': 'two'},
      ],
      'applied_events': [],
      'sync_conflicts': [],
      'collaboration_live_drafts': [],
      'collaboration_offline_records': [
        {'mutation_id': 'pending', 'state': 'pending'},
        {'mutation_id': 'resolved', 'state': 'resolved'},
        {'mutation_id': 'discarded', 'state': 'discarded'},
      ],
    }));

    expect(summary.formatVersion, 6);
    expect(
        summary.exportedAt, DateTime.parse('2026-07-17T08:00:00Z').toLocal());
    expect(summary.sessionCount, 2);
    expect(summary.logCount, 3);
    expect(summary.dictionaryItemCount, 1);
    expect(summary.collaborationBindingCount, 1);
    expect(summary.pendingSyncCount, 3);
    expect(summary.containsCollaborationData, isTrue);
  });

  test('rejects a non-backup object before destructive confirmation', () {
    expect(
      () => DatabaseBackupSummary.parse('{"version":6,"sessions":[]}'),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('DATABASE_BACKUP_INVALID_TABLE'),
        ),
      ),
    );
  });

  test('rejects a newer backup format before destructive confirmation', () {
    expect(
      () => DatabaseBackupSummary.parse('{"version":8}'),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'DATABASE_BACKUP_INVALID_VERSION',
        ),
      ),
    );
  });

  test('ignores a damaged retired QTH cache in a legacy backup', () {
    final summary = DatabaseBackupSummary.parse(jsonEncode({
      'version': 1,
      'sessions': [],
      'logs': [],
      'dictionary_items': [],
      'settings': [],
      'oplog': [],
      'callsign_qth_history': 'retired cache is not user data',
    }));

    expect(summary.formatVersion, 1);
    expect(summary.sessionCount, 0);
    expect(summary.logCount, 0);
  });
}
