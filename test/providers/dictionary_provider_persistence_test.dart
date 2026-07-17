import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/providers/dictionary_provider.dart';
import 'package:openlogtool/src/bridge/models/dict_item.dart' as bridge;

void main() {
  test('add rejects an upsert that is not readable after persistence',
      () async {
    var upsertCalls = 0;
    final provider = DictionaryProvider(
      autoload: false,
      upsertItem: ({
        required String dictType,
        required String raw,
        String? pinyin,
        String? abbreviation,
      }) async {
        upsertCalls++;
      },
      getItemByRaw: ({
        required String dictType,
        required String raw,
      }) async =>
          null,
    );

    await expectLater(
      provider.addDevice('Soft-deleted radio'),
      throwsA(
        isA<StateError>().having(
          (error) => error.toString(),
          'message',
          contains('DICT_ITEM_PERSIST_FAILED'),
        ),
      ),
    );

    expect(upsertCalls, 1);
    expect(provider.deviceDict, isEmpty);
    provider.dispose();
  });

  test('plain-list import exposes no partial in-memory result on read failure',
      () async {
    final provider = DictionaryProvider(
      autoload: false,
      upsertItem: ({
        required String dictType,
        required String raw,
        String? pinyin,
        String? abbreviation,
      }) async {},
      getItemByRaw: ({
        required String dictType,
        required String raw,
      }) async =>
          raw == 'Persisted radio' ? _persistedItem(dictType, raw) : null,
    );

    await expectLater(
      provider.importDevices(
        const <String>['Persisted radio', 'Soft-deleted radio'],
      ),
      throwsA(isA<StateError>()),
    );

    expect(provider.deviceDict, isEmpty);
    provider.dispose();
  });

  test('JSON import rejects an unreadable tombstoned item', () async {
    final provider = DictionaryProvider(
      autoload: false,
      upsertItem: ({
        required String dictType,
        required String raw,
        String? pinyin,
        String? abbreviation,
      }) async {},
      getItemByRaw: ({
        required String dictType,
        required String raw,
      }) async =>
          null,
    );

    await expectLater(
      provider.importFromJson(
        '{"devices":["Soft-deleted radio"]}',
      ),
      throwsA(isA<StateError>()),
    );

    expect(provider.deviceDict, isEmpty);
    provider.dispose();
  });

  test('add keeps the item returned by persistent storage', () async {
    final provider = DictionaryProvider(
      autoload: false,
      upsertItem: ({
        required String dictType,
        required String raw,
        String? pinyin,
        String? abbreviation,
      }) async {},
      getItemByRaw: ({
        required String dictType,
        required String raw,
      }) async =>
          _persistedItem(dictType, raw),
    );

    await provider.addDevice('FT-991A');

    expect(provider.deviceDict, hasLength(1));
    expect(provider.deviceDict.single.raw, 'FT-991A');
    expect(provider.deviceDict.single.syncId, 'persisted-FT-991A');
    provider.dispose();
  });

  test('single delete updates memory only after persistent deletion', () async {
    final store = _DictionaryStore();
    final provider = _providerForStore(store);
    await provider.addDevice('FT-991A');

    await provider.deleteDevice('FT-991A');

    expect(store.items, isEmpty);
    expect(provider.deviceDict, isEmpty);

    await provider.addDevice('FT-991A');
    expect(provider.deviceDict.single.raw, 'FT-991A');
    provider.dispose();
  });

  test('single delete keeps the visible entry when persistence rejects it',
      () async {
    final store = _DictionaryStore(ignoreDeletes: true);
    final provider = _providerForStore(store);
    await provider.addDevice('FT-991A');

    await expectLater(
      provider.deleteDevice('FT-991A'),
      throwsA(
        isA<StateError>().having(
          (error) => error.toString(),
          'message',
          contains('DICT_ITEM_DELETE_FAILED'),
        ),
      ),
    );

    expect(provider.deviceDict.single.raw, 'FT-991A');
    provider.dispose();
  });

  test('clear by type removes only that library after read-back', () async {
    final store = _DictionaryStore();
    final provider = _providerForStore(store);
    await provider.addDevice('FT-991A');
    await provider.addAntenna('Yagi');

    await provider.clearDeviceDict();

    expect(provider.deviceDict, isEmpty);
    expect(provider.antennaDict.single.raw, 'Yagi');
    expect(
      store.items.values.map((item) => item.raw),
      contains('Yagi'),
    );
    provider.dispose();
  });

  test('clear reports read-back failure and keeps remaining persisted rows',
      () async {
    final store = _DictionaryStore(ignoreClears: true);
    final provider = _providerForStore(store);
    await provider.addCallsign('BG5CRL');

    await expectLater(
      provider.clearCallsignDict(),
      throwsA(
        isA<StateError>().having(
          (error) => error.toString(),
          'message',
          contains('DICT_CLEAR_FAILED'),
        ),
      ),
    );

    expect(provider.callsignDict.single.raw, 'BG5CRL');
    provider.dispose();
  });

  test('database replacement reload discards stale in-memory libraries',
      () async {
    final store = _DictionaryStore();
    await store.upsert(dictType: 'device_dictionary', raw: 'Before import');
    final provider = _providerForStore(store);
    await provider.reloadFromDatabase(synchronizeBuiltins: false);
    expect(provider.deviceDict.single.raw, 'Before import');

    await store.clear(dictType: 'device_dictionary');
    await store.upsert(dictType: 'antenna_dictionary', raw: 'After import');
    await provider.reloadFromDatabase(synchronizeBuiltins: false);

    expect(provider.deviceDict, isEmpty);
    expect(provider.antennaDict.single.raw, 'After import');
    provider.dispose();
  });

  test('JSON map imports all four libraries in one batch with exact counts',
      () async {
    final store = _DictionaryStore();
    await store.upsert(
      dictType: 'device_dictionary',
      raw: 'Existing radio',
    );
    final provider = _providerForStore(store);
    await provider.reloadFromDatabase(synchronizeBuiltins: false);

    final counts = await provider.importFromJson('''
      {
        "devices": [
          "Existing radio",
          {"raw":"FT-991A","pinyin":"FT 991 A","abbreviation":"FT991A"}
        ],
        "antennas": ["Yagi"],
        "callsigns": ["BG5CRL"],
        "qths": [{"raw":"浙江杭州","pinyin":"zhe jiang hang zhou","abbreviation":"ZJHZ"}]
      }
    ''');

    expect(store.batchCalls, 1);
    expect(
      counts,
      <String, int>{
        'device': 1,
        'antenna': 1,
        'callsign': 1,
        'qth': 1,
      },
    );
    expect(
      provider.deviceDict.map((item) => item.raw),
      <String>['Existing radio', 'FT-991A'],
    );
    expect(provider.antennaDict.single.raw, 'Yagi');
    expect(provider.callsignDict.single.raw, 'BG5CRL');
    expect(provider.qthDict.single.raw, '浙江杭州');
    provider.dispose();
  });

  test('legacy JSON list stays a device import and de-duplicates its batch',
      () async {
    final store = _DictionaryStore();
    final provider = _providerForStore(store);

    final counts = await provider.importFromJson(
      '[" FT-991A ", {"raw":"IC-7300"}, "FT-991A"]',
    );

    expect(store.batchCalls, 1);
    expect(counts, <String, int>{'device': 2});
    expect(
      provider.deviceDict.map((item) => item.raw),
      <String>['FT-991A', 'IC-7300'],
    );
    expect(provider.antennaDict, isEmpty);
    provider.dispose();
  });

  test('failed batch leaves persistent and in-memory dictionaries unchanged',
      () async {
    final store = _DictionaryStore(failBatchRaw: 'Yagi');
    final provider = _providerForStore(store);
    await provider.addDevice('Existing radio');
    final persistentBefore = Map<String, bridge.DictItem>.from(store.items);

    await expectLater(
      provider.importFromJson(
        '{"devices":["FT-991A"],"antennas":["Yagi"]}',
      ),
      throwsA(isA<StateError>()),
    );

    expect(store.batchCalls, 1);
    expect(store.items, persistentBefore);
    expect(
      provider.deviceDict.map((item) => item.raw),
      <String>['Existing radio'],
    );
    expect(provider.antennaDict, isEmpty);
    provider.dispose();
  });

  test('strict built-in synchronization propagates an asset restore failure',
      () async {
    final store = _DictionaryStore();
    final provider = DictionaryProvider(
      autoload: false,
      upsertItem: store.upsert,
      upsertActiveItem: store.upsert,
      bulkUpsertItems: store.bulkUpsert,
      getItemByRaw: store.getByRaw,
      getItems: store.getItems,
      deleteItem: store.delete,
      clearItems: store.clear,
      loadAssetString: (_) async => throw StateError('asset unavailable'),
    );

    await expectLater(
      provider.reloadFromDatabase(
        synchronizeBuiltins: true,
        strictBuiltinSynchronization: true,
      ),
      throwsA(isA<StateError>()),
    );

    provider.dispose();
  });
}

DictionaryProvider _providerForStore(_DictionaryStore store) {
  return DictionaryProvider(
    autoload: false,
    upsertItem: store.upsert,
    upsertActiveItem: store.upsert,
    bulkUpsertItems: store.bulkUpsert,
    getItemByRaw: store.getByRaw,
    getItems: store.getItems,
    deleteItem: store.delete,
    clearItems: store.clear,
  );
}

class _DictionaryStore {
  _DictionaryStore({
    this.ignoreDeletes = false,
    this.ignoreClears = false,
    this.failBatchRaw,
  });

  final bool ignoreDeletes;
  final bool ignoreClears;
  final String? failBatchRaw;
  final Map<String, bridge.DictItem> items = <String, bridge.DictItem>{};
  int batchCalls = 0;

  String _key(String dictType, String raw) => '$dictType\u0000$raw';

  Future<void> upsert({
    required String dictType,
    required String raw,
    String? pinyin,
    String? abbreviation,
  }) async {
    items[_key(dictType, raw)] = _persistedItem(dictType, raw);
  }

  Future<void> bulkUpsert({required String requestJson}) async {
    batchCalls++;
    final before = Map<String, bridge.DictItem>.from(items);
    try {
      final request = json.decode(requestJson) as Map<String, dynamic>;
      for (final item in request['items'] as List<dynamic>) {
        final map = item as Map<String, dynamic>;
        final raw = map['raw'] as String;
        if (raw == failBatchRaw) {
          throw StateError('forced batch failure');
        }
        await upsert(
          dictType: map['dictType'] as String,
          raw: raw,
          pinyin: map['pinyin'] as String?,
          abbreviation: map['abbreviation'] as String?,
        );
      }
    } catch (_) {
      items
        ..clear()
        ..addAll(before);
      rethrow;
    }
  }

  Future<bridge.DictItem?> getByRaw({
    required String dictType,
    required String raw,
  }) async =>
      items[_key(dictType, raw)];

  Future<List<bridge.DictItem>> getItems({required String dictType}) async {
    return items.values
        .where((item) => item.dictType == dictType)
        .toList(growable: false);
  }

  Future<bool> delete({
    required String dictType,
    required String raw,
  }) async {
    if (ignoreDeletes) return false;
    return items.remove(_key(dictType, raw)) != null;
  }

  Future<void> clear({required String dictType}) async {
    if (ignoreClears) return;
    items.removeWhere((_, item) => item.dictType == dictType);
  }
}

bridge.DictItem _persistedItem(String dictType, String raw) {
  const timestamp = '2026-07-13T00:00:00Z';
  return bridge.DictItem(
    dictType: dictType,
    raw: raw,
    pinyin: '',
    abbreviation: '',
    syncId: 'persisted-$raw',
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}
