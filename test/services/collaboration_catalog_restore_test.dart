import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/models/collaboration_dto.dart';
import 'package:openlogtool/services/collaboration_catalog_restore.dart';

void main() {
  group('restoreMissingCollaborationSessions', () {
    test('restores active and closed sessions while skipping ineligible ones',
        () async {
      final installed = <String>[];
      final result = await restoreMissingCollaborationSessions(
        remoteSessions: [
          _session('existing'),
          _session('active'),
          _session('closed', status: 'closed'),
          _session('initializing', status: 'initializing'),
          _session('deleted', deleted: true),
        ],
        accountId: 'account-1',
        bindingExists: (id) async => id == 'existing',
        loadMembership: (id) async => _membership(id),
        loadSnapshot: (id) async => _snapshot(id),
        installSnapshot: ({required membership, required snapshot}) async {
          expect(membership.sessionId, snapshot.session.sessionId);
          installed.add(snapshot.session.sessionId);
        },
      );

      expect(installed, ['active', 'closed']);
      expect(result.installedSessionIds, ['active', 'closed']);
      expect(result.issues, isEmpty);
      expect(result.cancelled, isFalse);
    });

    test('isolates a malformed session and continues restoring the catalog',
        () async {
      final installed = <String>[];
      final result = await restoreMissingCollaborationSessions(
        remoteSessions: [_session('bad'), _session('good')],
        accountId: 'account-1',
        bindingExists: (_) async => false,
        loadMembership: (id) async =>
            _membership(id, userId: id == 'bad' ? 'other-account' : 'account-1'),
        loadSnapshot: (id) async => _snapshot(id),
        installSnapshot: ({required membership, required snapshot}) async {
          installed.add(snapshot.session.sessionId);
        },
      );

      expect(installed, ['good']);
      expect(result.installedSessionIds, ['good']);
      expect(result.issues, hasLength(1));
      expect(result.issues.single.sessionId, 'bad');
      expect(result.cancelled, isFalse);
    });

    test('stops without starting another install after the scope changes',
        () async {
      var current = true;
      final result = await restoreMissingCollaborationSessions(
        remoteSessions: [_session('first'), _session('second')],
        accountId: 'account-1',
        bindingExists: (_) async => false,
        loadMembership: (id) async => _membership(id),
        loadSnapshot: (id) async => _snapshot(id),
        installSnapshot: ({required membership, required snapshot}) async {
          current = false;
        },
        isCurrent: () => current,
      );

      expect(result.installedSessionIds, isEmpty);
      expect(result.issues, isEmpty);
      expect(result.cancelled, isTrue);
    });
  });
}

final _now = DateTime.utc(2026, 7, 22, 12);

CollaborationSessionDto _session(
  String id, {
  String status = 'active',
  bool deleted = false,
}) =>
    CollaborationSessionDto(
      sessionId: id,
      title: 'Session $id',
      status: status,
      version: 1,
      role: SessionRole.editor,
      highWatermarkSeq: 0,
      createdAt: _now,
      updatedAt: _now,
      closedAt: status == 'closed' ? _now : null,
      deletedAt: deleted ? _now : null,
    );

MembershipDto _membership(
  String sessionId, {
  String userId = 'account-1',
}) =>
    MembershipDto(
      membershipId: 'membership-$sessionId',
      sessionId: sessionId,
      userId: userId,
      role: SessionRole.editor,
      version: 1,
      joinedAt: _now,
      updatedAt: _now,
      removedAt: null,
    );

SessionSnapshotDto _snapshot(String sessionId) => SessionSnapshotDto(
      protocolVersion: 1,
      session: _session(sessionId),
      highWatermarkSeq: 0,
      includesDeletedLogs: false,
      logs: const [],
    );
