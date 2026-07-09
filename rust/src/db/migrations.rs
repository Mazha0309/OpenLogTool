use sqlx::SqlitePool;

const CURRENT_SCHEMA_VERSION: i32 = 3;

pub async fn run(pool: &SqlitePool) -> anyhow::Result<()> {
    sqlx::query(
        "CREATE TABLE IF NOT EXISTS schema_version (
            version INTEGER PRIMARY KEY,
            applied_at TEXT NOT NULL
        )",
    )
    .execute(pool)
    .await?;

    let current: Option<(i32,)> = sqlx::query_as("SELECT version FROM schema_version")
        .fetch_optional(pool)
        .await?;
    let version = current.map(|r| r.0).unwrap_or(0);

    if version < 1 {
        migrate_v1(pool).await?;
    }
    if version < 2 {
        migrate_v2(pool).await?;
    }
    if version < 3 {
        migrate_v3(pool).await?;
    }

    sqlx::query("INSERT OR REPLACE INTO schema_version (version, applied_at) VALUES (?, ?)")
        .bind(CURRENT_SCHEMA_VERSION)
        .bind(chrono::Utc::now().to_rfc3339())
        .execute(pool)
        .await?;

    Ok(())
}

async fn migrate_v1(pool: &SqlitePool) -> anyhow::Result<()> {
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
        )",
    )
    .execute(pool)
    .await?;

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
        )",
    )
    .execute(pool)
    .await?;

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
        )",
    )
    .execute(pool)
    .await?;

    sqlx::query(
        "CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        )",
    )
    .execute(pool)
    .await?;

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
        )",
    )
    .execute(pool)
    .await?;

    sqlx::query("CREATE INDEX IF NOT EXISTS idx_logs_session ON logs(session_id)")
        .execute(pool)
        .await?;
    sqlx::query("CREATE INDEX IF NOT EXISTS idx_logs_callsign ON logs(callsign)")
        .execute(pool)
        .await?;
    sqlx::query("CREATE INDEX IF NOT EXISTS idx_dict_type ON dictionary_items(dict_type)")
        .execute(pool)
        .await?;
    sqlx::query("CREATE INDEX IF NOT EXISTS idx_oplog_session ON oplog(session_id)")
        .execute(pool)
        .await?;

    Ok(())
}

async fn migrate_v2(pool: &SqlitePool) -> anyhow::Result<()> {
    sqlx::query(
        "CREATE TABLE IF NOT EXISTS callsign_qth_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sync_id TEXT UNIQUE,
            callsign TEXT NOT NULL,
            qth TEXT NOT NULL,
            recorded_at TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            deleted_at TEXT,
            source_device_id TEXT
        )",
    )
    .execute(pool)
    .await?;

    sqlx::query(
        "CREATE INDEX IF NOT EXISTS idx_callsign_qth_callsign ON callsign_qth_history(callsign)",
    )
    .execute(pool)
    .await?;

    Ok(())
}

async fn migrate_v3(pool: &SqlitePool) -> anyhow::Result<()> {
    // 备注列可能已存在（之前手动添加），忽略重复列错误。
    let result = sqlx::query("ALTER TABLE logs ADD COLUMN remarks TEXT")
        .execute(pool)
        .await;
    if let Err(e) = &result {
        let msg = format!("{e}");
        if !msg.contains("duplicate column") {
            result?;
        }
    }
    Ok(())
}
