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
