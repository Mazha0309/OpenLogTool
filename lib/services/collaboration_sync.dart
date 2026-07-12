import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:openlogtool/models/collaboration_dto.dart';
import 'package:openlogtool/services/server_api.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum CollaborationTransportPhase {
  stopped,
  connecting,
  online,
  backingOff,
  authRequired,
  incompatible,
}

enum CollaborationReplicaPhase {
  localOnly,
  catchingUp,
  ready,
  resyncing,
  revoked,
  failed,
}

final class CollaborationSyncIdentity {
  const CollaborationSyncIdentity({
    required this.serverInstanceId,
    required this.accountId,
    required this.sessionId,
    required this.deviceId,
  });

  final String serverInstanceId;
  final String accountId;
  final String sessionId;
  final String deviceId;

  String get partitionKey => '$serverInstanceId/$accountId/$sessionId';

  @override
  bool operator ==(Object other) =>
      other is CollaborationSyncIdentity &&
      other.serverInstanceId == serverInstanceId &&
      other.accountId == accountId &&
      other.sessionId == sessionId &&
      other.deviceId == deviceId;

  @override
  int get hashCode => Object.hash(
        serverInstanceId,
        accountId,
        sessionId,
        deviceId,
      );
}

final class CollaborationReplicaStatus {
  const CollaborationReplicaStatus({
    required this.lastAppliedSeq,
    required this.lastSeenHeadSeq,
    required this.pendingCount,
    required this.conflictCount,
    required this.rejectedCount,
    this.lastSuccessfulSyncAt,
    this.canonicalSessionStatus,
  });

  factory CollaborationReplicaStatus.fromJson(Object? json) {
    final object = _jsonObject(json, 'syncStatus');
    return CollaborationReplicaStatus(
      lastAppliedSeq: _jsonInt(object, 'lastAppliedSeq'),
      lastSeenHeadSeq: _jsonInt(object, 'lastSeenHeadSeq'),
      pendingCount: _jsonInt(object, 'pendingCount'),
      conflictCount: _jsonInt(object, 'conflictCount'),
      rejectedCount: _jsonInt(object, 'rejectedCount'),
      lastSuccessfulSyncAt: _optionalDateTime(
        object,
        'lastSuccessfulSyncAt',
      ),
      canonicalSessionStatus: _optionalString(
        object,
        'canonicalSessionStatus',
      ),
    );
  }

  final int lastAppliedSeq;
  final int lastSeenHeadSeq;
  final int pendingCount;
  final int conflictCount;
  final int rejectedCount;
  final DateTime? lastSuccessfulSyncAt;
  final String? canonicalSessionStatus;
}

final class PendingCollaborationMutations {
  const PendingCollaborationMutations({
    required this.protocolVersion,
    required this.deviceId,
    required this.operations,
  });

  factory PendingCollaborationMutations.fromJson(Object? json) {
    final object = _jsonObject(json, 'pendingMutations');
    final values = object['operations'];
    if (values is! List) {
      throw const FormatException('operations must be a JSON array');
    }
    return PendingCollaborationMutations(
      protocolVersion: _jsonInt(object, 'protocolVersion'),
      deviceId: _jsonString(object, 'deviceId'),
      operations: List.unmodifiable(
        values.map(CollaborationMutationDto.fromJson),
      ),
    );
  }

  final int protocolVersion;
  final String deviceId;
  final List<CollaborationMutationDto> operations;
}

enum CollaborationApplyOutcome { applied, duplicate, gap }

final class CollaborationApplyResult {
  const CollaborationApplyResult({
    required this.outcome,
    required this.cursor,
    required this.expectedSeq,
  });

  factory CollaborationApplyResult.fromJson(Object? json) {
    final object = _jsonObject(json, 'applyEventResult');
    final outcome = switch (_jsonString(object, 'outcome')) {
      'applied' => CollaborationApplyOutcome.applied,
      'duplicate' => CollaborationApplyOutcome.duplicate,
      'gap' => CollaborationApplyOutcome.gap,
      _ => throw const FormatException('unknown apply event outcome'),
    };
    return CollaborationApplyResult(
      outcome: outcome,
      cursor: _jsonInt(object, 'cursor'),
      expectedSeq: _jsonInt(object, 'expectedSeq'),
    );
  }

  final CollaborationApplyOutcome outcome;
  final int cursor;
  final int expectedSeq;
}

abstract interface class CollaborationReplicaPort {
  Future<void> updateMembership(
    CollaborationSyncIdentity identity,
    MembershipDto membership,
  );

  Future<CollaborationReplicaStatus> getStatus(
    CollaborationSyncIdentity identity,
  );

  Future<PendingCollaborationMutations> listPending(
    CollaborationSyncIdentity identity, {
    int limit = 100,
  });

  Future<void> markSending(
    CollaborationSyncIdentity identity,
    List<String> mutationIds,
  );

  Future<void> markAccepted(
    CollaborationSyncIdentity identity,
    String mutationId,
    int acceptedEventSeq,
  );

  Future<void> markRetry(
    CollaborationSyncIdentity identity,
    String mutationId, {
    required String code,
    required String message,
    required DateTime nextAttemptAt,
  });

  Future<void> markRejected(
    CollaborationSyncIdentity identity,
    String mutationId, {
    required String code,
    required String message,
    Object? details,
  });

  Future<void> recordConflict(
    CollaborationSyncIdentity identity,
    CollaborationMutationDto mutation,
    MutationResultDto result,
  );

  Future<CollaborationApplyResult> applyEvent(
    CollaborationSyncIdentity identity,
    CollaborationEventDto event,
  );

  Future<void> setHeadSeq(
    CollaborationSyncIdentity identity,
    int headSeq,
  );

  Future<void> markRevoked(CollaborationSyncIdentity identity);
}

abstract interface class CollaborationSyncTransport {
  Future<MembershipDto> getMembership(String sessionId);

  Future<SessionEventsPageDto> getEvents({
    required String sessionId,
    required int afterSeq,
    int limit = 500,
  });

  Future<MutationBatchResultDto> submitMutations({
    required String sessionId,
    required String deviceId,
    required List<CollaborationMutationDto> operations,
  });

  Future<WebSocketTicketDto> createWebSocketTicket({
    required String sessionId,
    required String deviceId,
    required int afterSeq,
  });

  Uri webSocketUri(String ticket);
}

final class ServerApiCollaborationSyncTransport
    implements CollaborationSyncTransport {
  const ServerApiCollaborationSyncTransport(this.api);

  final ServerApi api;

  @override
  Future<MembershipDto> getMembership(String sessionId) =>
      api.getMembership(sessionId);

  @override
  Future<SessionEventsPageDto> getEvents({
    required String sessionId,
    required int afterSeq,
    int limit = 500,
  }) =>
      api.getSessionEvents(
        sessionId: sessionId,
        afterSeq: afterSeq,
        limit: limit,
      );

  @override
  Future<MutationBatchResultDto> submitMutations({
    required String sessionId,
    required String deviceId,
    required List<CollaborationMutationDto> operations,
  }) =>
      api.submitMutations(
        sessionId: sessionId,
        deviceId: deviceId,
        operations: operations,
      );

  @override
  Future<WebSocketTicketDto> createWebSocketTicket({
    required String sessionId,
    required String deviceId,
    required int afterSeq,
  }) =>
      api.createCollaborationWebSocketTicket(
        sessionId: sessionId,
        deviceId: deviceId,
        afterSeq: afterSeq,
      );

  @override
  Uri webSocketUri(String ticket) => api.collaborationWebSocketUri(ticket);
}

abstract interface class CollaborationSocket {
  Stream<Object?> get messages;

  Future<void> close();
}

abstract interface class CollaborationSocketConnector {
  Future<CollaborationSocket> connect(Uri uri);
}

final class WebSocketChannelConnector implements CollaborationSocketConnector {
  const WebSocketChannelConnector();

  @override
  Future<CollaborationSocket> connect(Uri uri) async {
    final channel = WebSocketChannel.connect(uri);
    await channel.ready;
    return _WebSocketChannelSocket(channel);
  }
}

final class _WebSocketChannelSocket implements CollaborationSocket {
  const _WebSocketChannelSocket(this.channel);

  final WebSocketChannel channel;

  @override
  Stream<Object?> get messages => channel.stream;

  @override
  Future<void> close() async {
    await channel.sink.close();
  }
}

final class CollaborationSyncState {
  const CollaborationSyncState({
    required this.identity,
    required this.role,
    required this.transportPhase,
    required this.replicaPhase,
    required this.lastAppliedSeq,
    required this.serverHeadSeq,
    required this.pendingCount,
    required this.conflictCount,
    required this.rejectedCount,
    required this.sessionClosed,
    required this.writeSuspended,
    required this.lastSuccessfulSyncAt,
    required this.lastErrorCode,
    required this.lastErrorMessage,
    required this.nextRetryAt,
    required this.remoteCommitPendingLocalApply,
  });

  final CollaborationSyncIdentity? identity;
  final SessionRole? role;
  final CollaborationTransportPhase transportPhase;
  final CollaborationReplicaPhase replicaPhase;
  final int lastAppliedSeq;
  final int serverHeadSeq;
  final int pendingCount;
  final int conflictCount;
  final int rejectedCount;
  final bool sessionClosed;
  final bool writeSuspended;
  final DateTime? lastSuccessfulSyncAt;
  final String? lastErrorCode;
  final String? lastErrorMessage;
  final DateTime? nextRetryAt;
  final bool remoteCommitPendingLocalApply;

  bool get canEdit =>
      identity != null &&
      replicaPhase == CollaborationReplicaPhase.ready &&
      !sessionClosed &&
      !writeSuspended &&
      (role == SessionRole.owner || role == SessionRole.editor);
}

typedef CollaborationSyncStateListener = void Function(
  CollaborationSyncState state,
);
typedef CollaborationEventApplied = FutureOr<void> Function(
  CollaborationEventDto event,
);
typedef CollaborationDelay = Future<void> Function(Duration duration);
typedef CollaborationClock = DateTime Function();

final class CollaborationSyncException implements Exception {
  const CollaborationSyncException({
    required this.code,
    required this.message,
    this.retryable = false,
    this.remoteCommitted = false,
    this.retryAfter,
    this.cause,
  });

  final String code;
  final String message;
  final bool retryable;
  final bool remoteCommitted;
  final Duration? retryAfter;
  final Object? cause;

  @override
  String toString() => '$code: $message';
}

/// Serial Stage 2 synchronizer for one active collaboration context.
///
/// WebSocket messages are deliberately treated as hints. Every wake-up returns
/// to the authenticated events endpoint and advances the durable Rust cursor in
/// order, so reconnects and duplicate socket delivery share one code path.
final class CollaborationSyncCoordinator {
  CollaborationSyncCoordinator({
    required this.transport,
    required this.replica,
    CollaborationSocketConnector? sockets,
    this.onStateChanged,
    this.onEventApplied,
    CollaborationDelay? delay,
    CollaborationClock? clock,
    Random? random,
  })  : sockets = sockets ?? const WebSocketChannelConnector(),
        _delay = delay ?? Future<void>.delayed,
        _clock = clock ?? DateTime.now,
        _random = random ?? Random();

  final CollaborationSyncTransport transport;
  final CollaborationReplicaPort replica;
  final CollaborationSocketConnector sockets;
  final CollaborationSyncStateListener? onStateChanged;
  final CollaborationEventApplied? onEventApplied;
  final CollaborationDelay _delay;
  final CollaborationClock _clock;
  final Random _random;

  int _generation = 0;
  bool _disposed = false;
  CollaborationSocket? _activeSocket;
  StreamController<_SocketSignal>? _activeSignals;
  Future<void>? _loop;
  bool _wakePending = false;
  int _localStatusGeneration = 0;

  CollaborationSyncIdentity? _identity;
  SessionRole? _role;
  CollaborationTransportPhase _transportPhase =
      CollaborationTransportPhase.stopped;
  CollaborationReplicaPhase _replicaPhase = CollaborationReplicaPhase.localOnly;
  int _lastAppliedSeq = 0;
  int _serverHeadSeq = 0;
  int _pendingCount = 0;
  int _conflictCount = 0;
  int _rejectedCount = 0;
  bool _sessionClosed = false;
  bool _localSessionClosed = false;
  bool _writeSuspended = false;
  DateTime? _lastSuccessfulSyncAt;
  String? _lastErrorCode;
  String? _lastErrorMessage;
  String? _persistentWarningCode;
  String? _persistentWarningMessage;
  DateTime? _nextRetryAt;
  bool _remoteCommitPendingLocalApply = false;

  CollaborationSyncState get state => CollaborationSyncState(
        identity: _identity,
        role: _role,
        transportPhase: _transportPhase,
        replicaPhase: _replicaPhase,
        lastAppliedSeq: _lastAppliedSeq,
        serverHeadSeq: _serverHeadSeq,
        pendingCount: _pendingCount,
        conflictCount: _conflictCount,
        rejectedCount: _rejectedCount,
        sessionClosed: _sessionClosed,
        writeSuspended: _writeSuspended,
        lastSuccessfulSyncAt: _lastSuccessfulSyncAt,
        lastErrorCode: _lastErrorCode,
        lastErrorMessage: _lastErrorMessage,
        nextRetryAt: _nextRetryAt,
        remoteCommitPendingLocalApply: _remoteCommitPendingLocalApply,
      );

  bool get isRunning =>
      _identity != null &&
      _transportPhase != CollaborationTransportPhase.stopped &&
      _transportPhase != CollaborationTransportPhase.authRequired &&
      _transportPhase != CollaborationTransportPhase.incompatible;

  void start({
    required CollaborationSyncIdentity identity,
    required SessionRole role,
    bool sessionClosed = false,
  }) {
    if (_disposed) throw StateError('coordinator has been disposed');
    final generation = ++_generation;
    unawaited(_closeActiveTransport());
    _identity = identity;
    _wakePending = false;
    _role = role;
    _transportPhase = CollaborationTransportPhase.connecting;
    _replicaPhase = CollaborationReplicaPhase.catchingUp;
    _lastAppliedSeq = 0;
    _serverHeadSeq = 0;
    _pendingCount = 0;
    _conflictCount = 0;
    _rejectedCount = 0;
    _sessionClosed = false;
    _localSessionClosed = sessionClosed;
    _writeSuspended = sessionClosed;
    _lastSuccessfulSyncAt = null;
    _persistentWarningCode = null;
    _persistentWarningMessage = null;
    _clearError();
    _emit();
    _loop = _run(generation, identity);
  }

  /// Wakes the serial loop after a local transaction appended to the outbox.
  void wake() {
    final signals = _activeSignals;
    if (signals != null && !signals.isClosed) {
      signals.add(const _SocketSignal.wake());
    } else if (_identity != null) {
      // A local transaction can commit while the first REST cycle is ending
      // but before the socket signal stream exists. Keep the wake durable
      // across that connect window; the outbox itself remains the source of
      // truth, so coalescing multiple wakes is safe.
      _wakePending = true;
    }
    final identity = _identity;
    if (identity != null) {
      final generation = _generation;
      final statusGeneration = ++_localStatusGeneration;
      unawaited(
        _refreshLocalCounts(
          generation,
          statusGeneration,
          identity,
        ),
      );
    }
  }

  /// Locks local writes immediately while preserving the canonical active
  /// state. Older Log outbox entries must flush before the close mutation.
  void markSessionLocallyClosed() {
    if (_identity == null) return;
    _localSessionClosed = true;
    _writeSuspended = true;
    _emit();
    wake();
  }

  void markSessionLocallyReopened() {
    if (_identity == null) return;
    _localSessionClosed = false;
    _emit();
    wake();
  }

  Future<void> stop() async {
    _generation += 1;
    _identity = null;
    _wakePending = false;
    await _closeActiveTransport();
    _transportPhase = CollaborationTransportPhase.stopped;
    _replicaPhase = CollaborationReplicaPhase.localOnly;
    _nextRetryAt = null;
    _emit();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
    await _loop?.catchError((_) {});
  }

  Future<void> _run(
    int generation,
    CollaborationSyncIdentity identity,
  ) async {
    var retryAttempt = 0;
    while (_isCurrent(generation, identity)) {
      DateTime? onlineSince;
      try {
        _transportPhase = CollaborationTransportPhase.connecting;
        _nextRetryAt = null;
        _emitIfCurrent(generation, identity);

        var membership = await _refreshMembership(generation, identity);

        await _synchronizeOnce(generation, identity);
        _ensureCurrent(generation, identity);

        WebSocketTicketDto? ticket;
        for (var ticketAttempt = 0; ticketAttempt < 3; ticketAttempt += 1) {
          final candidate = await transport.createWebSocketTicket(
            sessionId: identity.sessionId,
            deviceId: identity.deviceId,
            afterSeq: _lastAppliedSeq,
          );
          _ensureCurrent(generation, identity);
          if (candidate.role == membership.role &&
              candidate.membershipVersion == membership.version) {
            ticket = candidate;
            break;
          }
          // Discard the unconsumed ticket. Its role/version snapshot is newer
          // than the membership persisted before ticket issuance, so using it
          // could reconnect while Rust still authorizes an obsolete role.
          membership = await _refreshMembership(generation, identity);
          _ensureCurrent(generation, identity);
          await _synchronizeOnce(generation, identity);
          _ensureCurrent(generation, identity);
        }
        if (ticket == null) {
          throw const CollaborationSyncException(
            code: 'MEMBERSHIP_CHANGING',
            message: 'Membership changed repeatedly while connecting',
            retryable: true,
          );
        }
        if (ticket.sessionId != identity.sessionId ||
            ticket.afterSeq != _lastAppliedSeq) {
          throw const CollaborationSyncException(
            code: 'WS_TICKET_CONTEXT_MISMATCH',
            message: 'WebSocket ticket does not match the local cursor',
          );
        }
        _role = ticket.role;
        final socket = await sockets.connect(
          transport.webSocketUri(ticket.ticket),
        );
        _ensureCurrent(generation, identity);
        _activeSocket = socket;
        onlineSince = _clock();
        await _listenToSocket(generation, identity, socket);
        _ensureCurrent(generation, identity);
        throw const CollaborationSyncException(
          code: 'WS_DISCONNECTED',
          message: 'The collaboration connection closed',
          retryable: true,
        );
      } catch (error) {
        if (!_isCurrent(generation, identity)) return;
        final syncError = _normalizeError(error);
        await _closeActiveTransport();
        if (!_isCurrent(generation, identity)) return;

        if (_isRevocation(syncError)) {
          try {
            await replica.markRevoked(identity);
          } catch (_) {
            // Authorization has already ended remotely; a local persistence
            // warning must not restart network writes.
          }
          if (!_isCurrent(generation, identity)) return;
          _replicaPhase = CollaborationReplicaPhase.revoked;
          _transportPhase = CollaborationTransportPhase.stopped;
          _setError(syncError);
          _emit();
          return;
        }
        if (_isAuthRequired(syncError)) {
          _transportPhase = CollaborationTransportPhase.authRequired;
          _setError(syncError);
          _emit();
          return;
        }
        if (syncError.code == 'CURSOR_EXPIRED' ||
            syncError.code == 'RESYNC_REQUIRED') {
          _replicaPhase = CollaborationReplicaPhase.resyncing;
          _transportPhase = CollaborationTransportPhase.stopped;
          _setError(syncError);
          _emit();
          return;
        }
        if (!syncError.retryable) {
          _replicaPhase = CollaborationReplicaPhase.failed;
          _transportPhase = CollaborationTransportPhase.incompatible;
          _setError(syncError);
          _emit();
          return;
        }

        if (onlineSince != null &&
            _clock().difference(onlineSince) >= const Duration(seconds: 30)) {
          retryAttempt = 0;
        }
        final retryDelay = syncError.retryAfter ?? _backoff(retryAttempt++);
        _transportPhase = CollaborationTransportPhase.backingOff;
        _setError(syncError);
        _nextRetryAt = _clock().add(retryDelay);
        _emit();
        await _delay(retryDelay);
      }
    }
  }

  Future<void> _synchronizeOnce(
    int generation,
    CollaborationSyncIdentity identity,
  ) async {
    if (_replicaPhase != CollaborationReplicaPhase.ready) {
      _replicaPhase = CollaborationReplicaPhase.catchingUp;
      _emitIfCurrent(generation, identity);
    }
    await _catchUp(generation, identity);
    _ensureCurrent(generation, identity);
    for (var settleAttempt = 0; settleAttempt < 100; settleAttempt += 1) {
      final canFlush = (_role == SessionRole.owner && _sessionClosed) ||
          ((_role == SessionRole.owner || _role == SessionRole.editor) &&
              !_sessionClosed);
      if (!canFlush) break;
      final sent = await _flushOutbox(generation, identity);
      _ensureCurrent(generation, identity);
      final applied = await _catchUp(generation, identity);
      _ensureCurrent(generation, identity);
      if (!sent && !applied) break;
      if (settleAttempt == 99) {
        throw const CollaborationSyncException(
          code: 'SYNC_SETTLE_LIMIT_EXCEEDED',
          message: 'Synchronization did not reach a stable boundary',
          retryable: true,
        );
      }
    }
    await _refreshStatus(generation, identity);
    _ensureCurrent(generation, identity);
    _replicaPhase = CollaborationReplicaPhase.ready;
    _lastSuccessfulSyncAt = _clock();
    _remoteCommitPendingLocalApply = false;
    _clearError();
    _emit();
  }

  Future<bool> _catchUp(
    int generation,
    CollaborationSyncIdentity identity,
  ) async {
    await _refreshStatus(generation, identity);
    var cursor = _lastAppliedSeq;
    var appliedAny = false;
    for (var pageNumber = 0; pageNumber < 1000; pageNumber += 1) {
      final page = await transport.getEvents(
        sessionId: identity.sessionId,
        afterSeq: cursor,
      );
      _ensureCurrent(generation, identity);
      if (page.afterSeq != cursor ||
          page.toSeq < page.afterSeq ||
          page.headSeq < page.toSeq ||
          page.minAvailableSeq < 0) {
        throw const CollaborationSyncException(
          code: 'INVALID_EVENTS_PAGE',
          message: 'The server returned inconsistent event cursor metadata',
        );
      }
      if (cursor < page.minAvailableSeq) {
        throw const CollaborationSyncException(
          code: 'CURSOR_EXPIRED',
          message: 'The local event cursor is outside server retention',
        );
      }
      await replica.setHeadSeq(identity, page.headSeq);
      _ensureCurrent(generation, identity);
      _serverHeadSeq = page.headSeq;

      final pageStart = cursor;
      for (final event in page.events) {
        if (event.protocolVersion != 1 ||
            event.sessionId != identity.sessionId ||
            event.seq < 1 ||
            event.entityVersion < 1) {
          throw const CollaborationSyncException(
            code: 'EVENT_CONTEXT_MISMATCH',
            message: 'An event is incompatible with this collaboration replica',
          );
        }
        if (event.seq > page.toSeq || event.seq > page.headSeq) {
          throw const CollaborationSyncException(
            code: 'INVALID_EVENTS_PAGE',
            message: 'An event exceeds the page cursor boundary',
          );
        }
        if (event.seq > cursor + 1) {
          throw CollaborationSyncException(
            code: 'EVENT_CURSOR_GAP',
            message: 'Expected event ${cursor + 1}, received ${event.seq}',
            retryable: true,
          );
        }
        final result = await replica.applyEvent(identity, event);
        _ensureCurrent(generation, identity);
        if (result.outcome == CollaborationApplyOutcome.gap) {
          throw CollaborationSyncException(
            code: 'EVENT_CURSOR_GAP',
            message: 'Replica expected event ${result.expectedSeq}',
            retryable: true,
          );
        }
        if (result.cursor < cursor || result.cursor > event.seq) {
          throw const CollaborationSyncException(
            code: 'INVALID_APPLY_RESULT',
            message: 'The replica returned an invalid event cursor',
          );
        }
        cursor = result.cursor;
        _lastAppliedSeq = cursor;
        if (result.outcome == CollaborationApplyOutcome.applied) {
          appliedAny = true;
          _updateSessionState(event);
          await onEventApplied?.call(event);
          _ensureCurrent(generation, identity);
        }
      }
      if (page.toSeq > cursor) {
        throw CollaborationSyncException(
          code: 'EVENT_CURSOR_GAP',
          message:
              'Events page ended at ${page.toSeq}, local cursor is $cursor',
          retryable: true,
        );
      }
      if (!page.hasMore && cursor >= page.headSeq) return appliedAny;
      if (cursor == pageStart) {
        throw const CollaborationSyncException(
          code: 'EVENT_CURSOR_STALLED',
          message: 'Events pagination made no cursor progress',
          retryable: true,
        );
      }
    }
    throw const CollaborationSyncException(
      code: 'EVENT_PAGE_LIMIT_EXCEEDED',
      message: 'Event catch-up exceeded its safety page limit',
      retryable: true,
    );
  }

  Future<bool> _flushOutbox(
    int generation,
    CollaborationSyncIdentity identity,
  ) async {
    var sentAny = false;
    for (var batchNumber = 0; batchNumber < 1000; batchNumber += 1) {
      final pending = await replica.listPending(identity);
      _ensureCurrent(generation, identity);
      if (pending.protocolVersion != 1 ||
          pending.deviceId != identity.deviceId ||
          pending.operations.length > 100) {
        throw const CollaborationSyncException(
          code: 'INVALID_OUTBOX_BATCH',
          message: 'The local outbox returned an incompatible mutation batch',
        );
      }
      final sendable = _sessionClosed
          ? pending.operations
              .where(
                (operation) =>
                    operation.entityType == 'session' &&
                    operation.operation == 'reopen',
              )
              .toList(growable: false)
          : pending.operations;
      if (sendable.isEmpty) return sentAny;
      final mutationIds = sendable
          .map((operation) => operation.mutationId)
          .toList(growable: false);
      if (mutationIds.toSet().length != mutationIds.length) {
        throw const CollaborationSyncException(
          code: 'DUPLICATE_OUTBOX_MUTATION',
          message: 'The local outbox returned duplicate mutation IDs',
        );
      }
      await replica.markSending(identity, mutationIds);
      _ensureCurrent(generation, identity);

      late final MutationBatchResultDto response;
      try {
        response = await transport.submitMutations(
          sessionId: identity.sessionId,
          deviceId: identity.deviceId,
          operations: sendable,
        );
      } catch (error) {
        if (!_isCurrent(generation, identity)) return sentAny;
        final syncError = _normalizeError(error);
        if (syncError.retryable) {
          final nextAttemptAt = _clock().add(
            syncError.retryAfter ?? const Duration(seconds: 1),
          );
          for (final mutationId in mutationIds) {
            await replica.markRetry(
              identity,
              mutationId,
              code: syncError.code,
              message: syncError.message,
              nextAttemptAt: nextAttemptAt,
            );
            _ensureCurrent(generation, identity);
          }
        }
        rethrow;
      }
      _ensureCurrent(generation, identity);
      sentAny = true;
      await replica.setHeadSeq(identity, response.headSeq);
      _ensureCurrent(generation, identity);
      _serverHeadSeq = max(_serverHeadSeq, response.headSeq);

      final results = <String, MutationResultDto>{};
      try {
        for (final result in response.results) {
          if (!mutationIds.contains(result.mutationId) ||
              results.containsKey(result.mutationId)) {
            throw const CollaborationSyncException(
              code: 'INVALID_MUTATION_RESULTS',
              message: 'Mutation response contains unknown or duplicate IDs',
            );
          }
          results[result.mutationId] = result;
        }
        if (results.length != sendable.length) {
          throw const CollaborationSyncException(
            code: 'INCOMPLETE_MUTATION_RESULTS',
            message: 'Mutation response omitted one or more operation results',
          );
        }
        for (final mutation in sendable) {
          final result = results[mutation.mutationId]!;
          final valid = switch (result.status) {
            'accepted' => result.event != null &&
                result.event!.protocolVersion == 1 &&
                result.event!.mutationId == mutation.mutationId &&
                result.event!.sessionId == identity.sessionId,
            'conflict' => result.code == 'VERSION_CONFLICT' &&
                result.currentVersion != null &&
                result.currentEntity != null,
            'rejected' => result.code != null,
            _ => false,
          };
          if (!valid) {
            throw const CollaborationSyncException(
              code: 'INVALID_MUTATION_RESULT',
              message: 'Mutation response contains an invalid result payload',
            );
          }
        }
      } on CollaborationSyncException catch (error) {
        final nextAttemptAt = _clock().add(const Duration(seconds: 1));
        for (final mutationId in mutationIds) {
          await replica.markRetry(
            identity,
            mutationId,
            code: error.code,
            message: error.message,
            nextAttemptAt: nextAttemptAt,
          );
          _ensureCurrent(generation, identity);
        }
        rethrow;
      }

      for (final mutation in sendable) {
        final result = results[mutation.mutationId]!;
        switch (result.status) {
          case 'accepted':
            final event = result.event!;
            await replica.markAccepted(
              identity,
              mutation.mutationId,
              event.seq,
            );
            _ensureCurrent(generation, identity);
            try {
              final applied = await replica.applyEvent(identity, event);
              _ensureCurrent(generation, identity);
              if (applied.outcome == CollaborationApplyOutcome.applied) {
                _lastAppliedSeq = applied.cursor;
                _updateSessionState(event);
                await onEventApplied?.call(event);
                _ensureCurrent(generation, identity);
              }
              // A gap is expected when another actor committed immediately
              // before this mutation. The following REST catch-up supplies it.
            } catch (error) {
              _remoteCommitPendingLocalApply = true;
              throw CollaborationSyncException(
                code: 'ACCEPTED_EVENT_APPLY_FAILED',
                message: '服务端已接受修改，本地确认将在重连后恢复',
                retryable: true,
                remoteCommitted: true,
                cause: error,
              );
            }
          case 'conflict':
            await replica.recordConflict(identity, mutation, result);
            _ensureCurrent(generation, identity);
          case 'rejected':
            await replica.markRejected(
              identity,
              mutation.mutationId,
              code: result.code ?? 'MUTATION_REJECTED',
              message: result.message ?? 'Mutation was rejected',
              details: result.details,
            );
            _ensureCurrent(generation, identity);
            _persistentWarningCode = result.code ?? 'MUTATION_REJECTED';
            _persistentWarningMessage =
                result.message ?? '一项本地修改被服务器拒绝，请检查后重新编辑';
          default:
            throw const CollaborationSyncException(
              code: 'INVALID_MUTATION_STATUS',
              message: 'Mutation response contains an unknown status',
            );
        }
      }
    }
    throw const CollaborationSyncException(
      code: 'OUTBOX_BATCH_LIMIT_EXCEEDED',
      message: 'Outbox flush exceeded its safety batch limit',
      retryable: true,
    );
  }

  Future<void> _listenToSocket(
    int generation,
    CollaborationSyncIdentity identity,
    CollaborationSocket socket,
  ) async {
    final signals = StreamController<_SocketSignal>();
    _activeSignals = signals;
    final readyTimeout = Timer(const Duration(seconds: 15), () {
      if (!signals.isClosed) {
        signals.add(
          const _SocketSignal.error(
            CollaborationSyncException(
              code: 'WS_READY_TIMEOUT',
              message: 'WebSocket did not complete catch-up in time',
              retryable: true,
            ),
          ),
        );
      }
    });
    late final StreamSubscription<Object?> subscription;
    subscription = socket.messages.listen(
      (message) {
        if (!signals.isClosed) signals.add(_SocketSignal.message(message));
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!signals.isClosed) signals.add(_SocketSignal.error(error));
      },
      onDone: () {
        if (!signals.isClosed) signals.add(const _SocketSignal.closed());
      },
      cancelOnError: false,
    );
    if (_wakePending) {
      _wakePending = false;
      signals.add(const _SocketSignal.wake());
    }
    try {
      await for (final signal in signals.stream) {
        _ensureCurrent(generation, identity);
        if (signal.kind == _SocketSignalKind.wake) {
          await _synchronizeOnce(generation, identity);
          continue;
        }
        if (signal.kind == _SocketSignalKind.error) {
          if (signal.value is CollaborationSyncException) {
            throw signal.value! as CollaborationSyncException;
          }
          throw CollaborationSyncException(
            code: 'WS_ERROR',
            message: 'The collaboration connection failed',
            retryable: true,
            cause: signal.value,
          );
        }
        if (signal.kind == _SocketSignalKind.closed) return;
        final message = _decodeSocketMessage(signal.value);
        final type = _jsonString(message, 'type');
        switch (type) {
          case 'hello':
            final sessionId = _jsonString(message, 'sessionId');
            if (sessionId != identity.sessionId) {
              throw const CollaborationSyncException(
                code: 'WS_CONTEXT_MISMATCH',
                message: 'WebSocket hello belongs to another session',
              );
            }
            _serverHeadSeq = max(
              _serverHeadSeq,
              _jsonInt(message, 'headSeq'),
            );
          case 'event':
            final event = CollaborationEventDto.fromJson(message['event']);
            if (event.sessionId != identity.sessionId) {
              throw const CollaborationSyncException(
                code: 'WS_CONTEXT_MISMATCH',
                message: 'WebSocket event belongs to another session',
              );
            }
            // The payload is a wake-up hint only. The authenticated REST page
            // is the source that closes gaps and drives the durable cursor.
            await _synchronizeOnce(generation, identity);
          case 'ready':
            readyTimeout.cancel();
            final readyCursor = _jsonInt(message, 'cursor');
            if (readyCursor > _lastAppliedSeq) {
              await _synchronizeOnce(generation, identity);
            }
            _ensureCurrent(generation, identity);
            _transportPhase = CollaborationTransportPhase.online;
            _clearError();
            _emit();
          case 'resyncRequired':
            throw const CollaborationSyncException(
              code: 'RESYNC_REQUIRED',
              message: 'The server requires a canonical snapshot refresh',
            );
          case 'accessRevoked':
            throw const CollaborationSyncException(
              code: 'MEMBERSHIP_REVOKED',
              message: 'Collaboration access was revoked',
            );
          case 'membershipChanged':
            _writeSuspended = true;
            _emit();
            await _refreshMembership(generation, identity);
            _ensureCurrent(generation, identity);
            await _synchronizeOnce(generation, identity);
          default:
            throw const CollaborationSyncException(
              code: 'UNKNOWN_WS_MESSAGE',
              message: 'The server sent an unknown WebSocket message',
            );
        }
      }
    } finally {
      readyTimeout.cancel();
      await subscription.cancel();
      if (identical(_activeSignals, signals)) _activeSignals = null;
      if (!signals.isClosed) await signals.close();
    }
  }

  Future<void> _refreshStatus(
    int generation,
    CollaborationSyncIdentity identity,
  ) async {
    final status = await replica.getStatus(identity);
    _ensureCurrent(generation, identity);
    if (status.lastAppliedSeq < 0 ||
        status.lastSeenHeadSeq < status.lastAppliedSeq ||
        status.pendingCount < 0 ||
        status.conflictCount < 0 ||
        status.rejectedCount < 0) {
      throw const CollaborationSyncException(
        code: 'INVALID_REPLICA_STATUS',
        message: 'The local replica returned invalid synchronization status',
      );
    }
    _localStatusGeneration += 1;
    _lastAppliedSeq = status.lastAppliedSeq;
    _serverHeadSeq = status.lastSeenHeadSeq;
    _pendingCount = status.pendingCount;
    _conflictCount = status.conflictCount;
    _updateRejectedCount(status.rejectedCount);
    _lastSuccessfulSyncAt =
        status.lastSuccessfulSyncAt ?? _lastSuccessfulSyncAt;
    final canonicalStatus = status.canonicalSessionStatus;
    if (canonicalStatus != null) {
      if (!const {'active', 'closed', 'deleted'}.contains(canonicalStatus)) {
        throw const CollaborationSyncException(
          code: 'INVALID_REPLICA_STATUS',
          message: 'The replica returned an invalid canonical Session status',
        );
      }
      _sessionClosed = canonicalStatus != 'active';
      _writeSuspended = canonicalStatus == 'active' && _localSessionClosed;
    }
    _emit();
  }

  Future<void> _refreshLocalCounts(
    int generation,
    int statusGeneration,
    CollaborationSyncIdentity identity,
  ) async {
    try {
      final status = await replica.getStatus(identity);
      if (!_isCurrent(generation, identity) ||
          statusGeneration != _localStatusGeneration) {
        return;
      }
      _pendingCount = status.pendingCount;
      _conflictCount = status.conflictCount;
      _updateRejectedCount(status.rejectedCount);
      _emit();
    } catch (_) {
      // The serialized sync loop owns recovery and errors. This read is only a
      // latency optimization for the pending/conflict badges.
    }
  }

  Future<MembershipDto> _refreshMembership(
    int generation,
    CollaborationSyncIdentity identity,
  ) async {
    final membership = await transport.getMembership(identity.sessionId);
    _ensureCurrent(generation, identity);
    if (membership.removedAt != null ||
        membership.userId != identity.accountId ||
        membership.sessionId != identity.sessionId) {
      throw const CollaborationSyncException(
        code: 'MEMBERSHIP_REVOKED',
        message: 'Collaboration membership is no longer active',
      );
    }
    if (membership.role == SessionRole.viewer) {
      _writeSuspended = true;
      _emit();
    }
    await replica.updateMembership(identity, membership);
    _ensureCurrent(generation, identity);
    _role = membership.role;
    _writeSuspended = _localSessionClosed && !_sessionClosed;
    _emit();
    return membership;
  }

  void _updateSessionState(CollaborationEventDto event) {
    switch (event.type) {
      case 'session.closed':
      case 'session.deleted':
        _sessionClosed = true;
        _writeSuspended = false;
      case 'session.reopened':
        _sessionClosed = false;
        _localSessionClosed = false;
        _writeSuspended = false;
    }
  }

  Future<void> _closeActiveTransport() async {
    final signals = _activeSignals;
    final socket = _activeSocket;
    _activeSignals = null;
    _activeSocket = null;
    if (signals != null && !signals.isClosed) {
      await signals.close();
    }
    if (socket != null) {
      try {
        await socket.close();
      } catch (_) {
        // Closing is best-effort during context switches and reconnects.
      }
    }
  }

  Duration _backoff(int attempt) {
    final cappedAttempt = min(attempt, 6);
    final ceilingMs = min(60000, 1000 * (1 << cappedAttempt));
    return Duration(milliseconds: _random.nextInt(ceilingMs + 1));
  }

  CollaborationSyncException _normalizeError(Object error) {
    if (error is CollaborationSyncException) return error;
    if (error is ServerApiException) {
      return CollaborationSyncException(
        code: error.code,
        message: error.message,
        retryable: error.retryable,
        retryAfter: _retryAfter(error.details),
        cause: error,
      );
    }
    if (error is FormatException) {
      return CollaborationSyncException(
        code: 'INVALID_SYNC_RESPONSE',
        message: error.message,
        cause: error,
      );
    }
    return CollaborationSyncException(
      code: 'SYNC_TRANSPORT_FAILED',
      message: error.toString(),
      retryable: true,
      cause: error,
    );
  }

  Duration? _retryAfter(Object? details) {
    if (details is! Map) return null;
    final value = details['retryAfterSeconds'];
    if (value is int && value >= 0) return Duration(seconds: value);
    return null;
  }

  bool _isRevocation(CollaborationSyncException error) => const {
        'MEMBERSHIP_REVOKED',
        'SESSION_DELETED',
        'NOT_FOUND',
      }.contains(error.code);

  bool _isAuthRequired(CollaborationSyncException error) => const {
        'AUTH_REQUIRED',
        'AUTH_CONTEXT_CHANGED',
        'INVALID_REFRESH_TOKEN',
      }.contains(error.code);

  bool _isCurrent(int generation, CollaborationSyncIdentity identity) =>
      !_disposed && generation == _generation && _identity == identity;

  void _ensureCurrent(int generation, CollaborationSyncIdentity identity) {
    if (!_isCurrent(generation, identity)) {
      throw const _SyncContextChanged();
    }
  }

  void _emitIfCurrent(
    int generation,
    CollaborationSyncIdentity identity,
  ) {
    if (_isCurrent(generation, identity)) _emit();
  }

  void _setError(CollaborationSyncException error) {
    _lastErrorCode = error.code;
    _lastErrorMessage = error.message;
    _remoteCommitPendingLocalApply = error.remoteCommitted;
  }

  void _clearError() {
    _lastErrorCode = _persistentWarningCode;
    _lastErrorMessage = _persistentWarningMessage;
    _nextRetryAt = null;
    _remoteCommitPendingLocalApply = false;
  }

  void _updateRejectedCount(int count) {
    if (count < 0) return;
    _rejectedCount = count;
    if (count != 0 || _persistentWarningCode == null) return;
    final warningCode = _persistentWarningCode;
    final warningMessage = _persistentWarningMessage;
    _persistentWarningCode = null;
    _persistentWarningMessage = null;
    if (_lastErrorCode == warningCode && _lastErrorMessage == warningMessage) {
      _lastErrorCode = null;
      _lastErrorMessage = null;
    }
  }

  void _emit() {
    if (!_disposed) onStateChanged?.call(state);
  }
}

enum _SocketSignalKind { message, wake, error, closed }

final class _SocketSignal {
  const _SocketSignal._(this.kind, this.value);

  const _SocketSignal.message(Object? value)
      : this._(_SocketSignalKind.message, value);
  const _SocketSignal.wake() : this._(_SocketSignalKind.wake, null);
  const _SocketSignal.error(Object error)
      : this._(_SocketSignalKind.error, error);
  const _SocketSignal.closed() : this._(_SocketSignalKind.closed, null);

  final _SocketSignalKind kind;
  final Object? value;
}

final class _SyncContextChanged implements Exception {
  const _SyncContextChanged();
}

JsonObject _decodeSocketMessage(Object? value) {
  Object? decoded = value;
  if (value is String) decoded = jsonDecode(value);
  if (value is List<int>) decoded = jsonDecode(utf8.decode(value));
  return _jsonObject(decoded, 'webSocketMessage');
}

JsonObject _jsonObject(Object? value, String field) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    try {
      return Map<String, Object?>.from(value);
    } on TypeError {
      // Fall through to a stable protocol error.
    }
  }
  throw FormatException('$field must be a JSON object');
}

String _jsonString(JsonObject object, String field) {
  final value = object[field];
  if (value is String) return value;
  throw FormatException('$field must be a string');
}

int _jsonInt(JsonObject object, String field) {
  final value = object[field];
  if (value is int) return value;
  throw FormatException('$field must be an integer');
}

DateTime? _optionalDateTime(JsonObject object, String field) {
  final value = object[field];
  if (value == null) return null;
  if (value is! String) throw FormatException('$field must be a string');
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw FormatException('$field must be RFC 3339');
  return parsed;
}

String? _optionalString(JsonObject object, String field) {
  final value = object[field];
  if (value == null) return null;
  if (value is String) return value;
  throw FormatException('$field must be a string');
}
