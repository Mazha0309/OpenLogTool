import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/models/database_status.dart';
import 'package:openlogtool/widgets/local_database_panel.dart';

void main() {
  testWidgets('shows semantic sections and keeps raw tables advanced',
      (tester) async {
    await tester.pumpWidget(_app(const Locale('zh', 'CN')));
    await tester.pumpAndSettle();

    expect(find.text('本机内容'), findsOneWidget);
    expect(find.text('协作状态'), findsOneWidget);
    expect(find.textContaining('进行中 1'), findsOneWidget);
    expect(find.text('615'), findsOneWidget);
    expect(find.text('本机仍有协作内容需要同步或处理'), findsOneWidget);
    expect(find.text('sync_outbox'), findsNothing);

    await tester.ensureVisible(
      find.byKey(const Key('database-status-advanced')),
    );
    await tester.tap(find.byKey(const Key('database-status-advanced')));
    await tester.pumpAndSettle();

    expect(find.text('sync_outbox'), findsOneWidget);
    expect(
      find.byKey(const Key('database-status-table-sync_outbox')),
      findsOneWidget,
    );
  });

  testWidgets('semantic status renders in en_US', (tester) async {
    await tester.pumpWidget(_app(const Locale('en', 'US')));
    await tester.pumpAndSettle();

    expect(find.text('On-device content'), findsOneWidget);
    expect(find.text('Collaboration state'), findsOneWidget);
    expect(find.text('Advanced: raw table counts'), findsOneWidget);
    expect(find.textContaining('1 active'), findsOneWidget);
  });
}

Widget _app(Locale locale) => MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: DatabaseStatusView(status: _status),
        ),
      ),
    );

final DatabaseStatus _status = DatabaseStatus.fromJson({
  'statusVersion': 2,
  'schemaVersion': 7,
  'backupFormatVersion': 7,
  'collectedAt': '2026-07-19T12:34:56Z',
  'localContent': {
    'sessions': {'active': 1, 'closed': 3, 'archived': 2, 'deleted': 1},
    'logs': {'active': 615, 'deleted': 4},
    'dictionaries': {
      'device': {'active': 304, 'deleted': 2},
    },
  },
  'collaboration': {
    'bindings': 2,
    'pendingOutbox': 1,
    'openConflicts': 0,
    'offlineRecords': 0,
    'draftCaches': 1,
  },
  'tables': [
    {'name': 'sync_outbox', 'rowCount': 0},
  ],
});
