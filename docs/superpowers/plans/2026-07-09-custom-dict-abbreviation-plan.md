# 自定义词条拼音/缩写自动生成实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为手动添加/导入的设备、天线、QTH 词条自动生成拼音和缩写，并持久化到 Rust 数据库；同时回填旧数据中空缺的拼音/缩写。

**Architecture:** 在 Dart 侧新增一个纯函数 helper，基于 `lpinyin` 生成拼音和缩写；`DictionaryProvider` 在添加、导入、启动加载三个入口调用 helper，并通过已有的 `RustApi.addDictItem` / `RustApi.upsertDictItem` 写入 Rust。

**Tech Stack:** Flutter/Dart, `lpinyin`, `flutter_rust_bridge`, Rust/sqlx。

---

## Task 1: 添加 `lpinyin` 依赖

**Files:**
- Modify: `pubspec.yaml:33`

- [ ] **Step 1: 在 `dependencies` 中加入 `lpinyin`**

```yaml
  flutter_rust_bridge: 2.12.0
  lpinyin: ^2.0.3
```

- [ ] **Step 2: 获取依赖**

Run:
```bash
flutter pub get
```

Expected: `lpinyin` downloaded without errors.

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "deps: 添加 lpinyin 用于自定义词条拼音/缩写生成"
```

---

## Task 2: 创建 `DictionaryPinyinHelper`

**Files:**
- Create: `lib/utils/dictionary_pinyin_helper.dart`
- Test: `test/utils/dictionary_pinyin_helper_test.dart`

- [ ] **Step 1: 写 failing test**

Create `test/utils/dictionary_pinyin_helper_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/utils/dictionary_pinyin_helper.dart';

void main() {
  group('DictionaryPinyinHelper', () {
    test('generates pinyin and abbreviation for Chinese', () {
      final result = DictionaryPinyinHelper.generate('华鸿 S518');
      expect(result.pinyin, 'hua hong s518');
      expect(result.abbreviation, 'hhs518');
    });

    test('keeps English and digits as-is', () {
      final result = DictionaryPinyinHelper.generate('ICOM 7300');
      expect(result.pinyin, 'icom 7300');
      expect(result.abbreviation, 'icom7300');
    });

    test('handles mixed Chinese and model numbers', () {
      final result = DictionaryPinyinHelper.generate('钻石 X-50');
      expect(result.pinyin, 'zuan shi x-50');
      expect(result.abbreviation, 'zsx50');
    });

    test('returns empty for empty input', () {
      final result = DictionaryPinyinHelper.generate('');
      expect(result.pinyin, '');
      expect(result.abbreviation, '');
    });
  });
}
```

Run:
```bash
flutter test test/utils/dictionary_pinyin_helper_test.dart
```

Expected: FAIL with `Target of URI doesn't exist: 'package:openlogtool/utils/dictionary_pinyin_helper.dart'`.

- [ ] **Step 2: 实现 helper**

Create `lib/utils/dictionary_pinyin_helper.dart`:

```dart
import 'package:lpinyin/lpinyin.dart';

class PinyinResult {
  final String pinyin;
  final String abbreviation;

  const PinyinResult({required this.pinyin, required this.abbreviation});
}

class DictionaryPinyinHelper {
  static PinyinResult generate(String raw) {
    if (raw.trim().isEmpty) {
      return const PinyinResult(pinyin: '', abbreviation: '');
    }
    try {
      final pinyin = PinyinHelper.getPinyinE(
        raw,
        separator: ' ',
        format: PinyinFormat.WITHOUT_TONE,
      ).toLowerCase();
      final abbreviation = PinyinHelper.getShortPinyin(raw).toLowerCase();
      return PinyinResult(pinyin: pinyin, abbreviation: abbreviation);
    } catch (_) {
      final fallback = raw.toLowerCase();
      return PinyinResult(pinyin: fallback, abbreviation: fallback);
    }
  }
}
```

- [ ] **Step 3: 运行测试**

Run:
```bash
flutter test test/utils/dictionary_pinyin_helper_test.dart
```

Expected: all 4 tests pass.

- [ ] **Step 4: Commit**

```bash
git add lib/utils/dictionary_pinyin_helper.dart test/utils/dictionary_pinyin_helper_test.dart
git commit -m "feat(dict): 添加自定义词条拼音/缩写生成 helper"
```

---

## Task 3: 修改 `DictionaryProvider` 写入拼音/缩写

**Files:**
- Modify: `lib/providers/dictionary_provider.dart`

- [ ] **Step 1: 引入 helper**

在 `lib/providers/dictionary_provider.dart` 顶部加入：

```dart
import 'package:openlogtool/utils/dictionary_pinyin_helper.dart';
```

- [ ] **Step 2: 修改 `_addDictItem`：手动添加时生成拼音/缩写**

替换当前 `_addDictItem` 中调用 `RustApi.addDictItem` 的部分：

```dart
  Future<void> _addDictItem(
    String dictType,
    String raw,
    List<DictionaryItem> target,
  ) async {
    if (raw.isEmpty || target.any((d) => d.raw == raw)) return;
    try {
      final generated = DictionaryPinyinHelper.generate(raw);
      await RustApi.addDictItem(
        dictType: dictType,
        raw: raw,
        pinyin: generated.pinyin,
        abbreviation: generated.abbreviation,
      );
      final persisted = await RustApi.getDictItemByRaw(dictType: dictType, raw: raw);
      target.add(persisted != null
          ? _toOldDictItem(persisted)
          : DictionaryItem(
              raw: raw,
              pinyin: generated.pinyin,
              abbreviation: generated.abbreviation,
              type: dictType,
            ));
      target.sort((a, b) => a.raw.compareTo(b.raw));
      _safeNotify();
      await _notifyDictionaryChanged();
    } catch (e, st) {
      debugPrint('[DictionaryProvider] _addDictItem failed: $e\n$st');
      rethrow;
    }
  }
```

- [ ] **Step 3: 修改 `_importDictItems`：批量导入时生成拼音/缩写**

替换当前 `_importDictItems`：

```dart
  Future<void> _importDictItems(
    String dictType,
    List<String> items,
    List<DictionaryItem> target,
  ) async {
    for (final raw in items) {
      if (target.any((d) => d.raw == raw)) continue;
      final generated = DictionaryPinyinHelper.generate(raw);
      await RustApi.addDictItem(
        dictType: dictType,
        raw: raw,
        pinyin: generated.pinyin,
        abbreviation: generated.abbreviation,
      );
      final persisted = await RustApi.getDictItemByRaw(dictType: dictType, raw: raw);
      target.add(persisted != null
          ? _toOldDictItem(persisted)
          : DictionaryItem(
              raw: raw,
              pinyin: generated.pinyin,
              abbreviation: generated.abbreviation,
              type: dictType,
            ));
    }
    target.sort((a, b) => a.raw.compareTo(b.raw));
    _safeNotify();
    await _notifyDictionaryChanged();
  }
```

- [ ] **Step 4: 新增启动回填方法 `_backfillMissingPinyin`**

在 `_loadDictionaries` 附近新增：

```dart
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
      await RustApi.upsertDictItem(
        dictType: dictType,
        raw: item.raw,
        pinyin: generated.pinyin,
        abbreviation: generated.abbreviation,
      );
    }
  }
```

- [ ] **Step 5: 在 `_loadDictionaries` 中调用回填**

把 `_loadDictionaries` 中 `await _syncBuiltinDictionaries();` 之后、重新加载列表之前的部分改为：

```dart
      // 每次启动都同步内置词库，补全缺失的拼音/缩写，同时保留用户自定义内容。
      await _syncBuiltinDictionaries();
      // 为旧版本没有拼音/缩写的自定义词条生成并回填。
      await _backfillMissingPinyin();
      _deviceDict = await _getDictItems('device_dictionary');
      _antennaDict = await _getDictItems('antenna_dictionary');
      _callsignDict = await _getDictItems('callsign_dictionary');
      _qthDict = await _getDictItems('qth_dictionary');
```

- [ ] **Step 6: 修改 `importFromJson`：支持对象中的 pinyin/abbreviation，缺失时自动生成**

替换 `_extractItems` 为返回 richer 对象，或直接 inline 处理。这里采用最小改动：把 `importDevices` / `importAntennas` / `importCallsigns` / `importQths` 的字符串列表导入，改为 `_importDictItemsWithPinyin`：

```dart
  Future<void> _importDictItemsWithPinyin(
    String dictType,
    List<String> items,
    List<DictionaryItem> target,
  ) async {
    await _importDictItems(dictType, items, target);
  }
```

更简单的方式：由于 `_importDictItems` 已在 Step 3 中自动生成，JSON 数组字符串导入已经覆盖。对于 JSON 对象导入，把 `_extractItems` 改造为返回 `List<MapEntry<String, String?>>` 过于复杂。**推荐方案**：在 `importFromJson` 中，对对象数组里的 `pinyin`/`abbreviation` 做一次性 upsert，不走原来的字符串导入。

具体修改：在 `importFromJson` 中，把每个分类的对象数组提取为：

```dart
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
      counts['qth'] = await _importTypedJson(
          'qth_dictionary', jsonData['qths'], _qthDict);
    } else if (jsonData is List) {
      final items = _extractItems(jsonData);
      if (items.isNotEmpty) {
        await importDevices(items);
        counts['device'] = items.length;
      }
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
    for (final item in items) {
      if (target.any((d) => d.raw == item.raw)) continue;
      final pinyin = item.pinyin?.isNotEmpty == true
          ? item.pinyin
          : DictionaryPinyinHelper.generate(item.raw).pinyin;
      final abbreviation = item.abbreviation?.isNotEmpty == true
          ? item.abbreviation
          : DictionaryPinyinHelper.generate(item.raw).abbreviation;
      await RustApi.upsertDictItem(
        dictType: dictType,
        raw: item.raw,
        pinyin: pinyin,
        abbreviation: abbreviation,
      );
      target.add(DictionaryItem(
        raw: item.raw,
        pinyin: pinyin ?? '',
        abbreviation: abbreviation ?? '',
        type: dictType,
      ));
    }
    target.sort((a, b) => a.raw.compareTo(b.raw));
    _safeNotify();
    await _notifyDictionaryChanged();
    return items.length;
  }
```

并新增辅助类和修改 `_extractItems`：

```dart
class _RawPinyinAbbrev {
  final String raw;
  final String? pinyin;
  final String? abbreviation;

  _RawPinyinAbbrev(this.raw, {this.pinyin, this.abbreviation});
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
```

旧的 `_extractItems` 如果不再使用可以删除；若 `importDevices` 等仍被外部调用则保留。当前 `importDevices` 等只在 `importFromJson` 的 List 分支中使用，保留即可。

- [ ] **Step 7: 运行测试**

Run:
```bash
flutter test
```

Expected: all existing tests pass (helper tests + existing 8 tests).

- [ ] **Step 8: Commit**

```bash
git add lib/providers/dictionary_provider.dart
flutter analyze --no-fatal-infos && flutter test
git commit -m "feat(dict): 自定义词条添加/导入时自动生成拼音/缩写，并回填旧数据"
```

---

## Task 4: 验证与构建

**Files:**
- All of the above

- [ ] **Step 1: 分析器检查**

Run:
```bash
flutter analyze --no-fatal-infos
```

Expected: `No issues found!`

- [ ] **Step 2: 全量测试**

Run:
```bash
flutter test
```

Expected: `All tests passed!`

- [ ] **Step 3: Linux 构建**

Run:
```bash
flutter build linux --debug
```

Expected: `✓ Built build/linux/x64/debug/bundle/openlogtool`

- [ ] **Step 4: 清理 Rust 缓存并重新构建（防止 content-hash 不匹配）**

Run:
```bash
cd rust && cargo clean && cd ..
flutter build linux --debug
```

Expected: build succeeds.

- [ ] **Step 5: 最终 commit**

```bash
git add -A
git commit -m "test/build: 自定义词条拼音/缩写功能验证通过"
```

---

## Self-Review Checklist

- [ ] `pubspec.yaml` 已添加 `lpinyin: ^2.0.3`。
- [ ] `DictionaryPinyinHelper.generate` 返回 `{pinyin, abbreviation}`，空串和异常均有 fallback。
- [ ] `_addDictItem` 手动添加时传入生成的 pinyin/abbreviation。
- [ ] `_importDictItems` 批量导入字符串时生成 pinyin/abbreviation。
- [ ] `_loadDictionaries` 启动时回填旧自定义词条的 pinyin/abbreviation。
- [ ] `importFromJson` 对 Map 格式支持对象中的 `pinyin`/`abbreviation`，缺失时自动生成。
- [ ] helper 单元测试覆盖中文、中英混合、纯英文/数字、空串。
- [ ] analyzer、test、linux build 全部通过。
