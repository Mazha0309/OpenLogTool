import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider with ChangeNotifier {
  static const String _wideLayoutKey = 'wideLayoutEnabled';
  static const String _themeColorKey = 'themeColor';
  static const String _isDarkModeKey = 'isDarkMode';

  bool _wideLayoutEnabled = false;
  Color _themeColor = const Color(0xFF2196F3); // 默认淡蓝色
  bool _isDarkMode = false;

  bool get wideLayoutEnabled => _wideLayoutEnabled;
  Color get themeColor => _themeColor;
  bool get isDarkMode => _isDarkMode;

  SettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    _wideLayoutEnabled = prefs.getBool(_wideLayoutKey) ?? false;
    _isDarkMode = prefs.getBool(_isDarkModeKey) ?? false;
    
    // 加载主题色
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
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_wideLayoutKey);
    await prefs.remove(_themeColorKey);
    await prefs.remove(_isDarkModeKey);
    
    notifyListeners();
  }
}
