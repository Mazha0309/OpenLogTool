import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/theme/app_theme.dart';

void main() {
  for (final brightness in Brightness.values) {
    test('app shell uses layered Material 3 surfaces in $brightness', () {
      final theme = buildAppTheme(
        brightness: brightness,
        seedColor: Colors.blue,
      );
      final colors = theme.colorScheme;

      expect(theme.useMaterial3, isTrue);
      expect(theme.extension<AppSemanticColors>(), isNotNull);
      expect(theme.scaffoldBackgroundColor, colors.surface);
      expect(theme.appBarTheme.backgroundColor, colors.surface);
      expect(theme.appBarTheme.scrolledUnderElevation, 0);

      final railTheme = theme.navigationRailTheme;
      expect(railTheme.backgroundColor, colors.surfaceContainerLow);
      expect(railTheme.useIndicator, isTrue);
      expect(railTheme.indicatorColor, colors.primaryContainer);
      expect(railTheme.indicatorShape, isA<StadiumBorder>());
      expect(railTheme.selectedIconTheme?.color, colors.onPrimaryContainer);
      expect(railTheme.selectedLabelTextStyle?.fontWeight, FontWeight.w700);
      expect(railTheme.unselectedIconTheme?.color, colors.onSurfaceVariant);

      final cardShape = theme.cardTheme.shape! as RoundedRectangleBorder;
      expect(theme.cardTheme.color, colors.surfaceContainerLow);
      expect(
        (cardShape.borderRadius as BorderRadius).topLeft.x,
        14,
      );

      final dialogShape = theme.dialogTheme.shape! as RoundedRectangleBorder;
      expect(theme.dialogTheme.backgroundColor, colors.surfaceContainerHigh);
      expect(
        (dialogShape.borderRadius as BorderRadius).topLeft.x,
        28,
      );

      final inputBorder =
          theme.inputDecorationTheme.enabledBorder! as OutlineInputBorder;
      expect(theme.inputDecorationTheme.filled, isTrue);
      expect(
          theme.inputDecorationTheme.fillColor, colors.surfaceContainerLowest);
      expect((inputBorder.borderRadius).topLeft.x, AppRadius.control);

      final filledStyle = theme.filledButtonTheme.style!;
      expect(
        filledStyle.minimumSize?.resolve(<WidgetState>{}),
        const Size(0, AppDimensions.controlHeight),
      );
      final filledShape =
          filledStyle.shape?.resolve(<WidgetState>{}) as RoundedRectangleBorder;
      expect(
        (filledShape.borderRadius as BorderRadius).topLeft.x,
        AppRadius.control,
      );

      expect(
          theme.navigationBarTheme.backgroundColor, colors.surfaceContainerLow);
      expect(theme.navigationBarTheme.indicatorColor, colors.primaryContainer);
      expect(theme.navigationBarTheme.indicatorShape, isA<StadiumBorder>());
    });
  }
}
