import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/providers/collaboration_provider.dart';
import 'package:openlogtool/providers/log_provider.dart';
import 'package:openlogtool/providers/session_provider.dart';
import 'package:openlogtool/providers/server_provider.dart';
import 'package:openlogtool/providers/settings_provider.dart';
import 'package:openlogtool/screens/session_hub_page.dart';
import 'package:openlogtool/src/bridge/models/session.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
      'SessionHubPage exposes a direct Live Share entry for the current session',
      (tester) async {
    final sessions = [
      _session(
        id: 'current-session',
        title: '本周点名',
        status: 'active',
      ),
    ];
    final sessionProvider = _FakeSessionProvider(
      sessions: sessions,
      currentSessionId: 'current-session',
    );
    final logProvider = LogProvider(
      sessionListLoader: () async => sessions,
      sessionLogPageLoader: (_, __, ___) async => [],
    );

    await tester.pumpWidget(
      _SessionHubTestApp(
        sessionProvider: sessionProvider,
        logProvider: logProvider,
      ),
    );
    await tester.pumpAndSettle();

    final entry = find.byKey(const Key('open-live-share-management'));
    expect(entry, findsOneWidget);
    expect(find.text('Live Share 公开页面'), findsOneWidget);

    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('public-share-access-required')),
      findsOneWidget,
    );
  });

  testWidgets(
    'SessionHubPage opens a closed history session and returns to workbench',
    (tester) async {
      final sessions = [
        _session(
          id: 'current-session',
          title: '本周点名',
          status: 'active',
        ),
        _session(
          id: 'closed-session',
          title: '上周点名',
          status: 'closed',
        ),
      ];
      final sessionProvider = _FakeSessionProvider(
        sessions: sessions,
        currentSessionId: 'current-session',
      );
      final loadedSessionIds = <String>[];
      final logProvider = LogProvider(
        sessionListLoader: () async => sessions,
        sessionLogPageLoader: (sessionId, page, pageSize) async {
          loadedSessionIds.add(sessionId);
          return [];
        },
      );

      await tester.pumpWidget(
        _SessionHubTestApp(
          sessionProvider: sessionProvider,
          logProvider: logProvider,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('open-session-history')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('session-history-dialog')), findsOneWidget);
      expect(find.text('上周点名'), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('session-history-tile-closed-session')),
      );
      await tester.pumpAndSettle();

      expect(sessionProvider.currentSessionId, 'closed-session');
      expect(loadedSessionIds, contains('closed-session'));
      expect(logProvider.currentSessionReadOnly, isTrue);
      expect(find.byKey(const Key('session-history-dialog')), findsNothing);
      expect(find.byKey(const Key('workbench-after-history')), findsOneWidget);
    },
  );

  testWidgets('SessionHubPage keeps the dialog open when loading logs fails',
      (tester) async {
    final sessions = [
      _session(
        id: 'current-session',
        title: '本周点名',
        status: 'active',
      ),
      _session(
        id: 'broken-session',
        title: '损坏的历史会话',
        status: 'closed',
      ),
    ];
    final sessionProvider = _FakeSessionProvider(
      sessions: sessions,
      currentSessionId: 'current-session',
    );
    final loadedSessionIds = <String>[];
    final logProvider = LogProvider(
      sessionListLoader: () async => sessions,
      sessionLogPageLoader: (sessionId, page, pageSize) async {
        loadedSessionIds.add(sessionId);
        if (sessionId == 'broken-session') {
          throw StateError('broken log page');
        }
        return [];
      },
    );

    await tester.pumpWidget(
      _SessionHubTestApp(
        sessionProvider: sessionProvider,
        logProvider: logProvider,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open-session-history')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('session-history-tile-broken-session')),
    );
    await tester.pumpAndSettle();

    expect(sessionProvider.currentSessionId, 'current-session');
    expect(
        loadedSessionIds,
        containsAllInOrder([
          'broken-session',
          'current-session',
        ]));
    expect(find.byKey(const Key('session-history-dialog')), findsOneWidget);
    expect(find.textContaining('打开会话失败'), findsOneWidget);
    expect(find.byKey(const Key('workbench-after-history')), findsNothing);
  });

  testWidgets(
      'current closed local session has a visible reactivate action and returns to workbench',
      (tester) async {
    final sessions = [
      _session(
        id: 'closed-session',
        title: '上周点名',
        status: 'closed',
      ),
    ];
    final sessionProvider = _FakeSessionProvider(
      sessions: sessions,
      currentSessionId: 'closed-session',
    );
    final loadedSessionIds = <String>[];
    final logProvider = LogProvider(
      sessionListLoader: () async => sessions,
      sessionLogPageLoader: (sessionId, page, pageSize) async {
        loadedSessionIds.add(sessionId);
        return [];
      },
    );

    await tester.pumpWidget(
      _SessionHubTestApp(
        sessionProvider: sessionProvider,
        logProvider: logProvider,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('reopen-current-local-session')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const Key('reopen-current-local-session')),
    );
    await tester.pumpAndSettle();
    expect(find.text('重新激活本地会话'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('confirm-reopen-local-session')),
    );
    await tester.pumpAndSettle();

    expect(sessionProvider.currentSession.status, 'active');
    expect(sessionProvider.currentSessionId, 'closed-session');
    expect(loadedSessionIds, contains('closed-session'));
    expect(logProvider.currentSessionReadOnly, isFalse);
    expect(find.byKey(const Key('workbench-after-history')), findsOneWidget);
  });

  testWidgets(
      'reactivating a non-current history session selects it and makes logs writable',
      (tester) async {
    final sessions = [
      _session(
        id: 'current-session',
        title: '本周点名',
        status: 'active',
      ),
      _session(
        id: 'closed-session',
        title: '上周点名',
        status: 'closed',
      ),
    ];
    final sessionProvider = _FakeSessionProvider(
      sessions: sessions,
      currentSessionId: 'current-session',
    );
    final logProvider = LogProvider(
      sessionListLoader: () async => sessions,
      sessionLogPageLoader: (_, __, ___) async => [],
    );

    await tester.pumpWidget(
      _SessionHubTestApp(
        sessionProvider: sessionProvider,
        logProvider: logProvider,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-session-history')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('reopen-history-session-closed-session')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('confirm-reopen-local-session')),
    );
    await tester.pumpAndSettle();

    expect(sessionProvider.currentSessionId, 'closed-session');
    expect(sessionProvider.currentSession.status, 'active');
    expect(logProvider.currentSessionReadOnly, isFalse);
    expect(find.byKey(const Key('workbench-after-history')), findsOneWidget);
    final refreshedSessions = await sessionProvider.listAvailableSessions();
    expect(
      refreshedSessions
          .singleWhere((session) => session.sessionId == 'current-session')
          .status,
      'closed',
    );
  });

  testWidgets(
      'reactivated history session stays selected but read-only when logs fail to load',
      (tester) async {
    final sessions = [
      _session(
        id: 'current-session',
        title: '本周点名',
        status: 'active',
      ),
      _session(
        id: 'broken-session',
        title: '日志损坏场次',
        status: 'closed',
      ),
    ];
    final sessionProvider = _FakeSessionProvider(
      sessions: sessions,
      currentSessionId: 'current-session',
    );
    var brokenLoadAttempts = 0;
    final logProvider = LogProvider(
      sessionListLoader: () async => sessions,
      sessionLogPageLoader: (sessionId, _, __) async {
        if (sessionId == 'broken-session' && brokenLoadAttempts++ == 0) {
          throw StateError('broken reopened log page');
        }
        return [];
      },
    );

    await tester.pumpWidget(
      _SessionHubTestApp(
        sessionProvider: sessionProvider,
        logProvider: logProvider,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-session-history')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('reopen-history-session-broken-session')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('confirm-reopen-local-session')),
    );
    await tester.pumpAndSettle();

    expect(sessionProvider.currentSessionId, 'broken-session');
    expect(sessionProvider.currentSession.status, 'active');
    expect(logProvider.currentSessionId, 'broken-session');
    expect(logProvider.currentSessionReadOnly, isTrue);
    expect(find.byKey(const Key('session-history-dialog')), findsNothing);
    expect(find.textContaining('已重新激活，但日志暂时加载失败'), findsOneWidget);
    expect(find.byKey(const Key('workbench-after-history')), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(brokenLoadAttempts, 2);
    expect(logProvider.currentSessionId, 'broken-session');
    expect(logProvider.currentSessionReadOnly, isFalse);
  });
}

class _SessionHubTestApp extends StatefulWidget {
  const _SessionHubTestApp({
    required this.sessionProvider,
    required this.logProvider,
  });

  final SessionProvider sessionProvider;
  final LogProvider logProvider;

  @override
  State<_SessionHubTestApp> createState() => _SessionHubTestAppState();
}

class _SessionHubTestAppState extends State<_SessionHubTestApp> {
  bool _showWorkbench = false;

  @override
  Widget build(BuildContext context) => MultiProvider(
        providers: [
          ChangeNotifierProvider<SessionProvider>.value(
            value: widget.sessionProvider,
          ),
          ChangeNotifierProvider<LogProvider>.value(value: widget.logProvider),
          ChangeNotifierProvider(create: (_) => CollaborationProvider()),
          ChangeNotifierProvider(
            create: (_) => ServerProvider(autoLoadSettings: false),
          ),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ],
        child: MaterialApp(
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: _showWorkbench
                ? const Text(
                    'workbench',
                    key: Key('workbench-after-history'),
                  )
                : SessionHubPage(
                    onSessionOpened: () {
                      setState(() => _showWorkbench = true);
                    },
                  ),
          ),
        ),
      );
}

class _FakeSessionProvider extends SessionProvider {
  _FakeSessionProvider({
    required List<Session> sessions,
    required String currentSessionId,
  })  : _sessions = sessions,
        _currentSession = sessions.firstWhere(
          (session) => session.sessionId == currentSessionId,
        );

  final List<Session> _sessions;
  Session _currentSession;

  @override
  Future<void> get ready => Future<void>.value();

  @override
  String get currentSessionId => _currentSession.sessionId;

  @override
  Session get currentSession => _currentSession;

  @override
  Future<List<Session>> listAvailableSessions() async => [..._sessions];

  @override
  Future<void> switchToSession(String sessionId) async {
    _currentSession = _sessions.firstWhere(
      (session) => session.sessionId == sessionId,
    );
    notifyListeners();
  }

  @override
  Future<void> reloadCurrentSession() async {
    _currentSession = _sessions.firstWhere(
      (session) => session.sessionId == _currentSession.sessionId,
    );
    notifyListeners();
  }

  @override
  Future<void> reopenLocalSession(String sessionId) async {
    for (var candidate = 0; candidate < _sessions.length; candidate += 1) {
      final existing = _sessions[candidate];
      if (existing.sessionId != sessionId && existing.status == 'active') {
        _sessions[candidate] = Session(
          sessionId: existing.sessionId,
          title: existing.title,
          status: 'closed',
          shareCode: existing.shareCode,
          createdAt: existing.createdAt,
          updatedAt: '2026-07-13T12:00:00Z',
          closedAt: '2026-07-13T12:00:00Z',
          deletedAt: existing.deletedAt,
        );
      }
    }
    final index = _sessions.indexWhere(
      (session) => session.sessionId == sessionId,
    );
    if (index < 0) throw StateError('Session not found: $sessionId');
    final previous = _sessions[index];
    final reopened = Session(
      sessionId: previous.sessionId,
      title: previous.title,
      status: 'active',
      shareCode: previous.shareCode,
      createdAt: previous.createdAt,
      updatedAt: '2026-07-13T12:00:00Z',
      closedAt: null,
      deletedAt: previous.deletedAt,
    );
    _sessions[index] = reopened;
    _currentSession = reopened;
    notifyListeners();
  }
}

Session _session({
  required String id,
  required String title,
  required String status,
}) =>
    Session(
      sessionId: id,
      title: title,
      status: status,
      createdAt: '2026-07-13T10:00:00Z',
      updatedAt: '2026-07-13T11:00:00Z',
      closedAt: status == 'closed' ? '2026-07-13T11:00:00Z' : null,
    );
