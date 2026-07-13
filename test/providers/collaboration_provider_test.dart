import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/models/collaboration_conflict.dart';
import 'package:openlogtool/models/collaboration_dto.dart';
import 'package:openlogtool/models/live_draft.dart';
import 'package:openlogtool/providers/collaboration_provider.dart';
import 'package:openlogtool/services/server_api.dart';

void main() {
  group('log authorship permissions', () {
    test('local sessions are not restricted by collaboration authorship', () {
      expect(
        collaborationLogMutationBlockReason(
          collaborationBound: false,
          canEditSession: true,
          accountId: 'user-1',
          authorshipKnown: false,
          createdBy: null,
        ),
        isNull,
      );
    });

    test('viewer, unknown author, and another author remain read-only', () {
      expect(
        collaborationLogMutationBlockReason(
          collaborationBound: true,
          canEditSession: false,
          accountId: 'user-1',
          authorshipKnown: true,
          createdBy: 'user-1',
        ),
        'COLLABORATION_SESSION_READ_ONLY',
      );
      expect(
        collaborationLogMutationBlockReason(
          collaborationBound: true,
          canEditSession: true,
          accountId: 'user-1',
          authorshipKnown: true,
          createdBy: null,
        ),
        'COLLABORATION_LOG_AUTHOR_UNKNOWN',
      );
      expect(
        collaborationLogMutationBlockReason(
          collaborationBound: true,
          canEditSession: true,
          accountId: 'user-1',
          authorshipKnown: true,
          createdBy: 'user-2',
        ),
        'COLLABORATION_LOG_NOT_OWNED',
      );
    });

    test('owner or editor can mutate a log only when authorship matches', () {
      expect(
        collaborationLogMutationBlockReason(
          collaborationBound: true,
          canEditSession: true,
          accountId: 'user-1',
          authorshipKnown: true,
          createdBy: 'user-1',
        ),
        isNull,
      );
    });
  });

  test('conflict invalidation follows entity and session event scope', () {
    final conflicts = [_logConflict()];

    expect(
      collaborationEventMayAffectOpenConflicts(
        event: _event(entityType: 'log', entityId: 'log-1'),
        openConflicts: conflicts,
        reportedConflictCount: 1,
      ),
      isTrue,
    );
    expect(
      collaborationEventMayAffectOpenConflicts(
        event: _event(entityType: 'log', entityId: 'log-other'),
        openConflicts: conflicts,
        reportedConflictCount: 1,
      ),
      isFalse,
    );
    expect(
      collaborationEventMayAffectOpenConflicts(
        event: _event(entityType: 'session', entityId: 'session-1'),
        openConflicts: conflicts,
        reportedConflictCount: 1,
      ),
      isTrue,
    );
  });

  test('pending initial conflict list invalidates conservatively', () {
    expect(
      collaborationEventMayAffectOpenConflicts(
        event: _event(entityType: 'log', entityId: 'log-other'),
        openConflicts: const [],
        reportedConflictCount: 1,
      ),
      isTrue,
    );
    expect(
      collaborationEventMayAffectOpenConflicts(
        event: _event(entityType: 'session', entityId: 'session-1'),
        openConflicts: const [],
        reportedConflictCount: 0,
      ),
      isFalse,
    );
  });

  group('atomic live-draft updates', () {
    test('uses field order, one PATCH, and releases only new locks', () async {
      final acquired = <String>[];
      final released = <String>[];
      final patchFields = <String>[];
      var patchCount = 0;
      final existingQth = _lock('qth', 'existing-qth');

      final execution = await executeLiveDraftAtomicPatch(
        values: const {
          'antenna': 'Yagi',
          'device': 'IC-705',
          'qth': 'Shanghai',
        },
        expectedRevisions: const {
          'antenna': 2,
          'device': 3,
          'qth': 4,
        },
        ownedLocks: {'qth': existingQth},
        nextClientSeq: 5,
        now: DateTime.utc(2026, 7, 13),
        acquireLock: (field) async {
          acquired.add(field);
          return _lock(field, 'new-$field');
        },
        sendPatch: (clientSeq, updates) async {
          patchCount += 1;
          expect(clientSeq, 5);
          patchFields.addAll(updates.map((update) => update.field));
          expect(
            updates.map((update) => update.expectedRevision),
            orderedEquals([4, 3, 2]),
          );
          expect(updates.first.leaseId, existingQth.leaseId);
          return _patchResult(clientSeq);
        },
        releaseLock: (field, _) async => released.add(field),
        onClientSeqChanged: (_) {},
      );

      expect(execution.appliedClientSeq, 5);
      expect(acquired, ['device', 'antenna']);
      expect(patchCount, 1);
      expect(patchFields, ['qth', 'device', 'antenna']);
      expect(released, ['antenna', 'device']);
    });

    test('an acquisition failure sends no PATCH and unwinds new locks',
        () async {
      final acquired = <String>[];
      final released = <String>[];
      var patchCount = 0;

      await expectLater(
        executeLiveDraftAtomicPatch(
          values: const {
            'qth': 'Shanghai',
            'device': 'IC-705',
            'antenna': 'Yagi',
          },
          expectedRevisions: const {
            'qth': 0,
            'device': 0,
            'antenna': 0,
          },
          ownedLocks: const {},
          nextClientSeq: 1,
          acquireLock: (field) async {
            acquired.add(field);
            if (field == 'device') {
              throw _serverError('LIVE_DRAFT_FIELD_LOCKED');
            }
            return _lock(field, 'new-$field');
          },
          sendPatch: (_, __) async {
            patchCount += 1;
            return _patchResult(1);
          },
          releaseLock: (field, _) async => released.add(field),
          onClientSeqChanged: (_) {},
        ),
        throwsA(
          isA<ServerApiException>().having(
            (error) => error.code,
            'code',
            'LIVE_DRAFT_FIELD_LOCKED',
          ),
        ),
      );

      expect(acquired, ['qth', 'device']);
      expect(patchCount, 0);
      expect(released, ['qth']);
    });

    test('a PATCH failure releases every lock acquired by the batch', () async {
      final released = <String>[];
      var patchCount = 0;

      await expectLater(
        executeLiveDraftAtomicPatch(
          values: const {'qth': 'Shanghai', 'device': 'IC-705'},
          expectedRevisions: const {'qth': 0, 'device': 0},
          ownedLocks: const {},
          nextClientSeq: 1,
          acquireLock: (field) async => _lock(field, 'new-$field'),
          sendPatch: (_, __) async {
            patchCount += 1;
            throw _serverError('LIVE_DRAFT_FIELD_CONFLICT');
          },
          releaseLock: (field, _) async => released.add(field),
          onClientSeqChanged: (_) {},
        ),
        throwsA(
          isA<ServerApiException>().having(
            (error) => error.code,
            'code',
            'LIVE_DRAFT_FIELD_CONFLICT',
          ),
        ),
      );

      expect(patchCount, 1);
      expect(released, ['device', 'qth']);
    });

    test('retries a client sequence gap with the server expected value',
        () async {
      final attempts = <int>[];
      final sequenceChanges = <int>[];

      final execution = await executeLiveDraftAtomicPatch(
        values: const {'qth': 'Shanghai'},
        expectedRevisions: const {'qth': 0},
        ownedLocks: const {},
        nextClientSeq: 2,
        acquireLock: (field) async => _lock(field, 'new-$field'),
        sendPatch: (clientSeq, _) async {
          attempts.add(clientSeq);
          if (attempts.length == 1) {
            throw _serverError(
              'LIVE_DRAFT_CLIENT_SEQ_GAP',
              details: const {'expectedClientSeq': 7},
            );
          }
          return _patchResult(clientSeq);
        },
        releaseLock: (_, __) async {},
        onClientSeqChanged: sequenceChanges.add,
      );

      expect(execution.appliedClientSeq, 7);
      expect(attempts, [2, 7]);
      expect(sequenceChanges, [6, 7]);
    });

    test('advances once after a reused client sequence', () async {
      final attempts = <int>[];
      final sequenceChanges = <int>[];

      final execution = await executeLiveDraftAtomicPatch(
        values: const {'qth': 'Shanghai'},
        expectedRevisions: const {'qth': 0},
        ownedLocks: const {},
        nextClientSeq: 2,
        acquireLock: (field) async => _lock(field, 'new-$field'),
        sendPatch: (clientSeq, _) async {
          attempts.add(clientSeq);
          if (attempts.length == 1) {
            throw _serverError('LIVE_DRAFT_CLIENT_SEQ_REUSED');
          }
          return _patchResult(clientSeq);
        },
        releaseLock: (_, __) async {},
        onClientSeqChanged: sequenceChanges.add,
      );

      expect(execution.appliedClientSeq, 3);
      expect(attempts, [2, 3]);
      expect(sequenceChanges, [2, 3]);
    });

    test('success merge preserves unrelated dirty state', () {
      final before = _fields({
        'qth': 'old-qth',
        'device': 'old-radio',
        'remarks': 'local-remarks',
      });
      final canonical = _draft(
        version: 3,
        values: const {
          'qth': 'new-qth',
          'device': 'new-radio',
          'remarks': 'remote-remarks',
        },
        revisions: const {'qth': 1, 'device': 1, 'remarks': 8},
      );

      final merged = mergeAcceptedLiveDraftAtomicPatch(
        targetFields: const {'qth', 'device'},
        beforeLocalFields: before,
        beforeDirtyFields: const {'remarks'},
        beforeBaseRevisions: const {'remarks': 7},
        currentLocalFields: before,
        currentDirtyFields: const {'remarks'},
        currentBaseRevisions: const {'remarks': 7},
        canonicalDraft: canonical,
      );

      expect(merged.localFields['qth'], 'new-qth');
      expect(merged.localFields['device'], 'new-radio');
      expect(merged.localFields['remarks'], 'local-remarks');
      expect(merged.dirtyFields, {'remarks'});
      expect(merged.baseRevisions, {'remarks': 7});
    });

    test('success merge retains a newer edit made while PATCH is pending', () {
      final before = _fields({'qth': 'old-qth', 'remarks': 'local-remarks'});
      final current = _fields({
        'qth': 'newer-local-qth',
        'remarks': 'local-remarks',
      });
      final canonical = _draft(
        version: 3,
        values: const {'qth': 'batch-qth', 'remarks': 'remote-remarks'},
        revisions: const {'qth': 4, 'remarks': 8},
      );

      final merged = mergeAcceptedLiveDraftAtomicPatch(
        targetFields: const {'qth'},
        beforeLocalFields: before,
        beforeDirtyFields: const {'remarks'},
        beforeBaseRevisions: const {'remarks': 7},
        currentLocalFields: current,
        currentDirtyFields: const {'qth', 'remarks'},
        currentBaseRevisions: const {'qth': 2, 'remarks': 7},
        canonicalDraft: canonical,
      );

      expect(merged.localFields['qth'], 'newer-local-qth');
      expect(merged.localFields['remarks'], 'local-remarks');
      expect(merged.dirtyFields, {'qth', 'remarks'});
      expect(merged.baseRevisions, {'qth': 4, 'remarks': 7});
    });

    test('an older PATCH response cannot replace a newer live snapshot', () {
      final accepted = _draft(version: 3, values: const {'qth': 'accepted'});
      final newer = _draft(version: 4, values: const {'qth': 'newer'});
      final nextGeneration = _draft(
        draftId: 'draft-2',
        version: 1,
        values: const {'qth': 'next'},
      );

      expect(
        selectLiveDraftCanonicalAfterAtomicPatch(
          current: newer,
          accepted: accepted,
        ),
        same(newer),
      );
      expect(
        selectLiveDraftCanonicalAfterAtomicPatch(
          current: nextGeneration,
          accepted: accepted,
        ),
        same(nextGeneration),
      );
    });
  });
}

CollaborationConflict _logConflict() => CollaborationConflict(
      conflictId: 'conflict-1',
      sessionId: 'session-1',
      entityType: CollaborationConflictEntityType.log,
      entityId: 'log-1',
      mutationId: 'mutation-1',
      baseVersion: 1,
      remoteVersion: 2,
      baseEntity: const {'version': 1},
      localEntity: const {'version': 1},
      remoteEntity: const {'version': 2},
      conflictingFields: const ['remarks'],
      allowedResolutions: const [
        CollaborationConflictResolution.useRemote,
      ],
      createdAt: DateTime.utc(2026, 7, 12),
    );

CollaborationEventDto _event({
  required String entityType,
  required String entityId,
}) =>
    CollaborationEventDto(
      protocolVersion: 1,
      eventId: 'event-$entityType-$entityId',
      sessionId: 'session-1',
      seq: 3,
      type: '$entityType.updated',
      entityType: entityType,
      entityId: entityId,
      entityVersion: 3,
      occurredAt: DateTime.utc(2026, 7, 12),
      payload: const {},
    );

LiveDraftLockDto _lock(String field, String leaseId) => LiveDraftLockDto(
      leaseId: leaseId,
      sessionId: 'session-1',
      field: field,
      userId: 'user-1',
      username: 'alice',
      deviceId: 'device-1',
      expiresAt: DateTime.utc(2026, 7, 14),
    );

LiveDraftPatchResultDto _patchResult(int clientSeq) {
  return LiveDraftPatchResultDto(
    draft: _draft(version: 2),
    appliedClientSeq: clientSeq,
    replayed: false,
  );
}

LiveDraftFieldsDto _fields(Map<String, String> values) =>
    LiveDraftFieldsDto(values);

LiveDraftDto _draft({
  String draftId = 'draft-1',
  required int version,
  Map<String, String> values = const {},
  Map<String, int> revisions = const {},
}) =>
    LiveDraftDto(
      draftId: draftId,
      sessionId: 'session-1',
      version: version,
      fields: _fields(values),
      fieldRevisions: {
        for (final field in liveDraftFieldNames) field: revisions[field] ?? 0,
      },
      lastUpdatedBy: null,
      createdAt: DateTime.utc(2026, 7, 13),
      lastUpdatedAt: DateTime.utc(2026, 7, 13),
    );

ServerApiException _serverError(String code, {Object? details}) =>
    ServerApiException(
      error: ApiErrorDto(
        code: code,
        message: code,
        requestId: 'request-1',
        details: details,
      ),
      statusCode: 409,
      retryable: false,
    );
