import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/models/collaboration_dto.dart';
import 'package:openlogtool/services/collaboration_sync.dart';

void main() {
  group('CollaborationSyncCoordinator', () {
    test('snapshot install selection keeps first join lean and rejoin safe',
        () {
      expect(
        includeDeletedLogsForSnapshotInstall(
          CollaborationSnapshotInstallTarget.publish,
        ),
        isFalse,
      );
      expect(
        includeDeletedLogsForSnapshotInstall(
          CollaborationSnapshotInstallTarget.firstJoin,
        ),
        isFalse,
      );
      expect(
        includeDeletedLogsForSnapshotInstall(
          CollaborationSnapshotInstallTarget.existingReplica,
        ),
        isTrue,
      );
    });

    test('legacy snapshots default missing tombstone capability to false', () {
      final json = _snapshotDto(
        'legacy-session',
        highWatermarkSeq: 0,
        includesDeletedLogs: false,
      ).toJson()
        ..remove('includesDeletedLogs');

      final parsed = SessionSnapshotDto.fromJson(json);

      expect(parsed.includesDeletedLogs, isFalse);
      expect(parsed.session.sessionId, 'legacy-session');
    });

    test('does not apply a REST cursor gap', () async {
      final replica = _FakeReplica(cursor: 0);
      final transport = _FakeTransport(
        events: (sessionId, afterSeq) => SessionEventsPageDto(
          afterSeq: afterSeq,
          toSeq: 2,
          headSeq: 2,
          minAvailableSeq: 0,
          hasMore: false,
          events: [_event(seq: 2)],
        ),
      );
      final backoff = Completer<void>();
      final states = <CollaborationSyncState>[];
      final coordinator = CollaborationSyncCoordinator(
        transport: transport,
        replica: replica,
        sockets: _FakeSocketConnector(),
        delay: (_) => backoff.future,
        onStateChanged: states.add,
      );

      coordinator.start(
          identity: _identity('session-a'), role: SessionRole.editor);
      await _waitUntil(
        () => states.any(
          (state) => state.lastErrorCode == 'EVENT_CURSOR_GAP',
        ),
      );

      expect(replica.cursor, 0);
      expect(replica.appliedEventIds, isEmpty);
      expect(coordinator.state.transportPhase,
          CollaborationTransportPhase.backingOff);
      await coordinator.stop();
      backoff.complete();
    });

    test('accepts duplicate delivery without advancing the cursor', () async {
      final duplicate = _event(seq: 1, eventId: 'event-1');
      final replica = _FakeReplica(
        cursor: 1,
        applied: {'event-1': 1},
      );
      final transport = _FakeTransport(
        events: (sessionId, afterSeq) => SessionEventsPageDto(
          afterSeq: afterSeq,
          toSeq: afterSeq,
          headSeq: afterSeq,
          minAvailableSeq: 0,
          hasMore: false,
          events: [duplicate],
        ),
      );
      final sockets = _FakeSocketConnector(autoReady: true);
      final coordinator = CollaborationSyncCoordinator(
        transport: transport,
        replica: replica,
        sockets: sockets,
      );

      coordinator.start(
          identity: _identity('session-a'), role: SessionRole.editor);
      await _waitUntil(
        () =>
            coordinator.state.transportPhase ==
            CollaborationTransportPhase.online,
      );

      expect(replica.cursor, 1);
      expect(replica.duplicateCount, greaterThanOrEqualTo(1));
      await coordinator.stop();
    });

    test('reconnects through catch-up after a socket closes', () async {
      final replica = _FakeReplica(cursor: 0);
      final transport = _FakeTransport();
      final sockets = _FakeSocketConnector(
        autoReady: true,
        closeFirstAfterReady: true,
      );
      var delayCount = 0;
      final coordinator = CollaborationSyncCoordinator(
        transport: transport,
        replica: replica,
        sockets: sockets,
        random: Random(1),
        delay: (_) async {
          delayCount += 1;
        },
      );

      coordinator.start(
          identity: _identity('session-a'), role: SessionRole.editor);
      await _waitUntil(
        () =>
            sockets.connectCount >= 2 &&
            coordinator.state.transportPhase ==
                CollaborationTransportPhase.online,
      );

      expect(delayCount, greaterThanOrEqualTo(1));
      expect(transport.membershipSessions, ['session-a', 'session-a']);
      expect(transport.eventSessions.length, greaterThanOrEqualTo(2));
      await coordinator.stop();
    });

    test('does not lose an outbox wake during the socket connect window',
        () async {
      final mutation = _mutation('mutation-window', 'log-window');
      final replica = _FakeReplica(cursor: 0);
      final transport = _FakeTransport(
        submit: (operations) => MutationBatchResultDto(
          headSeq: 1,
          results: [
            MutationResultDto(
              mutationId: mutation.mutationId,
              status: 'accepted',
              event: _event(
                seq: 1,
                eventId: 'event-window',
                mutationId: mutation.mutationId,
                entityId: mutation.entityId,
              ),
            ),
          ],
        ),
      );
      final sockets = _BlockingSocketConnector();
      final coordinator = CollaborationSyncCoordinator(
        transport: transport,
        replica: replica,
        sockets: sockets,
      );

      coordinator.start(
          identity: _identity('session-a'), role: SessionRole.editor);
      await sockets.connectStarted.future;
      replica.enqueue(mutation);
      coordinator.wake();
      sockets.release.complete();
      await _waitUntil(
        () =>
            replica.acceptedMutationIds.contains('mutation-window') &&
            coordinator.state.transportPhase ==
                CollaborationTransportPhase.online,
      );

      expect(transport.submittedSessions, ['session-a']);
      expect(replica.appliedEventIds, contains('event-window'));
      await coordinator.stop();
    });

    test('uses a WebSocket event only as a REST catch-up hint', () async {
      var remoteHead = 0;
      final event = _event(seq: 1, eventId: 'event-from-rest');
      final replica = _FakeReplica(cursor: 0);
      final transport = _FakeTransport(
        events: (sessionId, afterSeq) => SessionEventsPageDto(
          afterSeq: afterSeq,
          toSeq: remoteHead,
          headSeq: remoteHead,
          minAvailableSeq: 0,
          hasMore: false,
          events: afterSeq < remoteHead ? [event] : const [],
        ),
      );
      final sockets = _FakeSocketConnector(autoReady: true);
      final coordinator = CollaborationSyncCoordinator(
        transport: transport,
        replica: replica,
        sockets: sockets,
      );

      coordinator.start(
        identity: _identity('session-a'),
        role: SessionRole.editor,
      );
      await _waitUntil(
        () =>
            coordinator.state.transportPhase ==
            CollaborationTransportPhase.online,
      );
      remoteHead = 1;
      sockets.lastSocket!.add(jsonEncode({
        'type': 'event',
        // Deliberately different content: the socket envelope must not be
        // applied directly.
        'event': _event(
          seq: 1,
          eventId: 'untrusted-socket-hint',
        ).toJson(),
      }));
      await _waitUntil(() => replica.cursor == 1);

      expect(replica.appliedEventIds, contains('event-from-rest'));
      expect(replica.appliedEventIds, isNot(contains('untrusted-socket-hint')));
      await coordinator.stop();
    });

    test('local close locks writes until a canonical reopen event', () async {
      var remoteHead = 0;
      final reopened = CollaborationEventDto(
        protocolVersion: 1,
        eventId: 'session-reopened-1',
        sessionId: 'session-a',
        seq: 1,
        type: 'session.reopened',
        entityType: 'session',
        entityId: 'session-a',
        entityVersion: 2,
        mutationId: 'reopen-1',
        occurredAt: DateTime.utc(2026),
        payload: const {
          'sessionId': 'session-a',
          'status': 'active',
          'version': 2,
        },
      );
      final replica = _FakeReplica(cursor: 0);
      final transport = _FakeTransport(
        events: (sessionId, afterSeq) => SessionEventsPageDto(
          afterSeq: afterSeq,
          toSeq: remoteHead,
          headSeq: remoteHead,
          minAvailableSeq: 0,
          hasMore: false,
          events: afterSeq < remoteHead ? [reopened] : const [],
        ),
      );
      final sockets = _FakeSocketConnector(autoReady: true);
      final coordinator = CollaborationSyncCoordinator(
        transport: transport,
        replica: replica,
        sockets: sockets,
      );

      coordinator.start(
        identity: _identity('session-a'),
        role: SessionRole.editor,
      );
      await _waitUntil(
        () =>
            coordinator.state.transportPhase ==
            CollaborationTransportPhase.online,
      );
      expect(coordinator.state.canEdit, isTrue);
      coordinator.markSessionLocallyClosed();
      expect(coordinator.state.canEdit, isFalse);

      remoteHead = 1;
      sockets.lastSocket!.add(jsonEncode({
        'type': 'event',
        'event': reopened.toJson(),
      }));
      await _waitUntil(() => coordinator.state.lastAppliedSeq == 1);

      expect(coordinator.state.sessionClosed, isFalse);
      expect(coordinator.state.canEdit, isTrue);
      await coordinator.stop();
    });

    test('a closed local guard still flushes its owner session mutation',
        () async {
      final closeMutation = CollaborationMutationDto(
        mutationId: 'close-1',
        entityType: 'session',
        entityId: 'session-a',
        operation: 'close',
        baseVersion: 1,
        observedSeq: 0,
        queuedAt: DateTime.utc(2026),
      );
      final replica = _FakeReplica(cursor: 0, pending: [closeMutation]);
      final closedEvent = CollaborationEventDto(
        protocolVersion: 1,
        eventId: 'closed-event',
        sessionId: 'session-a',
        seq: 1,
        type: 'session.closed',
        entityType: 'session',
        entityId: 'session-a',
        entityVersion: 2,
        mutationId: 'close-1',
        occurredAt: DateTime.utc(2026),
        payload: const {
          'sessionId': 'session-a',
          'status': 'closed',
          'version': 2,
        },
      );
      final transport = _FakeTransport(
        membership: (sessionId) => Future.value(
          _membership(sessionId, role: SessionRole.owner),
        ),
        ticket: (sessionId, afterSeq, call) => WebSocketTicketDto(
          ticket: 'owner-ticket-$call-$afterSeq',
          expiresAt: DateTime.now().add(const Duration(minutes: 1)),
          sessionId: sessionId,
          role: SessionRole.owner,
          membershipVersion: 1,
          afterSeq: afterSeq,
        ),
        submit: (_) => MutationBatchResultDto(
          headSeq: 1,
          results: [
            MutationResultDto(
              mutationId: 'close-1',
              status: 'accepted',
              event: closedEvent,
            ),
          ],
        ),
      );
      final coordinator = CollaborationSyncCoordinator(
        transport: transport,
        replica: replica,
        sockets: _FakeSocketConnector(autoReady: true),
      );

      coordinator.start(
        identity: _identity('session-a'),
        role: SessionRole.owner,
        sessionClosed: true,
      );
      await _waitUntil(
        () =>
            coordinator.state.transportPhase ==
            CollaborationTransportPhase.online,
      );
      await _waitUntil(
        () => replica.acceptedMutationIds.contains('close-1'),
      );

      expect(transport.submittedSessions, ['session-a']);
      expect(replica.acceptedMutationIds, ['close-1']);
      expect(coordinator.state.sessionClosed, isTrue);
      await coordinator.stop();
    });

    test('a live-draft close rejection can restore local write access',
        () async {
      final closeMutation = CollaborationMutationDto(
        mutationId: 'close-rejected-1',
        entityType: 'session',
        entityId: 'session-a',
        operation: 'close',
        baseVersion: 1,
        observedSeq: 0,
        queuedAt: DateTime.utc(2026),
      );
      final replica = _FakeReplica(cursor: 0, pending: [closeMutation]);
      final rejected = <MutationResultDto>[];
      final transport = _FakeTransport(
        membership: (sessionId) => Future.value(
          _membership(sessionId, role: SessionRole.owner),
        ),
        ticket: (sessionId, afterSeq, call) => WebSocketTicketDto(
          ticket: 'owner-ticket-$call-$afterSeq',
          expiresAt: DateTime.now().add(const Duration(minutes: 1)),
          sessionId: sessionId,
          role: SessionRole.owner,
          membershipVersion: 1,
          afterSeq: afterSeq,
        ),
        submit: (_) => const MutationBatchResultDto(
          headSeq: 0,
          results: [
            MutationResultDto(
              mutationId: 'close-rejected-1',
              status: 'rejected',
              code: 'LIVE_DRAFT_NOT_EMPTY',
              message: 'Commit or discard the live draft first',
            ),
          ],
        ),
      );
      final coordinator = CollaborationSyncCoordinator(
        transport: transport,
        replica: replica,
        sockets: _FakeSocketConnector(autoReady: true),
        onLocalCloseRejected: (mutation, result) {
          expect(mutation, same(closeMutation));
          rejected.add(result);
          return true;
        },
      );

      coordinator.start(
        identity: _identity('session-a'),
        role: SessionRole.owner,
        sessionClosed: true,
      );
      await _waitUntil(
        () => rejected.length == 1 && coordinator.state.canEdit,
      );

      expect(rejected.single.code, 'LIVE_DRAFT_NOT_EMPTY');
      expect(coordinator.state.sessionClosed, isFalse);
      expect(coordinator.state.writeSuspended, isFalse);
      await coordinator.stop();
    });

    test('canonical closed mode sends reopen but not pending Logs', () async {
      final reopenMutation = CollaborationMutationDto(
        mutationId: 'reopen-1',
        entityType: 'session',
        entityId: 'session-a',
        operation: 'reopen',
        baseVersion: 2,
        observedSeq: 1,
        queuedAt: DateTime.utc(2026),
      );
      final logMutation = _mutation('closed-log-1', 'log-closed');
      final replica = _FakeReplica(
        cursor: 1,
        pending: [logMutation, reopenMutation],
        canonicalSessionStatus: 'closed',
      );
      final reopenedEvent = CollaborationEventDto(
        protocolVersion: 1,
        eventId: 'reopened-event',
        sessionId: 'session-a',
        seq: 2,
        type: 'session.reopened',
        entityType: 'session',
        entityId: 'session-a',
        entityVersion: 3,
        mutationId: 'reopen-1',
        occurredAt: DateTime.utc(2026),
        payload: const {
          'sessionId': 'session-a',
          'status': 'active',
          'version': 3,
        },
      );
      final submitted = <List<String>>[];
      final transport = _FakeTransport(
        membership: (sessionId) => Future.value(
          _membership(sessionId, role: SessionRole.owner),
        ),
        ticket: (sessionId, afterSeq, call) => WebSocketTicketDto(
          ticket: 'owner-ticket-$call-$afterSeq',
          expiresAt: DateTime.now().add(const Duration(minutes: 1)),
          sessionId: sessionId,
          role: SessionRole.owner,
          membershipVersion: 1,
          afterSeq: afterSeq,
        ),
        submit: (operations) {
          submitted.add(
              operations.map((operation) => operation.mutationId).toList());
          if (operations.single.mutationId == 'reopen-1') {
            return MutationBatchResultDto(
              headSeq: 2,
              results: [
                MutationResultDto(
                  mutationId: 'reopen-1',
                  status: 'accepted',
                  event: reopenedEvent,
                ),
              ],
            );
          }
          return MutationBatchResultDto(
            headSeq: 3,
            results: [
              MutationResultDto(
                mutationId: 'closed-log-1',
                status: 'accepted',
                event: _event(
                  seq: 3,
                  eventId: 'log-after-reopen',
                  mutationId: 'closed-log-1',
                  entityId: 'log-closed',
                ),
              ),
            ],
          );
        },
      );
      final coordinator = CollaborationSyncCoordinator(
        transport: transport,
        replica: replica,
        sockets: _FakeSocketConnector(autoReady: true),
      );

      coordinator.start(
        identity: _identity('session-a'),
        role: SessionRole.owner,
        sessionClosed: true,
      );
      await _waitUntil(
        () =>
            coordinator.state.transportPhase ==
            CollaborationTransportPhase.online,
      );

      expect(submitted.first, ['reopen-1']);
      expect(submitted[1], ['closed-log-1']);
      expect(coordinator.state.sessionClosed, isFalse);
      await coordinator.stop();
    });

    test('canonical closed mode leaves Log mutations local', () async {
      final replica = _FakeReplica(
        cursor: 1,
        pending: [_mutation('closed-log-only', 'log-closed')],
        canonicalSessionStatus: 'closed',
      );
      final transport = _FakeTransport(
        membership: (sessionId) => Future.value(
          _membership(sessionId, role: SessionRole.owner),
        ),
        ticket: (sessionId, afterSeq, call) => WebSocketTicketDto(
          ticket: 'owner-ticket-$call-$afterSeq',
          expiresAt: DateTime.now().add(const Duration(minutes: 1)),
          sessionId: sessionId,
          role: SessionRole.owner,
          membershipVersion: 1,
          afterSeq: afterSeq,
        ),
      );
      final coordinator = CollaborationSyncCoordinator(
        transport: transport,
        replica: replica,
        sockets: _FakeSocketConnector(autoReady: true),
      );

      coordinator.start(
        identity: _identity('session-a'),
        role: SessionRole.owner,
        sessionClosed: true,
      );
      await _waitUntil(
        () =>
            coordinator.state.transportPhase ==
            CollaborationTransportPhase.online,
      );

      expect(transport.submittedSessions, isEmpty);
      expect(coordinator.state.pendingCount, 1);
      expect(coordinator.state.canEdit, isFalse);
      await coordinator.stop();
    });

    test('membershipChanged refreshes role without becoming incompatible',
        () async {
      var membershipCalls = 0;
      final replica = _FakeReplica(cursor: 0);
      final transport = _FakeTransport(
        membership: (sessionId) async {
          membershipCalls += 1;
          return _membership(
            sessionId,
            role:
                membershipCalls == 1 ? SessionRole.editor : SessionRole.viewer,
          );
        },
      );
      final sockets = _FakeSocketConnector(autoReady: true);
      final coordinator = CollaborationSyncCoordinator(
        transport: transport,
        replica: replica,
        sockets: sockets,
      );

      coordinator.start(
        identity: _identity('session-a'),
        role: SessionRole.editor,
      );
      await _waitUntil(
        () =>
            coordinator.state.transportPhase ==
            CollaborationTransportPhase.online,
      );
      sockets.lastSocket!.add(jsonEncode({
        'type': 'membershipChanged',
        'role': 'viewer',
        'membershipVersion': 2,
      }));
      await _waitUntil(() => coordinator.state.role == SessionRole.viewer);

      expect(coordinator.state.canEdit, isFalse);
      expect(replica.persistedRoles.last, SessionRole.viewer);
      expect(
        coordinator.state.transportPhase,
        isNot(CollaborationTransportPhase.incompatible),
      );
      await coordinator.stop();
    });

    test(
        'delivers member-only live-draft controls without advancing event cursor',
        () async {
      final replica = _FakeReplica(cursor: 3);
      final sockets = _FakeSocketConnector(autoReady: true);
      final controls = <JsonObject>[];
      final coordinator = CollaborationSyncCoordinator(
        transport: _FakeTransport(),
        replica: replica,
        sockets: sockets,
        onControlMessage: controls.add,
      );

      coordinator.start(
        identity: _identity('session-a'),
        role: SessionRole.viewer,
      );
      await _waitUntil(
        () =>
            coordinator.state.transportPhase ==
            CollaborationTransportPhase.online,
      );
      sockets.lastSocket!.add(jsonEncode({
        'type': 'liveDraft.updated',
        'sessionId': 'session-a',
        'occurredAt': '2026-07-13T08:00:00.000Z',
        'draft': {'draftId': 'draft-1', 'version': 2},
      }));
      await _waitUntil(() => controls.length == 1);

      expect(controls.single['type'], 'liveDraft.updated');
      expect(coordinator.state.lastAppliedSeq, 3);
      expect(
          coordinator.state.transportPhase, CollaborationTransportPhase.online);
      await coordinator.stop();
    });

    test('discards a ticket until its membership is persisted locally',
        () async {
      var membershipCalls = 0;
      final replica = _FakeReplica(cursor: 0);
      final transport = _FakeTransport(
        membership: (sessionId) async {
          membershipCalls += 1;
          return _membership(
            sessionId,
            role:
                membershipCalls == 1 ? SessionRole.editor : SessionRole.viewer,
            version: membershipCalls == 1 ? 1 : 2,
          );
        },
        ticket: (sessionId, afterSeq, call) => WebSocketTicketDto(
          ticket: 'ticket-$call-$afterSeq',
          expiresAt: DateTime.now().add(const Duration(minutes: 1)),
          sessionId: sessionId,
          role: SessionRole.viewer,
          membershipVersion: 2,
          afterSeq: afterSeq,
        ),
      );
      final coordinator = CollaborationSyncCoordinator(
        transport: transport,
        replica: replica,
        sockets: _FakeSocketConnector(autoReady: true),
      );

      coordinator.start(
        identity: _identity('session-a'),
        role: SessionRole.editor,
      );
      await _waitUntil(
        () =>
            coordinator.state.transportPhase ==
            CollaborationTransportPhase.online,
      );

      expect(transport.ticketCalls, 2);
      expect(replica.persistedRoles, [SessionRole.editor, SessionRole.viewer]);
      expect(coordinator.state.role, SessionRole.viewer);
      expect(coordinator.state.canEdit, isFalse);
      await coordinator.stop();
    });

    test('a context switch cannot continue the old account pipeline', () async {
      final replica = _FakeReplica(cursor: 0);
      final oldMembership = Completer<MembershipDto>();
      final transport = _FakeTransport(
        membership: (sessionId) {
          if (sessionId == 'session-old') return oldMembership.future;
          return Future.value(
            _membership(sessionId, accountId: 'account-new'),
          );
        },
      );
      final sockets = _FakeSocketConnector(autoReady: true);
      final coordinator = CollaborationSyncCoordinator(
        transport: transport,
        replica: replica,
        sockets: sockets,
      );

      coordinator.start(
        identity: _identity('session-old', accountId: 'account-old'),
        role: SessionRole.editor,
      );
      await _waitUntil(
        () => transport.membershipSessions.contains('session-old'),
      );
      coordinator.start(
        identity: _identity('session-new', accountId: 'account-new'),
        role: SessionRole.editor,
      );
      oldMembership.complete(
        _membership('session-old', accountId: 'account-old'),
      );
      await _waitUntil(
        () =>
            coordinator.state.transportPhase ==
            CollaborationTransportPhase.online,
      );

      expect(coordinator.state.identity?.sessionId, 'session-new');
      expect(transport.eventSessions, everyElement('session-new'));
      expect(transport.submittedSessions, isEmpty);
      await coordinator.stop();
    });

    test('records accepted canonical events and per-entity conflicts',
        () async {
      final acceptedMutation = _mutation('mutation-accepted', 'log-1');
      final conflictMutation = _mutation('mutation-conflict', 'log-2');
      final replica = _FakeReplica(
        cursor: 0,
        pending: [acceptedMutation, conflictMutation],
      );
      final canonical = _event(
        seq: 1,
        eventId: 'accepted-event',
        mutationId: acceptedMutation.mutationId,
        entityId: acceptedMutation.entityId,
      );
      final transport = _FakeTransport(
        submit: (operations) => MutationBatchResultDto(
          headSeq: 1,
          results: [
            MutationResultDto(
              mutationId: acceptedMutation.mutationId,
              status: 'accepted',
              event: canonical,
            ),
            MutationResultDto(
              mutationId: conflictMutation.mutationId,
              status: 'conflict',
              code: 'VERSION_CONFLICT',
              currentVersion: 4,
              currentEntity: const {'syncId': 'log-2', 'version': 4},
            ),
          ],
        ),
      );
      final coordinator = CollaborationSyncCoordinator(
        transport: transport,
        replica: replica,
        sockets: _FakeSocketConnector(autoReady: true),
      );

      coordinator.start(
          identity: _identity('session-a'), role: SessionRole.editor);
      await _waitUntil(
        () =>
            coordinator.state.transportPhase ==
            CollaborationTransportPhase.online,
      );

      expect(replica.acceptedMutationIds, ['mutation-accepted']);
      expect(replica.appliedEventIds, contains('accepted-event'));
      expect(replica.conflictMutationIds, ['mutation-conflict']);
      expect(coordinator.state.pendingCount, 0);
      expect(coordinator.state.conflictCount, 1);
      await coordinator.stop();
    });

    test('malformed accepted events return mutations to retry', () async {
      final cases = <String, CollaborationEventDto>{
        'entity type': _event(
          seq: 1,
          mutationId: 'invalid-entity-type',
          entityId: 'log-1',
          entityType: 'session',
          type: 'session.updated',
          entityVersion: 2,
        ),
        'entity id': _event(
          seq: 1,
          mutationId: 'invalid-entity-id',
          entityId: 'other-log',
          entityVersion: 2,
        ),
        'entity version': _event(
          seq: 1,
          mutationId: 'invalid-entity-version',
          entityId: 'log-1',
          entityVersion: 3,
        ),
        'event type': _event(
          seq: 1,
          mutationId: 'invalid-event-type',
          entityId: 'log-1',
          type: 'log.deleted',
          entityVersion: 2,
        ),
      };

      for (final entry in cases.entries) {
        final mutationId = entry.value.mutationId!;
        final mutation = _mutation(mutationId, 'log-1');
        final replica = _FakeReplica(cursor: 0, pending: [mutation]);
        final backoff = Completer<void>();
        final transport = _FakeTransport(
          submit: (_) => MutationBatchResultDto(
            headSeq: 1,
            results: [
              MutationResultDto(
                mutationId: mutationId,
                status: 'accepted',
                event: entry.value,
              ),
            ],
          ),
        );
        final coordinator = CollaborationSyncCoordinator(
          transport: transport,
          replica: replica,
          sockets: _FakeSocketConnector(),
          delay: (_) => backoff.future,
        );

        coordinator.start(
          identity: _identity('session-a'),
          role: SessionRole.editor,
        );
        await _waitUntil(
          () => coordinator.state.lastErrorCode == 'INVALID_MUTATION_RESULT',
        );

        expect(replica.acceptedMutationIds, isEmpty, reason: entry.key);
        expect(replica.appliedEventIds, isEmpty, reason: entry.key);
        expect(replica.stateOf(mutationId), 'retrying', reason: entry.key);
        expect(
          coordinator.state.transportPhase,
          CollaborationTransportPhase.backingOff,
          reason: entry.key,
        );
        await coordinator.stop();
        backoff.complete();
      }
    });

    test('accepted gap catch-up unlocks and flushes a dependent mutation',
        () async {
      final first = _mutation('mutation-first', 'log-1');
      final dependent = _mutation('mutation-dependent', 'log-2');
      final replica = _FakeReplica(
        cursor: 0,
        pending: [first, dependent],
        dependencies: {'mutation-dependent': 'mutation-first'},
      );
      final remoteEvents = <CollaborationEventDto>[];
      final submitted = <List<String>>[];
      final transport = _FakeTransport(
        events: (sessionId, afterSeq) {
          final events = remoteEvents
              .where((event) => event.seq > afterSeq)
              .toList(growable: false);
          final head = remoteEvents.isEmpty ? 0 : remoteEvents.last.seq;
          return SessionEventsPageDto(
            afterSeq: afterSeq,
            toSeq: events.isEmpty ? afterSeq : events.last.seq,
            headSeq: head,
            minAvailableSeq: 0,
            hasMore: false,
            events: events,
          );
        },
        submit: (operations) {
          submitted.add(
              operations.map((operation) => operation.mutationId).toList());
          if (operations.single.mutationId == 'mutation-first') {
            final concurrent = _event(seq: 1, eventId: 'concurrent-event');
            final accepted = _event(
              seq: 2,
              eventId: 'first-event',
              mutationId: 'mutation-first',
            );
            remoteEvents.addAll([concurrent, accepted]);
            return MutationBatchResultDto(
              headSeq: 2,
              results: [
                MutationResultDto(
                  mutationId: 'mutation-first',
                  status: 'accepted',
                  event: accepted,
                ),
              ],
            );
          }
          final accepted = _event(
            seq: 3,
            eventId: 'dependent-event',
            mutationId: 'mutation-dependent',
            entityId: 'log-2',
          );
          remoteEvents.add(accepted);
          return MutationBatchResultDto(
            headSeq: 3,
            results: [
              MutationResultDto(
                mutationId: 'mutation-dependent',
                status: 'accepted',
                event: accepted,
              ),
            ],
          );
        },
      );
      final coordinator = CollaborationSyncCoordinator(
        transport: transport,
        replica: replica,
        sockets: _FakeSocketConnector(autoReady: true),
      );

      coordinator.start(
        identity: _identity('session-a'),
        role: SessionRole.editor,
      );
      await _waitUntil(
        () =>
            coordinator.state.transportPhase ==
            CollaborationTransportPhase.online,
      );

      expect(submitted, [
        ['mutation-first'],
        ['mutation-dependent'],
      ]);
      expect(replica.cursor, 3);
      expect(coordinator.state.pendingCount, 0);
      await coordinator.stop();
    });

    test('keeps a permanent mutation rejection visible', () async {
      final mutation = _mutation('mutation-rejected', 'log-1');
      final replica = _FakeReplica(cursor: 0, pending: [mutation]);
      final transport = _FakeTransport(
        submit: (_) => const MutationBatchResultDto(
          headSeq: 0,
          results: [
            MutationResultDto(
              mutationId: 'mutation-rejected',
              status: 'rejected',
              code: 'VALIDATION_FAILED',
              message: 'remarks is too long',
            ),
          ],
        ),
      );
      final coordinator = CollaborationSyncCoordinator(
        transport: transport,
        replica: replica,
        sockets: _FakeSocketConnector(autoReady: true),
      );

      coordinator.start(
        identity: _identity('session-a'),
        role: SessionRole.editor,
      );
      await _waitUntil(
        () =>
            coordinator.state.transportPhase ==
            CollaborationTransportPhase.online,
      );

      expect(coordinator.state.lastErrorCode, 'VALIDATION_FAILED');
      expect(coordinator.state.lastErrorMessage, 'remarks is too long');
      expect(coordinator.state.pendingCount, 1);
      expect(coordinator.state.rejectedCount, 1);

      replica.clearRejected();
      coordinator.wake();
      await _waitUntil(
        () =>
            coordinator.state.rejectedCount == 0 &&
            coordinator.state.lastErrorCode == null,
      );
      await coordinator.stop();
    });

    test('reinstalls a tombstone-complete snapshot after cursor expiry',
        () async {
      final mutation = _mutation('mutation-after-snapshot', 'log-local');
      final replica = _FakeReplica(cursor: 0, pending: [mutation]);
      final states = <CollaborationSyncState>[];
      var remoteHead = 6;
      final transport = _FakeTransport(
        snapshot: (sessionId, includeDeleted, call) => _snapshotDto(
          sessionId,
          highWatermarkSeq: 5,
          includesDeletedLogs: true,
        ),
        events: (sessionId, afterSeq) {
          if (afterSeq == 0) {
            return const SessionEventsPageDto(
              afterSeq: 0,
              toSeq: 0,
              headSeq: 6,
              minAvailableSeq: 5,
              hasMore: true,
              events: [],
            );
          }
          return SessionEventsPageDto(
            afterSeq: afterSeq,
            toSeq: afterSeq == 5 ? 6 : afterSeq,
            headSeq: max(remoteHead, afterSeq),
            minAvailableSeq: 5,
            hasMore: false,
            events: afterSeq == 5 ? [_event(seq: 6)] : const [],
          );
        },
        submit: (operations) {
          remoteHead = 7;
          return MutationBatchResultDto(
            headSeq: 7,
            results: [
              MutationResultDto(
                mutationId: operations.single.mutationId,
                status: 'accepted',
                event: _event(
                  seq: 7,
                  mutationId: operations.single.mutationId,
                  entityId: operations.single.entityId,
                ),
              ),
            ],
          );
        },
      );
      final coordinator = CollaborationSyncCoordinator(
        transport: transport,
        replica: replica,
        sockets: _FakeSocketConnector(autoReady: true),
        onStateChanged: states.add,
      );

      coordinator.start(
        identity: _identity('session-a'),
        role: SessionRole.editor,
      );
      await _waitUntil(
        () =>
            coordinator.state.transportPhase ==
                CollaborationTransportPhase.online &&
            replica.cursor == 7,
      );

      expect(transport.snapshotCalls, 1);
      expect(transport.snapshotIncludesDeleted, [isTrue]);
      expect(replica.installedSnapshots.single.highWatermarkSeq, 5);
      expect(transport.submittedSessions, ['session-a']);
      expect(
        states.any(
          (state) =>
              state.replicaPhase == CollaborationReplicaPhase.resyncing &&
              state.writeSuspended,
        ),
        isTrue,
      );
      expect(coordinator.state.writeSuspended, isFalse);
      await coordinator.stop();
    });

    test('retries a failed snapshot fetch while keeping writes suspended',
        () async {
      final states = <CollaborationSyncState>[];
      final transport = _FakeTransport(
        snapshot: (sessionId, includeDeleted, call) {
          if (call == 1) {
            throw const CollaborationSyncException(
              code: 'SNAPSHOT_FETCH_FAILED',
              message: 'temporary snapshot failure',
              retryable: true,
            );
          }
          return _snapshotDto(
            sessionId,
            highWatermarkSeq: 4,
            includesDeletedLogs: true,
          );
        },
        events: (sessionId, afterSeq) => SessionEventsPageDto(
          afterSeq: afterSeq,
          toSeq: afterSeq,
          headSeq: afterSeq == 0 ? 4 : afterSeq,
          minAvailableSeq: 4,
          hasMore: afterSeq == 0,
          events: const [],
        ),
      );
      final coordinator = CollaborationSyncCoordinator(
        transport: transport,
        replica: _FakeReplica(cursor: 0),
        sockets: _FakeSocketConnector(autoReady: true),
        delay: (_) async {},
        onStateChanged: states.add,
      );

      coordinator.start(
        identity: _identity('session-a'),
        role: SessionRole.editor,
      );
      await _waitUntil(
        () =>
            transport.snapshotCalls == 2 &&
            coordinator.state.transportPhase ==
                CollaborationTransportPhase.online,
      );

      final failedStates = states.where(
        (state) => state.lastErrorCode == 'SNAPSHOT_FETCH_FAILED',
      );
      expect(failedStates, isNotEmpty);
      expect(failedStates.every((state) => state.writeSuspended), isTrue);
      expect(coordinator.state.writeSuspended, isFalse);
      await coordinator.stop();
    });

    test('retries when membership role changes during snapshot fetch',
        () async {
      var membershipCalls = 0;
      final states = <CollaborationSyncState>[];
      final replica = _FakeReplica(cursor: 0);
      final transport = _FakeTransport(
        membership: (sessionId) async {
          membershipCalls += 1;
          return _membership(
            sessionId,
            role: membershipCalls < 3 ? SessionRole.editor : SessionRole.viewer,
            version: membershipCalls < 3 ? 1 : 2,
          );
        },
        snapshot: (sessionId, includeDeleted, call) => _snapshotDto(
          sessionId,
          highWatermarkSeq: 4,
          includesDeletedLogs: true,
          role: SessionRole.viewer,
        ),
        events: (sessionId, afterSeq) => SessionEventsPageDto(
          afterSeq: afterSeq,
          toSeq: afterSeq,
          headSeq: afterSeq == 0 ? 4 : afterSeq,
          minAvailableSeq: 4,
          hasMore: afterSeq == 0,
          events: const [],
        ),
        ticket: (sessionId, afterSeq, call) => WebSocketTicketDto(
          ticket: 'viewer-ticket-$call',
          expiresAt: DateTime.now().add(const Duration(minutes: 1)),
          sessionId: sessionId,
          role: SessionRole.viewer,
          membershipVersion: 2,
          afterSeq: afterSeq,
        ),
      );
      final coordinator = CollaborationSyncCoordinator(
        transport: transport,
        replica: replica,
        sockets: _FakeSocketConnector(autoReady: true),
        delay: (_) async {},
        onStateChanged: states.add,
      );

      coordinator.start(
        identity: _identity('session-a'),
        role: SessionRole.editor,
      );
      await _waitUntil(
        () =>
            transport.snapshotCalls == 2 &&
            coordinator.state.transportPhase ==
                CollaborationTransportPhase.online,
      );

      expect(
        states.any(
          (state) =>
              state.lastErrorCode == 'MEMBERSHIP_CHANGING' &&
              state.writeSuspended &&
              state.transportPhase == CollaborationTransportPhase.backingOff,
        ),
        isTrue,
      );
      expect(replica.installedSnapshots, hasLength(1));
      expect(
          replica.installedSnapshots.single.session.role, SessionRole.viewer);
      expect(coordinator.state.role, SessionRole.viewer);
      expect(coordinator.state.canEdit, isFalse);
      await coordinator.stop();
    });

    test('rejects an incomplete resync snapshot without installing it',
        () async {
      final transport = _FakeTransport(
        snapshot: (sessionId, includeDeleted, call) => _snapshotDto(
          sessionId,
          highWatermarkSeq: 4,
          includesDeletedLogs: false,
        ),
        events: (sessionId, afterSeq) => SessionEventsPageDto(
          afterSeq: afterSeq,
          toSeq: afterSeq,
          headSeq: 4,
          minAvailableSeq: 4,
          hasMore: true,
          events: const [],
        ),
      );
      final replica = _FakeReplica(cursor: 0);
      final coordinator = CollaborationSyncCoordinator(
        transport: transport,
        replica: replica,
        sockets: _FakeSocketConnector(),
      );

      coordinator.start(
        identity: _identity('session-a'),
        role: SessionRole.editor,
      );
      await _waitUntil(
        () => coordinator.state.lastErrorCode == 'SNAPSHOT_CONTEXT_MISMATCH',
      );

      expect(coordinator.state.transportPhase,
          CollaborationTransportPhase.incompatible);
      expect(coordinator.state.writeSuspended, isTrue);
      expect(replica.installedSnapshots, isEmpty);
      await coordinator.stop();
    });

    test('a WebSocket resync hint reinstalls once in the same generation',
        () async {
      final replica = _FakeReplica(cursor: 0);
      final transport = _FakeTransport(
        snapshot: (sessionId, includeDeleted, call) => _snapshotDto(
          sessionId,
          highWatermarkSeq: 2,
          includesDeletedLogs: true,
        ),
      );
      final sockets = _FakeSocketConnector(autoReady: true);
      final snapshots = <SessionSnapshotDto>[];
      final identity = _identity('session-a');
      final coordinator = CollaborationSyncCoordinator(
        transport: transport,
        replica: replica,
        sockets: sockets,
        onSnapshotInstalled: snapshots.add,
      );

      coordinator.start(identity: identity, role: SessionRole.editor);
      await _waitUntil(
        () =>
            coordinator.state.transportPhase ==
            CollaborationTransportPhase.online,
      );
      sockets.lastSocket!.add(jsonEncode({'type': 'resyncRequired'}));
      await _waitUntil(
        () =>
            sockets.connectCount == 2 &&
            coordinator.state.transportPhase ==
                CollaborationTransportPhase.online,
      );

      expect(transport.snapshotCalls, 1);
      expect(snapshots.single.highWatermarkSeq, 2);
      expect(replica.installIdentities, [identity]);
      expect(replica.cursor, 2);
      await coordinator.stop();
    });

    test('discards an old-account snapshot callback before Rust install',
        () async {
      final oldSnapshot = Completer<SessionSnapshotDto>();
      final transport = _FakeTransport(
        snapshot: (sessionId, includeDeleted, call) => oldSnapshot.future,
        events: (sessionId, afterSeq) {
          if (sessionId == 'session-a') {
            return SessionEventsPageDto(
              afterSeq: afterSeq,
              toSeq: afterSeq,
              headSeq: 3,
              minAvailableSeq: 3,
              hasMore: true,
              events: const [],
            );
          }
          return SessionEventsPageDto(
            afterSeq: afterSeq,
            toSeq: afterSeq,
            headSeq: afterSeq,
            minAvailableSeq: 0,
            hasMore: false,
            events: const [],
          );
        },
        membership: (sessionId) async => _membership(
          sessionId,
          accountId: sessionId == 'session-a' ? 'account-1' : 'account-2',
        ),
      );
      final replica = _FakeReplica(cursor: 0);
      final coordinator = CollaborationSyncCoordinator(
        transport: transport,
        replica: replica,
        sockets: _FakeSocketConnector(autoReady: true),
      );

      coordinator.start(
        identity: _identity('session-a'),
        role: SessionRole.editor,
      );
      await _waitUntil(() => transport.snapshotCalls == 1);
      coordinator.start(
        identity: _identity('session-b', accountId: 'account-2'),
        role: SessionRole.editor,
      );
      oldSnapshot.complete(
        _snapshotDto(
          'session-a',
          highWatermarkSeq: 3,
          includesDeletedLogs: true,
        ),
      );
      await _waitUntil(
        () =>
            coordinator.state.identity?.sessionId == 'session-b' &&
            coordinator.state.transportPhase ==
                CollaborationTransportPhase.online,
      );

      expect(replica.installIdentities, isEmpty);
      expect(coordinator.state.identity?.accountId, 'account-2');
      await coordinator.stop();
    });
  });
}

CollaborationSyncIdentity _identity(
  String sessionId, {
  String accountId = 'account-1',
}) =>
    CollaborationSyncIdentity(
      serverInstanceId: 'server-1',
      serverOrigin: 'https://example.test',
      accountId: accountId,
      sessionId: sessionId,
      deviceId: 'device-1',
    );

MembershipDto _membership(
  String sessionId, {
  String accountId = 'account-1',
  SessionRole role = SessionRole.editor,
  int version = 1,
}) =>
    MembershipDto(
      membershipId: 'membership-$sessionId',
      sessionId: sessionId,
      userId: accountId,
      role: role,
      version: version,
      joinedAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      removedAt: null,
    );

SessionSnapshotDto _snapshotDto(
  String sessionId, {
  required int highWatermarkSeq,
  required bool includesDeletedLogs,
  SessionRole role = SessionRole.editor,
}) {
  final timestamp = DateTime.utc(2026);
  return SessionSnapshotDto(
    protocolVersion: 1,
    session: CollaborationSessionDto(
      sessionId: sessionId,
      title: 'Session $sessionId',
      status: 'active',
      version: 1,
      role: role,
      highWatermarkSeq: highWatermarkSeq,
      createdAt: timestamp,
      updatedAt: timestamp,
      closedAt: null,
      deletedAt: null,
    ),
    highWatermarkSeq: highWatermarkSeq,
    includesDeletedLogs: includesDeletedLogs,
    logs: const [],
  );
}

CollaborationMutationDto _mutation(String mutationId, String entityId) =>
    CollaborationMutationDto(
      mutationId: mutationId,
      entityType: 'log',
      entityId: entityId,
      operation: 'update',
      baseVersion: 1,
      observedSeq: 0,
      patch: const {'remarks': 'updated'},
      queuedAt: DateTime.utc(2026),
    );

CollaborationEventDto _event({
  required int seq,
  String? eventId,
  String? mutationId,
  String entityId = 'log-1',
  String entityType = 'log',
  String type = 'log.updated',
  int? entityVersion,
}) =>
    CollaborationEventDto(
      protocolVersion: 1,
      eventId: eventId ?? 'event-$seq',
      sessionId: 'session-a',
      seq: seq,
      type: type,
      entityType: entityType,
      entityId: entityId,
      entityVersion: entityVersion ?? (mutationId == null ? seq : 2),
      mutationId: mutationId,
      occurredAt: DateTime.utc(2026),
      payload: {
        if (entityType == 'log') 'syncId': entityId else 'sessionId': entityId,
        'version': entityVersion ?? (mutationId == null ? seq : 2),
      },
    );

Future<void> _waitUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition was not reached before timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

typedef _EventsFactory = SessionEventsPageDto Function(
  String sessionId,
  int afterSeq,
);
typedef _SubmitFactory = MutationBatchResultDto Function(
  List<CollaborationMutationDto> operations,
);
typedef _TicketFactory = WebSocketTicketDto Function(
  String sessionId,
  int afterSeq,
  int call,
);
typedef _SnapshotFactory = FutureOr<SessionSnapshotDto> Function(
  String sessionId,
  bool includeDeleted,
  int call,
);

final class _FakeTransport implements CollaborationSyncTransport {
  _FakeTransport({
    _EventsFactory? events,
    _SubmitFactory? submit,
    Future<MembershipDto> Function(String sessionId)? membership,
    _TicketFactory? ticket,
    _SnapshotFactory? snapshot,
  })  : _events = events,
        _submit = submit,
        _membershipFactory = membership,
        _ticket = ticket,
        _snapshot = snapshot;

  final _EventsFactory? _events;
  final _SubmitFactory? _submit;
  final Future<MembershipDto> Function(String sessionId)? _membershipFactory;
  final _TicketFactory? _ticket;
  final _SnapshotFactory? _snapshot;
  final List<String> membershipSessions = [];
  final List<String> eventSessions = [];
  final List<String> submittedSessions = [];
  int ticketCalls = 0;
  int snapshotCalls = 0;
  final List<bool> snapshotIncludesDeleted = [];

  @override
  Future<MembershipDto> getMembership(String sessionId) {
    membershipSessions.add(sessionId);
    return _membershipFactory?.call(sessionId) ??
        Future.value(_membership(sessionId));
  }

  @override
  Future<SessionSnapshotDto> getSnapshot({
    required String sessionId,
    required bool includeDeleted,
  }) async {
    snapshotCalls += 1;
    snapshotIncludesDeleted.add(includeDeleted);
    final factory = _snapshot;
    if (factory != null) {
      return await factory(sessionId, includeDeleted, snapshotCalls);
    }
    return _snapshotDto(
      sessionId,
      highWatermarkSeq: 0,
      includesDeletedLogs: includeDeleted,
    );
  }

  @override
  Future<SessionEventsPageDto> getEvents({
    required String sessionId,
    required int afterSeq,
    int limit = 500,
  }) async {
    eventSessions.add(sessionId);
    return _events?.call(sessionId, afterSeq) ??
        SessionEventsPageDto(
          afterSeq: afterSeq,
          toSeq: afterSeq,
          headSeq: afterSeq,
          minAvailableSeq: 0,
          hasMore: false,
          events: const [],
        );
  }

  @override
  Future<MutationBatchResultDto> submitMutations({
    required String sessionId,
    required String deviceId,
    required List<CollaborationMutationDto> operations,
  }) async {
    submittedSessions.add(sessionId);
    return _submit?.call(operations) ??
        const MutationBatchResultDto(headSeq: 0, results: []);
  }

  @override
  Future<WebSocketTicketDto> createWebSocketTicket({
    required String sessionId,
    required String deviceId,
    required int afterSeq,
  }) async {
    ticketCalls += 1;
    return _ticket?.call(sessionId, afterSeq, ticketCalls) ??
        WebSocketTicketDto(
          ticket: 'ticket-$sessionId-$afterSeq',
          expiresAt: DateTime.now().add(const Duration(minutes: 1)),
          sessionId: sessionId,
          role: SessionRole.editor,
          membershipVersion: 1,
          afterSeq: afterSeq,
        );
  }

  @override
  Uri webSocketUri(String ticket) =>
      Uri.parse('ws://example.test/ws/collaboration?ticket=$ticket');
}

final class _FakeReplica implements CollaborationReplicaPort {
  _FakeReplica({
    required this.cursor,
    Map<String, int>? applied,
    List<CollaborationMutationDto> pending = const [],
    Map<String, String> dependencies = const {},
    this.canonicalSessionStatus = 'active',
  })  : _applied = {...?applied},
        _mutations = {
          for (final mutation in pending) mutation.mutationId: mutation,
        },
        _states = {
          for (final mutation in pending) mutation.mutationId: 'pending',
        },
        _dependencies = {...dependencies};

  int cursor;
  int head = 0;
  String? canonicalSessionStatus;
  final Map<String, int> _applied;
  final Map<String, CollaborationMutationDto> _mutations;
  final Map<String, String> _states;
  final Map<String, String> _dependencies;
  int duplicateCount = 0;
  int conflictCount = 0;
  bool revoked = false;
  final List<String> acceptedMutationIds = [];
  final List<String> conflictMutationIds = [];
  final List<SessionRole> persistedRoles = [];
  final List<SessionSnapshotDto> installedSnapshots = [];
  final List<CollaborationSyncIdentity> installIdentities = [];

  Iterable<String> get appliedEventIds => _applied.keys;
  String? stateOf(String mutationId) => _states[mutationId];

  @override
  Future<void> reinstallSnapshot(
    CollaborationSyncIdentity identity,
    MembershipDto membership,
    SessionSnapshotDto snapshot,
  ) async {
    installIdentities.add(identity);
    installedSnapshots.add(snapshot);
    cursor = snapshot.highWatermarkSeq;
    head = snapshot.highWatermarkSeq;
    canonicalSessionStatus = snapshot.session.status;
    _applied.clear();
  }

  void enqueue(CollaborationMutationDto mutation) {
    _mutations[mutation.mutationId] = mutation;
    _states[mutation.mutationId] = 'pending';
  }

  void clearRejected() {
    final rejected = _states.entries
        .where((entry) => entry.value == 'rejected')
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final mutationId in rejected) {
      _states.remove(mutationId);
      _mutations.remove(mutationId);
    }
  }

  @override
  Future<void> updateMembership(
    CollaborationSyncIdentity identity,
    MembershipDto membership,
  ) async {
    persistedRoles.add(membership.role);
  }

  @override
  Future<CollaborationReplicaStatus> getStatus(
    CollaborationSyncIdentity identity,
  ) async =>
      CollaborationReplicaStatus(
        lastAppliedSeq: cursor,
        lastSeenHeadSeq: max(head, cursor),
        pendingCount: _states.values
            .where((state) => const {
                  'pending',
                  'sending',
                  'accepted',
                  'retrying',
                  'rejected',
                }.contains(state))
            .length,
        conflictCount: conflictCount,
        rejectedCount:
            _states.values.where((state) => state == 'rejected').length,
        canonicalSessionStatus: canonicalSessionStatus,
      );

  @override
  Future<PendingCollaborationMutations> listPending(
    CollaborationSyncIdentity identity, {
    int limit = 100,
  }) async =>
      PendingCollaborationMutations(
        protocolVersion: 1,
        deviceId: identity.deviceId,
        operations: [
          for (final entry in _mutations.entries)
            if (_states[entry.key] == 'pending' ||
                _states[entry.key] == 'retrying')
              if (_dependencies[entry.key] == null ||
                  !_states.containsKey(_dependencies[entry.key]))
                entry.value,
        ].take(limit).toList(),
      );

  @override
  Future<void> markSending(
    CollaborationSyncIdentity identity,
    List<String> mutationIds,
  ) async {
    for (final id in mutationIds) {
      _states[id] = 'sending';
    }
  }

  @override
  Future<void> markAccepted(
    CollaborationSyncIdentity identity,
    String mutationId,
    int acceptedEventSeq,
  ) async {
    _states[mutationId] = 'accepted';
    acceptedMutationIds.add(mutationId);
  }

  @override
  Future<void> markRetry(
    CollaborationSyncIdentity identity,
    String mutationId, {
    required String code,
    required String message,
    required DateTime nextAttemptAt,
  }) async {
    _states[mutationId] = 'retrying';
  }

  @override
  Future<void> markRejected(
    CollaborationSyncIdentity identity,
    String mutationId, {
    required String code,
    required String message,
    Object? details,
  }) async {
    _states[mutationId] = 'rejected';
  }

  @override
  Future<void> recordConflict(
    CollaborationSyncIdentity identity,
    CollaborationMutationDto mutation,
    MutationResultDto result,
  ) async {
    _states[mutation.mutationId] = 'conflict';
    conflictCount += 1;
    conflictMutationIds.add(mutation.mutationId);
  }

  @override
  Future<CollaborationApplyResult> applyEvent(
    CollaborationSyncIdentity identity,
    CollaborationEventDto event,
  ) async {
    if (event.seq <= cursor) {
      if (_applied[event.eventId] != event.seq) {
        throw StateError('EVENT_FORK');
      }
      duplicateCount += 1;
      return CollaborationApplyResult(
        outcome: CollaborationApplyOutcome.duplicate,
        cursor: cursor,
        expectedSeq: cursor + 1,
      );
    }
    if (event.seq > cursor + 1) {
      return CollaborationApplyResult(
        outcome: CollaborationApplyOutcome.gap,
        cursor: cursor,
        expectedSeq: cursor + 1,
      );
    }
    cursor = event.seq;
    if (event.type == 'session.closed' || event.type == 'session.deleted') {
      canonicalSessionStatus = 'closed';
    } else if (event.type == 'session.reopened') {
      canonicalSessionStatus = 'active';
    }
    _applied[event.eventId] = event.seq;
    final mutationId = event.mutationId;
    if (mutationId != null && _states[mutationId] == 'accepted') {
      _states.remove(mutationId);
      _mutations.remove(mutationId);
    }
    return CollaborationApplyResult(
      outcome: CollaborationApplyOutcome.applied,
      cursor: cursor,
      expectedSeq: cursor + 1,
    );
  }

  @override
  Future<void> setHeadSeq(
    CollaborationSyncIdentity identity,
    int headSeq,
  ) async {
    head = max(head, headSeq);
  }

  @override
  Future<void> markRevoked(CollaborationSyncIdentity identity) async {
    revoked = true;
  }
}

final class _FakeSocketConnector implements CollaborationSocketConnector {
  _FakeSocketConnector({
    this.autoReady = false,
    this.closeFirstAfterReady = false,
  });

  final bool autoReady;
  final bool closeFirstAfterReady;
  int connectCount = 0;
  _FakeSocket? lastSocket;

  @override
  Future<CollaborationSocket> connect(Uri uri) async {
    connectCount += 1;
    final socket = _FakeSocket();
    lastSocket = socket;
    if (autoReady) {
      Timer.run(() async {
        if (socket.closed) return;
        final ticket = uri.queryParameters['ticket']!;
        final parts = ticket.split('-');
        final cursor = int.parse(parts.last);
        socket.add(jsonEncode({'type': 'ready', 'cursor': cursor}));
        if (closeFirstAfterReady && connectCount == 1) {
          await Future<void>.delayed(const Duration(milliseconds: 2));
          await socket.close();
        }
      });
    }
    return socket;
  }
}

final class _BlockingSocketConnector implements CollaborationSocketConnector {
  final Completer<void> connectStarted = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  Future<CollaborationSocket> connect(Uri uri) async {
    if (!connectStarted.isCompleted) connectStarted.complete();
    await release.future;
    final socket = _FakeSocket();
    Timer.run(() {
      if (socket.closed) return;
      final ticket = uri.queryParameters['ticket']!;
      final cursor = int.parse(ticket.split('-').last);
      socket.add(jsonEncode({'type': 'ready', 'cursor': cursor}));
    });
    return socket;
  }
}

final class _FakeSocket implements CollaborationSocket {
  final StreamController<Object?> _messages = StreamController<Object?>();
  bool closed = false;

  void add(Object? message) => _messages.add(message);

  @override
  Stream<Object?> get messages => _messages.stream;

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    await _messages.close();
  }
}
