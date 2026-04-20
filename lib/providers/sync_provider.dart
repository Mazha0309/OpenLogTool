import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:openlogtool/database/database_helper.dart';
import 'package:openlogtool/models/dictionary_item.dart';
import 'package:openlogtool/models/log_entry.dart';
import 'package:openlogtool/models/sync_callsign_qth_record.dart';
import 'package:openlogtool/models/sync_history_record.dart';

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
    Object? token = _syncSettingsUnset,
    Object? userId = _syncSettingsUnset,
    Object? theme = _syncSettingsUnset,
  }) {
    return SyncSettings(
      serverUrl: serverUrl ?? this.serverUrl,
      deviceId: deviceId ?? this.deviceId,
      syncEnabled: syncEnabled ?? this.syncEnabled,
      syncStrategy: syncStrategy ?? this.syncStrategy,
      syncMode: syncMode ?? this.syncMode,
      syncIntervalMinutes: syncIntervalMinutes ?? this.syncIntervalMinutes,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      token: identical(token, _syncSettingsUnset) ? this.token : token as String?,
      userId: identical(userId, _syncSettingsUnset) ? this.userId : userId as String?,
      theme: identical(theme, _syncSettingsUnset) ? this.theme : theme as String?,
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

const Object _syncSettingsUnset = Object();

class SyncProvider with ChangeNotifier {
  static const String _syncSettingsKey = 'syncSettings';

  SyncSettings _settings = SyncSettings();
  bool _isSyncing = false;
  String? _lastError;
  bool _isLoggingIn = false;
  Timer? _syncTimer;
  bool _hasPendingSyncRequest = false;

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
    _scheduleAutoSyncOnce();
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

  bool get _shouldAutoSync =>
      _settings.syncEnabled &&
      isConfigured &&
      isLoggedIn &&
      (_settings.syncMode == 'realtime' || _settings.syncMode == 'interval');

  void _scheduleAutoSyncOnce() {
    if (_shouldAutoSync && !_isSyncing) {
      unawaited(runBidirectionalSync());
    }
  }

  void triggerSync() {
    if (!isConfigured || !isLoggedIn || _isSyncing) return;
    unawaited(runBidirectionalSync());
  }

  Future<bool> triggerSyncAndWait() async {
    return runBidirectionalSync();
  }

  String _lastSyncAtValue() {
    return _settings.lastSyncTime?.toUtc().toIso8601String() ??
        '1970-01-01T00:00:00.000Z';
  }

  Map<String, dynamic> _normalizeDictionaryPayload(
      Map<String, dynamic> row, String type) {
    final item = DictionaryItem.fromMap({...row, 'type': type});
    return {
      'id': item.syncId,
      'raw': item.raw,
      'pinyin': item.pinyin,
      'abbreviation': item.abbreviation,
      'type': item.type,
      'createdAt': item.createdAt,
      'updatedAt': item.updatedAt,
      'deletedAt': item.deletedAt,
    };
  }

  Map<String, dynamic> _normalizeHistoryPayload(Map<String, dynamic> row) {
    final item = SyncHistoryRecord.fromMap(row);
    return {
      'id': item.syncId,
      'name': item.name,
      'logsData': item.logsData,
      'logCount': item.logCount,
      'createdAt': item.createdAt,
      'updatedAt': item.updatedAt,
      'deletedAt': item.deletedAt,
    };
  }

  Map<String, dynamic> _normalizeCallsignQthPayload(Map<String, dynamic> row) {
    final item = SyncCallsignQthRecord.fromMap(row);
    return {
      'id': item.syncId,
      'callsign': item.callsign,
      'qth': item.qth,
      'recordedAt': item.recordedAt,
      'createdAt': item.createdAt,
      'updatedAt': item.updatedAt,
      'deletedAt': item.deletedAt,
    };
  }

  Map<String, dynamic> _normalizeIncomingSyncItem(Map<String, dynamic> row) {
    final id = row['id'];
    if (id == null) {
      return row;
    }
    return {
      ...row,
      'syncId': row['syncId'] ?? id,
      'sync_id': row['sync_id'] ?? id,
    };
  }

  Future<Map<String, dynamic>> _collectBidirectionalPayload() async {
    final db = DatabaseHelper();
    final since = _lastSyncAtValue();

    final logs = await db.getLogsChangedSince(since);
    final deviceDicts = await db.getDictionaryChangedSince('device_dictionary', since);
    final antennaDicts = await db.getDictionaryChangedSince('antenna_dictionary', since);
    final qthDicts = await db.getDictionaryChangedSince('qth_dictionary', since);
    final callsignDicts = await db.getDictionaryChangedSince('callsign_dictionary', since);
    final history = await db.getHistoryChangedSince(since);
    final callsignQthHistory = await db.getCallsignQthHistoryChangedSince(since);

    return {
      'logs': logs.map((row) => LogEntry.fromMap(row).toJson()).toList(),
      'dictionaries': [
        ...deviceDicts.map((row) => _normalizeDictionaryPayload(row, 'device')),
        ...antennaDicts.map((row) => _normalizeDictionaryPayload(row, 'antenna')),
        ...qthDicts.map((row) => _normalizeDictionaryPayload(row, 'qth')),
        ...callsignDicts.map((row) => _normalizeDictionaryPayload(row, 'callsign')),
      ],
      'callsignQthHistory': callsignQthHistory
          .map((row) => _normalizeCallsignQthPayload(row))
          .toList(),
      'history': history.map((row) => _normalizeHistoryPayload(row)).toList(),
    };
  }

  Future<void> _applyBidirectionalChanges(Map<String, dynamic> changes) async {
    final db = DatabaseHelper();

    final logs = List<Map<String, dynamic>>.from(changes['logs'] ?? const []);
    for (final item in logs) {
      if (item['deletedAt'] != null) {
        await db.softDeleteLog(item['id'].toString(), item['deletedAt'].toString());
      } else {
        await db.upsertLogFromSync(item);
      }
    }

    final dictionaries =
        List<Map<String, dynamic>>.from(changes['dictionaries'] ?? const []);
    for (final item in dictionaries) {
      final normalized = _normalizeIncomingSyncItem(item);
      final type = normalized['type']?.toString() ?? '';
      final tableName = switch (type) {
        'device' => 'device_dictionary',
        'antenna' => 'antenna_dictionary',
        'qth' => 'qth_dictionary',
        'callsign' => 'callsign_dictionary',
        _ => '',
      };
      if (tableName.isEmpty) continue;
      if (normalized['deletedAt'] != null) {
        await db.softDeleteDictionaryItem(
            tableName, normalized['id'].toString(), normalized['deletedAt'].toString());
      } else {
        await db.upsertDictionaryItemFromSync(tableName, normalized);
      }
    }

    final history = List<Map<String, dynamic>>.from(changes['history'] ?? const []);
    for (final item in history) {
      final normalized = _normalizeIncomingSyncItem(item);
      if (normalized['deletedAt'] != null) {
        await db.softDeleteHistory(
            normalized['id'].toString(), normalized['deletedAt'].toString());
      } else {
        await db.upsertHistoryFromSync(normalized);
      }
    }

    final callsignQthHistory =
        List<Map<String, dynamic>>.from(changes['callsignQthHistory'] ?? const []);
    for (final item in callsignQthHistory) {
      final normalized = _normalizeIncomingSyncItem(item);
      if (normalized['deletedAt'] != null) {
        await db.softDeleteCallsignQthHistory(
            normalized['id'].toString(), normalized['deletedAt'].toString());
      } else {
        await db.upsertCallsignQthHistoryFromSync(normalized);
      }
    }
  }

  Future<bool> runBidirectionalSync() async {
    if (!isConfigured || !isLoggedIn) return false;
    if (_isSyncing) {
      _hasPendingSyncRequest = true;
      return false;
    }

    _isSyncing = true;
    _lastError = null;
    notifyListeners();

    try {
      final payload = await _collectBidirectionalPayload();
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (_settings.token != null) {
        headers['Authorization'] = 'Bearer ${_settings.token}';
      }

      final uri = Uri.parse('${_getBaseUrl()}/api/v1/logs/sync/bidirectional');
      final response = await http.post(
        uri,
        headers: headers,
        body: json.encode({
          'deviceId': _settings.deviceId,
          'lastSyncAt': _lastSyncAtValue(),
          'payload': payload,
        }),
      );

      if (response.statusCode != 200) {
        _lastError = '双向同步失败: ${response.statusCode}';
        return false;
      }

      final result = json.decode(response.body) as Map<String, dynamic>;
      if (result['success'] != true) {
        _lastError = result['error']?['message']?.toString() ?? '双向同步失败';
        return false;
      }

      await _applyBidirectionalChanges(
          Map<String, dynamic>.from(result['changes'] ?? const {}));

      final serverTimeValue = result['serverTime']?.toString();
      final serverTime =
          serverTimeValue != null ? DateTime.tryParse(serverTimeValue)?.toUtc() : null;
      _settings = _settings.copyWith(
        lastSyncTime: serverTime ?? DateTime.now().toUtc(),
      );
      await _saveSettings();
      notifyListeners();
      return true;
    } catch (e) {
      _lastError = '双向同步失败: $e';
      return false;
    } finally {
      _isSyncing = false;
      notifyListeners();
      if (_hasPendingSyncRequest && isConfigured && isLoggedIn) {
        _hasPendingSyncRequest = false;
        unawaited(runBidirectionalSync());
      }
    }
  }

  Future<void> setSyncMode(String mode) async {
    _settings = _settings.copyWith(syncMode: mode);
    await _saveSettings();
    notifyListeners();
    _scheduleAutoSyncOnce();
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
    _scheduleAutoSyncOnce();
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

  Future<Map<String, dynamic>?> _fetchCurrentUser(String token) async {
    final uri = Uri.parse('${_getBaseUrl()}/api/v1/auth/me');
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode != 200) {
      return null;
    }

    final result = json.decode(response.body) as Map<String, dynamic>;
    if (result['success'] != true || result['data'] == null) {
      return null;
    }

    return Map<String, dynamic>.from(result['data']);
  }

  Future<void> _clearAuthState() async {
    _settings = _settings.copyWith(
      token: null,
      userId: null,
      lastSyncTime: null,
    );
    await _saveSettings();
  }

  Future<bool> validateCurrentLogin() async {
    if (!isLoggedIn || _settings.token == null) {
      return false;
    }

    try {
      final user = await _fetchCurrentUser(_settings.token!);
      if (user == null) {
        await _clearAuthState();
        notifyListeners();
        return false;
      }

      final normalizedUserId = user['id']?.toString();
      final normalizedTheme = user['theme']?.toString() ?? _settings.theme;
      if (normalizedUserId != _settings.userId || normalizedTheme != _settings.theme) {
        _settings = _settings.copyWith(
          userId: normalizedUserId,
          theme: normalizedTheme,
        );
        await _saveSettings();
        notifyListeners();
      }

      return true;
    } catch (_) {
      await _clearAuthState();
      notifyListeners();
      return false;
    }
  }

  Future<bool> login(String username, String password) async {
    if (!isConfigured) return false;

    _isLoggingIn = true;
    _lastError = null;
    notifyListeners();

    try {
      await _clearAuthState();
      final uri = Uri.parse('${_getBaseUrl()}/api/v1/auth/login');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'username': username, 'password': password}),
      );

      if (response.statusCode == 200) {
        final result = json.decode(response.body) as Map<String, dynamic>;
        if (result['success'] == true) {
          final token = result['data']['token']?.toString();
          if (token == null || token.isEmpty) {
            _lastError = '登录失败: 服务端未返回有效令牌';
            _isLoggingIn = false;
            notifyListeners();
            return false;
          }

          final user = await _fetchCurrentUser(token);
          if (user == null) {
            _lastError = '登录失败: 登录校验未通过';
            await _clearAuthState();
            _isLoggingIn = false;
            notifyListeners();
            return false;
          }

          _settings = _settings.copyWith(
            token: token,
            userId: user['id']?.toString(),
            theme: user['theme']?.toString() ?? 'light',
          );
          await _saveSettings();
          _isLoggingIn = false;
          notifyListeners();
          _scheduleAutoSyncOnce();
          return true;
        } else {
          _lastError = result['error']?['message'] ?? '登录失败';
          await _clearAuthState();
          _isLoggingIn = false;
          notifyListeners();
          return false;
        }
      } else {
        _lastError = '登录失败: ${response.statusCode}';
        await _clearAuthState();
        _isLoggingIn = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _lastError = '登录失败: $e';
      await _clearAuthState();
      _isLoggingIn = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    await _clearAuthState();
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
      final ok = response.statusCode == 200;
      if (ok) {
        _scheduleAutoSyncOnce();
      }
      return ok;
    } catch (_) {
      return false;
    }
  }
}
