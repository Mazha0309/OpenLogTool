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
- 支持从文本文件导入

### 数据导入导出
- JSON导出/导入
- Excel导出

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

## 开始使用

### 环境要求
- Flutter SDK 3.41+
- Dart SDK 3.11+
- Rust toolchain 1.91.1（仓库中的 `rust-toolchain.toml` 会固定版本）
- Android 构建额外需要 Android NDK 28.2.13676358 与 cargo-ndk 4.1.2

### 构建

```bash
git clone https://github.com/Mazha0309/OpenLogTool.git
cd OpenLogTool
flutter pub get
flutter build linux
flutter build windows
flutter build macos
flutter build apk
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
```

Android 发布包允许连接局域网内的明文 HTTP 自建服务器，以匹配应用中可配置的
`http://` 地址；通过公网访问或承载真实账号时应使用 HTTPS，避免凭据和点名记录
在传输中暴露。

## 技术栈

- Flutter
- Provider（状态管理）
- Rust + SQLx + SQLite（本地数据与协作副本）
- flutter_rust_bridge
- Excel（导出）

## License

GNU Affero General Public License V3
