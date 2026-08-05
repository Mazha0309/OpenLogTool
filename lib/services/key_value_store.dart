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
  Future<double?> getDouble(String key);
  Future<Object?> get(String key);
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
  Future<double?> getDouble(String key) async => _prefs.getDouble(key);

  @override
  Future<Object?> get(String key) async => _prefs.get(key);

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
    await migrateInto(
        store, PrefsKeyValueStore(await SharedPreferences.getInstance()));
    await store.setBool(_migrationCompleteKey, true);
  } catch (e) {
    debugPrint('legacy localStorage migration failed: $e');
  }
}

/// 迁移主体（可测试）：把 [legacy] 中 [store] 尚不存在的 key 拷贝过去。
/// 单独抽出以便测试直接调用，跳过 kIsWeb 的编译期短路。
/// 按值的运行时类型分发：SharedPreferences 的 typed getter（如 getString）
/// 对类型不匹配的 key 会抛异常，因此先经 get() 读取原始值再按类型写入。
Future<void> migrateInto(KeyValueStore store, KeyValueStore legacy) async {
  for (final key in await legacy.getKeys()) {
    if (await store.getString(key) != null) continue;
    final raw = await legacy.get(key);
    if (raw is String) {
      await store.setString(key, raw);
    } else if (raw is bool) {
      await store.setBool(key, raw);
    } else if (raw is int) {
      await store.setInt(key, raw);
    } else if (raw is double) {
      await store.setDouble(key, raw);
    }
  }
}

const _migrationCompleteKey = 'openlogtool.kv.migration_complete.v1';
