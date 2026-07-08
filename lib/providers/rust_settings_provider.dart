import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:openlogtool/src/bridge/rust_api.dart';

class RustSettingsProvider extends ChangeNotifier {
  Color _themeColor = const Color(0xFF1976D2);
  bool _isDarkMode = false;
  bool _wideLayout = false;
  String _fontFamily = '';
  bool _loaded = false;

  Color get themeColor => _themeColor;
  bool get isDarkMode => _isDarkMode;
  bool get wideLayout => _wideLayout;
  String get fontFamily => _fontFamily;
  bool get loaded => _loaded;

  static const _keyThemeColor = 'theme_color';
  static const _keyDarkMode = 'dark_mode';
  static const _keyWideLayout = 'wide_layout';
  static const _keyFontFamily = 'font_family';

  Future<void> load() async {
    try {
      final colorStr = await RustApi.getSetting(key: _keyThemeColor);
      if (colorStr != null) {
        final intVal = int.tryParse(colorStr);
        if (intVal != null) _themeColor = Color(intVal);
      }

      final darkStr = await RustApi.getSetting(key: _keyDarkMode);
      if (darkStr != null) _isDarkMode = darkStr == 'true';

      final wideStr = await RustApi.getSetting(key: _keyWideLayout);
      if (wideStr != null) _wideLayout = wideStr == 'true';

      final fontStr = await RustApi.getSetting(key: _keyFontFamily);
      if (fontStr != null) _fontFamily = fontStr;
    } catch (_) {}

    _loaded = true;
    notifyListeners();
  }

  Future<void> setThemeColor(Color color) async {
    _themeColor = color;
    notifyListeners();
    await RustApi.setSetting(key: _keyThemeColor, value: color.value.toString());
  }

  Future<void> setDarkMode(bool value) async {
    _isDarkMode = value;
    notifyListeners();
    await RustApi.setSetting(key: _keyDarkMode, value: value.toString());
  }

  Future<void> setWideLayout(bool value) async {
    _wideLayout = value;
    notifyListeners();
    await RustApi.setSetting(key: _keyWideLayout, value: value.toString());
  }

  Future<void> setFontFamily(String value) async {
    _fontFamily = value;
    notifyListeners();
    await RustApi.setSetting(key: _keyFontFamily, value: value);
  }
}
