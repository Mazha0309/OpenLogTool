use openlogtool_core::api::sessions;
use openlogtool_core::db::logs;
use openlogtool_core::models::log_entry::LogEntry;
use openlogtool_core::{get_db, init_database};

const NOW: &str = "2026-07-13T08:00:00Z";

fn assert_session_closed(error: anyhow::Error) {
    assert!(
        error.to_string().contains("SESSION_CLOSED"),
        "unexpected error: {error}"
    );
}

async fn insert_log(sync_id: &str, callsign: &str, remarks: &str) {
    let mut entry = LogEntry::new(
        "closed-local".to_string(),
        "BG5CRL".to_string(),
        callsign.to_string(),
    );
    entry.sync_id = sync_id.to_string();
    entry.time = NOW.to_string();
    entry.remarks = Some(remarks.to_string());
    logs::insert_log(&entry).await.unwrap();
}

#[tokio::test]
async fn closed_local_session_rejects_every_log_mutation_without_changing_rows() {
    let database_path = std::env::temp_dir().join(format!(
        "openlogtool-local-log-write-guards-{}.db",
        uuid::Uuid::new_v4()
    ));
    init_database(database_path.to_str().unwrap())
        .await
        .unwrap();
    let pool = get_db().unwrap();
    sqlx::query(
        "INSERT INTO sessions (
            session_id, title, status, created_at, updated_at
         ) VALUES ('closed-local', 'Closed local', 'active', ?, ?)",
    )
    .bind(NOW)
    .bind(NOW)
    .execute(pool)
    .await
    .unwrap();

    insert_log("update-log", "BA4AAA", "keep update").await;
    insert_log("delete-log", "BA4BBB", "keep delete").await;
    insert_log("restore-log", "BA4CCC", "keep deleted").await;
    logs::soft_delete_log("restore-log").await.unwrap();
    insert_log("undo-log", "BA4DDD", "keep latest").await;

    let before: Vec<(String, String, Option<String>, String, Option<String>)> = sqlx::query_as(
        "SELECT sync_id, callsign, remarks, updated_at, deleted_at
         FROM logs WHERE session_id = 'closed-local' ORDER BY id",
    )
    .fetch_all(pool)
    .await
    .unwrap();

    sessions::close_session("closed-local".to_string())
        .await
        .unwrap();

    assert_session_closed(
        logs::update_log(
            "update-log",
            "BG5CRL",
            "BA4ZZZ",
            "2026-07-13T09:00:00Z",
            None,
            None,
            None,
            None,
            None,
            None,
            None,
            Some("must not persist"),
        )
        .await
        .unwrap_err(),
    );
    assert_session_closed(logs::soft_delete_log("delete-log").await.unwrap_err());
    assert_session_closed(logs::undo_last_log("closed-local").await.unwrap_err());
    assert_session_closed(logs::restore_log("restore-log").await.unwrap_err());

    let after: Vec<(String, String, Option<String>, String, Option<String>)> = sqlx::query_as(
        "SELECT sync_id, callsign, remarks, updated_at, deleted_at
         FROM logs WHERE session_id = 'closed-local' ORDER BY id",
    )
    .fetch_all(pool)
    .await
    .unwrap();
    assert_eq!(after, before);

    pool.close().await;
    let _ = std::fs::remove_file(database_path);
}
