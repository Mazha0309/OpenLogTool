import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/providers/collaboration_provider.dart';
import 'package:openlogtool/providers/dictionary_provider.dart';
import 'package:openlogtool/providers/log_provider.dart';
import 'package:openlogtool/providers/session_provider.dart';
import 'package:openlogtool/providers/settings_provider.dart';
import 'package:openlogtool/screens/home_screen.dart';
import 'package:openlogtool/src/bridge/models/session.dart';
import 'package:openlogtool/widgets/log_form.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('wide workbench limit is 1440 and can be disabled',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final settings = SettingsProvider();
    final sessions = _FixedSessionProvider();
    final logs = LogProvider(
      sessionListLoader: () async => [_FixedSessionProvider.session],
      sessionLogPageLoader: (_, __, ___) async => [],
    );
    final collaboration = CollaborationProvider();
    addTearDown(settings.dispose);
    addTearDown(sessions.dispose);
    addTearDown(logs.dispose);
    addTearDown(collaboration.dispose);
    await logs.reloadForSession(_FixedSessionProvider.session.sessionId);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<SessionProvider>.value(value: sessions),
          ChangeNotifierProvider<LogProvider>.value(value: logs),
          ChangeNotifierProvider<CollaborationProvider>.value(
            value: collaboration,
          ),
          ChangeNotifierProvider(
            create: (_) => DictionaryProvider(autoload: false),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('zh', 'CN'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: AddRecordPage()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const Key('current-record-section')), findsOneWidget);
    expect(find.byKey(const Key('saved-records-section')), findsOneWidget);
    final limited = find.byKey(const Key('workbench-width-limit'));
    expect(limited, findsOneWidget);
    expect(tester.getSize(limited).width, 1440);
    expect(_workbenchScrollWidth(tester), 1600);
    for (final key in const [
      'workbench-status-bar',
      'current-record-section',
      'saved-records-section',
    ]) {
      expect(
        find.ancestor(of: find.byKey(Key(key)), matching: limited),
        findsOneWidget,
      );
    }
    expect(
      tester.getSize(find.byKey(const Key('workbench-status-bar'))).height,
      lessThanOrEqualTo(56),
    );
    final statusHeader =
        tester.getRect(find.byKey(const Key('workbench-session-header')));
    final statuses =
        tester.getRect(find.byKey(const Key('workbench-session-statuses')));
    expect(statusHeader.right - statuses.right, lessThanOrEqualTo(13));
    final currentSection =
        tester.getRect(find.byKey(const Key('current-record-section')));
    final ordinal =
        tester.getRect(find.byKey(const Key('current-ordinal-badge')));
    expect(currentSection.right - ordinal.right, lessThanOrEqualTo(20));

    await settings.setLimitWorkbenchWidth(false);
    await tester.pump();

    expect(find.byKey(const Key('workbench-width-limit')), findsNothing);
    expect(_workbenchScrollWidth(tester), 1600);
    expect(tester.getSize(find.byType(Card).first).width, closeTo(1560, 0.1));
  });
}

double _workbenchScrollWidth(WidgetTester tester) {
  final scroll = find
      .ancestor(
        of: find.byType(LogForm),
        matching: find.byType(SingleChildScrollView),
      )
      .first;
  return tester.getSize(scroll).width;
}

final class _FixedSessionProvider extends SessionProvider {
  static const session = Session(
    sessionId: 'wide-session',
    title: 'Wide workbench',
    status: 'active',
    createdAt: '2026-07-13T10:00:00Z',
    updatedAt: '2026-07-13T10:00:00Z',
  );

  @override
  Future<void> get ready => Future<void>.value();

  @override
  String get currentSessionId => session.sessionId;

  @override
  Session get currentSession => session;
}
