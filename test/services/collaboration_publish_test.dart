import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/models/collaboration_dto.dart';
import 'package:openlogtool/services/collaboration_publish.dart';

void main() {
  BootstrapLogDto log(String id, {String? remarks}) => BootstrapLogDto(
        syncId: id,
        time: DateTime.parse('2026-07-11T08:00:00Z'),
        controller: 'BG5CRL',
        callsign: 'BA4AAA',
        remarks: remarks,
      );

  test('publish preflight enforces server field constraints before upload', () {
    expect(
      () => prepareCollaborationPublish(
        sessionId: 'session-1',
        title: 'valid',
        logs: [log('bad id')],
      ),
      throwsA(isA<CollaborationPublishValidationException>()),
    );
    expect(
      () => prepareCollaborationPublish(
        sessionId: 'session-1',
        title: 'valid',
        logs: [log('log-1', remarks: List.filled(2001, 'x').join())],
      ),
      throwsA(isA<CollaborationPublishValidationException>()),
    );
  });

  test('publish batches obey both item and encoded UTF-8 byte limits', () {
    final prepared = prepareCollaborationPublish(
      sessionId: 'session-1',
      title: '  Session title  ',
      logs: List.generate(
        5,
        (index) => log(
          'log-$index',
          remarks: List.filled(40, '测').join(),
        ),
      ),
      maxItems: 3,
      maxBodyBytes: 650,
    );

    expect(prepared.title, 'Session title');
    expect(prepared.batches.length, greaterThan(1));
    for (final batch in prepared.batches) {
      expect(batch.length, lessThanOrEqualTo(3));
      final bytes = utf8.encode(
        jsonEncode({'items': batch.map((item) => item.toJson()).toList()}),
      );
      expect(bytes.length, lessThanOrEqualTo(650));
    }
  });

  test('published snapshot rejects identity drift and deleted remote logs', () {
    final timestamp = DateTime.parse('2026-07-11T08:00:00Z');
    final local = log('log-1', remarks: 'kept');

    SessionSnapshotDto snapshot({
      String sessionId = 'session-1',
      String title = 'Session title',
      DateTime? deletedAt,
    }) =>
        SessionSnapshotDto(
          protocolVersion: 1,
          session: CollaborationSessionDto(
            sessionId: sessionId,
            title: title,
            status: 'active',
            version: 1,
            role: SessionRole.owner,
            highWatermarkSeq: 1,
            createdAt: timestamp,
            updatedAt: timestamp,
            closedAt: null,
            deletedAt: null,
          ),
          highWatermarkSeq: 1,
          logs: [
            CollaborationLogDto(
              syncId: local.syncId,
              sessionId: sessionId,
              version: 1,
              time: local.time,
              controller: local.controller,
              callsign: local.callsign,
              rstSent: local.rstSent,
              rstRcvd: local.rstRcvd,
              qth: local.qth,
              device: local.device,
              power: local.power,
              antenna: local.antenna,
              height: local.height,
              remarks: local.remarks,
              createdAt: timestamp,
              updatedAt: timestamp,
              deletedAt: deletedAt,
            ),
          ],
        );

    expect(
      () => validatePublishedCollaborationSnapshot(
        sessionId: 'session-1',
        title: 'Session title',
        localLogs: [local],
        snapshot: snapshot(),
      ),
      returnsNormally,
    );
    expect(
      () => validatePublishedCollaborationSnapshot(
        sessionId: 'session-1',
        title: 'Session title',
        localLogs: [local],
        snapshot: snapshot(sessionId: 'other-session'),
      ),
      throwsStateError,
    );
    expect(
      () => validatePublishedCollaborationSnapshot(
        sessionId: 'session-1',
        title: 'Session title',
        localLogs: [local],
        snapshot: snapshot(deletedAt: timestamp),
      ),
      throwsStateError,
    );
  });
}
