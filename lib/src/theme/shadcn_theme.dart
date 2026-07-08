import 'package:flutter/material.dart';

class ShadcnColors {
  // Light
  static const background = Color(0xFFFFFFFF);
  static const foreground = Color(0xFF09090B);
  static const card = Color(0xFFFFFFFF);
  static const cardForeground = Color(0xFF09090B);

  static const primary = Color(0xFF18181B);
  static const primaryForeground = Color(0xFFFAFAFA);

  static const secondary = Color(0xFFF4F4F5);
  static const secondaryForeground = Color(0xFF18181B);

  static const muted = Color(0xFFF4F4F5);
  static const mutedForeground = Color(0xFF71717A);

  static const accent = Color(0xFFF4F4F5);
  static const accentForeground = Color(0xFF18181B);

  static const destructive = Color(0xFFEF4444);
  static const destructiveForeground = Color(0xFFFAFAFA);

  static const border = Color(0xFFE4E4E7);
  static const input = Color(0xFFE4E4E7);
  static const ring = Color(0xFF18181B);

  // Dark
  static const backgroundDark = Color(0xFF09090B);
  static const foregroundDark = Color(0xFFFAFAFA);
  static const cardDark = Color(0xFF09090B);
  static const cardForegroundDark = Color(0xFFFAFAFA);

  static const primaryDark = Color(0xFFFAFAFA);
  static const primaryForegroundDark = Color(0xFF18181B);

  static const secondaryDark = Color(0xFF27272A);
  static const secondaryForegroundDark = Color(0xFFFAFAFA);

  static const mutedDark = Color(0xFF27272A);
  static const mutedForegroundDark = Color(0xFFA1A1AA);

  static const accentDark = Color(0xFF27272A);
  static const accentForegroundDark = Color(0xFFFAFAFA);

  static const destructiveDark = Color(0xFF7F1D1D);
  static const destructiveForegroundDark = Color(0xFFFAFAFA);

  static const borderDark = Color(0xFF27272A);
  static const inputDark = Color(0xFF27272A);
  static const ringDark = Color(0xFFD4D4D8);
}

ThemeData shadcnTheme({required bool dark}) {
  final c = dark ? _darkColors() : _lightColors();
  return ThemeData(
    useMaterial3: false,
    brightness: dark ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: c.background,
    colorScheme: ColorScheme(
      brightness: dark ? Brightness.dark : Brightness.light,
      primary: c.primary,
      onPrimary: c.primaryForeground,
      secondary: c.secondary,
      onSecondary: c.secondaryForeground,
      surface: c.card,
      onSurface: c.cardForeground,
      error: c.destructive,
      onError: c.destructiveForeground,
    ),
    textTheme: _textTheme(c),
    cardTheme: CardThemeData(
      color: c.card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: c.border, width: 1),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStatePropertyAll(c.primary),
        foregroundColor: WidgetStatePropertyAll(c.primaryForeground),
        elevation: const WidgetStatePropertyAll(0),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: false,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: c.input),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: c.input),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: c.ring, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: c.destructive),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      labelStyle: TextStyle(color: c.mutedForeground, fontSize: 14),
    ),
    dividerTheme: DividerThemeData(
      color: c.border,
      thickness: 1,
      space: 0,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: c.border),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: c.background,
      foregroundColor: c.foreground,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: c.background,
      selectedItemColor: c.primary,
      unselectedItemColor: c.mutedForeground,
      elevation: 0,
      type: BottomNavigationBarType.fixed,
    ),
  );
}

TextTheme _textTheme(_ThemeColors c) {
  return TextTheme(
    displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: c.foreground),
    headlineLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: c.foreground),
    titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: c.foreground),
    titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: c.foreground),
    bodyLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w400, color: c.foreground),
    bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: c.foreground),
    bodySmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: c.mutedForeground),
    labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: c.foreground),
    labelSmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: c.mutedForeground),
  );
}

class _ThemeColors {
  final Color background;
  final Color foreground;
  final Color card;
  final Color cardForeground;
  final Color primary;
  final Color primaryForeground;
  final Color secondary;
  final Color secondaryForeground;
  final Color muted;
  final Color mutedForeground;
  final Color accent;
  final Color accentForeground;
  final Color destructive;
  final Color destructiveForeground;
  final Color border;
  final Color input;
  final Color ring;

  const _ThemeColors({
    required this.background,
    required this.foreground,
    required this.card,
    required this.cardForeground,
    required this.primary,
    required this.primaryForeground,
    required this.secondary,
    required this.secondaryForeground,
    required this.muted,
    required this.mutedForeground,
    required this.accent,
    required this.accentForeground,
    required this.destructive,
    required this.destructiveForeground,
    required this.border,
    required this.input,
    required this.ring,
  });
}

_ThemeColors _lightColors() => const _ThemeColors(
  background: ShadcnColors.background,
  foreground: ShadcnColors.foreground,
  card: ShadcnColors.card,
  cardForeground: ShadcnColors.cardForeground,
  primary: ShadcnColors.primary,
  primaryForeground: ShadcnColors.primaryForeground,
  secondary: ShadcnColors.secondary,
  secondaryForeground: ShadcnColors.secondaryForeground,
  muted: ShadcnColors.muted,
  mutedForeground: ShadcnColors.mutedForeground,
  accent: ShadcnColors.accent,
  accentForeground: ShadcnColors.accentForeground,
  destructive: ShadcnColors.destructive,
  destructiveForeground: ShadcnColors.destructiveForeground,
  border: ShadcnColors.border,
  input: ShadcnColors.input,
  ring: ShadcnColors.ring,
);

_ThemeColors _darkColors() => const _ThemeColors(
  background: ShadcnColors.backgroundDark,
  foreground: ShadcnColors.foregroundDark,
  card: ShadcnColors.cardDark,
  cardForeground: ShadcnColors.cardForegroundDark,
  primary: ShadcnColors.primaryDark,
  primaryForeground: ShadcnColors.primaryForegroundDark,
  secondary: ShadcnColors.secondaryDark,
  secondaryForeground: ShadcnColors.secondaryForegroundDark,
  muted: ShadcnColors.mutedDark,
  mutedForeground: ShadcnColors.mutedForegroundDark,
  accent: ShadcnColors.accentDark,
  accentForeground: ShadcnColors.accentForegroundDark,
  destructive: ShadcnColors.destructiveDark,
  destructiveForeground: ShadcnColors.destructiveForegroundDark,
  border: ShadcnColors.borderDark,
  input: ShadcnColors.inputDark,
  ring: ShadcnColors.ringDark,
);
