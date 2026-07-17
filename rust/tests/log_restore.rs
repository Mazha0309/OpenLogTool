use openlogtool_core::db::logs;
use openlogtool_core::models::log_entry::LogEntry;
use openlogtool_core::{get_db, init_database};

const NOW: &str = "2026-07-13T08:00:00Z";

async fn insert_log(sync_id: &str, time: &str) {
    let mut entry = LogEntry::new(
        "active-local".to_string(),
        "BG5CRL".to_string(),
        sync_id.to_string(),
    );
    entry.sync_id = sync_id.to_string();
    entry.time = time.to_string();
    logs::insert_log(&entry).await.unwrap();
}

#[tokio::test]
async fn restore_targets_the_deleted_sync_id_and_keeps_the_latest_log() {
    let database_path = std::env::temp_dir().join(format!(
        "openlogtool-log-restore-{}.db",
        uuid::Uuid::new_v4()
    ));
    init_database(database_path.to_str().unwrap())
        .await
        .unwrap();
    let pool = get_db().unwrap();
    sqlx::query(
        "INSERT INTO sessions (
            session_id, title, status, created_at, updated_at
         ) VALUES ('active-local', 'Active local', 'active', ?, ?)",
    )
    .bind(NOW)
    .bind(NOW)
    .execute(pool)
    .await
    .unwrap();

    insert_log("deleted-target", "2026-07-13T08:01:00Z").await;
    insert_log("latest-active", "2026-07-13T08:02:00Z").await;
    logs::soft_delete_log("deleted-target").await.unwrap();

    let restored = logs::restore_log("deleted-target").await.unwrap();

    assert_eq!(restored.sync_id, "deleted-target");
    let rows: Vec<(String, Option<String>)> = sqlx::query_as(
        "SELECT sync_id, deleted_at FROM logs
         WHERE session_id = 'active-local' ORDER BY id",
    )
    .fetch_all(pool)
    .await
    .unwrap();
    assert_eq!(
        rows,
        vec![
            ("deleted-target".to_string(), None),
            ("latest-active".to_string(), None),
        ]
    );

    pool.close().await;
    let _ = std::fs::remove_file(database_path);
}
