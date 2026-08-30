import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/models/live_draft.dart';

void main() {
  test('parses the exact persisted live-draft and lock contract', () {
    final draft = LiveDraftDto.fromJson(_draftJson());

    expect(draft.draftId, 'draft-1');
    expect(draft.fields['callsign'], 'BG0TEST');
    expect(draft.fields['qth'], '');
    expect(draft.fieldRevisions['callsign'], 2);
    expect(draft.lastUpdatedBy?.username, 'scribe');
    expect(draft.createdAt, DateTime.parse('2026-07-13T08:00:00.000Z'));
    expect(draft.lastUpdatedAt, DateTime.parse('2026-07-13T08:00:01.000Z'));

    final lock = LiveDraftLockDto.fromJson({
      'leaseId': 'lease-1',
      'sessionId': 'session-1',
      'field': 'callsign',
      'userId': 'user-1',
      'username': 'scribe',
      'deviceId': 'device-1',
      'expiresAt': '2026-07-13T08:00:30.000Z',
    });
    expect(lock.sessionId, 'session-1');
    expect(lock.toJson()['sessionId'], 'session-1');
  });

  test('parses commit/discard ordinals and rejects incomplete protocol data',
      () {
    final discard = LiveDraftDiscardResultDto.fromJson({
      'discardedDraftId': 'draft-1',
      'nextDraft': _draftJson(draftId: 'draft-2', version: 2),
      'currentOrdinal': 4,
      'totalRecords': 3,
    });
    expect(discard.currentOrdinal, 4);
    expect(discard.totalRecords, 3);

    final missingCreatedAt = _draftJson()..remove('createdAt');
    expect(
      () => LiveDraftDto.fromJson(missingCreatedAt),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => LiveDraftPatchResultDto.fromJson({
        'draft': _draftJson(),
        'appliedClientSeq': 0,
        'replayed': false,
      }),
      throwsA(isA<FormatException>()),
    );
  });

  test('lock acquisition accepts both legacy and canonical-draft responses',
      () {
    final lockJson = {
      'leaseId': 'lease-1',
      'sessionId': 'session-1',
      'field': 'callsign',
      'userId': 'user-1',
      'username': 'scribe',
      'deviceId': 'device-1',
      'expiresAt': '2026-07-13T08:00:30.000Z',
    };
    final legacy = LiveDraftLockAcquisitionDto.fromJson({'lock': lockJson});
    final enhanced = LiveDraftLockAcquisitionDto.fromJson({
      'lock': lockJson,
      'draft': _draftJson(version: 3),
    });

    expect(legacy.lock.leaseId, 'lease-1');
    expect(legacy.draft, isNull);
    expect(enhanced.draft?.version, 3);
  });

  test('patch response accepts optional consumed lease objects', () {
    final legacy = LiveDraftPatchResultDto.fromJson({
      'draft': _draftJson(version: 2),
      'appliedClientSeq': 1,
      'replayed': false,
    });
    final consumed = LiveDraftPatchResultDto.fromJson({
      'draft': _draftJson(version: 2),
      'appliedClientSeq': 1,
      'replayed': false,
      'releasedLeases': [
        {'field': 'callsign', 'leaseId': 'lease-1'},
      ],
    });

    expect(legacy.releasedLeases, isEmpty);
    expect(consumed.releasedLeases.single.field, 'callsign');
    expect(consumed.releasedLeases.single.leaseId, 'lease-1');
    expect(
      () => LiveDraftPatchResultDto.fromJson({
        'draft': _draftJson(version: 2),
        'appliedClientSeq': 1,
        'replayed': false,
        'releasedLeases': [
          {'field': 'not-a-field', 'leaseId': 'lease-1'},
        ],
      }),
      throwsFormatException,
    );
  });

  test('history preview is ephemeral and reuse only carries station fields',
      () {
    final previewJson = {
      'previewId': 'preview-1',
      'draftId': 'draft-1',
      'deviceId': 'device-1',
      'callsign': 'bg0test',
      'actor': {'userId': 'user-1', 'username': 'scribe'},
      'expiresAt': '2026-07-13T08:00:20.000Z',
      'candidates': [
        {
          'candidateId': 'history-1',
          'sourceTime': '2026-07-12T08:00:00.000Z',
          'qth': '杭州',
          'device': null,
          'power': '5W',
          'antenna': 'DP',
          'height': null,
        },
      ],
    };
    final snapshot = LiveDraftSnapshotDto.fromJson({
      'draft': _draftJson(),
      'locks': const [],
      'currentOrdinal': 1,
      'totalRecords': 0,
      'previousRecord': null,
      'historyPreview': previewJson,
    });

    expect(snapshot.historyPreview?.callsign, 'BG0TEST');
    expect(snapshot.historyPreview?.candidates.single.reusableValues, {
      'qth': '杭州',
      'power': '5W',
      'antenna': 'DP',
    });
    // A preview expires after seconds and must never be persisted in the Rust
    // live-draft recovery cache.
    expect(snapshot.toJson(), isNot(contains('historyPreview')));

    final result = LiveDraftHistoryReuseResultDto.fromJson({
      'draft': _draftJson(version: 2),
      'updatedFields': ['qth', 'power'],
      'releasedLeases': [
        {'field': 'qth', 'leaseId': 'lease-qth'},
      ],
      'locks': const [],
      'historyPreview': null,
      'historyReuse': {
        'previewId': 'preview-1',
        'candidateId': 'history-1',
        'affectedFields': ['qth', 'power'],
      },
    });
    expect(result.updatedFields, {'qth', 'power'});
    expect(result.historyReuse.affectedFields, {'qth', 'power'});
    expect(result.releasedLeases.single.leaseId, 'lease-qth');
    expect(
      () => LiveDraftHistoryReuseDto.fromJson({
        'previewId': 'preview-1',
        'candidateId': 'history-1',
        'affectedFields': ['time'],
      }),
      throwsFormatException,
    );
  });
}

Map<String, Object?> _draftJson({
  String draftId = 'draft-1',
  int version = 1,
}) =>
    {
      'draftId': draftId,
      'sessionId': 'session-1',
      'version': version,
      'fields': {
        'time': '2026-07-13T08:00:00.000Z',
        'controller': 'BG0CTRL',
        'callsign': 'BG0TEST',
        'rstSent': '59',
        'rstRcvd': '59',
        'qth': null,
        'device': null,
        'power': null,
        'antenna': null,
        'height': null,
        'remarks': null,
      },
      'fieldRevisions': {
        'time': 1,
        'controller': 1,
        'callsign': 2,
        'rstSent': 0,
        'rstRcvd': 0,
        'qth': 0,
        'device': 0,
        'power': 0,
        'antenna': 0,
        'height': 0,
        'remarks': 0,
      },
      'lastUpdatedBy': {'userId': 'user-1', 'username': 'scribe'},
      'createdAt': '2026-07-13T08:00:00.000Z',
      'lastUpdatedAt': '2026-07-13T08:00:01.000Z',
    };
