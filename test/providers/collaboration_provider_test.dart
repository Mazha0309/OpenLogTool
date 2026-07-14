import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/models/collaboration_conflict.dart';
import 'package:openlogtool/models/collaboration_dto.dart';
import 'package:openlogtool/models/live_draft.dart';
import 'package:openlogtool/providers/collaboration_provider.dart';
import 'package:openlogtool/services/collaboration_sync.dart';
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

    test(
        'single-field response keeps every field edited while PATCH is pending',
        () {
      for (final field in liveDraftFieldNames) {
        final sentValue = 'sent-$field';
        final currentValue = 'current-$field';
        final sent = _fields({field: sentValue});
        final current = _fields({field: currentValue});
        final accepted = _draft(
          version: 2,
          values: {field: sentValue},
          revisions: {field: 1},
        );

        final merged = mergeAcceptedLiveDraftAtomicPatch(
          targetFields: {field},
          beforeLocalFields: sent,
          beforeDirtyFields: {field},
          beforeBaseRevisions: {field: 0},
          currentLocalFields: current,
          currentDirtyFields: {field},
          currentBaseRevisions: {field: 0},
          canonicalDraft: accepted,
        );

        expect(merged.localFields[field], currentValue, reason: field);
        expect(merged.dirtyFields, {field}, reason: field);
        expect(merged.baseRevisions, {field: 1}, reason: field);
      }
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

    test('refresh keeps a newer same-generation draft but adopts new locks',
        () {
      final current = _snapshot(
        draft: _draft(version: 4, values: const {'callsign': 'BG5CRL'}),
        locks: [_lock('callsign', 'old-lock')],
      );
      final stale = _snapshot(
        draft: _draft(version: 3, values: const {'callsign': 'B'}),
        locks: [_lock('qth', 'fresh-lock')],
      );

      final selected = selectLiveDraftSnapshotAfterRefresh(
        current: current,
        incoming: stale,
      );

      expect(selected.draft, same(current.draft));
      expect(selected.locks.single.leaseId, 'fresh-lock');
      expect(selected.currentOrdinal, current.currentOrdinal);
    });

    test('refresh accepts a newer version and a new draft generation', () {
      final current = _snapshot(draft: _draft(version: 4));
      final newer = _snapshot(draft: _draft(version: 5));
      final nextGeneration = _snapshot(
        draft: _draft(draftId: 'draft-2', version: 1),
      );

      expect(
        selectLiveDraftSnapshotAfterRefresh(
          current: current,
          incoming: newer,
        ),
        same(newer),
      );
      expect(
        selectLiveDraftSnapshotAfterRefresh(
          current: current,
          incoming: nextGeneration,
        ),
        same(nextGeneration),
      );
    });

    test('field and version conflicts rebase and retry exactly once', () async {
      for (final code in const [
        'LIVE_DRAFT_FIELD_CONFLICT',
        'LIVE_DRAFT_VERSION_CONFLICT',
      ]) {
        var attempts = 0;
        var rebases = 0;
        final result = await executeLiveDraftAtomicPatchWithRebaseRetry<int>(
          attempt: () async {
            attempts += 1;
            if (attempts == 1) throw _serverError(code);
            return 7;
          },
          rebase: () async => rebases += 1,
        );

        expect(result, 7, reason: code);
        expect(attempts, 2, reason: code);
        expect(rebases, 1, reason: code);
      }
    });

    test('a second atomic conflict is returned without a third attempt',
        () async {
      var attempts = 0;
      var rebases = 0;

      await expectLater(
        executeLiveDraftAtomicPatchWithRebaseRetry<void>(
          attempt: () async {
            attempts += 1;
            throw _serverError('LIVE_DRAFT_FIELD_CONFLICT');
          },
          rebase: () async => rebases += 1,
        ),
        throwsA(
          isA<ServerApiException>().having(
            (error) => error.code,
            'code',
            'LIVE_DRAFT_FIELD_CONFLICT',
          ),
        ),
      );

      expect(attempts, 2);
      expect(rebases, 1);
    });
  });

  test('offline commit starts the next record with an empty time', () {
    final next = resetLiveDraftFieldsAfterCommit(
      _fields({
        'time': '2026-07-14T12:34:00Z',
        'controller': 'BG5CRL',
        'callsign': 'BA4AAA',
        'rstSent': '58',
        'rstRcvd': '47',
        'qth': 'Shanghai',
      }),
    );

    expect(next['time'], isEmpty);
    expect(next['controller'], 'BG5CRL');
    expect(next['callsign'], isEmpty);
    expect(next['rstSent'], '59');
    expect(next['rstRcvd'], '59');
    expect(next['qth'], isEmpty);
  });

  group('live-draft realtime controls', () {
    test('updated payload projects every supported field without a GET', () {
      final current = _snapshot(draft: _draft(version: 1));
      final values = {
        for (final field in liveDraftFieldNames) field: 'value-$field',
      };
      final incoming = _draft(version: 2, values: values);

      final projection = applyLiveDraftControlMessage(
        currentSnapshot: current,
        currentLocalFields: current.draft.fields,
        currentDirtyFields: const {},
        currentBaseRevisions: const {},
        message: {
          'type': 'liveDraft.updated',
          'sessionId': 'session-1',
          'draft': incoming.toJson(),
        },
      );

      expect(projection.changed, isTrue);
      for (final field in liveDraftFieldNames) {
        expect(projection.snapshot.draft.fields[field], values[field],
            reason: field);
        expect(projection.localFields[field], values[field], reason: field);
      }
    });

    test('older updated payload is ignored', () {
      final current = _snapshot(
        draft: _draft(version: 4, values: const {'callsign': 'BG5CRL'}),
      );

      final projection = applyLiveDraftControlMessage(
        currentSnapshot: current,
        currentLocalFields: current.draft.fields,
        currentDirtyFields: const {},
        currentBaseRevisions: const {},
        message: {
          'type': 'liveDraft.updated',
          'sessionId': 'session-1',
          'draft': _draft(
            version: 3,
            values: const {'callsign': 'B'},
          ).toJson(),
        },
      );

      expect(projection.changed, isFalse);
      expect(projection.snapshot, same(current));
      expect(projection.localFields['callsign'], 'BG5CRL');
    });

    test('updated payload cannot switch draft generations', () {
      final current = _snapshot(draft: _draft(version: 4));

      expect(
        () => applyLiveDraftControlMessage(
          currentSnapshot: current,
          currentLocalFields: current.draft.fields,
          currentDirtyFields: const {},
          currentBaseRevisions: const {},
          message: {
            'type': 'liveDraft.updated',
            'sessionId': 'session-1',
            'draft': _draft(
              draftId: 'unproven-generation',
              version: 1,
            ).toJson(),
          },
        ),
        throwsFormatException,
      );
    });

    test('newer updated payload preserves local dirty fields', () {
      final current = _snapshot(
        draft: _draft(
          version: 4,
          values: const {'callsign': 'BA4AAA', 'qth': 'old-remote'},
          revisions: const {'callsign': 2, 'qth': 7},
        ),
      );
      final local = current.draft.fields.withField('qth', 'local-edit');

      final projection = applyLiveDraftControlMessage(
        currentSnapshot: current,
        currentLocalFields: local,
        currentDirtyFields: const {'qth'},
        currentBaseRevisions: const {'qth': 7},
        message: {
          'type': 'liveDraft.updated',
          'sessionId': 'session-1',
          'draft': _draft(
            version: 5,
            values: const {'callsign': 'BA4BBB', 'qth': 'new-remote'},
            revisions: const {'callsign': 3, 'qth': 8},
          ).toJson(),
        },
      );

      expect(projection.snapshot.draft.fields['qth'], 'new-remote');
      expect(projection.localFields['qth'], 'local-edit');
      expect(projection.localFields['callsign'], 'BA4BBB');
      expect(projection.dirtyFields, {'qth'});
      expect(projection.baseRevisions, {'qth': 7});
    });

    test('cleared and committed controls replace the draft generation', () {
      final previous = _log('previous-log', callsign: 'BA4AAA');
      final current = _snapshot(
        draft: _draft(version: 4, values: const {'qth': 'local'}),
        locks: [_lock('qth', 'qth-lock')],
        previousRecord: previous,
      );
      final nextAfterClear = _draft(
        draftId: 'draft-2',
        version: 1,
        values: const {'controller': 'BG5CRL'},
      );

      final cleared = applyLiveDraftControlMessage(
        currentSnapshot: current,
        currentLocalFields: current.draft.fields.withField('qth', 'dirty'),
        currentDirtyFields: const {'qth'},
        currentBaseRevisions: const {'qth': 0},
        message: {
          'type': 'liveDraft.cleared',
          'sessionId': 'session-1',
          'discardedDraftId': 'draft-1',
          'nextDraft': nextAfterClear.toJson(),
        },
      );

      expect(cleared.snapshot.draft.draftId, 'draft-2');
      expect(cleared.snapshot.locks, isEmpty);
      expect(cleared.snapshot.previousRecord, same(previous));
      expect(cleared.localFields['controller'], 'BG5CRL');
      expect(cleared.dirtyFields, isEmpty);

      final committedRecord = _log('committed-log', callsign: 'BA4BBB');
      final committed = applyLiveDraftControlMessage(
        currentSnapshot: cleared.snapshot,
        currentLocalFields: cleared.localFields,
        currentDirtyFields: cleared.dirtyFields,
        currentBaseRevisions: cleared.baseRevisions,
        message: {
          'type': 'liveDraft.committed',
          'sessionId': 'session-1',
          'committedDraftId': 'draft-2',
          'nextDraft': _draft(
            draftId: 'draft-3',
            version: 1,
          ).toJson(),
          'record': committedRecord.toJson(),
          'currentOrdinal': 9,
          'totalRecords': 8,
        },
      );

      expect(committed.snapshot.draft.draftId, 'draft-3');
      expect(committed.snapshot.currentOrdinal, 9);
      expect(committed.snapshot.totalRecords, 8);
      expect(committed.snapshot.previousRecord?.syncId, 'committed-log');
      expect(committed.snapshot.previousRecord?.callsign, 'BA4BBB');
      expect(committed.snapshot.locks, isEmpty);

      final repeated = applyLiveDraftControlMessage(
        currentSnapshot: committed.snapshot,
        currentLocalFields: committed.localFields,
        currentDirtyFields: committed.dirtyFields,
        currentBaseRevisions: committed.baseRevisions,
        message: {
          'type': 'liveDraft.committed',
          'sessionId': 'session-1',
          'committedDraftId': 'draft-2',
          'nextDraft': _draft(
            draftId: 'draft-3',
            version: 1,
          ).toJson(),
          'record': committedRecord.toJson(),
          'currentOrdinal': 9,
          'totalRecords': 8,
        },
      );
      expect(repeated.changed, isFalse);
      expect(repeated.snapshot, same(committed.snapshot));
    });

    test('reset controls reject an unrelated predecessor', () {
      final current = _snapshot(
        draft: _draft(draftId: 'draft-current', version: 2),
      );
      final next = _draft(draftId: 'draft-next', version: 1);

      expect(
        () => applyLiveDraftControlMessage(
          currentSnapshot: current,
          currentLocalFields: current.draft.fields,
          currentDirtyFields: const {},
          currentBaseRevisions: const {},
          message: {
            'type': 'liveDraft.cleared',
            'sessionId': 'session-1',
            'discardedDraftId': 'draft-unrelated',
            'nextDraft': next.toJson(),
          },
        ),
        throwsFormatException,
      );
      expect(
        () => applyLiveDraftControlMessage(
          currentSnapshot: current,
          currentLocalFields: current.draft.fields,
          currentDirtyFields: const {},
          currentBaseRevisions: const {},
          message: {
            'type': 'liveDraft.committed',
            'sessionId': 'session-1',
            'committedDraftId': 'draft-unrelated',
            'nextDraft': next.toJson(),
            'record': _log('log-1', callsign: 'BA4AAA').toJson(),
            'currentOrdinal': 2,
            'totalRecords': 1,
          },
        ),
        throwsFormatException,
      );
    });

    test('lock controls update, release, and replace the canonical lock list',
        () {
      final current = _snapshot(
        draft: _draft(version: 1),
        locks: [_lock('callsign', 'callsign-lock')],
      );
      final acquired = applyLiveDraftControlMessage(
        currentSnapshot: current,
        currentLocalFields: current.draft.fields,
        currentDirtyFields: const {},
        currentBaseRevisions: const {},
        message: {
          'type': 'liveDraft.lockChanged',
          'sessionId': 'session-1',
          'occurredAt': '2026-07-13T01:00:00.000Z',
          'action': 'acquired',
          'lock': _lock('qth', 'qth-lock').toJson(),
        },
      );
      expect(
        acquired.snapshot.locks.map((lock) => lock.field),
        orderedEquals(['callsign', 'qth']),
      );

      final released = applyLiveDraftControlMessage(
        currentSnapshot: acquired.snapshot,
        currentLocalFields: acquired.localFields,
        currentDirtyFields: acquired.dirtyFields,
        currentBaseRevisions: acquired.baseRevisions,
        message: const {
          'type': 'liveDraft.lockChanged',
          'sessionId': 'session-1',
          'occurredAt': '2026-07-13T01:00:00.000Z',
          'action': 'released',
          'field': 'callsign',
          'leaseId': 'callsign-lock',
        },
      );
      expect(released.snapshot.locks.single.field, 'qth');

      final membershipChanged = applyLiveDraftControlMessage(
        currentSnapshot: released.snapshot,
        currentLocalFields: released.localFields,
        currentDirtyFields: released.dirtyFields,
        currentBaseRevisions: released.baseRevisions,
        message: const {
          'type': 'liveDraft.lockChanged',
          'sessionId': 'session-1',
          'occurredAt': '2026-07-13T01:00:00.000Z',
          'action': 'membershipChanged',
          'fields': <Object?>['qth'],
        },
      );
      expect(membershipChanged.snapshot.locks, isEmpty);

      final closed = applyLiveDraftControlMessage(
        currentSnapshot: membershipChanged.snapshot,
        currentLocalFields: membershipChanged.localFields,
        currentDirtyFields: membershipChanged.dirtyFields,
        currentBaseRevisions: membershipChanged.baseRevisions,
        message: const {
          'type': 'liveDraft.lockChanged',
          'sessionId': 'session-1',
          'occurredAt': '2026-07-13T01:00:00.000Z',
          'action': 'ownershipTransferred',
          'locks': <Object?>[],
        },
      );
      expect(closed.snapshot.locks, isEmpty);
    });

    test('an old-generation lock control cannot revive a reset lock', () {
      final current = _snapshot(
        draft: _draft(draftId: 'draft-2', version: 1),
      );
      final stale = applyLiveDraftControlMessage(
        currentSnapshot: current,
        currentLocalFields: current.draft.fields,
        currentDirtyFields: const {},
        currentBaseRevisions: const {},
        message: {
          'type': 'liveDraft.lockChanged',
          'sessionId': 'session-1',
          'occurredAt': '2026-07-12T23:59:59.999Z',
          'action': 'acquired',
          'lock': _lock('callsign', 'stale-lock').toJson(),
        },
      );

      expect(stale.changed, isFalse);
      expect(stale.snapshot, same(current));
      expect(stale.snapshot.locks, isEmpty);
    });

    test('a same-millisecond lock control requires canonical recovery', () {
      final current = _snapshot(draft: _draft(version: 1));

      expect(
        () => applyLiveDraftControlMessage(
          currentSnapshot: current,
          currentLocalFields: current.draft.fields,
          currentDirtyFields: const {},
          currentBaseRevisions: const {},
          message: {
            'type': 'liveDraft.lockChanged',
            'sessionId': 'session-1',
            'occurredAt': '2026-07-13T00:00:00.000Z',
            'action': 'acquired',
            'lock': _lock('callsign', 'ambiguous-lock').toJson(),
          },
        ),
        throwsFormatException,
      );
    });

    test('canonical locks remove expired owned leases and adopt renewals', () {
      final owned = {
        'callsign': _lock('callsign', 'expired-lock'),
        'qth': _lock('qth', 'renewed-lock'),
      };
      final renewed = _lock(
        'qth',
        'renewed-lock',
        expiresAt: DateTime.utc(2026, 7, 15),
      );

      final reconciled = reconcileOwnedLiveDraftLocks(
        owned: owned,
        canonical: [renewed],
      );

      expect(reconciled.keys, ['qth']);
      expect(reconciled['qth'], same(renewed));
      expect(reconciled['qth']?.expiresAt, DateTime.utc(2026, 7, 15));
    });

    test('initial connect and one reconnect each request one fallback refresh',
        () {
      CollaborationTransportPhase? previous;
      var refreshes = 0;
      for (final current in const [
        CollaborationTransportPhase.connecting,
        CollaborationTransportPhase.online,
        CollaborationTransportPhase.online,
        CollaborationTransportPhase.backingOff,
        CollaborationTransportPhase.connecting,
        CollaborationTransportPhase.online,
        CollaborationTransportPhase.online,
      ]) {
        if (shouldRefreshLiveDraftAfterTransportTransition(previous, current)) {
          refreshes += 1;
        }
        previous = current;
      }

      expect(refreshes, 2);
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

LiveDraftLockDto _lock(
  String field,
  String leaseId, {
  DateTime? expiresAt,
}) =>
    LiveDraftLockDto(
      leaseId: leaseId,
      sessionId: 'session-1',
      field: field,
      userId: 'user-1',
      username: 'alice',
      deviceId: 'device-1',
      expiresAt: expiresAt ?? DateTime.utc(2026, 7, 14),
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

LiveDraftSnapshotDto _snapshot({
  required LiveDraftDto draft,
  List<LiveDraftLockDto> locks = const [],
  int currentOrdinal = 8,
  int totalRecords = 7,
  CollaborationLogDto? previousRecord,
}) =>
    LiveDraftSnapshotDto(
      draft: draft,
      locks: locks,
      currentOrdinal: currentOrdinal,
      totalRecords: totalRecords,
      previousRecord: previousRecord,
    );

CollaborationLogDto _log(String syncId, {required String callsign}) =>
    CollaborationLogDto(
      syncId: syncId,
      sessionId: 'session-1',
      version: 1,
      time: DateTime.utc(2026, 7, 13, 12),
      controller: 'BG5CRL',
      callsign: callsign,
      rstSent: '59',
      rstRcvd: '59',
      qth: null,
      device: null,
      power: null,
      antenna: null,
      height: null,
      remarks: null,
      createdAt: DateTime.utc(2026, 7, 13, 12),
      updatedAt: DateTime.utc(2026, 7, 13, 12),
      deletedAt: null,
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
