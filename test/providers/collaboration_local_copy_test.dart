import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/models/collaboration_dto.dart';
import 'package:openlogtool/providers/collaboration_provider.dart';
import 'package:openlogtool/providers/log_provider.dart';
import 'package:openlogtool/providers/server_provider.dart';
import 'package:openlogtool/providers/session_provider.dart';
import 'package:openlogtool/src/bridge/models/session.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('local copy switches to a writable session without contacting server',
      () async {
    final sessions = _CopySessionProvider();
    final logs = LogProvider(
      sessionListLoader: () async => [
        _CopySessionProvider.source,
        _CopySessionProvider.local,
      ],
      sessionLogPageLoader: (_, __, ___) async => [],
    );
    final server = _OfflineServerProvider();
    final collaboration = _BoundCollaborationProvider();
    addTearDown(sessions.dispose);
    addTearDown(logs.dispose);
    addTearDown(server.dispose);
    addTearDown(collaboration.dispose);

    await logs.reloadForSession(_CopySessionProvider.source.sessionId);
    logs.setCollaborationReadOnly(
      _CopySessionProvider.source.sessionId,
      true,
    );
    collaboration.updateDependencies(server, sessions, logs);

    await collaboration.createEditableLocalCopy(
      title: 'Emergency local copy',
    );

    expect(sessions.requestedTitles, ['Emergency local copy']);
    expect(sessions.currentSessionId, _CopySessionProvider.local.sessionId);
    expect(logs.currentSessionId, _CopySessionProvider.local.sessionId);
    expect(logs.currentSessionReadOnly, isFalse);
    expect(collaboration.state, CollaborationState.localOnly);

    await logs.reloadForSession(_CopySessionProvider.source.sessionId);
    expect(logs.currentSessionReadOnly, isTrue);
    await logs.reloadForSession(_CopySessionProvider.local.sessionId);
    expect(logs.currentSessionReadOnly, isFalse);
  });

  test('direct conversion switches to a writable local session', () async {
    final sessions = _ConvertingSessionProvider();
    final logs = LogProvider(
      sessionListLoader: () async => [
        _ConvertingSessionProvider.source,
        _ConvertingSessionProvider.local,
      ],
      sessionLogPageLoader: (_, __, ___) async => [],
    );
    final server = _OfflineServerProvider();
    final collaboration = _DirectConversionCollaborationProvider(
      conversionReady: true,
    );
    addTearDown(sessions.dispose);
    addTearDown(logs.dispose);
    addTearDown(server.dispose);
    addTearDown(collaboration.dispose);

    await logs.reloadForSession(_ConvertingSessionProvider.source.sessionId);
    logs.setCollaborationReadOnly(
      _ConvertingSessionProvider.source.sessionId,
      true,
    );
    collaboration.updateDependencies(server, sessions, logs);

    await collaboration.convertCurrentSessionToLocal();

    expect(sessions.conversionCalls, 1);
    expect(
      sessions.currentSessionId,
      _ConvertingSessionProvider.local.sessionId,
    );
    expect(
      sessions.currentSession.title,
      _ConvertingSessionProvider.source.title,
    );
    expect(logs.currentSessionId, _ConvertingSessionProvider.local.sessionId);
    expect(logs.currentSessionReadOnly, isFalse);
    expect(collaboration.state, CollaborationState.localOnly);

    // Direct conversion removes the old collaboration-only permission marker.
    // The fake session loader deliberately still reports the source as active,
    // so its writable state proves that no stale read-only marker remains.
    await logs.reloadForSession(_ConvertingSessionProvider.source.sessionId);
    expect(logs.currentSessionReadOnly, isFalse);
    await logs.reloadForSession(_ConvertingSessionProvider.local.sessionId);
    expect(logs.currentSessionReadOnly, isFalse);
  });

  test('direct conversion rejects a session that is not ready', () async {
    final sessions = _ConvertingSessionProvider();
    final logs = LogProvider(
      sessionListLoader: () async => [
        _ConvertingSessionProvider.source,
        _ConvertingSessionProvider.local,
      ],
      sessionLogPageLoader: (_, __, ___) async => [],
    );
    final server = _OfflineServerProvider();
    final collaboration = _DirectConversionCollaborationProvider(
      conversionReady: false,
    );
    addTearDown(sessions.dispose);
    addTearDown(logs.dispose);
    addTearDown(server.dispose);
    addTearDown(collaboration.dispose);

    await logs.reloadForSession(_ConvertingSessionProvider.source.sessionId);
    collaboration.updateDependencies(server, sessions, logs);

    await expectLater(
      collaboration.convertCurrentSessionToLocal(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'COLLABORATION_LOCAL_CONVERSION_NOT_READY',
        ),
      ),
    );

    expect(sessions.conversionCalls, 0);
    expect(
      sessions.currentSessionId,
      _ConvertingSessionProvider.source.sessionId,
    );
    expect(logs.currentSessionId, _ConvertingSessionProvider.source.sessionId);
  });
}

class _BoundCollaborationProvider extends CollaborationProvider {
  @override
  LocalCollaborationBinding get binding => const LocalCollaborationBinding(
        serverInstanceId: 'server-1',
        serverOrigin: 'https://offline.example.test',
        accountId: 'user-1',
        sessionId: 'collaboration-session',
        membershipId: 'membership-1',
        membershipVersion: 1,
        role: SessionRole.owner,
        replicaState: 'ready',
        lastAppliedSeq: 12,
        lastSeenHeadSeq: 12,
        revokedAt: null,
      );

  @override
  Future<void> refreshCurrentSession() async {}
}

class _CopySessionProvider extends SessionProvider {
  static const source = Session(
    sessionId: 'collaboration-session',
    title: 'Sunday net',
    status: 'active',
    createdAt: '2026-07-13T00:00:00Z',
    updatedAt: '2026-07-13T00:00:00Z',
  );
  static const local = Session(
    sessionId: 'local-copy',
    title: 'Emergency local copy',
    status: 'active',
    createdAt: '2026-07-14T00:00:00Z',
    updatedAt: '2026-07-14T00:00:00Z',
  );

  Session _current = source;
  final List<String> requestedTitles = [];

  @override
  Future<void> get ready => Future<void>.value();

  @override
  String get currentSessionId => _current.sessionId;

  @override
  Session get currentSession => _current;

  @override
  Future<Session> copyCurrentCollaborationSessionToLocal({
    required String title,
  }) async {
    requestedTitles.add(title);
    _current = local;
    notifyListeners();
    return local;
  }
}

class _DirectConversionCollaborationProvider extends CollaborationProvider {
  _DirectConversionCollaborationProvider({required this.conversionReady});

  final bool conversionReady;

  @override
  LocalCollaborationBinding get binding => const LocalCollaborationBinding(
        serverInstanceId: 'server-1',
        serverOrigin: 'https://offline.example.test',
        accountId: 'user-1',
        sessionId: 'collaboration-session',
        membershipId: 'membership-1',
        membershipVersion: 1,
        role: SessionRole.owner,
        replicaState: 'ready',
        lastAppliedSeq: 12,
        lastSeenHeadSeq: 12,
        revokedAt: null,
      );

  @override
  bool get canConvertCurrentSessionDirectly => conversionReady;

  @override
  Future<void> refreshCurrentSession() async {}
}

class _ConvertingSessionProvider extends SessionProvider {
  static const source = Session(
    sessionId: 'collaboration-session',
    title: 'Sunday net',
    status: 'active',
    createdAt: '2026-07-13T00:00:00Z',
    updatedAt: '2026-07-13T00:00:00Z',
  );
  static const local = Session(
    sessionId: 'converted-local-session',
    title: 'Sunday net',
    status: 'active',
    createdAt: '2026-07-14T00:00:00Z',
    updatedAt: '2026-07-14T00:00:00Z',
  );

  Session _current = source;
  int conversionCalls = 0;

  @override
  Future<void> get ready => Future<void>.value();

  @override
  String get currentSessionId => _current.sessionId;

  @override
  Session get currentSession => _current;

  @override
  Future<Session> convertCurrentCollaborationSessionToLocal() async {
    conversionCalls += 1;
    _current = local;
    notifyListeners();
    return local;
  }
}

class _OfflineServerProvider extends ServerProvider {
  _OfflineServerProvider() : super(autoLoadSettings: false);

  @override
  bool get isLoggedIn => false;

  @override
  String get serverUrl => 'https://offline.example.test';

  @override
  String? get accountId => null;
}
