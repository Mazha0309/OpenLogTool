import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:openlogtool/src/bridge/rust_api.dart';
import 'package:openlogtool/src/bridge/models/dict_item.dart' as bridge;
import 'package:openlogtool/models/dictionary_item.dart';
import 'package:openlogtool/utils/dictionary_pinyin_helper.dart';

typedef DictionaryUpsertItem = Future<void> Function({
  required String dictType,
  required String raw,
  String? pinyin,
  String? abbreviation,
});

typedef DictionaryGetItemByRaw = Future<bridge.DictItem?> Function({
  required String dictType,
  required String raw,
});

class _RawPinyinAbbrev {
  final String raw;
  final String? pinyin;
  final String? abbreviation;

  _RawPinyinAbbrev(this.raw, {this.pinyin, this.abbreviation});
}

class DictionaryProvider with ChangeNotifier {
  bool _disposed = false;
  List<DictionaryItem> _deviceDict = [];
  List<DictionaryItem> _antennaDict = [];
  List<DictionaryItem> _callsignDict = [];
  List<DictionaryItem> _qthDict = [];
  Future<void> Function()? _onDictionaryChanged;
  final DictionaryUpsertItem _upsertItem;
  final DictionaryGetItemByRaw _getItemByRaw;

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

  DictionaryProvider({
    bool autoload = true,
    DictionaryUpsertItem? upsertItem,
    DictionaryGetItemByRaw? getItemByRaw,
  })  : _upsertItem = upsertItem ?? RustApi.upsertDictItem,
        _getItemByRaw = getItemByRaw ?? RustApi.getDictItemByRaw {
    if (autoload) scheduleMicrotask(_loadDictionaries);
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

      // 每次启动都同步内置词库，补全缺失的拼音/缩写，同时保留用户自定义内容。
      await _syncBuiltinDictionaries();
      await _backfillMissingPinyin();
      _deviceDict = await _getDictItems('device_dictionary');
      _antennaDict = await _getDictItems('antenna_dictionary');
      _callsignDict = await _getDictItems('callsign_dictionary');
      _qthDict = await _getDictItems('qth_dictionary');
    } catch (e, st) {
      debugPrint('[DictionaryProvider] _loadDictionaries failed: $e\n$st');
    }
    _safeNotify();
  }

  Future<List<DictionaryItem>> _getDictItems(String dictType) async {
    final items = await RustApi.getDictItems(dictType: dictType);
    return items.map(_toOldDictItem).toList();
  }

  Future<void> _syncBuiltinDictionaries() async {
    await _syncBuiltinFromAsset(
        'device_dictionary', 'assets/dictionaries/device.json');
    await _syncBuiltinFromAsset(
        'antenna_dictionary', 'assets/dictionaries/antenna.json');
    await _syncBuiltinFromAsset(
        'qth_dictionary', 'assets/dictionaries/qth.json');
  }

  Future<void> _backfillMissingPinyin() async {
    await _backfillDict('device_dictionary', _deviceDict);
    await _backfillDict('antenna_dictionary', _antennaDict);
    await _backfillDict('qth_dictionary', _qthDict);
  }

  Future<void> _backfillDict(
    String dictType,
    List<DictionaryItem> target,
  ) async {
    for (final item in target) {
      if (item.abbreviation.isNotEmpty && item.pinyin.isNotEmpty) continue;
      final generated = DictionaryPinyinHelper.generate(item.raw);
      await _upsertItem(
        dictType: dictType,
        raw: item.raw,
        pinyin: generated.pinyin,
        abbreviation: generated.abbreviation,
      );
    }
  }

  Future<void> _syncBuiltinFromAsset(String dictType, String assetPath) async {
    try {
      final jsonString = await rootBundle.loadString(assetPath);
      final jsonData = json.decode(jsonString);
      if (jsonData is! List) return;
      for (final item in jsonData) {
        if (item is! Map) continue;
        final raw = item['raw']?.toString().trim();
        if (raw == null || raw.isEmpty) continue;
        final pinyin = item['pinyin']?.toString().trim();
        final abbreviation = item['abbreviation']?.toString().trim();
        await _upsertItem(
          dictType: dictType,
          raw: raw,
          pinyin: pinyin?.isNotEmpty == true ? pinyin : null,
          abbreviation: abbreviation?.isNotEmpty == true ? abbreviation : null,
        );
      }
    } catch (e, st) {
      debugPrint(
          '[DictionaryProvider] sync builtin from $assetPath failed: $e\n$st');
    }
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
      final generated = DictionaryPinyinHelper.generate(raw);
      await _upsertItem(
        dictType: dictType,
        raw: raw,
        pinyin: generated.pinyin,
        abbreviation: generated.abbreviation,
      );
      final persisted = await _getItemByRaw(dictType: dictType, raw: raw);
      if (persisted == null) {
        throw StateError('DICT_ITEM_PERSIST_FAILED: $dictType/$raw');
      }
      target.add(_toOldDictItem(persisted));
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
      final generated = DictionaryPinyinHelper.generate(raw);
      await _upsertItem(
        dictType: dictType,
        raw: raw,
        pinyin: generated.pinyin,
        abbreviation: generated.abbreviation,
      );
      final persisted = await _getItemByRaw(dictType: dictType, raw: raw);
      if (persisted == null) {
        throw StateError('DICT_ITEM_PERSIST_FAILED: $dictType/$raw');
      }
      target.add(_toOldDictItem(persisted));
    }
    target.sort((a, b) => a.raw.compareTo(b.raw));
    _safeNotify();
    await _notifyDictionaryChanged();
  }

  Future<Map<String, int>> importFromJson(String jsonString) async {
    final jsonData = json.decode(jsonString);
    final counts = <String, int>{};

    if (jsonData is Map) {
      counts['device'] = await _importTypedJson(
          'device_dictionary', jsonData['devices'], _deviceDict);
      counts['antenna'] = await _importTypedJson(
          'antenna_dictionary', jsonData['antennas'], _antennaDict);
      counts['callsign'] = await _importTypedJson(
          'callsign_dictionary', jsonData['callsigns'], _callsignDict);
      counts['qth'] =
          await _importTypedJson('qth_dictionary', jsonData['qths'], _qthDict);
    } else if (jsonData is List) {
      counts['device'] = await _importTypedJson(
        'device_dictionary',
        jsonData,
        _deviceDict,
      );
    }

    return counts;
  }

  Future<int> _importTypedJson(
    String dictType,
    dynamic data,
    List<DictionaryItem> target,
  ) async {
    final items = _extractTypedItems(data);
    if (items.isEmpty) return 0;
    var added = 0;
    for (final item in items) {
      if (target.any((d) => d.raw == item.raw)) continue;
      final pinyin = item.pinyin?.isNotEmpty == true
          ? item.pinyin!
          : DictionaryPinyinHelper.generate(item.raw).pinyin;
      final abbreviation = item.abbreviation?.isNotEmpty == true
          ? item.abbreviation!
          : DictionaryPinyinHelper.generate(item.raw).abbreviation;
      await _upsertItem(
        dictType: dictType,
        raw: item.raw,
        pinyin: pinyin,
        abbreviation: abbreviation,
      );
      final persisted = await _getItemByRaw(
        dictType: dictType,
        raw: item.raw,
      );
      if (persisted == null) {
        throw StateError('DICT_ITEM_PERSIST_FAILED: $dictType/${item.raw}');
      }
      target.add(_toOldDictItem(persisted));
      added++;
    }
    target.sort((a, b) => a.raw.compareTo(b.raw));
    _safeNotify();
    await _notifyDictionaryChanged();
    return added;
  }

  List<_RawPinyinAbbrev> _extractTypedItems(dynamic data) {
    if (data is! List) return [];
    final result = <_RawPinyinAbbrev>[];
    for (final item in data) {
      if (item is String) {
        final trimmed = item.trim();
        if (trimmed.isNotEmpty) result.add(_RawPinyinAbbrev(trimmed));
      } else if (item is Map) {
        final raw = item['raw']?.toString().trim();
        if (raw == null || raw.isEmpty) continue;
        result.add(_RawPinyinAbbrev(
          raw,
          pinyin: item['pinyin']?.toString().trim(),
          abbreviation: item['abbreviation']?.toString().trim(),
        ));
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
