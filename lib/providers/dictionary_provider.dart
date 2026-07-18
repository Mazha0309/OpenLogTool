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

typedef DictionaryBulkUpsertItems = Future<void> Function({
  required String requestJson,
});

typedef DictionaryGetItemByRaw = Future<bridge.DictItem?> Function({
  required String dictType,
  required String raw,
});

typedef DictionaryGetItems = Future<List<bridge.DictItem>> Function({
  required String dictType,
});

typedef DictionaryDeleteItem = Future<bool> Function({
  required String dictType,
  required String raw,
});

typedef DictionaryClearItems = Future<void> Function({
  required String dictType,
});

typedef DictionaryRenameItem = Future<bridge.DictItem> Function({
  required String dictType,
  required String oldRaw,
  required String newRaw,
  String? pinyin,
  String? abbreviation,
});

typedef DictionaryAssetLoader = Future<String> Function(String assetPath);
typedef DictionarySeedItems = Future<BigInt> Function({
  required String dictType,
  required List<String> items,
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
  final DictionaryUpsertItem _upsertActiveItem;
  final DictionaryBulkUpsertItems _bulkUpsertItems;
  final DictionaryGetItemByRaw _getItemByRaw;
  final DictionaryGetItems _getItems;
  final DictionaryDeleteItem _deleteItem;
  final DictionaryClearItems _clearItems;
  final DictionaryRenameItem _renameItem;
  final DictionaryAssetLoader _loadAssetString;
  final DictionarySeedItems _seedItems;
  final Completer<void> _readyCompleter = Completer<void>();
  int _dataRevision = 0;

  List<DictionaryItem> get deviceDict => _deviceDict;
  List<DictionaryItem> get antennaDict => _antennaDict;
  List<DictionaryItem> get callsignDict => _callsignDict;
  List<DictionaryItem> get qthDict => _qthDict;
  Future<void> get ready => _readyCompleter.future;
  int get dataRevision => _dataRevision;

  void setOnDictionaryChanged(Future<void> Function()? callback) {
    _onDictionaryChanged = callback;
  }

  Future<void> _notifyDictionaryChanged() async {
    _dataRevision += 1;
    // Publish the durable-data revision and the visible list change in the
    // same notification. PersonalCloudProvider observes [dataRevision] from
    // a ProxyProvider update; notifying before incrementing left it one
    // revision behind and dictionary uploads only happened on the periodic
    // poll.
    _safeNotify();
    if (_onDictionaryChanged != null) {
      unawaited(_onDictionaryChanged!());
    }
  }

  DictionaryProvider({
    bool autoload = true,
    DictionaryUpsertItem? upsertItem,
    DictionaryUpsertItem? upsertActiveItem,
    DictionaryBulkUpsertItems? bulkUpsertItems,
    DictionaryGetItemByRaw? getItemByRaw,
    DictionaryGetItems? getItems,
    DictionaryDeleteItem? deleteItem,
    DictionaryClearItems? clearItems,
    DictionaryRenameItem? renameItem,
    DictionaryAssetLoader? loadAssetString,
    DictionarySeedItems? seedItems,
  })  : _upsertItem = upsertItem ?? RustApi.upsertDictItem,
        _upsertActiveItem = upsertActiveItem ?? RustApi.upsertDictItemIfActive,
        _bulkUpsertItems = bulkUpsertItems ??
            _resolveBulkUpsertItems(
              upsertItem,
            ),
        _getItemByRaw = getItemByRaw ?? RustApi.getDictItemByRaw,
        _getItems = getItems ?? RustApi.getDictItems,
        _deleteItem = deleteItem ?? RustApi.softDeleteDictItem,
        _clearItems = clearItems ?? RustApi.softDeleteDictItems,
        _renameItem = renameItem ?? RustApi.renameDictItem,
        _loadAssetString = loadAssetString ?? rootBundle.loadString,
        _seedItems = seedItems ?? RustApi.seedDict {
    _readyCompleter.future.ignore();
    if (autoload) {
      scheduleMicrotask(_loadDictionaries);
    } else {
      _readyCompleter.complete();
    }
  }

  static DictionaryBulkUpsertItems _resolveBulkUpsertItems(
    DictionaryUpsertItem? injectedUpsert,
  ) {
    if (injectedUpsert == null) return RustApi.bulkUpsertDictItems;

    // Preserve the lightweight constructor injection used by provider tests
    // and embedders. Production always uses the single-transaction Rust API;
    // callers that model persistence can inject [bulkUpsertItems] directly.
    return ({required String requestJson}) async {
      final request = json.decode(requestJson);
      if (request is! Map || request['items'] is! List) {
        throw const FormatException('Invalid dictionary batch request');
      }
      for (final rawItem in request['items'] as List) {
        if (rawItem is! Map) {
          throw const FormatException('Invalid dictionary batch item');
        }
        await injectedUpsert(
          dictType: rawItem['dictType']?.toString() ?? '',
          raw: rawItem['raw']?.toString() ?? '',
          pinyin: rawItem['pinyin']?.toString(),
          abbreviation: rawItem['abbreviation']?.toString(),
        );
      }
    };
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
      await reloadFromDatabase(synchronizeBuiltins: true);
      if (!_readyCompleter.isCompleted) _readyCompleter.complete();
    } catch (e, st) {
      debugPrint('[DictionaryProvider] _loadDictionaries failed: $e\n$st');
      if (!_readyCompleter.isCompleted) {
        _readyCompleter.completeError(e, st);
      }
    }
  }

  /// Reloads lookup rows after the Rust database was atomically replaced.
  ///
  /// A normal app start synchronizes built-in rows, so callers should normally
  /// keep [synchronizeBuiltins] enabled for identical no-restart behavior.
  /// Built-in synchronization respects imported tombstones and therefore does
  /// not resurrect entries the user deliberately deleted.
  Future<void> reloadFromDatabase({
    bool synchronizeBuiltins = true,
    bool strictBuiltinSynchronization = false,
  }) async {
    _deviceDict = await _getDictItems('device_dictionary');
    _antennaDict = await _getDictItems('antenna_dictionary');
    _callsignDict = await _getDictItems('callsign_dictionary');
    _qthDict = await _getDictItems('qth_dictionary');

    if (synchronizeBuiltins) {
      await _syncBuiltinDictionaries(strict: strictBuiltinSynchronization);
      await _backfillMissingPinyin();
      _deviceDict = await _getDictItems('device_dictionary');
      _antennaDict = await _getDictItems('antenna_dictionary');
      _callsignDict = await _getDictItems('callsign_dictionary');
      _qthDict = await _getDictItems('qth_dictionary');
    }
    _safeNotify();
  }

  Future<List<DictionaryItem>> _getDictItems(String dictType) async {
    final items = await _getItems(dictType: dictType);
    return items.map(_toOldDictItem).toList();
  }

  Future<void> _syncBuiltinDictionaries({required bool strict}) async {
    await _syncBuiltinFromAsset(
      'device_dictionary',
      'assets/dictionaries/device.json',
      strict: strict,
    );
    await _syncBuiltinFromAsset(
      'antenna_dictionary',
      'assets/dictionaries/antenna.json',
      strict: strict,
    );
    await _syncBuiltinFromAsset(
      'qth_dictionary',
      'assets/dictionaries/qth.json',
      strict: strict,
    );
    await _seedItems(
      dictType: 'callsign_dictionary',
      items: const <String>[],
    );
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
      final upsert = item.origin == 'user' ? _upsertItem : _upsertActiveItem;
      await upsert(
        dictType: dictType,
        raw: item.raw,
        pinyin: generated.pinyin,
        abbreviation: generated.abbreviation,
      );
    }
  }

  Future<void> _syncBuiltinFromAsset(
    String dictType,
    String assetPath, {
    required bool strict,
  }) async {
    try {
      final jsonString = await _loadAssetString(assetPath);
      final jsonData = json.decode(jsonString);
      if (jsonData is! List) {
        throw FormatException('Invalid built-in dictionary: $assetPath');
      }
      final rawItems = <String>[];
      for (final item in jsonData) {
        if (item is! Map) continue;
        final raw = item['raw']?.toString().trim();
        if (raw != null && raw.isNotEmpty) rawItems.add(raw);
      }
      await _seedItems(dictType: dictType, items: rawItems);
      for (final item in jsonData) {
        if (item is! Map) continue;
        final raw = item['raw']?.toString().trim();
        if (raw == null || raw.isEmpty) continue;
        final pinyin = item['pinyin']?.toString().trim();
        final abbreviation = item['abbreviation']?.toString().trim();
        await _upsertActiveItem(
          dictType: dictType,
          raw: raw,
          pinyin: pinyin?.isNotEmpty == true ? pinyin : null,
          abbreviation: abbreviation?.isNotEmpty == true ? abbreviation : null,
        );
      }
    } catch (e, st) {
      debugPrint(
          '[DictionaryProvider] sync builtin from $assetPath failed: $e\n$st');
      if (strict) rethrow;
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
      origin: b.origin,
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
      await _notifyDictionaryChanged();
    } catch (e, st) {
      debugPrint('[DictionaryProvider] _addDictItem failed: $e\n$st');
      rethrow;
    }
  }

  Future<void> importDevices(List<String> devices) async {
    await _importDictionaryBatch(<String, List<_RawPinyinAbbrev>>{
      'device': devices.map(_RawPinyinAbbrev.new).toList(),
    });
  }

  Future<void> importAntennas(List<String> antennas) async {
    await _importDictionaryBatch(<String, List<_RawPinyinAbbrev>>{
      'antenna': antennas.map(_RawPinyinAbbrev.new).toList(),
    });
  }

  Future<void> importCallsigns(List<String> callsigns) async {
    await _importDictionaryBatch(<String, List<_RawPinyinAbbrev>>{
      'callsign': callsigns.map(_RawPinyinAbbrev.new).toList(),
    });
  }

  Future<void> importQths(List<String> qths) async {
    await _importDictionaryBatch(<String, List<_RawPinyinAbbrev>>{
      'qth': qths.map(_RawPinyinAbbrev.new).toList(),
    });
  }

  Future<Map<String, int>> importFromJson(String jsonString) async {
    final jsonData = json.decode(jsonString);

    if (jsonData is Map) {
      return _importDictionaryBatch(_extractDictionaryMap(jsonData));
    } else if (jsonData is List) {
      return _importDictionaryBatch(<String, List<_RawPinyinAbbrev>>{
        'device': _extractTypedItems(jsonData),
      });
    }

    return <String, int>{};
  }

  /// Serializes all four lookup libraries without local database identifiers.
  ///
  /// The plural top-level arrays intentionally match the existing import
  /// format. Each entry includes its searchable pinyin and abbreviation so a
  /// round trip preserves lookup behavior.
  String exportToJson() {
    List<Map<String, String>> encodeItems(List<DictionaryItem> items) => items
        .map(
          (item) => <String, String>{
            'raw': item.raw,
            if (item.pinyin.trim().isNotEmpty) 'pinyin': item.pinyin,
            if (item.abbreviation.trim().isNotEmpty)
              'abbreviation': item.abbreviation,
          },
        )
        .toList(growable: false);

    return const JsonEncoder.withIndent('  ').convert(<String, Object>{
      'format': 'openlogtool-dictionaries',
      'version': 1,
      'devices': encodeItems(_deviceDict),
      'antennas': encodeItems(_antennaDict),
      'callsigns': encodeItems(_callsignDict),
      'qths': encodeItems(_qthDict),
    });
  }

  Map<String, List<_RawPinyinAbbrev>> _extractDictionaryMap(Map data) {
    final nested = data['dictionaries'] is Map
        ? data['dictionaries'] as Map
        : const <Object?, Object?>{};
    dynamic firstValue(List<String> keys) {
      for (final key in keys) {
        if (data.containsKey(key)) return data[key];
        if (nested.containsKey(key)) return nested[key];
      }
      return null;
    }

    final requested = <String, List<_RawPinyinAbbrev>>{
      'device': _extractTypedItems(firstValue(const <String>[
        'devices',
        'device',
        'deviceDict',
        'device_dictionary',
      ])),
      'antenna': _extractTypedItems(firstValue(const <String>[
        'antennas',
        'antenna',
        'antennaDict',
        'antenna_dictionary',
      ])),
      'callsign': _extractTypedItems(firstValue(const <String>[
        'callsigns',
        'callsign',
        'callsignDict',
        'callsign_dictionary',
      ])),
      'qth': _extractTypedItems(firstValue(const <String>[
        'qths',
        'qth',
        'qthDict',
        'qth_dictionary',
      ])),
    };

    final flatItems = data['items'];
    if (flatItems is List) {
      const typeAliases = <String, String>{
        'device': 'device',
        'device_dictionary': 'device',
        'antenna': 'antenna',
        'antenna_dictionary': 'antenna',
        'callsign': 'callsign',
        'callsign_dictionary': 'callsign',
        'qth': 'qth',
        'qth_dictionary': 'qth',
      };
      for (final rawItem in flatItems) {
        if (rawItem is! Map) continue;
        final type = typeAliases[
            (rawItem['dictType'] ?? rawItem['type'])?.toString().trim()];
        if (type == null) continue;
        requested[type]!.addAll(_extractTypedItems(<Object?>[rawItem]));
      }
    }
    return requested;
  }

  Future<Map<String, int>> _importDictionaryBatch(
    Map<String, List<_RawPinyinAbbrev>> requestedItems,
  ) async {
    const dictTypes = <String, String>{
      'device': 'device_dictionary',
      'antenna': 'antenna_dictionary',
      'callsign': 'callsign_dictionary',
      'qth': 'qth_dictionary',
    };
    final normalizedByKey = <String, List<_RawPinyinAbbrev>>{};
    for (final entry in requestedItems.entries) {
      final unique = <String, _RawPinyinAbbrev>{};
      for (final item in entry.value) {
        final raw = item.raw.trim();
        if (raw.isEmpty) continue;
        unique.putIfAbsent(
          raw,
          () => _RawPinyinAbbrev(
            raw,
            pinyin: item.pinyin?.trim(),
            abbreviation: item.abbreviation?.trim(),
          ),
        );
      }
      normalizedByKey[entry.key] = unique.values.toList(growable: false);
    }

    final before = <String, bool>{};
    final requestPayload = <Map<String, Object?>>[];
    for (final entry in normalizedByKey.entries) {
      final dictType = dictTypes[entry.key];
      if (dictType == null) continue;
      for (final item in entry.value) {
        final persisted = await _getItemByRaw(
          dictType: dictType,
          raw: item.raw,
        );
        before['$dictType\u0000${item.raw}'] = persisted != null;
        final generated = DictionaryPinyinHelper.generate(item.raw);
        requestPayload.add(<String, Object?>{
          'dictType': dictType,
          'raw': item.raw,
          'pinyin':
              item.pinyin?.isNotEmpty == true ? item.pinyin : generated.pinyin,
          'abbreviation': item.abbreviation?.isNotEmpty == true
              ? item.abbreviation
              : generated.abbreviation,
        });
      }
    }

    if (requestPayload.isEmpty) {
      return <String, int>{
        for (final key in requestedItems.keys) key: 0,
      };
    }

    await _bulkUpsertItems(
      requestJson: json.encode(<String, Object?>{'items': requestPayload}),
    );

    // Stage every read-back before touching visible state. If persistence did
    // not commit the complete request, no partial provider state is exposed.
    final persistedByType = <String, Map<String, DictionaryItem>>{};
    final counts = <String, int>{};
    for (final entry in normalizedByKey.entries) {
      final dictType = dictTypes[entry.key];
      if (dictType == null) continue;
      var added = 0;
      final persistedItems = <String, DictionaryItem>{};
      for (final item in entry.value) {
        final persisted = await _getItemByRaw(
          dictType: dictType,
          raw: item.raw,
        );
        if (persisted == null) {
          throw StateError('DICT_ITEM_PERSIST_FAILED: $dictType/${item.raw}');
        }
        persistedItems[item.raw] = _toOldDictItem(persisted);
        if (before['$dictType\u0000${item.raw}'] != true) added++;
      }
      persistedByType[dictType] = persistedItems;
      counts[entry.key] = added;
    }

    _deviceDict = _mergeImportedItems(
      _deviceDict,
      persistedByType['device_dictionary'],
    );
    _antennaDict = _mergeImportedItems(
      _antennaDict,
      persistedByType['antenna_dictionary'],
    );
    _callsignDict = _mergeImportedItems(
      _callsignDict,
      persistedByType['callsign_dictionary'],
    );
    _qthDict = _mergeImportedItems(
      _qthDict,
      persistedByType['qth_dictionary'],
    );
    await _notifyDictionaryChanged();
    return counts;
  }

  List<DictionaryItem> _mergeImportedItems(
    List<DictionaryItem> current,
    Map<String, DictionaryItem>? imported,
  ) {
    if (imported == null || imported.isEmpty) return current;
    final merged = <String, DictionaryItem>{
      for (final item in current) item.raw: item,
      ...imported,
    }.values.toList();
    merged.sort((a, b) => a.raw.compareTo(b.raw));
    return merged;
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

  Future<void> deleteDevice(String raw) async {
    await _deleteDictItem('device_dictionary', raw, _deviceDict);
  }

  Future<void> deleteAntenna(String raw) async {
    await _deleteDictItem('antenna_dictionary', raw, _antennaDict);
  }

  Future<void> deleteCallsign(String raw) async {
    await _deleteDictItem('callsign_dictionary', raw, _callsignDict);
  }

  Future<void> deleteQth(String raw) async {
    await _deleteDictItem('qth_dictionary', raw, _qthDict);
  }

  Future<void> renameDevice(String oldRaw, String newRaw) async {
    await _renameDictItem(
      'device_dictionary',
      oldRaw,
      newRaw,
      _deviceDict,
    );
  }

  Future<void> renameAntenna(String oldRaw, String newRaw) async {
    await _renameDictItem(
      'antenna_dictionary',
      oldRaw,
      newRaw,
      _antennaDict,
    );
  }

  Future<void> renameCallsign(String oldRaw, String newRaw) async {
    await _renameDictItem(
      'callsign_dictionary',
      oldRaw,
      newRaw,
      _callsignDict,
    );
  }

  Future<void> renameQth(String oldRaw, String newRaw) async {
    await _renameDictItem('qth_dictionary', oldRaw, newRaw, _qthDict);
  }

  Future<void> _renameDictItem(
    String dictType,
    String oldRaw,
    String newRaw,
    List<DictionaryItem> target,
  ) async {
    final normalizedOldRaw = oldRaw.trim();
    final normalizedNewRaw = newRaw.trim();
    if (normalizedOldRaw.isEmpty || normalizedNewRaw.isEmpty) {
      throw ArgumentError('Dictionary entry is empty');
    }
    if (normalizedOldRaw == normalizedNewRaw) return;
    if (target.any((item) => item.raw == normalizedNewRaw)) {
      throw StateError('DICTIONARY_RENAME_TARGET_EXISTS');
    }
    final index = target.indexWhere((item) => item.raw == normalizedOldRaw);
    if (index < 0) {
      throw StateError('DICTIONARY_RENAME_SOURCE_NOT_FOUND');
    }

    final generated = DictionaryPinyinHelper.generate(normalizedNewRaw);
    await _renameItem(
      dictType: dictType,
      oldRaw: normalizedOldRaw,
      newRaw: normalizedNewRaw,
      pinyin: generated.pinyin,
      abbreviation: generated.abbreviation,
    );

    // Read both names back before mutating visible state. A failed or partial
    // persistence implementation therefore never makes the UI look renamed.
    final persisted = await _getItemByRaw(
      dictType: dictType,
      raw: normalizedNewRaw,
    );
    final staleSource = await _getItemByRaw(
      dictType: dictType,
      raw: normalizedOldRaw,
    );
    if (persisted == null || staleSource != null) {
      throw StateError(
        'DICT_ITEM_RENAME_FAILED: $dictType/$normalizedOldRaw',
      );
    }

    target[index] = _toOldDictItem(persisted);
    target.sort((a, b) => a.raw.compareTo(b.raw));
    await _notifyDictionaryChanged();
  }

  Future<void> _deleteDictItem(
    String dictType,
    String raw,
    List<DictionaryItem> target,
  ) async {
    final normalizedRaw = raw.trim();
    if (normalizedRaw.isEmpty) {
      throw ArgumentError.value(raw, 'raw', 'Dictionary entry is empty');
    }

    await _deleteItem(dictType: dictType, raw: normalizedRaw);
    final persisted = await _getItemByRaw(
      dictType: dictType,
      raw: normalizedRaw,
    );
    if (persisted != null) {
      throw StateError('DICT_ITEM_DELETE_FAILED: $dictType/$normalizedRaw');
    }

    target.removeWhere((item) => item.raw == normalizedRaw);
    await _notifyDictionaryChanged();
  }

  Future<void> _clearDict(String dictType, List<DictionaryItem> target) async {
    await _clearItems(dictType: dictType);
    final persisted = await _getDictItems(dictType);
    target
      ..clear()
      ..addAll(persisted);
    if (persisted.isNotEmpty) {
      // The injected/alternate persistence layer did not perform the full
      // clear. Reflect its read-back without claiming a successful revision.
      _safeNotify();
      throw StateError(
        'DICT_CLEAR_FAILED: $dictType (${persisted.length} entries remain)',
      );
    }
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
