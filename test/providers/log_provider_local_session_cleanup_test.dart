import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/models/log_entry.dart' as model;
import 'package:openlogtool/providers/log_provider.dart';
import 'package:openlogtool/src/bridge/models/session.dart';

void main() {
  test('forgetting a replaced source clears its pending and read-only caches',
      () async {
    final provider = LogProvider(
      sessionListLoader: () async => const [source, replacement],
      sessionLogPageLoader: (_, __, ___) async => [],
    );
    addTearDown(provider.dispose);
    await provider.reloadForSession(source.sessionId);
    final pending = _log('pending-source', source.sessionId);
    provider.stageCanonicalLog(pending);
    provider.setCollaborationReadOnly(source.sessionId, true);
    expect(
      provider.mutationBlockReason(pending),
      'COLLABORATION_SESSION_READ_ONLY',
    );

    await provider.reloadForSession(replacement.sessionId);
    await provider.forgetDeletedSession(source.sessionId);

    expect(provider.currentSessionId, replacement.sessionId);
    expect(provider.currentSessionReadOnly, isFalse);
    expect(provider.mutationBlockReason(pending), isNull);
  });

  test('forgetting the selected deleted session clears the log selection',
      () async {
    final provider = LogProvider(
      sessionListLoader: () async => const [source],
      sessionLogPageLoader: (_, __, ___) async => [],
    );
    addTearDown(provider.dispose);
    await provider.reloadForSession(source.sessionId);
    final pending = _log('pending-source', source.sessionId);
    provider.stageCanonicalLog(pending);
    provider.setCollaborationReadOnly(source.sessionId, true);

    await provider.forgetDeletedSession(source.sessionId);

    expect(provider.currentSessionId, isNull);
    expect(provider.logs, isEmpty);
    expect(provider.currentSessionReadOnly, isFalse);
    expect(provider.mutationBlockReason(pending), isNull);
  });
}

model.LogEntry _log(String id, String sessionId) => model.LogEntry(
      id: id,
      sessionId: sessionId,
      time: '2026-07-17T12:00:00Z',
      controller: 'BG5CRL',
      callsign: 'BA4AAA',
      report: '59',
      qth: '',
      device: '',
      power: '',
      antenna: '',
      height: '',
      createdAt: '2026-07-17T12:00:00Z',
      updatedAt: '2026-07-17T12:00:00Z',
    );

const source = Session(
  sessionId: 'collaboration-source',
  title: 'Sunday net',
  status: 'active',
  createdAt: '2026-07-17T00:00:00Z',
  updatedAt: '2026-07-17T00:00:00Z',
);

const replacement = Session(
  sessionId: 'local-replacement',
  title: 'Sunday net',
  status: 'active',
  createdAt: '2026-07-17T00:01:00Z',
  updatedAt: '2026-07-17T00:01:00Z',
);
