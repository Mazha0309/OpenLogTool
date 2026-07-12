use openlogtool_core::api::sessions;
use openlogtool_core::db::{collaboration, logs};
use openlogtool_core::models::collaboration::{
    ApplyEventRequest, CanonicalEvent, CollaborationRole, CollaborationSnapshot,
    InstallSnapshotRequest, MutationConflictRequest, MutationFailureRequest, RemoteLog,
    RemoteMembership, RemoteSession, SnapshotInstallMode,
};
use openlogtool_core::models::log_entry::LogEntry;
use openlogtool_core::{get_db, init_database};
use serde_json::{json, Value};

const SERVER: &str = "replica-server";
const ACCOUNT: &str = "replica-account";
const SESSION: &str = "replica-session";
const NOW: &str = "2026-07-12T08:00:00Z";

fn remote_log(sync_id: &str, version: i64, remarks: &str) -> RemoteLog {
    RemoteLog {
        sync_id: sync_id.to_string(),
        session_id: SESSION.to_string(),
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
        updated_at: NOW.to_string(),
        deleted_at: None,
    }
}

fn install_request() -> InstallSnapshotRequest {
    InstallSnapshotRequest {
        mode: SnapshotInstallMode::Join,
        server_instance_id: SERVER.to_string(),
        server_origin: "https://replica.example".to_string(),
        account_id: ACCOUNT.to_string(),
        membership: RemoteMembership {
            membership_id: "membership-owner".to_string(),
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
                title: "Replica".to_string(),
                status: "active".to_string(),
                version: 1,
                role: CollaborationRole::Owner,
                high_watermark_seq: 5,
                created_at: NOW.to_string(),
                updated_at: NOW.to_string(),
                closed_at: None,
                deleted_at: None,
            },
            high_watermark_seq: 5,
            logs: vec![
                remote_log("remote-log", 1, "base"),
                remote_log("undo-log", 1, "unchanged"),
                remote_log("time-log", 1, "time base"),
            ],
        },
    }
}

fn log_event(
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
            entity_type: "session".to_string(),
            entity_id: SESSION.to_string(),
            entity_version: version,
            mutation_id,
            occurred_at: NOW.to_string(),
            payload: json!({
                "sessionId": SESSION,
                "title": "Replica",
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

async fn outbox_mutation(pool: &sqlx::SqlitePool, entity_id: &str, offset: i64) -> String {
    let row: (String,) = sqlx::query_as(
        "SELECT mutation_id FROM sync_outbox
         WHERE session_id = ? AND entity_id = ? ORDER BY local_seq LIMIT 1 OFFSET ?",
    )
    .bind(SESSION)
    .bind(entity_id)
    .bind(offset)
    .fetch_one(pool)
    .await
    .unwrap();
    row.0
}

#[tokio::test]
async fn stage2_outbox_event_cursor_conflict_and_write_policy_are_atomic() {
    let database_path = std::env::temp_dir().join(format!(
        "openlogtool-collaboration-replica-{}.db",
        uuid::Uuid::new_v4()
    ));
    init_database(database_path.to_str().unwrap())
        .await
        .unwrap();
    let pool = get_db().unwrap();
    collaboration::install_snapshot(pool, install_request())
        .await
        .unwrap();

    logs::update_log(
        "remote-log",
        "BG5CRL",
        "BA4AAA",
        NOW,
        Some("59"),
        Some("57"),
        Some("上海"),
        Some("IC-705"),
        Some("10W"),
        Some("DP"),
        Some("8m"),
        Some("first local"),
    )
    .await
    .unwrap();
    let first_mutation = outbox_mutation(pool, "remote-log", 0).await;
    let batch = collaboration::list_pending_mutations(pool, SERVER, ACCOUNT, SESSION, 100)
        .await
        .unwrap();
    assert_eq!(batch["protocolVersion"], 1);
    assert_eq!(batch["operations"][0]["mutationId"], first_mutation);
    assert_eq!(batch["operations"][0]["patch"]["remarks"], "first local");
    assert!(batch["operations"][0].get("payloadJson").is_none());

    collaboration::mark_mutations_sending(
        pool,
        SERVER,
        ACCOUNT,
        SESSION,
        std::slice::from_ref(&first_mutation),
    )
    .await
    .unwrap();
    let claimed_once: (String, i64) =
        sqlx::query_as("SELECT state, attempts FROM sync_outbox WHERE mutation_id = ?")
            .bind(&first_mutation)
            .fetch_one(pool)
            .await
            .unwrap();
    assert_eq!(claimed_once, ("sending".to_string(), 1));
    logs::update_log(
        "remote-log",
        "BG5CRL",
        "BA4AAA",
        NOW,
        Some("59"),
        Some("57"),
        Some("上海"),
        Some("IC-705"),
        Some("10W"),
        Some("DP"),
        Some("8m"),
        Some("second local"),
    )
    .await
    .unwrap();
    let second_mutation = outbox_mutation(pool, "remote-log", 1).await;
    let dependency: (Option<String>, i64) = sqlx::query_as(
        "SELECT depends_on_mutation_id, base_version FROM sync_outbox WHERE mutation_id = ?",
    )
    .bind(&second_mutation)
    .fetch_one(pool)
    .await
    .unwrap();
    assert_eq!(dependency.0.as_deref(), Some(first_mutation.as_str()));
    assert_eq!(dependency.1, 1);

    let accepted_log = remote_log("remote-log", 2, "first local");
    let event = log_event(
        "event-6",
        6,
        "log.updated",
        accepted_log,
        Some(first_mutation.clone()),
    );
    let applied = collaboration::apply_event(pool, event.clone())
        .await
        .unwrap();
    assert_eq!(applied.outcome, "applied");
    assert_eq!(applied.cursor, 6);
    let local_remarks: (Option<String>,) =
        sqlx::query_as("SELECT remarks FROM logs WHERE sync_id = 'remote-log'")
            .fetch_one(pool)
            .await
            .unwrap();
    assert_eq!(local_remarks.0.as_deref(), Some("second local"));
    let rebased: (Option<String>, i64, String) = sqlx::query_as(
        "SELECT depends_on_mutation_id, base_version, base_json
         FROM sync_outbox WHERE mutation_id = ?",
    )
    .bind(&second_mutation)
    .fetch_one(pool)
    .await
    .unwrap();
    assert!(rebased.0.is_none());
    assert_eq!(rebased.1, 2);
    assert!(rebased.2.contains("first local"));

    // REST ACK may arrive after the event echo. It must be an idempotent no-op.
    collaboration::mark_mutation_accepted(pool, SERVER, ACCOUNT, SESSION, &first_mutation, 6)
        .await
        .unwrap();
    let duplicate = collaboration::apply_event(pool, event).await.unwrap();
    assert_eq!(duplicate.outcome, "duplicate");
    let fork = log_event(
        "different-event-6",
        6,
        "log.updated",
        remote_log("remote-log", 2, "first local"),
        None,
    );
    assert!(collaboration::apply_event(pool, fork)
        .await
        .unwrap_err()
        .to_string()
        .contains("EVENT_SEQUENCE_FORK"));
    let gap = log_event(
        "event-8-gap",
        8,
        "log.updated",
        remote_log("remote-log", 3, "remote gap"),
        None,
    );
    let gap_result = collaboration::apply_event(pool, gap).await.unwrap();
    assert_eq!(gap_result.outcome, "gap");
    assert_eq!(gap_result.cursor, 6);
    let cursor: (i64,) =
        sqlx::query_as("SELECT last_applied_seq FROM collaboration_bindings WHERE session_id = ?")
            .bind(SESSION)
            .fetch_one(pool)
            .await
            .unwrap();
    assert_eq!(cursor.0, 6);

    collaboration::record_mutation_conflict(
        pool,
        MutationConflictRequest {
            server_instance_id: SERVER.to_string(),
            account_id: ACCOUNT.to_string(),
            session_id: SESSION.to_string(),
            mutation_id: second_mutation.clone(),
            current_version: 3,
            current_entity: serde_json::to_value(remote_log("remote-log", 3, "remote edit"))
                .unwrap(),
        },
    )
    .await
    .unwrap();
    let conflict: (String, String) = sqlx::query_as(
        "SELECT state, conflicting_fields_json FROM sync_conflicts WHERE mutation_id = ?",
    )
    .bind(&second_mutation)
    .fetch_one(pool)
    .await
    .unwrap();
    assert_eq!(conflict.0, "open");
    assert!(conflict.1.contains("remarks"));

    logs::update_log(
        "time-log",
        "BG5CRL",
        "BA4AAA",
        "09:30",
        Some("59"),
        Some("57"),
        Some("上海"),
        Some("IC-705"),
        Some("10W"),
        Some("DP"),
        Some("8m"),
        Some("time base"),
    )
    .await
    .unwrap();
    let normalized_time: (String,) =
        sqlx::query_as("SELECT payload_json FROM sync_outbox WHERE entity_id = 'time-log'")
            .fetch_one(pool)
            .await
            .unwrap();
    assert!(normalized_time.0.contains("2026-07-12T09:30:00+00:00"));

    logs::soft_delete_log("undo-log").await.unwrap();
    logs::restore_log("undo-log").await.unwrap();
    let cancelled_delete: (i64, Option<String>) = sqlx::query_as(
        "SELECT
            (SELECT COUNT(*) FROM sync_outbox WHERE entity_id = 'undo-log'),
            (SELECT deleted_at FROM logs WHERE sync_id = 'undo-log')",
    )
    .fetch_one(pool)
    .await
    .unwrap();
    assert_eq!(cancelled_delete, (0, None));

    let mut ephemeral = LogEntry::new(
        SESSION.to_string(),
        "BG5CRL".to_string(),
        "BA4TMP".to_string(),
    );
    ephemeral.sync_id = "ephemeral-log".to_string();
    ephemeral.time = NOW.to_string();
    logs::insert_log(&ephemeral).await.unwrap();
    logs::update_log(
        "ephemeral-log",
        "BG5CRL",
        "BA4TMP",
        NOW,
        None,
        None,
        None,
        None,
        None,
        None,
        None,
        Some("merged into create"),
    )
    .await
    .unwrap();
    let merged_create: (i64, String) = sqlx::query_as(
        "SELECT COUNT(*), MAX(payload_json) FROM sync_outbox WHERE entity_id = 'ephemeral-log'",
    )
    .fetch_one(pool)
    .await
    .unwrap();
    assert_eq!(merged_create.0, 1);
    assert!(merged_create.1.contains("merged into create"));
    logs::soft_delete_log("ephemeral-log").await.unwrap();
    let cancelled_create: (i64, i64) = sqlx::query_as(
        "SELECT
            (SELECT COUNT(*) FROM sync_outbox WHERE entity_id = 'ephemeral-log'),
            (SELECT COUNT(*) FROM logs WHERE sync_id = 'ephemeral-log')",
    )
    .fetch_one(pool)
    .await
    .unwrap();
    assert_eq!(cancelled_create, (0, 0));

    // A create that has already been sent can still receive local update/delete
    // commands without a shadow. They are chained behind the stable create ID.
    let mut created = LogEntry::new(
        SESSION.to_string(),
        "BG5CRL".to_string(),
        "BA4BBB".to_string(),
    );
    created.sync_id = "created-log".to_string();
    created.time = NOW.to_string();
    created.remarks = Some("created".to_string());
    logs::insert_log(&created).await.unwrap();
    let create_mutation = outbox_mutation(pool, "created-log", 0).await;
    collaboration::mark_mutations_sending(
        pool,
        SERVER,
        ACCOUNT,
        SESSION,
        std::slice::from_ref(&create_mutation),
    )
    .await
    .unwrap();
    logs::update_log(
        "created-log",
        "BG5CRL",
        "BA4BBB",
        NOW,
        None,
        None,
        None,
        None,
        None,
        None,
        None,
        Some("changed after send"),
    )
    .await
    .unwrap();
    logs::soft_delete_log("created-log").await.unwrap();
    let chained_delete: (String, String, i64, Option<String>) = sqlx::query_as(
        "SELECT mutation_id, operation, base_version, depends_on_mutation_id
         FROM sync_outbox WHERE entity_id = 'created-log' ORDER BY local_seq DESC LIMIT 1",
    )
    .fetch_one(pool)
    .await
    .unwrap();
    assert_eq!(chained_delete.1, "delete");
    assert_eq!(chained_delete.2, 0);
    assert_eq!(chained_delete.3.as_deref(), Some(create_mutation.as_str()));

    let created_event = log_event(
        "event-7",
        7,
        "log.created",
        RemoteLog {
            sync_id: "created-log".to_string(),
            callsign: "BA4BBB".to_string(),
            remarks: Some("created".to_string()),
            ..remote_log("created-log", 1, "created")
        },
        Some(create_mutation),
    );
    collaboration::apply_event(pool, created_event)
        .await
        .unwrap();
    let rebased_delete: (i64, Option<String>, String) = sqlx::query_as(
        "SELECT base_version, depends_on_mutation_id, state
         FROM sync_outbox WHERE mutation_id = ?",
    )
    .bind(&chained_delete.0)
    .fetch_one(pool)
    .await
    .unwrap();
    assert_eq!(rebased_delete.0, 1);
    assert!(rebased_delete.1.is_none());
    let tombstone: (Option<String>,) =
        sqlx::query_as("SELECT deleted_at FROM logs WHERE sync_id = 'created-log'")
            .fetch_one(pool)
            .await
            .unwrap();
    assert!(tombstone.0.is_some());

    // Simulate a crash after marking sending. Listing recovers it with the same ID.
    collaboration::mark_mutations_sending(
        pool,
        SERVER,
        ACCOUNT,
        SESSION,
        std::slice::from_ref(&chained_delete.0),
    )
    .await
    .unwrap();
    let recovered = collaboration::list_pending_mutations(pool, SERVER, ACCOUNT, SESSION, 100)
        .await
        .unwrap();
    let recovered_ids: Vec<&str> = recovered["operations"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|operation| operation["mutationId"].as_str())
        .collect();
    assert!(recovered_ids.contains(&chained_delete.0.as_str()));
    let recovered_state: (String,) =
        sqlx::query_as("SELECT state FROM sync_outbox WHERE mutation_id = ?")
            .bind(&chained_delete.0)
            .fetch_one(pool)
            .await
            .unwrap();
    assert_eq!(recovered_state.0, "sending");
    collaboration::mark_mutation_rejected(
        pool,
        SERVER,
        ACCOUNT,
        SESSION,
        &chained_delete.0,
        "VALIDATION_FAILED",
        "permanent",
        Some(r#"{"field":"remarks"}"#),
    )
    .await
    .unwrap();
    let after_reject = collaboration::list_pending_mutations(pool, SERVER, ACCOUNT, SESSION, 100)
        .await
        .unwrap();
    assert!(!after_reject["operations"]
        .as_array()
        .unwrap()
        .iter()
        .any(|operation| operation["mutationId"] == chained_delete.0));

    let mut invalid_time_log = remote_log("created-log", 2, "invalid time");
    invalid_time_log.time = "not-rfc3339".to_string();
    let invalid_time_event = log_event(
        "event-8-invalid-time",
        8,
        "log.updated",
        invalid_time_log,
        None,
    );
    assert!(collaboration::apply_event(pool, invalid_time_event)
        .await
        .unwrap_err()
        .to_string()
        .contains("EVENT_LOG_TIME_INVALID"));

    sqlx::query(
        "CREATE TRIGGER fail_event_commit
         BEFORE INSERT ON applied_events WHEN NEW.event_seq = 8
         BEGIN SELECT RAISE(ABORT, 'injected event failure'); END",
    )
    .execute(pool)
    .await
    .unwrap();
    let failed_event = log_event(
        "event-8-fails",
        8,
        "log.updated",
        RemoteLog {
            sync_id: "created-log".to_string(),
            callsign: "BA4BBB".to_string(),
            remarks: Some("server version two".to_string()),
            ..remote_log("created-log", 2, "server version two")
        },
        None,
    );
    assert!(collaboration::apply_event(pool, failed_event)
        .await
        .unwrap_err()
        .to_string()
        .contains("injected event failure"));
    let rolled_back: (i64, i64) = sqlx::query_as(
        "SELECT
            (SELECT last_applied_seq FROM collaboration_bindings WHERE session_id = ?),
            (SELECT server_version FROM entity_shadows
             WHERE session_id = ? AND entity_type = 'log' AND entity_id = 'created-log')",
    )
    .bind(SESSION)
    .bind(SESSION)
    .fetch_one(pool)
    .await
    .unwrap();
    assert_eq!(rolled_back, (7, 1));
    sqlx::query("DROP TRIGGER fail_event_commit")
        .execute(pool)
        .await
        .unwrap();

    let time_mutation = outbox_mutation(pool, "time-log", 0).await;
    collaboration::mark_mutations_sending(
        pool,
        SERVER,
        ACCOUNT,
        SESSION,
        std::slice::from_ref(&time_mutation),
    )
    .await
    .unwrap();
    collaboration::mark_mutation_accepted(pool, SERVER, ACCOUNT, SESSION, &time_mutation, 8)
        .await
        .unwrap();
    let accepted_still_durable: (String,) =
        sqlx::query_as("SELECT state FROM sync_outbox WHERE mutation_id = ?")
            .bind(&time_mutation)
            .fetch_one(pool)
            .await
            .unwrap();
    assert_eq!(accepted_still_durable.0, "accepted");
    let mut canonical_time_log = remote_log("time-log", 2, "time base");
    canonical_time_log.time = "2026-07-12T09:30:00+00:00".to_string();
    collaboration::apply_event(
        pool,
        log_event(
            "event-8-time",
            8,
            "log.updated",
            canonical_time_log,
            Some(time_mutation.clone()),
        ),
    )
    .await
    .unwrap();
    let accepted_removed: (i64,) =
        sqlx::query_as("SELECT COUNT(*) FROM sync_outbox WHERE mutation_id = ?")
            .bind(&time_mutation)
            .fetch_one(pool)
            .await
            .unwrap();
    assert_eq!(accepted_removed.0, 0);

    for index in 0..101 {
        let mut backlog = LogEntry::new(
            SESSION.to_string(),
            "BG5CRL".to_string(),
            format!("BA4{index:03}"),
        );
        backlog.sync_id = format!("backlog-log-{index}");
        logs::insert_log(&backlog).await.unwrap();
    }
    let future_retry_mutation: (String,) = sqlx::query_as(
        "SELECT mutation_id FROM sync_outbox
         WHERE entity_type = 'log' AND entity_id LIKE 'backlog-log-%'
         ORDER BY local_seq LIMIT 1",
    )
    .fetch_one(pool)
    .await
    .unwrap();
    collaboration::mark_mutations_sending(
        pool,
        SERVER,
        ACCOUNT,
        SESSION,
        std::slice::from_ref(&future_retry_mutation.0),
    )
    .await
    .unwrap();
    collaboration::mark_mutation_retry(
        pool,
        MutationFailureRequest {
            server_instance_id: SERVER.to_string(),
            account_id: ACCOUNT.to_string(),
            session_id: SESSION.to_string(),
            mutation_id: future_retry_mutation.0.clone(),
            error_code: Some("RATE_LIMITED".to_string()),
            error_message: Some("retry later".to_string()),
            next_attempt_at: Some("2099-01-01T00:00:00Z".to_string()),
        },
    )
    .await
    .unwrap();
    let future_retry_batch =
        collaboration::list_pending_mutations(pool, SERVER, ACCOUNT, SESSION, 1)
            .await
            .unwrap();
    assert_eq!(
        future_retry_batch["operations"][0]["mutationId"],
        future_retry_mutation.0
    );
    sessions::close_session(SESSION.to_string()).await.unwrap();
    let local_close_status = collaboration::get_sync_status(pool, SERVER, ACCOUNT, SESSION)
        .await
        .unwrap();
    assert_eq!(local_close_status.canonical_session_status, "active");
    let closed_insert = LogEntry::new(
        SESSION.to_string(),
        "BG5CRL".to_string(),
        "BA4CCC".to_string(),
    );
    assert!(logs::insert_log(&closed_insert)
        .await
        .unwrap_err()
        .to_string()
        .contains("SESSION_CLOSED"));

    let close_mutation: (String,) = sqlx::query_as(
        "SELECT mutation_id FROM sync_outbox
         WHERE entity_type = 'session' AND operation = 'close'",
    )
    .fetch_one(pool)
    .await
    .unwrap();
    collaboration::mark_mutations_sending(
        pool,
        SERVER,
        ACCOUNT,
        SESSION,
        std::slice::from_ref(&close_mutation.0),
    )
    .await
    .unwrap();
    collaboration::mark_mutation_accepted(pool, SERVER, ACCOUNT, SESSION, &close_mutation.0, 9)
        .await
        .unwrap();
    collaboration::apply_event(
        pool,
        session_event(
            "event-9-close",
            9,
            "session.closed",
            "closed",
            2,
            Some(close_mutation.0),
        ),
    )
    .await
    .unwrap();
    let remote_close_status = collaboration::get_sync_status(pool, SERVER, ACCOUNT, SESSION)
        .await
        .unwrap();
    assert_eq!(remote_close_status.canonical_session_status, "closed");
    collaboration::reopen_session(pool, SESSION).await.unwrap();
    let reopened_batch = collaboration::list_pending_mutations(pool, SERVER, ACCOUNT, SESSION, 100)
        .await
        .unwrap();
    assert_eq!(reopened_batch["operations"].as_array().unwrap().len(), 1);
    assert_eq!(reopened_batch["operations"][0]["entityType"], "session");
    assert_eq!(reopened_batch["operations"][0]["operation"], "reopen");
    let closed_log_claims: (i64,) = sqlx::query_as(
        "SELECT COUNT(*) FROM sync_outbox
         WHERE entity_type = 'log' AND entity_id LIKE 'backlog-log-%'
           AND state = 'sending'",
    )
    .fetch_one(pool)
    .await
    .unwrap();
    assert_eq!(closed_log_claims.0, 0);
    let local_reopen_status = collaboration::get_sync_status(pool, SERVER, ACCOUNT, SESSION)
        .await
        .unwrap();
    assert_eq!(local_reopen_status.canonical_session_status, "closed");
    let before_canonical_reopen = LogEntry::new(
        SESSION.to_string(),
        "BG5CRL".to_string(),
        "BA4WAIT".to_string(),
    );
    assert!(logs::insert_log(&before_canonical_reopen)
        .await
        .unwrap_err()
        .to_string()
        .contains("SESSION_CLOSED"));

    collaboration::update_membership(
        pool,
        SERVER,
        ACCOUNT,
        SESSION,
        "membership-owner",
        2,
        CollaborationRole::Viewer,
    )
    .await
    .unwrap();
    assert!(collaboration::update_membership(
        pool,
        SERVER,
        ACCOUNT,
        SESSION,
        "membership-owner",
        1,
        CollaborationRole::Owner,
    )
    .await
    .unwrap_err()
    .to_string()
    .contains("MEMBERSHIP_VERSION_REGRESSION"));
    let viewer_insert = LogEntry::new(
        SESSION.to_string(),
        "BG5CRL".to_string(),
        "BA4DDD".to_string(),
    );
    assert!(logs::insert_log(&viewer_insert)
        .await
        .unwrap_err()
        .to_string()
        .contains("COLLABORATION_ROLE_READ_ONLY"));
    let viewer_row: (i64,) = sqlx::query_as("SELECT COUNT(*) FROM logs WHERE sync_id = ?")
        .bind(&viewer_insert.sync_id)
        .fetch_one(pool)
        .await
        .unwrap();
    assert_eq!(viewer_row.0, 0);

    collaboration::update_membership(
        pool,
        SERVER,
        ACCOUNT,
        SESSION,
        "membership-owner",
        3,
        CollaborationRole::Owner,
    )
    .await
    .unwrap();
    collaboration::mark_revoked(pool, SERVER, ACCOUNT, SESSION)
        .await
        .unwrap();
    assert!(logs::insert_log(&viewer_insert)
        .await
        .unwrap_err()
        .to_string()
        .contains("COLLABORATION_MEMBERSHIP_REVOKED"));
    let status = collaboration::get_sync_status(pool, SERVER, ACCOUNT, SESSION)
        .await
        .unwrap();
    assert_eq!(status.replica_state, "revoked");
    assert_eq!(status.last_applied_seq, 9);
    assert_eq!(status.canonical_session_status, "closed");
    assert_eq!(status.conflict_count, 1);

    let tables: (i64,) = sqlx::query_as(
        "SELECT COUNT(*) FROM sqlite_master
         WHERE type = 'table' AND name IN ('sync_outbox', 'applied_events', 'sync_conflicts')",
    )
    .fetch_one(pool)
    .await
    .unwrap();
    assert_eq!(tables.0, 3);
    let schema: (i64,) = sqlx::query_as("SELECT MAX(version) FROM schema_version")
        .fetch_one(pool)
        .await
        .unwrap();
    assert_eq!(schema.0, 5);

    // Ensure serde payload remains real JSON rather than double encoded strings.
    let _: Value = serde_json::from_str(
        &sqlx::query_as::<_, (String,)>(
            "SELECT payload_json FROM sync_outbox ORDER BY local_seq LIMIT 1",
        )
        .fetch_one(pool)
        .await
        .unwrap()
        .0,
    )
    .unwrap();

    pool.close().await;
    let _ = std::fs::remove_file(database_path);
}
