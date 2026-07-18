import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/src/bridge/models/log_entry.dart' as bridge;
import 'package:openlogtool/widgets/callsign_history_field.dart';

bridge.LogEntry _historyRecord() => const bridge.LogEntry(
      syncId: 'history-1',
      sessionId: 'session-1',
      time: '2026-07-12T08:15:00Z',
      controller: 'BG5CRL',
      callsign: 'BA4AAA',
      rstSent: '58',
      rstRcvd: '47',
      qth: '上海',
      device: 'IC-7300',
      power: '100W',
      antenna: 'DP',
      height: '12m',
      createdAt: '2026-07-12T08:15:00Z',
      updatedAt: '2026-07-12T08:15:00Z',
    );

Widget _localizedApp(Widget child) => MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('history reuse affordance follows its opt-in switch',
      (tester) async {
    final controllers = List.generate(6, (_) => TextEditingController());
    var historyLoads = 0;
    addTearDown(() {
      for (final controller in controllers) {
        controller.dispose();
      }
    });

    Widget app(bool historyEnabled) => MaterialApp(
          home: Scaffold(
            body: CallsignHistoryField(
              callsignController: controllers[0],
              deviceController: controllers[1],
              antennaController: controllers[2],
              qthController: controllers[3],
              powerController: controllers[4],
              heightController: controllers[5],
              label: 'Callsign',
              hintText: 'BA4AAA',
              historyEnabled: historyEnabled,
              historyLoader: (callsign, limit) async {
                historyLoads += 1;
                return [];
              },
            ),
          ),
        );

    await tester.pumpWidget(app(false));
    expect(find.byIcon(Icons.search), findsNothing);
    await tester.enterText(find.byType(TextFormField), 'BA4AAA');
    await tester.pump();
    expect(historyLoads, 0);

    await tester.pumpWidget(app(true));
    expect(find.byIcon(Icons.search), findsOneWidget);
    await tester.pump();
    expect(historyLoads, 1);

    await tester.pumpWidget(app(false));
    expect(find.byIcon(Icons.search), findsNothing);
    await tester.enterText(find.byType(TextFormField), 'BA4BBB');
    await tester.pump();
    expect(historyLoads, 1);
  });

  testWidgets('history reuse defaults to enabled', (tester) async {
    final controllers = List.generate(6, (_) => TextEditingController());
    addTearDown(() {
      for (final controller in controllers) {
        controller.dispose();
      }
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CallsignHistoryField(
            callsignController: controllers[0],
            deviceController: controllers[1],
            antennaController: controllers[2],
            qthController: controllers[3],
            powerController: controllers[4],
            heightController: controllers[5],
            label: 'Callsign',
            hintText: 'BA4AAA',
            historyLoader: (_, __) async => [],
          ),
        ),
      ),
    );
    expect(
      tester
          .widget<CallsignHistoryField>(find.byType(CallsignHistoryField))
          .historyEnabled,
      isTrue,
    );
    expect(find.byIcon(Icons.search), findsOneWidget);
  });

  testWidgets('history lookup waits for callsign IME composition to finish',
      (tester) async {
    final controllers = List.generate(6, (_) => TextEditingController());
    final queries = <String>[];
    addTearDown(() {
      for (final controller in controllers) {
        controller.dispose();
      }
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CallsignHistoryField(
            callsignController: controllers[0],
            deviceController: controllers[1],
            antennaController: controllers[2],
            qthController: controllers[3],
            powerController: controllers[4],
            heightController: controllers[5],
            label: 'Callsign',
            hintText: 'BA4AAA',
            historyLoader: (callsign, _) async {
              queries.add(callsign);
              return [];
            },
          ),
        ),
      ),
    );

    controllers[0].value = const TextEditingValue(
      text: 'bg5crl',
      selection: TextSelection.collapsed(offset: 6),
      composing: TextRange(start: 0, end: 6),
    );
    await tester.pump();
    expect(queries, isEmpty);

    controllers[0].value = const TextEditingValue(
      text: 'bg5crl',
      selection: TextSelection.collapsed(offset: 6),
      composing: TextRange.empty,
    );
    await tester.pumpAndSettle();
    expect(queries, ['BG5CRL']);
  });

  testWidgets('reuses station details without changing operator fields',
      (tester) async {
    final callsign = TextEditingController();
    final device = TextEditingController();
    final antenna = TextEditingController();
    final qth = TextEditingController();
    final power = TextEditingController();
    final height = TextEditingController();
    final rstSent = TextEditingController();
    final rstRcvd = TextEditingController();
    final controller = TextEditingController();
    final currentTime = TextEditingController(text: '20:42');
    final controllers = [
      callsign,
      device,
      antenna,
      qth,
      power,
      height,
      rstSent,
      rstRcvd,
      controller,
      currentTime,
    ];
    addTearDown(() {
      for (final item in controllers) {
        item.dispose();
      }
    });

    await tester.pumpWidget(
      _localizedApp(
        Column(
          children: [
            CallsignHistoryField(
              callsignController: callsign,
              deviceController: device,
              antennaController: antenna,
              qthController: qth,
              powerController: power,
              heightController: height,
              reportController: rstSent,
              rstRcvdController: rstRcvd,
              controllerController: controller,
              label: 'Callsign',
              hintText: 'BA4AAA',
              historyLoader: (_, __) async => [_historyRecord()],
            ),
            TextField(controller: currentTime),
          ],
        ),
      ),
    );

    await tester.tap(find.byType(TextFormField));
    await tester.enterText(find.byType(TextFormField), 'BA4AAA');
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.history));
    await tester.pumpAndSettle();

    expect(device.text, 'IC-7300');
    expect(antenna.text, 'DP');
    expect(qth.text, '上海');
    expect(power.text, '100W');
    expect(height.text, '12m');
    expect(rstSent.text, isEmpty);
    expect(rstRcvd.text, isEmpty);
    expect(controller.text, isEmpty);
    expect(currentTime.text, '20:42');
  });

  testWidgets('history overlay stays inside a narrow phone viewport',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controllers = List.generate(6, (_) => TextEditingController());
    addTearDown(() {
      for (final controller in controllers) {
        controller.dispose();
      }
    });

    await tester.pumpWidget(
      _localizedApp(
        Align(
          alignment: Alignment.topRight,
          child: SizedBox(
            width: 160,
            child: CallsignHistoryField(
              callsignController: controllers[0],
              deviceController: controllers[1],
              antennaController: controllers[2],
              qthController: controllers[3],
              powerController: controllers[4],
              heightController: controllers[5],
              label: 'Callsign',
              hintText: 'BA4AAA',
              historyLoader: (_, __) async => [_historyRecord()],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextFormField));
    await tester.enterText(find.byType(TextFormField), 'BA4AAA');
    await tester.pumpAndSettle();

    final rect =
        tester.getRect(find.byKey(const Key('callsign-history-overlay')));
    expect(rect.left, greaterThanOrEqualTo(8));
    expect(rect.right, lessThanOrEqualTo(312));
    expect(tester.takeException(), isNull);
  });

  testWidgets('history overlay opens above the mobile keyboard when needed',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.reset);
    final controllers = List.generate(6, (_) => TextEditingController());
    addTearDown(() {
      for (final controller in controllers) {
        controller.dispose();
      }
    });

    await tester.pumpWidget(
      _localizedApp(
        Align(
          alignment: Alignment.bottomRight,
          child: SizedBox(
            width: 160,
            child: CallsignHistoryField(
              callsignController: controllers[0],
              deviceController: controllers[1],
              antennaController: controllers[2],
              qthController: controllers[3],
              powerController: controllers[4],
              heightController: controllers[5],
              label: 'Callsign',
              hintText: 'BA4AAA',
              historyLoader: (_, __) async => [_historyRecord()],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextFormField));
    await tester.enterText(find.byType(TextFormField), 'BA4AAA');
    await tester.pumpAndSettle();

    final fieldRect = tester.getRect(find.byType(TextFormField));
    final overlayRect =
        tester.getRect(find.byKey(const Key('callsign-history-overlay')));
    expect(overlayRect.bottom, lessThanOrEqualTo(fieldRect.top - 4));
    expect(overlayRect.top, greaterThanOrEqualTo(8));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a mobile tap outside releases callsign focus', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final focusNode = FocusNode();
    final controllers = List.generate(6, (_) => TextEditingController());
    addTearDown(() {
      focusNode.dispose();
      for (final controller in controllers) {
        controller.dispose();
      }
    });

    await tester.pumpWidget(
      _localizedApp(
        Column(
          children: [
            CallsignHistoryField(
              callsignController: controllers[0],
              deviceController: controllers[1],
              antennaController: controllers[2],
              qthController: controllers[3],
              powerController: controllers[4],
              heightController: controllers[5],
              focusNode: focusNode,
              label: 'Callsign',
              hintText: 'BA4AAA',
              historyLoader: (_, __) async => [],
            ),
            const Expanded(child: SizedBox()),
          ],
        ),
      ),
    );

    await tester.tap(find.byType(TextFormField));
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    await tester.tapAt(
      const Offset(300, 600),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();
    expect(focusNode.hasFocus, isFalse);
  });
}
