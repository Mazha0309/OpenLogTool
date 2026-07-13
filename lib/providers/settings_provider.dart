import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openlogtool/config/app_config.dart';
import 'package:openlogtool/models/controller_display.dart';
import 'package:openlogtool/models/export_settings.dart';

class SettingsProvider with ChangeNotifier {
  static const String _wideLayoutKey = 'wideLayoutEnabled';
  static const String _themeColorKey = 'themeColor';
  static const String _isDarkModeKey = 'isDarkMode';
  static const String _fontFamilyKey = 'fontFamily';
  static const String _exportSettingsKey = 'exportSettings';
  static const String _callSignQthLinkKey = 'callSignQthLinkEnabled';
  static const String _paginationEnabledKey = 'paginationEnabled';
  static const String _duplicateCallsignWarningKey =
      'duplicateCallsignWarningEnabled';
  static const String _controllerDeviceModeEnabledKey =
      'controllerDeviceModeEnabled';
  static const String _primarySidebarExpandedKey = 'primarySidebarExpanded';

  bool _wideLayoutEnabled = false;
  Color _themeColor = const Color(0xFF2196F3);
  bool _isDarkMode = false;
  String _fontFamily = '';
  List<String> _availableFonts = [];
  ExportSettings _exportSettings = ExportSettings();
  bool _callSignQthLinkEnabled = true;
  bool _paginationEnabled = false;
  bool _duplicateCallsignWarningEnabled = true;
  bool _controllerDeviceModeEnabled = false;
  bool _primarySidebarExpanded = true;
  ControllerDisplayPreferences _controllerDisplayPreferences =
      const ControllerDisplayPreferences();

  bool get wideLayoutEnabled => _wideLayoutEnabled;
  Color get themeColor => _themeColor;
  bool get isDarkMode => _isDarkMode;
  String? get fontFamily => _fontFamily.isEmpty ? null : _fontFamily;
  List<String> get availableFonts => _availableFonts;
  ExportSettings get exportSettings => _exportSettings;
  bool get callSignQthLinkEnabled => _callSignQthLinkEnabled;
  bool get paginationEnabled => _paginationEnabled;
  bool get duplicateCallsignWarningEnabled => _duplicateCallsignWarningEnabled;
  bool get controllerDeviceModeEnabled => _controllerDeviceModeEnabled;
  bool get primarySidebarExpanded => _primarySidebarExpanded;
  ControllerDisplayPreferences get controllerDisplayPreferences =>
      _controllerDisplayPreferences;

  SettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _availableFonts = await AppConfig.getSystemFonts();

    final prefs = await SharedPreferences.getInstance();

    _wideLayoutEnabled = prefs.getBool(_wideLayoutKey) ?? false;
    _isDarkMode = prefs.getBool(_isDarkModeKey) ?? false;
    _fontFamily = prefs.getString(_fontFamilyKey) ?? '';

    final colorValue = prefs.getInt(_themeColorKey);
    if (colorValue != null) {
      _themeColor = Color(colorValue);
    }

    final exportSettingsJson = prefs.getString(_exportSettingsKey);
    if (exportSettingsJson != null) {
      try {
        _exportSettings =
            ExportSettings.fromJson(json.decode(exportSettingsJson));
      } catch (_) {
        _exportSettings = ExportSettings();
      }
    }

    _callSignQthLinkEnabled = prefs.getBool(_callSignQthLinkKey) ?? true;
    _paginationEnabled = prefs.getBool(_paginationEnabledKey) ?? false;
    _duplicateCallsignWarningEnabled =
        prefs.getBool(_duplicateCallsignWarningKey) ?? true;
    _controllerDeviceModeEnabled =
        prefs.getBool(_controllerDeviceModeEnabledKey) ?? false;
    _primarySidebarExpanded = prefs.getBool(_primarySidebarExpandedKey) ?? true;
    final controllerPreferencesJson =
        prefs.getString(controllerDisplayPreferencesStorageKey);
    if (controllerPreferencesJson != null) {
      try {
        _controllerDisplayPreferences = ControllerDisplayPreferences.fromJson(
          json.decode(controllerPreferencesJson),
        );
      } catch (_) {
        _controllerDisplayPreferences = const ControllerDisplayPreferences();
      }
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
    await _saveSetting(_themeColorKey, color.toARGB32());
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

  Future<void> setCallSignQthLink(bool enabled) async {
    _callSignQthLinkEnabled = enabled;
    await _saveSetting(_callSignQthLinkKey, enabled);
    notifyListeners();
  }

  Future<void> setPaginationEnabled(bool enabled) async {
    _paginationEnabled = enabled;
    await _saveSetting(_paginationEnabledKey, enabled);
    notifyListeners();
  }

  Future<void> setDuplicateCallsignWarningEnabled(bool enabled) async {
    _duplicateCallsignWarningEnabled = enabled;
    await _saveSetting(_duplicateCallsignWarningKey, enabled);
    notifyListeners();
  }

  Future<void> setControllerDeviceModeEnabled(bool enabled) async {
    _controllerDeviceModeEnabled = enabled;
    await _saveSetting(_controllerDeviceModeEnabledKey, enabled);
    notifyListeners();
  }

  Future<void> setPrimarySidebarExpanded(bool expanded) async {
    if (_primarySidebarExpanded == expanded) return;
    _primarySidebarExpanded = expanded;
    notifyListeners();
    await _saveSetting(_primarySidebarExpandedKey, expanded);
  }

  Future<void> setControllerDisplayPreferences(
    ControllerDisplayPreferences preferences,
  ) async {
    _controllerDisplayPreferences = preferences;
    await _saveSetting(
      controllerDisplayPreferencesStorageKey,
      json.encode(preferences.toJson()),
    );
    notifyListeners();
  }

  Future<void> updateExportSettings(ExportSettings settings) async {
    _exportSettings = settings;
    await _saveSetting(_exportSettingsKey, json.encode(settings.toJson()));
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
    _exportSettings = ExportSettings();
    _callSignQthLinkEnabled = true;
    _controllerDeviceModeEnabled = false;
    _primarySidebarExpanded = true;
    _duplicateCallsignWarningEnabled = true;
    _controllerDisplayPreferences = const ControllerDisplayPreferences();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_wideLayoutKey);
    await prefs.remove(_themeColorKey);
    await prefs.remove(_isDarkModeKey);
    await prefs.remove(_fontFamilyKey);
    await prefs.remove(_exportSettingsKey);
    await prefs.remove(_callSignQthLinkKey);
    await prefs.remove(_controllerDeviceModeEnabledKey);
    await prefs.remove(_primarySidebarExpandedKey);
    await prefs.remove(_duplicateCallsignWarningKey);
    await prefs.remove(controllerDisplayPreferencesStorageKey);

    notifyListeners();
  }
}
