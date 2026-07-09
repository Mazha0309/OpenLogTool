# 自定义词条拼音/缩写自动生成设计

## 目标
当用户手动添加或导入设备、天线、QTH 词条时，自动为其生成拼音和缩写，并持久化到 Rust SQLite，使后续可以通过缩写/拼音进行联想搜索。

## 背景
- 内置词库已通过 `assets/dictionaries/*.json` 提供 `raw`/`pinyin`/`abbreviation`，无需改动。
- 用户之前手动添加的自定义词条，`pinyin` 和 `abbreviation` 字段为空，缩写搜索不可用。
- `RustApi.addDictItem` / `RustApi.upsertDictItem` 已支持传入可选的 `pinyin` 和 `abbreviation`。

## 生成规则
使用 Dart 包 `lpinyin: ^2.0.3`。

| 输入 | 拼音 | 缩写 |
|------|------|------|
| `华鸿 S518` | `huahong s518` | `hhs518` |
| `ICOM 7300` | `icom 7300` | `icom7300` |
| `钻石 X-50` | `zuan shi x-50` | `zsx50` |

- **拼音**：`PinyinHelper.getPinyinE(raw, separator: ' ', format: PinyinFormat.WITHOUT_TONE)`，失败时回退为 `raw.toLowerCase()`。
- **缩写**：`PinyinHelper.getShortPinyin(raw)`，失败时回退为 `raw.toLowerCase()`。

说明：
- 中文每个汉字转拼音，无音标，词间用空格分隔。
- 缩写取每个汉字拼音首字母；英文、数字、模型编号原样保留；标点/分隔符由 `lpinyin` 处理。

## 架构

```
lib/utils/dictionary_pinyin_helper.dart
        │
        ▼
lib/providers/dictionary_provider.dart
        │
        ▼
RustApi.addDictItem / upsertDictItem
        │
        ▼
rust/src/dict/search.rs (INSERT / upsert)
```

## 文件变更

### 新增
- `lib/utils/dictionary_pinyin_helper.dart`：纯函数工具类。

### 修改
- `pubspec.yaml`：添加依赖 `lpinyin: ^2.0.3`。
- `lib/providers/dictionary_provider.dart`：
  - `_addDictItem`：手动添加时调用 helper 生成拼音/缩写，再写入 Rust。
  - `_importDictItems`：批量导入时同样生成。
  - `_loadDictionaries`：启动时扫描自定义词库中 `abbreviation` 为空的旧词条，回填。
  - `importFromJson`：若 JSON 对象未提供 `pinyin`/`abbreviation`，则自动生成。

## 数据流

### 新添加词条
1. 用户在表单输入自定义设备/天线/QTH。
2. `DictionaryProvider._addDictItem` 调用 `DictionaryPinyinHelper` 生成 `pinyin` 和 `abbreviation`。
3. 调用 `RustApi.addDictItem(dictType, raw, pinyin, abbreviation)`。
4. Rust `add_dict_item` 执行 `INSERT OR IGNORE`。

### 旧词条回填
1. 应用启动，`DictionaryProvider._loadDictionaries` 从 Rust 加载词库。
2. 对 `device_dictionary` / `antenna_dictionary` / `qth_dictionary` 中 `abbreviation.isEmpty` 的条目，生成拼音/缩写。
3. 调用 `RustApi.upsertDictItem(dictType, raw, pinyin, abbreviation)` 更新（`COALESCE(NULLIF(...), excluded...)` 保证不覆盖用户已自定义的值）。

### JSON 导入
- 字符串/仅含 `raw` 的对象：自动生成拼音/缩写。
- 含 `pinyin`/`abbreviation` 的对象：直接使用给定值，不再生成。

## 错误处理
- `lpinyin` 对非中文字符通常原样返回，不会抛异常。
- 若任何步骤抛异常，catch 后回退为 `raw.toLowerCase()` 作为拼音和缩写，确保添加/导入不中断。

## 测试计划
- `test/utils/dictionary_pinyin_helper_test.dart`：
  - 纯中文 → 拼音/缩写正确。
  - 中英混合 → 缩写首字母 + 英文保留。
  - 纯英文/数字 → 原样小写。
  - 空串 → 返回空。

## 兼容性
- 不影响内置词库加载流程。
- 不破坏现有 `DictionaryItem.matches` 搜索逻辑（仍按 raw/pinyin/abbreviation 匹配）。
- 回填空字段使用 `upsertDictItem`，不会覆盖用户已手动设置的拼音/缩写。
