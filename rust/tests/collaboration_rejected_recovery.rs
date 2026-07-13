use openlogtool_core::api::sessions;
use openlogtool_core::db::{collaboration, logs};
use openlogtool_core::models::collaboration::{
    ApplyEventRequest, CanonicalEvent, CollaborationRole, CollaborationSnapshot,
    InstallSnapshotRequest, RemoteLog, RemoteMembership, RemoteSession, SnapshotInstallMode,
};
use openlogtool_core::models::log_entry::LogEntry;
use openlogtool_core::{get_db, init_database};

const SERVER: &str = "rejected-server";
const ACCOUNT: &str = "rejected-account";
const SESSION: &str = "rejected-session";
const NOW: &str = "2026-07-12T10:00:00Z";

fn remote_log(sync_id: &str, version: i64, remarks: &str, deleted: bool) -> RemoteLog {
    RemoteLog {
        sync_id: sync_id.to_string(),
        session_id: SESSION.to_string(),
        version,
        time: NOW.to_string(),
        controller: "BG5CRL".to_string(),
        callsign: match sync_id {
            "update-log" => "BA4UPD",
            "delete-log" => "BA4DEL",
            "restore-log" => "BA4RST",
            _ => "BA4NEW",
        }
        .to_string(),
        rst_sent: Some("59".to_string()),
        rst_rcvd: Some("57".to_string()),
        qth: Some("上海".to_string()),
        device: Some("IC-705".to_string()),
        power: Some("10W".to_string()),
        antenna: Some("DP".to_string()),
        height: Some("8m".to_string()),
        remarks: Some(remarks.to_string()),
        created_at: NOW.to_string(),
        updated_at: NOW.to_string(),
        deleted_at: deleted.then(|| NOW.to_string()),
    }
}

fn install_request() -> InstallSnapshotRequest {
    InstallSnapshotRequest {
        mode: SnapshotInstallMode::Join,
        server_instance_id: SERVER.to_string(),
        server_origin: "https://rejected.example".to_string(),
        account_id: ACCOUNT.to_string(),
        membership: RemoteMembership {
            membership_id: "rejected-membership".to_string(),
            session_id: SESSION.to_string(),
            user_id: ACCOUNT.to_string(),
            role: CollaborationRole::Owner,
            version: 1,
            joined_at: NOW.to_string(),
            updated_at: NOW.to_string(),
            removed_at: None,
        },
        snapshot: CollaborationSnapshot {
            protocol_version: 1,
            includes_deleted_logs: true,
            session: RemoteSession {
                session_id: SESSION.to_string(),
                title: "Rejected recovery".to_string(),
                status: "active".to_string(),
                version: 1,
                role: CollaborationRole::Owner,
                high_watermark_seq: 0,
                created_at: NOW.to_string(),
                updated_at: NOW.to_string(),
                closed_at: None,
                deleted_at: None,
            },
            high_watermark_seq: 0,
            logs: vec![
                remote_log("update-log", 1, "update base", false),
                remote_log("delete-log", 1, "delete base", false),
                remote_log("restore-log", 1, "restore base", false),
            ],
        },
    }
}

fn event(
    event_id: &str,
    seq: i64,
    event_type: &str,
    log: RemoteLog,
    mutation_id: Option<String>,
) -> ApplyEventRequest {
    ApplyEventRequest {
        server_instance_id: SERVER.to_string(),
        account_id: ACCOUNT.to_string(),
        event: CanonicalEvent {
            protocol_version: 1,
            event_id: event_id.to_string(),
            session_id: SESSION.to_string(),
            seq,
            event_type: event_type.to_string(),
            entity_type: "log".to_string(),
            entity_id: log.sync_id.clone(),
            entity_version: log.version,
            mutation_id,
            occurred_at: NOW.to_string(),
            payload: serde_json::to_value(log).unwrap(),
        },
    }
}

fn session_event(
    event_id: &str,
    seq: i64,
    event_type: &str,
    status: &str,
    version: i64,
    mutation_id: String,
) -> ApplyEventRequest {
    ApplyEventRequest {
        server_instance_id: SERVER.to_string(),
        account_id: ACCOUNT.to_string(),
        event: CanonicalEvent {
            protocol_version: 1,
            event_id: event_id.to_string(),
            session_id: SESSION.to_string(),
            seq,
            event_type: event_type.to_string(),
            entity_type: "session".to_string(),
            entity_id: SESSION.to_string(),
            entity_version: version,
            mutation_id: Some(mutation_id),
            occurred_at: NOW.to_string(),
            payload: serde_json::json!({
                "sessionId": SESSION,
                "title": "Rejected recovery",
                "status": status,
                "version": version,
                "createdAt": NOW,
                "updatedAt": NOW,
                "closedAt": if status == "closed" { Some(NOW) } else { None },
                "deletedAt": null,
            }),
        },
    }
}

async fn only_operation(pool: &sqlx::SqlitePool) -> serde_json::Value {
    let batch = collaboration::list_pending_mutations(pool, SERVER, ACCOUNT, SESSION, 100)
        .await
        .unwrap();
    let operations = batch["operations"].as_array().unwrap();
    assert_eq!(operations.len(), 1, "unexpected batch: {batch}");
    operations[0].clone()
}

async fn reject(pool: &sqlx::SqlitePool, mutation_id: &str) {
    collaboration::mark_mutation_rejected(
        pool,
        SERVER,
        ACCOUNT,
        SESSION,
        mutation_id,
        "VALIDATION_FAILED",
        "permanent rejection",
        Some(r#"{"field":"remarks"}"#),
    )
    .await
    .unwrap();
}

async fn accept(
    pool: &sqlx::SqlitePool,
    mutation_id: &str,
    seq: i64,
    event_type: &str,
    canonical: RemoteLog,
) {
    collaboration::mark_mutation_accepted(pool, SERVER, ACCOUNT, SESSION, mutation_id, seq)
        .await
        .unwrap();
    collaboration::apply_event(
        pool,
        event(
            &format!("accepted-event-{seq}"),
            seq,
            event_type,
            canonical,
            Some(mutation_id.to_string()),
        ),
    )
    .await
    .unwrap();
}

#[tokio::test]
async fn rejected_chains_are_atomically_rebuilt_from_canonical_on_reedit() {
    let database_path = std::env::temp_dir().join(format!(
        "openlogtool-rejected-recovery-{}.db",
        uuid::Uuid::new_v4()
    ));
    init_database(database_path.to_str().unwrap())
        .await
        .unwrap();
    let pool = get_db().unwrap();
    collaboration::install_snapshot(pool, install_request())
        .await
        .unwrap();

    collaboration::apply_event(
        pool,
        event(
            "remote-delete-restore-log",
            1,
            "log.deleted",
            remote_log("restore-log", 2, "restore base", true),
            None,
        ),
    )
    .await
    .unwrap();

    // Rejected update -> a later edit becomes one fresh update from shadow.
    logs::update_log(
        "update-log",
        "BG5CRL",
        "BA4UPD",
        NOW,
        Some("59"),
        Some("57"),
        Some("上海"),
        Some("IC-705"),
        Some("10W"),
        Some("DP"),
        Some("8m"),
        Some("rejected update"),
    )
    .await
    .unwrap();
    let rejected_update = only_operation(pool).await;
    let rejected_update_id = rejected_update["mutationId"].as_str().unwrap().to_string();
    reject(pool, &rejected_update_id).await;
    // Simulate a chain persisted by the pre-fix implementation: it appended a
    // pending edit behind a permanently rejected root, which list could never
    // reach. Recovery must remove both rows, not merely clear the dependency.
    sqlx::query(
        "INSERT INTO sync_outbox (
            server_instance_id, account_id, session_id, mutation_id,
            entity_type, entity_id, operation, base_version, observed_seq,
            base_json, payload_json, state, attempts, depends_on_mutation_id,
            created_at, updated_at
         )
         SELECT server_instance_id, account_id, session_id,
                '00000000-0000-4000-8000-000000000099',
                entity_type, entity_id, 'update', base_version, observed_seq,
                base_json, '{\"patch\":{\"remarks\":\"stale downstream\"}}',
                'pending', 0, mutation_id, ?, ?
         FROM sync_outbox WHERE mutation_id = ?",
    )
    .bind(NOW)
    .bind(NOW)
    .bind(&rejected_update_id)
    .execute(pool)
    .await
    .unwrap();
    assert_eq!(
        collaboration::get_sync_status(pool, SERVER, ACCOUNT, SESSION)
            .await
            .unwrap()
            .rejected_count,
        1
    );
    sqlx::query(
        "CREATE TRIGGER fail_corrected_requeue
         BEFORE INSERT ON sync_outbox
         WHEN NEW.payload_json LIKE '%corrected update%'
         BEGIN SELECT RAISE(ABORT, 'injected corrected requeue failure'); END",
    )
    .execute(pool)
    .await
    .unwrap();
    assert!(logs::update_log(
        "update-log",
        "BG5CRL",
        "BA4UPD",
        NOW,
        Some("59"),
        Some("57"),
        Some("上海"),
        Some("IC-705"),
        Some("10W"),
        Some("DP"),
        Some("8m"),
        Some("corrected update"),
    )
    .await
    .unwrap_err()
    .to_string()
    .contains("injected corrected requeue failure"));
    let rolled_back_recovery: (i64, Option<String>) = sqlx::query_as(
        "SELECT
            (SELECT COUNT(*) FROM sync_outbox WHERE entity_id = 'update-log'),
            (SELECT remarks FROM logs WHERE sync_id = 'update-log')",
    )
    .fetch_one(pool)
    .await
    .unwrap();
    assert_eq!(rolled_back_recovery.0, 2);
    assert_eq!(rolled_back_recovery.1.as_deref(), Some("rejected update"));
    sqlx::query("DROP TRIGGER fail_corrected_requeue")
        .execute(pool)
        .await
        .unwrap();
    logs::update_log(
        "update-log",
        "BG5CRL",
        "BA4UPD",
        NOW,
        Some("59"),
        Some("57"),
        Some("上海"),
        Some("IC-705"),
        Some("10W"),
        Some("DP"),
        Some("8m"),
        Some("corrected update"),
    )
    .await
    .unwrap();
    let corrected_update = only_operation(pool).await;
    let corrected_update_id = corrected_update["mutationId"].as_str().unwrap().to_string();
    assert_ne!(corrected_update_id, rejected_update_id);
    assert_eq!(corrected_update["operation"], "update");
    assert_eq!(corrected_update["baseVersion"], 1);
    assert_eq!(corrected_update["patch"]["remarks"], "corrected update");
    assert_eq!(
        sqlx::query_as::<_, (i64,)>("SELECT COUNT(*) FROM sync_outbox WHERE mutation_id = ?")
            .bind(&rejected_update_id)
            .fetch_one(pool)
            .await
            .unwrap()
            .0,
        0
    );
    assert_eq!(
        sqlx::query_as::<_, (i64,)>(
            "SELECT COUNT(*) FROM sync_outbox
             WHERE mutation_id = '00000000-0000-4000-8000-000000000099'",
        )
        .fetch_one(pool)
        .await
        .unwrap()
        .0,
        0
    );
    accept(
        pool,
        &corrected_update_id,
        2,
        "log.updated",
        remote_log("update-log", 2, "corrected update", false),
    )
    .await;

    // Rejected create -> editing must remain create/baseVersion 0 with a new ID.
    let mut created = LogEntry::new(
        SESSION.to_string(),
        "BG5CRL".to_string(),
        "BA4NEW".to_string(),
    );
    created.sync_id = "created-log".to_string();
    created.time = NOW.to_string();
    created.remarks = Some("rejected create".to_string());
    logs::insert_log(&created).await.unwrap();
    let rejected_create = only_operation(pool).await;
    let rejected_create_id = rejected_create["mutationId"].as_str().unwrap().to_string();
    reject(pool, &rejected_create_id).await;
    logs::update_log(
        "created-log",
        "BG5CRL",
        "BA4NEW",
        NOW,
        None,
        None,
        None,
        None,
        None,
        None,
        None,
        Some("corrected create"),
    )
    .await
    .unwrap();
    let corrected_create = only_operation(pool).await;
    let corrected_create_id = corrected_create["mutationId"].as_str().unwrap().to_string();
    assert_ne!(corrected_create_id, rejected_create_id);
    assert_eq!(corrected_create["operation"], "create");
    assert_eq!(corrected_create["baseVersion"], 0);
    assert_eq!(corrected_create["value"]["remarks"], "corrected create");
    accept(
        pool,
        &corrected_create_id,
        3,
        "log.created",
        remote_log("created-log", 1, "corrected create", false),
    )
    .await;

    // Rejected delete -> restore cancels the stale delete; a later edit is a
    // fresh update based on the active canonical row.
    logs::soft_delete_log("delete-log").await.unwrap();
    let rejected_delete = only_operation(pool).await;
    let rejected_delete_id = rejected_delete["mutationId"].as_str().unwrap().to_string();
    reject(pool, &rejected_delete_id).await;
    logs::restore_log("delete-log").await.unwrap();
    assert_eq!(
        sqlx::query_as::<_, (i64,)>("SELECT COUNT(*) FROM sync_outbox")
            .fetch_one(pool)
            .await
            .unwrap()
            .0,
        0
    );
    logs::update_log(
        "delete-log",
        "BG5CRL",
        "BA4DEL",
        NOW,
        Some("59"),
        Some("57"),
        Some("上海"),
        Some("IC-705"),
        Some("10W"),
        Some("DP"),
        Some("8m"),
        Some("corrected after delete"),
    )
    .await
    .unwrap();
    let corrected_after_delete = only_operation(pool).await;
    let corrected_after_delete_id = corrected_after_delete["mutationId"]
        .as_str()
        .unwrap()
        .to_string();
    assert_eq!(corrected_after_delete["operation"], "update");
    accept(
        pool,
        &corrected_after_delete_id,
        4,
        "log.updated",
        remote_log("delete-log", 2, "corrected after delete", false),
    )
    .await;

    // Rejected restore -> editing the locally restored row creates a fresh
    // restore against the canonical tombstone, never an update/baseVersion 0.
    logs::restore_log("restore-log").await.unwrap();
    let rejected_restore = only_operation(pool).await;
    let rejected_restore_id = rejected_restore["mutationId"].as_str().unwrap().to_string();
    reject(pool, &rejected_restore_id).await;
    // Member snapshots omit tombstones. If a reinstall removed the shadow,
    // recovery must use the rejected mutation's canonical base rather than
    // misclassifying this as a brand-new create.
    sqlx::query(
        "DELETE FROM entity_shadows
         WHERE session_id = ? AND entity_type = 'log' AND entity_id = 'restore-log'",
    )
    .bind(SESSION)
    .execute(pool)
    .await
    .unwrap();
    logs::update_log(
        "restore-log",
        "BG5CRL",
        "BA4RST",
        NOW,
        Some("59"),
        Some("57"),
        Some("上海"),
        Some("IC-705"),
        Some("10W"),
        Some("DP"),
        Some("8m"),
        Some("corrected restore"),
    )
    .await
    .unwrap();
    let corrected_restore = only_operation(pool).await;
    let corrected_restore_id = corrected_restore["mutationId"]
        .as_str()
        .unwrap()
        .to_string();
    assert_ne!(corrected_restore_id, rejected_restore_id);
    assert_eq!(corrected_restore["operation"], "restore");
    assert_eq!(corrected_restore["baseVersion"], 2);
    assert_eq!(corrected_restore["value"]["remarks"], "corrected restore");
    accept(
        pool,
        &corrected_restore_id,
        5,
        "log.restored",
        remote_log("restore-log", 3, "corrected restore", false),
    )
    .await;

    // Session recovery follows the newest action only. A rejected title edit
    // followed by close must not smuggle the rejected title into the close.
    collaboration::update_session_title(pool, SESSION, "rejected title")
        .await
        .unwrap();
    let rejected_title = only_operation(pool).await;
    let rejected_title_id = rejected_title["mutationId"].as_str().unwrap().to_string();
    reject(pool, &rejected_title_id).await;
    sessions::close_session(SESSION.to_string()).await.unwrap();
    let corrected_close = only_operation(pool).await;
    let corrected_close_id = corrected_close["mutationId"].as_str().unwrap().to_string();
    assert_ne!(corrected_close_id, rejected_title_id);
    assert_eq!(corrected_close["entityType"], "session");
    assert_eq!(corrected_close["operation"], "close");
    assert!(corrected_close.get("patch").is_none());
    assert_eq!(
        sqlx::query_as::<_, (i64,)>("SELECT COUNT(*) FROM sync_outbox WHERE mutation_id = ?")
            .bind(&rejected_title_id)
            .fetch_one(pool)
            .await
            .unwrap()
            .0,
        0
    );
    collaboration::mark_mutation_accepted(pool, SERVER, ACCOUNT, SESSION, &corrected_close_id, 6)
        .await
        .unwrap();
    collaboration::apply_event(
        pool,
        session_event(
            "accepted-session-close-6",
            6,
            "session.closed",
            "closed",
            2,
            corrected_close_id,
        ),
    )
    .await
    .unwrap();
    let canonical_title: (String,) =
        sqlx::query_as("SELECT title FROM sessions WHERE session_id = ?")
            .bind(SESSION)
            .fetch_one(pool)
            .await
            .unwrap();
    assert_eq!(canonical_title.0, "Rejected recovery");

    let status = collaboration::get_sync_status(pool, SERVER, ACCOUNT, SESSION)
        .await
        .unwrap();
    assert_eq!(status.last_applied_seq, 6);
    assert_eq!(status.pending_count, 0);
    assert_eq!(status.rejected_count, 0);
    assert_eq!(status.conflict_count, 0);
    let remarks: Vec<(String, Option<String>)> =
        sqlx::query_as("SELECT sync_id, remarks FROM logs WHERE session_id = ? ORDER BY sync_id")
            .bind(SESSION)
            .fetch_all(pool)
            .await
            .unwrap();
    assert!(remarks.contains(&(
        "created-log".to_string(),
        Some("corrected create".to_string())
    )));
    assert!(remarks.contains(&(
        "restore-log".to_string(),
        Some("corrected restore".to_string())
    )));
    assert!(remarks.contains(&(
        "update-log".to_string(),
        Some("corrected update".to_string())
    )));

    pool.close().await;
    let _ = std::fs::remove_file(database_path);
}
