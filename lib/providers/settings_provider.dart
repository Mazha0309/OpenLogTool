import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openlogtool/config/app_config.dart';

class SettingsProvider with ChangeNotifier {
  static const String _wideLayoutKey = 'wideLayoutEnabled';
  static const String _themeColorKey = 'themeColor';
  static const String _isDarkModeKey = 'isDarkMode';
  static const String _fontFamilyKey = 'fontFamily';

  bool _wideLayoutEnabled = false;
  Color _themeColor = const Color(0xFF2196F3);
  bool _isDarkMode = false;
  String _fontFamily = '';
  List<String> _availableFonts = [];

  bool get wideLayoutEnabled => _wideLayoutEnabled;
  Color get themeColor => _themeColor;
  bool get isDarkMode => _isDarkMode;
  String? get fontFamily => _fontFamily.isEmpty ? null : _fontFamily;
  List<String> get availableFonts => _availableFonts;

  SettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _availableFonts = AppConfig.getSystemFonts();
    
    final prefs = await SharedPreferences.getInstance();
    
    _wideLayoutEnabled = prefs.getBool(_wideLayoutKey) ?? false;
    _isDarkMode = prefs.getBool(_isDarkModeKey) ?? false;
    _fontFamily = prefs.getString(_fontFamilyKey) ?? '';
    
    final colorValue = prefs.getInt(_themeColorKey);
    if (colorValue != null) {
      _themeColor = Color(colorValue);
    }
    
    notifyListeners();
  }

  Future<void> toggleWideLayout() async {
    _wideLayoutEnabled = !_wideLayoutEnabled;
    await _saveSetting(_wideLayoutKey, _wideLayoutEnabled);
    notifyListeners();
  }

  Future<void> setWideLayout(bool enabled) async {
    _wideLayoutEnabled = enabled;
    await _saveSetting(_wideLayoutKey, enabled);
    notifyListeners();
  }

  Future<void> setThemeColor(Color color) async {
    _themeColor = color;
    await _saveSetting(_themeColorKey, color.value);
    notifyListeners();
  }

  Future<void> toggleDarkMode() async {
    _isDarkMode = !_isDarkMode;
    await _saveSetting(_isDarkModeKey, _isDarkMode);
    notifyListeners();
  }

  Future<void> setDarkMode(bool isDark) async {
    _isDarkMode = isDark;
    await _saveSetting(_isDarkModeKey, isDark);
    notifyListeners();
  }

  Future<void> setFontFamily(String? fontFamily) async {
    _fontFamily = fontFamily ?? '';
    await _saveSetting(_fontFamilyKey, _fontFamily);
    notifyListeners();
  }

  Future<void> _saveSetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    
    if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    } else if (value is int) {
      await prefs.setInt(key, value);
    } else if (value is double) {
      await prefs.setDouble(key, value);
    }
  }

  Future<void> resetToDefaults() async {
    _wideLayoutEnabled = false;
    _themeColor = const Color(0xFF2196F3);
    _isDarkMode = false;
    _fontFamily = '';
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_wideLayoutKey);
    await prefs.remove(_themeColorKey);
    await prefs.remove(_isDarkModeKey);
    await prefs.remove(_fontFamilyKey);
    
    notifyListeners();
  }
}
