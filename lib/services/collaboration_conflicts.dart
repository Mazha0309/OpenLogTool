import 'dart:convert';

import 'package:openlogtool/models/collaboration_conflict.dart';
import 'package:openlogtool/services/collaboration_sync.dart';

typedef ListOpenCollaborationConflictsCall = Future<String> Function({
  required String serverInstanceId,
  required String accountId,
  required String sessionId,
});
typedef ResolveCollaborationConflictCall = Future<String> Function({
  required String requestJson,
});

abstract interface class CollaborationConflictPort {
  Future<List<CollaborationConflict>> listOpenConflicts(
    CollaborationSyncIdentity identity,
  );

  Future<CollaborationConflictResolutionResult> resolveConflict(
    CollaborationSyncIdentity identity,
    String conflictId,
    CollaborationConflictResolution resolution, {
    required int expectedRemoteVersion,
  });
}

/// JSON adapter kept independent from generated bridge symbols. The production
/// replica wires the two callbacks after FRB code generation; tests can inject
/// deterministic callbacks without native libraries.
final class JsonCollaborationConflictPort implements CollaborationConflictPort {
  const JsonCollaborationConflictPort({
    required this.listOpen,
    required this.resolve,
  });

  final ListOpenCollaborationConflictsCall listOpen;
  final ResolveCollaborationConflictCall resolve;

  @override
  Future<List<CollaborationConflict>> listOpenConflicts(
    CollaborationSyncIdentity identity,
  ) async {
    final json = await listOpen(
      serverInstanceId: identity.serverInstanceId,
      accountId: identity.accountId,
      sessionId: identity.sessionId,
    );
    return CollaborationConflictList.fromJson(jsonDecode(json)).conflicts;
  }

  @override
  Future<CollaborationConflictResolutionResult> resolveConflict(
    CollaborationSyncIdentity identity,
    String conflictId,
    CollaborationConflictResolution resolution, {
    required int expectedRemoteVersion,
  }) async {
    if (expectedRemoteVersion < 1) {
      throw ArgumentError.value(
        expectedRemoteVersion,
        'expectedRemoteVersion',
        'must be positive',
      );
    }
    final json = await resolve(
      requestJson: jsonEncode({
        'serverInstanceId': identity.serverInstanceId,
        'accountId': identity.accountId,
        'sessionId': identity.sessionId,
        'conflictId': conflictId,
        'resolution': resolution.toJson(),
        'expectedRemoteVersion': expectedRemoteVersion,
      }),
    );
    return CollaborationConflictResolutionResult.fromJson(jsonDecode(json));
  }
}

/// Explicit fail-closed stub for tests or hosts that intentionally omit the
/// generated Rust conflict API.
final class UnavailableCollaborationConflictPort
    implements CollaborationConflictPort {
  const UnavailableCollaborationConflictPort();

  Never _unavailable() => throw StateError(
        'COLLABORATION_CONFLICT_API_UNAVAILABLE: '
        '冲突 API 尚未连接到本地副本',
      );

  @override
  Future<List<CollaborationConflict>> listOpenConflicts(
    CollaborationSyncIdentity identity,
  ) async =>
      _unavailable();

  @override
  Future<CollaborationConflictResolutionResult> resolveConflict(
    CollaborationSyncIdentity identity,
    String conflictId,
    CollaborationConflictResolution resolution, {
    required int expectedRemoteVersion,
  }) async =>
      _unavailable();
}
