# OpenLogTool 2.9.0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 2.9.0-R：两弹窗序号、Excel+LLM 导入、功率加 W、Web 主控屏新标签页、云同步字段合并与冲突弹窗。

**Architecture:** 全部在现有 Flutter 客户端内完成：弹窗序号/功率规则在 log_form + l10n；Excel 导入用 excel 包 + 现有 TextAssistantClient；Web 主控屏用 package:web 的 window.open + BroadcastChannel；云同步合并改 personal_cloud_merge.dart 的 concurrentCreate 分支 + 冲突弹窗接入现有冲突 UI 流程。

**Tech Stack:** Flutter 3.44.7、excel 4.0.6、TextAssistantClient（openai/anthropic/compatible）、package:web（BroadcastChannel/window.open）

**Spec:** `docs/superpowers/specs/2026-08-06-repeat-excel-power-controller-sync-design.md`

---

## 环境约定

- 项目根：/home/mazha0309/Projects/openlogtool，dev 分支
- Flutter：`export PATH="$HOME/develop/flutter/bin:$PATH"`；测试用 `flutter test --no-pub`
- 不碰项目外目录，不用 root
- 提交风格：小写前缀 + 英文单行
- l10n：改 app_zh.arb + app_en.arb 后 `flutter gen-l10n`

---

### Task 1: 重复呼号两个弹窗显示原点名序号

**Files:**
- Modify: `lib/widgets/log_form.dart`（失焦弹窗 + 保存弹窗）
- Modify: `lib/l10n/app_zh.arb`、`app_en.arb`（+ gen-l10n）
- Test: `test/widgets/log_form_duplicate_prompt_test.dart`

- [ ] **Step 1: 加 l10n 占位符**

app_zh.arb：
```json
"duplicateContinueDialogMessage": "{callsign} 已在第 {ordinal} 位记录过，继续添加吗？",
"@duplicateContinueDialogMessage": {"placeholders": {"callsign": {"type": "String"}, "ordinal": {"type": "int"}}},
"duplicateOldRecordSummary": "原记录（第 {ordinal} 位）：{time} {callsign} {rstSent}/{rstRcvd} {qth}",
"@duplicateOldRecordSummary": {"placeholders": {"ordinal": {"type": "int"}, "time": {"type": "String"}, "callsign": {"type": "String"}, "rstSent": {"type": "String"}, "rstRcvd": {"type": "String"}, "qth": {"type": "String"}}},
```
app_en.arb 对应："{callsign} was already logged at position {ordinal}. Continue anyway?" 与 "Original record (#{ordinal}): {time} {callsign} {rstSent}/{rstRcvd} {qth}"

运行 `flutter gen-l10n`。

- [ ] **Step 2: 失焦弹窗加序号**

`lib/widgets/log_form.dart` `_onCallsignFocusLost`（约 524 行）：
```dart
final latest = existing.last;
final ordinal = logProvider.logs.indexOf(latest) + 1;
// content: Text(l10n.duplicateContinueDialogMessage(callsign, ordinal)),
```

- [ ] **Step 3: 保存弹窗加序号**

`_handleSave` 的 duplicate-save 弹窗（约 893 行）：
```dart
final ordinal = logProvider.logs.indexOf(latest) + 1;
// l10n.duplicateOldRecordSummary(ordinal, formatLogTimeForDisplay(latest.time), ...)
```

- [ ] **Step 4: 测试**

`test/widgets/log_form_duplicate_prompt_test.dart` 追加/修改：
- 构造 3 条记录（BG5FBT 在第 3 位），失焦触发弹窗 → 断言文本含 "第 3 位"
- 提交重复呼号 → 保存弹窗摘要含 "第 3 位"

- [ ] **Step 5: 验证提交**

`flutter analyze` + `flutter test --no-pub test/widgets/log_form_duplicate_prompt_test.dart`（+ 全量）
```bash
git add lib/widgets/log_form.dart lib/l10n/ test/widgets/log_form_duplicate_prompt_test.dart
git commit -m "feat: show original ordinal in duplicate-callsign dialogs"
```

---

### Task 2: Excel 导入接入 LLM

**Files:**
- Modify: `lib/widgets/export_panel.dart`
- Create: `lib/services/excel_import_service.dart`（解析 + LLM 结构化）
- Test: `test/services/excel_import_service_test.dart`、`test/widgets/export_panel_test.dart`（按钮显隐）

- [ ] **Step 1: 服务层（解析 + LLM）**

`lib/services/excel_import_service.dart`：
- `parseExcelRows(Uint8List bytes) → List<Map<String, String>>`：excel 包读第一工作表，每行 {列索引: 单元格文本}（纯函数可测）
- `buildSheetText(rows) → String`：行文本化（用于 LLM prompt）
- `Future<List<Map<String, Object?>>> structureWithLlm(TextAssistantClient client, String sheetText)`：completeJson 让模型输出记录数组（callsign/time/rstSent/rstRcvd/qth/power/remarks）
- `List<Map<String, Object?>> validateLlmOutput(Object? json)`：校验/清洗（呼号必填、剔除空行）
- 入库复用：参考 `_importJSON` 的现有入库路径（LogProvider.addLog 批量或 RustApi 批量——实现期按现有 JSON 导入模式对齐）

- [ ] **Step 2: UI（按钮显隐 + 导入流程）**

`export_panel.dart`：
- `_buildActionButton`（importExcel）包在 `if (context.watch<AiRecognitionSettingsProvider>().textAssistantEnabled)` 条件里
- `_importExcel` 实现：file_picker 选 xlsx → parseExcelRows → buildSheetText → 进度对话框 → structureWithLlm → validateLlmOutput → 预览对话框（记录列表 + 确认/取消）→ 入库 → 成功提示
- 失败/超时 → SnackBar 提示

- [ ] **Step 3: l10n**

zh/en 加：excelImportTitle（导入 Excel）、excelImportLlmProcessing（正在用 AI 解析…）、excelImportPreviewTitle（导入预览）、excelImportFailed（导入失败：{error}）、excelImportSuccess（已导入 {count} 条记录）
（en 对应英文）

- [ ] **Step 4: 测试**

- excel_import_service_test：parseExcelRows（构造内存 xlsx——用 excel 包生成测试文件）、buildSheetText、validateLlmOutput（合法/缺呼号/空）
- export_panel_test：textAssistantEnabled true/false 时按钮显隐

- [ ] **Step 5: 验证提交**

analyze + 相关测试 + 全量 → commit `feat: LLM-powered Excel import`

---

### Task 3: 功率自动加 W

**Files:**
- Modify: `lib/providers/settings_provider.dart`
- Modify: `lib/widgets/settings/layout_settings.dart`（或记录相关设置面板——按现有分组放）
- Modify: `lib/widgets/log_form.dart`（保存时应用）
- Create: `lib/utils/power_normalizer.dart`（纯函数）
- Test: `test/utils/power_normalizer_test.dart`、settings 测试

- [ ] **Step 1: 纯函数**

`lib/utils/power_normalizer.dart`：
```dart
/// 功率规范化：trim 后为纯数字（整数或小数）→ 补 W；否则原样返回。
String normalizePower(String raw) {
  final trimmed = raw.trim();
  if (RegExp(r'^\d+(\.\d+)?$').hasMatch(trimmed)) return '$trimmed W';
  return trimmed;
}
```

- [ ] **Step 2: 设置项**

SettingsProvider：`_autoAppendPowerW = true`、`bool get autoAppendPowerW`、`setAutoAppendPowerW`、load 读取（key `autoAppendPowerW`）、resetToDefaults；设置面板加开关（Switch，Key('auto-append-power-w-switch')，标题/副标题 l10n）

- [ ] **Step 3: 表单应用**

log_form `_handleSave`：`power: settings.autoAppendPowerW ? normalizePower(_powerController.text.trim()) : _powerController.text.trim()`（含编辑路径 _updateExistingLog 或对应处——按现有代码结构对齐）

- [ ] **Step 4: 测试**

power_normalizer_test：50→50W、50.5→50.5W、50W→50W、5kW→5kW、500mW→500mW、50瓦→50瓦、中文→不变、空→空
settings：默认 true、load 非法回落、set 持久化

- [ ] **Step 5: 验证提交**

`feat: auto-append W to pure numeric power`

---

### Task 4: Web 主控屏新标签页

**Files:**
- Modify: `lib/screens/session_hub_page.dart`（区块条件 + web 按钮）
- Modify: `lib/services/controller_window_service.dart`（web 分支：window.open + BroadcastChannel）
- Modify: `lib/screens/controller_display_screen.dart`（或路由处：接收 BroadcastChannel 数据）
- Test: URL/消息格式纯函数测试

- [ ] **Step 1: Web 打开逻辑**

`controller_window_service.dart` 加：
```dart
/// Web 端在主标签页打开主控屏（BroadcastChannel 推送实时数据）。
static void openWebTab({required String sessionId}) {
  if (!kIsWeb) return;
  // window.open('?page=controller&session=$sessionId', '_blank')
}
```
`updateOpenWindows` 在 kIsWeb 时改为 `BroadcastChannel('openlogtool-controller').postMessage(displayData)`（消息含 sessionId + displayData JSON）

- [ ] **Step 2: 新标签页接收**

controller_display_screen（或 home_screen 路由解析 `?page=controller`）：监听 BroadcastChannel，更新显示数据；首次加载从数据库读（沿用现有跨平台读取逻辑）

- [ ] **Step 3: session_hub_page 区块**

`supportsControllerDesktopWindows` 条件改 `supportsControllerDesktopWindows || kIsWeb`；web 下按钮文案"打开主控屏标签页"（window.open）；桌面按钮不变

- [ ] **Step 4: 测试**

纯函数：`controllerTabUrl(sessionId)`、BroadcastChannel 消息 JSON 格式（displayData 序列化——ControllerDisplayDto 已有 toJson?）

- [ ] **Step 5: 验证提交**

`feat: web controller display in a new tab`

---

### Task 5: 云同步合并优化

**Files:**
- Modify: `lib/utils/personal_cloud_merge.dart`
- Modify: `lib/providers/personal_cloud_provider.dart`（字段冲突弹窗接入）
- Modify: `lib/widgets/settings/settings_panel.dart` 或冲突展示处（弹窗）
- Test: `test/utils/personal_cloud_merge_test.dart`（+ provider 流程）

- [ ] **Step 1: merge 纯函数改造**

`_mergeTable` 的 `concurrentCreate` 分支（baseRow == null，双方不同）：
- entityType == 'log'：字段级合并——
  ```dart
  final merged = <String, Object?>{};
  final fieldConflicts = <String>[];
  for (final key in {...localRow.keys, ...remoteRow.keys}) {
    final l = localRow[key]; final r = remoteRow[key];
    if (immutableFields.contains(key)) { merged[key] = l; continue; }
    if (_deepEqual(l, r)) { merged[key] = l; continue; }
    if (l != null && l != '' && r != null && r != '') {
      fieldConflicts.add(key); merged[key] = l; // 默认本地，弹窗可改
    } else {
      merged[key] = (l != null && l != '') ? l : r;
    }
  }
  ```
  每个冲突字段产出一个 `fieldConflict` 冲突（conflictId = 'field-<id>-<key>'，fieldGroup=key，localValue/remoteValue）；resolutions 用 `PersonalCloudConflictChoice` 决定该字段取 local/remote
- entityType == 'session'：保持现有行为（弹窗二选一整体）

- [ ] **Step 2: provider 弹窗**

`personal_cloud_provider.dart` 的 resolveConflicts 流程：合并后若存在 fieldConflict 且无 resolution → 现有冲突列表机制已能承载（conflicts 列表 + 弹窗 UI）。确认现有 settings_panel 冲突弹窗能显示 fieldConflict（kind 显示"字段冲突：{key}"）——若现有弹窗按 kind 分支，加 fieldConflict 分支；否则新增字段冲突弹窗（列出冲突字段+两值，逐字段选/全部本地/全部远程）

- [ ] **Step 3: 测试**

merge 纯函数：
- log concurrentCreate 字段合并（本地空/远程空/相同/都非空不同）
- fieldConflict 冲突产出（conflictId/fieldGroup/值）
- resolutions 应用（选 remote 的字段用远程值）
- immutable 字段不冲突
- session concurrentCreate 仍产出冲突
- provider：合并产生 fieldConflict → resolveConflicts 应用

- [ ] **Step 4: 验证提交**

`feat: field-level merge with conflict dialog for concurrent log creates`

---

### Task 6: 版本 2.9.0-R + 发布

**Files:**
- Modify: pubspec.yaml、lib/config/version.dart、rust/Cargo.toml、rust/Cargo.lock（web/pkg 两处忽略）

- [ ] **Step 1: 版本号六处** → `2.9.0-R+19`（pubspec/version.dart），`2.9.0-R`（Cargo.toml/Cargo.lock）
- [ ] **Step 2: 全量验证**：analyze + `flutter test --no-pub` + `flutter build linux --release --no-pub`
- [ ] **Step 3: 提交推送**：`chore: bump version to 2.9.0-R+19` → push dev
- [ ] **Step 4: PR + 合并**：gh pr create → checks → merge
- [ ] **Step 5: tag + CI**：`v2.9.0-R` → push → 等 CI（含 iOS job）
- [ ] **Step 6: Release Notes**：中英双语（参照 v2.8.0-R 格式），覆盖 5 项功能
- [ ] **Step 7: 部署 Web**：下载 release WebClient 资产 → scp → 替换容器（保留旧目录回退）→ 验证 https://log.mazha0309.com
- [ ] **Step 8: 汇报**：完成后汇报（用户睡觉，不打扰；汇报即可）

---

## Self-Review 记录

- Spec 覆盖：5 项设计 → Task 1-5；版本发布 → Task 6 ✓
- 占位符：Task 2 的 LLM prompt 与入库路径、Task 4 的窗口通信细节、Task 5 的弹窗 UI 均以"实现期对齐现有代码"标注——实现时按实际代码结构确定
- 类型一致性：normalizePower（Task 3）在 log_form 使用；BroadcastChannel 频道名常量在 controller_window_service 定义、新标签页监听处使用（同常量）
