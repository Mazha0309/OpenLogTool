import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/theme/app_theme.dart' as theme;

void main() {
  test('dark theme surfaces are dark (no white-background leakage)', () {
    final dark = theme.buildAppTheme(
      brightness: Brightness.dark,
      seedColor: Colors.blue,
    );
    final scheme = dark.colorScheme;
    expect(scheme.brightness, Brightness.dark);
    // 表面色必须是暗色，避免深色模式下出现刺眼白块。
    expect(scheme.surface.computeLuminance(), lessThan(0.5));
    expect(scheme.surfaceContainerLow.computeLuminance(), lessThan(0.5));
    expect(scheme.surfaceContainerHighest.computeLuminance(), lessThan(0.5));
    expect(
      dark.scaffoldBackgroundColor.computeLuminance(),
      lessThan(0.5),
    );
    expect(
      dark.appBarTheme.backgroundColor!.computeLuminance(),
      lessThan(0.5),
    );
    expect(
      dark.navigationRailTheme.backgroundColor!.computeLuminance(),
      lessThan(0.5),
    );
  });

  test('light and dark themes both build with a real font family', () {
    for (final brightness in Brightness.values) {
      final t = theme.buildAppTheme(
        brightness: brightness,
        seedColor: Colors.teal,
      );
      expect(
        t.textTheme.bodyMedium?.fontFamily,
        isNotNull,
        reason: '$brightness theme should resolve a font family',
      );
    }
  });
}
