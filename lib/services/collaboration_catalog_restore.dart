import 'package:flutter/foundation.dart';
import 'package:openlogtool/models/collaboration_dto.dart';

typedef CollaborationBindingExists = Future<bool> Function(String sessionId);
typedef CollaborationMembershipLoader = Future<MembershipDto> Function(
  String sessionId,
);
typedef CollaborationSnapshotLoader = Future<SessionSnapshotDto> Function(
  String sessionId,
);
typedef CollaborationSnapshotInstaller = Future<void> Function({
  required MembershipDto membership,
  required SessionSnapshotDto snapshot,
});

@immutable
final class CollaborationCatalogRestoreIssue {
  const CollaborationCatalogRestoreIssue({
    required this.sessionId,
    required this.title,
    required this.error,
  });

  final String sessionId;
  final String title;
  final Object error;
}

@immutable
final class CollaborationCatalogRestoreResult {
  const CollaborationCatalogRestoreResult({
    required this.installedSessionIds,
    required this.issues,
    required this.cancelled,
  });

  final List<String> installedSessionIds;
  final List<CollaborationCatalogRestoreIssue> issues;
  final bool cancelled;
}

/// Rebuilds missing local collaboration replicas from the signed-in account's
/// server catalog without changing the user's current Session selection.
///
/// One malformed or temporarily unavailable Session must not prevent other
/// historical Sessions from being recovered on a new device.
Future<CollaborationCatalogRestoreResult> restoreMissingCollaborationSessions({
  required List<CollaborationSessionDto> remoteSessions,
  required String accountId,
  required CollaborationBindingExists bindingExists,
  required CollaborationMembershipLoader loadMembership,
  required CollaborationSnapshotLoader loadSnapshot,
  required CollaborationSnapshotInstaller installSnapshot,
  bool Function()? isCurrent,
}) async {
  final installed = <String>[];
  final issues = <CollaborationCatalogRestoreIssue>[];
  final stillCurrent = isCurrent ?? () => true;

  for (final remote in remoteSessions) {
    if (!stillCurrent()) {
      return CollaborationCatalogRestoreResult(
        installedSessionIds: List.unmodifiable(installed),
        issues: List.unmodifiable(issues),
        cancelled: true,
      );
    }
    // An interrupted publish has no stable canonical history to restore yet.
    if (remote.status == 'initializing' || remote.deletedAt != null) continue;

    try {
      if (await bindingExists(remote.sessionId)) continue;
      if (!stillCurrent()) continue;

      final membership = await loadMembership(remote.sessionId);
      if (!stillCurrent()) continue;
      if (membership.sessionId != remote.sessionId ||
          membership.userId != accountId ||
          membership.removedAt != null) {
        throw StateError('COLLABORATION_CATALOG_MEMBERSHIP_MISMATCH');
      }

      final snapshot = await loadSnapshot(remote.sessionId);
      if (!stillCurrent()) continue;
      if (snapshot.session.sessionId != remote.sessionId) {
        throw StateError('COLLABORATION_CATALOG_SNAPSHOT_MISMATCH');
      }

      await installSnapshot(membership: membership, snapshot: snapshot);
      if (!stillCurrent()) continue;
      installed.add(remote.sessionId);
    } catch (error) {
      if (!stillCurrent()) {
        return CollaborationCatalogRestoreResult(
          installedSessionIds: List.unmodifiable(installed),
          issues: List.unmodifiable(issues),
          cancelled: true,
        );
      }
      issues.add(
        CollaborationCatalogRestoreIssue(
          sessionId: remote.sessionId,
          title: remote.title,
          error: error,
        ),
      );
    }
  }

  return CollaborationCatalogRestoreResult(
    installedSessionIds: List.unmodifiable(installed),
    issues: List.unmodifiable(issues),
    cancelled: false,
  );
}
