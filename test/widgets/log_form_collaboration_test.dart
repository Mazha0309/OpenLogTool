import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/models/collaboration_dto.dart';
import 'package:openlogtool/models/live_draft.dart';
import 'package:openlogtool/providers/collaboration_provider.dart';
import 'package:openlogtool/providers/dictionary_provider.dart';
import 'package:openlogtool/providers/log_provider.dart';
import 'package:openlogtool/providers/session_provider.dart';
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

  for (final locale in const <Locale>[
    Locale('zh', 'CN'),
    Locale('en', 'US'),
  ]) {
    testWidgets('${locale.toLanguageTag()} localizes workbench form fields',
        (tester) async {
      final collaboration = _RecordingCollaborationProvider();
      addTearDown(collaboration.dispose);
      final isEnglish = locale.languageCode == 'en';

      await tester.pumpWidget(
        _LogFormTestApp(
          collaboration: collaboration,
          locale: locale,
        ),
      );
      await tester.pumpAndSettle();

      final decorations = tester
          .widgetList<TextField>(find.byType(TextField))
          .map((field) => field.decoration!)
          .toList(growable: false);
      expect(
        decorations.map((decoration) => decoration.labelText),
        containsAll(
          isEnglish
              ? const <String>[
                  'Controller callsign *',
                  'Callsign',
                  'Radio',
                  'Antenna',
                  'Power',
                  'QTH',
                  'Height',
                  'Time',
                  'RST sent',
                  'RST received',
                  'Remarks',
                ]
              : const <String>[
                  '主控呼号 *',
                  '来台呼号',
                  '设备',
                  '天线',
                  '功率',
                  'QTH',
                  '高度',
                  '时间',
                  'RST 发',
                  'RST 收',
                  '备注',
                ],
        ),
      );
      final controllerDecoration = decorations.singleWhere(
        (decoration) =>
            decoration.labelText ==
            (isEnglish ? 'Controller callsign *' : '主控呼号 *'),
      );
      final remarksDecoration = decorations.singleWhere(
        (decoration) => decoration.labelText == (isEnglish ? 'Remarks' : '备注'),
      );
      expect(
        controllerDecoration.hintText,
        isEnglish ? 'Enter Controller callsign' : '输入主控呼号',
      );
      expect(
        remarksDecoration.hintText,
        isEnglish ? 'Remarks (optional)' : '备注（可选）',
      );
      expect(
        find.text(isEnglish ? 'Clear fields' : '清空已填内容'),
        findsOneWidget,
      );
      expect(
        tester.getSize(find.byKey(const Key('clear-log-fields'))).width,
        lessThanOrEqualTo(180),
      );
      final actionsWidth =
          tester.getSize(find.byKey(const Key('log-form-actions'))).width;
      final clearWidth =
          tester.getSize(find.byKey(const Key('clear-log-fields'))).width;
      final saveWidth =
          tester.getSize(find.byKey(const Key('save-log-record'))).width;
      expect(clearWidth + 8 + saveWidth, closeTo(actionsWidth, 0.1));

      tester
          .widget<FilledButton>(find.byKey(const Key('save-log-record')))
          .onPressed!();
      await tester.pump();

      expect(
        find.text(isEnglish ? 'This field is required' : '此项不能为空'),
        findsOneWidget,
      );
      expect(
        find.text(isEnglish ? 'Enter a callsign' : '请输入点名呼号'),
        findsOneWidget,
      );
    });
  }

  for (final shortcut in <String, LogicalKeyboardKey>{
    'Ctrl+Enter': LogicalKeyboardKey.controlLeft,
    'Meta+Enter': LogicalKeyboardKey.metaLeft,
  }.entries) {
    testWidgets('${shortcut.key} saves a valid form', (tester) async {
      final collaboration = _RecordingCollaborationProvider(
        initialFields: const {
          'time': '',
          'controller': 'BG5CRL',
          'callsign': 'BA4AAA',
          'rstSent': '59',
          'rstRcvd': '59',
        },
      );
      addTearDown(collaboration.dispose);

      await tester.pumpWidget(_LogFormTestApp(collaboration: collaboration));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Ctrl/⌘ + Enter'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(CallsignHistoryField),
          matching: find.byType(EditableText),
        ),
      );
      await tester.pump();
      await _sendSaveShortcut(tester, shortcut.value);
      await tester.pumpAndSettle();

      expect(collaboration.commitCalls, 1);
    });
  }

  testWidgets(
    'clear fields keeps the controller callsign and updates collaboration atomically',
    (tester) async {
      final collaboration = _RecordingCollaborationProvider(
        initialTimeRevision: 1,
        initialFields: const {
          'time': '12:34',
          'controller': 'BG5CRL',
          'callsign': 'BA4AAA',
          'rstSent': '58',
          'rstRcvd': '47',
          'qth': 'Shanghai',
          'device': 'IC-7300',
          'power': '100W',
          'antenna': 'DP',
          'height': '12m',
          'remarks': 'portable',
        },
      );
      addTearDown(collaboration.dispose);

      await tester.pumpWidget(_LogFormTestApp(collaboration: collaboration));
      await tester.pumpAndSettle();

      TextEditingController controllerFor(String label) => tester
          .widget<TextFormField>(
            find.ancestor(
              of: find.text(label),
              matching: find.byType(TextFormField),
            ),
          )
          .controller!;

      await tester.tap(find.byKey(const Key('clear-log-fields')));
      await tester.pumpAndSettle();

      expect(collaboration.atomicUpdates, hasLength(1));
      expect(collaboration.atomicUpdates.single, {
        'time': '',
        'callsign': '',
        'rstSent': '59',
        'rstRcvd': '59',
        'qth': '',
        'device': '',
        'power': '',
        'antenna': '',
        'height': '',
        'remarks': '',
      });
      expect(collaboration.atomicUpdates.single, isNot(contains('controller')));
      expect(controllerFor('Controller callsign *').text, 'BG5CRL');
      for (final label in const <String>[
        'Callsign',
        'Radio',
        'Antenna',
        'Power',
        'QTH',
        'Height',
        'Time',
        'Remarks',
      ]) {
        expect(controllerFor(label).text, isEmpty, reason: label);
      }
      expect(controllerFor('RST sent').text, '59');
      expect(controllerFor('RST received').text, '59');
      expect(
        find.text('Fields cleared; controller callsign retained'),
        findsOneWidget,
      );
    },
  );

  testWidgets('clear fields also works locally without clearing controller',
      (tester) async {
    final collaboration = _LocalOnlyCollaborationProvider();
    addTearDown(collaboration.dispose);

    await tester.pumpWidget(_LogFormTestApp(collaboration: collaboration));
    await tester.pumpAndSettle();

    TextEditingController controllerFor(String label) => tester
        .widget<TextFormField>(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(TextFormField),
          ),
        )
        .controller!;

    controllerFor('Controller callsign *').text = 'BG5CRL';
    controllerFor('Callsign').text = 'BA4AAA';
    controllerFor('Remarks').text = 'portable';
    await tester.pump();
    await tester.tap(find.byKey(const Key('clear-log-fields')));
    await tester.pumpAndSettle();

    expect(controllerFor('Controller callsign *').text, 'BG5CRL');
    expect(controllerFor('Callsign').text, isEmpty);
    expect(controllerFor('RST sent').text, '59');
    expect(controllerFor('RST received').text, '59');
    expect(controllerFor('Remarks').text, isEmpty);
  });

  testWidgets('save shortcut keeps invalid and read-only forms blocked',
      (tester) async {
    final invalidCollaboration = _RecordingCollaborationProvider();
    addTearDown(invalidCollaboration.dispose);
    await tester.pumpWidget(
      _LogFormTestApp(collaboration: invalidCollaboration),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(EditableText).first);
    await tester.pump();
    await _sendSaveShortcut(tester, LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(invalidCollaboration.commitCalls, 0);

    final readOnlyCollaboration = _RecordingCollaborationProvider(
      initialFields: const {
        'controller': 'BG5CRL',
        'callsign': 'BA4AAA',
      },
    );
    addTearDown(readOnlyCollaboration.dispose);
    await tester.pumpWidget(
      _LogFormTestApp(
        collaboration: readOnlyCollaboration,
        readOnly: true,
      ),
    );
    await tester.pumpAndSettle();

    final shortcuts =
        tester.widget<CallbackShortcuts>(find.byType(CallbackShortcuts));
    shortcuts.bindings[
        const SingleActivator(LogicalKeyboardKey.enter, meta: true)]!();
    await tester.pump();
    expect(readOnlyCollaboration.commitCalls, 0);
  });

  testWidgets('rapid save shortcuts only start one submission', (tester) async {
    final collaboration = _RecordingCollaborationProvider(
      initialFields: const {
        'time': '',
        'controller': 'BG5CRL',
        'callsign': 'BA4AAA',
        'rstSent': '59',
        'rstRcvd': '59',
      },
    );
    final gate = Completer<void>();
    collaboration.commitGate = gate;
    addTearDown(collaboration.dispose);
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });

    await tester.pumpWidget(_LogFormTestApp(collaboration: collaboration));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(CallsignHistoryField),
        matching: find.byType(EditableText),
      ),
    );
    await tester.pump();

    await _sendSaveShortcut(tester, LogicalKeyboardKey.controlLeft);
    await _sendSaveShortcut(tester, LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(collaboration.commitCalls, 1);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('save-log-record')))
          .onPressed,
      isNull,
    );

    gate.complete();
    await tester.pumpAndSettle();
    expect(collaboration.commitCalls, 1);
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
        });
        expect(collaboration.atomicUpdates.single, isNot(contains('time')));
        expect(collaboration.atomicUpdates.single, isNot(contains('rstSent')));
        expect(collaboration.atomicUpdates.single, isNot(contains('rstRcvd')));
        expect(
          collaboration.atomicUpdates.single,
          isNot(contains('controller')),
        );
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

  testWidgets(
    'saving a blank time records it without prefilling the next record',
    (tester) async {
      final collaboration = _RecordingCollaborationProvider(
        initialFields: const {
          'time': '',
          'controller': 'BG5CRL',
          'callsign': 'BA4AAA',
          'rstSent': '59',
          'rstRcvd': '59',
        },
      );
      addTearDown(collaboration.dispose);

      await tester.pumpWidget(_LogFormTestApp(collaboration: collaboration));
      await tester.pumpAndSettle();

      TextEditingController timeController() => tester
          .widget<TextFormField>(find.byKey(const Key('log-time-field')))
          .controller!;

      expect(timeController().text, isEmpty);
      final save = find.byKey(const Key('save-log-record'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(collaboration.committedFields, isNotNull);
      _expectCanonicalUtcTimestamp(collaboration.committedFields!['time']!);
      expect(collaboration.liveDraftFields['time'], isEmpty);
      expect(timeController().text, isEmpty);
    },
  );

  testWidgets(
    'generated time stays hidden after rebuilding the form while save is pending',
    (tester) async {
      final collaboration = _RecordingCollaborationProvider(
        initialFields: const {
          'time': '',
          'controller': 'BG5CRL',
          'callsign': 'BA4AAA',
          'rstSent': '59',
          'rstRcvd': '59',
        },
      );
      final gate = Completer<void>();
      collaboration.commitGate = gate;
      addTearDown(collaboration.dispose);
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });

      await tester.pumpWidget(
        _LogFormTestApp(
          collaboration: collaboration,
          logFormKey: const ValueKey('before-save'),
        ),
      );
      await tester.pumpAndSettle();

      final originalTimeController = tester
          .widget<TextFormField>(find.byKey(const Key('log-time-field')))
          .controller!;
      await tester.tap(find.byKey(const Key('save-log-record')));
      await tester.pump();

      expect(collaboration.commitCalls, 1);
      expect(collaboration.liveDraftFields['time'], isNotEmpty);
      expect(collaboration.liveDraftDisplayFields!['time'], isEmpty);
      expect(originalTimeController.text, isEmpty);

      await tester.pumpWidget(
        _LogFormTestApp(
          collaboration: collaboration,
          logFormKey: const ValueKey('while-save-pending'),
        ),
      );
      await tester.pump();

      final rebuiltTimeController = tester
          .widget<TextFormField>(find.byKey(const Key('log-time-field')))
          .controller!;
      expect(rebuiltTimeController, isNot(same(originalTimeController)));
      expect(rebuiltTimeController.text, isEmpty);

      gate.complete();
      await tester.pumpAndSettle();
      expect(rebuiltTimeController.text, isEmpty);
    },
  );

  testWidgets(
    'legacy next-draft default time stays hidden after commit',
    (tester) async {
      const legacyDefaultTime = '2026-07-14T08:00:00.000Z';
      final collaboration = _RecordingCollaborationProvider(
        initialFields: const {
          'time': '',
          'controller': 'BG5CRL',
          'callsign': 'BA4AAA',
          'rstSent': '59',
          'rstRcvd': '59',
        },
        nextDraftTime: legacyDefaultTime,
        nextDraftTimeRevision: 0,
      );
      addTearDown(collaboration.dispose);

      await tester.pumpWidget(
        _LogFormTestApp(
          collaboration: collaboration,
          logFormKey: const ValueKey('before-legacy-commit'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('save-log-record')));
      await tester.pumpAndSettle();

      expect(collaboration.liveDraftFields['time'], legacyDefaultTime);
      expect(
        collaboration.liveDraftSnapshot.draft.fieldRevisions['time'],
        0,
      );
      expect(collaboration.liveDraftDisplayFields!['time'], isEmpty);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('log-time-field')))
            .controller!
            .text,
        isEmpty,
      );

      await tester.pumpWidget(
        _LogFormTestApp(
          collaboration: collaboration,
          logFormKey: const ValueKey('after-legacy-commit'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('log-time-field')))
            .controller!
            .text,
        isEmpty,
      );
    },
  );

  testWidgets(
    'a failed save does not copy its generated time into the input',
    (tester) async {
      final collaboration = _RecordingCollaborationProvider(
        initialFields: const {
          'time': '',
          'controller': 'BG5CRL',
          'callsign': 'BA4AAA',
          'rstSent': '59',
          'rstRcvd': '59',
        },
      )..commitError = StateError('commit failed');
      addTearDown(collaboration.dispose);

      await tester.pumpWidget(_LogFormTestApp(collaboration: collaboration));
      await tester.pumpAndSettle();

      final time = tester
          .widget<TextFormField>(find.byKey(const Key('log-time-field')))
          .controller!;
      tester
          .widget<FilledButton>(find.byKey(const Key('save-log-record')))
          .onPressed!();
      await tester.pump();

      expect(
          find.text('Action failed: Bad state: commit failed'), findsOneWidget);
      expect(collaboration.liveDraftFields['time'], isNotEmpty);
      expect(time.text, isEmpty);

      collaboration.replaceDraftField('time', '18:45');
      await tester.pump();
      expect(time.text, '18:45');
    },
  );

  testWidgets(
    'an offline queued save leaves the same draft time input empty',
    (tester) async {
      final collaboration = _RecordingCollaborationProvider(
        initialFields: const {
          'time': '',
          'controller': 'BG5CRL',
          'callsign': 'BA4AAA',
          'rstSent': '59',
          'rstRcvd': '59',
        },
      )..commitDisposition = LiveDraftCommitDisposition.queuedOffline;
      addTearDown(collaboration.dispose);

      await tester.pumpWidget(_LogFormTestApp(collaboration: collaboration));
      await tester.pumpAndSettle();

      final time = tester
          .widget<TextFormField>(find.byKey(const Key('log-time-field')))
          .controller!;
      await tester.tap(find.byKey(const Key('save-log-record')));
      await tester.pumpAndSettle();

      _expectCanonicalUtcTimestamp(collaboration.committedFields!['time']!);
      expect(collaboration.liveDraftSnapshot.draft.draftId, 'draft-1');
      expect(collaboration.liveDraftFields['time'], isEmpty);
      expect(time.text, isEmpty);
    },
  );

  testWidgets('rapid save taps only start one submission', (tester) async {
    final collaboration = _RecordingCollaborationProvider(
      initialFields: const {
        'time': '',
        'controller': 'BG5CRL',
        'callsign': 'BA4AAA',
        'rstSent': '59',
        'rstRcvd': '59',
      },
    );
    final gate = Completer<void>();
    collaboration.commitGate = gate;
    addTearDown(collaboration.dispose);

    await tester.pumpWidget(_LogFormTestApp(collaboration: collaboration));
    await tester.pumpAndSettle();

    final save = find.byKey(const Key('save-log-record'));
    await tester.tap(save);
    await tester.tap(save);
    await tester.pump();

    expect(collaboration.commitCalls, 1);
    expect(tester.widget<FilledButton>(save).onPressed, isNull);

    gate.complete();
    await tester.pumpAndSettle();
    expect(collaboration.commitCalls, 1);
  });

  testWidgets(
    'IME composition is neither synchronized nor remotely overwritten and save commits uppercase',
    (tester) async {
      final collaboration = _RecordingCollaborationProvider(
        initialFields: const {
          'time': '',
          'controller': 'REMOTE-CONTROLLER',
          'callsign': 'REMOTE-CALLSIGN',
          'rstSent': '59',
          'rstRcvd': '59',
        },
      );
      addTearDown(collaboration.dispose);

      await tester.pumpWidget(_LogFormTestApp(collaboration: collaboration));
      await tester.pumpAndSettle();

      final controller = tester
          .widgetList<TextField>(find.byType(TextField))
          .singleWhere(
            (field) => field.decoration?.labelText == 'Controller callsign *',
          )
          .controller!;
      final callsign = tester
          .widget<CallsignHistoryField>(find.byType(CallsignHistoryField))
          .callsignController;
      controller.value = const TextEditingValue(
        text: 'bg5crl',
        selection: TextSelection.collapsed(offset: 6),
        composing: TextRange(start: 0, end: 6),
      );
      callsign.value = const TextEditingValue(
        text: 'ba4aaa',
        selection: TextSelection.collapsed(offset: 6),
        composing: TextRange(start: 0, end: 6),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(collaboration.liveDraftFields['controller'], 'REMOTE-CONTROLLER');
      expect(collaboration.liveDraftFields['callsign'], 'REMOTE-CALLSIGN');

      collaboration.replaceDraft(
        draftId: 'remote-draft',
        fields: const {
          'time': '',
          'controller': 'NEW-REMOTE-CONTROLLER',
          'callsign': 'NEW-REMOTE-CALLSIGN',
          'rstSent': '59',
          'rstRcvd': '59',
        },
      );
      await tester.pump();
      expect(controller.text, 'bg5crl');
      expect(callsign.text, 'ba4aaa');

      await tester.tap(find.byKey(const Key('save-log-record')));
      await tester.pumpAndSettle();

      expect(collaboration.committedFields!['controller'], 'BG5CRL');
      expect(collaboration.committedFields!['callsign'], 'BA4AAA');
      _expectCanonicalUtcTimestamp(collaboration.committedFields!['time']!);
    },
  );

  testWidgets(
    'a new remote draft replaces generated time while save is pending',
    (tester) async {
      final collaboration = _RecordingCollaborationProvider(
        initialFields: const {
          'time': '',
          'controller': 'BG5CRL',
          'callsign': 'BA4AAA',
          'rstSent': '59',
          'rstRcvd': '59',
        },
      );
      final gate = Completer<void>();
      collaboration.commitGate = gate;
      addTearDown(collaboration.dispose);

      await tester.pumpWidget(_LogFormTestApp(collaboration: collaboration));
      await tester.pumpAndSettle();

      final time = tester
          .widget<TextFormField>(find.byKey(const Key('log-time-field')))
          .controller!;
      await tester.tap(find.byKey(const Key('save-log-record')));
      await tester.pump();
      expect(collaboration.commitCalls, 1);

      collaboration.replaceDraft(
        draftId: 'remote-draft',
        fields: const {
          'time': '18:45',
          'controller': 'BG5CRL',
          'callsign': 'BA4BBB',
          'rstSent': '59',
          'rstRcvd': '59',
        },
      );
      await tester.pump();
      expect(time.text, '18:45');

      gate.complete();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'a focused shared field defers a remote replacement until editing ends',
    (tester) async {
      final collaboration = _RecordingCollaborationProvider();
      collaboration.fieldUpdateError = StateError('field conflict');
      addTearDown(collaboration.dispose);

      await tester.pumpWidget(_LogFormTestApp(collaboration: collaboration));
      await tester.pumpAndSettle();

      final callsignEditableFinder = find.descendant(
        of: find.byType(CallsignHistoryField),
        matching: find.byType(EditableText),
      );
      await tester.tap(callsignEditableFinder);
      await tester.enterText(callsignEditableFinder, 'LOCAL');
      await tester.pump(const Duration(milliseconds: 50));

      collaboration.replaceDraftField('callsign', 'REMOTE');
      await tester.pump();
      expect(
        tester.widget<EditableText>(callsignEditableFinder).controller.text,
        'LOCAL',
      );

      await tester.tap(find.byKey(const Key('outside-log-form')));
      await tester.pump();
      await tester.pump();

      expect(
        tester.widget<EditableText>(callsignEditableFinder).controller.text,
        'REMOTE',
      );
      await tester.pump(const Duration(milliseconds: 350));
    },
  );

  testWidgets(
    'a focused non-callsign field defers a remote replacement until editing ends',
    (tester) async {
      final collaboration = _RecordingCollaborationProvider();
      collaboration.fieldUpdateError = StateError('field conflict');
      addTearDown(collaboration.dispose);

      await tester.pumpWidget(_LogFormTestApp(collaboration: collaboration));
      await tester.pumpAndSettle();

      final remarksField = find.ancestor(
        of: find.text('Remarks'),
        matching: find.byType(TextFormField),
      );
      expect(remarksField, findsOneWidget);
      final remarksEditable = find.descendant(
        of: remarksField,
        matching: find.byType(EditableText),
      );
      expect(remarksEditable, findsOneWidget);

      await tester.tap(remarksEditable);
      await tester.enterText(remarksEditable, 'LOCAL REMARKS');
      await tester.pump(const Duration(milliseconds: 50));

      collaboration.replaceDraftField('remarks', 'REMOTE REMARKS');
      await tester.pump();
      expect(
        tester.widget<EditableText>(remarksEditable).controller.text,
        'LOCAL REMARKS',
      );

      await tester.tap(find.byKey(const Key('outside-log-form')));
      await tester.pump();
      await tester.pump();

      expect(
        tester.widget<EditableText>(remarksEditable).controller.text,
        'REMOTE REMARKS',
      );
      await tester.pump(const Duration(milliseconds: 350));
    },
  );
}

void _expectCanonicalUtcTimestamp(String value) {
  expect(
    value,
    matches(
      r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$',
    ),
  );
  expect(DateTime.parse(value).isUtc, isTrue);
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

Future<void> _sendSaveShortcut(
  WidgetTester tester,
  LogicalKeyboardKey modifier,
) async {
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
  await tester.sendKeyUpEvent(modifier);
}

class _LogFormTestApp extends StatelessWidget {
  const _LogFormTestApp({
    required this.collaboration,
    this.logFormKey,
    this.readOnly = false,
    this.locale = const Locale('en', 'US'),
  });

  final CollaborationProvider collaboration;
  final Key? logFormKey;
  final bool readOnly;
  final Locale locale;

  @override
  Widget build(BuildContext context) => MultiProvider(
        providers: [
          ChangeNotifierProvider<CollaborationProvider>.value(
            value: collaboration,
          ),
          ChangeNotifierProvider<DictionaryProvider>(
            create: (_) => _NoopDictionaryProvider(),
          ),
          ChangeNotifierProvider(
            create: (_) => LogProvider(
              sessionListLoader: () async => [],
              sessionLogPageLoader: (_, __, ___) async => [],
            ),
          ),
          ChangeNotifierProvider(create: (_) => SessionProvider()),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ],
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: LogForm(key: logFormKey, readOnly: readOnly),
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
}

class _RecordingCollaborationProvider extends CollaborationProvider {
  _RecordingCollaborationProvider({
    Map<String, String> initialFields = const {
      'time': '12:34',
      'rstSent': '59',
      'rstRcvd': '59',
    },
    int initialTimeRevision = 0,
    this.nextDraftTime = '',
    this.nextDraftTimeRevision = 0,
  }) : _snapshot = LiveDraftSnapshotDto(
          draft: LiveDraftDto(
            draftId: 'draft-1',
            sessionId: 'session-1',
            version: 1,
            fields: LiveDraftFieldsDto(initialFields),
            fieldRevisions: {
              for (final field in liveDraftFieldNames)
                field: field == 'time' ? initialTimeRevision : 0,
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

  LiveDraftSnapshotDto _snapshot;
  final List<Map<String, String>> atomicUpdates = [];
  final List<String> acquiredFields = [];
  final List<String> releasedFields = [];
  final Map<String, LiveDraftLockDto> _ownedLocks = {};
  Map<String, String>? committedFields;
  Completer<void>? atomicGate;
  Completer<void>? commitGate;
  Object? fieldUpdateError;
  Object? commitError;
  final String nextDraftTime;
  final int nextDraftTimeRevision;
  LiveDraftCommitDisposition commitDisposition =
      LiveDraftCommitDisposition.committed;
  int commitCalls = 0;

  @override
  LocalCollaborationBinding get binding => const LocalCollaborationBinding(
        serverInstanceId: 'server-1',
        serverOrigin: 'https://example.test',
        accountId: 'user-1',
        sessionId: 'session-1',
        membershipId: 'membership-1',
        membershipVersion: 1,
        role: SessionRole.owner,
        replicaState: 'ready',
        lastAppliedSeq: 1,
        lastSeenHeadSeq: 1,
        revokedAt: null,
      );

  void replaceDraft({
    required String draftId,
    required Map<String, String> fields,
    int? timeRevision,
  }) {
    final previous = _snapshot.draft;
    _snapshot = LiveDraftSnapshotDto(
      draft: LiveDraftDto(
        draftId: draftId,
        sessionId: previous.sessionId,
        version: previous.version + 1,
        fields: LiveDraftFieldsDto(fields),
        fieldRevisions: {
          for (final field in liveDraftFieldNames)
            field: field == 'time'
                ? timeRevision ?? (fields['time']?.isNotEmpty == true ? 1 : 0)
                : 0,
        },
        lastUpdatedBy: null,
        createdAt: DateTime.now().toUtc(),
        lastUpdatedAt: DateTime.now().toUtc(),
      ),
      locks: const [],
      currentOrdinal: _snapshot.currentOrdinal,
      totalRecords: _snapshot.totalRecords,
      previousRecord: null,
    );
    notifyListeners();
  }

  void replaceDraftField(String field, String value) {
    final previous = _snapshot.draft;
    final revisions = Map<String, int>.from(previous.fieldRevisions);
    revisions[field] = (revisions[field] ?? 0) + 1;
    _snapshot = LiveDraftSnapshotDto(
      draft: LiveDraftDto(
        draftId: previous.draftId,
        sessionId: previous.sessionId,
        version: previous.version + 1,
        fields: previous.fields.withField(field, value),
        fieldRevisions: revisions,
        lastUpdatedBy: previous.lastUpdatedBy,
        createdAt: previous.createdAt,
        lastUpdatedAt: DateTime.now().toUtc(),
      ),
      locks: _snapshot.locks,
      currentOrdinal: _snapshot.currentOrdinal,
      totalRecords: _snapshot.totalRecords,
      previousRecord: _snapshot.previousRecord,
    );
    notifyListeners();
  }

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
  Future<void> updateLiveDraftField(String field, String value) async {
    final error = fieldUpdateError;
    if (error != null) throw error;
    replaceDraftField(field, value);
  }

  @override
  Future<void> updateLiveDraftFieldsAtomically(
    Map<String, String> updates,
  ) async {
    atomicUpdates.add(Map<String, String>.from(updates));
    await atomicGate?.future;
    final previous = _snapshot.draft;
    _snapshot = LiveDraftSnapshotDto(
      draft: LiveDraftDto(
        draftId: previous.draftId,
        sessionId: previous.sessionId,
        version: previous.version + 1,
        fields: LiveDraftFieldsDto({
          ...previous.fields.values,
          ...updates,
        }),
        fieldRevisions: {
          for (final field in liveDraftFieldNames)
            field: (previous.fieldRevisions[field] ?? 0) +
                (updates.containsKey(field) ? 1 : 0),
        },
        lastUpdatedBy: previous.lastUpdatedBy,
        createdAt: previous.createdAt,
        lastUpdatedAt: DateTime.now().toUtc(),
      ),
      locks: _snapshot.locks,
      currentOrdinal: _snapshot.currentOrdinal,
      totalRecords: _snapshot.totalRecords,
      previousRecord: _snapshot.previousRecord,
    );
    notifyListeners();
  }

  @override
  Future<LiveDraftCommitDisposition> commitCurrentLiveDraft() async {
    commitCalls += 1;
    committedFields = Map<String, String>.from(_snapshot.draft.fields.values);
    await commitGate?.future;
    final error = commitError;
    if (error != null) throw error;
    final previous = _snapshot.draft;
    final disposition = commitDisposition;
    _snapshot = LiveDraftSnapshotDto(
      draft: LiveDraftDto(
        draftId: disposition == LiveDraftCommitDisposition.committed
            ? 'draft-after-commit'
            : previous.draftId,
        sessionId: previous.sessionId,
        version: previous.version + 1,
        fields: LiveDraftFieldsDto({
          'time': nextDraftTime,
          'controller': previous.fields['controller'],
          'rstSent': '59',
          'rstRcvd': '59',
        }),
        fieldRevisions: {
          for (final field in liveDraftFieldNames)
            field: field == 'time' ? nextDraftTimeRevision : 0,
        },
        lastUpdatedBy: null,
        createdAt: DateTime.now().toUtc(),
        lastUpdatedAt: DateTime.now().toUtc(),
      ),
      locks: const [],
      currentOrdinal: _snapshot.currentOrdinal + 1,
      totalRecords: _snapshot.totalRecords + 1,
      previousRecord: null,
    );
    notifyListeners();
    return disposition;
  }
}

class _LocalOnlyCollaborationProvider extends CollaborationProvider {
  @override
  LocalCollaborationBinding? get binding => null;

  @override
  LiveDraftSnapshotDto? get liveDraftSnapshot => null;
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
