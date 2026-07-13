import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/providers/collaboration_provider.dart';
import 'package:openlogtool/providers/log_provider.dart';
import 'package:openlogtool/providers/session_provider.dart';
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
