import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/providers/session_provider.dart';
import 'package:openlogtool/src/bridge/models/session.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
      'adopts the committed reopen result when preference writing returns false',
      () async {
    final reopened = _reopenedSession();
    final provider = SessionProvider(
      localSessionReopener: (_) async => reopened,
      currentSessionIdWriter: (_) async => false,
    );
    addTearDown(provider.dispose);
    await provider.ready;

    await provider.reopenLocalSession(reopened.sessionId);

    expect(provider.currentSessionId, reopened.sessionId);
    expect(provider.currentSession, reopened);
  });

  test('adopts the committed reopen result when preference writing throws',
      () async {
    final reopened = _reopenedSession();
    final provider = SessionProvider(
      localSessionReopener: (_) async => reopened,
      currentSessionIdWriter: (_) async => throw StateError('disk full'),
    );
    addTearDown(provider.dispose);
    await provider.ready;

    await provider.reopenLocalSession(reopened.sessionId);

    expect(provider.currentSessionId, reopened.sessionId);
    expect(provider.currentSession, reopened);
  });

  test('database replacement selects imported active session without restart',
      () async {
    SharedPreferences.setMockInitialValues({
      'current_session_id': 'before-import',
    });
    var rows = <Session>[
      _session('before-import', updatedAt: '2026-07-13T10:00:00Z'),
    ];
    final provider = SessionProvider(sessionListLoader: () async => rows);
    addTearDown(provider.dispose);
    await provider.ready;
    expect(provider.currentSessionId, 'before-import');

    rows = <Session>[
      _session('older-import', updatedAt: '2026-07-13T11:00:00Z'),
      _session('newer-import', updatedAt: '2026-07-13T12:00:00Z'),
    ];
    await provider.reloadAfterDatabaseReplacement();

    expect(provider.currentSessionId, 'newer-import');
    expect(
      (await SharedPreferences.getInstance()).getString('current_session_id'),
      'newer-import',
    );
  });

  test('database clear removes stale current session selection', () async {
    SharedPreferences.setMockInitialValues({
      'current_session_id': 'before-clear',
    });
    var rows = <Session>[_session('before-clear')];
    final provider = SessionProvider(sessionListLoader: () async => rows);
    addTearDown(provider.dispose);
    await provider.ready;

    rows = const [];
    await provider.reloadAfterDatabaseReplacement();

    expect(provider.currentSessionId, isNull);
    expect(provider.currentSession, isNull);
    expect(
      (await SharedPreferences.getInstance()).getString('current_session_id'),
      isNull,
    );
  });
}

Session _reopenedSession() => const Session(
      sessionId: 'reopened-session',
      title: 'Sunday net',
      status: 'active',
      shareCode: null,
      createdAt: '2026-07-13T12:00:00Z',
      updatedAt: '2026-07-13T13:00:00Z',
      closedAt: null,
      deletedAt: null,
    );

Session _session(
  String id, {
  String updatedAt = '2026-07-13T10:00:00Z',
}) =>
    Session(
      sessionId: id,
      title: id,
      status: 'active',
      createdAt: '2026-07-13T10:00:00Z',
      updatedAt: updatedAt,
    );
