use openlogtool_core::db::{collaboration, migrations};
use openlogtool_core::models::collaboration::{
    ApplyEventRequest, CanonicalEvent, CollaborationRole, CollaborationSnapshot,
    InstallSnapshotRequest, RemoteLog, RemoteMembership, RemoteSession, SnapshotInstallMode,
};
use sqlx::sqlite::{SqliteConnectOptions, SqlitePoolOptions};
use sqlx::{FromRow, SqlitePool};
use std::str::FromStr;

const NOW: &str = "2026-07-11T08:00:00Z";
const LATER: &str = "2026-07-11T09:00:00Z";

#[derive(Debug, FromRow)]
struct StoredLog {
    sync_id: String,
    session_id: String,
    time: String,
    rst_sent: Option<String>,
    rst_rcvd: Option<String>,
    remarks: Option<String>,
    source_device_id: Option<String>,
}

async fn test_pool() -> SqlitePool {
    let options = SqliteConnectOptions::from_str("sqlite::memory:")
        .unwrap()
        .create_if_missing(true)
        .foreign_keys(true);
    let pool = SqlitePoolOptions::new()
        .max_connections(1)
        .connect_with(options)
        .await
        .unwrap();
    migrations::run(&pool).await.unwrap();
    pool
}

async fn insert_local_session(pool: &SqlitePool, session_id: &str, title: &str) {
    sqlx::query(
        "INSERT INTO sessions (
            session_id, title, status, share_code, created_at, updated_at
         ) VALUES (?, ?, 'active', NULL, ?, ?)",
    )
    .bind(session_id)
    .bind(title)
    .bind(NOW)
    .bind(NOW)
    .execute(pool)
    .await
    .unwrap();
}

async fn insert_local_log(
    pool: &SqlitePool,
    session_id: &str,
    sync_id: &str,
    remarks: &str,
    source_device_id: Option<&str>,
) {
    sqlx::query(
        "INSERT INTO logs (
            sync_id, session_id, time, controller, callsign,
            rst_sent, rst_rcvd, qth, device, power, antenna, height, remarks,
            created_at, updated_at, source_device_id
         ) VALUES (?, ?, ?, 'BG5CRL', 'BA4AAA', '59', '57', '上海',
                   'IC-705', '10W', 'DP', '8m', ?, ?, ?, ?)",
    )
    .bind(sync_id)
    .bind(session_id)
    .bind(NOW)
    .bind(remarks)
    .bind(NOW)
    .bind(NOW)
    .bind(source_device_id)
    .execute(pool)
    .await
    .unwrap();
}

fn remote_log(session_id: &str, sync_id: &str, version: i64, remarks: &str) -> RemoteLog {
    RemoteLog {
        sync_id: sync_id.to_string(),
        session_id: session_id.to_string(),
        version,
        time: NOW.to_string(),
        controller: "BG5CRL".to_string(),
        callsign: "BA4AAA".to_string(),
        rst_sent: Some("59".to_string()),
        rst_rcvd: Some("57".to_string()),
        qth: Some("上海".to_string()),
        device: Some("IC-705".to_string()),
        power: Some("10W".to_string()),
        antenna: Some("DP".to_string()),
        height: Some("8m".to_string()),
        remarks: Some(remarks.to_string()),
        created_at: NOW.to_string(),
        updated_at: LATER.to_string(),
        deleted_at: None,
    }
}

fn install_request(
    mode: SnapshotInstallMode,
    session_id: &str,
    head: i64,
    membership_version: i64,
    logs: Vec<RemoteLog>,
) -> InstallSnapshotRequest {
    InstallSnapshotRequest {
        mode,
        server_instance_id: "server-1".to_string(),
        server_origin: "https://server.example".to_string(),
        account_id: "account-1".to_string(),
        membership: RemoteMembership {
            membership_id: "membership-1".to_string(),
            session_id: session_id.to_string(),
            user_id: "account-1".to_string(),
            role: CollaborationRole::Owner,
            version: membership_version,
            joined_at: NOW.to_string(),
            updated_at: LATER.to_string(),
            removed_at: None,
        },
        snapshot: CollaborationSnapshot {
            protocol_version: 1,
            includes_deleted_logs: true,
            session: RemoteSession {
                session_id: session_id.to_string(),
                title: "远端会话".to_string(),
                status: "active".to_string(),
                version: 2,
                role: CollaborationRole::Owner,
                high_watermark_seq: head,
                created_at: NOW.to_string(),
                updated_at: LATER.to_string(),
                closed_at: None,
                deleted_at: None,
            },
            high_watermark_seq: head,
            logs,
        },
    }
}

async fn insert_log_outbox(
    pool: &SqlitePool,
    session_id: &str,
    mutation_id: &str,
    log_id: &str,
    state: &str,
    base_version: i64,
    base_json: Option<&str>,
    remarks: &str,
    accepted_event_seq: Option<i64>,
    dependency: Option<&str>,
) {
    sqlx::query(
        "INSERT INTO sync_outbox (
            server_instance_id, account_id, session_id, mutation_id,
            entity_type, entity_id, operation, base_version, observed_seq,
            base_json, payload_json, state, attempts, accepted_event_seq,
            depends_on_mutation_id, created_at, updated_at
         ) VALUES (
            'server-1', 'account-1', ?, ?, 'log', ?, 'update', ?, 3,
            ?, ?, ?, 1, ?, ?, ?, ?
         )",
    )
    .bind(session_id)
    .bind(mutation_id)
    .bind(log_id)
    .bind(base_version)
    .bind(base_json)
    .bind(serde_json::json!({"patch": {"remarks": remarks}}).to_string())
    .bind(state)
    .bind(accepted_event_seq)
    .bind(dependency)
    .bind(NOW)
    .bind(NOW)
    .execute(pool)
    .await
    .unwrap();
}

fn log_event(
    session_id: &str,
    event_id: &str,
    seq: i64,
    mutation_id: &str,
    log: RemoteLog,
) -> ApplyEventRequest {
    ApplyEventRequest {
        server_instance_id: "server-1".to_string(),
        account_id: "account-1".to_string(),
        event: CanonicalEvent {
            protocol_version: 1,
            event_id: event_id.to_string(),
            session_id: session_id.to_string(),
            seq,
            event_type: "log.updated".to_string(),
            entity_type: "log".to_string(),
            entity_id: log.sync_id.clone(),
            entity_version: log.version,
            mutation_id: Some(mutation_id.to_string()),
            occurred_at: LATER.to_string(),
            payload: serde_json::to_value(log).unwrap(),
        },
    }
}

#[tokio::test]
async fn publish_install_preserves_ids_all_fields_remarks_and_source_device() {
    let pool = test_pool().await;
    insert_local_session(&pool, "session-1", "本地会话").await;
    insert_local_log(
        &pool,
        "session-1",
        "log-1",
        "本地备注",
        Some("local-device"),
    )
    .await;
    let local_snapshot = collaboration::begin_publish_snapshot(
        &pool,
        "server-1",
        "https://server.example",
        "account-1",
        "session-1",
    )
    .await
    .unwrap();
    assert_eq!(local_snapshot.logs.len(), 1);

    let mut request = install_request(
        SnapshotInstallMode::Publish,
        "session-1",
        7,
        1,
        vec![remote_log("session-1", "log-1", 3, "服务端备注")],
    );
    request.snapshot.includes_deleted_logs = false;
    let binding = collaboration::install_snapshot(&pool, request)
        .await
        .unwrap();

    assert_eq!(binding.session_id, "session-1");
    assert_eq!(binding.last_applied_seq, 7);
    assert_eq!(binding.last_seen_head_seq, 7);
    let stored = sqlx::query_as::<_, StoredLog>(
        "SELECT sync_id, session_id, time, rst_sent, rst_rcvd, remarks, source_device_id
         FROM logs WHERE sync_id = 'log-1'",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(stored.sync_id, "log-1");
    assert_eq!(stored.session_id, "session-1");
    assert_eq!(stored.time, NOW);
    assert_eq!(stored.rst_sent.as_deref(), Some("59"));
    assert_eq!(stored.rst_rcvd.as_deref(), Some("57"));
    assert_eq!(stored.remarks.as_deref(), Some("服务端备注"));
    assert_eq!(stored.source_device_id.as_deref(), Some("local-device"));

    let shadow_json: (String,) = sqlx::query_as(
        "SELECT server_json FROM entity_shadows
         WHERE session_id = 'session-1' AND entity_type = 'log' AND entity_id = 'log-1'",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(shadow_json.0.contains("服务端备注"));

    let version_rows: (i64, i64) =
        sqlx::query_as("SELECT COUNT(*), MAX(version) FROM schema_version")
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(version_rows, (1, 7));
    let first_device = collaboration::get_or_create_device_id(&pool).await.unwrap();
    let second_device = collaboration::get_or_create_device_id(&pool).await.unwrap();
    assert_eq!(first_device, second_device);
}

#[tokio::test]
async fn publish_snapshot_normalizes_short_time_without_mutating_local_data() {
    let pool = test_pool().await;
    insert_local_session(&pool, "session-time", "时间兼容").await;
    insert_local_log(&pool, "session-time", "log-time", "短时间", None).await;
    sqlx::query(
        "UPDATE logs
         SET time = '08:30', created_at = '2026-07-11T07:00:00+08:00'
         WHERE sync_id = 'log-time'",
    )
    .execute(&pool)
    .await
    .unwrap();

    let snapshot = collaboration::begin_publish_snapshot(
        &pool,
        "time-server",
        "https://time.example",
        "time-account",
        "session-time",
    )
    .await
    .unwrap();
    assert_eq!(snapshot.logs.len(), 1);
    assert_eq!(snapshot.logs[0].time, "2026-07-11T08:30:00+08:00");

    let json = serde_json::to_value(&snapshot.logs[0]).unwrap();
    let object = json.as_object().unwrap();
    let mut keys: Vec<&str> = object.keys().map(String::as_str).collect();
    keys.sort_unstable();
    let mut expected = vec![
        "antenna",
        "callsign",
        "controller",
        "device",
        "height",
        "power",
        "qth",
        "remarks",
        "rstRcvd",
        "rstSent",
        "syncId",
        "time",
    ];
    expected.sort_unstable();
    assert_eq!(keys, expected);

    let local_time: (String,) = sqlx::query_as("SELECT time FROM logs WHERE sync_id = 'log-time'")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(local_time.0, "08:30");

    sqlx::query("UPDATE logs SET time = 'not-a-time' WHERE sync_id = 'log-time'")
        .execute(&pool)
        .await
        .unwrap();
    let error = collaboration::get_publish_snapshot(&pool, "session-time")
        .await
        .unwrap_err()
        .to_string();
    assert!(error.contains("LOCAL_LOG_TIME_INVALID:log-time"));
    let invalid_local_time: (String,) =
        sqlx::query_as("SELECT time FROM logs WHERE sync_id = 'log-time'")
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(invalid_local_time.0, "not-a-time");
}

#[tokio::test]
async fn snapshot_failure_rolls_back_session_logs_binding_and_shadows() {
    let pool = test_pool().await;
    insert_local_session(&pool, "existing", "现有会话").await;
    insert_local_log(&pool, "existing", "existing-log", "原数据", None).await;
    sqlx::query(
        "CREATE TRIGGER fail_snapshot_insert
         BEFORE INSERT ON logs WHEN NEW.sync_id = 'fail-log'
         BEGIN SELECT RAISE(ABORT, 'injected snapshot failure'); END",
    )
    .execute(&pool)
    .await
    .unwrap();

    let request = install_request(
        SnapshotInstallMode::Join,
        "remote-session",
        2,
        1,
        vec![
            remote_log("remote-session", "ok-log", 1, "先写入"),
            remote_log("remote-session", "fail-log", 1, "触发失败"),
        ],
    );
    let error = collaboration::install_snapshot(&pool, request)
        .await
        .unwrap_err()
        .to_string();
    assert!(error.contains("injected snapshot failure"));

    let remote_sessions: (i64,) =
        sqlx::query_as("SELECT COUNT(*) FROM sessions WHERE session_id = 'remote-session'")
            .fetch_one(&pool)
            .await
            .unwrap();
    let remote_logs: (i64,) =
        sqlx::query_as("SELECT COUNT(*) FROM logs WHERE session_id = 'remote-session'")
            .fetch_one(&pool)
            .await
            .unwrap();
    let bindings: (i64,) = sqlx::query_as("SELECT COUNT(*) FROM collaboration_bindings")
        .fetch_one(&pool)
        .await
        .unwrap();
    let shadows: (i64,) = sqlx::query_as("SELECT COUNT(*) FROM entity_shadows")
        .fetch_one(&pool)
        .await
        .unwrap();
    let existing_logs: (i64,) =
        sqlx::query_as("SELECT COUNT(*) FROM logs WHERE sync_id = 'existing-log'")
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(remote_sessions.0, 0);
    assert_eq!(remote_logs.0, 0);
    assert_eq!(bindings.0, 0);
    assert_eq!(shadows.0, 0);
    assert_eq!(existing_logs.0, 1);
}

#[tokio::test]
async fn join_rejects_an_unbound_local_session_with_the_same_id() {
    let pool = test_pool().await;
    insert_local_session(&pool, "same-session", "不得覆盖").await;

    let request = install_request(SnapshotInstallMode::Join, "same-session", 0, 1, Vec::new());
    let error = collaboration::install_snapshot(&pool, request)
        .await
        .unwrap_err()
        .to_string();
    assert!(error.contains("LOCAL_SESSION_ID_CONFLICT"));
    let title: (String,) =
        sqlx::query_as("SELECT title FROM sessions WHERE session_id = 'same-session'")
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(title.0, "不得覆盖");
}

#[tokio::test]
async fn reinstall_is_authoritative_and_advances_cursor_atomically() {
    let pool = test_pool().await;
    let first = install_request(
        SnapshotInstallMode::Join,
        "joined-session",
        3,
        1,
        vec![
            remote_log("joined-session", "kept-log", 1, "第一版"),
            remote_log("joined-session", "removed-log", 1, "稍后删除"),
        ],
    );
    collaboration::install_snapshot(&pool, first).await.unwrap();

    let second = install_request(
        SnapshotInstallMode::Join,
        "joined-session",
        9,
        2,
        vec![remote_log("joined-session", "kept-log", 4, "第二版")],
    );
    let binding = collaboration::install_snapshot(&pool, second)
        .await
        .unwrap();
    assert_eq!(binding.membership_version, 2);
    assert_eq!(binding.last_applied_seq, 9);
    assert_eq!(binding.last_seen_head_seq, 9);

    let logs: (i64,) =
        sqlx::query_as("SELECT COUNT(*) FROM logs WHERE session_id = 'joined-session'")
            .fetch_one(&pool)
            .await
            .unwrap();
    let remarks: (Option<String>,) =
        sqlx::query_as("SELECT remarks FROM logs WHERE sync_id = 'kept-log'")
            .fetch_one(&pool)
            .await
            .unwrap();
    let removed: (i64,) = sqlx::query_as("SELECT COUNT(*) FROM logs WHERE sync_id = 'removed-log'")
        .fetch_one(&pool)
        .await
        .unwrap();
    let shadows: (i64,) =
        sqlx::query_as("SELECT COUNT(*) FROM entity_shadows WHERE session_id = 'joined-session'")
            .fetch_one(&pool)
            .await
            .unwrap();
    let min_shadow_seq: (i64,) = sqlx::query_as(
        "SELECT MIN(last_event_seq) FROM entity_shadows WHERE session_id = 'joined-session'",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(logs.0, 1);
    assert_eq!(remarks.0.as_deref(), Some("第二版"));
    assert_eq!(removed.0, 0);
    assert_eq!(shadows.0, 2);
    assert_eq!(min_shadow_seq.0, 9);

    let stale_cursor = install_request(
        SnapshotInstallMode::Join,
        "joined-session",
        8,
        2,
        vec![remote_log("joined-session", "kept-log", 3, "不得恢复")],
    );
    let error = collaboration::install_snapshot(&pool, stale_cursor)
        .await
        .unwrap_err()
        .to_string();
    assert!(error.contains("SNAPSHOT_CURSOR_REGRESSION"));

    let stale_membership = install_request(
        SnapshotInstallMode::Join,
        "joined-session",
        9,
        1,
        vec![remote_log("joined-session", "kept-log", 3, "不得恢复")],
    );
    let error = collaboration::install_snapshot(&pool, stale_membership)
        .await
        .unwrap_err()
        .to_string();
    assert!(error.contains("SNAPSHOT_MEMBERSHIP_VERSION_REGRESSION"));

    let unchanged: (Option<String>,) =
        sqlx::query_as("SELECT remarks FROM logs WHERE sync_id = 'kept-log'")
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(unchanged.0.as_deref(), Some("第二版"));
}

#[tokio::test]
async fn revoked_binding_requires_a_newer_version_of_the_same_membership() {
    let pool = test_pool().await;
    let initial = install_request(
        SnapshotInstallMode::Join,
        "revoked-session",
        3,
        2,
        vec![remote_log("revoked-session", "revoked-log", 1, "原版")],
    );
    collaboration::install_snapshot(&pool, initial)
        .await
        .unwrap();
    collaboration::mark_revoked(&pool, "server-1", "account-1", "revoked-session")
        .await
        .unwrap();

    let late = install_request(
        SnapshotInstallMode::Join,
        "revoked-session",
        4,
        2,
        vec![remote_log("revoked-session", "revoked-log", 2, "迟到")],
    );
    let error = collaboration::install_snapshot(&pool, late)
        .await
        .unwrap_err()
        .to_string();
    assert!(error.contains("BINDING_REVOKED"));

    let explicit_rejoin = install_request(
        SnapshotInstallMode::Join,
        "revoked-session",
        4,
        3,
        vec![remote_log("revoked-session", "revoked-log", 2, "重新加入")],
    );
    let binding = collaboration::install_snapshot(&pool, explicit_rejoin)
        .await
        .unwrap();
    assert_eq!(binding.replica_state, "ready");
    assert_eq!(binding.membership_version, 3);
    assert!(binding.revoked_at.is_none());
}

#[tokio::test]
async fn snapshot_reinstall_reapplies_pending_overlay_without_changing_shadow() {
    let pool = test_pool().await;
    collaboration::install_snapshot(
        &pool,
        install_request(
            SnapshotInstallMode::Join,
            "pending-session",
            3,
            1,
            vec![remote_log(
                "pending-session",
                "pending-log",
                1,
                "remote base",
            )],
        ),
    )
    .await
    .unwrap();
    let base_json: (String,) = sqlx::query_as(
        "SELECT server_json FROM entity_shadows
         WHERE session_id = 'pending-session' AND entity_type = 'log'
           AND entity_id = 'pending-log'",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO sync_outbox (
            server_instance_id, account_id, session_id, mutation_id,
            entity_type, entity_id, operation, base_version, observed_seq,
            base_json, payload_json, state, attempts, created_at, updated_at
         ) VALUES (
            'server-1', 'account-1', 'pending-session', 'pending-mutation',
            'log', 'pending-log', 'update', 1, 3, ?,
            '{\"patch\":{\"remarks\":\"local pending\"}}',
            'pending', 0, ?, ?
         )",
    )
    .bind(&base_json.0)
    .bind(NOW)
    .bind(NOW)
    .execute(&pool)
    .await
    .unwrap();
    sqlx::query("UPDATE logs SET remarks = 'local pending' WHERE sync_id = 'pending-log'")
        .execute(&pool)
        .await
        .unwrap();

    collaboration::install_snapshot(
        &pool,
        install_request(
            SnapshotInstallMode::Join,
            "pending-session",
            9,
            2,
            vec![remote_log(
                "pending-session",
                "pending-log",
                2,
                "remote newer",
            )],
        ),
    )
    .await
    .unwrap();

    let materialized: (Option<String>,) =
        sqlx::query_as("SELECT remarks FROM logs WHERE sync_id = 'pending-log'")
            .fetch_one(&pool)
            .await
            .unwrap();
    let shadow: (String,) = sqlx::query_as(
        "SELECT server_json FROM entity_shadows
         WHERE session_id = 'pending-session' AND entity_type = 'log'
           AND entity_id = 'pending-log'",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    let outbox: (i64,) =
        sqlx::query_as("SELECT COUNT(*) FROM sync_outbox WHERE mutation_id = 'pending-mutation'")
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(materialized.0.as_deref(), Some("local pending"));
    assert!(shadow.0.contains("remote newer"));
    assert!(!shadow.0.contains("local pending"));
    assert_eq!(outbox.0, 1);
}

#[tokio::test]
async fn snapshot_completeness_is_required_for_reinstall_but_not_first_join() {
    let pool = test_pool().await;
    let mut first = install_request(
        SnapshotInstallMode::Join,
        "completeness-session",
        3,
        1,
        vec![remote_log(
            "completeness-session",
            "completeness-log",
            1,
            "initial",
        )],
    );
    first.snapshot.includes_deleted_logs = false;
    collaboration::install_snapshot(&pool, first).await.unwrap();

    let mut incomplete = install_request(
        SnapshotInstallMode::Join,
        "completeness-session",
        4,
        2,
        vec![remote_log(
            "completeness-session",
            "completeness-log",
            2,
            "must not install",
        )],
    );
    incomplete.snapshot.includes_deleted_logs = false;
    let error = collaboration::install_snapshot(&pool, incomplete)
        .await
        .unwrap_err()
        .to_string();
    assert!(error.contains("SNAPSHOT_TOMBSTONES_REQUIRED"));
    let unchanged: (i64, i64, Option<String>) = sqlx::query_as(
        "SELECT b.membership_version, b.last_applied_seq, l.remarks
         FROM collaboration_bindings b JOIN logs l ON l.session_id = b.session_id
         WHERE b.session_id = 'completeness-session'",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(unchanged.0, 1);
    assert_eq!(unchanged.1, 3);
    assert_eq!(unchanged.2.as_deref(), Some("initial"));

    let mut inconsistent = install_request(
        SnapshotInstallMode::Join,
        "another-session",
        1,
        1,
        vec![remote_log("another-session", "deleted-log", 2, "deleted")],
    );
    inconsistent.snapshot.includes_deleted_logs = false;
    inconsistent.snapshot.logs[0].deleted_at = Some(LATER.to_string());
    let error = collaboration::install_snapshot(&pool, inconsistent)
        .await
        .unwrap_err()
        .to_string();
    assert!(error.contains("SNAPSHOT_DELETED_LOGS_FLAG_INVALID"));

    let mut serialized = serde_json::to_value(install_request(
        SnapshotInstallMode::Join,
        "json-session",
        0,
        1,
        Vec::new(),
    ))
    .unwrap();
    serialized
        .get_mut("snapshot")
        .and_then(serde_json::Value::as_object_mut)
        .unwrap()
        .remove("includesDeletedLogs");
    assert!(serde_json::from_value::<InstallSnapshotRequest>(serialized).is_err());
}

#[tokio::test]
async fn cursor_reinstall_preserves_every_unresolved_state_and_conflict_overlay() {
    let pool = test_pool().await;
    let states = ["pending", "retrying", "sending", "rejected", "conflict"];
    let initial_logs = states
        .iter()
        .map(|state| remote_log("state-session", &format!("{state}-log"), 1, "remote base"))
        .collect();
    collaboration::install_snapshot(
        &pool,
        install_request(
            SnapshotInstallMode::Join,
            "state-session",
            3,
            1,
            initial_logs,
        ),
    )
    .await
    .unwrap();

    for state in states {
        let log_id = format!("{state}-log");
        let mutation_id = format!("{state}-mutation");
        let base: (String,) = sqlx::query_as(
            "SELECT server_json FROM entity_shadows
             WHERE session_id = 'state-session' AND entity_type = 'log'
               AND entity_id = ?",
        )
        .bind(&log_id)
        .fetch_one(&pool)
        .await
        .unwrap();
        insert_log_outbox(
            &pool,
            "state-session",
            &mutation_id,
            &log_id,
            state,
            1,
            Some(&base.0),
            &format!("{state} local"),
            None,
            None,
        )
        .await;
        sqlx::query("UPDATE logs SET remarks = ? WHERE sync_id = ?")
            .bind(format!("{state} local"))
            .bind(&log_id)
            .execute(&pool)
            .await
            .unwrap();
    }
    sqlx::query(
        "INSERT INTO sync_conflicts (
            conflict_id, server_instance_id, account_id, session_id,
            entity_type, entity_id, mutation_id, base_version, remote_version,
            base_json, local_json, remote_json, conflicting_fields_json,
            state, created_at
         )
         SELECT 'conflict-record', server_instance_id, account_id, session_id,
                entity_type, entity_id, mutation_id, base_version, 2,
                base_json, '{\"remarks\":\"conflict local\"}',
                '{\"remarks\":\"remote conflict\"}', '[\"remarks\"]',
                'open', ?
         FROM sync_outbox WHERE mutation_id = 'conflict-mutation'",
    )
    .bind(NOW)
    .execute(&pool)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO applied_events (
            server_instance_id, account_id, session_id, event_id,
            event_seq, mutation_id, applied_at
         ) VALUES ('server-1', 'account-1', 'state-session',
                   'pre-snapshot-event', 1, NULL, ?)",
    )
    .bind(NOW)
    .execute(&pool)
    .await
    .unwrap();

    let newer_logs = states
        .iter()
        .map(|state| {
            remote_log(
                "state-session",
                &format!("{state}-log"),
                2,
                &format!("{state} remote newer"),
            )
        })
        .collect();
    let binding = collaboration::install_snapshot(
        &pool,
        install_request(SnapshotInstallMode::Join, "state-session", 9, 2, newer_logs),
    )
    .await
    .unwrap();
    assert_eq!(binding.membership_version, 2);
    assert_eq!(binding.last_applied_seq, 9);
    assert_eq!(binding.last_seen_head_seq, 9);

    let stored_states: Vec<(String, String)> = sqlx::query_as(
        "SELECT entity_id, state FROM sync_outbox
         WHERE session_id = 'state-session' ORDER BY entity_id",
    )
    .fetch_all(&pool)
    .await
    .unwrap();
    let expected_states = vec![
        ("conflict-log".to_string(), "conflict".to_string()),
        ("pending-log".to_string(), "pending".to_string()),
        ("rejected-log".to_string(), "rejected".to_string()),
        ("retrying-log".to_string(), "retrying".to_string()),
        ("sending-log".to_string(), "sending".to_string()),
    ];
    assert_eq!(stored_states, expected_states);
    for state in states {
        let log_id = format!("{state}-log");
        let materialized: (Option<String>,) =
            sqlx::query_as("SELECT remarks FROM logs WHERE sync_id = ?")
                .bind(&log_id)
                .fetch_one(&pool)
                .await
                .unwrap();
        let shadow: (String,) = sqlx::query_as(
            "SELECT server_json FROM entity_shadows
             WHERE session_id = 'state-session' AND entity_type = 'log'
               AND entity_id = ?",
        )
        .bind(&log_id)
        .fetch_one(&pool)
        .await
        .unwrap();
        assert_eq!(
            materialized.0.as_deref(),
            Some(format!("{state} local").as_str())
        );
        assert!(shadow.0.contains(&format!("{state} remote newer")));
        assert!(!shadow.0.contains(&format!("{state} local")));
    }
    let retained: (i64, String, String) = sqlx::query_as(
        "SELECT COUNT(*), MIN(state), MIN(local_json) FROM sync_conflicts
         WHERE conflict_id = 'conflict-record'",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(retained.0, 1);
    assert_eq!(retained.1, "open");
    assert!(retained.2.contains("conflict local"));
    let applied: (i64,) =
        sqlx::query_as("SELECT COUNT(*) FROM applied_events WHERE session_id = 'state-session'")
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(applied.0, 0);
}

#[tokio::test]
async fn covered_accepted_roots_rebase_only_an_exact_direct_successor() {
    let pool = test_pool().await;
    collaboration::install_snapshot(
        &pool,
        install_request(
            SnapshotInstallMode::Join,
            "accepted-session",
            3,
            1,
            vec![
                remote_log("accepted-session", "exact-log", 1, "exact base"),
                remote_log("accepted-session", "newer-log", 1, "newer base"),
            ],
        ),
    )
    .await
    .unwrap();
    for (kind, accepted_remarks, dependent_remarks) in [
        ("exact", "exact accepted", "exact local successor"),
        ("newer", "newer accepted", "newer local successor"),
    ] {
        let log_id = format!("{kind}-log");
        let base: (String,) = sqlx::query_as(
            "SELECT server_json FROM entity_shadows
             WHERE session_id = 'accepted-session' AND entity_id = ?",
        )
        .bind(&log_id)
        .fetch_one(&pool)
        .await
        .unwrap();
        let root = format!("{kind}-root");
        insert_log_outbox(
            &pool,
            "accepted-session",
            &root,
            &log_id,
            "accepted",
            1,
            Some(&base.0),
            accepted_remarks,
            Some(4),
            None,
        )
        .await;
        insert_log_outbox(
            &pool,
            "accepted-session",
            &format!("{kind}-dependent"),
            &log_id,
            "pending",
            1,
            Some(&base.0),
            dependent_remarks,
            None,
            Some(&root),
        )
        .await;
        sqlx::query("UPDATE logs SET remarks = ? WHERE sync_id = ?")
            .bind(dependent_remarks)
            .bind(&log_id)
            .execute(&pool)
            .await
            .unwrap();
    }
    collaboration::install_snapshot(
        &pool,
        install_request(
            SnapshotInstallMode::Join,
            "accepted-session",
            9,
            2,
            vec![
                remote_log("accepted-session", "exact-log", 2, "exact accepted"),
                remote_log("accepted-session", "newer-log", 3, "remote intervened"),
            ],
        ),
    )
    .await
    .unwrap();

    let roots: Vec<(String,)> = sqlx::query_as(
        "SELECT mutation_id FROM sync_outbox
         WHERE mutation_id IN ('exact-root', 'newer-root')
         ORDER BY mutation_id",
    )
    .fetch_all(&pool)
    .await
    .unwrap();
    assert!(roots.is_empty());
    let exact: (i64, i64, Option<String>, String) = sqlx::query_as(
        "SELECT base_version, observed_seq, depends_on_mutation_id, base_json
         FROM sync_outbox WHERE mutation_id = 'exact-dependent'",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(exact.0, 2);
    assert_eq!(exact.1, 9);
    assert!(exact.2.is_none());
    assert!(exact.3.contains("exact accepted"));
    let newer: (i64, i64, Option<String>, String) = sqlx::query_as(
        "SELECT base_version, observed_seq, depends_on_mutation_id, base_json
         FROM sync_outbox WHERE mutation_id = 'newer-dependent'",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(newer.0, 1);
    assert_eq!(newer.1, 3);
    assert!(newer.2.is_none());
    assert!(newer.3.contains("newer base"));
    assert!(!newer.3.contains("remote intervened"));
    for (log_id, expected) in [
        ("exact-log", "exact local successor"),
        ("newer-log", "newer local successor"),
    ] {
        let remarks: (Option<String>,) =
            sqlx::query_as("SELECT remarks FROM logs WHERE sync_id = ?")
                .bind(log_id)
                .fetch_one(&pool)
                .await
                .unwrap();
        assert_eq!(remarks.0.as_deref(), Some(expected));
    }
}

#[tokio::test]
async fn complete_reinstall_rejects_a_missing_accepted_canonical_entity_atomically() {
    let pool = test_pool().await;
    collaboration::install_snapshot(
        &pool,
        install_request(
            SnapshotInstallMode::Join,
            "missing-session",
            3,
            1,
            vec![remote_log(
                "missing-session",
                "missing-log",
                1,
                "old canonical",
            )],
        ),
    )
    .await
    .unwrap();
    let base: (String,) = sqlx::query_as(
        "SELECT server_json FROM entity_shadows
         WHERE session_id = 'missing-session' AND entity_id = 'missing-log'",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    insert_log_outbox(
        &pool,
        "missing-session",
        "missing-root",
        "missing-log",
        "accepted",
        1,
        Some(&base.0),
        "accepted local",
        Some(4),
        None,
    )
    .await;
    sqlx::query("UPDATE logs SET remarks = 'accepted local' WHERE sync_id = 'missing-log'")
        .execute(&pool)
        .await
        .unwrap();

    let error = collaboration::install_snapshot(
        &pool,
        install_request(
            SnapshotInstallMode::Join,
            "missing-session",
            8,
            2,
            Vec::new(),
        ),
    )
    .await
    .unwrap_err()
    .to_string();
    assert!(error.contains("SNAPSHOT_ACCEPTED_ENTITY_MISSING"));
    let unchanged: (i64, i64, Option<String>, String, i64) = sqlx::query_as(
        "SELECT b.membership_version, b.last_applied_seq, l.remarks, e.server_json,
                (SELECT COUNT(*) FROM sync_outbox WHERE mutation_id = 'missing-root')
         FROM collaboration_bindings b
         JOIN logs l ON l.session_id = b.session_id AND l.sync_id = 'missing-log'
         JOIN entity_shadows e ON e.session_id = b.session_id
              AND e.entity_type = 'log' AND e.entity_id = 'missing-log'
         WHERE b.session_id = 'missing-session'",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(unchanged.0, 1);
    assert_eq!(unchanged.1, 3);
    assert_eq!(unchanged.2.as_deref(), Some("accepted local"));
    assert!(unchanged.3.contains("old canonical"));
    assert_eq!(unchanged.4, 1);
}

#[tokio::test]
async fn complete_reinstall_rejects_a_missing_non_create_chain_but_keeps_local_create() {
    let pool = test_pool().await;
    collaboration::install_snapshot(
        &pool,
        install_request(
            SnapshotInstallMode::Join,
            "coverage-session",
            3,
            1,
            vec![remote_log(
                "coverage-session",
                "remote-log",
                1,
                "remote base",
            )],
        ),
    )
    .await
    .unwrap();
    let base: (String,) = sqlx::query_as(
        "SELECT server_json FROM entity_shadows
         WHERE session_id = 'coverage-session' AND entity_id = 'remote-log'",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    insert_log_outbox(
        &pool,
        "coverage-session",
        "missing-update",
        "remote-log",
        "retrying",
        1,
        Some(&base.0),
        "local update",
        None,
        None,
    )
    .await;
    sqlx::query("UPDATE logs SET remarks = 'local update' WHERE sync_id = 'remote-log'")
        .execute(&pool)
        .await
        .unwrap();

    let error = collaboration::install_snapshot(
        &pool,
        install_request(
            SnapshotInstallMode::Join,
            "coverage-session",
            8,
            2,
            Vec::new(),
        ),
    )
    .await
    .unwrap_err()
    .to_string();
    assert!(error.contains("SNAPSHOT_PENDING_ENTITY_MISSING"));
    let unchanged: (i64, i64, Option<String>, String) = sqlx::query_as(
        "SELECT b.membership_version, b.last_applied_seq, l.remarks, e.server_json
         FROM collaboration_bindings b
         JOIN logs l ON l.session_id = b.session_id AND l.sync_id = 'remote-log'
         JOIN entity_shadows e ON e.session_id = b.session_id
              AND e.entity_type = 'log' AND e.entity_id = 'remote-log'
         WHERE b.session_id = 'coverage-session'",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(unchanged.0, 1);
    assert_eq!(unchanged.1, 3);
    assert_eq!(unchanged.2.as_deref(), Some("local update"));
    assert!(unchanged.3.contains("remote base"));

    // Once the server supplies the missing tombstone, the reinstall succeeds;
    // then a true local create is the only entity legitimately absent from a
    // complete canonical snapshot.
    let mut tombstone = remote_log("coverage-session", "remote-log", 2, "remote deleted");
    tombstone.deleted_at = Some(LATER.to_string());
    collaboration::install_snapshot(
        &pool,
        install_request(
            SnapshotInstallMode::Join,
            "coverage-session",
            8,
            2,
            vec![tombstone],
        ),
    )
    .await
    .unwrap();
    insert_local_log(
        &pool,
        "coverage-session",
        "local-create",
        "local create overlay",
        Some("local-device"),
    )
    .await;
    sqlx::query(
        "INSERT INTO sync_outbox (
            server_instance_id, account_id, session_id, mutation_id,
            entity_type, entity_id, operation, base_version, observed_seq,
            base_json, payload_json, state, attempts, created_at, updated_at
         ) VALUES (
            'server-1', 'account-1', 'coverage-session', 'local-create-root',
            'log', 'local-create', 'create', 0, 8, NULL,
            '{\"value\":{\"remarks\":\"local create overlay\"}}',
            'sending', 1, ?, ?
         )",
    )
    .bind(NOW)
    .bind(NOW)
    .execute(&pool)
    .await
    .unwrap();
    collaboration::install_snapshot(
        &pool,
        install_request(
            SnapshotInstallMode::Join,
            "coverage-session",
            9,
            3,
            vec![remote_log(
                "coverage-session",
                "remote-log",
                2,
                "remote deleted",
            )],
        ),
    )
    .await
    .unwrap();
    let local_create: (Option<String>, Option<String>, String, i64) = sqlx::query_as(
        "SELECT l.remarks, l.source_device_id, o.state,
                (SELECT COUNT(*) FROM entity_shadows
                 WHERE session_id = 'coverage-session' AND entity_id = 'local-create')
         FROM logs l JOIN sync_outbox o ON o.entity_id = l.sync_id
         WHERE l.sync_id = 'local-create'",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(local_create.0.as_deref(), Some("local create overlay"));
    assert_eq!(local_create.1.as_deref(), Some("local-device"));
    assert_eq!(local_create.2, "sending");
    assert_eq!(local_create.3, 0);
}

#[tokio::test]
async fn replayed_event_below_snapshot_cursor_safely_retires_sending_root() {
    let pool = test_pool().await;
    collaboration::install_snapshot(
        &pool,
        install_request(
            SnapshotInstallMode::Join,
            "replay-session",
            3,
            1,
            vec![remote_log("replay-session", "replay-log", 1, "base")],
        ),
    )
    .await
    .unwrap();
    let base: (String,) = sqlx::query_as(
        "SELECT server_json FROM entity_shadows
         WHERE session_id = 'replay-session' AND entity_id = 'replay-log'",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    insert_log_outbox(
        &pool,
        "replay-session",
        "replay-root",
        "replay-log",
        "sending",
        1,
        Some(&base.0),
        "accepted value",
        None,
        None,
    )
    .await;
    insert_log_outbox(
        &pool,
        "replay-session",
        "replay-dependent",
        "replay-log",
        "pending",
        1,
        Some(&base.0),
        "local successor",
        None,
        Some("replay-root"),
    )
    .await;
    collaboration::install_snapshot(
        &pool,
        install_request(
            SnapshotInstallMode::Join,
            "replay-session",
            10,
            2,
            vec![remote_log(
                "replay-session",
                "replay-log",
                2,
                "accepted value",
            )],
        ),
    )
    .await
    .unwrap();
    collaboration::mark_mutation_accepted(
        &pool,
        "server-1",
        "account-1",
        "replay-session",
        "replay-root",
        4,
    )
    .await
    .unwrap();
    let canonical = remote_log("replay-session", "replay-log", 2, "accepted value");
    let result = collaboration::apply_event(
        &pool,
        log_event(
            "replay-session",
            "replayed-event-4",
            4,
            "replay-root",
            canonical,
        ),
    )
    .await
    .unwrap();
    assert_eq!(result.outcome, "duplicate");
    assert_eq!(result.cursor, 10);
    let root: (i64,) =
        sqlx::query_as("SELECT COUNT(*) FROM sync_outbox WHERE mutation_id = 'replay-root'")
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(root.0, 0);
    let dependent: (i64, i64, Option<String>, String) = sqlx::query_as(
        "SELECT base_version, observed_seq, depends_on_mutation_id, base_json
         FROM sync_outbox WHERE mutation_id = 'replay-dependent'",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(dependent.0, 2);
    assert_eq!(dependent.1, 10);
    assert!(dependent.2.is_none());
    assert!(dependent.3.contains("accepted value"));
    let materialized: (Option<String>,) =
        sqlx::query_as("SELECT remarks FROM logs WHERE sync_id = 'replay-log'")
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(materialized.0.as_deref(), Some("local successor"));
}

#[tokio::test]
async fn replayed_event_canonical_fork_is_an_atomic_zero_write_failure() {
    let pool = test_pool().await;
    collaboration::install_snapshot(
        &pool,
        install_request(
            SnapshotInstallMode::Join,
            "fork-session",
            3,
            1,
            vec![remote_log("fork-session", "fork-log", 1, "base")],
        ),
    )
    .await
    .unwrap();
    let base: (String,) = sqlx::query_as(
        "SELECT server_json FROM entity_shadows
         WHERE session_id = 'fork-session' AND entity_id = 'fork-log'",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    insert_log_outbox(
        &pool,
        "fork-session",
        "fork-root",
        "fork-log",
        "sending",
        1,
        Some(&base.0),
        "canonical actual",
        None,
        None,
    )
    .await;
    insert_log_outbox(
        &pool,
        "fork-session",
        "fork-dependent",
        "fork-log",
        "pending",
        1,
        Some(&base.0),
        "local successor",
        None,
        Some("fork-root"),
    )
    .await;
    collaboration::install_snapshot(
        &pool,
        install_request(
            SnapshotInstallMode::Join,
            "fork-session",
            10,
            2,
            vec![remote_log(
                "fork-session",
                "fork-log",
                2,
                "canonical actual",
            )],
        ),
    )
    .await
    .unwrap();
    collaboration::mark_mutation_accepted(
        &pool,
        "server-1",
        "account-1",
        "fork-session",
        "fork-root",
        4,
    )
    .await
    .unwrap();

    let error = collaboration::apply_event(
        &pool,
        log_event(
            "fork-session",
            "forked-event-4",
            4,
            "fork-root",
            remote_log("fork-session", "fork-log", 2, "forged payload"),
        ),
    )
    .await
    .unwrap_err()
    .to_string();
    assert!(error.contains("DUPLICATE_EVENT_CANONICAL_FORK"));
    let state: (String, Option<String>, i64, String, Option<String>) = sqlx::query_as(
        "SELECT root.state, dependent.depends_on_mutation_id,
                b.last_applied_seq, shadow.server_json, l.remarks
         FROM sync_outbox root
         JOIN sync_outbox dependent ON dependent.mutation_id = 'fork-dependent'
         JOIN collaboration_bindings b ON b.session_id = root.session_id
         JOIN entity_shadows shadow ON shadow.session_id = root.session_id
              AND shadow.entity_type = 'log' AND shadow.entity_id = 'fork-log'
         JOIN logs l ON l.sync_id = 'fork-log'
         WHERE root.mutation_id = 'fork-root'",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(state.0, "accepted");
    assert_eq!(state.1.as_deref(), Some("fork-root"));
    assert_eq!(state.2, 10);
    assert!(state.3.contains("canonical actual"));
    assert!(!state.3.contains("forged payload"));
    assert_eq!(state.4.as_deref(), Some("local successor"));
}

#[tokio::test]
async fn stale_membership_head_and_identity_snapshots_are_zero_write_rejections() {
    let pool = test_pool().await;
    collaboration::install_snapshot(
        &pool,
        install_request(
            SnapshotInstallMode::Join,
            "guard-session",
            9,
            2,
            vec![remote_log("guard-session", "guard-log", 2, "guard base")],
        ),
    )
    .await
    .unwrap();
    collaboration::set_head_seq(&pool, "server-1", "account-1", "guard-session", 12)
        .await
        .unwrap();
    let before: (String, String, i64, i64, i64, String, Option<String>) = sqlx::query_as(
        "SELECT s.title, b.role, b.membership_version, b.last_applied_seq,
                b.last_seen_head_seq, e.server_json, l.remarks
         FROM sessions s
         JOIN collaboration_bindings b ON b.session_id = s.session_id
         JOIN entity_shadows e ON e.session_id = s.session_id
              AND e.entity_type = 'log' AND e.entity_id = 'guard-log'
         JOIN logs l ON l.sync_id = 'guard-log'
         WHERE s.session_id = 'guard-session'",
    )
    .fetch_one(&pool)
    .await
    .unwrap();

    let mut role_fork = install_request(
        SnapshotInstallMode::Join,
        "guard-session",
        12,
        2,
        vec![remote_log(
            "guard-session",
            "guard-log",
            3,
            "must not write",
        )],
    );
    role_fork.membership.role = CollaborationRole::Viewer;
    role_fork.snapshot.session.role = CollaborationRole::Viewer;
    let error = collaboration::install_snapshot(&pool, role_fork)
        .await
        .unwrap_err()
        .to_string();
    assert!(error.contains("SNAPSHOT_MEMBERSHIP_VERSION_FORK"));

    let head_regression = install_request(
        SnapshotInstallMode::Join,
        "guard-session",
        11,
        3,
        vec![remote_log(
            "guard-session",
            "guard-log",
            3,
            "must not write",
        )],
    );
    let error = collaboration::install_snapshot(&pool, head_regression)
        .await
        .unwrap_err()
        .to_string();
    assert!(error.contains("SNAPSHOT_HEAD_REGRESSION"));

    let mut identity_fork = install_request(
        SnapshotInstallMode::Join,
        "guard-session",
        12,
        3,
        vec![remote_log(
            "guard-session",
            "guard-log",
            3,
            "must not write",
        )],
    );
    identity_fork.account_id = "other-account".to_string();
    identity_fork.membership.user_id = "other-account".to_string();
    let error = collaboration::install_snapshot(&pool, identity_fork)
        .await
        .unwrap_err()
        .to_string();
    assert!(error.contains("BINDING_IDENTITY_CONFLICT"));

    let after: (String, String, i64, i64, i64, String, Option<String>) = sqlx::query_as(
        "SELECT s.title, b.role, b.membership_version, b.last_applied_seq,
                b.last_seen_head_seq, e.server_json, l.remarks
         FROM sessions s
         JOIN collaboration_bindings b ON b.session_id = s.session_id
         JOIN entity_shadows e ON e.session_id = s.session_id
              AND e.entity_type = 'log' AND e.entity_id = 'guard-log'
         JOIN logs l ON l.sync_id = 'guard-log'
         WHERE s.session_id = 'guard-session'",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(after, before);
}

#[tokio::test]
async fn accepted_ack_failure_rolls_back_entire_snapshot_reinstall() {
    let pool = test_pool().await;
    collaboration::install_snapshot(
        &pool,
        install_request(
            SnapshotInstallMode::Join,
            "rollback-session",
            3,
            1,
            vec![remote_log(
                "rollback-session",
                "rollback-log",
                1,
                "old canonical",
            )],
        ),
    )
    .await
    .unwrap();
    let base: (String,) = sqlx::query_as(
        "SELECT server_json FROM entity_shadows
         WHERE session_id = 'rollback-session' AND entity_id = 'rollback-log'",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    insert_log_outbox(
        &pool,
        "rollback-session",
        "rollback-root",
        "rollback-log",
        "accepted",
        1,
        Some(&base.0),
        "accepted canonical",
        Some(4),
        None,
    )
    .await;
    sqlx::query(
        "INSERT INTO applied_events (
            server_instance_id, account_id, session_id, event_id,
            event_seq, mutation_id, applied_at
         ) VALUES ('server-1', 'account-1', 'rollback-session',
                   'rollback-old-event', 1, NULL, ?)",
    )
    .bind(NOW)
    .execute(&pool)
    .await
    .unwrap();
    sqlx::query(
        "CREATE TRIGGER fail_accepted_snapshot_ack
         BEFORE DELETE ON sync_outbox WHEN OLD.mutation_id = 'rollback-root'
         BEGIN SELECT RAISE(ABORT, 'injected accepted ack failure'); END",
    )
    .execute(&pool)
    .await
    .unwrap();

    let error = collaboration::install_snapshot(
        &pool,
        install_request(
            SnapshotInstallMode::Join,
            "rollback-session",
            8,
            2,
            vec![remote_log(
                "rollback-session",
                "rollback-log",
                2,
                "accepted canonical",
            )],
        ),
    )
    .await
    .unwrap_err()
    .to_string();
    assert!(error.contains("injected accepted ack failure"));

    let state: (i64, i64, Option<String>, String, i64, i64) = sqlx::query_as(
        "SELECT b.membership_version, b.last_applied_seq, l.remarks,
                e.server_json,
                (SELECT COUNT(*) FROM sync_outbox WHERE mutation_id = 'rollback-root'),
                (SELECT COUNT(*) FROM applied_events
                 WHERE event_id = 'rollback-old-event')
         FROM collaboration_bindings b
         JOIN logs l ON l.session_id = b.session_id AND l.sync_id = 'rollback-log'
         JOIN entity_shadows e ON e.session_id = b.session_id
              AND e.entity_type = 'log' AND e.entity_id = 'rollback-log'
         WHERE b.session_id = 'rollback-session'",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(state.0, 1);
    assert_eq!(state.1, 3);
    assert_eq!(state.2.as_deref(), Some("old canonical"));
    assert!(state.3.contains("old canonical"));
    assert_eq!(state.4, 1);
    assert_eq!(state.5, 1);
}

#[tokio::test]
async fn future_schema_is_rejected_without_rewriting_the_version() {
    let options = SqliteConnectOptions::from_str("sqlite::memory:")
        .unwrap()
        .create_if_missing(true)
        .foreign_keys(true);
    let pool = SqlitePoolOptions::new()
        .max_connections(1)
        .connect_with(options)
        .await
        .unwrap();
    sqlx::query(
        "CREATE TABLE schema_version (version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL)",
    )
    .execute(&pool)
    .await
    .unwrap();
    sqlx::query("INSERT INTO schema_version (version, applied_at) VALUES (8, ?)")
        .bind(NOW)
        .execute(&pool)
        .await
        .unwrap();

    let error = migrations::run(&pool).await.unwrap_err().to_string();
    assert!(error.contains("DATABASE_SCHEMA_TOO_NEW"));
    let version: (i64,) = sqlx::query_as("SELECT version FROM schema_version")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(version.0, 8);
}
