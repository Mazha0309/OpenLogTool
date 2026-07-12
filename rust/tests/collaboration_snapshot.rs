use openlogtool_core::db::{collaboration, migrations};
use openlogtool_core::models::collaboration::{
    CollaborationRole, CollaborationSnapshot, InstallSnapshotRequest, RemoteLog, RemoteMembership,
    RemoteSession, SnapshotInstallMode,
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

    let request = install_request(
        SnapshotInstallMode::Publish,
        "session-1",
        7,
        1,
        vec![remote_log("session-1", "log-1", 3, "服务端备注")],
    );
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
    assert_eq!(version_rows, (1, 5));
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
    sqlx::query("INSERT INTO schema_version (version, applied_at) VALUES (6, ?)")
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
    assert_eq!(version.0, 6);
}
