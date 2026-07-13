import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/src/bridge/models/session.dart';
import 'package:openlogtool/widgets/session_history_dialog.dart';

void main() {
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
            loadSessions: () async => [
              _session(
                id: 'current-session',
                title: 'Current net',
                status: 'active',
              ),
            ],
            openSession: (_) async => openCount += 1,
            closeSession: (_) async {},
            deleteSession: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Session history'), findsOneWidget);
    expect(find.text('Current session'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('session-history-tile-current-session')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(openCount, 0);
  });

  testWidgets(
      'only a closed non-current session can be permanently deleted by name',
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
      findsNothing,
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
    FilledButton confirmButton() => tester.widget<FilledButton>(
          find.byKey(const Key('confirm-delete-history-session')),
        );
    expect(confirmButton().onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('delete-history-session-name')),
      '上周',
    );
    await tester.pump();
    expect(confirmButton().onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('delete-history-session-name')),
      '上周点名',
    );
    await tester.pump();
    expect(confirmButton().onPressed, isNotNull);

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
