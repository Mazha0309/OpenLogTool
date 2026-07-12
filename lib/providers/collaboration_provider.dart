import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:openlogtool/models/collaboration_conflict.dart';
import 'package:openlogtool/models/collaboration_dto.dart';
import 'package:openlogtool/providers/log_provider.dart';
import 'package:openlogtool/providers/server_provider.dart';
import 'package:openlogtool/providers/session_provider.dart';
import 'package:openlogtool/services/collaboration_publish.dart';
import 'package:openlogtool/services/collaboration_conflicts.dart';
import 'package:openlogtool/services/collaboration_replica.dart';
import 'package:openlogtool/services/collaboration_sync.dart';
import 'package:openlogtool/services/server_api.dart';
import 'package:openlogtool/src/bridge/rust_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum CollaborationState {
  localOnly,
  publishing,
  joining,
  snapshotting,
  catchingUp,
  ready,
  resyncing,
  revoked,
  failed,
}

final class LocalCollaborationBinding {
  const LocalCollaborationBinding({
    required this.serverInstanceId,
    required this.serverOrigin,
    required this.accountId,
    required this.sessionId,
    required this.membershipId,
    required this.membershipVersion,
    required this.role,
    required this.replicaState,
    required this.lastAppliedSeq,
    required this.lastSeenHeadSeq,
    required this.revokedAt,
  });

  factory LocalCollaborationBinding.fromJson(Object? value) {
    final map = Map<String, Object?>.from(value! as Map);
    return LocalCollaborationBinding(
      serverInstanceId: map['serverInstanceId']! as String,
      serverOrigin: map['serverOrigin']! as String,
      accountId: map['accountId']! as String,
      sessionId: map['sessionId']! as String,
      membershipId: map['membershipId']! as String,
      membershipVersion: map['membershipVersion']! as int,
      role: SessionRole.fromJson(map['role'], 'role'),
      replicaState: map['replicaState']! as String,
      lastAppliedSeq: map['lastAppliedSeq']! as int,
      lastSeenHeadSeq: map['lastSeenHeadSeq']! as int,
      revokedAt: map['revokedAt'] == null
          ? null
          : DateTime.parse(map['revokedAt']! as String),
    );
  }

  final String serverInstanceId;
  final String serverOrigin;
  final String accountId;
  final String sessionId;
  final String membershipId;
  final int membershipVersion;
  final SessionRole role;
  final String replicaState;
  final int lastAppliedSeq;
  final int lastSeenHeadSeq;
  final DateTime? revokedAt;
}

final class _OperationContext {
  _OperationContext({
    required this.server,
    required this.api,
    required this.sessions,
    required this.logs,
    required this.serverContextRevision,
    required this.serverUrl,
    required this.accountId,
    required this.sessionId,
    required this.epoch,
  });

  final ServerProvider server;
  final ServerApi api;
  final SessionProvider sessions;
  final LogProvider logs;
  final int serverContextRevision;
  final String serverUrl;
  final String accountId;
  String? sessionId;
  int epoch;
}

final class _OperationContextChanged implements Exception {
  const _OperationContextChanged();

  @override
  String toString() => 'COLLABORATION_CONTEXT_CHANGED: 服务器、账号或会话已切换';
}

CollaborationConflictPort _resolveConflictPort(
  CollaborationReplicaPort? replica,
) {
  if (replica is CollaborationConflictPort) {
    return replica as CollaborationConflictPort;
  }
  return const RustCollaborationReplicaPort();
}

@visibleForTesting
bool collaborationEventMayAffectOpenConflicts({
  required CollaborationEventDto event,
  required List<CollaborationConflict> openConflicts,
  required int reportedConflictCount,
}) {
  if (reportedConflictCount <= 0 && openConflicts.isEmpty) return false;
  // While the first list request is pending, conservatively invalidate on any
  // event so a response read just before that event cannot become permanent.
  if (openConflicts.isEmpty) return true;
  // Session status/version changes can alter the allowed resolutions of every
  // Log conflict, even when the conflicted entity itself did not change.
  if (event.entityType == 'session') return true;
  return openConflicts.any(
    (conflict) =>
        conflict.entityType.name == event.entityType &&
        conflict.entityId == event.entityId,
  );
}

class CollaborationProvider with ChangeNotifier {
  CollaborationProvider({
    CollaborationReplicaPort? replica,
    CollaborationConflictPort? conflicts,
    CollaborationSocketConnector? sockets,
  })  : _replica = replica ?? const RustCollaborationReplicaPort(),
        _conflictPort = conflicts ?? _resolveConflictPort(replica),
        _sockets = sockets ?? const WebSocketChannelConnector();

  static const _pendingJoinPrefix = 'collaboration_pending_join_';
  static const _legacyPendingJoinIdKey = 'collaboration_pending_join_id';
  static const _legacyPendingJoinFingerprintKey =
      'collaboration_pending_join_fingerprint';
  static const _pendingMutationPrefix = 'collaboration_pending_mutation_';

  static const _publishFeatures = {
    'sessionPublishing',
    'sessionBootstrap',
    'sessionSnapshots',
    'sessionMembership',
  };
  static const _joinFeatures = {
    'collaborationInvites',
    'sessionSnapshots',
    'sessionMembership',
  };
  static const _refreshFeatures = {
    'sessionSnapshots',
    'sessionSnapshotTombstones',
    'sessionMembership',
  };
  static const _memberManagementFeatures = {
    'sessionMembership',
  };
  static const _inviteManagementFeatures = {
    'collaborationInvites',
  };
  static const _syncFeatures = {
    'sessionEvents',
    'sessionMutations',
    'collaborationWebSocket',
    'sessionSnapshotTombstones',
  };

  final CollaborationReplicaPort _replica;
  final CollaborationConflictPort _conflictPort;
  final CollaborationSocketConnector _sockets;

  ServerProvider? _server;
  SessionProvider? _sessions;
  LogProvider? _logs;
  String? _dependencyKey;
  bool _refreshScheduled = false;
  bool _disposed = false;
  bool _operationInProgress = false;
  int _stateEpoch = 0;
  int _refreshGeneration = 0;
  String? _publishingSessionId;
  CollaborationSyncCoordinator? _syncCoordinator;
  CollaborationSyncState? _syncState;
  int _syncGeneration = 0;
  int _conflictRequestGeneration = 0;
  int _conflictInvalidationGeneration = 0;
  bool _conflictsNeedRefresh = false;
  bool _conflictReloadScheduled = false;

  CollaborationState _state = CollaborationState.localOnly;
  LocalCollaborationBinding? _binding;
  MembershipDto? _membership;
  List<MembershipDto> _members = const [];
  List<CollaborationInviteDto> _invites = const [];
  CollaborationInviteDto? _lastCreatedInvite;
  String? _deviceId;
  String? _errorCode;
  String? _errorMessage;
  String? _failedOperation;
  String _progressLabel = '';
  double? _progress;
  List<CollaborationConflict> _openConflicts = const [];
  bool _conflictsLoaded = false;
  bool _conflictsLoading = false;
  String? _resolvingConflictId;

  CollaborationState get state => _state;
  LocalCollaborationBinding? get binding => _binding;
  MembershipDto? get membership => _membership;
  List<MembershipDto> get members => _members;
  List<CollaborationInviteDto> get invites => _invites;
  CollaborationInviteDto? get lastCreatedInvite => _lastCreatedInvite;
  String? get deviceId => _deviceId;
  String? get errorCode => _errorCode;
  String? get errorMessage => _errorMessage;
  String? get failedOperation => _failedOperation;
  String get progressLabel => _progressLabel;
  double? get progress => _progress;
  List<CollaborationConflict> get openConflicts => _openConflicts;
  bool get conflictsLoading => _conflictsLoading;
  String? get resolvingConflictId => _resolvingConflictId;
  bool get isBusy => _operationInProgress;
  CollaborationSyncState? get syncState => _syncState;
  CollaborationTransportPhase get transportPhase =>
      _syncState?.transportPhase ?? CollaborationTransportPhase.stopped;
  int get lastAppliedSeq =>
      _syncState?.lastAppliedSeq ?? _binding?.lastAppliedSeq ?? 0;
  int get serverHeadSeq =>
      _syncState?.serverHeadSeq ?? _binding?.lastSeenHeadSeq ?? 0;
  int get pendingCount => _syncState?.pendingCount ?? 0;
  int get conflictCount =>
      _conflictsLoaded ? _openConflicts.length : _syncState?.conflictCount ?? 0;
  int get rejectedCount => _syncState?.rejectedCount ?? 0;
  DateTime? get lastSuccessfulSyncAt => _syncState?.lastSuccessfulSyncAt;
  DateTime? get nextRetryAt => _syncState?.nextRetryAt;
  String? get syncErrorCode => _syncState?.lastErrorCode;
  String? get syncErrorMessage => _syncState?.lastErrorMessage;
  bool get remoteCommitPendingLocalApply =>
      _syncState?.remoteCommitPendingLocalApply ?? false;
  bool get canonicalSessionClosed => _syncState?.sessionClosed ?? false;
  SessionRole? get effectiveRole => _syncState?.role ?? _membership?.role;
  bool get canEditCurrentSession =>
      _state == CollaborationState.ready && (_syncState?.canEdit ?? false);
  bool get canResolveConflicts => _currentConflictIdentity() != null;
  bool get hasOpenSessionConflict {
    final sessionId = _binding?.sessionId;
    return sessionId != null &&
        _openConflicts.any(
          (conflict) =>
              conflict.entityType == CollaborationConflictEntityType.session &&
              conflict.entityId == sessionId,
        );
  }

  Set<String> get conflictedLogIds => Set.unmodifiable(
        _openConflicts
            .where(
              (conflict) =>
                  conflict.entityType == CollaborationConflictEntityType.log,
            )
            .map((conflict) => conflict.entityId),
      );

  bool canResolveConflictWith(
    CollaborationConflict conflict,
    CollaborationConflictResolution resolution,
  ) =>
      canResolveConflicts &&
      conflict.sessionId == _binding?.sessionId &&
      conflict.allowedResolutions.contains(resolution);

  bool get isOwner {
    final server = _server;
    final sessions = _sessions;
    final binding = _binding;
    final membership = _membership;
    return server != null &&
        sessions != null &&
        binding != null &&
        membership != null &&
        _state == CollaborationState.ready &&
        binding.replicaState == 'ready' &&
        sessions.currentSessionId == binding.sessionId &&
        server.isLoggedIn &&
        server.accountId == binding.accountId &&
        server.serverInfo?.serverInstanceId == binding.serverInstanceId &&
        membership.membershipId == binding.membershipId &&
        membership.sessionId == binding.sessionId &&
        membership.userId == binding.accountId &&
        membership.removedAt == null &&
        effectiveRole == SessionRole.owner;
  }

  bool get supportsInvites =>
      isOwner &&
      (_server?.serverInfo?.features.contains('collaborationInvites') ?? false);

  bool get readOnly => isCurrentSessionReadOnly;

  bool get isCurrentSessionReadOnly {
    final sessionId = _sessions?.currentSessionId;
    if (sessionId == null) return false;
    if (_publishingSessionId == sessionId) return true;
    if (_binding?.sessionId == sessionId) return !canEditCurrentSession;
    return _logs?.currentSessionReadOnly ?? false;
  }

  void updateDependencies(
    ServerProvider server,
    SessionProvider sessions,
    LogProvider logs,
  ) {
    _server = server;
    _sessions = sessions;
    _logs = logs;
    final key = '${server.contextRevision}|${server.serverUrl}|'
        '${server.accountId ?? ''}|'
        '${sessions.currentSessionId ?? ''}';
    if (_dependencyKey == key) return;
    _dependencyKey = key;
    _stateEpoch += 1;
    _stopSynchronization();
    _clearScopedState();
    _safeNotify();
    _scheduleRefresh();
  }

  Future<void> refreshCurrentSession() async {
    if (_operationInProgress) return;
    _stopSynchronization();
    final refreshGeneration = ++_refreshGeneration;
    final epoch = _stateEpoch;
    final server = _server;
    final sessions = _sessions;
    final logs = _logs;
    if (server == null || sessions == null || logs == null) return;
    final serverContextRevision = server.contextRevision;
    final serverUrl = server.serverUrl;
    final accountId = server.accountId;
    final sessionId = sessions.currentSessionId;

    bool isCurrent() =>
        !_disposed &&
        !_operationInProgress &&
        refreshGeneration == _refreshGeneration &&
        epoch == _stateEpoch &&
        identical(server, _server) &&
        identical(sessions, _sessions) &&
        identical(logs, _logs) &&
        server.contextRevision == serverContextRevision &&
        server.serverUrl == serverUrl &&
        server.accountId == accountId &&
        sessions.currentSessionId == sessionId;

    final resolvedDeviceId = _deviceId ?? await RustApi.getOrCreateDeviceId();
    _deviceId = resolvedDeviceId;
    if (!isCurrent()) return;
    await server.setDeviceId(resolvedDeviceId);
    if (!isCurrent()) return;
    if (sessionId == null) {
      _clearScopedState();
      _state = CollaborationState.localOnly;
      _safeNotify();
      return;
    }

    final bindingJson = await RustApi.getSessionCollaborationBinding(
      sessionId: sessionId,
    );
    if (!isCurrent()) return;
    if (bindingJson == null) {
      if (_publishingSessionId == sessionId) {
        _publishingSessionId = null;
      }
      logs.setCollaborationReadOnly(sessionId, false);
      _clearScopedState();
      _state = CollaborationState.localOnly;
      _safeNotify();
      return;
    }

    var currentBinding = LocalCollaborationBinding.fromJson(
      jsonDecode(bindingJson),
    );
    _binding = currentBinding;
    _membership = null;
    _members = const [];
    _invites = const [];
    logs.setCollaborationReadOnly(sessionId, true);
    _state = _stateFromReplica(currentBinding.replicaState);
    if (currentBinding.replicaState == 'publishing') {
      _publishingSessionId = sessionId;
      _safeNotify();
      return;
    }
    if (currentBinding.replicaState == 'ready') {
      _state = CollaborationState.snapshotting;
    }
    _safeNotify();

    await logs.reloadForSession(sessionId, propagateErrors: true);
    if (!isCurrent()) return;

    if (!server.isLoggedIn || accountId != currentBinding.accountId) {
      _state = _stateFromReplica(currentBinding.replicaState);
      _safeNotify();
      return;
    }
    final api = server.api;
    try {
      final info = server.serverInfo ?? await api.getServerInfo();
      if (!isCurrent()) return;
      _requireFeatures(info, _refreshFeatures);
      if (info.serverInstanceId != currentBinding.serverInstanceId) {
        _state = _stateFromReplica(currentBinding.replicaState);
        _setError(
          'SERVER_IDENTITY_MISMATCH',
          '当前地址指向另一台服务器；本地副本保持只读',
        );
        _safeNotify();
        return;
      }
      final remoteMembership = await api.getMembership(sessionId);
      if (!isCurrent()) return;
      if (remoteMembership.version > currentBinding.membershipVersion ||
          remoteMembership.role != currentBinding.role) {
        final snapshot = await api.getSessionSnapshot(
          sessionId,
          includeDeleted: includeDeletedLogsForSnapshotInstall(
            CollaborationSnapshotInstallTarget.existingReplica,
          ),
        );
        if (!isCurrent()) return;
        final refreshedBinding = await RustApi.installCollaborationSnapshot(
          requestJson: jsonEncode({
            'mode': 'join',
            'serverInstanceId': currentBinding.serverInstanceId,
            'serverOrigin': serverUrl,
            'accountId': currentBinding.accountId,
            'membership': remoteMembership.toJson(),
            'snapshot': snapshot.toJson(),
          }),
        );
        if (!isCurrent()) return;
        currentBinding = LocalCollaborationBinding.fromJson(
          jsonDecode(refreshedBinding),
        );
        await logs.reloadForSession(sessionId, propagateErrors: true);
        if (!isCurrent()) return;
      }

      var members = const <MembershipDto>[];
      var invites = const <CollaborationInviteDto>[];
      if (remoteMembership.role == SessionRole.owner) {
        _requireFeatures(info, _memberManagementFeatures);
        final supportsInvites = info.features.contains('collaborationInvites');
        final results = await Future.wait<Object>([
          api.listMembers(sessionId),
          if (supportsInvites) api.listInvites(sessionId),
        ]);
        if (!isCurrent()) return;
        members = results[0] as List<MembershipDto>;
        if (supportsInvites) {
          invites = results[1] as List<CollaborationInviteDto>;
        }
      }

      _binding = currentBinding;
      _membership = remoteMembership;
      _members = members;
      _invites = invites;
      _publishingSessionId = null;
      _state = CollaborationState.ready;
      _clearError();
      if (_syncFeatures.difference(info.features.toSet()).isEmpty) {
        _startSynchronization(
          currentBinding,
          remoteMembership,
          sessionClosed: sessions.currentSession?.status != 'active',
        );
      } else {
        logs.setCollaborationReadOnly(sessionId, true);
        _setError(
          'SYNC_FEATURE_UNAVAILABLE',
          '服务器未完整启用 Stage 2 实时同步；本地副本保持只读',
        );
      }
    } on ServerApiException catch (error) {
      if (!isCurrent()) return;
      if ({'MEMBERSHIP_REVOKED', 'SESSION_DELETED', 'NOT_FOUND'}
          .contains(error.code)) {
        await RustApi.markCollaborationRevoked(
          serverInstanceId: currentBinding.serverInstanceId,
          accountId: currentBinding.accountId,
          sessionId: sessionId,
        );
        if (!isCurrent()) return;
        _membership = null;
        _members = const [];
        _invites = const [];
        _lastCreatedInvite = null;
        _state = CollaborationState.revoked;
        _setError(error.code, error.message);
      } else {
        if (error.code == 'FORBIDDEN') {
          _membership = null;
          _members = const [];
          _invites = const [];
          _lastCreatedInvite = null;
        }
        _setError(error.code, error.message);
      }
    }
    _safeNotify();
  }

  Future<void> publishCurrentSession() async {
    final sessions = _requireSessions();
    final logs = _requireLogs();
    final sessionId = sessions.currentSessionId;
    final session = sessions.currentSession;
    if (sessionId == null || session == null) {
      throw StateError('没有可发布的本地会话');
    }
    await _runOperation((context) async {
      _assertOperationCurrent(context);
      if (context.sessionId != sessionId) {
        throw const _OperationContextChanged();
      }
      final info = await _ensureServerCapabilities(
        context,
        _publishFeatures,
      );
      _assertOperationCurrent(context);
      _state = CollaborationState.publishing;
      _failedOperation = null;
      _publishingSessionId = sessionId;
      logs.setCollaborationReadOnly(sessionId, true);
      _setProgress('锁定并准备本地快照', 0.02);

      var leaseStarted = false;
      var leaseCreated = false;
      var remoteTouched = false;
      var snapshotInstalled = false;
      try {
        final publishJson = await RustApi.beginPublishSnapshot(
          serverInstanceId: info.serverInstanceId,
          serverOrigin: context.serverUrl,
          accountId: context.accountId,
          sessionId: sessionId,
        );
        leaseStarted = true;
        _assertOperationCurrent(context);
        final publish = Map<String, Object?>.from(
          jsonDecode(publishJson) as Map,
        );
        leaseCreated = publish['leaseCreated']! as bool;
        final publishSession = Map<String, Object?>.from(
          publish['session']! as Map,
        );
        final rawLogs = List<Object?>.from(publish['logs']! as List);
        final bootstrapLogs = rawLogs.map(_bootstrapLogFromJson).toList();
        final prepared = prepareCollaborationPublish(
          sessionId: sessionId,
          title: publishSession['title']! as String,
          logs: bootstrapLogs,
        );

        _setProgress('创建远端协作会话', 0.08);
        remoteTouched = true;
        final remoteSession = await context.api.putSession(
          sessionId: sessionId,
          title: prepared.title,
          idempotencyKey: _uuidV4(),
        );
        _assertOperationCurrent(context);
        if (remoteSession.status == 'initializing') {
          var uploaded = 0;
          for (final batch in prepared.batches) {
            await context.api.bootstrapLogs(
              sessionId: sessionId,
              items: batch,
              idempotencyKey: _uuidV4(),
            );
            _assertOperationCurrent(context);
            uploaded += batch.length;
            final fraction =
                bootstrapLogs.isEmpty ? 1.0 : uploaded / bootstrapLogs.length;
            _setProgress(
              '上传记录 $uploaded/${bootstrapLogs.length}',
              0.1 + fraction * 0.65,
            );
          }
          _setProgress('激活远端会话', 0.8);
          await context.api.activateSession(
            sessionId: sessionId,
            expectedLogCount: bootstrapLogs.length,
            idempotencyKey: _uuidV4(),
          );
          _assertOperationCurrent(context);
        } else if (remoteSession.status != 'active') {
          throw StateError('REMOTE_SESSION_STATE_INVALID');
        }

        _setProgress('安装服务端规范快照', 0.9);
        final remoteMembership = await context.api.getMembership(sessionId);
        _assertOperationCurrent(context);
        final snapshot = await context.api.getSessionSnapshot(
          sessionId,
          includeDeleted: includeDeletedLogsForSnapshotInstall(
            CollaborationSnapshotInstallTarget.publish,
          ),
        );
        _assertOperationCurrent(context);
        validatePublishedCollaborationSnapshot(
          sessionId: sessionId,
          title: prepared.title,
          localLogs: bootstrapLogs,
          snapshot: snapshot,
        );
        final bindingJson = await RustApi.installCollaborationSnapshot(
          requestJson: jsonEncode({
            'mode': 'publish',
            'serverInstanceId': info.serverInstanceId,
            'serverOrigin': context.serverUrl,
            'accountId': context.accountId,
            'membership': remoteMembership.toJson(),
            'snapshot': snapshot.toJson(),
          }),
        );
        snapshotInstalled = true;
        final installedBinding = LocalCollaborationBinding.fromJson(
          jsonDecode(bindingJson),
        );
        if (!_isOperationCurrent(context)) {
          _scheduleRefresh();
          return;
        }
        _binding = installedBinding;
        _membership = remoteMembership;
        _publishingSessionId = null;
        _state = CollaborationState.ready;
        _failedOperation = null;
        _clearError();

        String? refreshWarning;
        try {
          await sessions.switchToSession(sessionId);
          if (sessions.currentSessionId != sessionId) {
            throw StateError('SESSION_SWITCH_NOT_CONFIRMED');
          }
          await logs.reloadForSession(sessionId, propagateErrors: true);
          if (_isOperationCurrent(context)) {
            await _refreshManagementForOperation(
              context,
              installedBinding,
            );
          }
        } catch (error) {
          refreshWarning = error.toString();
        }
        if (!_isOperationCurrent(context)) return;
        _setProgress('发布完成', 1);
        if (refreshWarning != null) {
          _setError(
            'PUBLISH_COMPLETED_REFRESH_FAILED',
            '发布已经完成，但本地界面刷新失败：$refreshWarning',
          );
        }
      } catch (error) {
        if (snapshotInstalled) {
          if (_isOperationCurrent(context)) {
            _state = CollaborationState.ready;
            _failedOperation = null;
            _setError(
              'PUBLISH_COMPLETED_REFRESH_FAILED',
              '发布已经完成，但本地界面刷新失败：$error',
            );
          }
          return;
        }

        var safelyAborted = false;
        if (leaseStarted && leaseCreated && !remoteTouched) {
          try {
            await RustApi.abortPublish(
              serverInstanceId: info.serverInstanceId,
              accountId: context.accountId,
              sessionId: sessionId,
            );
            safelyAborted = true;
          } catch (_) {
            // Conservatively retain the lease if local rollback cannot be
            // proven. The Session must remain read-only in that case.
          }
        }
        if (_isOperationCurrent(context)) {
          if (safelyAborted || !leaseStarted) {
            if (_binding == null) {
              logs.setCollaborationReadOnly(sessionId, false);
            }
            _publishingSessionId = null;
          }
          _state = safelyAborted
              ? CollaborationState.localOnly
              : CollaborationState.failed;
          _failedOperation = safelyAborted ? null : 'publish';
        }
        rethrow;
      }
    });
  }

  Future<void> joinWithCode(String code) async {
    final sessions = _requireSessions();
    final logs = _requireLogs();
    final normalizedCode = code
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[\s-]'), '')
        .replaceAll('O', '0')
        .replaceAll(RegExp(r'[IL]'), '1');
    if (!RegExp(r'^[0-9A-HJKMNP-TV-Z]{10}$').hasMatch(normalizedCode)) {
      throw ArgumentError('邀请码应为 10 位字符');
    }
    await _runOperation((context) async {
      try {
        final info = await _ensureServerCapabilities(
          context,
          _joinFeatures,
        );
        _assertOperationCurrent(context);
        final resolvedDeviceId =
            _deviceId ?? await RustApi.getOrCreateDeviceId();
        _deviceId = resolvedDeviceId;
        _assertOperationCurrent(context);
        final pendingJoin = await _pendingJoinRequestId(
          serverInstanceId: info.serverInstanceId,
          accountId: context.accountId,
          credentialKind: 'code',
          credentialValue: normalizedCode,
        );
        _assertOperationCurrent(context);
        _state = CollaborationState.joining;
        _setProgress('兑换邀请码', 0.2);
        final redeemed = await context.api.redeemInvite(
          RedeemInviteRequestDto(
            code: normalizedCode,
            joinRequestId: pendingJoin.id,
            deviceId: resolvedDeviceId,
          ),
        );
        _assertOperationCurrent(context);
        _state = CollaborationState.snapshotting;
        _setProgress('下载协作快照', 0.55);
        final existingBinding = await RustApi.getCollaborationBinding(
          serverInstanceId: info.serverInstanceId,
          accountId: context.accountId,
          sessionId: redeemed.session.sessionId,
        );
        _assertOperationCurrent(context);
        final isReinstall = existingBinding != null;
        if (isReinstall &&
            !info.features.contains('sessionSnapshotTombstones')) {
          throw StateError(
            'SYNC_FEATURE_UNAVAILABLE: '
            '服务器不支持含删除记录的安全副本重装',
          );
        }
        final snapshot = await context.api.getSessionSnapshot(
          redeemed.session.sessionId,
          includeDeleted: includeDeletedLogsForSnapshotInstall(
            isReinstall
                ? CollaborationSnapshotInstallTarget.existingReplica
                : CollaborationSnapshotInstallTarget.firstJoin,
          ),
        );
        _assertOperationCurrent(context);
        if (snapshot.session.sessionId != redeemed.session.sessionId ||
            redeemed.membership.sessionId != redeemed.session.sessionId ||
            redeemed.membership.userId != context.accountId) {
          throw StateError('JOIN_REMOTE_CONTENT_MISMATCH');
        }
        _setProgress('原子安装本地副本', 0.8);
        final bindingJson = await RustApi.installCollaborationSnapshot(
          requestJson: jsonEncode({
            'mode': 'join',
            'serverInstanceId': info.serverInstanceId,
            'serverOrigin': context.serverUrl,
            'accountId': context.accountId,
            'membership': redeemed.membership.toJson(),
            'snapshot': snapshot.toJson(),
          }),
        );
        final installedBinding = LocalCollaborationBinding.fromJson(
          jsonDecode(bindingJson),
        );
        if (!_isServerIdentityCurrent(context)) {
          _scheduleRefresh();
          throw StateError(
            'JOIN_COMMITTED_CONTEXT_CHANGED: '
            '协作副本已安全安装，但服务器或账号已切换；请切回原账号后重试以完成界面切换',
          );
        }
        final joinedSessionId = redeemed.session.sessionId;
        logs.setCollaborationReadOnly(joinedSessionId, true);
        await sessions.switchToSession(joinedSessionId);
        if (sessions.currentSessionId != joinedSessionId) {
          throw StateError('SESSION_SWITCH_NOT_CONFIRMED');
        }
        _adoptOperationSession(context, joinedSessionId);
        await logs.reloadForSession(
          joinedSessionId,
          propagateErrors: true,
        );
        _assertOperationCurrent(context);
        await _clearPendingJoin(pendingJoin.storageKey);
        _assertOperationCurrent(context);
        _binding = installedBinding;
        _membership = redeemed.membership;
        _members = const [];
        _invites = const [];
        _lastCreatedInvite = null;
        _state = CollaborationState.ready;
        _failedOperation = null;
        _setProgress('加入完成', 1);
        _clearError();
      } catch (error) {
        if (_isOperationCurrent(context)) {
          _state = CollaborationState.failed;
          _failedOperation = 'join';
          _safeNotify();
        }
        rethrow;
      }
    });
  }

  Future<void> refreshManagement() async {
    await _runOperation((context) async {
      final binding = _requireBoundSession(context, requireOwner: true);
      await _ensureServerCapabilities(context, _memberManagementFeatures);
      _assertOperationCurrent(context);
      await _refreshManagementForOperation(context, binding);
    });
  }

  Future<CollaborationInviteDto> createInvite({
    required InviteRole role,
    int expiresInHours = 24,
    int maxUses = 1,
  }) async {
    late CollaborationInviteDto created;
    await _runOperation((context) async {
      final binding = _requireBoundSession(context, requireOwner: true);
      await _ensureServerCapabilities(context, _inviteManagementFeatures);
      _assertOperationCurrent(context);
      final pending = await _pendingMutationId(
        context,
        binding,
        'createInvite',
        {
          'role': role.toJson(),
          'expiresInHours': expiresInHours,
          'maxUses': maxUses,
        },
      );
      _assertOperationCurrent(context);
      created = await context.api.createInvite(
        sessionId: binding.sessionId,
        request: CreateInviteRequestDto(
          role: role,
          expiresInHours: expiresInHours,
          maxUses: maxUses,
        ),
        idempotencyKey: pending.id,
      );
      await _confirmPendingMutation(pending.storageKey);
      if (!_isOperationCurrent(context)) return;
      _lastCreatedInvite = created;
      await _refreshManagementBestEffort(context, binding);
    });
    return created;
  }

  Future<void> revokeInvite(String inviteId) async {
    await _runOperation((context) async {
      final binding = _requireBoundSession(context, requireOwner: true);
      await _ensureServerCapabilities(context, _inviteManagementFeatures);
      _assertOperationCurrent(context);
      final pending = await _pendingMutationId(
        context,
        binding,
        'revokeInvite',
        {'inviteId': inviteId},
      );
      _assertOperationCurrent(context);
      final revoked = await context.api.revokeInvite(
        sessionId: binding.sessionId,
        inviteId: inviteId,
        idempotencyKey: pending.id,
      );
      await _confirmPendingMutation(pending.storageKey);
      if (!_isOperationCurrent(context)) return;
      _invites = [
        for (final invite in _invites)
          if (invite.inviteId == revoked.inviteId) revoked else invite,
      ];
      await _refreshManagementBestEffort(context, binding);
    });
  }

  Future<void> removeMember(String userId) async {
    await _runOperation((context) async {
      final binding = _requireBoundSession(context, requireOwner: true);
      await _ensureServerCapabilities(context, _memberManagementFeatures);
      _assertOperationCurrent(context);
      final pending = await _pendingMutationId(
        context,
        binding,
        'removeMember',
        {'userId': userId},
      );
      _assertOperationCurrent(context);
      await context.api.removeMember(
        sessionId: binding.sessionId,
        userId: userId,
        idempotencyKey: pending.id,
      );
      await _confirmPendingMutation(pending.storageKey);
      if (!_isOperationCurrent(context)) return;
      _members = _members.where((member) => member.userId != userId).toList();
      await _refreshManagementBestEffort(context, binding);
    });
  }

  Future<void> updateMemberRole(String userId, InviteRole role) async {
    await _runOperation((context) async {
      final binding = _requireBoundSession(context, requireOwner: true);
      await _ensureServerCapabilities(context, _memberManagementFeatures);
      _assertOperationCurrent(context);
      final pending = await _pendingMutationId(
        context,
        binding,
        'updateMemberRole',
        {'userId': userId, 'role': role.toJson()},
      );
      _assertOperationCurrent(context);
      final updated = await context.api.updateMemberRole(
        sessionId: binding.sessionId,
        userId: userId,
        role: role,
        idempotencyKey: pending.id,
      );
      await _confirmPendingMutation(pending.storageKey);
      if (!_isOperationCurrent(context)) return;
      _members = [
        for (final member in _members)
          if (member.userId == updated.userId) updated else member,
      ];
      await _refreshManagementBestEffort(context, binding);
    });
  }

  Future<void> transferOwnership(String userId) async {
    await _runOperation((context) async {
      final binding = _requireBoundSession(context, requireOwner: true);
      await _ensureServerCapabilities(context, {
        ..._memberManagementFeatures,
        'sessionSnapshots',
        'sessionSnapshotTombstones',
      });
      _assertOperationCurrent(context);
      final pending = await _pendingMutationId(
        context,
        binding,
        'transferOwnership',
        {'newOwnerUserId': userId},
      );
      _assertOperationCurrent(context);
      final transfer = await context.api.transferOwnership(
        sessionId: binding.sessionId,
        newOwnerUserId: userId,
        idempotencyKey: pending.id,
      );
      await _confirmPendingMutation(pending.storageKey);
      if (!_isOperationCurrent(context)) return;
      _membership = transfer.previousOwner;
      _members = const [];
      _invites = const [];
      _lastCreatedInvite = null;
      try {
        final snapshot = await context.api.getSessionSnapshot(
          binding.sessionId,
          includeDeleted: includeDeletedLogsForSnapshotInstall(
            CollaborationSnapshotInstallTarget.existingReplica,
          ),
        );
        _assertOperationCurrent(context);
        final bindingJson = await RustApi.installCollaborationSnapshot(
          requestJson: jsonEncode({
            'mode': 'join',
            'serverInstanceId': binding.serverInstanceId,
            'serverOrigin': context.serverUrl,
            'accountId': context.accountId,
            'membership': transfer.previousOwner.toJson(),
            'snapshot': snapshot.toJson(),
          }),
        );
        if (!_isOperationCurrent(context)) return;
        _binding = LocalCollaborationBinding.fromJson(
          jsonDecode(bindingJson),
        );
      } catch (error) {
        if (_isOperationCurrent(context)) {
          _setError(
            'OWNERSHIP_TRANSFERRED_REFRESH_FAILED',
            '所有权已经转移，但本地权限快照刷新失败：$error',
          );
        }
      }
    });
  }

  Future<void> renameCurrentSession(String title) async {
    final normalized = title.trim();
    if (normalized.isEmpty || normalized.length > 200) {
      throw ArgumentError('会话标题长度应为 1–200 个字符');
    }
    await _runOperation((context) async {
      final binding = _requireSynchronizedOwner(context);
      await RustApi.updateCollaborationSessionTitle(
        sessionId: binding.sessionId,
        title: normalized,
      );
      _assertOperationCurrent(context);
      await context.sessions.reloadCurrentSession();
      _assertOperationCurrent(context);
      _syncCoordinator?.wake();
    }, refreshAfter: false);
  }

  Future<void> closeCurrentSession() async {
    await _runOperation((context) async {
      final binding = _requireSynchronizedOwner(context);
      await RustApi.closeSession(sessionId: binding.sessionId);
      _assertOperationCurrent(context);
      // Lock writes before any async UI reload or network round trip. Rust has
      // committed the local status + outbox atomically at this point.
      _syncCoordinator?.markSessionLocallyClosed();
      context.logs.setCollaborationReadOnly(binding.sessionId, true);
      await context.sessions.reloadCurrentSession();
      _assertOperationCurrent(context);
    }, refreshAfter: false);
  }

  Future<void> reopenCurrentSession() async {
    await _runOperation((context) async {
      final binding = _requireSynchronizedOwner(context);
      await RustApi.reopenCollaborationSession(sessionId: binding.sessionId);
      _assertOperationCurrent(context);
      await context.sessions.reloadCurrentSession();
      _assertOperationCurrent(context);
      // Keep the local close guard until session.reopened is applied. This
      // avoids reporting writable state if the server resolves the operation
      // as a conflict or rejection.
      context.logs.setCollaborationReadOnly(binding.sessionId, true);
      _syncCoordinator?.markSessionLocallyReopened();
    }, refreshAfter: false);
  }

  Future<void> refreshOpenConflicts() async {
    if (_operationInProgress) {
      throw StateError('已有协作操作正在进行');
    }
    final identity = _currentConflictIdentity();
    if (identity == null) {
      throw StateError('COLLABORATION_CONFLICT_CONTEXT_MISMATCH');
    }
    await _loadOpenConflicts(identity, rethrowError: true);
  }

  Future<void> useRemoteForConflict(String conflictId) => _resolveConflict(
        conflictId,
        CollaborationConflictResolution.useRemote,
      );

  Future<void> keepLocalForConflict(String conflictId) => _resolveConflict(
        conflictId,
        CollaborationConflictResolution.keepLocal,
      );

  Future<void> copyLocalAsNewForConflict(String conflictId) => _resolveConflict(
        conflictId,
        CollaborationConflictResolution.copyLocalAsNew,
      );

  Future<void> _resolveConflict(
    String conflictId,
    CollaborationConflictResolution resolution,
  ) async {
    if (conflictId.trim().isEmpty) {
      throw ArgumentError.value(conflictId, 'conflictId', 'must not be empty');
    }
    await _runOperation((context) async {
      final binding = _requireBoundSession(context, requireOwner: false);
      final identity = _currentConflictIdentity();
      if (identity == null ||
          identity.serverInstanceId != binding.serverInstanceId ||
          identity.accountId != binding.accountId ||
          identity.sessionId != binding.sessionId) {
        throw StateError('COLLABORATION_CONFLICT_CONTEXT_MISMATCH');
      }
      CollaborationConflict? conflict;
      for (final candidate in _openConflicts) {
        if (candidate.conflictId == conflictId) {
          conflict = candidate;
          break;
        }
      }
      if (conflict == null || conflict.sessionId != identity.sessionId) {
        throw StateError('COLLABORATION_CONFLICT_NOT_FOUND');
      }
      if (!conflict.allowedResolutions.contains(resolution)) {
        throw StateError('CONFLICT_RESOLUTION_NOT_ALLOWED');
      }
      if (_resolvingConflictId != null) {
        throw StateError('COLLABORATION_CONFLICT_OPERATION_IN_PROGRESS');
      }

      _resolvingConflictId = conflictId;
      _conflictRequestGeneration += 1;
      _safeNotify();
      try {
        final result = await _conflictPort.resolveConflict(
          identity,
          conflictId,
          resolution,
          expectedRemoteVersion: conflict.remoteVersion,
        );
        _assertOperationCurrent(context);
        if (_currentConflictIdentity() != identity ||
            result.resolution != resolution) {
          throw const _OperationContextChanged();
        }

        // The local resolution transaction is durable at this point. Wake the
        // coordinator before UI reloads so a keep-local replacement mutation
        // is not delayed by rendering work.
        _syncCoordinator?.wake();
        await context.sessions.reloadCurrentSession();
        _assertOperationCurrent(context);
        await context.logs.reloadForSession(
          binding.sessionId,
          propagateErrors: true,
        );
        _assertOperationCurrent(context);
        await _loadOpenConflicts(identity, rethrowError: true);
        _assertOperationCurrent(context);
      } catch (error) {
        // A remote-version precondition or a permission change means the
        // choice the user confirmed is stale. Keep the operation error
        // visible, but best-effort refresh the list before returning it.
        if (_isOperationCurrent(context) &&
            _currentConflictIdentity() == identity) {
          await _loadOpenConflicts(identity, rethrowError: false);
        }
        if (_localErrorCode(error) == 'CONFLICT_REMOTE_ADVANCED') {
          throw StateError(
            'CONFLICT_REMOTE_ADVANCED: 远端内容已更新，'
            '请检查刷新后的冲突内容并重新确认',
          );
        }
        rethrow;
      } finally {
        if (_isOperationCurrent(context) &&
            _resolvingConflictId == conflictId) {
          _resolvingConflictId = null;
          _safeNotify();
        }
      }
    }, refreshAfter: false);
  }

  Future<void> _loadOpenConflicts(
    CollaborationSyncIdentity identity, {
    required bool rethrowError,
  }) async {
    final requestGeneration = ++_conflictRequestGeneration;
    final invalidationGeneration = _conflictInvalidationGeneration;
    _conflictsLoading = true;
    _safeNotify();
    try {
      final conflicts = await _conflictPort.listOpenConflicts(identity);
      if (!_isConflictRequestCurrent(requestGeneration, identity)) return;
      final ids = <String>{};
      if (conflicts.any(
        (conflict) =>
            conflict.sessionId != identity.sessionId ||
            !ids.add(conflict.conflictId),
      )) {
        throw const FormatException(
          'Conflict list contains another session or duplicate IDs',
        );
      }
      _openConflicts = List.unmodifiable(conflicts);
      _conflictsLoaded = true;
      if (_conflictInvalidationGeneration == invalidationGeneration) {
        _conflictsNeedRefresh = false;
      }
      if (_errorCode == 'CONFLICT_LIST_FAILED') _clearError();
    } catch (error) {
      if (_isConflictRequestCurrent(requestGeneration, identity)) {
        _setError('CONFLICT_LIST_FAILED', error.toString());
      }
      if (rethrowError) rethrow;
    } finally {
      if (requestGeneration == _conflictRequestGeneration) {
        _conflictsLoading = false;
        _safeNotify();
        if (_conflictsNeedRefresh &&
            _conflictInvalidationGeneration != invalidationGeneration) {
          _scheduleOpenConflictReload(identity);
        }
      }
    }
  }

  void _invalidateOpenConflicts(CollaborationSyncIdentity identity) {
    if ((_syncState?.conflictCount ?? 0) <= 0 && _openConflicts.isEmpty) {
      return;
    }
    _conflictInvalidationGeneration += 1;
    _conflictsNeedRefresh = true;
    _scheduleOpenConflictReload(identity);
  }

  void _scheduleOpenConflictReload(CollaborationSyncIdentity identity) {
    if (_conflictReloadScheduled ||
        _conflictsLoading ||
        _currentConflictIdentity() != identity) {
      return;
    }
    _conflictReloadScheduled = true;
    scheduleMicrotask(() {
      _conflictReloadScheduled = false;
      if (_conflictsLoading ||
          _currentConflictIdentity() != identity ||
          ((_syncState?.conflictCount ?? 0) <= 0 && _openConflicts.isEmpty)) {
        return;
      }
      unawaited(_loadOpenConflicts(identity, rethrowError: false));
    });
  }

  Future<void> _runOperation(
    Future<void> Function(_OperationContext context) operation, {
    bool refreshAfter = true,
  }) async {
    if (_operationInProgress) throw StateError('已有协作操作正在进行');
    final server = _requireServer();
    final sessions = _requireSessions();
    final logs = _requireLogs();
    final accountId = _requireAccountId(server);
    _stateEpoch += 1;
    final context = _OperationContext(
      server: server,
      api: server.api,
      sessions: sessions,
      logs: logs,
      serverContextRevision: server.contextRevision,
      serverUrl: server.serverUrl,
      accountId: accountId,
      sessionId: sessions.currentSessionId,
      epoch: _stateEpoch,
    );
    _operationInProgress = true;
    _clearError();
    _safeNotify();
    try {
      await operation(context);
    } on ServerApiException catch (error) {
      if (_isOperationCurrent(context)) {
        _setError(error.code, error.message);
      }
      rethrow;
    } catch (error) {
      if (_isOperationCurrent(context)) {
        _setError(_localErrorCode(error), error.toString());
      }
      rethrow;
    } finally {
      _operationInProgress = false;
      _safeNotify();
      if (refreshAfter) _scheduleRefresh();
    }
  }

  Future<ServerInfoDto> _ensureServerCapabilities(
    _OperationContext context,
    Set<String> required,
  ) async {
    _assertOperationCurrent(context);
    final info =
        context.server.serverInfo ?? await context.server.checkServer();
    _assertOperationCurrent(context);
    _requireFeatures(info, required);
    final binding = _binding;
    if (binding != null &&
        binding.sessionId == context.sessionId &&
        info.serverInstanceId != binding.serverInstanceId) {
      throw StateError('SERVER_IDENTITY_MISMATCH');
    }
    return info;
  }

  void _requireFeatures(ServerInfoDto info, Set<String> required) {
    if (info.protocolMin > 1 || info.protocolMax < 1) {
      throw StateError('服务器不支持协作协议 v1');
    }
    final missing = required.difference(info.features.toSet());
    if (missing.isNotEmpty) {
      throw StateError('服务器缺少协作能力: ${missing.join(', ')}');
    }
  }

  Future<void> _refreshManagementForOperation(
    _OperationContext context,
    LocalCollaborationBinding binding,
  ) async {
    final info = await _ensureServerCapabilities(
      context,
      _memberManagementFeatures,
    );
    _assertOperationCurrent(context);
    final supportsInvites = info.features.contains('collaborationInvites');
    final results = await Future.wait<Object>([
      context.api.listMembers(binding.sessionId),
      if (supportsInvites) context.api.listInvites(binding.sessionId),
    ]);
    _assertOperationCurrent(context);
    _members = results[0] as List<MembershipDto>;
    _invites =
        supportsInvites ? results[1] as List<CollaborationInviteDto> : const [];
    _safeNotify();
  }

  Future<void> _refreshManagementBestEffort(
    _OperationContext context,
    LocalCollaborationBinding binding,
  ) async {
    try {
      await _refreshManagementForOperation(context, binding);
    } catch (error) {
      if (_isOperationCurrent(context)) {
        _setError(
          'MANAGEMENT_REFRESH_FAILED',
          '服务器变更已经确认，但成员列表刷新失败：$error',
        );
      }
    }
  }

  BootstrapLogDto _bootstrapLogFromJson(Object? value) {
    final map = Map<String, Object?>.from(value! as Map);
    String? optional(String key) {
      final raw = map[key] as String?;
      return raw == null || raw.trim().isEmpty ? null : raw;
    }

    return BootstrapLogDto(
      syncId: (map['syncId']! as String).trim(),
      time: DateTime.parse(map['time']! as String),
      controller: (map['controller']! as String).trim().toUpperCase(),
      callsign: (map['callsign']! as String).trim().toUpperCase(),
      rstSent: optional('rstSent'),
      rstRcvd: optional('rstRcvd'),
      qth: optional('qth'),
      device: optional('device'),
      power: optional('power'),
      antenna: optional('antenna'),
      height: optional('height'),
      remarks: optional('remarks'),
    );
  }

  Future<({String id, String storageKey})> _pendingJoinRequestId({
    required String serverInstanceId,
    required String accountId,
    required String credentialKind,
    required String credentialValue,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final fingerprint = sha256
        .convert(
          utf8.encode(
            jsonEncode({
              'serverInstanceId': serverInstanceId,
              'accountId': accountId,
              'credentialKind': credentialKind,
              'credentialValue': credentialValue,
            }),
          ),
        )
        .toString();
    final storageKey = '$_pendingJoinPrefix$fingerprint';
    final storedId = prefs.getString(storageKey);
    if (storedId != null &&
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          caseSensitive: false,
        ).hasMatch(storedId)) {
      return (id: storedId, storageKey: storageKey);
    }
    final legacyFingerprint = prefs.getString(
      _legacyPendingJoinFingerprintKey,
    );
    final legacyId = prefs.getString(_legacyPendingJoinIdKey);
    final validLegacyId = legacyId != null &&
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          caseSensitive: false,
        ).hasMatch(legacyId);
    final id = legacyFingerprint == fingerprint && validLegacyId
        ? legacyId
        : _uuidV4();
    if (!await prefs.setString(storageKey, id)) {
      throw StateError('PENDING_JOIN_PERSIST_FAILED');
    }
    // Clean the pre-scoped Stage 1 draft keys without making the new request
    // depend on that best-effort migration.
    await prefs.remove(_legacyPendingJoinFingerprintKey);
    await prefs.remove(_legacyPendingJoinIdKey);
    return (id: id, storageKey: storageKey);
  }

  Future<void> _clearPendingJoin(String storageKey) async {
    final prefs = await SharedPreferences.getInstance();
    final removed = await prefs.remove(storageKey);
    if (!removed && prefs.containsKey(storageKey)) {
      throw StateError('PENDING_JOIN_CLEAR_FAILED');
    }
  }

  Future<({String id, String storageKey})> _pendingMutationId(
    _OperationContext context,
    LocalCollaborationBinding binding,
    String kind,
    Object payload,
  ) async {
    final fingerprint = sha256
        .convert(
          utf8.encode(
            jsonEncode({
              'serverInstanceId': binding.serverInstanceId,
              'accountId': context.accountId,
              'sessionId': binding.sessionId,
              'kind': kind,
              'payload': payload,
            }),
          ),
        )
        .toString();
    final storageKey = '$_pendingMutationPrefix$fingerprint';
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(storageKey);
    if (stored != null &&
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          caseSensitive: false,
        ).hasMatch(stored)) {
      return (id: stored, storageKey: storageKey);
    }
    final id = _uuidV4();
    if (!await prefs.setString(storageKey, id)) {
      throw StateError('PENDING_MUTATION_PERSIST_FAILED');
    }
    return (id: id, storageKey: storageKey);
  }

  Future<void> _confirmPendingMutation(String storageKey) async {
    final prefs = await SharedPreferences.getInstance();
    final removed = await prefs.remove(storageKey);
    if (!removed && prefs.containsKey(storageKey)) {
      throw StateError('PENDING_MUTATION_CLEAR_FAILED');
    }
  }

  LocalCollaborationBinding _requireBoundSession(
    _OperationContext context, {
    required bool requireOwner,
  }) {
    _assertOperationCurrent(context);
    final binding = _binding;
    final membership = _membership;
    if (binding == null || membership == null) {
      throw StateError('当前会话尚未绑定服务器');
    }
    if (_state != CollaborationState.ready ||
        binding.replicaState != 'ready' ||
        binding.sessionId != context.sessionId ||
        binding.sessionId != _sessions?.currentSessionId ||
        binding.accountId != context.accountId ||
        membership.membershipId != binding.membershipId ||
        membership.sessionId != binding.sessionId ||
        membership.userId != context.accountId ||
        membership.removedAt != null ||
        (requireOwner && effectiveRole != SessionRole.owner)) {
      throw StateError('COLLABORATION_CONTEXT_MISMATCH');
    }
    final serverInstanceId = context.server.serverInfo?.serverInstanceId;
    if (serverInstanceId != null &&
        serverInstanceId != binding.serverInstanceId) {
      throw StateError('SERVER_IDENTITY_MISMATCH');
    }
    return binding;
  }

  LocalCollaborationBinding _requireSynchronizedOwner(
    _OperationContext context,
  ) {
    final binding = _requireBoundSession(context, requireOwner: true);
    final sync = _syncState;
    if (sync == null ||
        sync.replicaPhase != CollaborationReplicaPhase.ready ||
        sync.identity?.serverInstanceId != binding.serverInstanceId ||
        sync.identity?.accountId != binding.accountId ||
        sync.identity?.sessionId != binding.sessionId ||
        sync.role != SessionRole.owner) {
      throw StateError('COLLABORATION_SYNC_NOT_READY');
    }
    return binding;
  }

  bool _isServerIdentityCurrent(_OperationContext context) =>
      !_disposed &&
      identical(_server, context.server) &&
      context.server.contextRevision == context.serverContextRevision &&
      context.server.serverUrl == context.serverUrl &&
      context.server.accountId == context.accountId;

  bool _isOperationCurrent(_OperationContext context) =>
      _isServerIdentityCurrent(context) &&
      _operationInProgress &&
      context.epoch == _stateEpoch &&
      identical(_sessions, context.sessions) &&
      identical(_logs, context.logs) &&
      _sessions?.currentSessionId == context.sessionId;

  void _assertOperationCurrent(_OperationContext context) {
    if (!_isOperationCurrent(context)) {
      throw const _OperationContextChanged();
    }
  }

  void _adoptOperationSession(
    _OperationContext context,
    String sessionId,
  ) {
    if (!_isServerIdentityCurrent(context) ||
        _sessions?.currentSessionId != sessionId) {
      throw const _OperationContextChanged();
    }
    _stateEpoch += 1;
    context.epoch = _stateEpoch;
    context.sessionId = sessionId;
    _dependencyKey = '${context.server.contextRevision}|'
        '${context.serverUrl}|${context.accountId}|$sessionId';
    _clearScopedState();
  }

  void _startSynchronization(
    LocalCollaborationBinding binding,
    MembershipDto membership, {
    required bool sessionClosed,
  }) {
    final server = _server;
    final sessions = _sessions;
    final logs = _logs;
    final deviceId = _deviceId;
    if (server == null ||
        sessions == null ||
        logs == null ||
        deviceId == null ||
        sessions.currentSessionId != binding.sessionId ||
        server.accountId != binding.accountId ||
        server.serverInfo?.serverInstanceId != binding.serverInstanceId) {
      logs?.setCollaborationReadOnly(binding.sessionId, true);
      return;
    }

    _stopSynchronization();
    final generation = ++_syncGeneration;
    final identity = CollaborationSyncIdentity(
      serverInstanceId: binding.serverInstanceId,
      serverOrigin: binding.serverOrigin,
      accountId: binding.accountId,
      sessionId: binding.sessionId,
      deviceId: deviceId,
    );
    late final CollaborationSyncCoordinator coordinator;
    coordinator = CollaborationSyncCoordinator(
      transport: ServerApiCollaborationSyncTransport(server.api),
      replica: _replica,
      sockets: _sockets,
      onStateChanged: (state) {
        if (!_isSyncCurrent(generation, identity, coordinator)) return;
        final previousRole = _syncState?.role ?? _membership?.role;
        final previousConflictCount = _syncState?.conflictCount;
        _syncState = state;
        switch (state.replicaPhase) {
          case CollaborationReplicaPhase.catchingUp:
            _state = CollaborationState.catchingUp;
          case CollaborationReplicaPhase.ready:
            _state = CollaborationState.ready;
          case CollaborationReplicaPhase.resyncing:
            _state = CollaborationState.resyncing;
          case CollaborationReplicaPhase.revoked:
            _state = CollaborationState.revoked;
            _membership = null;
            _members = const [];
            _invites = const [];
            _lastCreatedInvite = null;
          case CollaborationReplicaPhase.failed:
            _state = CollaborationState.failed;
          case CollaborationReplicaPhase.localOnly:
            _state = CollaborationState.localOnly;
        }
        logs.setCollaborationReadOnly(binding.sessionId, !state.canEdit);
        _safeNotify();
        if (state.conflictCount == 0) {
          if (_openConflicts.isNotEmpty ||
              !_conflictsLoaded ||
              _conflictsLoading ||
              _conflictsNeedRefresh ||
              _conflictReloadScheduled) {
            _conflictRequestGeneration += 1;
            _conflictInvalidationGeneration += 1;
            _openConflicts = const [];
            _conflictsLoaded = true;
            _conflictsLoading = false;
            _conflictsNeedRefresh = false;
            _conflictReloadScheduled = false;
            _safeNotify();
          }
        } else if (state.replicaPhase == CollaborationReplicaPhase.ready &&
            !_conflictsLoading &&
            (!_conflictsLoaded ||
                _openConflicts.length != state.conflictCount ||
                previousConflictCount != state.conflictCount ||
                _conflictsNeedRefresh)) {
          _scheduleOpenConflictReload(identity);
        }
        if (state.role != null && state.role != previousRole) {
          _invalidateOpenConflicts(identity);
          _scheduleRefresh();
        }
      },
      onEventApplied: (event) async {
        if (!_isSyncCurrent(generation, identity, coordinator)) return;
        if (collaborationEventMayAffectOpenConflicts(
          event: event,
          openConflicts: _openConflicts,
          reportedConflictCount: _syncState?.conflictCount ?? 0,
        )) {
          _invalidateOpenConflicts(identity);
        }
        await sessions.reloadCurrentSession();
        if (!_isSyncCurrent(generation, identity, coordinator)) return;
        await logs.reloadForSession(
          sessions.currentSessionId,
          propagateErrors: true,
        );
      },
      onSnapshotInstalled: (snapshot) async {
        if (!_isSyncCurrent(generation, identity, coordinator)) return;
        _invalidateOpenConflicts(identity);
        await sessions.reloadCurrentSession();
        if (!_isSyncCurrent(generation, identity, coordinator)) return;
        await logs.reloadForSession(
          sessions.currentSessionId,
          propagateErrors: true,
        );
      },
    );
    _syncCoordinator = coordinator;
    logs.setOnDataChanged(() async {
      if (_isSyncCurrent(generation, identity, coordinator)) {
        coordinator.wake();
      }
    });
    coordinator.start(
      identity: identity,
      role: membership.role,
      sessionClosed: sessionClosed,
    );
  }

  bool _isSyncCurrent(
    int generation,
    CollaborationSyncIdentity identity,
    CollaborationSyncCoordinator coordinator,
  ) {
    final server = _server;
    return !_disposed &&
        generation == _syncGeneration &&
        identical(_syncCoordinator, coordinator) &&
        _binding?.serverInstanceId == identity.serverInstanceId &&
        _binding?.serverOrigin == identity.serverOrigin &&
        _binding?.accountId == identity.accountId &&
        _binding?.sessionId == identity.sessionId &&
        server?.accountId == identity.accountId &&
        server?.serverUrl == identity.serverOrigin &&
        server?.serverInfo?.serverInstanceId == identity.serverInstanceId &&
        _sessions?.currentSessionId == identity.sessionId;
  }

  CollaborationSyncIdentity? _currentConflictIdentity() {
    final identity = _syncState?.identity;
    final binding = _binding;
    final membership = _membership;
    final server = _server;
    if (_disposed ||
        identity == null ||
        binding == null ||
        membership == null ||
        _syncState?.replicaPhase != CollaborationReplicaPhase.ready ||
        binding.replicaState != 'ready' ||
        binding.serverInstanceId != identity.serverInstanceId ||
        binding.serverOrigin != identity.serverOrigin ||
        binding.accountId != identity.accountId ||
        binding.sessionId != identity.sessionId ||
        membership.membershipId != binding.membershipId ||
        membership.sessionId != identity.sessionId ||
        membership.userId != identity.accountId ||
        membership.removedAt != null ||
        server?.serverUrl != identity.serverOrigin ||
        server?.accountId != identity.accountId ||
        server?.serverInfo?.serverInstanceId != identity.serverInstanceId ||
        _sessions?.currentSessionId != identity.sessionId) {
      return null;
    }
    return identity;
  }

  bool _isConflictRequestCurrent(
    int requestGeneration,
    CollaborationSyncIdentity identity,
  ) =>
      requestGeneration == _conflictRequestGeneration &&
      _currentConflictIdentity() == identity;

  void _resetConflictState() {
    _conflictRequestGeneration += 1;
    _conflictInvalidationGeneration += 1;
    _openConflicts = const [];
    _conflictsLoaded = false;
    _conflictsLoading = false;
    _conflictsNeedRefresh = false;
    _conflictReloadScheduled = false;
    _resolvingConflictId = null;
  }

  void _stopSynchronization() {
    _syncGeneration += 1;
    _resetConflictState();
    final binding = _binding;
    if (binding != null) {
      _logs?.setCollaborationReadOnly(binding.sessionId, true);
    }
    _logs?.setOnDataChanged(null);
    final coordinator = _syncCoordinator;
    _syncCoordinator = null;
    _syncState = null;
    if (coordinator != null) unawaited(coordinator.dispose());
  }

  void _clearScopedState() {
    _stopSynchronization();
    _binding = null;
    _membership = null;
    _members = const [];
    _invites = const [];
    _lastCreatedInvite = null;
    _failedOperation = null;
    _progressLabel = '';
    _progress = null;
    _clearError();
    _state = _publishingSessionId != null &&
            _publishingSessionId == _sessions?.currentSessionId
        ? CollaborationState.publishing
        : CollaborationState.localOnly;
  }

  ServerProvider _requireServer() {
    final server = _server;
    if (server == null) throw StateError('服务器尚未初始化');
    return server;
  }

  SessionProvider _requireSessions() {
    final sessions = _sessions;
    if (sessions == null) throw StateError('会话尚未初始化');
    return sessions;
  }

  LogProvider _requireLogs() {
    final logs = _logs;
    if (logs == null) throw StateError('日志尚未初始化');
    return logs;
  }

  String _requireAccountId(ServerProvider server) {
    final accountId = server.accountId;
    if (accountId == null) throw StateError('请先登录服务器');
    return accountId;
  }

  void _scheduleRefresh() {
    if (_refreshScheduled) return;
    _refreshScheduled = true;
    scheduleMicrotask(() async {
      _refreshScheduled = false;
      final epoch = _stateEpoch;
      final refreshGeneration = _refreshGeneration + 1;
      try {
        await refreshCurrentSession();
      } catch (error) {
        if (epoch == _stateEpoch &&
            refreshGeneration == _refreshGeneration &&
            !_operationInProgress) {
          _setError(_localErrorCode(error), error.toString());
          _safeNotify();
        }
      }
    });
  }

  void _setProgress(String label, double value) {
    _progressLabel = label;
    _progress = value < 0 ? 0 : (value > 1 ? 1 : value);
    _safeNotify();
  }

  void _setError(String code, String message) {
    _errorCode = code;
    _errorMessage = message;
  }

  void _clearError() {
    _errorCode = null;
    _errorMessage = null;
  }

  String _localErrorCode(Object error) {
    final text = error.toString();
    final match = RegExp(r'([A-Z][A-Z0-9_]{3,})').firstMatch(text);
    return match?.group(1) ?? 'COLLABORATION_FAILED';
  }

  CollaborationState _stateFromReplica(String value) => switch (value) {
        'publishing' => CollaborationState.publishing,
        'joining' => CollaborationState.joining,
        'snapshotting' => CollaborationState.snapshotting,
        'catchingUp' => CollaborationState.catchingUp,
        'ready' => CollaborationState.ready,
        'resyncing' => CollaborationState.resyncing,
        'revoked' => CollaborationState.revoked,
        'failed' => CollaborationState.failed,
        _ => CollaborationState.failed,
      };

  String _uuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex =
        bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _stopSynchronization();
    _disposed = true;
    super.dispose();
  }
}
