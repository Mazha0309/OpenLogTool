import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/widgets/font_picker_dialog.dart';

void main() {
  testWidgets('large font lists stay lazy and use one pending preview',
      (tester) async {
    FontPickerResult? result;
    final fonts = List<String>.generate(
      400,
      (index) => 'Font ${index.toString().padLeft(3, '0')}',
    );

    await tester.pumpWidget(
      _FontPickerHarness(
        locale: const Locale('zh', 'CN'),
        fonts: fonts,
        currentFont: null,
        onResult: (value) => result = value,
      ),
    );
    await tester.tap(find.byKey(const Key('open-font-picker')));
    await tester.pumpAndSettle();

    expect(find.text('共 400 个字体'), findsOneWidget);
    expect(find.byType(ListTile).evaluate().length, lessThan(30));

    final firstOption = find.byKey(const ValueKey('font-option-Font 000'));
    final optionText = tester.widget<Text>(firstOption);
    expect(optionText.style?.fontFamily, isNull);

    await tester.tap(firstOption);
    await tester.pump();
    expect(result, isNull);
    final preview = tester.widget<Text>(
      find.byKey(const Key('font-preview-sample')),
    );
    expect(preview.style?.fontFamily, 'Font 000');

    await tester.tap(find.byKey(const Key('apply-font-selection')));
    await tester.pumpAndSettle();
    expect(result?.fontFamily, 'Font 000');
  });

  testWidgets('font search and system-default selection render in en_US',
      (tester) async {
    FontPickerResult? result;
    await tester.pumpWidget(
      _FontPickerHarness(
        locale: const Locale('en', 'US'),
        fonts: const <String>['Inter', 'Roboto', 'SarasaGothicSC'],
        currentFont: 'Inter',
        onResult: (value) => result = value,
      ),
    );
    await tester.tap(find.byKey(const Key('open-font-picker')));
    await tester.pumpAndSettle();

    expect(find.text('Choose font'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('font-search-field')),
      'robo',
    );
    await tester.pump();
    expect(find.text('1 fonts'), findsOneWidget);
    expect(find.text('Roboto'), findsOneWidget);

    await tester.tap(find.text('System default'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('apply-font-selection')));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result?.fontFamily, isNull);
  });
}

class _FontPickerHarness extends StatelessWidget {
  const _FontPickerHarness({
    required this.locale,
    required this.fonts,
    required this.currentFont,
    required this.onResult,
  });

  final Locale locale;
  final List<String> fonts;
  final String? currentFont;
  final ValueChanged<FontPickerResult?> onResult;

  @override
  Widget build(BuildContext context) => MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                key: const Key('open-font-picker'),
                onPressed: () async {
                  final result = await showDialog<FontPickerResult>(
                    context: context,
                    builder: (_) => FontPickerDialog(
                      availableFonts: fonts,
                      currentFont: currentFont,
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
