import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/theme/app_theme.dart';

void main() {
  test('default theme uses SarasaGothicSC as the font family', () {
    final t = buildAppTheme(
      brightness: Brightness.light,
      seedColor: Colors.blue,
    );
    expect(t.textTheme.bodyMedium?.fontFamily, 'SarasaGothicSC');
  });

  test('explicit fontFamily still overrides the SarasaGothicSC default', () {
    final t = buildAppTheme(
      brightness: Brightness.dark,
      seedColor: Colors.blue,
      fontFamily: 'Noto Sans SC',
    );
    expect(t.textTheme.bodyMedium?.fontFamily, 'Noto Sans SC');
  });
}
