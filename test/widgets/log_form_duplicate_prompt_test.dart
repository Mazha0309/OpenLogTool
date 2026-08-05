import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/models/log_entry.dart';
import 'package:openlogtool/providers/collaboration_provider.dart';
import 'package:openlogtool/providers/dictionary_provider.dart';
import 'package:openlogtool/providers/log_provider.dart';
import 'package:openlogtool/providers/session_provider.dart';
import 'package:openlogtool/providers/settings_provider.dart';
import 'package:openlogtool/widgets/callsign_history_field.dart';
import 'package:openlogtool/widgets/log_form.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(
      <String, Object>{'duplicateCallsignWarningEnabled': true},
    );
  });

  testWidgets('blurring the callsign with a duplicate shows update dialog',
      (tester) async {
    final logProvider = _StaticLogProvider([
      LogEntry(
        id: 'old-1',
        sessionId: 's1',
        time: '2026-07-13T12:00:00Z',
        controller: 'BG5CTRL',
        callsign: 'BA4AAA',
        report: '59',
        rstRcvd: '59',
        qth: '杭州',
        device: 'FT-991A',
        power: '50W',
        antenna: 'GP',
        height: '8m',
        createdAt: '2026-07-13T12:00:00Z',
        updatedAt: '2026-07-13T12:00:00Z',
      ),
    ]);
    addTearDown(logProvider.dispose);
    await tester.pumpWidget(_app(logProvider));
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
          of: find.byType(CallsignHistoryField),
          matching: find.byType(TextFormField)),
    );
    await tester.pump();
    await tester.enterText(
      find.descendant(
          of: find.byType(CallsignHistoryField),
          matching: find.byType(TextFormField)),
      'BA4AAA',
    );
    await tester.tap(find.byKey(const Key('outside-log-form')));
    await tester.pumpAndSettle();

    expect(find.text('呼号已记录过'), findsOneWidget);
    expect(find.text('更新旧记录'), findsOneWidget);
    expect(find.text('添加新记录'), findsOneWidget);
  });

  testWidgets('updating the old record keeps its time', (tester) async {
    final logProvider = _StaticLogProvider([
      LogEntry(
        id: 'old-1',
        sessionId: 's1',
        time: '2026-07-13T12:00:00Z',
        controller: 'BG5CTRL',
        callsign: 'BA4AAA',
        report: '59',
        rstRcvd: '59',
        qth: '杭州',
        device: 'FT-991A',
        power: '50W',
        antenna: 'GP',
        height: '8m',
        createdAt: '2026-07-13T12:00:00Z',
        updatedAt: '2026-07-13T12:00:00Z',
      ),
    ]);
    addTearDown(logProvider.dispose);
    await tester.pumpWidget(_app(logProvider));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'QTH'),
      '上海',
    );
    await tester.tap(
      find.descendant(
          of: find.byType(CallsignHistoryField),
          matching: find.byType(TextFormField)),
    );
    await tester.pump();
    await tester.enterText(
      find.descendant(
          of: find.byType(CallsignHistoryField),
          matching: find.byType(TextFormField)),
      'BA4AAA',
    );
    await tester.tap(find.byKey(const Key('outside-log-form')));
    await tester.pumpAndSettle();

    expect(find.text('呼号已记录过'), findsOneWidget);
    await tester.tap(find.byKey(const Key('duplicate-update-old-record')));
    await tester.pumpAndSettle();

    expect(logProvider.updateCalls, 1);
    final updated = logProvider.updatedLog!;
    expect(updated.callsign, 'BA4AAA');
    expect(updated.qth, '上海');
    expect(updated.time, '2026-07-13T12:00:00Z');
    expect(find.text('记录已更新'), findsOneWidget);
  });

  testWidgets('adding a new record does not touch the old one', (tester) async {
    final logProvider = _StaticLogProvider([
      LogEntry(
        id: 'old-1',
        sessionId: 's1',
        time: '2026-07-13T12:00:00Z',
        controller: 'BG5CTRL',
        callsign: 'BA4AAA',
        report: '59',
        rstRcvd: '59',
        qth: '杭州',
        device: '',
        power: '',
        antenna: '',
        height: '',
        createdAt: '2026-07-13T12:00:00Z',
        updatedAt: '2026-07-13T12:00:00Z',
      ),
    ]);
    addTearDown(logProvider.dispose);
    await tester.pumpWidget(_app(logProvider));
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
          of: find.byType(CallsignHistoryField),
          matching: find.byType(TextFormField)),
    );
    await tester.pump();
    await tester.enterText(
      find.descendant(
          of: find.byType(CallsignHistoryField),
          matching: find.byType(TextFormField)),
      'BA4AAA',
    );
    await tester.tap(find.byKey(const Key('outside-log-form')));
    await tester.pumpAndSettle();

    expect(find.text('呼号已记录过'), findsOneWidget);
    await tester.tap(find.text('添加新记录'));
    await tester.pumpAndSettle();

    expect(logProvider.updateCalls, 0);
    expect(find.text('呼号已记录过'), findsNothing);
  });
}

Widget _app(LogProvider logProvider) => MultiProvider(
      providers: [
        ChangeNotifierProvider<CollaborationProvider>(
          create: (_) => CollaborationProvider(),
        ),
        ChangeNotifierProvider<LogProvider>.value(value: logProvider),
        ChangeNotifierProvider<DictionaryProvider>(
          create: (_) => _NoopDictionaryProvider(),
        ),
        ChangeNotifierProvider(create: (_) => SessionProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Column(
            children: [
              const Expanded(
                child: SingleChildScrollView(
                  child: LogForm(),
                ),
              ),
              Container(
                key: const Key('outside-log-form'),
                width: double.infinity,
                height: 80,
                color: Colors.transparent,
              ),
            ],
          ),
        ),
      ),
    );

class _StaticLogProvider extends LogProvider {
  _StaticLogProvider(List<LogEntry> initialLogs) : _logs = initialLogs;

  final List<LogEntry> _logs;
  int updateCalls = 0;
  LogEntry? updatedLog;

  @override
  List<LogEntry> get logs => _logs;

  @override
  Future<void> updateLog(int index, LogEntry log) async {
    updateCalls += 1;
    updatedLog = log;
  }
}

class _NoopDictionaryProvider extends DictionaryProvider {
  _NoopDictionaryProvider() : super(autoload: false);

  @override
  Future<void> addDevice(String device) async {}

  @override
  Future<void> addAntenna(String antenna) async {}

  @override
  Future<void> addCallsign(String callsign) async {}

  @override
  Future<void> addQth(String qth) async {}
}
