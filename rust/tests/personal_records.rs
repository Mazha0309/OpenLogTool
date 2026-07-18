use openlogtool_core::api::personal_records::{
    export_personal_records, merge_personal_records, replace_personal_records,
    replace_personal_records_if_unchanged,
};
use openlogtool_core::{get_db, init_database};
use serde_json::{json, Value};

const CREATED: &str = "2026-07-18T08:00:00.000Z";
const UPDATED: &str = "2026-07-18T09:00:00.000Z";

async fn insert_session(session_id: &str, title: &str, share_code: Option<&str>) {
    sqlx::query(
        "INSERT INTO sessions (
            session_id, title, status, share_code, created_at, updated_at, closed_at
         ) VALUES (?, ?, 'closed', ?, ?, ?, ?)",
    )
    .bind(session_id)
    .bind(title)
    .bind(share_code)
    .bind(CREATED)
    .bind(UPDATED)
    .bind(UPDATED)
    .execute(get_db().unwrap())
    .await
    .unwrap();
}

async fn insert_log(session_id: &str, sync_id: &str, remarks: &str, source_device_id: &str) {
    sqlx::query(
        "INSERT INTO logs (
            sync_id, session_id, time, controller, callsign,
            rst_sent, rst_rcvd, qth, device, power, antenna, height, remarks,
            created_at, updated_at, source_device_id
         ) VALUES (?, ?, ?, 'BG5CRL', 'BA4AAA', '59', '57', '杭州',
                   'IC-705', '10W', 'DP', '8m', ?, ?, ?, ?)",
    )
    .bind(sync_id)
    .bind(session_id)
    .bind(CREATED)
    .bind(remarks)
    .bind(CREATED)
    .bind(UPDATED)
    .bind(source_device_id)
    .execute(get_db().unwrap())
    .await
    .unwrap();
}

async fn install_protected_fixture() {
    insert_session("collaboration-session", "Shared", Some("REMOTE")).await;
    insert_log(
        "collaboration-session",
        "collaboration-log",
        "shared remarks",
        "shared-device",
    )
    .await;
    let pool = get_db().unwrap();
    sqlx::query(
        "INSERT INTO collaboration_bindings (
            server_instance_id, server_origin, account_id, session_id,
            membership_id, membership_version, role, replica_state,
            last_applied_seq, last_seen_head_seq, joined_at, updated_at
         ) VALUES (
            'server-1', 'https://server.example', 'account-1',
            'collaboration-session', 'membership-1', 1, 'owner', 'ready',
            5, 5, ?, ?
         )",
    )
    .bind(CREATED)
    .bind(UPDATED)
    .execute(pool)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO sync_outbox (
            server_instance_id, account_id, session_id, mutation_id,
            entity_type, entity_id, operation, base_version, observed_seq,
            base_json, payload_json, state, attempts, created_at, updated_at
         ) VALUES (
            'server-1', 'account-1', 'collaboration-session', 'mutation-1',
            'log', 'collaboration-log', 'update', 1, 5,
            '{\"remarks\":\"base\"}', '{\"patch\":{\"remarks\":\"pending\"}}',
            'conflict', 1, ?, ?
         )",
    )
    .bind(CREATED)
    .bind(UPDATED)
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
            'conflict-1', 'server-1', 'account-1', 'collaboration-session',
            'log', 'collaboration-log', 'mutation-1', 1, 2,
            '{\"remarks\":\"base\"}', '{\"remarks\":\"local\"}',
            '{\"remarks\":\"remote\"}', '[\"remarks\"]', 'open', ?
         )",
    )
    .bind(CREATED)
    .execute(pool)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO dictionary_items (
            dict_type, raw, sync_id, created_at, updated_at
         ) VALUES ('qth_dictionary', '杭州', 'dict-1', ?, ?)",
    )
    .bind(CREATED)
    .bind(UPDATED)
    .execute(pool)
    .await
    .unwrap();
    sqlx::query("INSERT INTO settings (key, value) VALUES ('theme', 'dark')")
        .execute(pool)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO callsign_qth_history (
            sync_id, callsign, qth, recorded_at, created_at, updated_at
         ) VALUES ('qth-1', 'BA4AAA', '杭州', ?, ?, ?)",
    )
    .bind(CREATED)
    .bind(CREATED)
    .bind(UPDATED)
    .execute(pool)
    .await
    .unwrap();
}

async fn protected_state() -> (i64, i64, i64, i64, i64, i64, String) {
    sqlx::query_as(
        "SELECT
            (SELECT COUNT(*) FROM collaboration_bindings),
            (SELECT COUNT(*) FROM sync_outbox),
            (SELECT COUNT(*) FROM sync_conflicts),
            (SELECT COUNT(*) FROM dictionary_items),
            (SELECT COUNT(*) FROM settings),
            (SELECT COUNT(*) FROM callsign_qth_history),
            (SELECT remarks FROM logs WHERE sync_id = 'collaboration-log')",
    )
    .fetch_one(get_db().unwrap())
    .await
    .unwrap()
}

#[tokio::test]
async fn personal_snapshot_replace_and_merge_are_atomic_and_collaboration_safe() {
    let database_path = std::env::temp_dir().join(format!(
        "openlogtool-personal-records-{}.db",
        uuid::Uuid::new_v4()
    ));
    init_database(database_path.to_str().unwrap())
        .await
        .unwrap();
    insert_session("personal-session", "Original title", Some("LOCAL1")).await;
    insert_log(
        "personal-session",
        "personal-log",
        "original remarks",
        "personal-device",
    )
    .await;
    sqlx::query("UPDATE logs SET deleted_at = ? WHERE sync_id = 'personal-log'")
        .bind(UPDATED)
        .execute(get_db().unwrap())
        .await
        .unwrap();
    install_protected_fixture().await;
    let protected_before = protected_state().await;

    let exported: Value = serde_json::from_str(&export_personal_records().await.unwrap()).unwrap();
    assert_eq!(exported["version"], 1);
    assert!(exported["exportedAt"].as_str().unwrap().ends_with('Z'));
    assert_eq!(exported["sessions"].as_array().unwrap().len(), 1);
    assert_eq!(exported["logs"].as_array().unwrap().len(), 1);
    assert_eq!(exported["sessions"][0]["session_id"], "personal-session");
    assert_eq!(exported["logs"][0]["sync_id"], "personal-log");
    assert_eq!(exported["logs"][0]["source_device_id"], "personal-device");
    assert_eq!(exported["logs"][0]["deleted_at"], UPDATED);
    assert!(exported["sessions"][0].get("share_code").is_none());
    assert!(exported["logs"][0].get("id").is_none());
    assert!(!exported.to_string().contains("collaboration-session"));

    insert_session("local-extra", "Keep during merge", Some("LOCAL2")).await;
    insert_log("local-extra", "local-extra-log", "extra", "extra-device").await;
    let mut incoming = exported.clone();
    incoming["sessions"][0]["title"] = json!("Cloud title");
    incoming["logs"][0]["remarks"] = json!("cloud remarks");
    let merged: Value =
        serde_json::from_str(&merge_personal_records(incoming.to_string()).await.unwrap()).unwrap();
    assert_eq!(merged, json!({"sessionCount": 1, "logCount": 1}));
    let after_merge: (String, Option<String>, String, i64) = sqlx::query_as(
        "SELECT
            (SELECT title FROM sessions WHERE session_id = 'personal-session'),
            (SELECT share_code FROM sessions WHERE session_id = 'personal-session'),
            (SELECT remarks FROM logs WHERE sync_id = 'personal-log'),
            (SELECT COUNT(*) FROM sessions WHERE session_id = 'local-extra')",
    )
    .fetch_one(get_db().unwrap())
    .await
    .unwrap();
    assert_eq!(
        after_merge,
        (
            "Cloud title".to_string(),
            Some("LOCAL1".to_string()),
            "cloud remarks".to_string(),
            1
        )
    );
    assert_eq!(protected_state().await, protected_before);

    let replaced: Value = serde_json::from_str(
        &replace_personal_records(incoming.to_string())
            .await
            .unwrap(),
    )
    .unwrap();
    assert_eq!(replaced, json!({"sessionCount": 1, "logCount": 1}));
    let after_replace: (
        i64,
        i64,
        Option<String>,
        String,
        String,
        String,
        String,
        String,
        Option<String>,
        Option<String>,
    ) = sqlx::query_as(
        "SELECT
            (SELECT COUNT(*) FROM sessions WHERE session_id = 'local-extra'),
            (SELECT COUNT(*) FROM logs WHERE sync_id = 'local-extra-log'),
            (SELECT share_code FROM sessions WHERE session_id = 'personal-session'),
            (SELECT created_at FROM sessions WHERE session_id = 'personal-session'),
            (SELECT status FROM sessions WHERE session_id = 'personal-session'),
            (SELECT closed_at FROM sessions WHERE session_id = 'personal-session'),
            (SELECT updated_at FROM logs WHERE sync_id = 'personal-log'),
            (SELECT source_device_id FROM logs WHERE sync_id = 'personal-log'),
            (SELECT deleted_at FROM logs WHERE sync_id = 'personal-log'),
            (SELECT qth FROM logs WHERE sync_id = 'personal-log')",
    )
    .fetch_one(get_db().unwrap())
    .await
    .unwrap();
    assert_eq!(
        after_replace,
        (
            0,
            0,
            None,
            CREATED.to_string(),
            "closed".to_string(),
            UPDATED.to_string(),
            UPDATED.to_string(),
            "personal-device".to_string(),
            Some(UPDATED.to_string()),
            Some("杭州".to_string())
        )
    );
    assert_eq!(protected_state().await, protected_before);

    let expected_before_late_edit = export_personal_records().await.unwrap();
    sqlx::query("UPDATE logs SET remarks = 'late local edit' WHERE sync_id = 'personal-log'")
        .execute(get_db().unwrap())
        .await
        .unwrap();
    let error =
        replace_personal_records_if_unchanged(incoming.to_string(), expected_before_late_edit)
            .await
            .unwrap_err()
            .to_string();
    assert!(error.contains("PERSONAL_RECORDS_LOCAL_CHANGED"));
    let retained_late_edit: (String,) =
        sqlx::query_as("SELECT remarks FROM logs WHERE sync_id = 'personal-log'")
            .fetch_one(get_db().unwrap())
            .await
            .unwrap();
    assert_eq!(retained_late_edit.0, "late local edit");

    let expected_after_late_edit = export_personal_records().await.unwrap();
    for (session_id, entity_id) in [
        ("personal-session", "personal-op"),
        ("collaboration-session", "collaboration-op"),
    ] {
        sqlx::query(
            "INSERT INTO oplog (
                session_id, op_type, entity_type, entity_id, data, created_at
             ) VALUES (?, 'update', 'log', ?, '{}', ?)",
        )
        .bind(session_id)
        .bind(entity_id)
        .bind(UPDATED)
        .execute(get_db().unwrap())
        .await
        .unwrap();
    }
    replace_personal_records_if_unchanged(incoming.to_string(), expected_after_late_edit)
        .await
        .unwrap();
    let oplog_counts: (i64, i64) = sqlx::query_as(
        "SELECT
            (SELECT COUNT(*) FROM oplog WHERE session_id = 'personal-session'),
            (SELECT COUNT(*) FROM oplog WHERE session_id = 'collaboration-session')",
    )
    .fetch_one(get_db().unwrap())
    .await
    .unwrap();
    assert_eq!(oplog_counts, (0, 1));

    let personal_before_conflict: (String, String) = sqlx::query_as(
        "SELECT
            (SELECT title FROM sessions WHERE session_id = 'personal-session'),
            (SELECT remarks FROM logs WHERE sync_id = 'personal-log')",
    )
    .fetch_one(get_db().unwrap())
    .await
    .unwrap();
    let mut collision = incoming.clone();
    collision["sessions"][0]["session_id"] = json!("collaboration-session");
    collision["logs"][0]["session_id"] = json!("collaboration-session");
    let error = replace_personal_records(collision.to_string())
        .await
        .unwrap_err()
        .to_string();
    assert!(error.contains("PERSONAL_RECORDS_COLLABORATION_SESSION_CONFLICT"));
    let personal_after_conflict: (String, String) = sqlx::query_as(
        "SELECT
            (SELECT title FROM sessions WHERE session_id = 'personal-session'),
            (SELECT remarks FROM logs WHERE sync_id = 'personal-log')",
    )
    .fetch_one(get_db().unwrap())
    .await
    .unwrap();
    assert_eq!(personal_after_conflict, personal_before_conflict);
    assert_eq!(protected_state().await, protected_before);

    let mut invalid_after_validation = incoming;
    invalid_after_validation["logs"][0]["source_device_id"] = json!("");
    let error = replace_personal_records(invalid_after_validation.to_string())
        .await
        .unwrap_err()
        .to_string();
    assert!(error.contains("PERSONAL_RECORDS_INVALID_LENGTH:logs.source_device_id:1:128"));
    assert_eq!(protected_state().await, protected_before);

    sqlx::query("UPDATE logs SET time = '24:00' WHERE sync_id = 'personal-log'")
        .execute(get_db().unwrap())
        .await
        .unwrap();
    let export_error = export_personal_records().await.unwrap_err().to_string();
    assert!(export_error.contains("PERSONAL_RECORDS_INVALID_TIMESTAMP:logs.time"));

    get_db().unwrap().close().await;
    let _ = std::fs::remove_file(database_path);
}
