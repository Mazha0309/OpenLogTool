import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/widgets/callsign_history_field.dart';

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
}
