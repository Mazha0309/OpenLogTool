import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/utils/personal_cloud_merge.dart';

void main() {
  test('merges independent record changes without a conflict', () {
    final base = _records(
      sessions: [_session(title: 'Original')],
      logs: [_log(callsign: 'BG5AAA', remarks: null)],
    );
    final local = _records(
      sessions: [_session(title: 'Local title')],
      logs: [_log(callsign: 'BG5AAA', remarks: null)],
    );
    final remote = _records(
      sessions: [_session(title: 'Original')],
      logs: [_log(callsign: 'BG5AAA', remarks: 'remote note')],
    );

    final result = mergePersonalCloudSnapshots(
      dataset: PersonalCloudDataset.records,
      base: base,
      local: local,
      remote: remote,
    );

    expect(result.conflicts, isEmpty);
    expect(
        (result.snapshot['sessions'] as List).single['title'], 'Local title');
    expect((result.snapshot['logs'] as List).single['remarks'], 'remote note');
  });

  test('reports and resolves a same-field edit conflict', () {
    final base = _records(sessions: [_session(title: 'Original')]);
    final local = _records(sessions: [_session(title: 'Local')]);
    final remote = _records(sessions: [_session(title: 'Remote')]);

    final preview = mergePersonalCloudSnapshots(
      dataset: PersonalCloudDataset.records,
      base: base,
      local: local,
      remote: remote,
    );

    expect(preview.conflicts, hasLength(1));
    expect(preview.conflicts.single.fieldGroup, 'title');
    final resolved = mergePersonalCloudSnapshots(
      dataset: PersonalCloudDataset.records,
      base: base,
      local: local,
      remote: remote,
      resolutions: {
        preview.conflicts.single.conflictId: PersonalCloudConflictChoice.remote,
      },
    );
    expect(resolved.conflicts, isEmpty);
    expect((resolved.snapshot['sessions'] as List).single['title'], 'Remote');
  });

  test('merges independent dictionary identities', () {
    final base = _dictionary([]);
    final local = _dictionary([_dictionaryItem('device', 'IC-705')]);
    final remote = _dictionary([_dictionaryItem('antenna', 'X520')]);

    final result = mergePersonalCloudSnapshots(
      dataset: PersonalCloudDataset.dictionaries,
      base: base,
      local: local,
      remote: remote,
    );

    expect(result.conflicts, isEmpty);
    final items = result.snapshot['items'] as List;
    expect(items.map((item) => item['raw']), ['X520', 'IC-705']);
  });

  test('does not silently keep an orphan log after its session is removed', () {
    final base = _records(
      sessions: [_session()],
      logs: [_log(callsign: 'BG5AAA', remarks: null)],
    );
    final local = _records(sessions: const [], logs: const []);
    final remote = _records(
      sessions: [_session()],
      logs: [_log(callsign: 'BG5AAA', remarks: 'edited')],
    );

    final result = mergePersonalCloudSnapshots(
      dataset: PersonalCloudDataset.records,
      base: base,
      local: local,
      remote: remote,
    );

    expect(result.conflicts, isNotEmpty);
    expect(
      result.conflicts.any(
        (conflict) =>
            conflict.kind == 'deleteVsEdit' || conflict.kind == 'parentDeleted',
      ),
      isTrue,
    );
  });

  test('soft session deletion conflicts with a remote log edit', () {
    final base = _records(
      sessions: [_session()],
      logs: [_log(callsign: 'BG5AAA', remarks: null)],
    );
    final local = _records(
      sessions: [
        _session(deletedAt: '2026-07-19T12:30:00.000Z'),
      ],
      logs: [_log(callsign: 'BG5AAA', remarks: null)],
    );
    final remote = _records(
      sessions: [_session()],
      logs: [_log(callsign: 'BG5AAA', remarks: 'remote edit')],
    );

    final preview = mergePersonalCloudSnapshots(
      dataset: PersonalCloudDataset.records,
      base: base,
      local: local,
      remote: remote,
    );
    expect(
      preview.conflicts.where((conflict) => conflict.kind == 'parentDeleted'),
      hasLength(1),
    );

    final keepLocal = mergePersonalCloudSnapshots(
      dataset: PersonalCloudDataset.records,
      base: base,
      local: local,
      remote: remote,
      resolutions: _resolveAll(
        preview,
        PersonalCloudConflictChoice.local,
      ),
    );
    expect(keepLocal.conflicts, isEmpty);
    expect(
      (keepLocal.snapshot['sessions'] as List).single['deleted_at'],
      isNotNull,
    );
    expect(
      (keepLocal.snapshot['logs'] as List).single['remarks'],
      isNull,
    );

    final keepRemote = mergePersonalCloudSnapshots(
      dataset: PersonalCloudDataset.records,
      base: base,
      local: local,
      remote: remote,
      resolutions: _resolveAll(
        preview,
        PersonalCloudConflictChoice.remote,
      ),
    );
    expect(keepRemote.conflicts, isEmpty);
    expect(
      (keepRemote.snapshot['sessions'] as List).single['deleted_at'],
      isNull,
    );
    expect(
      (keepRemote.snapshot['logs'] as List).single['remarks'],
      'remote edit',
    );
  });

  test('hard session deletion resolutions never produce orphan logs', () {
    final base = _records(
      sessions: [_session()],
      logs: [_log(callsign: 'BG5AAA', remarks: null)],
    );
    final local = _records(sessions: const [], logs: const []);
    final remote = _records(
      sessions: [_session()],
      logs: [_log(callsign: 'BG5AAA', remarks: 'remote edit')],
    );

    final preview = mergePersonalCloudSnapshots(
      dataset: PersonalCloudDataset.records,
      base: base,
      local: local,
      remote: remote,
    );
    expect(
      preview.conflicts.any((conflict) => conflict.kind == 'parentDeleted'),
      isTrue,
    );

    final keepLocal = mergePersonalCloudSnapshots(
      dataset: PersonalCloudDataset.records,
      base: base,
      local: local,
      remote: remote,
      resolutions: _resolveAll(
        preview,
        PersonalCloudConflictChoice.local,
      ),
    );
    expect(keepLocal.conflicts, isEmpty);
    expect(keepLocal.snapshot['sessions'], isEmpty);
    expect(keepLocal.snapshot['logs'], isEmpty);

    final keepRemote = mergePersonalCloudSnapshots(
      dataset: PersonalCloudDataset.records,
      base: base,
      local: local,
      remote: remote,
      resolutions: _resolveAll(
        preview,
        PersonalCloudConflictChoice.remote,
      ),
    );
    expect(keepRemote.conflicts, isEmpty);
    final sessions = keepRemote.snapshot['sessions'] as List;
    final logs = keepRemote.snapshot['logs'] as List;
    expect(sessions, hasLength(1));
    expect(logs, hasLength(1));
    expect(logs.single['session_id'], sessions.single['session_id']);
    expect(logs.single['remarks'], 'remote edit');
  });
}

Map<String, PersonalCloudConflictChoice> _resolveAll(
  PersonalCloudMergeResult preview,
  PersonalCloudConflictChoice choice,
) =>
    {
      for (final conflict in preview.conflicts) conflict.conflictId: choice,
    };

Map<String, Object?> _records({
  List<Map<String, Object?>> sessions = const [],
  List<Map<String, Object?>> logs = const [],
}) =>
    {
      'version': 1,
      'exportedAt': '2026-07-19T12:00:00.000Z',
      'sessions': sessions,
      'logs': logs,
    };

Map<String, Object?> _session({
  String title = 'Net',
  String? deletedAt,
}) =>
    {
      'session_id': 'session-1',
      'title': title,
      'status': 'active',
      'created_at': '2026-07-19T10:00:00.000Z',
      'updated_at': '2026-07-19T12:00:00.000Z',
      'closed_at': null,
      'deleted_at': deletedAt,
    };

Map<String, Object?> _log({
  required String callsign,
  required String? remarks,
}) =>
    {
      'sync_id': 'log-1',
      'session_id': 'session-1',
      'time': '2026-07-19T11:00:05.000Z',
      'controller': 'BG5CRL',
      'callsign': callsign,
      'rst_sent': '59',
      'rst_rcvd': '59',
      'qth': null,
      'device': null,
      'power': null,
      'antenna': null,
      'height': null,
      'remarks': remarks,
      'created_at': '2026-07-19T11:00:05.000Z',
      'updated_at': '2026-07-19T12:00:00.000Z',
      'deleted_at': null,
      'source_device_id': 'test-device',
    };

Map<String, Object?> _dictionary(List<Map<String, Object?>> items) => {
      'version': 1,
      'exportedAt': '2026-07-19T12:00:00.000Z',
      'items': items,
    };

Map<String, Object?> _dictionaryItem(String type, String raw) => {
      'dictType': type,
      'raw': raw,
      'origin': 'user',
      'state': 'active',
      'pinyin': null,
      'abbreviation': null,
    };
