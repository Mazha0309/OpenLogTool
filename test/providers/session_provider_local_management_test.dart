import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/providers/session_provider.dart';
import 'package:openlogtool/src/bridge/models/session.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'current_session_id': source.sessionId,
    });
  });

  test('offline stop follows the replacement local session and persists it',
      () async {
    final requested = <String>[];
    final provider = SessionProvider(
      sessionListLoader: () async => [source],
      collaborationSessionLocalStopper: (sessionId) async {
        requested.add(sessionId);
        return editableLocal;
      },
    );
    addTearDown(provider.dispose);
    await provider.ready;

    final result = await provider.stopCurrentCollaborationSessionLocally();

    expect(requested, [source.sessionId]);
    expect(result, same(editableLocal));
    expect(provider.currentSessionId, editableLocal.sessionId);
    expect(provider.currentSession, same(editableLocal));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('current_session_id'), editableLocal.sessionId);
  });

  test('device-only close follows a replacement closed local history row',
      () async {
    final requested = <String>[];
    final provider = SessionProvider(
      sessionListLoader: () async => [source],
      localSessionCloser: (sessionId) async {
        requested.add(sessionId);
        return closedLocal;
      },
    );
    addTearDown(provider.dispose);
    await provider.ready;

    final result = await provider.closeSessionLocally(source.sessionId);

    expect(requested, [source.sessionId]);
    expect(result.status, 'closed');
    expect(provider.currentSessionId, closedLocal.sessionId);
    expect(provider.currentSession?.status, 'closed');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('current_session_id'), closedLocal.sessionId);
  });

  test('deleting the selected local replica clears the safe selection',
      () async {
    final requested = <String>[];
    final provider = SessionProvider(
      sessionListLoader: () async => [source],
      localSessionDeleter: (sessionId) async => requested.add(sessionId),
    );
    addTearDown(provider.dispose);
    await provider.ready;

    await provider.deleteSessionLocally(source.sessionId);

    expect(requested, [source.sessionId]);
    expect(provider.currentSessionId, isNull);
    expect(provider.currentSession, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('current_session_id'), isFalse);
  });

  test('closing a non-current row does not replace the current selection',
      () async {
    final provider = SessionProvider(
      sessionListLoader: () async => [source],
      localSessionCloser: (_) async => otherClosed,
    );
    addTearDown(provider.dispose);
    await provider.ready;

    await provider.closeSessionLocally('other-collaboration');

    expect(provider.currentSessionId, source.sessionId);
    expect(provider.currentSession, same(source));
  });

  test('a committed offline stop does not overwrite a newer selection',
      () async {
    final committed = Completer<Session>();
    final provider = SessionProvider(
      sessionListLoader: () async => [source, otherActive],
      collaborationSessionLocalStopper: (_) => committed.future,
    );
    addTearDown(provider.dispose);
    await provider.ready;

    final stopping = provider.stopCurrentCollaborationSessionLocally();
    await Future<void>.delayed(Duration.zero);
    await provider.switchToSession(otherActive.sessionId);
    committed.complete(editableLocal);

    expect(await stopping, same(editableLocal));
    expect(provider.currentSessionId, otherActive.sessionId);
    expect(provider.currentSession, same(otherActive));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('current_session_id'), otherActive.sessionId);
  });
}

const source = Session(
  sessionId: 'collaboration-session',
  title: 'Sunday net',
  status: 'active',
  createdAt: '2026-07-13T00:00:00Z',
  updatedAt: '2026-07-13T00:00:00Z',
);

const editableLocal = Session(
  sessionId: 'editable-local',
  title: 'Sunday net',
  status: 'active',
  createdAt: '2026-07-14T00:00:00Z',
  updatedAt: '2026-07-14T00:00:00Z',
);

const closedLocal = Session(
  sessionId: 'closed-local',
  title: 'Sunday net',
  status: 'closed',
  createdAt: '2026-07-14T00:00:00Z',
  updatedAt: '2026-07-14T00:01:00Z',
  closedAt: '2026-07-14T00:01:00Z',
);

const otherClosed = Session(
  sessionId: 'other-local-history',
  title: 'Other net',
  status: 'closed',
  createdAt: '2026-07-14T00:00:00Z',
  updatedAt: '2026-07-14T00:01:00Z',
  closedAt: '2026-07-14T00:01:00Z',
);

const otherActive = Session(
  sessionId: 'other-local-active',
  title: 'Other active net',
  status: 'active',
  createdAt: '2026-07-14T00:00:00Z',
  updatedAt: '2026-07-14T00:01:00Z',
);
