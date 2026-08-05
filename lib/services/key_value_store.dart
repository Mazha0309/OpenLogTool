import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'web_kv_store.dart';

/// 跨平台键值存储抽象：桌面=SharedPreferences，Web=IndexedDB。
///
/// 方法签名与 SharedPreferences 保持一致（setter 返回 Future<bool> 表示
/// 是否写入成功），使现有调用点无需修改即可切换存储后端。
abstract class KeyValueStore {
  Future<String?> getString(String key);
  Future<bool> getBool(String key, {bool defaultValue = false});
  Future<int?> getInt(String key);
  Future<bool> setString(String key, String value);
  Future<bool> setBool(String key, bool value);
  Future<bool> setInt(String key, int value);
  Future<bool> setDouble(String key, double value);
  Future<bool> remove(String key);
  Future<bool> containsKey(String key);
  Future<Set<String>> getKeys();
  Future<bool> clear();
}

/// SharedPreferences 实现（桌面端）。
class PrefsKeyValueStore implements KeyValueStore {
  PrefsKeyValueStore(this._prefs);
  final SharedPreferences _prefs;

  @override
  Future<String?> getString(String key) async => _prefs.getString(key);

  @override
  Future<bool> getBool(String key, {bool defaultValue = false}) async =>
      _prefs.getBool(key) ?? defaultValue;

  @override
  Future<int?> getInt(String key) async => _prefs.getInt(key);

  @override
  Future<bool> setString(String key, String value) =>
      _prefs.setString(key, value);

  @override
  Future<bool> setBool(String key, bool value) => _prefs.setBool(key, value);

  @override
  Future<bool> setInt(String key, int value) => _prefs.setInt(key, value);

  @override
  Future<bool> setDouble(String key, double value) =>
      _prefs.setDouble(key, value);

  @override
  Future<bool> remove(String key) => _prefs.remove(key);

  @override
  Future<bool> containsKey(String key) async => _prefs.containsKey(key);

  @override
  Future<Set<String>> getKeys() async => _prefs.getKeys();

  @override
  Future<bool> clear() => _prefs.clear();
}

/// 全局键值存储实例；Web 返回 IndexedDB 实现，其他平台 SharedPreferences。
Future<KeyValueStore> openKeyValueStore() async {
  if (kIsWeb) {
    return WebKeyValueStore.open();
  }
  return PrefsKeyValueStore(await SharedPreferences.getInstance());
}

/// 一次性迁移：把 localStorage（SharedPreferences）已有数据拷贝到 IndexedDB。
/// 在 Web 上由启动流程调用一次；成功后会写入完成标记，避免重复拷贝，也防止
/// 之后被删除的 key 被 localStorage 的旧值复活。失败不影响启动（下次再试）。
Future<void> migrateLegacyLocalStorage(KeyValueStore store) async {
  if (!kIsWeb) return;
  try {
    if (await store.getBool(_migrationCompleteKey)) return;
    final legacy = await SharedPreferences.getInstance();
    final keys = legacy.getKeys();
    for (final key in keys) {
      if (await store.getString(key) != null) continue;
      final s = legacy.getString(key);
      if (s != null) {
        await store.setString(key, s);
        continue;
      }
      final b = legacy.getBool(key);
      if (b != null) {
        await store.setBool(key, b);
        continue;
      }
      final i = legacy.getInt(key);
      if (i != null) {
        await store.setInt(key, i);
        continue;
      }
      final d = legacy.getDouble(key);
      if (d != null) {
        await store.setDouble(key, d);
      }
    }
    await store.setBool(_migrationCompleteKey, true);
  } catch (e) {
    debugPrint('legacy localStorage migration failed: $e');
  }
}

const _migrationCompleteKey = 'openlogtool.kv.migration_complete.v1';
