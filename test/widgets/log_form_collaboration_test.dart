import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/models/live_draft.dart';
import 'package:openlogtool/providers/collaboration_provider.dart';
import 'package:openlogtool/providers/dictionary_provider.dart';
import 'package:openlogtool/providers/settings_provider.dart';
import 'package:openlogtool/src/bridge/models/log_entry.dart' as bridge;
import 'package:openlogtool/widgets/callsign_history_field.dart';
import 'package:openlogtool/widgets/log_form.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'collaboration history reuse is atomic and an outside tap releases focus',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final collaboration = _RecordingCollaborationProvider();
      final reuseGate = Completer<void>();
      collaboration.atomicGate = reuseGate;
      addTearDown(collaboration.dispose);
      try {
        tester.view.physicalSize = const Size(600, 960);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_LogFormTestApp(collaboration: collaboration));
        await tester.pumpAndSettle();

        final historyField = tester.widget<CallsignHistoryField>(
          find.byType(CallsignHistoryField),
        );
        final reuse = historyField.onReuseRecord!(_historyRecord);
        await tester.pump();

        expect(
          tester
              .widget<AbsorbPointer>(
                find.byKey(const Key('history-reuse-guard')),
              )
              .absorbing,
          isTrue,
        );
        reuseGate.complete();
        await reuse;
        await tester.pump();

        expect(collaboration.atomicUpdates, hasLength(1));
        expect(collaboration.atomicUpdates.single, {
          'device': 'IC-7300',
          'antenna': 'DP',
          'qth': 'Shanghai',
          'power': '100W',
          'height': '12m',
          'rstSent': '58',
          'rstRcvd': '47',
          'controller': 'BG5CRL',
        });
        expect(collaboration.atomicUpdates.single, isNot(contains('time')));
        collaboration.acquiredFields.clear();
        collaboration.releasedFields.clear();

        final callsignEditableFinder = find.descendant(
          of: find.byType(CallsignHistoryField),
          matching: find.byType(EditableText),
        );
        final callsignEditable =
            tester.widget<EditableText>(callsignEditableFinder);
        await tester.tap(callsignEditableFinder);
        await tester.pump();
        expect(collaboration.acquiredFields, ['callsign']);

        final outside = tester.getCenter(
          find.byKey(const Key('outside-log-form')),
        );
        await tester.tapAt(
          outside,
          kind: PointerDeviceKind.touch,
        );
        await tester.pump();
        await tester.pump();

        expect(callsignEditable.focusNode.hasFocus, isFalse);
        expect(collaboration.releasedFields, ['callsign']);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}

const _historyRecord = bridge.LogEntry(
  syncId: 'history-1',
  sessionId: 'session-1',
  time: '2026-07-12T08:15:00Z',
  controller: 'BG5CRL',
  callsign: 'BA4AAA',
  rstSent: '58',
  rstRcvd: '47',
  qth: 'Shanghai',
  device: 'IC-7300',
  power: '100W',
  antenna: 'DP',
  height: '12m',
  createdAt: '2026-07-12T08:15:00Z',
  updatedAt: '2026-07-12T08:15:00Z',
);

class _LogFormTestApp extends StatelessWidget {
  const _LogFormTestApp({required this.collaboration});

  final CollaborationProvider collaboration;

  @override
  Widget build(BuildContext context) => MultiProvider(
        providers: [
          ChangeNotifierProvider<CollaborationProvider>.value(
            value: collaboration,
          ),
          ChangeNotifierProvider(
            create: (_) => DictionaryProvider(autoload: false),
          ),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ],
        child: MaterialApp(
          locale: const Locale('en', 'US'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Column(
              children: [
                const Expanded(
                  child: SingleChildScrollView(child: LogForm()),
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
}

class _RecordingCollaborationProvider extends CollaborationProvider {
  _RecordingCollaborationProvider()
      : _snapshot = LiveDraftSnapshotDto(
          draft: LiveDraftDto(
            draftId: 'draft-1',
            sessionId: 'session-1',
            version: 1,
            fields: LiveDraftFieldsDto({
              'time': '12:34',
              'rstSent': '59',
              'rstRcvd': '59',
            }),
            fieldRevisions: {
              for (final field in liveDraftFieldNames) field: 0,
            },
            lastUpdatedBy: null,
            createdAt: DateTime.utc(2026, 7, 13),
            lastUpdatedAt: DateTime.utc(2026, 7, 13),
          ),
          locks: const [],
          currentOrdinal: 1,
          totalRecords: 0,
          previousRecord: null,
        );

  final LiveDraftSnapshotDto _snapshot;
  final List<Map<String, String>> atomicUpdates = [];
  final List<String> acquiredFields = [];
  final List<String> releasedFields = [];
  final Map<String, LiveDraftLockDto> _ownedLocks = {};
  Completer<void>? atomicGate;

  @override
  LiveDraftSnapshotDto get liveDraftSnapshot => _snapshot;

  @override
  LiveDraftFieldsDto get liveDraftFields => _snapshot.draft.fields;

  @override
  bool get canEditLiveDraft => true;

  @override
  List<LiveDraftLockDto> get liveDraftLocks => const [];

  @override
  Map<String, LiveDraftLockDto> get ownedLiveDraftLocks =>
      Map.unmodifiable(_ownedLocks);

  @override
  LiveDraftLockDto? lockForField(String field) => null;

  @override
  bool fieldLockedByAnotherUser(String field) => false;

  @override
  Future<LiveDraftLockDto> acquireLiveDraftField(String field) async {
    acquiredFields.add(field);
    final lock = LiveDraftLockDto(
      leaseId: 'lease-$field',
      sessionId: 'session-1',
      field: field,
      userId: 'user-1',
      username: 'tester',
      deviceId: 'device-1',
      expiresAt: DateTime.now().add(const Duration(minutes: 1)),
    );
    _ownedLocks[field] = lock;
    return lock;
  }

  @override
  Future<void> releaseLiveDraftField(String field) async {
    releasedFields.add(field);
    _ownedLocks.remove(field);
  }

  @override
  Future<void> updateLiveDraftField(String field, String value) async {}

  @override
  Future<void> updateLiveDraftFieldsAtomically(
    Map<String, String> updates,
  ) async {
    atomicUpdates.add(Map<String, String>.from(updates));
    await atomicGate?.future;
  }
}
