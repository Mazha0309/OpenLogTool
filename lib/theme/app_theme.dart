import 'package:flutter/material.dart';

/// Shared spacing used by the application shell and its reusable surfaces.
///
/// Keeping this scale deliberately small prevents every screen from inventing
/// a slightly different 10/14/18 px rhythm.
abstract final class AppSpace {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

abstract final class AppRadius {
  static const double small = 8;
  static const double control = 12;
  static const double surface = 14;
  static const double hero = 20;
  static const double dialog = 28;
  static const double pill = 999;
}

abstract final class AppBreakpoints {
  static const double compact = 600;
  static const double cardHeaderStack = 640;
  static const double medium = 840;
  static const double desktop = 1200;
}

abstract final class AppDimensions {
  static const double controlHeight = 40;
  static const double pageIcon = 44;
  static const double sectionIcon = 36;
  static const double actionIcon = 32;
  static const double standardContentWidth = 1120;
  static const double wideContentWidth = 1440;
  static const double dialogWidth = 560;
}

abstract final class AppMotion {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration standard = Duration(milliseconds: 160);
}

/// Semantic colors that Material's base [ColorScheme] does not expose.
///
/// Status UI should use this extension instead of hard-coded green/orange
/// values so that it remains legible in both brightness modes.
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
  });

  factory AppSemanticColors.forBrightness(Brightness brightness) =>
      brightness == Brightness.dark
          ? const AppSemanticColors(
              success: Color(0xFF81D9A3),
              onSuccess: Color(0xFF00391D),
              successContainer: Color(0xFF07512F),
              onSuccessContainer: Color(0xFF9EF6BE),
              warning: Color(0xFFFFC66D),
              onWarning: Color(0xFF432C00),
              warningContainer: Color(0xFF604100),
              onWarningContainer: Color(0xFFFFDEA4),
            )
          : const AppSemanticColors(
              success: Color(0xFF146C43),
              onSuccess: Colors.white,
              successContainer: Color(0xFFB6F2CE),
              onSuccessContainer: Color(0xFF002112),
              warning: Color(0xFF805600),
              onWarning: Colors.white,
              warningContainer: Color(0xFFFFDEA4),
              onWarningContainer: Color(0xFF281900),
            );

  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;

  @override
  AppSemanticColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
  }) =>
      AppSemanticColors(
        success: success ?? this.success,
        onSuccess: onSuccess ?? this.onSuccess,
        successContainer: successContainer ?? this.successContainer,
        onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
        warning: warning ?? this.warning,
        onWarning: onWarning ?? this.onWarning,
        warningContainer: warningContainer ?? this.warningContainer,
        onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      );

  @override
  AppSemanticColors lerp(
    covariant ThemeExtension<AppSemanticColors>? other,
    double t,
  ) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successContainer:
          Color.lerp(successContainer, other.successContainer, t)!,
      onSuccessContainer:
          Color.lerp(onSuccessContainer, other.onSuccessContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      warningContainer:
          Color.lerp(warningContainer, other.warningContainer, t)!,
      onWarningContainer:
          Color.lerp(onWarningContainer, other.onWarningContainer, t)!,
    );
  }
}

extension AppThemeExtensions on BuildContext {
  AppSemanticColors get semanticColors =>
      Theme.of(this).extension<AppSemanticColors>() ??
      AppSemanticColors.forBrightness(Theme.of(this).brightness);
}

/// Builds the application theme used by both the clerk window and controller
/// display windows.
///
/// Keeping this in one place prevents a controller window from looking like a
/// different application when the seed color or font changes.
ThemeData buildAppTheme({
  required Brightness brightness,
  required Color seedColor,
  String? fontFamily,
}) {
  final dark = brightness == Brightness.dark;
  final colorScheme = ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: brightness,
  );
  final outlineColor = colorScheme.outlineVariant.withValues(
    alpha: dark ? 0.72 : 0.86,
  );
  final semanticColors = AppSemanticColors.forBrightness(brightness);
  final controlShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppRadius.control),
  );
  const compactButtonPadding = EdgeInsets.symmetric(
    horizontal: AppSpace.md,
    vertical: AppSpace.xs,
  );
  const compactButtonSize = Size(0, AppDimensions.controlHeight);

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    extensions: [semanticColors],
    scaffoldBackgroundColor: colorScheme.surface,
    appBarTheme: AppBarThemeData(
      backgroundColor: colorScheme.surface,
      foregroundColor: colorScheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
    fontFamily: fontFamily,
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: colorScheme.surfaceContainerLow,
      elevation: 0,
      useIndicator: true,
      indicatorColor: colorScheme.primaryContainer,
      indicatorShape: const StadiumBorder(),
      selectedIconTheme: IconThemeData(
        color: colorScheme.onPrimaryContainer,
        size: 24,
      ),
      selectedLabelTextStyle: TextStyle(
        color: colorScheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
      unselectedIconTheme: IconThemeData(
        color: colorScheme.onSurfaceVariant,
        size: 24,
      ),
      unselectedLabelTextStyle: TextStyle(
        color: colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w500,
      ),
    ),
    cardTheme: CardThemeData(
      color: colorScheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.surface),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colorScheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.dialog),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: colorScheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: colorScheme.surfaceContainerLowest,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpace.sm,
        vertical: AppSpace.sm,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: BorderSide(color: outlineColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: BorderSide(color: outlineColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: BorderSide(color: colorScheme.primary, width: 1.6),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colorScheme.surfaceContainerLow,
      elevation: 0,
      indicatorColor: colorScheme.primaryContainer,
      indicatorShape: const StadiumBorder(),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        return TextStyle(
          color: states.contains(WidgetState.selected)
              ? colorScheme.onSurface
              : colorScheme.onSurfaceVariant,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
        );
      }),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        minimumSize: compactButtonSize,
        padding: compactButtonPadding,
        shape: controlShape,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        elevation: 0,
        minimumSize: compactButtonSize,
        padding: compactButtonPadding,
        shape: controlShape,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: compactButtonSize,
        padding: compactButtonPadding,
        shape: controlShape,
        side: BorderSide(color: outlineColor),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: compactButtonSize,
        padding: compactButtonPadding,
        shape: controlShape,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size.square(AppDimensions.controlHeight),
        maximumSize: const Size.square(AppDimensions.controlHeight),
        padding: const EdgeInsets.all(AppSpace.xs),
        shape: controlShape,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
      minVerticalPadding: AppSpace.xs,
      iconColor: colorScheme.onSurfaceVariant,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
    ),
    chipTheme: ChipThemeData(
      side: BorderSide.none,
      shape: const StadiumBorder(),
      backgroundColor: colorScheme.surfaceContainerHighest,
      selectedColor: colorScheme.primaryContainer,
      labelStyle: TextStyle(
        color: colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
    ),
    tabBarTheme: TabBarThemeData(
      dividerColor: colorScheme.outlineVariant,
      labelColor: colorScheme.primary,
      unselectedLabelColor: colorScheme.onSurfaceVariant,
      labelStyle: const TextStyle(fontWeight: FontWeight.w700),
      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
      indicatorSize: TabBarIndicatorSize.label,
    ),
  );
}
