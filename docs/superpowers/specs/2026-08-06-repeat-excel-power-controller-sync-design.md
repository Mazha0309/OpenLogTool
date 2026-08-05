# OpenLogTool 2.9.0：重复呼号序号、Excel+LLM 导入、功率加 W、Web 主控屏、云同步合并

日期：2026-08-06
状态：已批准（用户确认 5 项设计 + 版本 2.9.0-R；两个重复呼号弹窗都加序号）

## 目标

1. 重复呼号**两个弹窗**（失焦询问 + 保存更新）显示旧记录的当前列表序号
2. Excel 导入功能接入 LLM（按钮仅 LLM 启用时显示）
3. 功率自动加 W（设置开关，纯数字含小数点才加）
4. 网页版主控屏新标签页（BroadcastChannel 实时推送）
5. 云同步合并优化：log 级 concurrentCreate 字段级合并 + 字段冲突弹窗；session 级保持手动选择

## 现状调研

- 弹窗：`log_form.dart` 失焦弹窗（`_onCallsignFocusLost`，505-540 行，`duplicateContinueDialogMessage(callsign)`）；保存弹窗（865-910 行，`duplicateOldRecordSummary(time, callsign, rstSent, rstRcvd, qth)`）。表格序号 = 正序位置 + 1（`log_table.dart:1009` reverseIndex = originalIndex + 1，与分页无关）。
- Excel 导入：`export_panel.dart:145` 有"导入 Excel"按钮（`_importExcel` 占位，显示"即将推出"）。`excel: ^4.0.6` 包已依赖。LLM 客户端 `TextAssistantClient`（lib/services/text_assistant.dart，completeJson，支持 openai/anthropic/compatible）；`AiRecognitionSettingsProvider.textAssistantEnabled` 是开关。
- 功率：`old.LogEntry.power` Option<String>，log_form `_powerController`。
- 主控屏：桌面版子进程窗口（`ControllerWindowService`，`supportsControllerDesktopWindows = !kIsWeb && ...`），session_hub_page:118-150 的"本地主控屏"区块在 web 不显示。`controller_display_screen.dart` 是跨平台只读主控屏（安卓平板/独立电脑/子窗口共用）。数据经 `ControllerWindowService.updateOpenWindows` 推送，Web 无此机制。
- 云同步合并：`lib/utils/personal_cloud_merge.dart` 三向合并。`_mergeTable` 的 `concurrentCreate`（base 无，local/remote 都有且不同）→ 冲突弹窗二选一（整体替换）。`_conflict` 产出 conflictId/kind/fieldGroup 等。`PersonalCloudConflictChoice { local, remote }`。provider 侧 `personal_cloud_provider.dart` 有 `_conflicts` 列表 + `resolveConflicts`（per-conflict map）。

## 设计

### 1. 重复呼号弹窗显示序号（两个弹窗）

- 失焦弹窗：`duplicateContinueDialogMessage` 加 `ordinal` 参数，文案 "BG5FBT 已在第 {ordinal} 位记录过，继续添加吗？"
- 保存弹窗：`duplicateOldRecordSummary` 加 `ordinal`，文案 "原记录（第 {ordinal} 位）：{time} {callsign} {rstSent}/{rstRcvd} {qth}"
- 序号计算：`logProvider.logs.indexOf(existing.last) + 1`（与表格一致）

### 2. Excel 导入接入 LLM

- "导入 Excel"按钮仅在 `textAssistantEnabled == true` 时显示
- 流程：file_picker 选 .xlsx → excel 包解析 → 工作表行文本化（每行字段拼成文本）→ `TextAssistantClient.completeJson` 让 LLM 输出结构化记录数组 → 预览弹窗（列表 + 确认）→ 批量入库
- 入库方式：复用现有导入逻辑（参考 `_importJSON` 的入库路径）
- 失败/超时友好提示

### 3. 功率自动加 W

- SettingsProvider 加 `autoAppendPowerW`（默认 true，key `autoAppendPowerW`），设置面板加开关
- 规则：power.trim() 匹配 `^\d+(\.\d+)?$`（纯数字整数或小数）→ 补 `W`；否则不动（50W/5kW/500mW/50瓦/中文/空 都不加）
- 应用点：log_form 提交（`_handleSave` 的 power 字段）与编辑回填一致

### 4. Web 主控屏新标签页

- session_hub_page 主控屏区块条件：`supportsControllerDesktopWindows || kIsWeb`（web 显示"打开主控屏"按钮）
- Web 按钮：`window.open` 新标签页（URL 带 `?page=controller&session=<id>`，用 url_sync 的 buildSyncQuery 扩展）
- 新标签页：路由解析 page=controller → 显示 `controller_display_screen`（从数据库读数据）
- 实时刷新：主窗口 `BroadcastChannel('openlogtool-controller')` postMessage(displayData)；新标签页监听更新
- 桌面行为不变

### 5. 云同步合并优化

- `_mergeTable` 的 `concurrentCreate`：entityType == 'log' 时改为**字段级合并**：
  - 每字段：本地非空保留本地，本地空用远程
  - 某字段双方非空且不同 → 产出 `fieldConflict` 冲突（conflictId 按字段细分）
  - immutable 字段（created_at/source_device_id）不参与冲突，保留本地
- 弹窗：合并时若存在 fieldConflict → 弹窗列出冲突字段（本地值/远程值），逐字段选择或"全部用本地/全部用远程"
- session 级 concurrentCreate 保持现有手动选择
- 合并结果：冲突解决后各字段取选定值

## 错误处理

- Excel 解析失败/LLM 超时/LLM 输出非法 → 提示用户重试，不中断
- BroadcastChannel 不可用（旧浏览器）→ 降级为轮询数据库
- 字段合并 immutable 冲突 → 忽略远程值，保留本地

## 测试策略

- 序号：log_form_duplicate_prompt_test 断言两弹窗文本含序号
- Excel：解析/LLM 输出校验纯函数 + 按钮显隐（textAssistantEnabled）
- 功率：规则纯函数（50/50.5/50W/5kW/500mW/50瓦/中文/空）+ 表单提交
- 主控屏：URL 构建 + BroadcastChannel 消息格式纯函数
- 合并：merge 纯函数（log concurrentCreate 字段合并、fieldConflict 产出、resolutions 应用、session 保持冲突）+ provider 流程
- 全量 flutter test + analyze

## 版本与发布

- 六处版本号 2.9.0-R+19（pubspec、version.dart、Cargo.toml、Cargo.lock；web/pkg 两处本地生成物不提交）
- 全量测试 → PR → 合并 → tag v2.9.0-R → CI 构建（含 iOS）→ Release Notes（中英双语，参照 2.8.0-R）→ 部署 Web 到 log.mazha0309.com
- 不单独跑 APK 构建（CI 发布流程自动构建）

## 明确不做

- 不新增主控屏 Web 专属界面（复用现有跨平台页面）
- 不改 session 级冲突弹窗行为
- 不引入新依赖（excel 包已有；BroadcastChannel 用 package:web 原生）
