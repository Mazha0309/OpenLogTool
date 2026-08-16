import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/l10n/generated/app_localizations.dart';
import 'package:openlogtool/services/app_logger.dart';
import 'package:openlogtool/widgets/log_viewer_dialog.dart';

void main() {
  setUp(AppLogger.instance.resetForTest);
  tearDown(AppLogger.instance.resetForTest);

  testWidgets('filters structured persistent logs by level and search',
      (tester) async {
    AppLogger.instance.log(
      AppLogLevel.info,
      'session loaded',
      source: 'SessionProvider',
    );
    AppLogger.instance.log(
      AppLogLevel.error,
      'network request failed',
      source: 'ServerApi',
      error: StateError('offline'),
    );

    await tester.pumpWidget(_testApp());
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('session loaded'), findsOneWidget);
    expect(find.text('network request failed'), findsOneWidget);

    await tester.tap(find.byKey(const Key('log-level-info')));
    await tester.pump();
    expect(find.text('session loaded'), findsNothing);
    expect(find.text('network request failed'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('log-viewer-search')),
      'SessionProvider',
    );
    await tester.pump();
    expect(find.text('No logs match the current filters'), findsOneWidget);
  });

  testWidgets('clears the unified diagnostic log after confirmation',
      (tester) async {
    AppLogger.instance.info('one entry');
    await tester.pumpWidget(_testApp());
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('log-viewer-clear')));
    await tester.pumpAndSettle();
    expect(find.text('Clear diagnostic logs'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Clear'),
      ),
    );
    await tester.pumpAndSettle();

    expect(AppLogger.instance.snapshotEntries(), isEmpty);
    expect(find.text('No logs yet'), findsOneWidget);
  });
}

Widget _testApp() => MaterialApp(
      locale: const Locale('en', 'US'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const LogViewerDialog(),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
