import 'dart:async';
import 'package:flutter/material.dart';
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
    await RustApi.seedDict(dictType: 'device_dictionary', items: _defaultDevices);
    await RustApi.seedDict(dictType: 'antenna_dictionary', items: _defaultAntennas);
    await RustApi.seedDict(dictType: 'qth_dictionary', items: _defaultQths);
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
    // TODO: implement full data reset via Rust API
    await resetDictionaries();
  }

  static const List<String> _defaultDevices = [
    'ICOM 7300',
    'ICOM 7610',
    'Yaesu FT-817',
    'Yaesu FT-857',
    'Yaesu FT-891',
    'Yaesu FT-991A',
    'Kenwood TS-590',
    'Kenwood TS-890',
    'FlexRadio 6400',
    'Anan 7000',
  ];

  static const List<String> _defaultAntennas = [
    'Dipole',
    'Vertical',
    'Yagi',
    'Loop',
    'Long Wire',
    'End Fed',
    'GP',
    'DP',
  ];

  static const List<String> _defaultQths = [
    '北京',
    '上海',
    '广州',
    '深圳',
    '成都',
    '杭州',
    '南京',
    '武汉',
  ];
}
