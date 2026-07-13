import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/models/collaboration_conflict.dart';
import 'package:openlogtool/models/collaboration_dto.dart';
import 'package:openlogtool/providers/collaboration_provider.dart';

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
