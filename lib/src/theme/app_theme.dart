import 'package:flutter/material.dart';

const _seedColor = Color(0xFF2563EB);

ThemeData buildLightTheme() {
  final cs = ColorScheme.fromSeed(seedColor: _seedColor, brightness: Brightness.light);
  return _baseTheme(cs, Brightness.light);
}

ThemeData buildDarkTheme() {
  final cs = ColorScheme.fromSeed(seedColor: _seedColor, brightness: Brightness.dark);
  return _baseTheme(cs, Brightness.dark);
}

ThemeData _baseTheme(ColorScheme cs, Brightness brightness) {
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: cs,
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      isDense: true,
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      type: BottomNavigationBarType.fixed,
      selectedItemColor: cs.primary,
      unselectedItemColor: cs.onSurface.withAlpha(150),
    ),
  );
}
