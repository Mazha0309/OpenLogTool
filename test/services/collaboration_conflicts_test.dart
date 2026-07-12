import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/models/collaboration_conflict.dart';
import 'package:openlogtool/services/collaboration_conflicts.dart';
import 'package:openlogtool/services/collaboration_sync.dart';

void main() {
  test('JSON conflict adapter preserves identity and resolution request',
      () async {
    final calls = <Object?>[];
    final adapter = JsonCollaborationConflictPort(
      listOpen: ({
        required serverInstanceId,
        required accountId,
        required sessionId,
      }) async {
        calls.add([serverInstanceId, accountId, sessionId]);
        return jsonEncode([
          {
            'conflictId': 'conflict-1',
            'sessionId': sessionId,
            'entityType': 'session',
            'entityId': sessionId,
            'mutationId': 'mutation-1',
            'baseVersion': 1,
            'remoteVersion': 2,
            'baseEntity': {'title': 'base'},
            'localEntity': {'title': 'local'},
            'remoteEntity': {'title': 'remote'},
            'conflictingFields': ['title'],
            'allowedResolutions': ['useRemote', 'keepLocal'],
            'createdAt': '2026-07-12T08:00:00Z',
          },
        ]);
      },
      resolve: ({required requestJson}) async {
        calls.add(jsonDecode(requestJson));
        return jsonEncode({
          'outcome': 'resolved',
          'resolution': 'keepLocal',
          'replacementMutationId': 'replacement-1',
        });
      },
    );
    const identity = CollaborationSyncIdentity(
      serverInstanceId: 'server-1',
      serverOrigin: 'https://example.test',
      accountId: 'account-1',
      sessionId: 'session-1',
      deviceId: 'device-1',
    );

    final conflicts = await adapter.listOpenConflicts(identity);
    final result = await adapter.resolveConflict(
      identity,
      'conflict-1',
      CollaborationConflictResolution.keepLocal,
      expectedRemoteVersion: 2,
    );

    expect(conflicts.single.entityId, 'session-1');
    expect(result.replacementMutationId, 'replacement-1');
    expect(calls.first, ['server-1', 'account-1', 'session-1']);
    expect(calls.last, {
      'serverInstanceId': 'server-1',
      'accountId': 'account-1',
      'sessionId': 'session-1',
      'conflictId': 'conflict-1',
      'resolution': 'keepLocal',
      'expectedRemoteVersion': 2,
    });
  });

  test('JSON conflict adapter preserves copy-as-new replacement IDs', () async {
    Object? request;
    final adapter = JsonCollaborationConflictPort(
      listOpen: ({
        required serverInstanceId,
        required accountId,
        required sessionId,
      }) async =>
          '[]',
      resolve: ({required requestJson}) async {
        request = jsonDecode(requestJson);
        return jsonEncode({
          'outcome': 'resolved',
          'resolution': 'copyLocalAsNew',
          'replacementMutationId': 'replacement-copy-1',
          'replacementEntityId': 'log-copy-1',
        });
      },
    );
    const identity = CollaborationSyncIdentity(
      serverInstanceId: 'server-1',
      serverOrigin: 'https://example.test',
      accountId: 'account-1',
      sessionId: 'session-1',
      deviceId: 'device-1',
    );

    final result = await adapter.resolveConflict(
      identity,
      'conflict-1',
      CollaborationConflictResolution.copyLocalAsNew,
      expectedRemoteVersion: 7,
    );

    expect(result.replacementMutationId, 'replacement-copy-1');
    expect(result.replacementEntityId, 'log-copy-1');
    expect(request, {
      'serverInstanceId': 'server-1',
      'accountId': 'account-1',
      'sessionId': 'session-1',
      'conflictId': 'conflict-1',
      'resolution': 'copyLocalAsNew',
      'expectedRemoteVersion': 7,
    });
  });
}
