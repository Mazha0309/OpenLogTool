import 'dart:convert';

import 'package:openlogtool/models/collaboration_conflict.dart';
import 'package:openlogtool/models/collaboration_dto.dart';
import 'package:openlogtool/services/collaboration_conflicts.dart';
import 'package:openlogtool/services/collaboration_sync.dart';
import 'package:openlogtool/src/bridge/api/collaboration.dart' as bridge;

/// Thin JSON boundary around the Rust replica engine.
///
/// Keeping protocol DTO conversion here prevents the coordinator from
/// depending on generated flutter_rust_bridge types or method signatures.
final class RustCollaborationReplicaPort
    implements CollaborationReplicaPort, CollaborationConflictPort {
  const RustCollaborationReplicaPort();

  static const CollaborationConflictPort _conflicts =
      JsonCollaborationConflictPort(
    listOpen: bridge.listOpenCollaborationConflicts,
    resolve: bridge.resolveCollaborationConflict,
  );

  @override
  Future<void> reinstallSnapshot(
    CollaborationSyncIdentity identity,
    MembershipDto membership,
    SessionSnapshotDto snapshot,
  ) async {
    await bridge.installCollaborationSnapshot(
      requestJson: jsonEncode({
        'mode': 'join',
        'serverInstanceId': identity.serverInstanceId,
        'serverOrigin': identity.serverOrigin,
        'accountId': identity.accountId,
        'membership': membership.toJson(),
        'snapshot': snapshot.toJson(),
      }),
    );
  }

  @override
  Future<void> updateMembership(
    CollaborationSyncIdentity identity,
    MembershipDto membership,
  ) async {
    await bridge.updateCollaborationMembership(
      serverInstanceId: identity.serverInstanceId,
      accountId: identity.accountId,
      sessionId: identity.sessionId,
      membershipId: membership.membershipId,
      membershipVersion: membership.version,
      role: membership.role.toJson(),
    );
  }

  @override
  Future<CollaborationReplicaStatus> getStatus(
    CollaborationSyncIdentity identity,
  ) async {
    final json = await bridge.getCollaborationSyncStatus(
      serverInstanceId: identity.serverInstanceId,
      accountId: identity.accountId,
      sessionId: identity.sessionId,
    );
    return CollaborationReplicaStatus.fromJson(jsonDecode(json));
  }

  @override
  Future<PendingCollaborationMutations> listPending(
    CollaborationSyncIdentity identity, {
    int limit = 100,
  }) async {
    final json = await bridge.listPendingCollaborationMutations(
      serverInstanceId: identity.serverInstanceId,
      accountId: identity.accountId,
      sessionId: identity.sessionId,
      limit: limit,
    );
    return PendingCollaborationMutations.fromJson(jsonDecode(json));
  }

  @override
  Future<void> markSending(
    CollaborationSyncIdentity identity,
    List<String> mutationIds,
  ) =>
      bridge.markCollaborationMutationsSending(
        serverInstanceId: identity.serverInstanceId,
        accountId: identity.accountId,
        sessionId: identity.sessionId,
        mutationIdsJson: jsonEncode(mutationIds),
      );

  @override
  Future<void> markAccepted(
    CollaborationSyncIdentity identity,
    String mutationId,
    int acceptedEventSeq,
  ) =>
      bridge.markCollaborationMutationAccepted(
        serverInstanceId: identity.serverInstanceId,
        accountId: identity.accountId,
        sessionId: identity.sessionId,
        mutationId: mutationId,
        acceptedEventSeq: acceptedEventSeq,
      );

  @override
  Future<void> markRetry(
    CollaborationSyncIdentity identity,
    String mutationId, {
    required String code,
    required String message,
    required DateTime nextAttemptAt,
  }) =>
      bridge.markCollaborationMutationRetry(
        requestJson: jsonEncode({
          'serverInstanceId': identity.serverInstanceId,
          'accountId': identity.accountId,
          'sessionId': identity.sessionId,
          'mutationId': mutationId,
          'errorCode': code,
          'errorMessage': message,
          'nextAttemptAt': nextAttemptAt.toUtc().toIso8601String(),
        }),
      );

  @override
  Future<void> markRejected(
    CollaborationSyncIdentity identity,
    String mutationId, {
    required String code,
    required String message,
    Object? details,
  }) =>
      bridge.markCollaborationMutationRejected(
        serverInstanceId: identity.serverInstanceId,
        accountId: identity.accountId,
        sessionId: identity.sessionId,
        mutationId: mutationId,
        errorCode: code,
        errorMessage: message,
        detailsJson: details == null ? null : jsonEncode(details),
      );

  @override
  Future<void> recordConflict(
    CollaborationSyncIdentity identity,
    CollaborationMutationDto mutation,
    MutationResultDto result,
  ) async {
    await bridge.recordCollaborationMutationConflict(
      requestJson: jsonEncode({
        'serverInstanceId': identity.serverInstanceId,
        'accountId': identity.accountId,
        'sessionId': identity.sessionId,
        'mutationId': mutation.mutationId,
        'currentVersion': result.currentVersion,
        'currentEntity': result.currentEntity,
      }),
    );
  }

  @override
  Future<CollaborationApplyResult> applyEvent(
    CollaborationSyncIdentity identity,
    CollaborationEventDto event,
  ) async {
    final json = await bridge.applyCollaborationEvent(
      requestJson: jsonEncode({
        'serverInstanceId': identity.serverInstanceId,
        'accountId': identity.accountId,
        'event': event.toJson(),
      }),
    );
    return CollaborationApplyResult.fromJson(jsonDecode(json));
  }

  @override
  Future<void> setHeadSeq(
    CollaborationSyncIdentity identity,
    int headSeq,
  ) =>
      bridge.setCollaborationHeadSeq(
        serverInstanceId: identity.serverInstanceId,
        accountId: identity.accountId,
        sessionId: identity.sessionId,
        headSeq: headSeq,
      );

  @override
  Future<void> markRevoked(CollaborationSyncIdentity identity) =>
      bridge.markCollaborationRevoked(
        serverInstanceId: identity.serverInstanceId,
        accountId: identity.accountId,
        sessionId: identity.sessionId,
      );

  @override
  Future<List<CollaborationConflict>> listOpenConflicts(
    CollaborationSyncIdentity identity,
  ) =>
      _conflicts.listOpenConflicts(identity);

  @override
  Future<CollaborationConflictResolutionResult> resolveConflict(
    CollaborationSyncIdentity identity,
    String conflictId,
    CollaborationConflictResolution resolution, {
    required int expectedRemoteVersion,
  }) =>
      _conflicts.resolveConflict(
        identity,
        conflictId,
        resolution,
        expectedRemoteVersion: expectedRemoteVersion,
      );
}
