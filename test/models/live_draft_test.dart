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
