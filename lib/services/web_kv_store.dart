import 'package:idb_shim/idb.dart' as idb;
import 'package:idb_shim/idb_browser.dart';
import 'key_value_store.dart';

/// IndexedDB 实现（Web 端），库名 openlogtool_settings，objectStore kv。
///
/// 所有值以字符串形式存储（bool/int 序列化为字符串），读取时按需还原，
/// 与 SharedPreferences 的存储格式保持一致。
class WebKeyValueStore implements KeyValueStore {
  WebKeyValueStore._(this._db);
  final idb.Database _db;

  static const _dbName = 'openlogtool_settings';
  static const _storeName = 'kv';

  static Future<WebKeyValueStore> open() async {
    final db = await idbFactoryBrowser.open(
      _dbName,
      version: 1,
      onUpgradeNeeded: (event) {
        final database = event.database;
        if (!database.objectStoreNames.contains(_storeName)) {
          database.createObjectStore(_storeName, keyPath: 'k');
        }
      },
    );
    return WebKeyValueStore._(db);
  }

  idb.ObjectStore _store([String mode = idb.idbModeReadOnly]) =>
      _db.transaction(_storeName, mode).objectStore(_storeName);

  Future<Map<String, dynamic>?> _getRecord(String key) async {
    final record = await _store().getObject(key);
    if (record == null) return null;
    return (record as Map).cast<String, dynamic>();
  }

  @override
  Future<String?> getString(String key) async {
    final record = await _getRecord(key);
    return record == null ? null : record['v'] as String?;
  }

  @override
  Future<bool> getBool(String key, {bool defaultValue = false}) async {
    final value = await getString(key);
    return value == null ? defaultValue : value == 'true';
  }

  @override
  Future<int?> getInt(String key) async {
    final value = await getString(key);
    return value == null ? null : int.tryParse(value);
  }

  @override
  Future<bool> setString(String key, String value) async {
    final store = _store(idb.idbModeReadWrite);
    await store.put({'k': key, 'v': value});
    return true;
  }

  @override
  Future<bool> setBool(String key, bool value) =>
      setString(key, value.toString());

  @override
  Future<bool> setInt(String key, int value) =>
      setString(key, value.toString());

  @override
  Future<bool> setDouble(String key, double value) =>
      setString(key, value.toString());

  @override
  Future<bool> remove(String key) async {
    final store = _store(idb.idbModeReadWrite);
    await store.delete(key);
    return true;
  }

  @override
  Future<bool> containsKey(String key) async {
    return (await _getRecord(key)) != null;
  }

  @override
  Future<Set<String>> getKeys() async {
    final keys = await _store().getAllKeys();
    return keys.map((key) => key as String).toSet();
  }

  @override
  Future<bool> clear() async {
    final store = _store(idb.idbModeReadWrite);
    await store.clear();
    return true;
  }
}
