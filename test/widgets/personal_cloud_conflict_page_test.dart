import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/providers/personal_cloud_provider.dart';
import 'package:openlogtool/utils/personal_cloud_merge.dart';
import 'package:openlogtool/widgets/personal_cloud_conflict_page.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('requires an explicit decision for every cloud conflict',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final cloud = _ConflictCloudProvider();
    addTearDown(cloud.dispose);
    var openedDatabase = false;
    await tester.pumpWidget(
      ChangeNotifierProvider<PersonalCloudProvider>.value(
        value: cloud,
        child: MaterialApp(
          locale: const Locale('en', 'US'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: PersonalCloudConflictPage(
              onOpenDatabase: () => openedDatabase = true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Personal cloud conflicts'), findsOneWidget);
    expect(find.text('Selected 0 of 2; choose every item before applying.'),
        findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('personal-cloud-conflict-apply')),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(
        find.byKey(const Key('conflict-local-records:log:log-1:controller')));
    await tester.pump();
    expect(find.text('Selected 1 of 2; choose every item before applying.'),
        findsOneWidget);

    await tester.tap(
      find.byKey(
        const Key(
          'conflict-remote-dictionaries:dictionaryItem:qth_dictionary\u0000Hangzhou:state',
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Selected 2 of 2; choose every item before applying.'),
        findsOneWidget);

    final apply = find.byKey(const Key('personal-cloud-conflict-apply'));
    await tester.ensureVisible(apply);
    expect(tester.widget<FilledButton>(apply).onPressed, isNotNull);
    await tester.tap(apply);
    await tester.pumpAndSettle();

    expect(
      cloud.appliedChoices,
      {
        'records:log:log-1:controller': PersonalCloudConflictChoice.local,
        'dictionaries:dictionaryItem:qth_dictionary\u0000Hangzhou:state':
            PersonalCloudConflictChoice.remote,
      },
    );
    expect(
        find.byKey(const Key('personal-cloud-no-conflicts')), findsOneWidget);

    await tester.tap(find.byKey(const Key('personal-cloud-open-database')));
    expect(openedDatabase, isTrue);
  });
}

final class _ConflictCloudProvider extends PersonalCloudProvider {
  _ConflictCloudProvider()
      : super(
          exporter: () async => '{"version":1,"sessions":[],"logs":[]}',
        );

  List<PersonalCloudMergeConflict> _visibleConflicts = const [
    PersonalCloudMergeConflict(
      dataset: PersonalCloudDataset.records,
      conflictId: 'records:log:log-1:controller',
      entityType: 'log',
      entityId: 'log-1',
      sessionId: 'session-1',
      kind: 'concurrentEdit',
      fieldGroup: 'controller',
      basePresent: true,
      localPresent: true,
      remotePresent: true,
      baseValue: 'BG5AAA',
      localValue: 'BG5BBB',
      remoteValue: 'BG5CCC',
    ),
    PersonalCloudMergeConflict(
      dataset: PersonalCloudDataset.dictionaries,
      conflictId:
          'dictionaries:dictionaryItem:qth_dictionary\u0000Hangzhou:state',
      entityType: 'dictionaryItem',
      entityId: 'qth_dictionary\u0000Hangzhou',
      kind: 'concurrentEdit',
      fieldGroup: 'state',
      basePresent: true,
      localPresent: true,
      remotePresent: true,
      baseValue: {'state': 'active'},
      localValue: {'state': 'deleted'},
      remoteValue: {'state': 'active'},
    ),
  ];

  Map<String, PersonalCloudConflictChoice>? appliedChoices;

  @override
  PersonalCloudSyncState get state => _visibleConflicts.isEmpty
      ? PersonalCloudSyncState.upToDate
      : PersonalCloudSyncState.decisionRequired;

  @override
  List<PersonalCloudMergeConflict> get conflicts =>
      List.unmodifiable(_visibleConflicts);

  @override
  bool get hasPendingMerge => _visibleConflicts.isNotEmpty;

  @override
  Future<void> resolvePendingConflicts(
    Map<String, PersonalCloudConflictChoice> resolutions,
  ) async {
    appliedChoices = Map<String, PersonalCloudConflictChoice>.from(resolutions);
    _visibleConflicts = const [];
    notifyListeners();
  }
}
