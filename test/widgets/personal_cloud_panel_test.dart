import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/providers/personal_cloud_provider.dart';
import 'package:openlogtool/widgets/personal_cloud_panel.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets(
      'signed-out panel explains availability without destructive actions',
      (tester) async {
    final cloud = PersonalCloudProvider(
      exporter: () async => '{"version":1,"sessions":[],"logs":[]}',
    );
    addTearDown(cloud.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: cloud,
        child: const MaterialApp(
          locale: Locale('en', 'US'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(child: PersonalCloudPanel()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('personal-cloud-panel')), findsOneWidget);
    expect(find.text('Personal cloud sync'), findsOneWidget);
    expect(
      find.text(
        'Sign in to automatically synchronize personal records and dictionary changes',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('separate realtime workflow'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('personal-cloud-sync-now')), findsNothing);
    expect(
      find.byKey(const Key('personal-cloud-replace-remote')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('personal-cloud-restore-local')),
      findsNothing,
    );
  });
}
