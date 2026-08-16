import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/models/dictionary_item.dart';
import 'package:openlogtool/widgets/dictionary_autocomplete_field.dart';

void main() {
  testWidgets('arrow keys highlight and Enter accepts a dictionary option',
      (tester) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 280,
              child: DictionaryAutocompleteField(
                controller: controller,
                focusNode: focusNode,
                label: 'Radio',
                hintText: 'Radio',
                options: [
                  _item('IC-705'),
                  _item('IC-7300'),
                  _item('IC-7610'),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final field = find.byType(TextFormField);
    await tester.tap(field);
    await tester.enterText(field, 'IC-7');
    await tester.pumpAndSettle();
    expect(find.text('IC-705'), findsOneWidget);
    expect(find.text('IC-7300'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(controller.text, 'IC-7300');
  });
}

DictionaryItem _item(String raw) => DictionaryItem(
      raw: raw,
      pinyin: raw.toLowerCase(),
      abbreviation: raw.toLowerCase(),
      type: 'device',
    );
