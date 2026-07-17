import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/src/bridge/models/session.dart';
import 'package:openlogtool/widgets/session_history_dialog.dart';

void main() {
  test('history close routes a local session to the local close action',
      () async {
    final session = _session(
      id: 'local-session',
      title: 'Local net',
      status: 'active',
    );
    var localCloseCount = 0;
    var collaborationCloseCount = 0;

    await closeSessionFromHistory(
      session: session,
      currentSessionId: session.sessionId,
      hasCollaborationBinding: (_) async => false,
      closeLocalSession: (_) async => localCloseCount += 1,
      closeCurrentCollaborationLocally: () async =>
          collaborationCloseCount += 1,
    );

    expect(localCloseCount, 1);
    expect(collaborationCloseCount, 0);
  });

  test('history close handles a non-current collaboration replica locally',
      () async {
    final session = _session(
      id: 'remote-session',
      title: 'Remote net',
      status: 'active',
    );

    var localCloseCount = 0;
    var currentCloseCount = 0;
    await closeSessionFromHistory(
      session: session,
      currentSessionId: 'other-session',
      hasCollaborationBinding: (_) async => true,
      closeLocalSession: (_) async => localCloseCount += 1,
      closeCurrentCollaborationLocally: () async => currentCloseCount += 1,
    );

    expect(localCloseCount, 1);
    expect(currentCloseCount, 0);
  });

  test('history close stops the current collaboration only on this device',
      () async {
    final session = _session(
      id: 'remote-session',
      title: 'Remote net',
      status: 'active',
    );
    var localCloseCount = 0;
    var localCollaborationCloseCount = 0;

    await closeSessionFromHistory(
      session: session,
      currentSessionId: session.sessionId,
      hasCollaborationBinding: (_) async => true,
      closeLocalSession: (_) async => localCloseCount += 1,
      closeCurrentCollaborationLocally: () async =>
          localCollaborationCloseCount += 1,
    );

    expect(localCloseCount, 0);
    expect(localCollaborationCloseCount, 1);
  });

  testWidgets('a closed session opens from the whole history row in zh_CN',
      (tester) async {
    String? openedSessionId;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              key: const Key('show-session-history'),
              onPressed: () => showDialog<Session>(
                context: context,
                builder: (_) => SessionHistoryDialog(
                  currentSessionId: 'current-session',
                  loadSessions: () async => [
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
                  ],
                  openSession: (session) async {
                    openedSessionId = session.sessionId;
                  },
                  reopenSession: (_) async {},
                  closeSession: (_) async {},
                  deleteSession: (_) async {},
                ),
              ),
              child: const Text('show'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('show-session-history')));
    await tester.pumpAndSettle();

    expect(find.text('历史会话'), findsOneWidget);
    expect(find.text('历史记录'), findsNothing);
    expect(find.text('上周点名'), findsOneWidget);
    expect(find.textContaining('已关闭'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('session-history-tile-closed-session')),
    );
    await tester.pumpAndSettle();

    expect(openedSessionId, 'closed-session');
    expect(find.byKey(const Key('session-history-dialog')), findsNothing);
  });

  testWidgets('current session is marked and cannot be opened again',
      (tester) async {
    var openCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en', 'US'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SessionHistoryDialog(
            currentSessionId: 'current-session',
            canCloseCurrentSession: true,
            loadSessions: () async => [
              _session(
                id: 'current-session',
                title: 'Current net',
                status: 'active',
              ),
            ],
            openSession: (_) async => openCount += 1,
            reopenSession: (_) async {},
            closeSession: (_) async {},
            deleteSession: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Session history'), findsOneWidget);
    expect(find.text('Current session'), findsOneWidget);
    expect(
      find.byKey(const Key('close-history-session-current-session')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const Key('session-history-tile-current-session')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(openCount, 0);
  });

  testWidgets('current closed session keeps its marker and can be reactivated',
      (tester) async {
    var reopenCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              key: const Key('show-session-history'),
              onPressed: () => showDialog<Session>(
                context: context,
                builder: (_) => SessionHistoryDialog(
                  currentSessionId: 'current-closed-session',
                  loadSessions: () async => [
                    _session(
                      id: 'current-closed-session',
                      title: '正在查看的旧场次',
                      status: 'closed',
                    ),
                  ],
                  openSession: (_) async {},
                  reopenSession: (_) async => reopenCount += 1,
                  closeSession: (_) async {},
                  deleteSession: (_) async {},
                ),
              ),
              child: const Text('show'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('show-session-history')));
    await tester.pumpAndSettle();

    expect(find.text('当前会话'), findsOneWidget);
    expect(
      find.byKey(
        const Key('reopen-history-session-current-closed-session'),
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(
        const Key('reopen-history-session-current-closed-session'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('confirm-reopen-local-session')),
    );
    await tester.pumpAndSettle();

    expect(reopenCount, 1);
    expect(find.byKey(const Key('session-history-dialog')), findsNothing);
  });

  testWidgets('an archived session can be deleted but not reactivated',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en', 'US'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SessionHistoryDialog(
            currentSessionId: 'current-session',
            loadSessions: () async => [
              _session(
                id: 'archived-session',
                title: 'Archived net',
                status: 'archived',
              ),
            ],
            openSession: (_) async {},
            reopenSession: (_) async {},
            closeSession: (_) async {},
            deleteSession: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('archived'), findsOneWidget);
    expect(
      find.byKey(const Key('reopen-history-session-archived-session')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('delete-history-session-archived-session')),
      findsOneWidget,
    );
  });

  testWidgets('any non-current local row can be permanently deleted by name',
      (tester) async {
    final sessions = <Session>[
      _session(
        id: 'current-closed-session',
        title: '正在查看的旧场次',
        status: 'closed',
      ),
      _session(
        id: 'closed-session',
        title: '上周点名',
        status: 'closed',
      ),
      _session(
        id: 'active-session',
        title: '仍在进行的点名',
        status: 'active',
      ),
    ];
    String? deletedSessionId;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SessionHistoryDialog(
            currentSessionId: 'current-closed-session',
            loadSessions: () async => [...sessions],
            openSession: (_) async {},
            reopenSession: (_) async {},
            closeSession: (_) async {},
            deleteSession: (session) async {
              deletedSessionId = session.sessionId;
              sessions.removeWhere(
                (candidate) => candidate.sessionId == session.sessionId,
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const Key('delete-history-session-current-closed-session'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(const Key('delete-history-session-active-session')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('delete-history-session-closed-session')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('delete-history-session-closed-session')),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('不会删除或关闭服务器上的共享会话'),
      findsOneWidget,
    );
    expect(find.text('期望输入：上周点名'), findsOneWidget);
    FilledButton confirmButton() => tester.widget<FilledButton>(
          find.byKey(const Key('confirm-delete-history-session')),
        );
    expect(confirmButton().onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('delete-history-session-name')),
      '上周点铭',
    );
    await tester.pump();
    expect(confirmButton().onPressed, isNull);
    expect(find.text('输入的会话名不匹配，请逐字核对。'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('delete-history-session-name')),
      '  上周点名  ',
    );
    await tester.pump();
    expect(confirmButton().onPressed, isNotNull);
    expect(find.text('输入的会话名不匹配，请逐字核对。'), findsNothing);

    await tester.tap(
      find.byKey(const Key('confirm-delete-history-session')),
    );
    await tester.pumpAndSettle();

    expect(deletedSessionId, 'closed-session');
    expect(find.text('上周点名'), findsNothing);
    expect(find.text('已永久删除本机会话'), findsOneWidget);
  });

  testWidgets('a permanent-delete failure keeps the closed session visible',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en', 'US'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SessionHistoryDialog(
            currentSessionId: 'current-session',
            loadSessions: () async => [
              _session(
                id: 'closed-session',
                title: 'Sunday net',
                status: 'closed',
              ),
            ],
            openSession: (_) async {},
            reopenSession: (_) async {},
            closeSession: (_) async {},
            deleteSession: (_) async => throw StateError('disk busy'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('delete-history-session-closed-session')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('delete-history-session-name')),
      'Sunday net',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('confirm-delete-history-session')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sunday net'), findsOneWidget);
    expect(
      find.textContaining('Could not permanently delete local session'),
      findsOneWidget,
    );
  });

  testWidgets('a closed non-current session can be reactivated and opened',
      (tester) async {
    String? reopenedSessionId;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en', 'US'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              key: const Key('show-session-history'),
              onPressed: () => showDialog<Session>(
                context: context,
                builder: (_) => SessionHistoryDialog(
                  currentSessionId: 'current-session',
                  loadSessions: () async => [
                    _session(
                      id: 'closed-session',
                      title: 'Sunday net',
                      status: 'closed',
                    ),
                  ],
                  openSession: (_) async {},
                  reopenSession: (session) async {
                    reopenedSessionId = session.sessionId;
                  },
                  closeSession: (_) async {},
                  deleteSession: (_) async {},
                ),
              ),
              child: const Text('show'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('show-session-history')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('reopen-history-session-closed-session')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Reactivate local session'), findsOneWidget);
    expect(
      find.textContaining('Any other active local session'),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('confirm-reopen-local-session')),
    );
    await tester.pumpAndSettle();

    expect(reopenedSessionId, 'closed-session');
    expect(find.byKey(const Key('session-history-dialog')), findsNothing);
  });

  testWidgets('collaboration reopen rejection shows a readable next step',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SessionHistoryDialog(
            currentSessionId: 'current-session',
            loadSessions: () async => [
              _session(
                id: 'collaboration-session',
                title: '远程点名',
                status: 'closed',
              ),
            ],
            openSession: (_) async {},
            reopenSession: (_) async =>
                throw StateError('LOCAL_REOPEN_COLLABORATION_FORBIDDEN'),
            closeSession: (_) async {},
            deleteSession: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const Key('reopen-history-session-collaboration-session'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('confirm-reopen-local-session')),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('这是协作会话。请先打开该会话，再到“协作与成员”中重新打开。'),
      findsOneWidget,
    );
    expect(
      find.textContaining('LOCAL_REOPEN_COLLABORATION_FORBIDDEN'),
      findsNothing,
    );
  });

  testWidgets('history close explains and completes a device-only close',
      (tester) async {
    var closeCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SessionHistoryDialog(
            currentSessionId: 'current-session',
            loadSessions: () async => [
              _session(
                id: 'collaboration-session',
                title: '远程点名',
                status: 'active',
              ),
            ],
            openSession: (_) async {},
            reopenSession: (_) async {},
            closeSession: (_) async => closeCount += 1,
            deleteSession: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const Key('close-history-session-collaboration-session'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('服务器共享会话、成员及其他设备不受影响'), findsOneWidget);
    await tester.tap(find.text('仅在本机关闭').last);
    await tester.pumpAndSettle();

    expect(closeCount, 1);
    expect(find.text('已在本机关闭会话'), findsOneWidget);
  });

  testWidgets('replacement id remains marked current after local close',
      (tester) async {
    var currentId = 'collaboration-session';
    var sessions = <Session>[
      _session(
        id: 'collaboration-session',
        title: 'Sunday net',
        status: 'active',
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en', 'US'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SessionHistoryDialog(
            currentSessionId: currentId,
            currentSessionIdGetter: () => currentId,
            canCloseCurrentSession: true,
            loadSessions: () async => sessions,
            openSession: (_) async {},
            reopenSession: (_) async {},
            closeSession: (_) async {
              currentId = 'closed-local-session';
              sessions = [
                _session(
                  id: currentId,
                  title: 'Sunday net',
                  status: 'closed',
                ),
              ];
            },
            deleteSession: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const Key('close-history-session-collaboration-session'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close only on this device').last);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('session-history-tile-closed-local-session')),
      findsOneWidget,
    );
    expect(find.text('Current session'), findsOneWidget);
    expect(
      find.byKey(
        const Key('delete-history-session-closed-local-session'),
      ),
      findsNothing,
    );
  });
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
