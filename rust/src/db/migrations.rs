use sqlx::{Sqlite, SqlitePool, Transaction};

const CURRENT_SCHEMA_VERSION: i32 = 7;

pub async fn run(pool: &SqlitePool) -> anyhow::Result<()> {
    sqlx::query(
        "CREATE TABLE IF NOT EXISTS schema_version (
            version INTEGER PRIMARY KEY,
            applied_at TEXT NOT NULL
        )",
    )
    .execute(pool)
    .await?;

    // Older releases used `version` itself as the primary key and inserted the
    // new version without deleting the previous row. MAX keeps upgrades correct
    // for databases that already contain more than one version row.
    let current: (Option<i32>,) = sqlx::query_as("SELECT MAX(version) FROM schema_version")
        .fetch_one(pool)
        .await?;
    let version = current.0.unwrap_or(0);

    if version > CURRENT_SCHEMA_VERSION {
        anyhow::bail!(
            "DATABASE_SCHEMA_TOO_NEW: found version {version}, supported version is {CURRENT_SCHEMA_VERSION}"
        );
    }

    if version < 1 {
        migrate_v1(pool).await?;
    }
    if version < 2 {
        migrate_v2(pool).await?;
    }
    if version < 3 {
        migrate_v3(pool).await?;
    }
    if version < 4 {
        migrate_v4(pool).await?;
    }
    if version < 5 {
        migrate_v5(pool).await?;
    }
    if version < 6 {
        migrate_v6(pool).await?;
    }
    // v7 was developed across builds that could already have written schema
    // version 7 before every v7 object was present. Keep this migration
    // idempotent and re-assert its shape for version-7 databases so those
    // installations cannot expose a nine-column dictionary row to the
    // ten-column Rust model.
    migrate_v7(pool).await?;

    let mut tx = pool.begin().await?;
    sqlx::query("DELETE FROM schema_version")
        .execute(&mut *tx)
        .await?;
    sqlx::query("INSERT INTO schema_version (version, applied_at) VALUES (?, ?)")
        .bind(CURRENT_SCHEMA_VERSION)
        .bind(chrono::Utc::now().to_rfc3339())
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;

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

async fn execute_v4(tx: &mut Transaction<'_, Sqlite>, sql: &str) -> anyhow::Result<()> {
    sqlx::query(sql).execute(&mut **tx).await?;
    Ok(())
}

async fn migrate_v4(pool: &SqlitePool) -> anyhow::Result<()> {
    let mut tx = pool.begin().await?;

    execute_v4(
        &mut tx,
        "CREATE TABLE IF NOT EXISTS device_state (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            device_id TEXT NOT NULL UNIQUE,
            created_at TEXT NOT NULL
        )",
    )
    .await?;

    execute_v4(
        &mut tx,
        "CREATE TABLE IF NOT EXISTS collaboration_bindings (
            server_instance_id TEXT NOT NULL,
            server_origin TEXT NOT NULL,
            account_id TEXT NOT NULL,
            session_id TEXT NOT NULL REFERENCES sessions(session_id) ON DELETE CASCADE,
            membership_id TEXT NOT NULL,
            membership_version INTEGER NOT NULL CHECK (membership_version >= 1),
            role TEXT NOT NULL CHECK (role IN ('owner', 'editor', 'viewer')),
            replica_state TEXT NOT NULL CHECK (
                replica_state IN ('publishing', 'joining', 'snapshotting', 'ready', 'revoked', 'failed')
            ),
            last_applied_seq INTEGER NOT NULL DEFAULT 0 CHECK (last_applied_seq >= 0),
            last_seen_head_seq INTEGER NOT NULL DEFAULT 0 CHECK (last_seen_head_seq >= 0),
            joined_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            revoked_at TEXT,
            PRIMARY KEY (server_instance_id, account_id, session_id),
            UNIQUE (session_id)
        )",
    )
    .await?;

    execute_v4(
        &mut tx,
        "CREATE INDEX IF NOT EXISTS idx_collaboration_bindings_identity
         ON collaboration_bindings(server_instance_id, account_id, replica_state)",
    )
    .await?;

    execute_v4(
        &mut tx,
        "CREATE TABLE IF NOT EXISTS entity_shadows (
            server_instance_id TEXT NOT NULL,
            account_id TEXT NOT NULL,
            session_id TEXT NOT NULL,
            entity_type TEXT NOT NULL CHECK (entity_type IN ('session', 'log')),
            entity_id TEXT NOT NULL,
            server_version INTEGER NOT NULL CHECK (server_version >= 1),
            last_event_seq INTEGER NOT NULL CHECK (last_event_seq >= 0),
            server_json TEXT NOT NULL,
            deleted INTEGER NOT NULL DEFAULT 0 CHECK (deleted IN (0, 1)),
            PRIMARY KEY (
                server_instance_id, account_id, session_id, entity_type, entity_id
            ),
            FOREIGN KEY (server_instance_id, account_id, session_id)
                REFERENCES collaboration_bindings(
                    server_instance_id, account_id, session_id
                ) ON DELETE CASCADE
        )",
    )
    .await?;

    execute_v4(
        &mut tx,
        "CREATE INDEX IF NOT EXISTS idx_entity_shadows_session_type
         ON entity_shadows(server_instance_id, account_id, session_id, entity_type)",
    )
    .await?;

    tx.commit().await?;
    Ok(())
}

async fn execute_v5(tx: &mut Transaction<'_, Sqlite>, sql: &str) -> anyhow::Result<()> {
    sqlx::query(sql).execute(&mut **tx).await?;
    Ok(())
}

async fn migrate_v5(pool: &SqlitePool) -> anyhow::Result<()> {
    let mut tx = pool.begin().await?;

    execute_v5(
        &mut tx,
        "CREATE TABLE IF NOT EXISTS sync_outbox (
            local_seq INTEGER PRIMARY KEY AUTOINCREMENT,
            server_instance_id TEXT NOT NULL,
            account_id TEXT NOT NULL,
            session_id TEXT NOT NULL,
            mutation_id TEXT NOT NULL UNIQUE,
            entity_type TEXT NOT NULL CHECK (entity_type IN ('session', 'log')),
            entity_id TEXT NOT NULL,
            operation TEXT NOT NULL CHECK (
                operation IN ('create', 'update', 'delete', 'restore', 'close', 'reopen')
            ),
            base_version INTEGER NOT NULL CHECK (base_version >= 0),
            observed_seq INTEGER NOT NULL CHECK (observed_seq >= 0),
            base_json TEXT,
            payload_json TEXT NOT NULL,
            state TEXT NOT NULL DEFAULT 'pending' CHECK (
                state IN (
                    'pending', 'sending', 'accepted', 'retrying',
                    'conflict', 'rejected'
                )
            ),
            attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
            next_attempt_at TEXT,
            accepted_event_seq INTEGER CHECK (accepted_event_seq IS NULL OR accepted_event_seq >= 1),
            depends_on_mutation_id TEXT REFERENCES sync_outbox(mutation_id) ON DELETE SET NULL,
            last_error_code TEXT,
            last_error_message TEXT,
            last_error_details_json TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY (server_instance_id, account_id, session_id)
                REFERENCES collaboration_bindings(
                    server_instance_id, account_id, session_id
                ) ON DELETE CASCADE
        )",
    )
    .await?;

    execute_v5(
        &mut tx,
        "CREATE INDEX IF NOT EXISTS idx_sync_outbox_flush
         ON sync_outbox(
            server_instance_id, account_id, session_id, state,
            next_attempt_at, local_seq
         )",
    )
    .await?;
    execute_v5(
        &mut tx,
        "CREATE INDEX IF NOT EXISTS idx_sync_outbox_entity
         ON sync_outbox(
            server_instance_id, account_id, session_id,
            entity_type, entity_id, local_seq
         )",
    )
    .await?;

    execute_v5(
        &mut tx,
        "CREATE TABLE IF NOT EXISTS applied_events (
            server_instance_id TEXT NOT NULL,
            account_id TEXT NOT NULL,
            session_id TEXT NOT NULL,
            event_id TEXT NOT NULL,
            event_seq INTEGER NOT NULL CHECK (event_seq >= 1),
            mutation_id TEXT,
            applied_at TEXT NOT NULL,
            PRIMARY KEY (server_instance_id, account_id, session_id, event_id),
            UNIQUE (server_instance_id, account_id, session_id, event_seq),
            FOREIGN KEY (server_instance_id, account_id, session_id)
                REFERENCES collaboration_bindings(
                    server_instance_id, account_id, session_id
                ) ON DELETE CASCADE
        )",
    )
    .await?;
    execute_v5(
        &mut tx,
        "CREATE INDEX IF NOT EXISTS idx_applied_events_mutation
         ON applied_events(
            server_instance_id, account_id, session_id, mutation_id
         )",
    )
    .await?;

    execute_v5(
        &mut tx,
        "CREATE TABLE IF NOT EXISTS sync_conflicts (
            conflict_id TEXT PRIMARY KEY,
            server_instance_id TEXT NOT NULL,
            account_id TEXT NOT NULL,
            session_id TEXT NOT NULL,
            entity_type TEXT NOT NULL CHECK (entity_type IN ('session', 'log')),
            entity_id TEXT NOT NULL,
            mutation_id TEXT NOT NULL,
            base_version INTEGER NOT NULL CHECK (base_version >= 0),
            remote_version INTEGER NOT NULL CHECK (remote_version >= 1),
            base_json TEXT,
            local_json TEXT NOT NULL,
            remote_json TEXT NOT NULL,
            conflicting_fields_json TEXT NOT NULL,
            state TEXT NOT NULL DEFAULT 'open' CHECK (state IN ('open', 'resolving', 'resolved')),
            resolution_mutation_id TEXT,
            created_at TEXT NOT NULL,
            resolved_at TEXT,
            UNIQUE (server_instance_id, account_id, session_id, mutation_id),
            FOREIGN KEY (server_instance_id, account_id, session_id)
                REFERENCES collaboration_bindings(
                    server_instance_id, account_id, session_id
                ) ON DELETE CASCADE,
            FOREIGN KEY (mutation_id) REFERENCES sync_outbox(mutation_id) ON DELETE CASCADE
        )",
    )
    .await?;
    execute_v5(
        &mut tx,
        "CREATE INDEX IF NOT EXISTS idx_sync_conflicts_open
         ON sync_conflicts(
            server_instance_id, account_id, session_id, state, created_at
         )",
    )
    .await?;

    tx.commit().await?;
    Ok(())
}

async fn migrate_v6(pool: &SqlitePool) -> anyhow::Result<()> {
    let mut tx = pool.begin().await?;

    sqlx::query(
        "CREATE TABLE IF NOT EXISTS collaboration_live_drafts (
            server_instance_id TEXT NOT NULL,
            account_id TEXT NOT NULL,
            session_id TEXT NOT NULL,
            draft_id TEXT NOT NULL,
            draft_version INTEGER NOT NULL CHECK (draft_version >= 1),
            remote_json TEXT NOT NULL CHECK (json_valid(remote_json)),
            local_fields_json TEXT NOT NULL CHECK (
                json_valid(local_fields_json) AND json_type(local_fields_json) = 'object'
            ),
            field_revisions_json TEXT NOT NULL CHECK (
                json_valid(field_revisions_json) AND json_type(field_revisions_json) = 'object'
            ),
            dirty_fields_json TEXT NOT NULL DEFAULT '[]' CHECK (
                json_valid(dirty_fields_json) AND json_type(dirty_fields_json) = 'array'
            ),
            client_seq INTEGER NOT NULL DEFAULT 0 CHECK (client_seq >= 0),
            remote_updated_at TEXT,
            local_updated_at TEXT NOT NULL,
            PRIMARY KEY (server_instance_id, account_id, session_id),
            FOREIGN KEY (server_instance_id, account_id, session_id)
                REFERENCES collaboration_bindings(
                    server_instance_id, account_id, session_id
                ) ON DELETE CASCADE
        )",
    )
    .execute(&mut *tx)
    .await?;

    sqlx::query(
        "CREATE TABLE IF NOT EXISTS collaboration_offline_records (
            mutation_id TEXT PRIMARY KEY,
            server_instance_id TEXT NOT NULL,
            account_id TEXT NOT NULL,
            session_id TEXT NOT NULL,
            draft_id TEXT NOT NULL,
            expected_draft_version INTEGER NOT NULL CHECK (expected_draft_version >= 1),
            provisional_ordinal INTEGER NOT NULL CHECK (provisional_ordinal >= 1),
            record_json TEXT NOT NULL CHECK (
                json_valid(record_json) AND json_type(record_json) = 'object'
            ),
            state TEXT NOT NULL CHECK (
                state IN ('pending', 'submitting', 'reviewing', 'resolved', 'discarded')
            ),
            resolution TEXT CHECK (
                resolution IS NULL OR
                resolution IN ('discard', 'submitAsDuplicate', 'copyToCurrentDraft')
            ),
            last_error_code TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY (server_instance_id, account_id, session_id)
                REFERENCES collaboration_bindings(
                    server_instance_id, account_id, session_id
                ) ON DELETE CASCADE
        )",
    )
    .execute(&mut *tx)
    .await?;

    sqlx::query(
        "CREATE INDEX IF NOT EXISTS idx_collaboration_offline_records_state
         ON collaboration_offline_records(
            server_instance_id, account_id, session_id, state, created_at, mutation_id
         )",
    )
    .execute(&mut *tx)
    .await?;

    tx.commit().await?;
    Ok(())
}

async fn migrate_v7(pool: &SqlitePool) -> anyhow::Result<()> {
    let mut tx = pool.begin().await?;

    let columns = sqlx::query_as::<_, (i64, String, String, i64, Option<String>, i64)>(
        "PRAGMA table_info(dictionary_items)",
    )
    .fetch_all(&mut *tx)
    .await?;
    if !columns.iter().any(|column| column.1 == "origin") {
        sqlx::query(
            "ALTER TABLE dictionary_items
             ADD COLUMN origin TEXT NOT NULL DEFAULT 'unknown'
             CHECK (origin IN ('unknown', 'builtin', 'user'))",
        )
        .execute(&mut *tx)
        .await?;
    }

    sqlx::query("DROP INDEX IF EXISTS idx_callsign_qth_callsign")
        .execute(&mut *tx)
        .await?;
    sqlx::query("DROP TABLE IF EXISTS callsign_qth_history")
        .execute(&mut *tx)
        .await?;

    sqlx::query(
        "CREATE TABLE IF NOT EXISTS personal_cloud_baselines (
            scope_hash TEXT NOT NULL CHECK (
                length(scope_hash) = 64 AND scope_hash NOT GLOB '*[^0-9a-f]*'
            ),
            dataset TEXT NOT NULL CHECK (dataset IN ('records', 'dictionaries')),
            remote_revision INTEGER NOT NULL CHECK (remote_revision >= 0),
            snapshot_json TEXT NOT NULL CHECK (
                json_valid(snapshot_json) AND json_type(snapshot_json) = 'object'
            ),
            checksum TEXT NOT NULL CHECK (
                length(checksum) = 64 AND checksum NOT GLOB '*[^0-9a-f]*'
            ),
            updated_at TEXT NOT NULL,
            PRIMARY KEY (scope_hash, dataset)
        )",
    )
    .execute(&mut *tx)
    .await?;

    sqlx::query(
        "CREATE TABLE IF NOT EXISTS personal_cloud_state (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            owner_scope_hash TEXT CHECK (
                owner_scope_hash IS NULL OR
                (length(owner_scope_hash) = 64 AND owner_scope_hash NOT GLOB '*[^0-9a-f]*')
            ),
            pairing_required_reason TEXT CHECK (
                pairing_required_reason IS NULL OR
                pairing_required_reason IN ('database_replaced', 'local_cleared', 'account_changed')
            ),
            updated_at TEXT NOT NULL
        )",
    )
    .execute(&mut *tx)
    .await?;
    sqlx::query(
        "INSERT OR IGNORE INTO personal_cloud_state (
            id, owner_scope_hash, pairing_required_reason, updated_at
         ) VALUES (1, NULL, NULL, ?)",
    )
    .bind(chrono::Utc::now().to_rfc3339())
    .execute(&mut *tx)
    .await?;

    tx.commit().await?;
    Ok(())
}
