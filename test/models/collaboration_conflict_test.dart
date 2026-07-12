import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/models/collaboration_conflict.dart';

void main() {
  test('parses the Rust open-conflict array without losing entity snapshots',
      () {
    final conflicts = CollaborationConflictList.fromJson([
      {
        'conflictId': 'conflict-1',
        'sessionId': 'session-1',
        'entityType': 'log',
        'entityId': 'log-1',
        'mutationId': 'mutation-1',
        'baseVersion': 2,
        'remoteVersion': 4,
        'baseEntity': {'callsign': 'BA4OLD', 'remarks': 'base', 'version': 2},
        'localEntity': {
          'callsign': 'BA4LOCAL',
          'remarks': 'local',
          'version': 2,
        },
        'remoteEntity': {
          'callsign': 'BA4REMOTE',
          'remarks': 'remote',
          'version': 4,
        },
        'conflictingFields': ['callsign', 'remarks'],
        'allowedResolutions': [
          'useRemote',
          'keepLocal',
          'copyLocalAsNew',
        ],
        'createdAt': '2026-07-12T08:00:00Z',
      },
    ]).conflicts;

    expect(conflicts, hasLength(1));
    expect(conflicts.single.entityType, CollaborationConflictEntityType.log);
    expect(conflicts.single.conflictingFields, ['callsign', 'remarks']);
    expect(conflicts.single.allowedResolutions, [
      CollaborationConflictResolution.useRemote,
      CollaborationConflictResolution.keepLocal,
      CollaborationConflictResolution.copyLocalAsNew,
    ]);
    expect(conflicts.single.localEntity['remarks'], 'local');
    expect(
      collaborationConflictEntitySummary(conflicts.single.remoteEntity),
      contains('呼号=BA4REMOTE'),
    );
  });

  test('allows keepLocal to converge without a replacement mutation', () {
    final keepLocal = CollaborationConflictResolutionResult.fromJson({
      'outcome': 'resolved',
      'resolution': 'keepLocal',
      'replacementMutationId': 'replacement-1',
    });
    final useRemote = CollaborationConflictResolutionResult.fromJson({
      'outcome': 'resolved',
      'resolution': 'useRemote',
    });
    final converged = CollaborationConflictResolutionResult.fromJson({
      'outcome': 'resolved',
      'resolution': 'keepLocal',
    });
    final copied = CollaborationConflictResolutionResult.fromJson({
      'outcome': 'resolved',
      'resolution': 'copyLocalAsNew',
      'replacementMutationId': 'replacement-copy-1',
      'replacementEntityId': 'log-copy-1',
    });

    expect(keepLocal.replacementMutationId, 'replacement-1');
    expect(useRemote.replacementMutationId, isNull);
    expect(converged.replacementMutationId, isNull);
    expect(copied.replacementMutationId, 'replacement-copy-1');
    expect(copied.replacementEntityId, 'log-copy-1');
    expect(
      () => CollaborationConflictList.fromJson({
        'conflicts': const [],
      }),
      throwsFormatException,
    );
  });

  test('rejects incomplete or contradictory resolution results', () {
    expect(
      () => CollaborationConflictResolutionResult.fromJson({
        'outcome': 'resolved',
        'resolution': 'copyLocalAsNew',
        'replacementMutationId': 'replacement-copy-1',
      }),
      throwsFormatException,
    );
    expect(
      () => CollaborationConflictResolutionResult.fromJson({
        'outcome': 'resolved',
        'resolution': 'keepLocal',
        'replacementEntityId': 'log-copy-1',
      }),
      throwsFormatException,
    );
  });
}
