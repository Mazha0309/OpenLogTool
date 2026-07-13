import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/l10n/generated/app_localizations.dart';
import 'package:openlogtool/models/collaboration_conflict.dart';
import 'package:openlogtool/widgets/collaboration_conflict_center.dart';

void main() {
  testWidgets('shows summaries and dispatches both conflict decisions',
      (tester) async {
    final decisions = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ListView(
            children: [
              CollaborationConflictCenter(
                conflicts: [_conflict()],
                loading: false,
                resolvingConflictId: null,
                enabled: true,
                onRefresh: () => decisions.add('refresh'),
                onAcceptRemote: (id) => decisions.add('remote:$id'),
                onKeepLocal: (id) => decisions.add('local:$id'),
                onCopyLocalAsNew: (id) => decisions.add('copy:$id'),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('冲突中心'), findsOneWidget);
    expect(find.textContaining('字段 remarks'), findsOneWidget);
    await tester.tap(find.textContaining('日志 · log-1'));
    await tester.pumpAndSettle();
    expect(find.textContaining('备注=base'), findsOneWidget);
    expect(find.textContaining('备注=local'), findsOneWidget);
    expect(find.textContaining('备注=remote'), findsOneWidget);

    await tester.tap(find.byKey(const Key('accept-remote-conflict-1')));
    await tester.tap(find.byKey(const Key('keep-local-conflict-1')));
    await tester.tap(find.byKey(const Key('refresh-conflicts')));
    expect(decisions, [
      'remote:conflict-1',
      'local:conflict-1',
      'refresh',
    ]);
  });

  testWidgets('renders only the resolutions advertised by Rust',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CollaborationConflictCenter(
            conflicts: [
              _conflict(
                allowedResolutions: const [
                  CollaborationConflictResolution.useRemote,
                ],
              ),
            ],
            loading: false,
            resolvingConflictId: null,
            enabled: true,
            onRefresh: () {},
            onAcceptRemote: (_) {},
            onKeepLocal: (_) {},
            onCopyLocalAsNew: (_) {},
          ),
        ),
      ),
    );
    await tester.tap(find.textContaining('日志 · log-1'));
    await tester.pumpAndSettle();

    final remote = tester.widget<OutlinedButton>(
      find.byKey(const Key('accept-remote-conflict-1')),
    );
    expect(remote.onPressed, isNotNull);
    expect(find.byKey(const Key('keep-local-conflict-1')), findsNothing);
    expect(find.byKey(const Key('copy-local-conflict-1')), findsNothing);
  });

  testWidgets('deletion-wins offers copy-as-new and hides keep-local',
      (tester) async {
    final decisions = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CollaborationConflictCenter(
            conflicts: [
              _conflict(
                allowedResolutions: const [
                  CollaborationConflictResolution.useRemote,
                  CollaborationConflictResolution.copyLocalAsNew,
                ],
              ),
            ],
            loading: false,
            resolvingConflictId: null,
            enabled: true,
            onRefresh: () {},
            onAcceptRemote: (_) {},
            onKeepLocal: (_) {},
            onCopyLocalAsNew: (id) => decisions.add('copy:$id'),
          ),
        ),
      ),
    );
    await tester.tap(find.textContaining('日志 · log-1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('keep-local-conflict-1')), findsNothing);
    expect(find.byKey(const Key('copy-local-conflict-1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('copy-local-conflict-1')));
    expect(decisions, ['copy:conflict-1']);
  });
}

CollaborationConflict _conflict({
  List<CollaborationConflictResolution> allowedResolutions = const [
    CollaborationConflictResolution.useRemote,
    CollaborationConflictResolution.keepLocal,
  ],
}) =>
    CollaborationConflict(
      conflictId: 'conflict-1',
      sessionId: 'session-1',
      entityType: CollaborationConflictEntityType.log,
      entityId: 'log-1',
      mutationId: 'mutation-1',
      baseVersion: 1,
      remoteVersion: 2,
      baseEntity: const {'callsign': 'BA4AAA', 'remarks': 'base', 'version': 1},
      localEntity: const {
        'callsign': 'BA4AAA',
        'remarks': 'local',
        'version': 1,
      },
      remoteEntity: const {
        'callsign': 'BA4AAA',
        'remarks': 'remote',
        'version': 2,
      },
      conflictingFields: const ['remarks'],
      allowedResolutions: allowedResolutions,
      createdAt: DateTime.utc(2026, 7, 12),
    );
