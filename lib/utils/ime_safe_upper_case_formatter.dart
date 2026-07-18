import 'dart:math' as math;

import 'package:flutter/services.dart';

/// Uppercases committed text without modifying an IME's active composition.
///
/// Replacing the composing range while a platform input method is still
/// building a candidate can cancel or corrupt that candidate. Controller and
/// callsign fields therefore keep composing text untouched and normalize it
/// only after the composition is committed (or the form is submitted).
class ImeSafeUpperCaseTextFormatter extends TextInputFormatter {
  const ImeSafeUpperCaseTextFormatter();

  static bool hasActiveComposition(TextEditingValue value) =>
      value.composing.isValid && !value.composing.isCollapsed;

  static TextEditingValue commit(TextEditingValue value) {
    final upperCaseText = value.text.toUpperCase();

    int remapOffset(int offset) {
      if (offset < 0) return offset;
      final clamped = math.min(offset, value.text.length);
      return value.text.substring(0, clamped).toUpperCase().length;
    }

    final selection = value.selection;
    return TextEditingValue(
      text: upperCaseText,
      selection: TextSelection(
        baseOffset: remapOffset(selection.baseOffset),
        extentOffset: remapOffset(selection.extentOffset),
        affinity: selection.affinity,
        isDirectional: selection.isDirectional,
      ),
      composing: TextRange.empty,
    );
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (hasActiveComposition(newValue)) return newValue;
    return commit(newValue);
  }
}
