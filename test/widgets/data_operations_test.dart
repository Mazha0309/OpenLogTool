import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/l10n/generated/app_localizations.dart';
import 'package:openlogtool/widgets/settings/data_operations.dart';

void main() {
  testWidgets('uses English localizations and blocks overlapping operations',
      (tester) async {
    final exportCompleter = Completer<void>();
    var importCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en', 'US'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: DataOperations(
              isNarrow: true,
              cardPadding: 12,
              onViewDatabaseLog: () async {},
              onExportDatabase: () => exportCompleter.future,
              onImportDatabase: () async => importCalls += 1,
              onViewSnackbarLog: () async {},
              onClearAllData: () async {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('On-device data'), findsOneWidget);
    expect(find.text('Backup & restore'), findsOneWidget);

    await tester.tap(find.byKey(const Key('database-operation-export')));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.tap(find.byKey(const Key('database-operation-import')));
    await tester.pump();
    expect(importCalls, 0);

    exportCompleter.complete();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
