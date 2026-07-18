use openlogtool_core::api::database::{
    clear_all_data, export_database, get_database_status, import_database,
};
use openlogtool_core::db::collaboration;
use openlogtool_core::models::collaboration::{
    CollaborationRole, CollaborationSnapshot, InstallSnapshotRequest, RemoteLog, RemoteMembership,
    RemoteSession, SnapshotInstallMode,
};
use openlogtool_core::{get_db, init_database};
use serde_json::json;
use sqlx::SqlitePool;

const NOW: &str = "2026-07-11T08:00:00Z";

fn snapshot_request() -> InstallSnapshotRequest {
    InstallSnapshotRequest {
        mode: SnapshotInstallMode::Join,
        server_instance_id: "backup-server".to_string(),
        server_origin: "https://backup.example".to_string(),
        account_id: "backup-account".to_string(),
        membership: RemoteMembership {
            membership_id: "backup-membership".to_string(),
            session_id: "remote-before-import".to_string(),
            user_id: "backup-account".to_string(),
            role: CollaborationRole::Viewer,
            version: 1,
            joined_at: NOW.to_string(),
            updated_at: NOW.to_string(),
            removed_at: None,
        },
        snapshot: CollaborationSnapshot {
            protocol_version: 1,
            includes_deleted_logs: true,
            session: RemoteSession {
                session_id: "remote-before-import".to_string(),
                title: "Remote before import".to_string(),
                status: "active".to_string(),
                version: 1,
                role: CollaborationRole::Viewer,
                high_watermark_seq: 4,
                created_at: NOW.to_string(),
                updated_at: NOW.to_string(),
                closed_at: None,
                deleted_at: None,
            },
            high_watermark_seq: 4,
            logs: vec![RemoteLog {
                sync_id: "remote-log".to_string(),
                session_id: "remote-before-import".to_string(),
                version: 1,
                time: NOW.to_string(),
                controller: "BG5CRL".to_string(),
                callsign: "BA4AAA".to_string(),
                rst_sent: Some("59".to_string()),
                rst_rcvd: Some("57".to_string()),
                qth: None,
                device: None,
                power: None,
                antenna: None,
                height: None,
                remarks: Some("backup remarks".to_string()),
                created_at: NOW.to_string(),
                updated_at: NOW.to_string(),
                deleted_at: None,
            }],
        },
    }
}

async fn assert_import_failure_preserves_collaboration_replica(
    pool: &SqlitePool,
    backup: serde_json::Value,
    expected_error: &str,
) {
    let error = import_database(backup.to_string())
        .await
        .unwrap_err()
        .to_string();
    assert!(
        error.contains(expected_error),
        "expected {expected_error:?} in import error, got {error:?}"
    );

    let preserved: (i64, i64, Option<String>) = sqlx::query_as(
        "SELECT
            (SELECT COUNT(*) FROM sessions WHERE session_id = 'remote-before-import'),
            (SELECT COUNT(*) FROM collaboration_bindings),
            (SELECT remarks FROM logs WHERE sync_id = 'remote-log')",
    )
    .fetch_one(pool)
    .await
    .unwrap();
    assert_eq!(
        preserved,
        (1, 1, Some("backup remarks".to_string())),
        "a rejected backup must leave the original replica untouched"
    );
}

#[tokio::test]
async fn backup_replacement_is_atomic_offline_capable_and_preserves_device_identity() {
    let database_path = std::env::temp_dir().join(format!(
        "openlogtool-collaboration-backup-{}.db",
        uuid::Uuid::new_v4()
    ));
    init_database(database_path.to_str().unwrap())
        .await
        .unwrap();
    let pool = get_db().unwrap();
    let device_before = collaboration::get_or_create_device_id(pool).await.unwrap();
    collaboration::install_snapshot(pool, snapshot_request())
        .await
        .unwrap();
    let status: serde_json::Value =
        serde_json::from_str(&get_database_status().await.unwrap()).unwrap();
    assert_eq!(status["schemaVersion"], 7);
    assert!(status["tables"]
        .as_array()
        .unwrap()
        .iter()
        .any(|table| table["name"] == "sessions" && table["rowCount"] == 1));
    let shadow: (String,) = sqlx::query_as(
        "SELECT server_json FROM entity_shadows
         WHERE session_id = 'remote-before-import' AND entity_type = 'log'",
    )
    .fetch_one(pool)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO sync_outbox (
            server_instance_id, account_id, session_id, mutation_id,
            entity_type, entity_id, operation, base_version, observed_seq,
            base_json, payload_json, state, attempts, created_at, updated_at
         ) VALUES (
            'backup-server', 'backup-account', 'remote-before-import',
            '00000000-0000-4000-8000-000000000001', 'log', 'remote-log',
            'update', 1, 4, ?, '{\"patch\":{\"remarks\":\"pending\"}}',
            'conflict', 1, ?, ?
         )",
    )
    .bind(&shadow.0)
    .bind(NOW)
    .bind(NOW)
    .execute(pool)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO sync_outbox (
            server_instance_id, account_id, session_id, mutation_id,
            entity_type, entity_id, operation, base_version, observed_seq,
            base_json, payload_json, state, attempts,
            depends_on_mutation_id, created_at, updated_at
         ) VALUES (
            'backup-server', 'backup-account', 'remote-before-import',
            '00000000-0000-4000-8000-000000000005', 'log', 'remote-log',
            'update', 1, 4, ?, '{\"patch\":{\"remarks\":\"dependent\"}}',
            'pending', 0, '00000000-0000-4000-8000-000000000001', ?, ?
         )",
    )
    .bind(&shadow.0)
    .bind(NOW)
    .bind(NOW)
    .execute(pool)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO applied_events (
            server_instance_id, account_id, session_id, event_id,
            event_seq, mutation_id, applied_at
         ) VALUES (
            'backup-server', 'backup-account', 'remote-before-import',
            '00000000-0000-4000-8000-000000000002', 1, NULL, ?
         )",
    )
    .bind(NOW)
    .execute(pool)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO sync_conflicts (
            conflict_id, server_instance_id, account_id, session_id,
            entity_type, entity_id, mutation_id, base_version, remote_version,
            base_json, local_json, remote_json, conflicting_fields_json,
            state, created_at
         ) VALUES (
            '00000000-0000-4000-8000-000000000003',
            'backup-server', 'backup-account', 'remote-before-import',
            'log', 'remote-log', '00000000-0000-4000-8000-000000000001',
            1, 2, ?, ?, ?, '[\"remarks\"]', 'open', ?
         )",
    )
    .bind(&shadow.0)
    .bind(&shadow.0)
    .bind(&shadow.0)
    .bind(NOW)
    .execute(pool)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO collaboration_live_drafts (
            server_instance_id, account_id, session_id, draft_id, draft_version,
            remote_json, local_fields_json, field_revisions_json, dirty_fields_json,
            client_seq, remote_updated_at, local_updated_at
         ) VALUES (
            'backup-server', 'backup-account', 'remote-before-import',
            'draft-before-import', 3,
            '{\"draftId\":\"draft-before-import\",\"version\":3}',
            '{\"callsign\":\"BA4BBB\"}', '{\"callsign\":2}',
            '[\"callsign\"]', 7, ?, ?
         )",
    )
    .bind(NOW)
    .bind(NOW)
    .execute(pool)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO collaboration_offline_records (
            mutation_id, server_instance_id, account_id, session_id,
            draft_id, expected_draft_version, provisional_ordinal, record_json,
            state, resolution, last_error_code, created_at, updated_at
         ) VALUES (
            '00000000-0000-4000-8000-000000000004',
            'backup-server', 'backup-account', 'remote-before-import',
            'draft-before-import', 3, 2,
            '{\"callsign\":\"BA4CCC\",\"controller\":\"BG5CRL\"}',
            'reviewing', NULL, 'LIVE_DRAFT_VERSION_CONFLICT', ?, ?
         )",
    )
    .bind(NOW)
    .bind(NOW)
    .execute(pool)
    .await
    .unwrap();

    let mut exported: serde_json::Value =
        serde_json::from_str(&export_database().await.unwrap()).unwrap();
    assert_eq!(exported["version"], 7);
    assert_eq!(
        exported["collaboration_bindings"].as_array().unwrap().len(),
        1
    );
    assert_eq!(exported["entity_shadows"].as_array().unwrap().len(), 2);
    assert_eq!(exported["sync_outbox"].as_array().unwrap().len(), 2);
    assert_eq!(exported["applied_events"].as_array().unwrap().len(), 1);
    assert_eq!(exported["sync_conflicts"].as_array().unwrap().len(), 1);
    assert_eq!(
        exported["collaboration_live_drafts"]
            .as_array()
            .unwrap()
            .len(),
        1
    );
    assert_eq!(
        exported["collaboration_offline_records"]
            .as_array()
            .unwrap()
            .len(),
        1
    );
    assert!(exported.get("device_state").is_none());

    // A corrupted TEXT value must make export fail. Silently turning a decode
    // error into JSON null would produce a backup that looks successful but
    // cannot faithfully restore the database.
    sqlx::query(
        "INSERT INTO settings (key, value)
         VALUES ('malformed-export-value', CAST(X'80' AS TEXT))",
    )
    .execute(pool)
    .await
    .unwrap();
    let export_decode_error = export_database().await.unwrap_err().to_string();
    assert!(export_decode_error.contains("DATABASE_BACKUP_EXPORT_UNREADABLE_COLUMN:value:TEXT"));
    sqlx::query("DELETE FROM settings WHERE key = 'malformed-export-value'")
        .execute(pool)
        .await
        .unwrap();

    // Backups are relational data, not an insertion-order protocol. Put the
    // dependent outbox row first to prove import defers foreign-key checks.
    exported["sync_outbox"].as_array_mut().unwrap().reverse();
    assert_eq!(
        exported["sync_outbox"][0]["depends_on_mutation_id"],
        "00000000-0000-4000-8000-000000000001"
    );

    let invalid_error = import_database(r#"{"version":4}"#.to_string())
        .await
        .unwrap_err()
        .to_string();
    assert!(invalid_error.contains("DATABASE_BACKUP_INVALID_TABLE"));
    let future_error = import_database(r#"{"version":8}"#.to_string())
        .await
        .unwrap_err()
        .to_string();
    assert!(future_error.contains("DATABASE_BACKUP_UNSUPPORTED_VERSION"));
    let preserved_after_invalid: (i64,) =
        sqlx::query_as("SELECT COUNT(*) FROM sessions WHERE session_id = 'remote-before-import'")
            .fetch_one(pool)
            .await
            .unwrap();
    assert_eq!(preserved_after_invalid.0, 1);

    let mut unknown_column = exported.clone();
    unknown_column["logs"][0]["callsign); DELETE FROM sessions; --"] = json!("injected");
    let unknown_column_error = import_database(unknown_column.to_string())
        .await
        .unwrap_err()
        .to_string();
    assert!(unknown_column_error.contains("DATABASE_BACKUP_UNKNOWN_COLUMN:logs."));
    let preserved_after_unknown_column: (i64, i64) = sqlx::query_as(
        "SELECT (SELECT COUNT(*) FROM sessions WHERE session_id = 'remote-before-import'), \
                (SELECT COUNT(*) FROM collaboration_bindings)",
    )
    .fetch_one(pool)
    .await
    .unwrap();
    assert_eq!(preserved_after_unknown_column, (1, 1));

    // This backup passes structural validation, then fails after the import
    // transaction has already deleted and reinserted some tables. The original
    // collaboration replica must still be present after the rollback.
    let mut invalid_row = exported.clone();
    invalid_row["logs"][0]["callsign"] = serde_json::Value::Null;
    let invalid_row_error = import_database(invalid_row.to_string())
        .await
        .unwrap_err()
        .to_string();
    assert!(invalid_row_error.contains("NOT NULL constraint failed"));
    let preserved_after_rolled_back_insert: (i64, i64, Option<String>) = sqlx::query_as(
        "SELECT
            (SELECT COUNT(*) FROM sessions WHERE session_id = 'remote-before-import'),
            (SELECT COUNT(*) FROM collaboration_bindings),
            (SELECT remarks FROM logs WHERE sync_id = 'remote-log')",
    )
    .fetch_one(pool)
    .await
    .unwrap();
    assert_eq!(
        preserved_after_rolled_back_insert,
        (1, 1, Some("backup remarks".to_string()))
    );

    let mut invalid_json_column = exported.clone();
    invalid_json_column["sync_outbox"][0]["last_error_details_json"] = json!("{broken");
    let invalid_json_error = import_database(invalid_json_column.to_string())
        .await
        .unwrap_err()
        .to_string();
    assert!(invalid_json_error
        .contains("DATABASE_BACKUP_INVALID_JSON_COLUMN:sync_outbox.last_error_details_json"));

    let mut empty_identifier = exported.clone();
    empty_identifier["logs"][0]["sync_id"] = json!("   ");
    assert_import_failure_preserves_collaboration_replica(
        pool,
        empty_identifier,
        "DATABASE_BACKUP_EMPTY_IDENTIFIER:logs.sync_id",
    )
    .await;

    let mut empty_required_log_value = exported.clone();
    empty_required_log_value["logs"][0]["callsign"] = json!("\n");
    assert_import_failure_preserves_collaboration_replica(
        pool,
        empty_required_log_value,
        "DATABASE_BACKUP_EMPTY_REQUIRED_VALUE:logs.callsign",
    )
    .await;

    let mut empty_session_title = exported.clone();
    empty_session_title["sessions"][0]["title"] = json!("  ");
    assert_import_failure_preserves_collaboration_replica(
        pool,
        empty_session_title,
        "DATABASE_BACKUP_EMPTY_REQUIRED_VALUE:sessions.title",
    )
    .await;

    let mut invalid_dictionary_type = exported.clone();
    invalid_dictionary_type["dictionary_items"] = json!([{
        "id": 9001,
        "dict_type": "ghost_dictionary",
        "raw": "invisible item",
        "pinyin": null,
        "abbreviation": null,
        "sync_id": "dict-invalid-type",
        "created_at": NOW,
        "updated_at": NOW,
        "deleted_at": null
    }]);
    assert_import_failure_preserves_collaboration_replica(
        pool,
        invalid_dictionary_type,
        "DATABASE_BACKUP_INVALID_DICTIONARY_TYPE",
    )
    .await;

    let mut empty_collaboration_identifier = exported.clone();
    empty_collaboration_identifier["collaboration_bindings"][0]["account_id"] = json!("\t");
    assert_import_failure_preserves_collaboration_replica(
        pool,
        empty_collaboration_identifier,
        "DATABASE_BACKUP_EMPTY_IDENTIFIER:collaboration_bindings.account_id",
    )
    .await;

    let mut invalid_session_timestamp = exported.clone();
    invalid_session_timestamp["sessions"][0]["created_at"] = json!("not-rfc3339");
    assert_import_failure_preserves_collaboration_replica(
        pool,
        invalid_session_timestamp,
        "DATABASE_BACKUP_INVALID_TIMESTAMP:sessions.created_at",
    )
    .await;

    let mut invalid_log_timestamp = exported.clone();
    invalid_log_timestamp["logs"][0]["updated_at"] = json!("2026-07-11 08:00:00");
    assert_import_failure_preserves_collaboration_replica(
        pool,
        invalid_log_timestamp,
        "DATABASE_BACKUP_INVALID_TIMESTAMP:logs.updated_at",
    )
    .await;

    let mut invalid_log_time = exported.clone();
    invalid_log_time["logs"][0]["time"] = json!("24:00");
    assert_import_failure_preserves_collaboration_replica(
        pool,
        invalid_log_time,
        "DATABASE_BACKUP_INVALID_LOG_TIME:logs.time",
    )
    .await;

    let mut invalid_collaboration_timestamp = exported.clone();
    invalid_collaboration_timestamp["collaboration_bindings"][0]["joined_at"] = json!("yesterday");
    assert_import_failure_preserves_collaboration_replica(
        pool,
        invalid_collaboration_timestamp,
        "DATABASE_BACKUP_INVALID_TIMESTAMP:collaboration_bindings.joined_at",
    )
    .await;

    let mut invalid_optional_timestamp = exported.clone();
    invalid_optional_timestamp["sessions"][0]["closed_at"] = json!("tomorrow");
    assert_import_failure_preserves_collaboration_replica(
        pool,
        invalid_optional_timestamp,
        "DATABASE_BACKUP_INVALID_TIMESTAMP:sessions.closed_at",
    )
    .await;

    let legacy_v3 = json!({
        "version": 3,
        "exportedAt": NOW,
        "sessions": [{
            "session_id": "legacy-local",
            "title": "Legacy local backup",
            "status": "active",
            "share_code": null,
            "created_at": NOW,
            "updated_at": NOW,
            "closed_at": null,
            "deleted_at": null
        }],
        "logs": [{
            "sync_id": "legacy-log",
            "session_id": "legacy-local",
            "time": "20:00",
            "controller": "BG5CRL",
            "callsign": "BA4AAA",
            "rst_sent": "59",
            "rst_rcvd": "57",
            "qth": null,
            "device": null,
            "power": null,
            "antenna": null,
            "height": null,
            "remarks": "legacy remarks",
            "created_at": NOW,
            "updated_at": NOW,
            "deleted_at": null,
            "source_device_id": null
        }],
        "dictionary_items": [],
        "settings": [],
        "oplog": [],
        "callsign_qth_history": []
    });

    // SQLite permits NULL in a non-INTEGER PRIMARY KEY, even though every
    // typed reader expects a String. Reject such a backup before commit so it
    // cannot leave the app with a database that only fails on the next read.
    let mut unreadable_session = legacy_v3.clone();
    unreadable_session["sessions"][0]["session_id"] = serde_json::Value::Null;
    let unreadable_session_error = import_database(unreadable_session.to_string())
        .await
        .unwrap_err()
        .to_string();
    assert!(unreadable_session_error
        .contains("DATABASE_BACKUP_UNREADABLE_COLUMN:sessions.session_id:text"));

    // sync_id was nullable in the original table definition but current Rust
    // models require it. Validation must catch the mismatch transactionally.
    let mut unreadable_dictionary = legacy_v3.clone();
    unreadable_dictionary["dictionary_items"] = json!([{
        "dict_type": "device_dictionary",
        "raw": "Unreadable radio",
        "pinyin": null,
        "abbreviation": null,
        "sync_id": null,
        "created_at": NOW,
        "updated_at": NOW,
        "deleted_at": null
    }]);
    let unreadable_dictionary_error = import_database(unreadable_dictionary.to_string())
        .await
        .unwrap_err()
        .to_string();
    assert!(unreadable_dictionary_error
        .contains("DATABASE_BACKUP_UNREADABLE_COLUMN:dictionary_items.sync_id:text"));

    let preserved_after_unreadable_rows: (i64, i64, Option<String>) = sqlx::query_as(
        "SELECT
            (SELECT COUNT(*) FROM sessions WHERE session_id = 'remote-before-import'),
            (SELECT COUNT(*) FROM collaboration_bindings),
            (SELECT remarks FROM logs WHERE sync_id = 'remote-log')",
    )
    .fetch_one(pool)
    .await
    .unwrap();
    assert_eq!(
        preserved_after_unreadable_rows,
        (1, 1, Some("backup remarks".to_string()))
    );

    // Replacing a bound replica is a local database operation. It must work
    // without contacting the collaboration server, and a legacy backup has no
    // replica metadata so the restored session is local-only.
    import_database(legacy_v3.to_string()).await.unwrap();
    let legacy_after_bound_import: (i64, i64, Option<String>) = sqlx::query_as(
        "SELECT
            (SELECT COUNT(*) FROM sessions WHERE session_id = 'legacy-local'),
            (SELECT COUNT(*) FROM collaboration_bindings),
            (SELECT remarks FROM logs WHERE sync_id = 'legacy-log')",
    )
    .fetch_one(pool)
    .await
    .unwrap();
    assert_eq!(
        legacy_after_bound_import,
        (1, 0, Some("legacy remarks".to_string()))
    );

    import_database(exported.to_string()).await.unwrap();
    let roundtrip_bindings: (i64,) = sqlx::query_as("SELECT COUNT(*) FROM collaboration_bindings")
        .fetch_one(pool)
        .await
        .unwrap();
    let roundtrip_shadows: (i64,) = sqlx::query_as("SELECT COUNT(*) FROM entity_shadows")
        .fetch_one(pool)
        .await
        .unwrap();
    let roundtrip_remarks: (Option<String>,) =
        sqlx::query_as("SELECT remarks FROM logs WHERE sync_id = 'remote-log'")
            .fetch_one(pool)
            .await
            .unwrap();
    let roundtrip_sync: (i64, i64, i64, i64, i64) = sqlx::query_as(
        "SELECT
            (SELECT COUNT(*) FROM sync_outbox),
            (SELECT COUNT(*) FROM applied_events),
            (SELECT COUNT(*) FROM sync_conflicts),
            (SELECT COUNT(*) FROM collaboration_live_drafts),
            (SELECT COUNT(*) FROM collaboration_offline_records)",
    )
    .fetch_one(pool)
    .await
    .unwrap();
    assert_eq!(roundtrip_bindings.0, 1);
    assert_eq!(roundtrip_shadows.0, 2);
    assert_eq!(roundtrip_sync, (2, 1, 1, 1, 1));
    assert_eq!(roundtrip_remarks.0.as_deref(), Some("backup remarks"));

    // A full local reset also works for a bound replica and removes its
    // pending queues, while keeping this installation's device identity.
    clear_all_data().await.unwrap();
    let cleared: (i64, i64, i64, i64) = sqlx::query_as(
        "SELECT
            (SELECT COUNT(*) FROM sessions),
            (SELECT COUNT(*) FROM logs),
            (SELECT COUNT(*) FROM collaboration_bindings),
            (SELECT COUNT(*) FROM sync_outbox)",
    )
    .fetch_one(pool)
    .await
    .unwrap();
    assert_eq!(cleared, (0, 0, 0, 0));
    let device_after_clear = collaboration::get_or_create_device_id(pool).await.unwrap();
    assert_eq!(device_before, device_after_clear);

    import_database(legacy_v3.to_string()).await.unwrap();

    let bindings: (i64,) = sqlx::query_as("SELECT COUNT(*) FROM collaboration_bindings")
        .fetch_one(pool)
        .await
        .unwrap();
    let shadows: (i64,) = sqlx::query_as("SELECT COUNT(*) FROM entity_shadows")
        .fetch_one(pool)
        .await
        .unwrap();
    let legacy_session: (i64,) =
        sqlx::query_as("SELECT COUNT(*) FROM sessions WHERE session_id = 'legacy-local'")
            .fetch_one(pool)
            .await
            .unwrap();
    let legacy_remarks: (Option<String>,) =
        sqlx::query_as("SELECT remarks FROM logs WHERE sync_id = 'legacy-log'")
            .fetch_one(pool)
            .await
            .unwrap();
    let device_after = collaboration::get_or_create_device_id(pool).await.unwrap();
    assert_eq!(bindings.0, 0);
    assert_eq!(shadows.0, 0);
    assert_eq!(legacy_session.0, 1);
    assert_eq!(legacy_remarks.0.as_deref(), Some("legacy remarks"));
    assert_eq!(device_before, device_after);

    pool.close().await;
    let _ = std::fs::remove_file(database_path);
}
