import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:openlogtool/src/bridge/rust_api.dart';
import 'package:openlogtool/src/bridge/models/dict_item.dart' as bridge;
import 'package:openlogtool/models/dictionary_item.dart';

class DictionaryProvider with ChangeNotifier {
  bool _disposed = false;
  List<DictionaryItem> _deviceDict = [];
  List<DictionaryItem> _antennaDict = [];
  List<DictionaryItem> _callsignDict = [];
  List<DictionaryItem> _qthDict = [];
  Future<void> Function()? _onDictionaryChanged;

  List<DictionaryItem> get deviceDict => _deviceDict;
  List<DictionaryItem> get antennaDict => _antennaDict;
  List<DictionaryItem> get callsignDict => _callsignDict;
  List<DictionaryItem> get qthDict => _qthDict;

  void setOnDictionaryChanged(Future<void> Function()? callback) {
    _onDictionaryChanged = callback;
  }

  Future<void> _notifyDictionaryChanged() async {
    if (_onDictionaryChanged != null) {
      unawaited(_onDictionaryChanged!());
    }
  }

  DictionaryProvider() {
    scheduleMicrotask(_loadDictionaries);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  Future<void> _loadDictionaries() async {
    try {
      _deviceDict = await _getDictItems('device_dictionary');
      _antennaDict = await _getDictItems('antenna_dictionary');
      _callsignDict = await _getDictItems('callsign_dictionary');
      _qthDict = await _getDictItems('qth_dictionary');

      if (_deviceDict.isEmpty && _antennaDict.isEmpty && _qthDict.isEmpty) {
        await _seedInitialDictionaries();
        _deviceDict = await _getDictItems('device_dictionary');
        _antennaDict = await _getDictItems('antenna_dictionary');
        _qthDict = await _getDictItems('qth_dictionary');
      }
    } catch (e, st) {
      debugPrint('[DictionaryProvider] _loadDictionaries failed: $e\n$st');
    }
    _safeNotify();
  }

  Future<List<DictionaryItem>> _getDictItems(String dictType) async {
    final items = await RustApi.getDictItems(dictType: dictType);
    return items.map(_toOldDictItem).toList();
  }

  Future<void> _seedInitialDictionaries() async {
    await _seedFromAsset('device_dictionary', 'assets/dictionaries/device.json');
    await _seedFromAsset('antenna_dictionary', 'assets/dictionaries/antenna.json');
    await _seedFromAsset('qth_dictionary', 'assets/dictionaries/qth.json');
  }

  Future<void> _seedFromAsset(String dictType, String assetPath) async {
    try {
      final jsonString = await rootBundle.loadString(assetPath);
      final items = _parseDictItemsJson(jsonString);
      for (final item in items) {
        await RustApi.addDictItem(dictType: dictType, raw: item);
      }
    } catch (e, st) {
      debugPrint('[DictionaryProvider] seed from $assetPath failed: $e\n$st');
    }
  }

  /// 解析词库 JSON。
  /// 支持两种格式：
  /// - 字符串数组：["a", "b"]
  /// - 对象数组（取 raw 字段）：[{"raw": "a", ...}]
  List<String> _parseDictItemsJson(String jsonString) {
    final jsonData = json.decode(jsonString);
    if (jsonData is! List) return [];
    final result = <String>[];
    for (final item in jsonData) {
      if (item is String) {
        result.add(item.trim());
      } else if (item is Map) {
        final raw = item['raw']?.toString().trim();
        if (raw != null && raw.isNotEmpty) {
          result.add(raw);
        }
      }
    }
    return result;
  }

  DictionaryItem _toOldDictItem(bridge.DictItem b) {
    return DictionaryItem(
      id: b.id?.toInt(),
      raw: b.raw,
      pinyin: b.pinyin ?? '',
      abbreviation: b.abbreviation ?? '',
      syncId: b.syncId,
      type: b.dictType,
      createdAt: b.createdAt,
      updatedAt: b.updatedAt,
      deletedAt: b.deletedAt,
    );
  }

  List<DictionaryItem> filterDevices(String query) {
    if (query.isEmpty) return _deviceDict;
    return _deviceDict.where((item) => item.matches(query)).toList();
  }

  List<DictionaryItem> filterAntennas(String query) {
    if (query.isEmpty) return _antennaDict;
    return _antennaDict.where((item) => item.matches(query)).toList();
  }

  List<DictionaryItem> filterCallsigns(String query) {
    if (query.isEmpty) return _callsignDict;
    return _callsignDict.where((item) => item.matches(query)).toList();
  }

  List<DictionaryItem> filterQths(String query) {
    if (query.isEmpty) return _qthDict;
    return _qthDict.where((item) => item.matches(query)).toList();
  }

  Future<void> addDevice(String device) async {
    await _addDictItem('device_dictionary', device, _deviceDict);
  }

  Future<void> addAntenna(String antenna) async {
    await _addDictItem('antenna_dictionary', antenna, _antennaDict);
  }

  Future<void> addCallsign(String callsign) async {
    await _addDictItem('callsign_dictionary', callsign, _callsignDict);
  }

  Future<void> addQth(String qth) async {
    await _addDictItem('qth_dictionary', qth, _qthDict);
  }

  Future<void> _addDictItem(
    String dictType,
    String raw,
    List<DictionaryItem> target,
  ) async {
    if (raw.isEmpty || target.any((d) => d.raw == raw)) return;
    try {
      await RustApi.addDictItem(dictType: dictType, raw: raw);
      final persisted = await RustApi.getDictItemByRaw(dictType: dictType, raw: raw);
      target.add(persisted != null
          ? _toOldDictItem(persisted)
          : DictionaryItem(raw: raw, pinyin: '', abbreviation: '', type: dictType));
      target.sort((a, b) => a.raw.compareTo(b.raw));
      _safeNotify();
      await _notifyDictionaryChanged();
    } catch (e, st) {
      debugPrint('[DictionaryProvider] _addDictItem failed: $e\n$st');
      rethrow;
    }
  }

  Future<void> importDevices(List<String> devices) async {
    await _importDictItems('device_dictionary', devices, _deviceDict);
  }

  Future<void> importAntennas(List<String> antennas) async {
    await _importDictItems('antenna_dictionary', antennas, _antennaDict);
  }

  Future<void> importCallsigns(List<String> callsigns) async {
    await _importDictItems('callsign_dictionary', callsigns, _callsignDict);
  }

  Future<void> importQths(List<String> qths) async {
    await _importDictItems('qth_dictionary', qths, _qthDict);
  }

  Future<void> _importDictItems(
    String dictType,
    List<String> items,
    List<DictionaryItem> target,
  ) async {
    for (final raw in items) {
      if (target.any((d) => d.raw == raw)) continue;
      await RustApi.addDictItem(dictType: dictType, raw: raw);
      final persisted = await RustApi.getDictItemByRaw(dictType: dictType, raw: raw);
      target.add(persisted != null
          ? _toOldDictItem(persisted)
          : DictionaryItem(raw: raw, pinyin: '', abbreviation: '', type: dictType));
    }
    target.sort((a, b) => a.raw.compareTo(b.raw));
    _safeNotify();
    await _notifyDictionaryChanged();
  }

  /// 从 JSON 文件批量导入词库。
  /// 支持两种格式：
  /// 1. 单类数组：["a", "b"] 或 [{"raw":"a"}, ...]
  /// 2. 合并对象：{"devices": [...], "antennas": [...], "callsigns": [...], "qths": [...]}
  Future<Map<String, int>> importFromJson(String jsonString) async {
    final jsonData = json.decode(jsonString);
    final counts = <String, int>{};

    if (jsonData is Map) {
      final deviceItems = _extractItems(jsonData['devices']);
      if (deviceItems.isNotEmpty) {
        await importDevices(deviceItems);
        counts['device'] = deviceItems.length;
      }
      final antennaItems = _extractItems(jsonData['antennas']);
      if (antennaItems.isNotEmpty) {
        await importAntennas(antennaItems);
        counts['antenna'] = antennaItems.length;
      }
      final callsignItems = _extractItems(jsonData['callsigns']);
      if (callsignItems.isNotEmpty) {
        await importCallsigns(callsignItems);
        counts['callsign'] = callsignItems.length;
      }
      final qthItems = _extractItems(jsonData['qths']);
      if (qthItems.isNotEmpty) {
        await importQths(qthItems);
        counts['qth'] = qthItems.length;
      }
    } else if (jsonData is List) {
      final items = _extractItems(jsonData);
      if (items.isNotEmpty) {
        await importDevices(items);
        counts['device'] = items.length;
      }
    }

    return counts;
  }

  List<String> _extractItems(dynamic data) {
    if (data is! List) return [];
    final result = <String>[];
    for (final item in data) {
      if (item is String) {
        final trimmed = item.trim();
        if (trimmed.isNotEmpty) result.add(trimmed);
      } else if (item is Map) {
        final raw = item['raw']?.toString().trim();
        if (raw != null && raw.isNotEmpty) result.add(raw);
      }
    }
    return result;
  }

  Future<void> clearDeviceDict() async {
    await _clearDict('device_dictionary', _deviceDict);
  }

  Future<void> clearAntennaDict() async {
    await _clearDict('antenna_dictionary', _antennaDict);
  }

  Future<void> clearCallsignDict() async {
    await _clearDict('callsign_dictionary', _callsignDict);
  }

  Future<void> clearQthDict() async {
    await _clearDict('qth_dictionary', _qthDict);
  }

  Future<void> _clearDict(String dictType, List<DictionaryItem> target) async {
    await RustApi.softDeleteDictItems(dictType: dictType);
    target.clear();
    _safeNotify();
    await _notifyDictionaryChanged();
  }

  Future<void> resetDictionaries() async {
    await RustApi.resetDictionaries();
    await _loadDictionaries();
    await _notifyDictionaryChanged();
  }

  Future<void> resetAllData() async {
    await resetDictionaries();
  }
}
