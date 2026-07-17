use openlogtool_core::api::sessions;
use openlogtool_core::db::{collaboration, logs};
use openlogtool_core::models::log_entry::LogEntry;
use openlogtool_core::{get_db, init_database};

const NOW: &str = "2026-07-11T08:00:00Z";

fn assert_read_only(error: anyhow::Error) {
    assert!(
        error
            .to_string()
            .contains("COLLABORATION_SESSION_READ_ONLY"),
        "unexpected error: {error}"
    );
}

#[tokio::test]
async fn publishing_lease_blocks_all_local_writes_and_abort_restores_them() {
    let database_path = std::env::temp_dir().join(format!(
        "openlogtool-collaboration-write-guards-{}.db",
        uuid::Uuid::new_v4()
    ));
    init_database(database_path.to_str().unwrap())
        .await
        .unwrap();
    let pool = get_db().unwrap();
    sqlx::query(
        "INSERT INTO sessions (
            session_id, title, status, share_code, created_at, updated_at
         ) VALUES ('publish-local', 'Local publish', 'active', NULL, ?, ?)",
    )
    .bind(NOW)
    .bind(NOW)
    .execute(pool)
    .await
    .unwrap();

    let mut first = LogEntry::new(
        "publish-local".to_string(),
        "BG5CRL".to_string(),
        "BA4AAA".to_string(),
    );
    first.sync_id = "first-log".to_string();
    first.remarks = Some("before lease".to_string());
    logs::insert_log(&first).await.unwrap();

    let snapshot = collaboration::begin_publish_snapshot(
        pool,
        "publish-server",
        "https://publish.example",
        "publish-account",
        "publish-local",
    )
    .await
    .unwrap();
    assert!(snapshot.lease_created);
    assert_eq!(snapshot.logs.len(), 1);
    let recovered = collaboration::begin_publish_snapshot(
        pool,
        "publish-server",
        "https://publish.example/new-origin",
        "publish-account",
        "publish-local",
    )
    .await
    .unwrap();
    assert!(!recovered.lease_created);
    assert_eq!(recovered.logs.len(), 1);
    let identity_error = collaboration::begin_publish_snapshot(
        pool,
        "other-server",
        "https://other.example",
        "other-account",
        "publish-local",
    )
    .await
    .unwrap_err()
    .to_string();
    assert!(identity_error.contains("BINDING_IDENTITY_CONFLICT"));

    let mut second = LogEntry::new(
        "publish-local".to_string(),
        "BG5CRL".to_string(),
        "BA4BBB".to_string(),
    );
    second.sync_id = "second-log".to_string();
    assert_read_only(logs::insert_log(&second).await.unwrap_err());
    assert_read_only(
        logs::update_log(
            "first-log",
            "BG5CRL",
            "BA4CCC",
            NOW,
            None,
            None,
            None,
            None,
            None,
            None,
            None,
            Some("blocked"),
        )
        .await
        .unwrap_err(),
    );
    assert_read_only(logs::soft_delete_log("first-log").await.unwrap_err());
    assert_read_only(logs::undo_last_log("publish-local").await.unwrap_err());
    assert_read_only(
        sessions::close_session("publish-local".to_string())
            .await
            .unwrap_err(),
    );

    let stored: (String, Option<String>) =
        sqlx::query_as("SELECT callsign, remarks FROM logs WHERE sync_id = 'first-log'")
            .fetch_one(pool)
            .await
            .unwrap();
    assert_eq!(stored.0, "BA4AAA");
    assert_eq!(stored.1.as_deref(), Some("before lease"));
    let status: (String,) =
        sqlx::query_as("SELECT status FROM sessions WHERE session_id = 'publish-local'")
            .fetch_one(pool)
            .await
            .unwrap();
    assert_eq!(status.0, "active");

    let abort_identity_error =
        collaboration::abort_publish(pool, "other-server", "other-account", "publish-local")
            .await
            .unwrap_err()
            .to_string();
    assert!(abort_identity_error.contains("BINDING_IDENTITY_CONFLICT"));
    collaboration::abort_publish(pool, "publish-server", "publish-account", "publish-local")
        .await
        .unwrap();
    collaboration::abort_publish(pool, "publish-server", "publish-account", "publish-local")
        .await
        .unwrap();

    logs::insert_log(&second).await.unwrap();
    sessions::close_session("publish-local".to_string())
        .await
        .unwrap();
    let final_count: (i64,) =
        sqlx::query_as("SELECT COUNT(*) FROM logs WHERE session_id = 'publish-local'")
            .fetch_one(pool)
            .await
            .unwrap();
    assert_eq!(final_count.0, 2);

    pool.close().await;
    let _ = std::fs::remove_file(database_path);
}
