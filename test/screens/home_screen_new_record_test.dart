import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/providers/collaboration_provider.dart';
import 'package:openlogtool/providers/dictionary_provider.dart';
import 'package:openlogtool/providers/log_provider.dart';
import 'package:openlogtool/providers/session_provider.dart';
import 'package:openlogtool/providers/settings_provider.dart';
import 'package:openlogtool/providers/snackbar_log_provider.dart';
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

  testWidgets(
    'a revoked collaboration session can start a writable local record',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final sessions = _SwitchingSessionProvider();
      final logs = LogProvider(
        sessionListLoader: () async => [
          _SwitchingSessionProvider.revokedSession,
          _SwitchingSessionProvider.localSession,
        ],
        sessionLogPageLoader: (_, __, ___) async => [],
      );
      final collaboration = CollaborationProvider();
      addTearDown(sessions.dispose);
      addTearDown(logs.dispose);
      addTearDown(collaboration.dispose);

      await logs.reloadForSession(
        _SwitchingSessionProvider.revokedSession.sessionId,
      );
      logs.setCollaborationReadOnly(
        _SwitchingSessionProvider.revokedSession.sessionId,
        true,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SessionProvider>.value(value: sessions),
            ChangeNotifierProvider<LogProvider>.value(value: logs),
            ChangeNotifierProvider<CollaborationProvider>.value(
              value: collaboration,
            ),
            ChangeNotifierProvider(
              create: (_) => DictionaryProvider(autoload: false),
            ),
            ChangeNotifierProvider(create: (_) => SettingsProvider()),
            ChangeNotifierProvider(create: (_) => SnackbarLogProvider()),
          ],
          child: const MaterialApp(
            locale: Locale('zh', 'CN'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: AddRecordPage()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(logs.currentSessionReadOnly, isTrue);
      final oldForm = tester.widget<LogForm>(find.byType(LogForm));
      expect(oldForm.readOnly, isTrue);
      expect(
        oldForm.key,
        const ValueKey('log-form-revoked-session'),
      );

      final startNewRecord = find.byKey(const Key('start-new-record'));
      expect(startNewRecord, findsOneWidget);
      expect(
        tester.widget<FilledButton>(startNewRecord).onPressed,
        isNotNull,
      );

      await tester.ensureVisible(startNewRecord);
      await tester.tap(startNewRecord);
      await tester.pumpAndSettle();

      final dialog = find.byType(AlertDialog);
      expect(dialog, findsOneWidget);
      final nameField = find.descendant(
        of: dialog,
        matching: find.byType(TextField),
      );
      expect(nameField, findsOneWidget);
      await tester.enterText(nameField, 'Monday net');

      final confirm = find.descendant(
        of: dialog,
        matching: find.byType(FilledButton),
      );
      expect(confirm, findsOneWidget);
      await tester.tap(confirm);
      await tester.pumpAndSettle();

      expect(sessions.startedTitles, ['Monday net']);
      expect(
        sessions.currentSessionId,
        _SwitchingSessionProvider.localSession.sessionId,
      );
      expect(
        logs.currentSessionId,
        _SwitchingSessionProvider.localSession.sessionId,
      );
      expect(logs.currentSessionReadOnly, isFalse);

      final newForm = tester.widget<LogForm>(find.byType(LogForm));
      expect(newForm.readOnly, isFalse);
      expect(
        newForm.key,
        const ValueKey('log-form-local-session'),
      );

      // The permission is scoped to the revoked session; creating a local
      // record must not erase that guard or spread it to the new session.
      await logs.reloadForSession(
        _SwitchingSessionProvider.revokedSession.sessionId,
      );
      expect(logs.currentSessionReadOnly, isTrue);
      await logs.reloadForSession(
        _SwitchingSessionProvider.localSession.sessionId,
      );
      expect(logs.currentSessionReadOnly, isFalse);
    },
  );
}

final class _SwitchingSessionProvider extends SessionProvider {
  _SwitchingSessionProvider() : _current = revokedSession;

  static const revokedSession = Session(
    sessionId: 'revoked-session',
    title: 'Revoked collaboration session',
    status: 'active',
    createdAt: '2026-07-13T10:00:00Z',
    updatedAt: '2026-07-13T10:00:00Z',
  );

  static const localSession = Session(
    sessionId: 'local-session',
    title: 'Monday net',
    status: 'active',
    createdAt: '2026-07-13T11:00:00Z',
    updatedAt: '2026-07-13T11:00:00Z',
  );

  Session _current;
  final List<String?> startedTitles = [];

  @override
  Future<void> get ready => Future<void>.value();

  @override
  String get currentSessionId => _current.sessionId;

  @override
  Session get currentSession => _current;

  @override
  Future<void> startNewSession({
    String? title,
    bool autoGenerated = false,
  }) async {
    startedTitles.add(title);
    _current = localSession;
    notifyListeners();
  }
}
