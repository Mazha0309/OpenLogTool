import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/widgets/theme_color_picker_dialog.dart';

void main() {
  testWidgets('presets and custom controls share one confirmation flow',
      (tester) async {
    Color? result;
    await tester.pumpWidget(
      _PickerHarness(
        locale: const Locale('zh', 'CN'),
        initialColor: const Color(0xFF2196F3),
        onResult: (color) => result = color,
      ),
    );

    await tester.tap(find.byKey(const Key('open-theme-color-picker')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('预设颜色'), findsOneWidget);
    expect(find.text('自定义颜色'), findsOneWidget);
    expect(find.byKey(const Key('theme-color-hex-field')), findsOneWidget);
    expect(find.text('粉色'), findsOneWidget);

    await tester.tap(find.text('粉色'));
    await tester.pumpAndSettle();
    final hexField = tester.widget<TextField>(
      find.byKey(const Key('theme-color-hex-field')),
    );
    expect(hexField.controller?.text, '#FF93B7');
    expect(result, isNull);

    await tester.tap(find.byKey(const Key('apply-theme-color')));
    await tester.pumpAndSettle();
    expect(result, const Color(0xFFFF93B7));
  });

  testWidgets('HEX input supports a custom opaque theme color', (tester) async {
    Color? result;
    await tester.pumpWidget(
      _PickerHarness(
        locale: const Locale('en', 'US'),
        initialColor: const Color(0xFF4CAF50),
        onResult: (color) => result = color,
      ),
    );

    await tester.tap(find.byKey(const Key('open-theme-color-picker')));
    await tester.pumpAndSettle();
    expect(find.text('Choose theme color'), findsOneWidget);
    expect(find.text('Preset colors'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('theme-color-hex-field')),
      '#123456',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('apply-theme-color')));
    await tester.pumpAndSettle();

    expect(result, const Color(0xFF123456));
  });

  testWidgets('theme mode hides opacity and always returns an opaque color',
      (tester) async {
    Color? result;
    await tester.pumpWidget(
      _PickerHarness(
        locale: const Locale('en', 'US'),
        initialColor: const Color(0x402196F3),
        onResult: (color) => result = color,
      ),
    );

    await tester.tap(find.byKey(const Key('open-theme-color-picker')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('theme-color-opacity-slider')),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('apply-theme-color')));
    await tester.pumpAndSettle();

    expect(result, const Color(0xFF2196F3));
  });

  testWidgets('export mode preserves opacity while editing the RGB value',
      (tester) async {
    Color? result;
    await tester.pumpWidget(
      _PickerHarness(
        locale: const Locale('en', 'US'),
        initialColor: const Color(0x802196F3),
        title: 'Choose export color',
        allowOpacity: true,
        onResult: (color) => result = color,
      ),
    );

    await tester.tap(find.byKey(const Key('open-theme-color-picker')));
    await tester.pumpAndSettle();

    expect(find.text('Choose export color'), findsOneWidget);
    final opacityFinder = find.byKey(const Key('theme-color-opacity-slider'));
    expect(opacityFinder, findsOneWidget);
    expect(
      tester.widget<Slider>(opacityFinder).value,
      closeTo(128 / 255, 0.001),
    );

    await tester.enterText(
      find.byKey(const Key('theme-color-hex-field')),
      '#123456',
    );
    await tester.pump();
    expect(
      tester.widget<Slider>(opacityFinder).value,
      closeTo(128 / 255, 0.001),
    );

    tester.widget<Slider>(opacityFinder).onChanged!(0.25);
    await tester.pump();
    await tester.tap(find.byKey(const Key('apply-theme-color')));
    await tester.pumpAndSettle();

    expect(result, const Color(0x40123456));
  });

  testWidgets('SV drag uses the actual narrow-dialog color area',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(407, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      _PickerHarness(
        locale: const Locale('zh', 'CN'),
        initialColor: const Color(0xFFFF0000),
        onResult: (_) {},
      ),
    );
    await tester.tap(find.byKey(const Key('open-theme-color-picker')));
    await tester.pumpAndSettle();

    final area = find.byKey(const Key('theme-color-sv-area'));
    await tester.ensureVisible(area);
    final rect = tester.getRect(area);
    final gesture = await tester.startGesture(rect.center);
    await gesture.moveTo(rect.topRight);
    await gesture.up();
    await tester.pump();

    final hexField = tester.widget<TextField>(
      find.byKey(const Key('theme-color-hex-field')),
    );
    expect(hexField.controller?.text, '#FF0000');
  });

  testWidgets('desktop-height dialog initially shows HEX and hue controls',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    // The captured 666 px desktop window includes roughly 46 px of title bar.
    tester.view.physicalSize = const Size(1247, 620);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      _PickerHarness(
        locale: const Locale('zh', 'CN'),
        initialColor: const Color(0xFFFF93B7),
        onResult: (_) {},
      ),
    );
    await tester.tap(find.byKey(const Key('open-theme-color-picker')));
    await tester.pumpAndSettle();

    final scrollRect =
        tester.getRect(find.byKey(const Key('theme-color-content-scroll')));
    final hexRect =
        tester.getRect(find.byKey(const Key('theme-color-hex-field')));
    expect(hexRect.top, greaterThanOrEqualTo(scrollRect.top));
    expect(hexRect.bottom, lessThanOrEqualTo(scrollRect.bottom));
    expect(
      find.byKey(const Key('theme-color-hue-slider')).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('apply-theme-color')).hitTestable(),
      findsOneWidget,
    );

    // All six desktop presets stay on one row instead of pushing custom
    // controls below the fold.
    expect(tester.getTopLeft(find.text('蓝色')).dy,
        tester.getTopLeft(find.text('粉色')).dy);
  });

  testWidgets('very short dialog scrolls while actions remain reachable',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 480);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      _PickerHarness(
        locale: const Locale('en', 'US'),
        initialColor: const Color(0xFF2196F3),
        onResult: (_) {},
      ),
    );
    await tester.tap(find.byKey(const Key('open-theme-color-picker')));
    await tester.pumpAndSettle();

    final apply = find.byKey(const Key('apply-theme-color'));
    expect(apply.hitTestable(), findsOneWidget);

    await tester.drag(
      find.byKey(const Key('theme-color-content-scroll')),
      const Offset(0, -260),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('theme-color-hue-slider')).hitTestable(),
      findsOneWidget,
    );
    expect(apply.hitTestable(), findsOneWidget);
  });
}

class _PickerHarness extends StatelessWidget {
  const _PickerHarness({
    required this.locale,
    required this.initialColor,
    required this.onResult,
    this.title,
    this.allowOpacity = false,
  });

  final Locale locale;
  final Color initialColor;
  final ValueChanged<Color?> onResult;
  final String? title;
  final bool allowOpacity;

  @override
  Widget build(BuildContext context) => MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                key: const Key('open-theme-color-picker'),
                onPressed: () async {
                  final result = await showDialog<Color>(
                    context: context,
                    builder: (_) => ThemeColorPickerDialog(
                      initialColor: initialColor,
                      title: title,
                      allowOpacity: allowOpacity,
                    ),
                  );
                  onResult(result);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
}
