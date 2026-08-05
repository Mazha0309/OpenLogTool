import 'package:flutter/material.dart';
import 'package:openlogtool/services/key_value_store.dart';

class ThemeProvider with ChangeNotifier {
  bool _isDarkMode = false;

  bool get isDarkMode => _isDarkMode;

  ThemeProvider() {
    _loadThemePreference();
  }

  Future<void> _loadThemePreference() async {
    final prefs = await openKeyValueStore();
    _isDarkMode = await prefs.getBool('darkMode');
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    _isDarkMode = !_isDarkMode;
    final prefs = await openKeyValueStore();
    await prefs.setBool('darkMode', _isDarkMode);
    notifyListeners();
  }
}
