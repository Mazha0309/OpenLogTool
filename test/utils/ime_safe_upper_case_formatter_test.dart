import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/utils/ime_safe_upper_case_formatter.dart';

void main() {
  const formatter = ImeSafeUpperCaseTextFormatter();

  test('leaves an active IME composition untouched', () {
    const composing = TextEditingValue(
      text: 'bg5crl',
      selection: TextSelection.collapsed(offset: 6),
      composing: TextRange(start: 0, end: 6),
    );

    expect(
      formatter.formatEditUpdate(TextEditingValue.empty, composing),
      composing,
    );
  });

  test('commit uppercases text, clears composition, and remaps selection', () {
    const value = TextEditingValue(
      text: 'abc',
      selection: TextSelection(baseOffset: 2, extentOffset: 3),
      composing: TextRange(start: 0, end: 3),
    );

    final committed = ImeSafeUpperCaseTextFormatter.commit(value);

    expect(committed.text, 'ABC');
    expect(committed.selection.baseOffset, 2);
    expect(committed.selection.extentOffset, 3);
    expect(committed.composing, TextRange.empty);
  });
}
