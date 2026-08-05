# OpenLogTool 2.8.0：Web 适配优化与跨平台扩展设计

日期：2026-08-05
状态：已批准（批次一、批次二均获用户确认；表格分页默认 10；版本号定为 2.8.0-R）

## 目标

2.8.0 聚焦 Web 端体验与跨平台覆盖：

1. Web 端默认使用项目自带更纱黑体
2. 修复 Web 端导出 bug（Excel 文件名错乱、JSON 导出失败）
3. Web 设置存储升级 IndexedDB
4. PWA 离线支持 + 可安装
5. 首屏加载优化（字体子集化）
6. iOS 构建支持（出包，签名安装用户自理）
7. Linux 打包 .deb + .rpm（tar.gz 保留）
8. 日志系统（运行日志 + 错误堆栈）
9. 深色模式全面适配
10. URL 路由同步
11. 表格分页可配置（预选项 5/10/15/20/25，默认 10）

已排除：FreeBSD/OpenBSD/Windows x86 原生构建（Flutter 官方不支持）、大数据表格虚拟化（用户确认数据量不大）。

## 现状调研结论

- Rust 核心用 `sqlite_compat`：桌面 rusqlite / 浏览器 sqlite-wasm-rs（IndexedDB 后端），日志记录数据在 Web 上已持久化到 IndexedDB。
- `SharedPreferences`（Web=localStorage，5MB 上限）用于 9 个 provider 的设置/词库类数据：theme_provider、ai_recognition_settings_provider、personal_cloud_provider、server_provider、session_provider、collaboration_provider、settings_provider、controller_window_service、secure_token_store。
- 深色模式已有开关（`theme_provider.dart` `darkMode`）+ `darkTheme`（main.dart:133），但存在硬编码浅色页面。
- `LogTable` 已有分页（`_currentPage` + `static const _itemsPerPage = 5`，log_table.dart:29-30），每页数量硬编码。
- 路由使用 `MaterialApp` 默认 Navigator，未配置 `urlStrategy`（Web 默认 hash 路由，无 URL 同步）。
- Web 导出走 `FilePicker.platform.saveFile`（export_service.dart:74），file_picker Web 实现忽略自定义文件名（fallback `FlutterExcel.xlsx`）且返回值不可靠 → Excel 文件名变 `FlutterExcel.xlsl`、JSON 判定失败。
- `deploy/web/release/` 已有 Docker 部署（Nginx），PWA 资产（manifest/icons）已存在。

## 设计

### 1. Web 字体：默认更纱黑体

- 将自带 Sarasa Gothic SC 字体（现有字体资产，检查 `assets/fonts/` 或构建产物）的 woff2 拷贝到 `web/fonts/`。
- `web/index.html` 增加 `@font-face`（`font-family: SarasaGothicSC; font-display: swap;`）。
- 主题默认 `fontFamily: 'SarasaGothicSC'`（`buildAppTheme`），桌面/Web 字体一致。
- Web 构建后字体随静态资源发布。

### 2. Web 导出修复

- `ExportService.saveFile` 增加 `kIsWeb` 专属分支：用 `package:web`（`dart:js_interop`）创建 `Blob` + `AnchorElement`，`download = filename`，触发点击后释放 object URL。
- Web 分支返回 `ExportSaveResult(path: filename, usedSaf: true)`（文件名即成功标志），JSON/Excel 调用方无需改动判定逻辑。
- 修复点：文件名完全由模板生成（含 `.json` / `.xlsx` 扩展名），不再经过 file_picker。
- 浏览器限制：同步下载即可，无需弹窗；失败（如被拦截）返回 cancelled。

### 3. 存储升级 IndexedDB

- Dart 侧新增 `KeyValueStore` 抽象（接口对齐现有 SharedPreferences 用法：get/set/remove key-value）。
- Web 后端：`package:idb_shim` 包一层 IndexedDB（库 `openlogtool_settings`，object store `kv`），支持大 value、无 5MB 限制。
- 桌面后端：保持 `SharedPreferences`。
- 替换 9 个 provider 的 `SharedPreferences` 直调：provider 通过注入/全局访问 `KeyValueStore` 读写。
- 迁移：首次运行把 localStorage 中已有 key 拷贝进 IndexedDB（一次性迁移，保留原 key 兼容降级）。
- secure_token_store 单独评估：桌面已有安全存储，Web 上 IndexedDB 可接受（同浏览器安全模型）。

### 4. PWA 离线 + 可安装

- 完善 `web/manifest.json`：`display: standalone`、主题色、`short_name`、图标补齐（192/512/maskable 已存在）。
- 启用 Flutter 构建自带的 service worker（`flutter_service_worker.js` 已随构建生成，确认 `index.html` 中注册；必要时配置缓存策略让离线可用）。
- `index.html` 增加 iOS meta：`apple-mobile-web-app-capable`、`apple-mobile-web-app-status-bar-style`、`apple-touch-icon`。

### 5. 首屏加载优化

- 更纱黑体**子集化**：用 fonttools 对 woff2 做 CJK 常用字（GB2312 或自定常用集）子集，目标体积 ≤300KB（原始 MB 级），同时保留桌面完整字体不受影响。
- Web 构建使用 `flutter build web --wasm`（skwasm 渲染）并按需加载 canvaskit/skwasm。
- `index.html` 增加首屏加载进度提示（简单 div + CSS，加载完成移除）。

### 6. iOS 构建支持（CI）

- 新增 workflow job（macOS runner，复用现有 macOS job 的 Flutter/Rust 设置）：
  - rustup target 添加 `aarch64-apple-ios`、`aarch64-apple-ios-sim`、`x86_64-apple-ios`
  - cargo-ndk 类似流程：为 iOS 目标构建 `libopenlogtool_core.a`，配置 `ios/Runner` 链接
  - `flutter build ios --release --no-codesign` → 产物 `.xcarchive` 或 `.app` 打包 zip 上传 Release
  - 可选：`flutter build ios --simulator` 出模拟器版
- 安装/签名用户自理（文档说明 sideload 途径）。
- 需新增 `ios/` 平台目录（若未生成过：`flutter create --platforms=ios .` 生成脚手架后适配）。

### 7. Linux .deb + .rpm 打包（CI）

- 在现有 Linux 构建 job 后新增打包步骤：
  - .deb：`dpkg-deb`（控制文件：包名 `openlogtool`、版本、依赖 `libgtk-3-0` 等；安装 `/opt/openlogtool/`，桌面 .desktop 条目、图标、`libopenlogtool_core.so` 一并打包）。
  - .rpm：`rpmbuild`（spec 文件同理；CI 镜像预装 rpm 工具）。
- 产物命名：`OpenLogTool-<version>-Linux-x86_64.deb` / `.rpm`，随 Release 发布；tar.gz 保留。

### 8. 日志系统

- 依赖：`logging` 包（标准 Dart 日志）。
- `AppLogger`（单例）：
  - 级别 DEBUG/INFO/WARN/ERROR，可运行时调级别。
  - 记录点：启动参数、版本、数据库打开状态、设置变更、记录保存/更新/删除、导入导出（含失败）、协作/云同步事件、异常堆栈。
  - 桌面输出：文件 `~/.local/share/openlogtool/logs/app.log`（按大小轮转：3 × 1MB，保留旧文件）。
  - Web 输出：浏览器 console（格式化 INFO/DEBUG 可降噪），无文件（IndexedDB 记录可选，先 console）。
- 全局异常钩子：
  - `FlutterError.onError` → ERROR + 完整堆栈。
  - `PlatformDispatcher.instance.onError` → ERROR + 堆栈。
- 设置页新增"日志"入口：查看最近日志（内存环形缓冲 500 条），可复制；桌面端显示日志文件路径。

### 9. 深色模式完善

- 审计全部页面/组件硬编码 `Color`（白底 `Colors.white`、黑字等）：
  - 目标文件：export_panel、log_table（含导出表格配色）、record_editor_dialog、settings 系列、controller 显示、dictionary_manager 等。
  - 改为 `Theme.of(context).colorScheme` / `theme.colorScheme` 系列（surface、onSurface、primaryContainer 等）。
- 表格导出（Excel）颜色设置属导出样式，维持用户自定义，不随主题变化。
- 验证：深色模式下逐页面走查无刺眼白块、文字对比度达标。

### 10. URL 路由同步

- `MaterialApp` 配置 `urlStrategy: PathUrlStrategy`（干净 URL，无 `#`）。
- 当前页/会话同步到 URL query：`?page=workspace|settings|...&session=<id>`。
- 启动时解析 URL 恢复页面/会话；`WidgetsBindingObserver.didChangeAppLifecycleState` 或导航后更新 URL。
- 浏览器后退：监听 URL 变化（`NavigationResult`/URL 监听）映射到应用内页面切换。
- 不引入 go_router，保持现有 Navigator 结构，最小侵入。
- 注：部署已由 Nginx/Caddy 反代，PathUrlStrategy 需反代无特殊配置（SPA fallback 已满足，因无服务端路由）。

### 11. 表格分页可配置

- `SettingsProvider` 新增 `tablePageSize`（int，默认 10），设置面板（布局设置区）新增"每页记录数"选择（预选项 5/10/15/20/25）。
- `LogTable`：`static const _itemsPerPage = 5` 改为从设置读取（listen 设置变化），页码/切片逻辑不变。
- 测试：修改设置后表格每页行数变化、翻页边界正确。

## 错误处理

- Web 导出：浏览器拦截下载（无抛错但无文件）无法检测，返回成功并提示"已在浏览器下载"；构造失败（非法字符等）抛异常 → 现有 catch 显示导出失败。
- IndexedDB 迁移：迁移失败不影响启动（保留 localStorage 继续工作，下次再试）。
- iOS 构建失败：不阻塞其他平台 release（job 独立）。
- 日志写入失败（磁盘满等）：静默降级到 console，不中断应用。

## 测试策略

- 单元：导出文件名生成（已有）+ Web 下载逻辑（函数抽离，mock blob/anchor）；分页设置读写；日志格式化。
- 组件：表格分页行数随设置变化；深色模式抽样页面无硬编码色（golden/静态检查难做 → 人工走查 + 抽查测试）。
- CI：新增 iOS job、deb/rpm 打包步骤验证（产出物存在性 + 结构校验）；quality gate 保持全绿。
- Web 端手动回归清单：导出 JSON/Excel 文件名正确、PWA 安装/离线、字体显示、深色切换、URL 同步/后退、日志 console 输出。

## 里程碑

1. M1（Web 修复与基建）：字体、导出修复、IndexedDB、PWA、首屏优化
2. M2（平台扩展）：iOS job、deb/rpm 打包
3. M3（体验完善）：日志系统、深色模式、URL 同步、分页设置
4. M4（发布）：版本号 2.8.0-R 迭代、全量测试、Release + notes

## 明确不做

- FreeBSD/OpenBSD/Windows x86 原生构建（Flutter 官方不支持）
- 大数据表格虚拟化（数据量小，不做）
- go_router 引入
- Web 端本地日志文件（console 即可）
