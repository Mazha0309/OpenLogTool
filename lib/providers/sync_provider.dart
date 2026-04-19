import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

class SyncSettings {
  final String serverUrl;
  final String deviceId;
  final bool syncEnabled;
  final String syncStrategy;
  final String syncMode;
  final int syncIntervalMinutes;
  final DateTime? lastSyncTime;
  final String? token;
  final String? userId;
  final String? theme;

  SyncSettings({
    this.serverUrl = '',
    this.deviceId = '',
    this.syncEnabled = false,
    this.syncStrategy = 'server-wins',
    this.syncMode = 'manual',
    this.syncIntervalMinutes = 5,
    this.lastSyncTime,
    this.token,
    this.userId,
    this.theme = 'light',
  });

  SyncSettings copyWith({
    String? serverUrl,
    String? deviceId,
    bool? syncEnabled,
    String? syncStrategy,
    String? syncMode,
    int? syncIntervalMinutes,
    DateTime? lastSyncTime,
    String? token,
    String? userId,
    String? theme,
  }) {
    return SyncSettings(
      serverUrl: serverUrl ?? this.serverUrl,
      deviceId: deviceId ?? this.deviceId,
      syncEnabled: syncEnabled ?? this.syncEnabled,
      syncStrategy: syncStrategy ?? this.syncStrategy,
      syncMode: syncMode ?? this.syncMode,
      syncIntervalMinutes: syncIntervalMinutes ?? this.syncIntervalMinutes,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      token: token ?? this.token,
      userId: userId ?? this.userId,
      theme: theme ?? this.theme,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'serverUrl': serverUrl,
      'deviceId': deviceId,
      'syncEnabled': syncEnabled,
      'syncStrategy': syncStrategy,
      'syncMode': syncMode,
      'syncIntervalMinutes': syncIntervalMinutes,
      'lastSyncTime': lastSyncTime?.toIso8601String(),
      'token': token,
      'userId': userId,
      'theme': theme,
    };
  }

  factory SyncSettings.fromJson(Map<String, dynamic> json) {
    return SyncSettings(
      serverUrl: json['serverUrl'] ?? '',
      deviceId: json['deviceId'] ?? '',
      syncEnabled: json['syncEnabled'] ?? false,
      syncStrategy: json['syncStrategy'] ?? 'server-wins',
      syncMode: json['syncMode'] ?? 'manual',
      syncIntervalMinutes: json['syncIntervalMinutes'] ?? 5,
      lastSyncTime: json['lastSyncTime'] != null
          ? DateTime.parse(json['lastSyncTime'])
          : null,
      token: json['token'],
      userId: json['userId'],
      theme: json['theme'] ?? 'light',
    );
  }
}

class SyncProvider with ChangeNotifier {
  static const String _syncSettingsKey = 'syncSettings';

  SyncSettings _settings = SyncSettings();
  bool _isSyncing = false;
  String? _lastError;
  bool _isLoggingIn = false;
  Timer? _syncTimer;

  String _getBaseUrl() {
    return _settings.serverUrl.replaceAll(RegExp(r'/$'), '');
  }

  SyncSettings get settings => _settings;
  bool get isSyncing => _isSyncing;
  bool get isLoggingIn => _isLoggingIn;
  String? get lastError => _lastError;
  bool get isConfigured =>
      _settings.serverUrl.isNotEmpty && _settings.deviceId.isNotEmpty;
  bool get isLoggedIn => _settings.token != null && _settings.userId != null;
  String get theme => _settings.theme ?? 'light';

  SyncProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_syncSettingsKey);
    if (jsonStr != null) {
      try {
        _settings = SyncSettings.fromJson(jsonDecode(jsonStr));
        notifyListeners();
      } catch (_) {}
    }
    _updateSyncTimer();
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_syncSettingsKey, json.encode(_settings.toJson()));
    _updateSyncTimer();
  }

  void _updateSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = null;

    if (_settings.syncEnabled && _settings.syncMode == 'interval') {
      _syncTimer = Timer.periodic(
        Duration(minutes: _settings.syncIntervalMinutes),
        (_) => triggerSync(),
      );
    }
  }

  void triggerSync() {
    if (!isConfigured || !isLoggedIn || _isSyncing) return;
    // This method can be called externally for realtime sync
    // The actual sync will be performed by _performSync
  }

  Future<void> setSyncMode(String mode) async {
    _settings = _settings.copyWith(syncMode: mode);
    await _saveSettings();
    notifyListeners();
  }

  Future<void> setSyncIntervalMinutes(int minutes) async {
    _settings = _settings.copyWith(syncIntervalMinutes: minutes);
    await _saveSettings();
    notifyListeners();
  }

  Future<void> setServerUrl(String url) async {
    _settings = _settings.copyWith(serverUrl: url);
    await _saveSettings();
    notifyListeners();
  }

  Future<void> setDeviceId(String id) async {
    _settings = _settings.copyWith(deviceId: id);
    await _saveSettings();
    notifyListeners();
  }

  Future<void> setSyncEnabled(bool enabled) async {
    _settings = _settings.copyWith(syncEnabled: enabled);
    await _saveSettings();
    notifyListeners();
  }

  Future<void> setSyncStrategy(String strategy) async {
    _settings = _settings.copyWith(syncStrategy: strategy);
    await _saveSettings();
    notifyListeners();
  }

  Future<void> updateLastSyncTime() async {
    _settings = _settings.copyWith(lastSyncTime: DateTime.now());
    await _saveSettings();
    notifyListeners();
  }

  Future<bool> login(String username, String password) async {
    if (!isConfigured) return false;

    _isLoggingIn = true;
    _lastError = null;
    notifyListeners();

    try {
      final uri = Uri.parse('${_getBaseUrl()}/api/v1/auth/login');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'username': username, 'password': password}),
      );

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        if (result['success'] == true) {
          _settings = _settings.copyWith(
            token: result['data']['token'],
            userId: result['data']['user']['id'],
            theme: result['data']['user']['theme'] ?? 'light',
          );
          await _saveSettings();
          _isLoggingIn = false;
          notifyListeners();
          return true;
        } else {
          _lastError = result['error']?['message'] ?? '登录失败';
          _isLoggingIn = false;
          notifyListeners();
          return false;
        }
      } else {
        _lastError = '登录失败: ${response.statusCode}';
        _isLoggingIn = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _lastError = '登录失败: $e';
      _isLoggingIn = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    _settings = SyncSettings(
      serverUrl: _settings.serverUrl,
      deviceId: _settings.deviceId,
      syncEnabled: _settings.syncEnabled,
      syncStrategy: _settings.syncStrategy,
      lastSyncTime: _settings.lastSyncTime,
    );
    await _saveSettings();
    notifyListeners();
  }

  Future<bool> changePassword(String oldPassword, String newPassword) async {
    if (!isLoggedIn) return false;

    try {
      final uri = Uri.parse('${_getBaseUrl()}/api/v1/auth/password');
      final response = await http.put(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${_settings.token}',
        },
        body: json.encode({
          'oldPassword': oldPassword,
          'newPassword': newPassword,
        }),
      );

      if (response.statusCode == 200) {
        return true;
      } else {
        _lastError = '修改密码失败: ${response.statusCode}';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _lastError = '修改密码失败: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> setTheme(String theme) async {
    if (!isLoggedIn) {
      _settings = _settings.copyWith(theme: theme);
      await _saveSettings();
      notifyListeners();
      return true;
    }

    try {
      final uri = Uri.parse('${_getBaseUrl()}/api/v1/auth/theme');
      final response = await http.put(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${_settings.token}',
        },
        body: json.encode({'theme': theme}),
      );

      if (response.statusCode == 200) {
        _settings = _settings.copyWith(theme: theme);
        await _saveSettings();
        notifyListeners();
        return true;
      } else {
        _lastError = '设置主题失败: ${response.statusCode}';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _lastError = '设置主题失败: $e';
      notifyListeners();
      return false;
    }
  }

  Future<Map<String, dynamic>?> pushSync(List<Map<String, dynamic>> logs,
      {List<Map<String, dynamic>>? dictionaries,
      List<Map<String, dynamic>>? callsignQthHistory}) async {
    if (!isConfigured) return null;

    _isSyncing = true;
    _lastError = null;
    notifyListeners();

    try {
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };
      if (_settings.token != null) {
        headers['Authorization'] = 'Bearer ${_settings.token}';
      }

      final uri = Uri.parse('${_getBaseUrl()}/api/v1/logs/sync/push');
      final response = await http.post(
        uri,
        headers: headers,
        body: json.encode({
          'logs': logs,
          'dictionaries': dictionaries,
          'callsignQthHistory': callsignQthHistory,
          'deviceId': _settings.deviceId,
        }),
      );

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        await updateLastSyncTime();
        _isSyncing = false;
        notifyListeners();
        return result;
      } else {
        _lastError = '推送失败: ${response.statusCode}';
        _isSyncing = false;
        notifyListeners();
        return null;
      }
    } catch (e) {
      _lastError = '推送失败: $e';
      _isSyncing = false;
      notifyListeners();
      return null;
    }
  }

  Future<Map<String, dynamic>?> pullSync() async {
    if (!isConfigured) return null;

    _isSyncing = true;
    _lastError = null;
    notifyListeners();

    try {
      final headers = <String, String>{};
      if (_settings.token != null) {
        headers['Authorization'] = 'Bearer ${_settings.token}';
      }

      final since = _settings.lastSyncTime?.toIso8601String() ??
          '1970-01-01T00:00:00.000Z';
      final uri = Uri.parse(
          '${_getBaseUrl()}/api/v1/logs/sync/pull?deviceId=${_settings.deviceId}&since=$since');
      final response = await http.get(uri, headers: headers);

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        await updateLastSyncTime();
        _isSyncing = false;
        notifyListeners();
        return result;
      } else {
        _lastError = '拉取失败: ${response.statusCode}';
        _isSyncing = false;
        notifyListeners();
        return null;
      }
    } catch (e) {
      _lastError = '拉取失败: $e';
      _isSyncing = false;
      notifyListeners();
      return null;
    }
  }

  Future<bool> shareData({
    required String toUsername,
    required String shareType,
  }) async {
    if (!isLoggedIn) return false;

    try {
      final uri = Uri.parse('${_getBaseUrl()}/api/v1/sync/share');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${_settings.token}',
        },
        body: json.encode({
          'toUsername': toUsername,
          'shareType': shareType,
        }),
      );

      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>?> getInbox() async {
    if (!isLoggedIn) return null;

    try {
      final uri = Uri.parse('${_getBaseUrl()}/api/v1/sync/inbox');
      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer ${_settings.token}'},
      );

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        return List<Map<String, dynamic>>.from(result['data'] ?? []);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> acceptShare(String shareId) async {
    if (!isLoggedIn) return false;

    try {
      final uri = Uri.parse('${_getBaseUrl()}/api/v1/sync/accept/$shareId');
      final response = await http.post(
        uri,
        headers: {'Authorization': 'Bearer ${_settings.token}'},
      );

      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> testConnection() async {
    if (_settings.serverUrl.isEmpty) return false;

    try {
      final uri = Uri.parse('${_getBaseUrl()}/api/v1/health');
      final response = await http.get(uri).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
