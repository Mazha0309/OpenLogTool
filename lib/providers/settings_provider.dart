import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openlogtool/config/app_config.dart';
import 'package:openlogtool/models/controller_display.dart';
import 'package:openlogtool/models/export_settings.dart';

enum AppLocalePreference { system, simplifiedChinese, english }

class SettingsProvider with ChangeNotifier {
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
  static const String _limitWorkbenchWidthKey = 'limitWorkbenchWidth';
  static const String _appLocalePreferenceKey = 'appLocalePreference';

  Color _themeColor = const Color(0xFF2196F3);
  bool _isDarkMode = false;
  String _fontFamily = '';
  List<String> _availableFonts = [];
  ExportSettings _exportSettings = ExportSettings();
  bool _callSignQthLinkEnabled = true;
  bool _paginationEnabled = true;
  bool _duplicateCallsignWarningEnabled = true;
  bool _controllerDeviceModeEnabled = false;
  bool _primarySidebarExpanded = true;
  bool _limitWorkbenchWidth = true;
  AppLocalePreference _appLocalePreference = AppLocalePreference.system;
  ControllerDisplayPreferences _controllerDisplayPreferences =
      const ControllerDisplayPreferences();
  final Future<SharedPreferences> Function() _preferencesLoader;
  final Future<List<String>> Function() _systemFontsLoader;
  var _localePreferenceRevision = 0;
  var _disposed = false;

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
  bool get limitWorkbenchWidth => _limitWorkbenchWidth;
  AppLocalePreference get appLocalePreference => _appLocalePreference;
  Locale? get locale => switch (_appLocalePreference) {
        AppLocalePreference.system => null,
        AppLocalePreference.simplifiedChinese => const Locale('zh', 'CN'),
        AppLocalePreference.english => const Locale('en', 'US'),
      };
  ControllerDisplayPreferences get controllerDisplayPreferences =>
      _controllerDisplayPreferences;

  SettingsProvider({
    Future<SharedPreferences> Function()? preferencesLoader,
    Future<List<String>> Function()? systemFontsLoader,
  })  : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance,
        _systemFontsLoader = systemFontsLoader ?? AppConfig.getSystemFonts {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final localePreferenceRevision = _localePreferenceRevision;
    final prefs = await _preferencesLoader();
    if (_disposed) return;

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
    _paginationEnabled = prefs.getBool(_paginationEnabledKey) ?? true;
    _duplicateCallsignWarningEnabled =
        prefs.getBool(_duplicateCallsignWarningKey) ?? true;
    _controllerDeviceModeEnabled =
        prefs.getBool(_controllerDeviceModeEnabledKey) ?? false;
    _primarySidebarExpanded = prefs.getBool(_primarySidebarExpandedKey) ?? true;
    _limitWorkbenchWidth = prefs.getBool(_limitWorkbenchWidthKey) ?? true;
    if (_localePreferenceRevision == localePreferenceRevision) {
      final storedLocalePreference = prefs.getString(_appLocalePreferenceKey);
      _appLocalePreference = AppLocalePreference.values.firstWhere(
        (preference) => preference.name == storedLocalePreference,
        orElse: () => AppLocalePreference.system,
      );
    }
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

    final availableFonts = await _systemFontsLoader();
    if (_disposed) return;
    _availableFonts = availableFonts;
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
    final normalized = fontFamily?.trim() ?? '';
    if (_fontFamily == normalized) return;
    _fontFamily = normalized;
    // Apply the selected font immediately. Persisting first made the picker
    // feel unresponsive, especially on slower desktop storage.
    notifyListeners();
    await _saveSetting(_fontFamilyKey, _fontFamily);
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

  Future<void> setLimitWorkbenchWidth(bool enabled) async {
    if (_limitWorkbenchWidth == enabled) return;
    _limitWorkbenchWidth = enabled;
    notifyListeners();
    await _saveSetting(_limitWorkbenchWidthKey, enabled);
  }

  Future<void> setAppLocalePreference(
    AppLocalePreference preference,
  ) async {
    _localePreferenceRevision += 1;
    _appLocalePreference = preference;
    notifyListeners();
    await _saveSetting(_appLocalePreferenceKey, preference.name);
  }

  Future<void> setControllerDisplayPreferences(
    ControllerDisplayPreferences preferences,
  ) async {
    _controllerDisplayPreferences = preferences;
    notifyListeners();
    await _saveSetting(
      controllerDisplayPreferencesStorageKey,
      json.encode(preferences.toJson()),
    );
  }

  Future<void> updateExportSettings(ExportSettings settings) async {
    _exportSettings = settings;
    await _saveSetting(_exportSettingsKey, json.encode(settings.toJson()));
    notifyListeners();
  }

  Future<void> _saveSetting(String key, dynamic value) async {
    final prefs = await _preferencesLoader();

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
    _localePreferenceRevision += 1;
    _themeColor = const Color(0xFF2196F3);
    _isDarkMode = false;
    _fontFamily = '';
    _exportSettings = ExportSettings();
    _callSignQthLinkEnabled = true;
    _paginationEnabled = true;
    _controllerDeviceModeEnabled = false;
    _primarySidebarExpanded = true;
    _limitWorkbenchWidth = true;
    _appLocalePreference = AppLocalePreference.system;
    _duplicateCallsignWarningEnabled = true;
    _controllerDisplayPreferences = const ControllerDisplayPreferences();

    final prefs = await _preferencesLoader();
    await prefs.remove(_themeColorKey);
    await prefs.remove(_isDarkModeKey);
    await prefs.remove(_fontFamilyKey);
    await prefs.remove(_exportSettingsKey);
    await prefs.remove(_callSignQthLinkKey);
    await prefs.remove(_paginationEnabledKey);
    await prefs.remove(_controllerDeviceModeEnabledKey);
    await prefs.remove(_primarySidebarExpandedKey);
    await prefs.remove(_limitWorkbenchWidthKey);
    await prefs.remove(_appLocalePreferenceKey);
    await prefs.remove(_duplicateCallsignWarningKey);
    await prefs.remove(controllerDisplayPreferencesStorageKey);

    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
