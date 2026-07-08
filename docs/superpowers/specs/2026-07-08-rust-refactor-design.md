# OpenLogTool Rust 重构设计文档

## 概述

将 OpenLogTool 从纯 Flutter/Dart 重构为 **Flutter + Rust** 混合架构。Flutter 仅负责 UI 层，所有核心逻辑（数据库、业务逻辑、网络同步、导入导出）迁移到 Rust。

- 技术方案：`flutter_rust_bridge` v2
- UI 风格：shadcn 风格（替代 Material Design 3）
- 授权：AGPL-3.0
- 仓库：https://github.com/Mazha0309/OpenLogTool

---

## 架构

```
Flutter (Dart)                      Rust Core (openlogtool_core)
┌──────────────────────┐           ┌──────────────────────────────┐
│  Screens / Widgets   │           │  ┌─────┐ ┌──────┐ ┌──────┐ │
│  (shadcn 风格)        │  bridge   │  │ db  │ │ sync │ │export│ │
│         ↓            │◄─────────►│  │sqlx │ │req+ws│ │ xlsx │ │
│  Providers (thin)    │  api 调用  │  └──┬──┘ └──┬───┘ └──┬───┘ │
│         ↓            │           │     │       │        │      │
│  bridge bindings     │           │  ┌──▼───────▼────────▼───┐ │
│  (自动生成)           │           │  │        api/           │ │
└──────────────────────┘           │  │  (bridge 暴露层)       │ │
                                    │  └──────────────────────┘ │
                                    └──────────────────────────────┘
```

### Rust 模块

| 模块 | 职责 |
|------|------|
| `api/` | flutter_rust_bridge 暴露的所有公开函数 |
| `db/` | SQLite (sqlx)、migrations、所有 CRUD 操作 |
| `models/` | 数据模型定义 (serde) |
| `sync/` | 协同同步、HTTP 客户端、WebSocket、OpLog 协议 |
| `export/` | JSON 导出、Excel 导出 (rust_xlsxwriter) |
| `dict/` | 词典管理和模糊搜索 |
| `settings/` | 设置存取 |

---

## 项目文件结构

```
openlogtool/
├── lib/                        # Flutter UI (Dart)
│   ├── main.dart
│   ├── src/
│   │   ├── screens/            # UI 页面（保持现有结构）
│   │   ├── widgets/            # shadcn 风格组件
│   │   │   ├── log_form.dart   # 添加记录表单
│   │   │   ├── log_table.dart  # 日志列表表格
│   │   │   ├── callsign_field.dart  # 呼号输入 + 历史下拉
│   │   │   ├── dictionary_manager.dart
│   │   │   └── settings_panel.dart
│   │   ├── providers/          # 状态管理 (调用 bridge)
│   │   └── bridge/             # flutter_rust_bridge 生成的绑定
│   └── ...
├── rust/                       # Rust 核心代码
│   ├── Cargo.toml
│   └── src/
│       ├── lib.rs
│       ├── api/                # bridge 暴露函数
│       │   ├── mod.rs
│       │   ├── logs.rs
│       │   ├── sessions.rs
│       │   ├── dictionaries.rs
│       │   ├── settings.rs
│       │   ├── sync.rs
│       │   └── export.rs
│       ├── db/
│       │   ├── mod.rs
│       │   ├── migrations.rs   # 数据库迁移
│       │   ├── logs.rs         # 日志 CRUD
│       │   ├── sessions.rs     # 会话 CRUD
│       │   └── dictionaries.rs # 词典 CRUD
│       ├── models/
│       │   ├── mod.rs
│       │   ├── log_entry.rs
│       │   ├── session.rs
│       │   ├── dict_item.rs
│       │   ├── settings.rs
│       │   ├── sync_event.rs   # OpLog / SyncEvent
│       │   └── export.rs
│       ├── sync/
│       │   ├── mod.rs
│       │   ├── protocol.rs     # OpLog 协议定义
│       │   ├── client.rs       # HTTP 客户端 (reqwest)
│       │   ├── ws.rs           # WebSocket (tokio-tungstenite)
│       │   └── conflict.rs     # 冲突解决
│       ├── export/
│       │   ├── mod.rs
│       │   ├── json.rs
│       │   └── excel.rs
│       ├── dict/
│       │   ├── mod.rs
│       │   └── search.rs       # 模糊搜索 (pinyin/abbreviation)
│       └── settings/
│           ├── mod.rs
│           └── store.rs
├── pubspec.yaml
├── flutter_rust_bridge.yaml
└── ...
```

---

## 数据库

### 表结构

**logs** — 日志记录

| 列 | 类型 | 说明 |
|----|------|------|
| `id` | INTEGER PK AI | 本地自增 ID |
| `sync_id` | TEXT UNIQUE | UUID |
| `session_id` | TEXT FK → sessions | 归属会话 |
| `time` | TEXT NOT NULL | ISO-8601 完整时间戳，导出时显示 HH:mm，默认当前时间 |
| `controller` | TEXT NOT NULL | 主控呼号 |
| `callsign` | TEXT NOT NULL | 点名呼号 |
| `rst_sent` | TEXT | 发 (给对方) 的信号报告 |
| `rst_rcvd` | TEXT | 收 (对方给) 的信号报告 |
| `qth` | TEXT | 位置 |
| `device` | TEXT | 设备 |
| `power` | TEXT | 功率 |
| `antenna` | TEXT | 天线 |
| `height` | TEXT | 高度 |
| `created_at` | TEXT | ISO-8601 UTC |
| `updated_at` | TEXT | ISO-8601 UTC |
| `deleted_at` | TEXT | 软删除 (NULL=活跃) |
| `source_device_id` | TEXT | 来源设备 ID |

**sessions** — 点名单/会话

| 列 | 类型 | 说明 |
|----|------|------|
| `session_id` | TEXT PK | SHA-256 hash |
| `title` | TEXT NOT NULL | 会话名称 |
| `status` | TEXT NOT NULL | active / closed / archived |
| `share_code` | TEXT | 6 位分享码 |
| `created_at` | TEXT | |
| `updated_at` | TEXT | |
| `closed_at` | TEXT | 关闭时间 |
| `deleted_at` | TEXT | 软删除 |

**dictionary_items** — 词典（原 4 表合一）

| 列 | 类型 | 说明 |
|----|------|------|
| `id` | INTEGER PK AI | |
| `dict_type` | TEXT NOT NULL | device / antenna / callsign / qth |
| `raw` | TEXT NOT NULL | 显示值 |
| `pinyin` | TEXT | 拼音（中文搜索） |
| `abbreviation` | TEXT | 缩写 |
| `sync_id` | TEXT UNIQUE | |
| `created_at` | TEXT | |
| `updated_at` | TEXT | |
| `deleted_at` | TEXT | |

**settings** — 应用设置

| 列 | 类型 | 说明 |
|----|------|------|
| `key` | TEXT PK | 设置键 |
| `value` | TEXT | 设置值 |

**oplog** — 操作日志（协同同步核心）

| 列 | 类型 | 说明 |
|----|------|------|
| `id` | INTEGER PK AI | 单调递增 Watermark |
| `session_id` | TEXT | 所属会话 |
| `op_type` | TEXT | upsert_log / delete_log / upsert_dict / ... |
| `entity_type` | TEXT | log / session / dict |
| `entity_id` | TEXT | 操作目标的 sync_id |
| `data` | TEXT JSON | 操作数据 |
| `device_id` | TEXT | 来源设备 |
| `created_at` | TEXT | |
| `applied` | BOOL | 是否已应用 |

### 词典种子数据

- `device.json`、`antenna.json`、`qth.json` 三个资产文件不变
- 首次启动时（表为空）自动导入
- `callsign` 词典初始为空，用户输入时自动积累

---

## 同步协议

### 核心设计

以 **Session 为边界**、**OpLog 为基础**、**WebSocket 实时广播**的协同同步协议。

### 角色

- **记录员 (Logger)** — 可增删改记录、创建/管理会话
- **观众 (Viewer)** — 实时查看，不能操作

任意记录员可创建会话并生成 6 位 share_code 邀请他人加入。

### 流程

```
1. 创建会话
   Logger: createSession("晚点名")
   → 本地写入 session + oplog(session.created)
   → 生成 6 位 share_code

2. 加入会话
   Viewer: joinSession(share_code)
   → WebSocket 连接到 session
   → 拉取从头开始的全部 oplog (watermark=0)
   → 回放 ops 构建本地数据

3. 实时记录
   Logger 添加日志:
     → 写入 logs 表
     → 写入 oplog (watermark+1)
     → WS 广播 { op_type, data, device_id, session_id }
   其他人收到:
     → 过滤自己发的 (by device_id)
     → 应用到本地

4. 断线重连
     → push 本地未同步 ops (applied=false)
     → pull (watermark 之后的 ops)
     → 回放合并

5. 冲突解决
   Last-Writer-Wins (按 created_at 时间戳)
   已删除的记录后续 update → 忽略
```

### API 端点

所有端点前缀 `/api/v1/logs/`

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/sessions` | 创建会话 |
| POST | `/sessions/join` | 通过 share_code 加入 |
| GET | `/sessions/{id}/ops?since={watermark}` | 拉取增量 ops |
| POST | `/sessions/{id}/ops` | 推送本地 ops |
| DELETE | `/sessions/{id}` | 关闭/删除会话 |
| WS | `/ws?session_id=&device_id=` | 实时 WebSocket |

---

## Bridge API (Dart ↔ Rust)

### 日志

```dart
Future<LogEntry> addLog(LogEntry entry, String sessionId);
Future<void> updateLog(LogEntry entry);
Future<void> deleteLog(String syncId);
Future<List<LogEntry>> getLogs(String sessionId, {int page, int pageSize, String? search});
Future<LogStats> getLogStats(String sessionId);
Future<LogEntry?> getLatestByCallsign(String callsign);
Future<List<LogEntry>> getRecentByCallsign(String callsign, int limit);
Future<void> undoLastLog(String sessionId);
```

### 会话

```dart
Future<Session> createSession(String title);
Future<void> closeSession(String sessionId);
Future<List<Session>> listSessions();
Future<Session?> joinSession(String shareCode);
```

### 词典

```dart
Future<List<DictItem>> searchDict(String dictType, String query, {int limit});
Future<void> addDictItem(DictItem item);
Future<void> importDictFromFile(String dictType, String path);
Future<List<DictItem>> getAllDictItems(String dictType);
```

### 设置

```dart
Future<String?> getSetting(String key);
Future<void> setSetting(String key, String value);
Future<Map<String, String>> getAllSettings();
```

### 同步

```dart
Future<String> connectToSession(String shareCode);
Future<void> disconnectSession();
Stream<SyncEvent> syncEventStream();
SyncStatus getSyncStatus();
```

### 导出

```dart
Future<Uint8List> exportJson(String sessionId);
Future<Uint8List> exportExcel(String sessionId, ExportSettings settings);
```

---

## 关键功能

### 呼号历史复用

- 输入呼号时，自动显示该呼号最近 3 条记录的完整内容（设备/天线/功率/高度/QTH/RST 收发）
- 选中一条后预填所有字段
- 时间保持默认当前时间（完整时间戳存储，导出时格式化为 HH:mm）
- 数据来源：按 callsign 降序查 logs 表，limit 3

### 信号报告拆分为 收/发

- 表单两个输入框：**RST 发**（给对方）和 **RST 收**（对方反馈）
- 表格显示两列
- Excel 导出两列
- 向后兼容：导入旧 JSON 时 report 字段自动填入 rst_sent

### 词典合一

- 原 4 张结构相同的表合并为 `dictionary_items` + `dict_type`
- 搜索条件增加 `dict_type` 过滤
- 其余功能不变（自动添加、文件导入、模糊搜索）

---

## Rust 技术栈

| 组件 | 选型 |
|------|------|
| 数据库 | sqlx (SQLite, async) |
| HTTP | reqwest |
| WebSocket | tokio-tungstenite |
| Excel | rust_xlsxwriter |
| 序列化 | serde + serde_json |
| 异步 | tokio |
| UUID | uuid |
| 哈希 | sha2 |
| 随机数 | rand |
| 日期/时间 | chrono |
| 错误处理 | thiserror + anyhow |
| 中文拼音 | pinyin |

---

## 实现顺序

1. **Rust 骨架** — Cargo.toml、模块结构、sqlx 连接、migrations
2. **数据模型 + 基础 CRUD** — models + db 层
3. **Bridge 集成** — flutter_rust_bridge 配置、Dart 绑定
4. **词典系统** — 字典 CRUD + 种子数据 + 搜索
5. **设置系统** — settings 存取
6. **表单/表格数据流** — Provider 调 bridge → UI 渲染
7. **呼号历史复用** — 最近3条记录预填
8. **同步协议** — OpLog + HTTP + WebSocket
9. **协同会话** — 创建/加入/实时广播
10. **导出** — JSON + Excel
11. **UI 风格迁移** — 替换 MD3 为 shadcn 组件
12. **删除旧代码** — 清理原 Dart 数据库/网络层
