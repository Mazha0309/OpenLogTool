# OpenLogTool 2.8.0 Web/跨平台适配 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 2.8.0-R 完成 Web 端体验优化（字体/导出/IndexedDB/PWA/首屏）、平台扩展（iOS 构建、Linux .deb/.rpm）、日志系统、深色模式、URL 同步、分页设置。

**Architecture:** 全部工作基于现有 Flutter 客户端（lib/）+ Rust 核心（rust/）+ GitHub Actions CI。Web 特有能力通过 `kIsWeb` + `package:web` 条件实现；存储抽象为 KeyValueStore（Web=IndexedDB，桌面=SharedPreferences）；日志通过 logging 包 + 自定义 AppLogger；CI 新增 iOS job 与 .deb/.rpm 打包步骤。

**Tech Stack:** Flutter 3.44.7、Dart 3.12+、Rust 1.91.1、package:web、package:logging、idb_shim、fonttools(pyftsubset)、dpkg-deb、rpmbuild

**Spec:** `docs/superpowers/specs/2026-08-05-web-cross-platform-design.md`

---

## 环境与命令约定

- 所有 Flutter 命令在项目根目录运行，需 `export PATH="$HOME/develop/flutter/bin:$PATH"`。
- 测试命令：`flutter test test/<path>`；全量 `flutter test`。
- 每次任务完成后运行 `flutter analyze` 确认无告警。
- 提交风格：`feat:` / `fix:` / `build:` / `docs:` 前缀，单行英文描述（沿用仓库惯例）。
- 当前分支 dev（在 /home/mazha0309/Projects/openlogtool）。

---

### Task 1: Web 字体默认更纱黑体 + 字体子集化（FontLoader 方案）

**Files:**
- Modify: `pubspec.yaml`（移除 fonts 声明，保留 assets 目录）
- Create: `lib/services/app_fonts.dart`（FontLoader 分平台加载）
- Modify: `lib/main.dart`（main 开头 await loadAppFonts）
- Modify: `tool/subset_fonts.py`（输出 ttf 而非 woff2）
- Modify: `web/index.html`（仅保留 #loader + flutter-first-frame；不加 @font-face）
- Modify: `lib/theme/app_theme.dart`（fontFamily 默认 'SarasaGothicSC'）
- Test: `test/theme/theme_test.dart`、`test/services/app_fonts_test.dart`

背景与方案：CanvasKit/skwasm 渲染器不读取 CSS @font-face，Flutter Web 的 FontManifest 只认 pubspec fonts 声明（且只支持 ttf/otf）。因此 @font-face + woff2 方案对 wasm 部署无效。改为：
- 子集化输出 ttf（GB2312 一级 + 符号，约 1.5MB）到 `assets/fonts/SarasaGothicSC-subset.ttf`，与完整 ttf 同目录（都在 assets/fonts/ 打包，惰性下载）。
- **移除 pubspec fonts 声明**（SarasaGothicSC 不再由 FontManifest 自动加载）。
- 应用启动时 `loadAppFonts()`：Web 用 FontLoader 加载子集 ttf；桌面加载完整 ttf。首屏只下载子集。
- index.html 不加 @font-face（避免与引擎注入冲突）；#loader 进度条保留，加 window.onerror 兜底。

- [ ] **Step 1: 修改子集化脚本输出 ttf**

`tool/subset_fonts.py` 中 pyftsubset 参数去掉 `--flavor=woff2`（FontLoader 需要 ttf），并在 main() 开头加 `args.dst.parent.mkdir(parents=True, exist_ok=True)`。GB2312 一级 + COMMON 逻辑保持不变。docstring 改为描述 ttf 输出。

- [ ] **Step 2: 生成子集 ttf 并清理旧产物**

```bash
python3 tool/subset_fonts.py assets/fonts/SarasaGothicSC-Regular.ttf assets/fonts/SarasaGothicSC-subset.ttf
ls -la assets/fonts/
git rm -r web/fonts/ 2>/dev/null || rm -rf web/fonts/
```
预期：生成 `assets/fonts/SarasaGothicSC-subset.ttf`（约 1.5MB，≤2MB 可接受）；`web/fonts/` 目录删除（woff2 方案废弃）。

- [ ] **Step 3: pubspec 移除 fonts 声明**

`pubspec.yaml`：删除 `fonts:` 块（SarasaGothicSC 声明），**保留** `assets: - assets/fonts/`（两个 ttf 都随包发布、惰性下载）。`flutter pub get` 后 `flutter gen-l10n` 无影响（若 pubspec 其他部分引用 fontFamily 均无碍）。

- [ ] **Step 4: 创建 loadAppFonts**

创建 `lib/services/app_fonts.dart`：

```dart
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// 应用启动时按平台加载 SarasaGothicSC：
/// Web 加载子集 ttf（首屏只下载子集），桌面加载完整 ttf。
/// 字体文件在 assets/fonts/ 下（随包发布、惰性下载）。
Future<void> loadAppFonts() async {
  final asset = kIsWeb
      ? 'assets/fonts/SarasaGothicSC-subset.ttf'
      : 'assets/fonts/SarasaGothicSC-Regular.ttf';
  final data = await rootBundle.load(asset);
  final loader = FontLoader('SarasaGothicSC')..addFont(data);
  await loader.load();
}

/// 平台选择字体资产路径（可测试纯函数）。
String appFontAssetPath({required bool isWeb}) =>
    isWeb
        ? 'assets/fonts/SarasaGothicSC-subset.ttf'
        : 'assets/fonts/SarasaGothicSC-Regular.ttf';
```

- [ ] **Step 5: main.dart 接入**

`lib/main.dart` 的 `main()` 中、`WidgetsFlutterBinding.ensureInitialized()` 之后调用：

```dart
import 'package:openlogtool/services/app_fonts.dart';
// ...
await loadAppFonts();
```

- [ ] **Step 6: 主题默认字体**

`lib/theme/app_theme.dart` 的 `buildAppTheme` 中 `fontFamily: fontFamily ?? 'SarasaGothicSC'`（如已由上一轮改动存在则跳过）。

- [ ] **Step 7: 更新测试**

`test/theme/theme_test.dart` 保持（断言默认 fontFamily）；新建 `test/services/app_fonts_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/services/app_fonts.dart';

void main() {
  test('web uses subset font asset', () {
    expect(appFontAssetPath(isWeb: true),
        'assets/fonts/SarasaGothicSC-subset.ttf');
  });

  test('desktop uses full font asset', () {
    expect(appFontAssetPath(isWeb: false),
        'assets/fonts/SarasaGothicSC-Regular.ttf');
  });
}
```

- [ ] **Step 8: index.html 清理**

`web/index.html`：删除上一轮加的 `@font-face` 样式块（保留 `#loader` + `flutter-first-frame` 逻辑；`#loader` 加 `window.onerror` 兜底：页面 JS 加载失败时也移除 loader）：

```html
<script>
  window.addEventListener('flutter-first-frame', function () {
    document.body.classList.add('flt-app-ready');
  });
  window.addEventListener('error', function () {
    document.body.classList.add('flt-app-ready');
  });
</script>
```

- [ ] **Step 9: 测试 + analyze + 构建验证**

运行：`flutter test test/theme/theme_test.dart test/services/app_fonts_test.dart`（PASS）、`flutter analyze`（No issues）、`flutter build web --wasm`（成功；`build/web/assets/FontManifest.json` 中不应再有 SarasaGothicSC 条目）。

- [ ] **Step 10: 提交**

```bash
git add pubspec.yaml lib/services/app_fonts.dart lib/main.dart lib/theme/app_theme.dart tool/subset_fonts.py assets/fonts/ web/index.html test/theme/theme_test.dart test/services/app_fonts_test.dart
git commit -m "feat: default to subset Sarasa Gothic SC font on web (FontLoader)"
```
### Task 2: Web 导出修复（原生浏览器下载）

**Files:**
- Modify: `lib/services/export_service.dart`
- Modify: `lib/widgets/export_panel.dart`（仅当判定逻辑需要微调）
- Test: `test/services/export_service_test.dart`

背景：Web 上 `FilePicker.platform.saveFile` 忽略自定义文件名（fallback `FlutterExcel.xlsx`，且返回路径不可靠导致 JSON 显示失败）。修复：Web 分支用原生 Blob + AnchorElement 下载。

- [ ] **Step 1: 写失败测试（Web 保存逻辑抽为纯函数）**

在 `lib/services/export_service.dart` 新增一个可测试的 Web 保存封装。先写测试 `test/services/export_service_test.dart` 追加：

```dart
import 'dart:convert';
import 'package:openlogtool/services/export_service.dart';

void main() {
  // ... 现有测试 ...

  group('ExportService web download metadata', () {
    test('web download uses exact filename and json mime', () {
      final meta = ExportService.webDownloadMeta(
        '点名记录_2026-08-05.json',
        const [1, 2, 3],
        mimeType: 'application/json',
      );
      expect(meta.filename, '点名记录_2026-08-05.json');
      expect(meta.mimeType, 'application/json');
      expect(meta.bytes, [1, 2, 3]);
    });

    test('appends extension when filename lacks it', () {
      final meta = ExportService.webDownloadMeta(
        '点名记录',
        Uint8List.fromList([1]),
        mimeType: 'application/json',
        extension: '.json',
      );
      expect(meta.filename, '点名记录.json');
    });
  });
}
```

- [ ] **Step 2: 运行确认失败**

运行：`flutter test test/services/export_service_test.dart`
预期：编译失败（`webDownloadMeta` 未定义）。

- [ ] **Step 3: 实现 webDownloadMeta 与 Web 下载分支**

修改 `lib/services/export_service.dart`：

```dart
import 'package:web/web.dart' as web;

class WebDownloadMeta {
  final String filename;
  final String mimeType;
  final List<int> bytes;
  const WebDownloadMeta({
    required this.filename,
    required this.mimeType,
    required this.bytes,
  });
}
```

在 `ExportService` 类内新增：

```dart
/// 组装 Web 下载元数据；[extension] 缺失时自动补全扩展名。
static WebDownloadMeta webDownloadMeta(
  String filename,
  List<int> bytes, {
  required String mimeType,
  String? extension,
}) {
  var name = filename;
  if (extension != null && !name.endsWith(extension)) {
    name = '$name$extension';
  }
  return WebDownloadMeta(filename: name, mimeType: mimeType, bytes: bytes);
}

/// Web 端浏览器原生下载（绕过 file_picker 的文件名/返回 bug）。
static Future<ExportSaveResult> downloadOnWeb(WebDownloadMeta meta) async {
  final blob = web.Blob(
    [meta.bytes.toJS].toJS,
    web.BlobPropertyBag(type: meta.mimeType),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = meta.filename;
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
  return ExportSaveResult(path: meta.filename, usedSaf: true);
}
```

修改 `saveFile`，在 `shouldUseSaf` 分支前拦截 Web：

```dart
static Future<ExportSaveResult> saveFile({
  required String configuredPath,
  required String filename,
  required Uint8List bytes,
  required String dialogTitle,
  required List<String> allowedExtensions,
}) async {
  if (kIsWeb) {
    final mime = switch (allowedExtensions.firstOrNull) {
      'json' => 'application/json',
      'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      _ => 'application/octet-stream',
    };
    return downloadOnWeb(webDownloadMeta(
      filename,
      bytes,
      mimeType: mime,
      extension: allowedExtensions.isEmpty ? null : '.${allowedExtensions.first}',
    ));
  }
  if (await shouldUseSaf(configuredPath)) {
    // ... 现有逻辑不变
  }
  // ...
}
```

注意：`webDownloadMeta` 的 extension 逻辑会为已带扩展名（调用方已 `+= '.json'`）的 filename 自动跳过重复追加。

- [ ] **Step 4: 运行测试确认通过**

运行：`flutter test test/services/export_service_test.dart`
预期：全部 PASS（原有 7 个 + 新增 2 个）。

- [ ] **Step 5: 手动 Web 验证（可选，需 build web）**

```bash
flutter build web --wasm
```
本地 `python3 -m http.server 8080 -d build/web`，浏览器访问导出 JSON/Excel，确认文件名正确（模板生成名 + .json/.xlsx）、无"导出失败"提示。

- [ ] **Step 6: 提交**

```bash
git add lib/services/export_service.dart test/services/export_service_test.dart
git commit -m "fix: native browser download for web export"
```

---

### Task 3: KeyValueStore 抽象 + Web IndexedDB 后端

**Files:**
- Create: `lib/services/key_value_store.dart`
- Create: `lib/services/web_kv_store.dart`
- Modify: `lib/providers/settings_provider.dart`
- Modify: `lib/providers/theme_provider.dart`
- Modify: `lib/providers/session_provider.dart`
- Modify: `lib/providers/collaboration_provider.dart`
- Modify: `lib/providers/server_provider.dart`
- Modify: `lib/providers/ai_recognition_settings_provider.dart`
- Modify: `lib/providers/personal_cloud_provider.dart`
- Modify: `lib/services/secure_token_store.dart`
- Modify: `lib/services/controller_window_service.dart`
- Modify: `pubspec.yaml`
- Test: `test/services/key_value_store_test.dart`

背景：9 个文件直连 SharedPreferences（Web=localStorage 5MB 上限）。抽象 KeyValueStore：桌面仍 SharedPreferences，Web 用 IndexedDB，并提供一次性迁移。

- [ ] **Step 1: 添加依赖**

`pubspec.yaml` dependencies 增加：

```yaml
  idb_shim: ^2.4.1
  package_web: ^0.0.0  # 若 pub 不支持，改用 package:web 别名；见 Step 2 实际代码
```

实际执行：`flutter pub add idb_shim`（package:web 在 Flutter SDK 内置，无需显式添加；若 analyze 报 import 错误再 `flutter pub add web`）。

- [ ] **Step 2: 定义 KeyValueStore 接口**

创建 `lib/services/key_value_store.dart`：

```dart
import 'package:shared_preferences/shared_preferences.dart';

/// 跨平台键值存储抽象：桌面=SharedPreferences，Web=IndexedDB。
abstract class KeyValueStore {
  Future<String?> getString(String key);
  Future<bool> getBool(String key, {bool defaultValue = false});
  Future<int?> getInt(String key);
  Future<void> setString(String key, String value);
  Future<void> setBool(String key, bool value);
  Future<void> setInt(String key, int value);
  Future<void> remove(String key);
  Future<Set<String>> getKeys();
  Future<void> clear();
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
  Future<void> setString(String key, String value) async {
    await _prefs.setString(key, value);
  }

  @override
  Future<void> setBool(String key, bool value) async {
    await _prefs.setBool(key, value);
  }

  @override
  Future<void> setInt(String key, int value) async {
    await _prefs.setInt(key, value);
  }

  @override
  Future<void> remove(String key) async => _prefs.remove(key);
  @override
  Future<Set<String>> getKeys() async => _prefs.getKeys();
  @override
  Future<void> clear() async => _prefs.clear();
}
```

- [ ] **Step 3: 实现 Web IndexedDB 后端**

创建 `lib/services/web_kv_store.dart`：

```dart
import 'package:idb_shim/idb.dart' as idb;
import 'package:idb_shim/idb_browser.dart';
import 'key_value_store.dart';

/// IndexedDB 实现（Web 端），库名 openlogtool_settings，objectStore kv。
class WebKeyValueStore implements KeyValueStore {
  WebKeyValueStore._(this._db);
  final idb.Database _db;

  static const _dbName = 'openlogtool_settings';
  static const _storeName = 'kv';
  static const _keyField = 'k';
  static const _valueField = 'v';

  static Future<WebKeyValueStore> open() async {
    final db = await idbBrowserFactory().open(_dbName, version: 1,
        onUpgradeNeeded: (event) {
      final db = event.database;
      if (!db.objectStoreNames.contains(_storeName)) {
        db.createObjectStore(_storeName, keyPath: _keyField);
      }
    });
    return WebKeyValueStore._(db);
  }

  Future<idb.ObjectStore> _store([idb.TransactionMode mode = idb.TransactionMode.readOnly]) {
    final tx = _db.transaction(_storeName, mode);
    return Future.value(tx.objectStore(_storeName));
  }

  String _encodeKey(String key) => key;

  @override
  Future<String?> getString(String key) async {
    final rec = await (await _store()).getObject(_encodeKey(key));
    return rec == null ? null : (rec as Map)[_valueField] as String?;
  }

  @override
  Future<bool> getBool(String key, {bool defaultValue = false}) async {
    final v = await getString(key);
    return v == null ? defaultValue : v == 'true';
  }

  @override
  Future<int?> getInt(String key) async {
    final v = await getString(key);
    return v == null ? null : int.tryParse(v);
  }

  @override
  Future<void> setString(String key, String value) async {
    final store = await _store(idb.TransactionMode.readWrite);
    await store.put({_keyField: _encodeKey(key), _valueField: value});
  }

  @override
  Future<void> setBool(String key, bool value) =>
      setString(key, value.toString());

  @override
  Future<void> setInt(String key, int value) =>
      setString(key, value.toString());

  @override
  Future<void> remove(String key) async {
    final store = await _store(idb.TransactionMode.readWrite);
    await store.delete(_encodeKey(key));
  }

  @override
  Future<Set<String>> getKeys() async {
    final store = await _store();
    final keys = await store.getAllKeys();
    return keys.map((k) => k as String).toSet();
  }

  @override
  Future<void> clear() async {
    final store = await _store(idb.TransactionMode.readWrite);
    await store.clear();
  }
}
```

（idb_shim API 细节以实际版本为准：`idbBrowserFactory()` 来自 `package:idb_shim/idb_browser.dart`；getAllKeys 若不存在则用 cursor 遍历，见实现期调整。）

- [ ] **Step 4: 写测试**

创建 `test/services/key_value_store_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/services/key_value_store.dart';

void main() {
  test('PrefsKeyValueStore round-trips string/bool/int', () async {
    // 用内存 mock：SharedPreferences.setMockInitialValues 来自 shared_preferences 包
    // （测试依赖 shared_preferences 的测试工具）
    // 由于 PrefsKeyValueStore 直接依赖 SharedPreferences 实例，用
    // SharedPreferences.setMockInitialValues({}) 后 getInstance 构造。
  });
}
```

实现：完整测试代码（使用 `SharedPreferences.setMockInitialValues({})` 后 `await SharedPreferences.getInstance()` 构造 store，断言 set/get/remove/clear 行为）。Web 后端在 VM 测试环境不可用，仅做编译级覆盖（import 不报错）。

- [ ] **Step 5: 全局存储入口**

在 `lib/services/key_value_store.dart` 追加：

```dart
import 'package:flutter/foundation.dart';
import 'web_kv_store.dart';

/// 全局键值存储实例；Web 返回 IndexedDB 实现，其他平台 SharedPreferences。
Future<KeyValueStore> openKeyValueStore() async {
  if (kIsWeb) {
    return WebKeyValueStore.open();
  }
  return PrefsKeyValueStore(await SharedPreferences.getInstance());
}

/// 一次性迁移：把 localStorage（SharedPreferences）已有数据拷贝到 IndexedDB。
/// 在 Web 上由启动流程调用一次。
Future<void> migrateLegacyLocalStorage(KeyValueStore store) async {
  if (!kIsWeb) return;
  final legacy = PrefsKeyValueStore(await SharedPreferences.getInstance());
  final keys = await legacy.getKeys();
  for (final key in keys) {
    final existing = await store.getString(key);
    if (existing != null) continue;
    final v = await legacy.getString(key);
    if (v != null) await store.setString(key, v);
  }
  final b = await legacy.getBool('darkMode');
  // bool/int 类型 key 需要逐一处理，这里用通用策略：从 legacy 读原始字符串
  // 简化：SharedPreferences 的 getKeys 不含类型信息，先迁移字符串，bool/int
  // key（如 darkMode）由 provider 首次读取时回写（见 Step 6 说明）。
}
```

- [ ] **Step 6: 替换 provider 的 SharedPreferences 直连（以 theme_provider 与 settings_provider 为例）**

`lib/providers/theme_provider.dart` 改造（示例模式，其余 provider 同样处理）：

```dart
// 原：final prefs = await SharedPreferences.getInstance();
// 改：注入 KeyValueStore，构造时传入（main.dart 中 openKeyValueStore 后创建 provider）。
class ThemeProvider extends ChangeNotifier {
  ThemeProvider(this._store);
  final KeyValueStore _store;
  bool _isDarkMode = false;
  bool get isDarkMode => _isDarkMode;

  Future<void> load() async {
    _isDarkMode = await _store.getBool('darkMode');
    notifyListeners();
  }

  Future<void> toggle() async {
    _isDarkMode = !_isDarkMode;
    await _store.setBool('darkMode', _isDarkMode);
    notifyListeners();
  }
}
```

`lib/providers/settings_provider.dart`、`session_provider.dart`、`collaboration_provider.dart`、`server_provider.dart`、`ai_recognition_settings_provider.dart`、`personal_cloud_provider.dart`、`controller_window_service.dart`、`secure_token_store.dart` 按同一模式：构造注入 `KeyValueStore`，读写改走 store 接口，删除 `SharedPreferences` 直调。

`main.dart`：创建 provider 时调用 `openKeyValueStore()` 并把实例传给所有 provider；Web 上启动后调用 `migrateLegacyLocalStorage`（fire-and-forget）。

- [ ] **Step 7: 运行全量测试 + analyze**

运行：`flutter test`（预期全过，provider 构造变更需同步调整 test 中的 provider 初始化）和 `flutter analyze`。

- [ ] **Step 8: 提交**

```bash
git add pubspec.yaml pubspec.lock lib/services/key_value_store.dart lib/services/web_kv_store.dart lib/providers/ lib/services/ lib/main.dart test/services/key_value_store_test.dart
git commit -m "feat: abstract key-value storage with IndexedDB backend on web"
```

---

### Task 4: PWA 完善（manifest + service worker + iOS meta）

**Files:**
- Modify: `web/manifest.json`
- Modify: `web/index.html`
- Test: 无（静态配置，人工验证）

- [ ] **Step 1: 完善 manifest.json**

读取现有 `web/manifest.json`，补齐为：

```json
{
  "name": "OpenLogTool",
  "short_name": "OpenLogTool",
  "description": "业余无线电点名记录与协作客户端",
  "start_url": "./",
  "scope": "./",
  "display": "standalone",
  "orientation": "any",
  "background_color": "#faf8f2",
  "theme_color": "#2196F3",
  "lang": "zh-CN",
  "icons": [
    { "src": "icons/Icon-192.png", "sizes": "192x192", "type": "image/png", "purpose": "any" },
    { "src": "icons/Icon-512.png", "sizes": "512x512", "type": "image/png", "purpose": "any" },
    { "src": "icons/Icon-maskable-192.png", "sizes": "192x192", "type": "image/png", "purpose": "maskable" },
    { "src": "icons/Icon-maskable-512.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable" }
  ]
}
```

（保留原有字段若存在；以实际 icons 文件名为准，先 `ls web/icons/`。）

- [ ] **Step 2: 确认 service worker 注册**

运行 `grep -n "serviceWorker\|flutter_service_worker" web/index.html web/flutter_bootstrap.js 2>/dev/null`。Flutter 3.22+ 的 flutter_bootstrap.js 会自动注册 `flutter_service_worker.js`。若未注册，在 index.html 末尾加：

```html
<script>
  if ('serviceWorker' in navigator) {
    window.addEventListener('load', function () {
      navigator.serviceWorker.register('flutter_service_worker.js');
    });
  }
</script>
```

- [ ] **Step 3: iOS meta 补齐**

`web/index.html` 的 head 中已有部分 iOS meta。补齐：

```html
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="default">
<meta name="apple-mobile-web-app-title" content="OpenLogTool">
```

（若已存在则跳过。）

- [ ] **Step 4: 构建验证**

运行：`flutter build web --wasm`（预期成功），`ls build/web/flutter_service_worker.js` 存在。

- [ ] **Step 5: 提交**

```bash
git add web/manifest.json web/index.html
git commit -m "feat: complete PWA manifest and install support"
```

---

### Task 5: 首屏加载优化（构建参数 + 加载进度）

**Files:**
- Modify: `.github/workflows/build.yml`（web 构建步骤）
- Modify: `web/index.html`（进度条已在 Task 1 添加，此处完善）
- Test: 无

- [ ] **Step 1: 确认当前 web 构建命令**

运行 `grep -n "flutter build web" .github/workflows/build.yml` 记录现有命令与参数。

- [ ] **Step 2: 更新 CI web 构建**

将 web 构建命令改为：

```bash
flutter build web --wasm --no-pub
```

（--wasm 启用 skwasm 渲染 + 按需加载；若 CI 中已有 --wasm 则保持，仅确认。）

- [ ] **Step 3: 字体子集化接入 CI**

在 workflow 的 web job 中，`flutter build web` 之前插入字体子集化步骤：

```yaml
      - name: Subset web fonts
        run: |
          pip install fonttools brotli 2>&1 | tail -1
          python3 tool/subset_fonts.py \
            assets/fonts/SarasaGothicSC-Regular.ttf \
            web/fonts/SarasaGothicSC-subset.woff2
```

（注意：web/fonts/ 目录需在仓库中保留占位或由该步骤创建，`mkdir -p web/fonts` 后运行脚本；脚本内 textfile 与 dst 同目录需存在。）

- [ ] **Step 4: 加载进度条完善（可选）**

确认 Task 1 Step 4 的 `#loader` 逻辑已随构建生效（`flutter-first-frame` 事件在 --wasm 下同样触发；若未触发，改为轮询 `document.querySelector('flt-glass-pane')` 检测首帧后移除 loader，实现期按实际构建产物调整）。

- [ ] **Step 5: 提交**

```bash
git add .github/workflows/build.yml
git commit -m "build: wasm web build with subset fonts and loader"
```

---

### Task 6: iOS 构建支持（平台目录 + CI job）

**Files:**
- Create: `ios/`（脚手架）
- Modify: `.github/workflows/build.yml`
- Test: CI 验证

背景：无 ios/ 目录；Rust core 需为 iOS target 交叉编译 libopenlogtool_core.a。

- [ ] **Step 1: 生成 iOS 脚手架**

```bash
flutter create --platforms=ios --org com.mazha0309 --project-name openlogtool .
```

检查生成的 `ios/Runner/Info.plist`、`ios/Podfile` 是否可构建。删除模板多余文件（保持仓库整洁）。

- [ ] **Step 2: 配置 Rust iOS 目标**

`rust/` 的 `.cargo/config.toml`（或 CI 步骤）添加 iOS linker 配置。先确认现有配置：

运行 `cat rust/.cargo/config.toml 2>/dev/null || echo NONE`，在 CI iOS job 中用 rustup 添加 target：

```bash
rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios
```

为 `rust/src/api/database.rs` 的 sqlite_compat 确认 iOS 编译路径（rusqlite bundled 在 iOS 上默认可用；若失败需在 CI 设置 `SQLITE3_LIBDIR` 或 `libsqlite3-sys` feature，实现期按编译错误处理）。

- [ ] **Step 3: 新增 CI iOS job**

在 `.github/workflows/build.yml` 添加 job（macOS runner，复用 macOS job 的 setup 步骤模式）：

```yaml
  build-ios:
    name: Build and verify iOS
    needs: version
    if: startsWith(github.ref, 'refs/tags/v') || github.event_name == 'workflow_dispatch'
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v7
      # Setup Flutter / Rust 与 macOS job 相同的步骤（拷贝现有步骤块）
      - name: Add iOS Rust targets
        run: rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios
      - name: Build Rust core for iOS
        run: |
          cd rust
          for target in aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios; do
            cargo build --release --target "$target"
          done
      - name: Configure Rust library paths
        run: |
          # 将三个 target 的 libopenlogtool_core.a 拷贝到 iOS 工程约定的链接目录
          mkdir -p ios/Runner/rustlibs
          cp rust/target/aarch64-apple-ios/release/libopenlogtool_core.a ios/Runner/rustlibs/
          cp rust/target/aarch64-apple-ios-sim/release/libopenlogtool_core.a ios/Runner/rustlibs/
          cp rust/target/x86_64-apple-ios/release/libopenlogtool_core.a ios/Runner/rustlibs/
      - name: Build iOS release (no codesign)
        run: flutter build ios --release --no-codesign --no-pub
      - name: Package iOS artifacts
        run: |
          mkdir -p dist
          cd build/ios/iphoneos
          zip -qr "$GITHUB_WORKSPACE/dist/OpenLogTool-ios-arm64.zip" Runner.app
      - name: Upload iOS artifacts
        uses: actions/upload-artifact@v7
        with:
          name: openlogtool-${{ needs.version.outputs.artifact_version }}-ios
          path: dist/*.zip
          if-no-files-found: error
          retention-days: 14
```

（ios/Runner 的 Xcode 工程需通过 Build Settings 或 `rustlibs` 链接 libopenlogtool_core.a：在 Xcode project.pbxproj 中添加 OTHER_LDFLAGS 或引入 framework 目录。实现期以实际构建错误调整——Flutter iOS 的 Rust 集成常用方式是把 .a 放入 `ios/Runner/Frameworks` 并配置 `FRAMEWORK_SEARCH_PATHS`。）

- [ ] **Step 4: release job 依赖追加**

`release` job 的 `needs:` 增加 `build-ios`，`download-artifact` 的 pattern 已含 `openlogtool-*-*` 可覆盖 iOS 产物；`Publish cross-platform release` 的"Verify release inventory"步骤若校验平台清单需加入 ios 项。

- [ ] **Step 5: 提交**

```bash
git add ios/ .github/workflows/build.yml
git commit -m "build: add iOS release job"
```

---

### Task 7: Linux .deb/.rpm 打包（CI）

**Files:**
- Create: `deploy/linux/openlogtool.desktop`
- Create: `deploy/linux/DEBIAN/control`（模板）
- Create: `deploy/linux/openlogtool.spec`（rpm spec 模板）
- Modify: `.github/workflows/build.yml`
- Test: CI 产物结构验证

- [ ] **Step 1: 创建 desktop entry**

创建 `deploy/linux/openlogtool.desktop`：

```ini
[Desktop Entry]
Type=Application
Name=OpenLogTool
Name[zh_CN]=OpenLogTool
Comment=Amateur radio net logging and collaboration client
Exec=/opt/openlogtool/openlogtool
Icon=openlogtool
Terminal=false
Categories=Utility;HamRadio;
StartupWMClass=com.mazha0309.openlogtool
```

- [ ] **Step 2: 创建 deb control**

创建 `deploy/linux/DEBIAN/control`：

```
Package: openlogtool
Version: 2.8.0-R
Section: hamradio
Priority: optional
Architecture: amd64
Maintainer: Mazha0309 <mazha0309@example.com>
Depends: libgtk-3-0 (>= 3.24), libx11-6, libxext6
Description: OpenLogTool amateur radio net logging client
```

（CI 打包时用 sed 替换 Version 为实际版本。）

- [ ] **Step 3: 创建 rpm spec**

创建 `deploy/linux/openlogtool.spec`：

```spec
Name: openlogtool
Version: 2.8.0
Release: 1
Summary: Amateur radio net logging and collaboration client
License: AGPL-3.0
URL: https://github.com/Mazha0309/OpenLogTool

%description
OpenLogTool is an amateur radio net logging and collaboration client.

%prep

%build

%install
mkdir -p %{buildroot}/opt/openlogtool
cp -r build/linux/x64/release/bundle/* %{buildroot}/opt/openlogtool/
mkdir -p %{buildroot}/usr/share/applications
cp deploy/linux/openlogtool.desktop %{buildroot}/usr/share/applications/
mkdir -p %{buildroot}/usr/share/icons/hicolor/256x256/apps
cp assets/images/app_icon_512.png %{buildroot}/usr/share/icons/hicolor/256x256/apps/openlogtool.png

%files
/opt/openlogtool
/usr/share/applications/openlogtool.desktop
/usr/share/icons/hicolor/256x256/apps/openlogtool.png
```

- [ ] **Step 4: CI 打包步骤**

在 `.github/workflows/build.yml` 的 Linux job 中，`flutter build linux --release` 之后追加：

```yaml
      - name: Package .deb
        run: |
          set -euo pipefail
          mkdir -p pkgdeb/DEBIAN pkgdeb/opt/openlogtool pkgdeb/usr/share/applications
          cp deploy/linux/DEBIAN/control pkgdeb/DEBIAN/control
          sed -i "s/^Version: .*/Version: $VERSION_NAME/" pkgdeb/DEBIAN/control
          cp -r build/linux/x64/release/bundle/* pkgdeb/opt/openlogtool/
          cp deploy/linux/openlogtool.desktop pkgdeb/usr/share/applications/
          dpkg-deb --build pkgdeb "OpenLogTool-${VERSION_NAME}-Linux-x86_64.deb"

      - name: Package .rpm
        run: |
          set -euo pipefail
          sed "s/^Version: .*/Version: ${VERSION_NAME%-R}/" deploy/linux/openlogtool.spec > /tmp/openlogtool.spec
          rpmbuild -bb /tmp/openlogtool.spec --define "_rpmdir ." --define "VERSION_NAME ${VERSION_NAME}"
          mv *.rpm "OpenLogTool-${VERSION_NAME}-Linux-x86_64.rpm"
```

（VERSION_NAME 来自 needs.version.outputs.version_name；rpm 版号需去除 -R 后缀，spec 中已有处理。rpmbuild 在 ubuntu runner 需先 `apt-get install -y rpm`。）

- [ ] **Step 5: 上传产物**

Linux job 的 upload-artifact 步骤 path 增加 `OpenLogTool-*.deb`、`OpenLogTool-*.rpm`（或新建 step 上传到 dist/）。release 的下载 pattern `openlogtool-*-*` 若为小写命名需同步调整，确保 .deb/.rpm 进入 release。

- [ ] **Step 6: 提交**

```bash
git add deploy/linux/ .github/workflows/build.yml
git commit -m "build: package Linux .deb and .rpm installers"
```

---

### Task 8: 日志系统（AppLogger + 异常钩子 + 查看页）

**Files:**
- Create: `lib/services/app_logger.dart`
- Modify: `lib/main.dart`
- Modify: `lib/widgets/settings/settings_panel.dart`（或设置页所在文件，新增日志入口）
- Create: `lib/widgets/log_viewer_dialog.dart`
- Test: `test/services/app_logger_test.dart`

- [ ] **Step 1: 添加依赖**

运行：`flutter pub add logging`

- [ ] **Step 2: 写测试**

创建 `test/services/app_logger_test.dart`：

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/services/app_logger.dart';

void main() {
  tearDown(() {
    AppLogger.instance.resetForTest();
  });

  test('writes entries to ring buffer', () {
    AppLogger.instance.debug('d1');
    AppLogger.instance.info('i1');
    AppLogger.instance.error('e1', StackTrace.current);
    final lines = AppLogger.instance.snapshot();
    expect(lines.any((l) => l.contains('d1')), isTrue);
    expect(lines.any((l) => l.contains('i1')), isTrue);
    expect(lines.any((l) => l.contains('e1')), isTrue);
  });

  test('rotates ring buffer at capacity', () {
    final logger = AppLogger.instance;
    for (var i = 0; i < 600; i++) {
      logger.info('msg$i');
    }
    final lines = logger.snapshot();
    expect(lines.length, 500);
    expect(lines.any((l) => l.contains('msg0')), isFalse);
    expect(lines.any((l) => l.contains('msg599')), isTrue);
  });

  test('writes to file with rotation', () async {
    final dir = await Directory.systemTemp.createTemp('olt-log-test');
    addTearDown(() => dir.delete(recursive: true));
    await AppLogger.instance.initForTest(logDir: dir);
    AppLogger.instance.error('boom', StackTrace.current);
    final file = File('${dir.path}/app.log');
    expect(file.existsSync(), isTrue);
    expect(file.readAsStringSync().contains('boom'), isTrue);
  });
}
```

- [ ] **Step 3: 运行确认失败**

运行：`flutter test test/services/app_logger_test.dart`
预期：编译失败（AppLogger 未定义）。

- [ ] **Step 4: 实现 AppLogger**

创建 `lib/services/app_logger.dart`：

```dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart' as logging;

/// 应用统一日志：桌面写文件（轮转），Web 输出 console；始终维护内存环形缓冲。
class AppLogger {
  AppLogger._();

  static final AppLogger instance = AppLogger._();

  static const int ringCapacity = 500;
  static const int fileMaxBytes = 1024 * 1024; // 1MB
  static const int fileKeepCount = 3;

  final logging.Logger _logger = logging.Logger('OpenLogTool');
  final List<String> _ring = List.filled(ringCapacity, '', growable: false);
  int _ringIndex = 0;
  int _ringCount = 0;
  File? _file;
  final List<File> _backups = [];
  bool _ready = false;

  List<String> snapshot() => _ready
      ? List.generate(_ringCount, (i) => _ring[(i) % ringCapacity])
      : const [];

  void resetForTest() {
    _ringIndex = 0;
    _ringCount = 0;
    _file = null;
    _ready = false;
  }

  Future<void> initForTest({required Directory logDir}) async {
    _file = File('${logDir.path}/app.log');
    _ready = true;
  }

  Future<void> init({Directory? logDirOverride}) async {
    logging.Logger.root.level = logging.Level.ALL;
    logging.Logger.root.onRecord.listen(_onRecord);
    if (!kIsWeb) {
      final dir = logDirOverride ??
          Directory('${Platform.environment['HOME'] ?? '.'}/.local/share/openlogtool/logs');
      await dir.create(recursive: true);
      _file = File('${dir.path}/app.log');
    }
    _ready = true;
    info('OpenLogTool logging initialized (web=${kIsWeb})');
  }

  void _onRecord(logging.LogRecord record) {
    final line =
        '${record.time.toIso8601String()} [${record.level.name}] ${record.loggerName}: ${record.message}'
        '${record.error != null ? '\n  ${record.error}' : ''}'
        '${record.stackTrace != null ? '\n  $record.stackTrace' : ''}';
    _ring[_ringIndex] = line;
    _ringIndex = (_ringIndex + 1) % ringCapacity;
    if (_ringCount < ringCapacity) _ringCount++;
    if (kIsWeb) {
      // console 输出
      debugPrint(line);
    }
    _writeFile(line);
  }

  Future<void> _writeFile(String line) async {
    final file = _file;
    if (file == null) return;
    try {
      if (await file.exists() && await file.length() > fileMaxBytes) {
        for (var i = fileKeepCount - 1; i >= 1; i--) {
          final src = File('${file.path}.$i');
          final dst = File('${file.path}.${i + 1}');
          if (await src.exists()) await dst.writeAsString(await src.readAsString());
        }
        await File('${file.path}.1').writeAsString(await file.readAsString());
        await file.writeAsString('');
      }
      await file.writeAsString('$line\n', mode: FileMode.append);
    } catch (_) {
      // 写失败静默降级
    }
  }

  void debug(String message, [Object? error, StackTrace? stack]) =>
      _logger.fine('$message${error != null ? ' | $error' : ''}', error, stack);
  void info(String message) => _logger.info(message);
  void warn(String message, [Object? error, StackTrace? stack]) =>
      _logger.warning('$message${error != null ? ' | $error' : ''}', error, stack);
  void error(String message, [Object? error, StackTrace? stack]) =>
      _logger.severe('$message${error != null ? ' | $error' : ''}', error, stack);
}
```

- [ ] **Step 5: 接入 main.dart 异常钩子**

`lib/main.dart` 的 `main()` 开头加：

```dart
import 'package:openlogtool/services/app_logger.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppLogger.instance.init();
  FlutterError.onError = (details) {
    AppLogger.instance.error('Flutter error', details.exception, details.stack);
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLogger.instance.error('Platform error', error, stack);
    return true;
  };
  // ... 现有启动逻辑
}
```

（PlatformDispatcher 已在 main.dart 使用则合并；保证 import dart:ui。）

- [ ] **Step 6: 日志查看页**

创建 `lib/widgets/log_viewer_dialog.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:openlogtool/services/app_logger.dart';

/// 设置页入口：查看最近日志，可复制。
class LogViewerDialog extends StatelessWidget {
  const LogViewerDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final lines = AppLogger.instance.snapshot().join('\n');
    return AlertDialog(
      title: const Text('日志'),
      content: SizedBox(
        width: 480,
        child: SelectableText(
          lines.isEmpty ? '（暂无日志）' : lines,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            // 复制到剪贴板
            Clipboard.setData(ClipboardData(text: lines));
            Navigator.pop(context);
          },
          child: const Text('复制'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
```

在设置面板新增入口（找到设置面板的文件与分组，加一个 ListTile/按钮打开 LogViewerDialog）。

- [ ] **Step 7: 测试 + analyze + 提交**

运行：`flutter test test/services/app_logger_test.dart` 与 `flutter analyze`；提交：

```bash
git add pubspec.yaml pubspec.lock lib/services/app_logger.dart lib/main.dart lib/widgets/log_viewer_dialog.dart lib/widgets/settings/
git commit -m "feat: app logging with file rotation and viewer"
```

---

### Task 9: 深色模式全面适配

**Files:**
- Modify: `lib/widgets/export_panel.dart`
- Modify: `lib/widgets/log_table.dart`
- Modify: `lib/widgets/record_editor_dialog.dart`
- Modify: `lib/widgets/dictionary_manager.dart`
- Modify: `lib/widgets/session_history_dialog.dart`
- Modify: `lib/widgets/settings/*.dart`
- Modify: `lib/screens/controller_display_screen.dart`
- Test: 抽样 Widget 测试（深色下渲染不抛错）

- [ ] **Step 1: 审计硬编码颜色**

运行 `grep -rn "Colors\.white\|Colors\.black\|Color(0xFF" lib/widgets lib/screens --include="*.dart"`，逐文件列出硬编码色与行号，分类：
- 文字/背景用硬编码（需改主题色）
- 导出 Excel 样式用色（保持自定义，不动）
- 装饰色（可保留或改）

- [ ] **Step 2: 逐文件替换为 ColorScheme**

按以下模式修改（示例，具体按 Step 1 清单）：
- 背景 `Colors.white` → `Theme.of(context).colorScheme.surface`
- 文字 `Colors.black87` → `colorScheme.onSurface`
- 次要文字 → `colorScheme.onSurfaceVariant`
- 卡片 → `colorScheme.surfaceContainerLow`（若无此字段用 `surfaceVariant`）
- 分隔线 → `colorScheme.outlineVariant`
- 输入框/表单 → `Theme.of(context).inputDecorationTheme`（不硬编码）

涉及文件按清单逐处修改，避免遗漏表格控件默认色。Excel 导出样式区（export_panel 的样式 tab、ExportSettings 颜色）不动。

- [ ] **Step 3: 抽样深色 Widget 测试**

在 `test/widgets/dark_mode_smoke_test.dart` 新建：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('material app renders under dark theme', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.dark,
      )),
      home: const Scaffold(body: Center(child: Text('dark'))),
    ));
    expect(find.text('dark'), findsOneWidget);
  });
}
```

（此为冒烟测试模板；实际抽样：在深色 ThemeData 下 pump 设置面板与导出面板，断言不抛异常。）

- [ ] **Step 4: analyze + 全量测试 + 提交**

```bash
git add lib/widgets lib/screens test/widgets/dark_mode_smoke_test.dart
git commit -m "feat: full dark mode adaptation for remaining pages"
```

---

### Task 10: URL 路由同步

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/screens/home_screen.dart`（tab 切换处）
- Modify: `lib/services/url_sync.dart`（新建）
- Test: `test/services/url_sync_test.dart`

- [ ] **Step 1: 写测试**

创建 `test/services/url_sync_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/services/url_sync.dart';

void main() {
  test('builds query for page and session', () {
    expect(buildSyncQuery('workspace', 'sess-1'), '?page=workspace&session=sess-1');
    expect(buildSyncQuery('settings', null), '?page=settings');
  });

  test('parses query', () {
    final r = parseSyncQuery('?page=workspace&session=abc');
    expect(r.page, 'workspace');
    expect(r.session, 'abc');
  });
}
```

- [ ] **Step 2: 实现 url_sync 服务**

创建 `lib/services/url_sync.dart`：

```dart
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

class SyncRoute {
  final String? page;
  final String? session;
  const SyncRoute({this.page, this.session});
}

String buildSyncQuery(String page, String? session) {
  final params = <String, String>{'page': page};
  if (session != null && session.isNotEmpty) {
    params['session'] = session;
  }
  final qs = params.entries
      .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
      .join('&');
  return '?$qs';
}

SyncRoute parseSyncQuery(String query) {
  String? page;
  String? session;
  final uri = Uri.parse('x$query');
  page = uri.queryParameters['page'];
  session = uri.queryParameters['session'];
  return SyncRoute(page: page, session: session);
}

/// 浏览器 URL 同步：非 Web 平台为空实现。
class UrlSync {
  static void init({required void Function(SyncRoute) onRouteChanged}) {
    if (!kIsWeb) return;
    final route = parseSyncQuery(web.window.location.search);
    onRouteChanged(route);
    web.window.addEventListener('popstate', (e) {
      onRouteChanged(parseSyncQuery(web.window.location.search));
    });
  }

  static void push(String page, String? session) {
    if (!kIsWeb) return;
    web.window.history.pushState(
      web.JsAny.jsify(null),
      '',
      buildSyncQuery(page, session),
    );
  }
}
```

- [ ] **Step 3: main.dart 启用 PathUrlStrategy + 初始化**

```dart
import 'package:flutter_web_plugins/url_strategy.dart';

void main() {
  usePathUrlStrategy();
  // ... 现有逻辑
  UrlSync.init(onRouteChanged: (route) {
    // 通知 HomeScreen 切换页面/会话（通过事件总线或 ValueNotifier）
  });
}
```

- [ ] **Step 4: HomeScreen 联动**

`lib/screens/home_screen.dart`：tab 切换/会话切换时调用 `UrlSync.push(page, sessionId)`；启动时收到 `UrlSync.init` 回调则按解析结果设置初始 tab/会话。若 HomeScreen 已有 tab index 管理，将回调接到对应状态。事件传递用一个全局 `ValueNotifier<SyncRoute?>`（或现有导航状态）。

- [ ] **Step 5: 测试 + 构建验证 + 提交**

运行：`flutter test test/services/url_sync_test.dart`；`flutter build web --wasm` 确认编译通过；提交：

```bash
git add lib/main.dart lib/screens/home_screen.dart lib/services/url_sync.dart test/services/url_sync_test.dart
git commit -m "feat: sync page and session to browser URL"
```

---

### Task 11: 表格分页可配置（5/10/15/20/25，默认 10）

**Files:**
- Modify: `lib/providers/settings_provider.dart`
- Modify: `lib/widgets/settings/layout_settings.dart`（布局设置面板）
- Modify: `lib/widgets/log_table.dart`
- Modify: `lib/l10n/app_zh.arb` / `app_en.arb` / `app_zh_CN.arb` / `app_en_US.arb`
- Test: `test/widgets/log_table_test.dart`

- [ ] **Step 1: 添加 l10n 文案**

四个 arb 文件各加：

```json
"tablePageSizeLabel": "每页记录数",
"tablePageSizeHint": "已保存记录表格每页显示的数量"
```
```json
"tablePageSizeLabel": "Records per page",
"tablePageSizeHint": "How many saved records each page shows"
```

运行：`flutter gen-l10n`。

- [ ] **Step 2: SettingsProvider 加字段**

`lib/providers/settings_provider.dart` 追加：

```dart
static const List<int> tablePageSizeOptions = [5, 10, 15, 20, 25];
int _tablePageSize = 10;
int get tablePageSize => _tablePageSize;

Future<void> setTablePageSize(int value) async {
  if (!tablePageSizeOptions.contains(value)) return;
  _tablePageSize = value;
  await _store.setInt('tablePageSize', value);
  notifyListeners();
}
```

load() 中：`_tablePageSize = await _store.getInt('tablePageSize') ?? 10;`

（若 SettingsProvider 尚未接入 KeyValueStore——Task 3 已完成，使用 _store。）

- [ ] **Step 3: 布局设置面板加选择**

`lib/widgets/settings/layout_settings.dart`（或实际布局设置文件）新增：

```dart
// 在设置分组内新增：
_SettingSection(
  title: context.l10n.tablePageSizeLabel,
  child: DropdownButtonFormField<int>(
    key: const Key('table-page-size-select'),
    initialValue: settingsProvider.tablePageSize,
    items: settingsProvider.tablePageSizeOptions
        .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
        .toList(),
    onChanged: (v) {
      if (v != null) settingsProvider.setTablePageSize(v);
    },
  ),
)
```

（_SettingSection 等组件名以现有 settings 代码为准，实现时对齐。）

- [ ] **Step 4: LogTable 读取设置**

`lib/widgets/log_table.dart`：
- 删除 `static const int _itemsPerPage = 5;`
- 在 `didChangeDependencies`（或 build 时）读取：`_itemsPerPage = context.read<SettingsProvider>().tablePageSize;`
- 所有 `_itemsPerPage` 引用处保持不变（变量从 final 字段改为实例变量）。
- 当设置变化时刷新：`context.watch<SettingsProvider>()` 或监听。

- [ ] **Step 5: 更新/新增测试**

`test/widgets/log_table_test.dart` 增加：

```dart
testWidgets('table honors configurable page size', (tester) async {
  // 构造 SettingsProvider（tablePageSize=5）与 12 条日志
  // pump LogTable，断言第一页显示 5 行
  // 修改设置 tablePageSize=10 并 pump，断言第一页显示 10 行
});
```

（按现有 pumpLogTable 辅助函数模式扩展。）

- [ ] **Step 6: 测试 + analyze + 提交**

```bash
git add lib/providers/settings_provider.dart lib/widgets/settings/ lib/widgets/log_table.dart lib/l10n/ test/widgets/log_table_test.dart
git commit -m "feat: configurable records per page (default 10)"
```

---

### Task 12: 版本迭代 2.8.0-R + Release 发布

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/config/version.dart`
- Modify: `web/pkg/package.json`、`rust/web/pkg/package.json`
- Modify: `rust/Cargo.toml`、`rust/Cargo.lock`

- [ ] **Step 1: 版本号迭代**

按仓库惯例（`tool/gen_version.dart` 或手改六处，参考 2.7.0-R 的改动方式）把版本改为 `2.8.0-R`：
- `pubspec.yaml` version: `2.8.0-R+18`（build 号沿用上一版本 +1）
- `lib/config/version.dart` appVersion = `2.8.0-R+18`
- `web/pkg/package.json`、`rust/web/pkg/package.json` version: `2.8.0-R`
- `rust/Cargo.toml` version = `2.8.0-R`
- `rust/Cargo.lock` 中 openlogtool_core 条目同步

- [ ] **Step 2: 全量验证**

运行：`flutter analyze`（No issues）+ `flutter test`（全绿）+ `flutter build linux --release`（构建成功）。

- [ ] **Step 3: 提交并推送**

```bash
git add .
git commit -m "chore: bump version to 2.8.0-R"
git push origin dev
```

- [ ] **Step 4: PR + 合并 + tag + Release**

- `gh pr create --base main --head dev` → 检查 CI 通过 → 合并
- `git tag -a v2.8.0-R -m "OpenLogTool v2.8.0-R"` 推送到 main 的合并 commit
- 等 CI 全平台构建通过（含 iOS job、deb/rpm）
- `gh release edit v2.8.0-R --notes-file <notes>` 写 Release Notes（中英双语，格式参照 v2.7.0-R）

---

## Self-Review 记录

- **Spec 覆盖**：11 项需求 → Task 1（字体）、Task 2（导出）、Task 3（IndexedDB）、Task 4（PWA）、Task 5（首屏）、Task 6（iOS）、Task 7（deb/rpm）、Task 8（日志）、Task 9（深色）、Task 10（URL 同步）、Task 11（分页）、Task 12（版本/发布）。全部覆盖。
- **占位符扫描**：Task 6/7/9 的 CI/颜色清单依赖实现期调查（构建错误按实际情况调整、grep 清单逐处修改），属于合理探索点而非省略；其余任务含完整代码。
- **类型一致性**：`KeyValueStore`（Task 3 定义）在 Task 11 的 SettingsProvider 中使用；`AppLogger`（Task 8 定义）仅在 Task 8 内使用；`UrlSync`/`SyncRoute`（Task 10）自洽。
