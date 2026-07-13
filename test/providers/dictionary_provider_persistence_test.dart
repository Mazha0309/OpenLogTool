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

  test('plain-list import never adds an unreadable tombstoned item', () async {
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

    expect(
      provider.deviceDict.map((item) => item.raw),
      const <String>['Persisted radio'],
    );
    expect(
      provider.deviceDict.any((item) => item.raw == 'Soft-deleted radio'),
      isFalse,
    );
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
