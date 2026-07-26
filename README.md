# OpenLogTool - 业余无线电点名记录工具

专为业余无线电爱好者设计的点名记录工具，支持跨平台运行。

## 功能

### 记录管理
- 快速添加记录：支持主控呼号、点名呼号、设备、天线、功率、QTH、高度、时间、信号报告等字段
- 智能表单：自动大写呼号，保留主控呼号，支持词典自动补全
- 编辑和删除记录
- 撤销上一条记录
- 统计信息：总记录数、今日记录、最近7天记录

### 词典管理
- 设备、天线、呼号、QTH词典管理
- 支持自动补全
- 输入新内容时自动添加到词典
- 支持 JSON 导入导出
- 可选文字助手可从本机历史聚合识别缺失词条，并为四类词库提出新增、改名或合并建议；所有变更均需确认且不会改写历史记录

### 可选 AI 辅助
- 语音识别与文字助手相互独立，可分别启用；文字助手支持 OpenAI Responses API、Anthropic Messages API 和旧版 OpenAI Chat Completions 兼容协议
- 设备、天线、QTH、高度和功率字段停止输入约 300 毫秒后，可在原下拉框中显示一条格式规范建议
- 文字模型请求默认关闭或弱化推理以优先获得快速结构化结果；API 密钥使用平台安全存储，不写入普通设置或导出文件
- 语音接口格式、录音行为和排错方法见 [AI 语音识别配置指南](docs/ai-speech-recognition.md)

### 数据导入导出
- JSON导出/导入
- Excel导出

### 个人云同步
- 登录支持 `personalCloudSnapshots` 与 `personalDictionarySnapshots` 的自建服务器后，自动双向同步个人会话、点名记录及词库用户改动
- 个人记录不会写入协作会话，也不会出现在服务端的“协作会话（Sessions）”列表；协作会话继续使用独立的实时同步
- 使用账户隔离、完整本地基线、内容校验和与 revision 条件写入；多设备的独立改动自动三方合并，真实字段冲突才要求选择
- 词库只同步用户词条和对内置词条的删除覆盖，不复制整份内置词库；从云端替换记录不会修改设置或协作会话
- 导入或清空整库后会立即刷新会话列表，并暂停自动覆盖，等待用户确认新的同步基线

### 协作会话（v1 阶段 3）
- 使用 `/api/v1` 短期 Access Token 与 Refresh Token 登录自建服务器
- 将完整本地 Session 分批发布，保留 sessionId、syncId、RST、时间和备注
- 发布前按服务端字段约束校验冻结快照，并同时按 500 条与 UTF-8 请求字节上限动态分批
- 通过 10 位成员邀请码加入同一个 Session，并原子安装服务端规范快照
- Owner 可创建/撤销邀请、调整或移除成员、转移所有权
- Owner/Editor 的 Log 增改删恢复会与 durable outbox 在同一个本地事务提交；Owner 还可重命名、关闭和重开 Session
- 通过连续事件 REST 补拉和鉴权 WebSocket 提示保持在线同步；断线、重启和请求结果丢失后复用原 mutationId 恢复
- 本地持久化服务器绑定、成员角色、shadow、游标、outbox 和冲突记录；accepted mutation 只在规范事件落库后清除
- 永久 rejected 会保留可见提示；再次编辑同一实体时基于规范 shadow 原子重建新 mutation，不复用被拒 payload 或 ID
- Viewer、已撤权成员及服务端已关闭的 Session 强制只读，角色变化会持久化后重连
- 协作页展示传输状态、事件游标、待同步数、冲突数和永久拒绝提示
- 服务器、账号、Session 切换会立即隔离管理状态；加入和管理操作保留可重放的幂等 ID
- 事件游标过期或 WebSocket 请求重同步时，自动拉取包含 Log tombstone 的一致快照，原子重装规范基线，再叠加未提交 outbox 并继续补拉
- 对完整本地 mutation 链执行安全三方 rebase；无重叠修改自动生成新的 mutation，生命周期或同字段冲突进入持久冲突中心
- 冲突实体在解决前禁止继续编辑；可按 Rust 返回的允许操作采用远端、保留本地重试，或把本地日志复制为全新记录

公开 Liveshare、事件裁剪/指标和高级逐字段手动合并仍在后续阶段；旧的未鉴权分享通道不会重新启用。

### 主题设置
- 自定义主题颜色
- 暗色/亮色模式
- 可折叠侧边栏与响应式布局

### 跨平台
- Linux
- Windows
- macOS
- Android
- WebClient（Flutter Web + Rust WASM）

## 开始使用

### 环境要求
- Flutter SDK 3.44+
- Dart SDK 3.12+
- Rust toolchain 1.91.1（仓库中的 `rust-toolchain.toml` 会固定版本）
- Android 构建额外需要 Android NDK 28.2.13676358 与 cargo-ndk 4.1.2
- WebClient 构建额外需要 `nightly-2026-07-26`、`rust-src`、
  `wasm32-unknown-unknown`、wasm-pack 0.15.0 和
  flutter_rust_bridge_codegen 2.12.0
- Linux 构建需要 `libsecret-1-dev`，运行需要 `libsecret-1-0` 和可用的 Secret Service/keyring
- Windows 构建需要 Visual Studio C++ ATL 组件

### Windows 崩溃诊断

Windows 原生崩溃会先在
`%LOCALAPPDATA%\OpenLogTool\CrashDumps` 写入 minidump，再交给 Windows
错误报告处理。Windows 10 默认启用无障碍语义树兼容保护，以规避 Flutter
在响应式布局重组语义节点时的原生崩溃。确实需要屏幕阅读器的用户可在启动前设置
`OPENLOGTOOL_ENABLE_WINDOWS_ACCESSIBILITY=1`，重新启用完整 Windows 语义树。

### 构建

```bash
git clone https://github.com/Mazha0309/OpenLogTool.git
cd OpenLogTool
flutter pub get
flutter build linux
flutter build windows
flutter build macos
flutter build apk
bash tool/build_web.sh
```

Linux、Windows 和 macOS 的平台工程会在 Flutter 构建时自动编译并打包 Rust
动态库。首次构建 Android 前还需要安装对应 Rust targets 和固定版本的
cargo-ndk；macOS 的 Release 默认生成 universal App：

```bash
# Android（在 Linux 或 macOS 上执行）
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
cargo install --locked cargo-ndk --version 4.1.2
flutter build apk --release

# macOS universal Release
rustup target add aarch64-apple-darwin x86_64-apple-darwin
flutter build macos --release

# WebClient（首次执行前安装一次）
rustup toolchain install nightly-2026-07-26 \
  --profile minimal \
  --component rust-src \
  --target wasm32-unknown-unknown
cargo install --locked wasm-pack --version 0.15.0
cargo install --locked flutter_rust_bridge_codegen --version 2.12.0
bash tool/build_web.sh
```

### WebClient 数据与部署

WebClient 与原生客户端共用同一套 Rust 数据核心、迁移和备份格式。浏览器端
SQLite 优先使用 OPFS，并在不可用时回退到持久化 IndexedDB；数据按网站来源
（协议、域名、端口）隔离，清除该网站数据会同时删除本地数据库。WebClient
不再携带旧的 Dart/sqflite 数据库实现。

Rust 工作线程依赖 `SharedArrayBuffer`。部署服务器必须返回
`Cross-Origin-Opener-Policy: same-origin` 和
`Cross-Origin-Embedder-Policy: credentialless`，WASM 还应使用
`application/wasm` MIME 类型。除 `localhost` 外应通过 HTTPS 访问，否则浏览器
不会提供安全上下文。

仓库内置的 Nginx 镜像已包含这些响应头，Docker Compose 默认使用外部端口
`5973`：

```bash
# 从源码构建 WebClient
docker compose -f docker-compose.web.yml up -d --build
# 本机访问：http://127.0.0.1:5973
```

可以覆盖外部端口，但容器内仍监听 80：

```bash
OPENLOGTOOL_WEB_PORT=8080 \
  docker compose -f docker-compose.web.yml up -d --build
```

该容器只提供静态 WebClient，不包含 OpenLogToolServer。公网部署时应由现有的
HTTPS 反向代理转发到 `127.0.0.1:5973`。GitHub Actions 会在每次推送和 PR
自动构建 WebClient；普通构建可下载 Actions artifact，`v*` 标签发布时
WebClient 压缩包会一并加入 GitHub Release。

Release 中的 WebClient 压缩包是完整的预构建 Docker 部署包，不需要仓库源码，
也不会在部署机器上重新编译 Flutter 或 Rust。下载并解压后直接运行：

```bash
tar -xzf OpenLogTool-*-WebClient.tar.gz
cd OpenLogTool-*-WebClient
docker compose up -d
```

发布包中已包含静态网页、Rust WASM、Dockerfile、Nginx 配置和
`docker-compose.yml`，默认同样映射到外部端口 `5973`。

### 迭代版本

版本号只需输入一次。下面的命令会同步 Flutter、Rust、Cargo 锁文件和应用内
版本常量，并使用 `cargo check --locked` 校验结果：

```bash
dart run tool/bump_version.dart 2.6.3-R+15
```

只检查当前文件是否一致而不修改内容：

```bash
dart run tool/bump_version.dart --check
```

`android/local.properties` 是 Flutter 在本机生成的构建配置，不是版本来源，也不
纳入 Git。Android 的 `versionName` 和 `versionCode` 均来自 `pubspec.yaml`。

Android 发布包允许连接局域网内的明文 HTTP 自建服务器，以匹配应用中可配置的
`http://` 地址；通过公网访问或承载真实账号时应使用 HTTPS，避免凭据和点名记录
在传输中暴露。

## 技术栈

- Flutter
- Provider（状态管理）
- Rust + rusqlite + SQLite（原生端）
- Rust + sqlite-wasm-rs（Web 持久化 SQLite）
- flutter_rust_bridge
- Excel（导出）

## License

GNU Affero General Public License V3
