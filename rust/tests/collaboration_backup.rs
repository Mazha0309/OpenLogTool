use openlogtool_core::api::database::{clear_all_data, export_database, import_database};
use openlogtool_core::db::collaboration;
use openlogtool_core::models::collaboration::{
    CollaborationRole, CollaborationSnapshot, InstallSnapshotRequest, RemoteLog, RemoteMembership,
    RemoteSession, SnapshotInstallMode,
};
use openlogtool_core::{get_db, init_database};
use serde_json::json;

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

#[tokio::test]
async fn v5_export_preserves_replica_metadata_and_v3_import_becomes_local_only() {
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

    let exported: serde_json::Value =
        serde_json::from_str(&export_database().await.unwrap()).unwrap();
    assert_eq!(exported["version"], 5);
    assert_eq!(
        exported["collaboration_bindings"].as_array().unwrap().len(),
        1
    );
    assert_eq!(exported["entity_shadows"].as_array().unwrap().len(), 2);
    assert_eq!(exported["sync_outbox"].as_array().unwrap().len(), 1);
    assert_eq!(exported["applied_events"].as_array().unwrap().len(), 1);
    assert_eq!(exported["sync_conflicts"].as_array().unwrap().len(), 1);
    assert!(exported.get("device_state").is_none());

    let invalid_error = import_database(r#"{"version":4}"#.to_string())
        .await
        .unwrap_err()
        .to_string();
    assert!(invalid_error.contains("数据库备份缺少有效表"));
    let future_error = import_database(r#"{"version":6}"#.to_string())
        .await
        .unwrap_err()
        .to_string();
    assert!(future_error.contains("不支持的数据库备份版本"));
    let preserved_after_invalid: (i64,) =
        sqlx::query_as("SELECT COUNT(*) FROM sessions WHERE session_id = 'remote-before-import'")
            .fetch_one(pool)
            .await
            .unwrap();
    assert_eq!(preserved_after_invalid.0, 1);

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
            "time": NOW,
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
    let protected_error = import_database(legacy_v3.to_string())
        .await
        .unwrap_err()
        .to_string();
    assert!(protected_error.contains("COLLABORATION_SESSION_READ_ONLY"));

    let clear_error = clear_all_data().await.unwrap_err().to_string();
    assert!(clear_error.contains("COLLABORATION_SESSION_READ_ONLY"));
    let preserved_after_clear: (i64, i64) = sqlx::query_as(
        "SELECT (SELECT COUNT(*) FROM sessions WHERE session_id = 'remote-before-import'), \
                (SELECT COUNT(*) FROM collaboration_bindings)",
    )
    .fetch_one(pool)
    .await
    .unwrap();
    assert_eq!(preserved_after_clear, (1, 1));

    sqlx::query("DELETE FROM entity_shadows")
        .execute(pool)
        .await
        .unwrap();
    sqlx::query("DELETE FROM collaboration_bindings")
        .execute(pool)
        .await
        .unwrap();
    clear_all_data().await.unwrap();
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
    let roundtrip_sync: (i64, i64, i64) = sqlx::query_as(
        "SELECT
            (SELECT COUNT(*) FROM sync_outbox),
            (SELECT COUNT(*) FROM applied_events),
            (SELECT COUNT(*) FROM sync_conflicts)",
    )
    .fetch_one(pool)
    .await
    .unwrap();
    assert_eq!(roundtrip_bindings.0, 1);
    assert_eq!(roundtrip_shadows.0, 2);
    assert_eq!(roundtrip_sync, (1, 1, 1));
    assert_eq!(roundtrip_remarks.0.as_deref(), Some("backup remarks"));

    sqlx::query("DELETE FROM entity_shadows")
        .execute(pool)
        .await
        .unwrap();
    sqlx::query("DELETE FROM collaboration_bindings")
        .execute(pool)
        .await
        .unwrap();
    clear_all_data().await.unwrap();
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
