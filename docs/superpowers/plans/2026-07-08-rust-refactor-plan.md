# OpenLogTool Rust 重构实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 OpenLogTool 核心逻辑从 Dart 迁移到 Rust，通过 flutter_rust_bridge v2 集成

**Architecture:** Flutter 仅做 UI 层，Rust (`rust/src/`) 负责数据库 (sqlx SQLite)、业务逻辑、同步、导入导出。两者通过 flutter_rust_bridge 生成的 Dart 绑定通信。

**Tech Stack:** Rust + sqlx + tokio + serde + flutter_rust_bridge v2; Flutter + Provider

---

## 文件结构

```
rust/
├── Cargo.toml
├── src/
│   ├── lib.rs
│   ├── api/                  # bridge 暴露层
│   │   ├── mod.rs
│   │   ├── logs.rs
│   │   ├── sessions.rs
│   │   ├── dictionaries.rs
│   │   ├── settings.rs
│   │   ├── sync.rs
│   │   └── export.rs
│   ├── db/
│   │   ├── mod.rs
│   │   ├── migrations.rs     # CREATE TABLE + migrations
│   │   └── logs.rs           # 日志 CRUD
│   ├── models/
│   │   ├── mod.rs
│   │   ├── log_entry.rs
│   │   ├── session.rs
│   │   ├── dict_item.rs
│   │   ├── sync_event.rs
│   │   └── settings.rs
│   └── dict/
│       ├── mod.rs
│       └── search.rs
├── flutter_rust_bridge.yaml
└── rust-toolchain.toml (可选)

lib/ (Dart 改动)
├── main.dart                 # + bridge 初始化
├── src/
│   ├── bridge/               # 自动生成 + 手动封装
│   │   ├── frb_generated.dart
│   │   ├── frb_generated.io.dart
│   │   ├── frb_generated.web.dart
│   │   └── rust_api.dart     # 封装层
│   └── providers/            # 改为调 bridge
│       ├── log_provider.dart
│       ├── session_provider.dart
│       ├── dictionary_provider.dart
│       ├── settings_provider.dart
│       └── sync_provider.dart
```

## Phase 1: Rust Core Foundation

构建 Rust crate 骨架、数据模型、数据库迁移、基础 CRUD，并打通 bridge。

### Task 1: Rust 项目初始化

**Files:**
- Create: `rust/Cargo.toml`
- Create: `rust/src/lib.rs`
- Create: `rust/src/db/mod.rs`
- Create: `rust/src/db/migrations.rs`
- Create: `rust/src/models/mod.rs`
- Create: `rust/src/models/log_entry.rs`

**Step 1: 创建 Cargo.toml**

```toml
[package]
name = "openlogtool_core"
version = "0.1.0"
edition = "2024"
license = "AGPL-3.0"

[lib]
crate-type = ["cdylib", "staticlib", "lib"]

[dependencies]
flutter_rust_bridge = "=2.9.0"
sqlx = { version = "0.8", features = ["runtime-tokio", "sqlite"] }
tokio = { version = "1", features = ["rt", "macros"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
uuid = { version = "1", features = ["v4"] }
chrono = { version = "0.4", features = ["serde"] }
thiserror = "2"
anyhow = "1"
rand = "0.8"
sha2 = "0.10"
pinyin = "0.10"
once_cell = "1"
log = "0.4"
```

**Step 2: 创建 lib.rs**

```rust
pub mod api;
pub mod db;
pub mod dict;
pub mod models;

// 全局数据库连接
use once_cell::sync::OnceCell;
use sqlx::SqlitePool;

static DB_POOL: OnceCell<SqlitePool> = OnceCell::new();

pub async fn init_database(db_path: &str) -> anyhow::Result<()> {
    let pool = SqlitePool::connect(db_path).await?;
    sqlx::query("PRAGMA journal_mode=WAL").execute(&pool).await?;
    sqlx::query("PRAGMA foreign_keys=ON").execute(&pool).await?;
    db::migrations::run(&pool).await?;
    DB_POOL.set(pool).map_err(|_| anyhow::anyhow!("DB already initialized"))?;
    Ok(())
}

pub fn get_db() -> anyhow::Result<&'static SqlitePool> {
    DB_POOL.get().ok_or_else(|| anyhow::anyhow!("DB not initialized"))
}
```

**Step 3: 创建 models/log_entry.rs**

```rust
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LogEntry {
    pub id: Option<i64>,
    pub sync_id: String,
    pub session_id: String,
    pub time: String, // ISO-8601 full timestamp
    pub controller: String,
    pub callsign: String,
    pub rst_sent: Option<String>,
    pub rst_rcvd: Option<String>,
    pub qth: Option<String>,
    pub device: Option<String>,
    pub power: Option<String>,
    pub antenna: Option<String>,
    pub height: Option<String>,
    pub created_at: String,
    pub updated_at: String,
    pub deleted_at: Option<String>,
    pub source_device_id: Option<String>,
}

impl LogEntry {
    pub fn new(
        session_id: String,
        controller: String,
        callsign: String,
    ) -> Self {
        let now = Utc::now().to_rfc3339();
        Self {
            id: None,
            sync_id: format!("log-{}", uuid::Uuid::new_v4()),
            session_id,
            time: now.clone(),
            controller: controller.to_uppercase(),
            callsign: callsign.to_uppercase(),
            rst_sent: None,
            rst_rcvd: None,
            qth: None,
            device: None,
            power: None,
            antenna: None,
            height: None,
            created_at: now.clone(),
            updated_at: now,
            deleted_at: None,
            source_device_id: None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LogStats {
    pub total: i64,
    pub today: i64,
    pub last_7_days: i64,
}
```

**Step 4: 创建 db/migrations.rs**

```rust
use sqlx::SqlitePool;

pub async fn run(pool: &SqlitePool) -> anyhow::Result<()> {
    sqlx::query(
        "CREATE TABLE IF NOT EXISTS logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sync_id TEXT NOT NULL UNIQUE,
            session_id TEXT NOT NULL,
            time TEXT NOT NULL,
            controller TEXT NOT NULL,
            callsign TEXT NOT NULL,
            rst_sent TEXT,
            rst_rcvd TEXT,
            qth TEXT,
            device TEXT,
            power TEXT,
            antenna TEXT,
            height TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            deleted_at TEXT,
            source_device_id TEXT
        )"
    ).execute(pool).await?;

    sqlx::query(
        "CREATE TABLE IF NOT EXISTS sessions (
            session_id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'active',
            share_code TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            closed_at TEXT,
            deleted_at TEXT
        )"
    ).execute(pool).await?;

    sqlx::query(
        "CREATE TABLE IF NOT EXISTS dictionary_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            dict_type TEXT NOT NULL,
            raw TEXT NOT NULL,
            pinyin TEXT,
            abbreviation TEXT,
            sync_id TEXT UNIQUE,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            deleted_at TEXT,
            UNIQUE(dict_type, raw)
        )"
    ).execute(pool).await?;

    sqlx::query(
        "CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        )"
    ).execute(pool).await?;

    sqlx::query(
        "CREATE TABLE IF NOT EXISTS oplog (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL,
            op_type TEXT NOT NULL,
            entity_type TEXT NOT NULL,
            entity_id TEXT NOT NULL,
            data TEXT NOT NULL,
            device_id TEXT,
            created_at TEXT NOT NULL,
            applied INTEGER NOT NULL DEFAULT 0
        )"
    ).execute(pool).await?;

    // Indexes
    sqlx::query("CREATE INDEX IF NOT EXISTS idx_logs_session ON logs(session_id)").execute(pool).await?;
    sqlx::query("CREATE INDEX IF NOT EXISTS idx_logs_callsign ON logs(callsign)").execute(pool).await?;
    sqlx::query("CREATE INDEX IF NOT EXISTS idx_dict_type ON dictionary_items(dict_type)").execute(pool).await?;
    sqlx::query("CREATE INDEX IF NOT EXISTS idx_oplog_session ON oplog(session_id)").execute(pool).await?;

    Ok(())
}
```

**Step 5: 创建 db/mod.rs**

```rust
pub mod migrations;
pub mod logs;
```

**Step 6: 创建 models/mod.rs**

```rust
pub mod log_entry;
```

**Step 7: 编译验证**

```bash
cd rust && cargo check
```
Expected: 编译成功

**Step 8: 提交**

```bash
git add rust/
git commit -m "feat(rust): 初始化 Rust 核心项目结构"
```

### Task 2: 日志 CRUD

**Files:**
- Create: `rust/src/db/logs.rs`

**Step 1: 实现 logs CRUD**

```rust
use sqlx::SqlitePool;
use crate::models::log_entry::{LogEntry, LogStats};
use crate::get_db;

pub async fn insert_log(entry: &LogEntry) -> anyhow::Result<LogEntry> {
    let pool = get_db()?;
    let now = chrono::Utc::now().to_rfc3339();
    sqlx::query(
        "INSERT INTO logs (sync_id, session_id, time, controller, callsign,
         rst_sent, rst_rcvd, qth, device, power, antenna, height,
         created_at, updated_at, source_device_id)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
    )
    .bind(&entry.sync_id)
    .bind(&entry.session_id)
    .bind(&entry.time)
    .bind(&entry.controller)
    .bind(&entry.callsign)
    .bind(&entry.rst_sent)
    .bind(&entry.rst_rcvd)
    .bind(&entry.qth)
    .bind(&entry.device)
    .bind(&entry.power)
    .bind(&entry.antenna)
    .bind(&entry.height)
    .bind(&entry.created_at)
    .bind(&entry.updated_at)
    .bind(&entry.source_device_id)
    .execute(pool)
    .await?;
    get_log_by_sync_id(&entry.sync_id).await?.ok_or_else(|| anyhow::anyhow!("Failed to read back log"))
}

pub async fn get_logs(
    session_id: &str,
    page: i64,
    page_size: i64,
    search: Option<&str>,
) -> anyhow::Result<Vec<LogEntry>> {
    let pool = get_db()?;
    let offset = (page - 1) * page_size;
    let rows = if let Some(q) = search {
        let pattern = format!("%{}%", q);
        sqlx::query_as::<_, LogEntryRow>(
            "SELECT * FROM logs WHERE session_id = ? AND deleted_at IS NULL
             AND (callsign LIKE ? OR controller LIKE ? OR qth LIKE ? OR device LIKE ?)
             ORDER BY time DESC LIMIT ? OFFSET ?"
        )
        .bind(session_id).bind(&pattern).bind(&pattern).bind(&pattern).bind(&pattern)
        .bind(page_size).bind(offset)
        .fetch_all(pool).await?
    } else {
        sqlx::query_as::<_, LogEntryRow>(
            "SELECT * FROM logs WHERE session_id = ? AND deleted_at IS NULL
             ORDER BY time DESC LIMIT ? OFFSET ?"
        )
        .bind(session_id).bind(page_size).bind(offset)
        .fetch_all(pool).await?
    };
    Ok(rows.into_iter().map(|r| r.into_entry()).collect())
}

pub async fn get_log_by_sync_id(sync_id: &str) -> anyhow::Result<Option<LogEntry>> {
    let pool = get_db()?;
    let row = sqlx::query_as::<_, LogEntryRow>(
        "SELECT * FROM logs WHERE sync_id = ?"
    )
    .bind(sync_id)
    .fetch_optional(pool).await?;
    Ok(row.map(|r| r.into_entry()))
}

pub async fn get_log_stats(session_id: &str) -> anyhow::Result<LogStats> {
    let pool = get_db()?;
    let total: (i64,) = sqlx::query_as(
        "SELECT COUNT(*) FROM logs WHERE session_id = ? AND deleted_at IS NULL"
    )
    .bind(session_id)
    .fetch_one(pool).await?;

    let today_start = chrono::Utc::now().format("%Y-%m-%d").to_string();
    let today: (i64,) = sqlx::query_as(
        "SELECT COUNT(*) FROM logs WHERE session_id = ? AND deleted_at IS NULL AND time >= ?"
    )
    .bind(session_id).bind(today_start)
    .fetch_one(pool).await?;

    let week_ago = (chrono::Utc::now() - chrono::Duration::days(7)).to_rfc3339();
    let last_7: (i64,) = sqlx::query_as(
        "SELECT COUNT(*) FROM logs WHERE session_id = ? AND deleted_at IS NULL AND time >= ?"
    )
    .bind(session_id).bind(week_ago)
    .fetch_one(pool).await?;

    Ok(LogStats { total: total.0, today: today.0, last_7_days: last_7.0 })
}

pub async fn soft_delete_log(sync_id: &str) -> anyhow::Result<()> {
    let pool = get_db()?;
    let now = chrono::Utc::now().to_rfc3339();
    sqlx::query("UPDATE logs SET deleted_at = ?, updated_at = ? WHERE sync_id = ?")
        .bind(&now).bind(&now).bind(sync_id)
        .execute(pool).await?;
    Ok(())
}

pub async fn get_recent_by_callsign(callsign: &str, limit: i64) -> anyhow::Result<Vec<LogEntry>> {
    let pool = get_db()?;
    let rows = sqlx::query_as::<_, LogEntryRow>(
        "SELECT * FROM logs WHERE callsign = ? AND deleted_at IS NULL
         ORDER BY time DESC LIMIT ?"
    )
    .bind(callsign).bind(limit)
    .fetch_all(pool).await?;
    Ok(rows.into_iter().map(|r| r.into_entry()).collect())
}

// -- Internal row mapper --

#[derive(sqlx::FromRow)]
struct LogEntryRow {
    id: Option<i64>,
    sync_id: String,
    session_id: String,
    time: String,
    controller: String,
    callsign: String,
    rst_sent: Option<String>,
    rst_rcvd: Option<String>,
    qth: Option<String>,
    device: Option<String>,
    power: Option<String>,
    antenna: Option<String>,
    height: Option<String>,
    created_at: String,
    updated_at: String,
    deleted_at: Option<String>,
    source_device_id: Option<String>,
}

impl LogEntryRow {
    fn into_entry(self) -> LogEntry {
        LogEntry {
            id: self.id,
            sync_id: self.sync_id,
            session_id: self.session_id,
            time: self.time,
            controller: self.controller,
            callsign: self.callsign,
            rst_sent: self.rst_sent,
            rst_rcvd: self.rst_rcvd,
            qth: self.qth,
            device: self.device,
            power: self.power,
            antenna: self.antenna,
            height: self.height,
            created_at: self.created_at,
            updated_at: self.updated_at,
            deleted_at: self.deleted_at,
            source_device_id: self.source_device_id,
        }
    }
}
```

**Step 2: 编译验证**

```bash
cd rust && cargo check
```
Expected: 编译成功

**Step 3: 提交**

```bash
git add rust/src/db/logs.rs
git commit -m "feat(rust): 实现日志 CRUD"
```

### Task 3: Bridge API 层

**Files:**
- Create: `rust/src/api/mod.rs`
- Create: `rust/src/api/logs.rs`
- Update: `rust/src/lib.rs`

**Step 1: 创建 api/mod.rs**

```rust
pub mod logs;
```

**Step 2: 创建 api/logs.rs**

```rust
use crate::db;
use crate::models::log_entry::{LogEntry, LogStats};

/// 添加日志记录
pub async fn add_log(
    session_id: String,
    controller: String,
    callsign: String,
    rst_sent: Option<String>,
    rst_rcvd: Option<String>,
    qth: Option<String>,
    device: Option<String>,
    power: Option<String>,
    antenna: Option<String>,
    height: Option<String>,
) -> anyhow::Result<LogEntry> {
    let mut entry = LogEntry::new(session_id, controller, callsign);
    entry.rst_sent = rst_sent;
    entry.rst_rcvd = rst_rcvd;
    entry.qth = qth;
    entry.device = device;
    entry.power = power;
    entry.antenna = antenna;
    entry.height = height;
    db::logs::insert_log(&entry).await
}

/// 获取日志列表（分页）
pub async fn get_logs(
    session_id: String,
    page: Option<i64>,
    page_size: Option<i64>,
    search: Option<String>,
) -> anyhow::Result<Vec<LogEntry>> {
    db::logs::get_logs(
        &session_id,
        page.unwrap_or(1),
        page_size.unwrap_or(50),
        search.as_deref(),
    ).await
}

/// 获取日志统计
pub async fn get_log_stats(session_id: String) -> anyhow::Result<LogStats> {
    db::logs::get_log_stats(&session_id).await
}

/// 获取某个呼号最近的 N 条记录
pub async fn get_recent_by_callsign(
    callsign: String,
    limit: Option<i64>,
) -> anyhow::Result<Vec<LogEntry>> {
    db::logs::get_recent_by_callsign(&callsign.to_uppercase(), limit.unwrap_or(3)).await
}

/// 软删除一条日志
pub async fn delete_log(sync_id: String) -> anyhow::Result<()> {
    db::logs::soft_delete_log(&sync_id).await
}
```

**Step 3: 更新 lib.rs 添加 api module**

```rust
pub mod api;
pub mod db;
pub mod dict;
pub mod models;
// ... rest stays the same
```

**Step 4: 编译验证**

```bash
cd rust && cargo check
```
Expected: 编译成功

**Step 5: 提交**

```bash
git add rust/src/api/
git commit -m "feat(rust): 添加 bridge API 层"
```

### Task 4: flutter_rust_bridge 集成

**Files:**
- Create: `rust/Cargo.toml` (update to add `#[frb]` attributes knowledge)
- Create: `flutter_rust_bridge.yaml`
- Update: `pubspec.yaml` (add flutter_rust_bridge dependency)
- Update: `lib/main.dart` (add bridge init)
- Create: `lib/src/providers/rust_bridge.dart` (flutter_rust_bridge 初始化)
- Generated: `lib/src/bridge/` (自动生成)

**Step 1: 安装 flutter_rust_bridge**

```bash
cargo install flutter_rust_bridge_codegen@2.9.0
```

**Step 2: 创建 flutter_rust_bridge.yaml**

```yaml
rust_input: rust/src/api/
dart_output: lib/src/bridge
rust_root: rust/
dart_root: .
```

**Step 3: 添加 flutter_rust_bridge 到 pubspec.yaml**

```yaml
dependencies:
  flutter_rust_bridge: ^2.9.0
  # ... keep existing dependencies for now
```

**Step 4: 生成 Dart 绑定**

```bash
flutter_rust_bridge_codegen generate
```
Expected: 生成 `lib/src/bridge/frb_generated.dart` 等文件

**Step 5: 更新 lib/main.dart 添加初始化**

在 `main()` 开头添加：

```dart
import 'src/bridge/frb_generated.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  // ... rest of existing main()
}
```

注意：先保持原有的 sqflite 初始化代码，Rust 数据库路径与原有数据库不同，避免冲突。开发阶段先用独立的 Rust DB 路径。

**Step 6: 创建 Dart 封装层 lib/src/bridge/rust_api.dart**

```dart
import 'frb_generated.dart';
import 'frb_generated.io.dart' if (dart.library.html) 'frb_generated.web.dart';

class RustApi {
  static Future<void> init(String dbPath) async {
    await RustLib.init();
    await initDatabase(dbPath: dbPath);
  }

  static Future<void> initDatabase({required String dbPath}) {
    return RustLib.instance.api.initDatabase(dbPath: dbPath);
  }

  // Logs
  static Future<LogEntry> addLog({
    required String sessionId,
    required String controller,
    required String callsign,
    String? rstSent,
    String? rstRcvd,
    String? qth,
    String? device,
    String? power,
    String? antenna,
    String? height,
  }) {
    return RustLib.instance.api.addLog(
      sessionId: sessionId,
      controller: controller,
      callsign: callsign,
      rstSent: rstSent,
      rstRcvd: rstRcvd,
      qth: qth,
      device: device,
      power: power,
      antenna: antenna,
      height: height,
    );
  }

  static Future<List<LogEntry>> getLogs({
    required String sessionId,
    int? page,
    int? pageSize,
    String? search,
  }) {
    return RustLib.instance.api.getLogs(
      sessionId: sessionId,
      page: page,
      pageSize: pageSize,
      search: search,
    );
  }

  static Future<LogStats> getLogStats({required String sessionId}) {
    return RustLib.instance.api.getLogStats(sessionId: sessionId);
  }

  static Future<List<LogEntry>> getRecentByCallsign({
    required String callsign,
    int? limit,
  }) {
    return RustLib.instance.api.getRecentByCallsign(
      callsign: callsign,
      limit: limit,
    );
  }

  static Future<void> deleteLog({required String syncId}) {
    return RustLib.instance.api.deleteLog(syncId: syncId);
  }
}
```

**Step 7: 编译验证**

```bash
flutter pub get && flutter build linux --debug
```
Expected: 构建成功

**Step 8: 提交**

```bash
git add flutter_rust_bridge.yaml lib/src/bridge/ rust/ pubspec.yaml pubspec.lock
git commit -m "feat: flutter_rust_bridge 集成"
```

## Phase 2: 核心功能对接

将现有 Flutter Provider 逐步切换到调 Rust bridge。

### Task 5: 会话管理

**Files:**
- Create: `rust/src/models/session.rs`
- Create: `rust/src/api/sessions.rs`
- Update: `rust/src/db/migrations.rs` (已包含 sessions 表)
- Update: `rust/src/api/mod.rs`
- Update: `rust/src/models/mod.rs`
- Update: `lib/src/bridge/rust_api.dart`

**Step 1: 创建 models/session.rs**

```rust
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Session {
    pub session_id: String,
    pub title: String,
    pub status: String,
    pub share_code: Option<String>,
    pub created_at: String,
    pub updated_at: String,
    pub closed_at: Option<String>,
    pub deleted_at: Option<String>,
}

impl Session {
    pub fn new(title: String) -> Self {
        use sha2::{Sha256, Digest};
        use rand::Rng;
        let now = chrono::Utc::now();
        let random: u64 = rand::thread_rng().gen();
        let hash = Sha256::digest(format!("{}{}", now.timestamp_nanos(), random));
        let session_id = format!("{:x}", hash);
        let ts = now.to_rfc3339();
        let share_code = Some(format!("{:06X}", rand::thread_rng().gen_range(0..0xFFFFFF)));
        Self {
            session_id,
            title,
            status: "active".to_string(),
            share_code,
            created_at: ts.clone(),
            updated_at: ts,
            closed_at: None,
            deleted_at: None,
        }
    }
}
```

**Step 2: 创建 api/sessions.rs**

```rust
use crate::models::session::Session;
use crate::get_db;

pub async fn create_session(title: String) -> anyhow::Result<Session> {
    let pool = get_db()?;
    let session = Session::new(title);
    sqlx::query(
        "INSERT INTO sessions (session_id, title, status, share_code, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?)"
    )
    .bind(&session.session_id)
    .bind(&session.title)
    .bind(&session.status)
    .bind(&session.share_code)
    .bind(&session.created_at)
    .bind(&session.updated_at)
    .execute(pool).await?;
    Ok(session)
}

pub async fn list_sessions() -> anyhow::Result<Vec<Session>> {
    let pool = get_db()?;
    let rows = sqlx::query_as::<_, SessionRow>(
        "SELECT * FROM sessions WHERE deleted_at IS NULL ORDER BY created_at DESC"
    )
    .fetch_all(pool).await?;
    Ok(rows.into_iter().map(|r| r.into_session()).collect())
}

pub async fn close_session(session_id: String) -> anyhow::Result<()> {
    let pool = get_db()?;
    let now = chrono::Utc::now().to_rfc3339();
    sqlx::query("UPDATE sessions SET status = 'closed', closed_at = ?, updated_at = ? WHERE session_id = ?")
        .bind(&now).bind(&now).bind(&session_id)
        .execute(pool).await?;
    Ok(())
}

pub async fn join_session(share_code: String) -> anyhow::Result<Session> {
    let pool = get_db()?;
    let row = sqlx::query_as::<_, SessionRow>(
        "SELECT * FROM sessions WHERE share_code = ? AND deleted_at IS NULL AND status = 'active'"
    )
    .bind(&share_code)
    .fetch_optional(pool).await?
    .ok_or_else(|| anyhow::anyhow!("Session not found"))?;
    Ok(row.into_session())
}

#[derive(sqlx::FromRow)]
struct SessionRow {
    session_id: String,
    title: String,
    status: String,
    share_code: Option<String>,
    created_at: String,
    updated_at: String,
    closed_at: Option<String>,
    deleted_at: Option<String>,
}

impl SessionRow {
    fn into_session(self) -> Session {
        Session {
            session_id: self.session_id,
            title: self.title,
            status: self.status,
            share_code: self.share_code,
            created_at: self.created_at,
            updated_at: self.updated_at,
            closed_at: self.closed_at,
            deleted_at: self.deleted_at,
        }
    }
}
```

**Step 3: 更新 RustApi 封装 + 提交**

```bash
git add rust/src/models/session.rs rust/src/api/sessions.rs lib/src/bridge/rust_api.dart
git commit -m "feat(rust): 会话管理"
```

### Task 6: Provider 对接 — LogProvider 改调 Rust

**Files:**
- Modify: `lib/providers/log_provider.dart` (大规模重写)
- Keep existing interface but delegate to RustApi

**Step 1: 重写 LogProvider**

```dart
import 'package:flutter/foundation.dart';
import 'package:openlogtool/src/bridge/rust_api.dart';

class LogProvider extends ChangeNotifier {
  List<LogEntry> _logs = [];
  LogStats? _stats;
  bool _loading = false;
  String? _error;
  int _currentPage = 1;
  final int _pageSize = 50;

  List<LogEntry> get logs => _logs;
  LogStats? get stats => _stats;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> loadLogs(String sessionId, {String? search, bool append = false}) async {
    _loading = true;
    notifyListeners();
    try {
      if (!append) _currentPage = 1;
      final result = await RustApi.getLogs(
        sessionId: sessionId,
        page: _currentPage,
        pageSize: _pageSize,
        search: search,
      );
      if (append) {
        _logs = [..._logs, ...result];
      } else {
        _logs = result;
      }
      _stats = await RustApi.getLogStats(sessionId: sessionId);
      _error = null;
    } catch (e) {
      _error = e.toString();
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> addLog({
    required String sessionId,
    required String controller,
    required String callsign,
    String? rstSent,
    String? rstRcvd,
    String? qth,
    String? device,
    String? power,
    String? antenna,
    String? height,
  }) async {
    try {
      await RustApi.addLog(
        sessionId: sessionId,
        controller: controller,
        callsign: callsign,
        rstSent: rstSent,
        rstRcvd: rstRcvd,
        qth: qth,
        device: device,
        power: power,
        antenna: antenna,
        height: height,
      );
      await loadLogs(sessionId);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> deleteLog(String sessionId, String syncId) async {
    try {
      await RustApi.deleteLog(syncId: syncId);
      await loadLogs(sessionId);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }
}
```

**Step 2: 提交**

```bash
git add lib/providers/log_provider.dart
git commit -m "feat: LogProvider 对接 Rust bridge"
```

## Phase 3: 词典 + 设置

### Task 7: 词典系统

**Files:**
- Create: `rust/src/dict/mod.rs`
- Create: `rust/src/dict/search.rs`
- Create: `rust/src/api/dictionaries.rs`
- Create: `rust/src/models/dict_item.rs`
- Update: `lib/src/bridge/rust_api.dart`
- Update: `lib/providers/dictionary_provider.dart`

**Step 1: 创建 models/dict_item.rs**

```rust
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DictItem {
    pub id: Option<i64>,
    pub dict_type: String,
    pub raw: String,
    pub pinyin: Option<String>,
    pub abbreviation: Option<String>,
    pub sync_id: String,
    pub created_at: String,
    pub updated_at: String,
    pub deleted_at: Option<String>,
}

impl DictItem {
    pub fn new(dict_type: String, raw: String) -> Self {
        let now = chrono::Utc::now().to_rfc3339();
        Self {
            id: None,
            dict_type,
            raw,
            pinyin: None,
            abbreviation: None,
            sync_id: format!("dict-{}", uuid::Uuid::new_v4()),
            created_at: now.clone(),
            updated_at: now,
            deleted_at: None,
        }
    }
}
```

**Step 2: 创建 dict/search.rs**

```rust
use crate::models::dict_item::DictItem;
use crate::get_db;

pub async fn search_dict(dict_type: &str, query: &str, limit: i64) -> anyhow::Result<Vec<DictItem>> {
    let pool = get_db()?;
    let pattern = format!("%{}%", query);
    let rows = sqlx::query_as::<_, DictItemRow>(
        "SELECT * FROM dictionary_items
         WHERE dict_type = ? AND deleted_at IS NULL
         AND (raw LIKE ? OR pinyin LIKE ? OR abbreviation LIKE ?)
         ORDER BY raw ASC LIMIT ?"
    )
    .bind(dict_type).bind(&pattern).bind(&pattern).bind(&pattern)
    .bind(limit)
    .fetch_all(pool).await?;
    Ok(rows.into_iter().map(|r| r.into_item()).collect())
}

pub async fn add_dict_item(item: &DictItem) -> anyhow::Result<()> {
    let pool = get_db()?;
    sqlx::query(
        "INSERT OR IGNORE INTO dictionary_items (dict_type, raw, pinyin, abbreviation, sync_id, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?)"
    )
    .bind(&item.dict_type).bind(&item.raw).bind(&item.pinyin).bind(&item.abbreviation)
    .bind(&item.sync_id).bind(&item.created_at).bind(&item.updated_at)
    .execute(pool).await?;
    Ok(())
}

pub async fn seed_dict(dict_type: &str, items: Vec<String>) -> anyhow::Result<usize> {
    let pool = get_db()?;
    let count = sqlx::query_as::<(i64,)>(
        "SELECT COUNT(*) FROM dictionary_items WHERE dict_type = ?"
    )
    .bind(dict_type)
    .fetch_one(pool).await?.0;
    if count > 0 {
        return Ok(count as usize);
    }
    let now = chrono::Utc::now().to_rfc3339();
    for raw in items {
        let sync_id = format!("dict-{}", uuid::Uuid::new_v4());
        sqlx::query(
            "INSERT OR IGNORE INTO dictionary_items (dict_type, raw, sync_id, created_at, updated_at)
             VALUES (?, ?, ?, ?, ?)"
        )
        .bind(dict_type).bind(&raw).bind(&sync_id).bind(&now).bind(&now)
        .execute(pool).await?;
    }
    let total: (i64,) = sqlx::query_as(
        "SELECT COUNT(*) FROM dictionary_items WHERE dict_type = ?"
    )
    .bind(dict_type)
    .fetch_one(pool).await?;
    Ok(total.0 as usize)
}

#[derive(sqlx::FromRow)]
struct DictItemRow {
    id: Option<i64>,
    dict_type: String,
    raw: String,
    pinyin: Option<String>,
    abbreviation: Option<String>,
    sync_id: String,
    created_at: String,
    updated_at: String,
    deleted_at: Option<String>,
}

impl DictItemRow {
    fn into_item(self) -> DictItem {
        DictItem {
            id: self.id,
            dict_type: self.dict_type,
            raw: self.raw,
            pinyin: self.pinyin,
            abbreviation: self.abbreviation,
            sync_id: self.sync_id,
            created_at: self.created_at,
            updated_at: self.updated_at,
            deleted_at: self.deleted_at,
        }
    }
}
```

**Step 3: 创建 api/dictionaries.rs**

```rust
use crate::models::dict_item::DictItem;
use crate::dict;

pub async fn search_dict(dict_type: String, query: String, limit: Option<i64>) -> anyhow::Result<Vec<DictItem>> {
    dict::search::search_dict(&dict_type, &query, limit.unwrap_or(20)).await
}

pub async fn add_dict_item(dict_type: String, raw: String) -> anyhow::Result<()> {
    let pinyin = pinyin::to_pinyin(&raw).map(|s| s.to_string());
    let item = DictItem::new(dict_type, raw);
    dict::search::add_dict_item(&item).await
}

pub async fn seed_dict(dict_type: String, items: Vec<String>) -> anyhow::Result<usize> {
    dict::search::seed_dict(&dict_type, items).await
}
```

**Step 4: 更新 RustApi + DictionaryProvider → 提交**

### Task 8: 设置系统

**Files:**
- Create: `rust/src/models/settings.rs`
- Create: `rust/src/api/settings.rs`
- Update: `lib/src/bridge/rust_api.dart`
- Update: `lib/providers/settings_provider.dart`

**Step 1: 创建 api/settings.rs**

```rust
use crate::get_db;

pub async fn get_setting(key: String) -> anyhow::Result<Option<String>> {
    let pool = get_db()?;
    let row: Option<(String,)> = sqlx::query_as(
        "SELECT value FROM settings WHERE key = ?"
    )
    .bind(&key)
    .fetch_optional(pool).await?;
    Ok(row.map(|r| r.0))
}

pub async fn set_setting(key: String, value: String) -> anyhow::Result<()> {
    let pool = get_db()?;
    sqlx::query(
        "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)"
    )
    .bind(&key).bind(&value)
    .execute(pool).await?;
    Ok(())
}

pub async fn get_all_settings() -> anyhow::Result<Vec<(String, String)>> {
    let pool = get_db()?;
    let rows: Vec<(String, String)> = sqlx::query_as(
        "SELECT key, value FROM settings"
    )
    .fetch_all(pool).await?;
    Ok(rows)
}
```

**Step 2: 更新 SettingsProvider → 从 Rust 读写**

**Step 3: 提交**

## Phase 4: 导出 + UI 风格

### Task 9: JSON/Excel 导出

**Files:**
- Create: `rust/src/api/export.rs`
- Create: `rust/src/models/export_settings.rs` (for Excel config)
- Update: `lib/src/bridge/rust_api.dart`

**Step 1: 实现 JSON 导出**

```rust
use crate::get_db;
use crate::models::log_entry::LogEntry;

pub async fn export_json(session_id: String) -> anyhow::Result<Vec<u8>> {
    let pool = get_db()?;
    let rows = sqlx::query_as::<_, LogEntryRow>(
        "SELECT * FROM logs WHERE session_id = ? AND deleted_at IS NULL ORDER BY time ASC"
    )
    .bind(&session_id)
    .fetch_all(pool).await?;
    let entries: Vec<LogEntry> = rows.into_iter().map(|r| r.into_entry()).collect();
    let json = serde_json::to_string_pretty(&entries)?;
    Ok(json.into_bytes())
}
```

**Step 2: 实现 Excel 导出 (使用 rust_xlsxwriter)**

Cargo.toml 添加依赖：`rust_xlsxwriter = "0.83"`

**Step 3: 更新 UI — ExportPanel → 调 RustApi**

**Step 4: 提交**

### Task 10: UI 风格迁移 (shadcn)

**Files:**
- Modify: `lib/main.dart` — 替换 MaterialApp theme 为 shadcn 风格
- Modify: 各个 widget 文件 — 替换 MD3 组件
- Create: `lib/src/widgets/shadcn/` — shadcn 风格组件库

**Step 1: 创建 shadcn 基础组件**

Button, Card, Input, Table, Dialog 等基础组件的 shadcn 风格实现：
- 干净边框 `border: 1px solid var(--border)`
- 圆角 `border-radius: 12px`
- 柔和阴影
- 无 elevation
- 细字体权重

**Step 2: 逐页面替换**

从核心表单/表格开始，逐步替换。

**Step 3: 提交**

## 后续 Phase

### Phase 5: 同步协议
- OpLog CRUD
- HTTP 客户端 (reqwest)
- WebSocket (tokio-tungstenite)
- 实时广播

### Phase 6: 协同会话
- Session 创建/加入/离开
- Share code 生成与验证
- 角色权限控制
- 断线重连逻辑

### Phase 7: 旧代码清理
- 删除 `lib/database/`
- 删除 `lib/services/` (auth, share, collaboration)
- 清理 pubspec.yaml 中不再使用的依赖
