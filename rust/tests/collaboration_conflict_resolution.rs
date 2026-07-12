use openlogtool_core::api;
use openlogtool_core::db::{collaboration, logs};
use openlogtool_core::models::collaboration::{
    CollaborationRole, CollaborationSnapshot, ConflictResolution, InstallSnapshotRequest,
    MutationConflictRequest, RemoteLog, RemoteMembership, RemoteSession, ResolveConflictRequest,
    SnapshotInstallMode,
};
use openlogtool_core::models::log_entry::LogEntry;
use openlogtool_core::{get_db, init_database};
use serde_json::{json, Value};

const SERVER: &str = "conflict-server";
const ACCOUNT: &str = "conflict-account";
const SESSION: &str = "conflict-session";
const NOW: &str = "2026-07-12T12:00:00Z";

fn remote_log(
    sync_id: &str,
    version: i64,
    qth: &str,
    device: &str,
    remarks: &str,
    deleted: bool,
) -> RemoteLog {
    RemoteLog {
        sync_id: sync_id.to_string(),
        session_id: SESSION.to_string(),
        version,
        time: NOW.to_string(),
        controller: "BG5CRL".to_string(),
        callsign: "BA4AAA".to_string(),
        rst_sent: Some("59".to_string()),
        rst_rcvd: Some("57".to_string()),
        qth: Some(qth.to_string()),
        device: Some(device.to_string()),
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
    let logs = [
        "safe",
        "equal",
        "hazard",
        "keep",
        "keep-equal",
        "lifecycle",
        "invalid",
        "rollback",
        "fork",
        "delete-wins",
        "copy-rollback",
        "toctou",
    ]
    .into_iter()
    .map(|id| remote_log(id, 1, "base-qth", "base-device", "base-remarks", false))
    .chain(std::iter::once(remote_log(
        "explicit-restore",
        1,
        "base-qth",
        "base-device",
        "base-remarks",
        true,
    )))
    .collect();
    InstallSnapshotRequest {
        mode: SnapshotInstallMode::Join,
        server_instance_id: SERVER.to_string(),
        server_origin: "https://conflict.example".to_string(),
        account_id: ACCOUNT.to_string(),
        membership: RemoteMembership {
            membership_id: "conflict-membership".to_string(),
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
                title: "Conflict base".to_string(),
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
            logs,
        },
    }
}

fn local_log(sync_id: &str, remarks: &str) -> LogEntry {
    LogEntry {
        id: None,
        sync_id: sync_id.to_string(),
        session_id: SESSION.to_string(),
        time: NOW.to_string(),
        controller: "BG5CRL".to_string(),
        callsign: "BA4LOCAL".to_string(),
        rst_sent: Some("59".to_string()),
        rst_rcvd: Some("57".to_string()),
        qth: Some("local-qth".to_string()),
        device: Some("local-device".to_string()),
        power: Some("10W".to_string()),
        antenna: Some("DP".to_string()),
        height: Some("8m".to_string()),
        remarks: Some(remarks.to_string()),
        created_at: NOW.to_string(),
        updated_at: NOW.to_string(),
        deleted_at: None,
        source_device_id: None,
    }
}

async fn try_update_log(
    sync_id: &str,
    qth: &str,
    device: &str,
    remarks: &str,
) -> anyhow::Result<()> {
    logs::update_log(
        sync_id,
        "BG5CRL",
        "BA4AAA",
        NOW,
        Some("59"),
        Some("57"),
        Some(qth),
        Some(device),
        Some("10W"),
        Some("DP"),
        Some("8m"),
        Some(remarks),
    )
    .await?;
    Ok(())
}

async fn update_log(sync_id: &str, qth: &str, device: &str, remarks: &str) {
    try_update_log(sync_id, qth, device, remarks).await.unwrap();
}

async fn claim_root(pool: &sqlx::SqlitePool, entity_id: &str) -> (i64, String, String, i64) {
    let row: (i64, String, String, i64) = sqlx::query_as(
        "SELECT local_seq, mutation_id, payload_json, base_version
         FROM sync_outbox WHERE session_id = ? AND entity_id = ?
         ORDER BY local_seq LIMIT 1",
    )
    .bind(SESSION)
    .bind(entity_id)
    .fetch_one(pool)
    .await
    .unwrap();
    let changed = sqlx::query(
        "UPDATE sync_outbox SET state = 'sending', attempts = attempts + 1
         WHERE mutation_id = ? AND state = 'pending'",
    )
    .bind(&row.1)
    .execute(pool)
    .await
    .unwrap();
    assert_eq!(changed.rows_affected(), 1);
    row
}

fn conflict_request(mutation_id: &str, remote: RemoteLog) -> MutationConflictRequest {
    MutationConflictRequest {
        server_instance_id: SERVER.to_string(),
        account_id: ACCOUNT.to_string(),
        session_id: SESSION.to_string(),
        mutation_id: mutation_id.to_string(),
        current_version: remote.version,
        current_entity: serde_json::to_value(remote).unwrap(),
    }
}

fn session_conflict_request(
    mutation_id: &str,
    version: i64,
    title: &str,
) -> MutationConflictRequest {
    MutationConflictRequest {
        server_instance_id: SERVER.to_string(),
        account_id: ACCOUNT.to_string(),
        session_id: SESSION.to_string(),
        mutation_id: mutation_id.to_string(),
        current_version: version,
        current_entity: json!({
            "sessionId": SESSION,
            "title": title,
            "status": "active",
            "version": version,
            "createdAt": NOW,
            "updatedAt": NOW,
            "closedAt": null,
            "deletedAt": null,
        }),
    }
}

fn resolution(
    conflict_id: String,
    expected_remote_version: i64,
    resolution: ConflictResolution,
) -> ResolveConflictRequest {
    ResolveConflictRequest {
        server_instance_id: SERVER.to_string(),
        account_id: ACCOUNT.to_string(),
        session_id: SESSION.to_string(),
        conflict_id,
        expected_remote_version,
        resolution,
    }
}

async fn materialized_log(
    pool: &sqlx::SqlitePool,
    entity_id: &str,
) -> (String, String, String, Option<String>) {
    sqlx::query_as("SELECT qth, device, remarks, deleted_at FROM logs WHERE sync_id = ?")
        .bind(entity_id)
        .fetch_one(pool)
        .await
        .unwrap()
}

async fn outbox_count(pool: &sqlx::SqlitePool, entity_id: &str) -> i64 {
    sqlx::query_as::<_, (i64,)>("SELECT COUNT(*) FROM sync_outbox WHERE entity_id = ?")
        .bind(entity_id)
        .fetch_one(pool)
        .await
        .unwrap()
        .0
}

#[tokio::test]
async fn stage3_conflict_rebase_and_resolution_are_safe_and_atomic() {
    let database_path = std::env::temp_dir().join(format!(
        "openlogtool-collaboration-conflict-{}.db",
        uuid::Uuid::new_v4()
    ));
    init_database(database_path.to_str().unwrap())
        .await
        .unwrap();
    let pool = get_db().unwrap();
    collaboration::install_snapshot(pool, install_request())
        .await
        .unwrap();

    // A fully unsent dependent update chain is folded into one fresh ID. The
    // replacement keeps the old local_seq, merges unrelated remote fields,
    // and never mutates either payload that was already queued.
    update_log("safe", "base-qth", "base-device", "local-remarks").await;
    let (safe_seq, safe_root, safe_root_payload, safe_base) = claim_root(pool, "safe").await;
    update_log("safe", "local-qth", "base-device", "local-remarks").await;
    let safe_dependent: (String, String) = sqlx::query_as(
        "SELECT mutation_id, payload_json FROM sync_outbox
         WHERE entity_id = 'safe' ORDER BY local_seq DESC LIMIT 1",
    )
    .fetch_one(pool)
    .await
    .unwrap();
    let safe_remote = remote_log(
        "safe",
        2,
        "base-qth",
        "remote-device",
        "base-remarks",
        false,
    );
    let rebased = collaboration::record_mutation_conflict(
        pool,
        conflict_request(&safe_root, safe_remote.clone()),
    )
    .await
    .unwrap();
    assert_eq!(rebased.outcome, "rebased");
    let safe_replacement = rebased.replacement_mutation_id.unwrap();
    assert_ne!(safe_replacement, safe_root);
    assert_ne!(safe_replacement, safe_dependent.0);
    let safe_row: (i64, String, i64, String, String, i64) = sqlx::query_as(
        "SELECT local_seq, mutation_id, base_version, payload_json, state, attempts
         FROM sync_outbox WHERE entity_id = 'safe'",
    )
    .fetch_one(pool)
    .await
    .unwrap();
    assert_eq!(safe_row.0, safe_seq);
    assert_eq!(safe_row.1, safe_replacement);
    assert_eq!(safe_row.2, 2);
    assert_eq!(safe_row.4, "pending");
    assert_eq!(safe_row.5, 0);
    let safe_patch: Value = serde_json::from_str(&safe_row.3).unwrap();
    assert_eq!(safe_patch["patch"]["remarks"], "local-remarks");
    assert_eq!(safe_patch["patch"]["qth"], "local-qth");
    assert!(safe_patch["patch"].get("device").is_none());
    let old_rows: (i64,) =
        sqlx::query_as("SELECT COUNT(*) FROM sync_outbox WHERE mutation_id IN (?, ?)")
            .bind(&safe_root)
            .bind(&safe_dependent.0)
            .fetch_one(pool)
            .await
            .unwrap();
    assert_eq!(old_rows.0, 0);
    assert_eq!(safe_base, 1);
    assert!(safe_root_payload.contains("local-remarks"));
    assert!(safe_dependent.1.contains("local-qth"));
    let safe_local = materialized_log(pool, "safe").await;
    assert_eq!(safe_local.0, "local-qth");
    assert_eq!(safe_local.1, "remote-device");
    assert_eq!(safe_local.2, "local-remarks");

    // If remote already reached the complete local goal, the old intent is
    // retired without creating a meaningless version-bumping mutation.
    update_log("equal", "base-qth", "base-device", "same-target").await;
    let (_, equal_root, _, _) = claim_root(pool, "equal").await;
    let equal_remote = remote_log(
        "equal",
        2,
        "remote-qth",
        "base-device",
        "same-target",
        false,
    );
    let equal =
        collaboration::record_mutation_conflict(pool, conflict_request(&equal_root, equal_remote))
            .await
            .unwrap();
    assert_eq!(equal.outcome, "rebased");
    assert!(equal.replacement_mutation_id.is_none());
    assert_eq!(outbox_count(pool, "equal").await, 0);
    assert_eq!(materialized_log(pool, "equal").await.0, "remote-qth");

    // The head itself is safe, but its dependent changes the same field as
    // remote to a different value. Folding only the head would later let ACK
    // blindly rebase the dependent and silently overwrite remote.
    update_log("hazard", "base-qth", "base-device", "local-head").await;
    let (_, hazard_root, hazard_payload, _) = claim_root(pool, "hazard").await;
    update_log("hazard", "base-qth", "local-dependent", "local-head").await;
    let hazard_child: (String, String, Option<String>, i64) = sqlx::query_as(
        "SELECT mutation_id, payload_json, depends_on_mutation_id, attempts
         FROM sync_outbox WHERE entity_id = 'hazard' ORDER BY local_seq DESC LIMIT 1",
    )
    .fetch_one(pool)
    .await
    .unwrap();
    let hazard_remote = remote_log(
        "hazard",
        2,
        "base-qth",
        "remote-dependent",
        "base-remarks",
        false,
    );
    let hazard = collaboration::record_mutation_conflict(
        pool,
        conflict_request(&hazard_root, hazard_remote.clone()),
    )
    .await
    .unwrap();
    assert_eq!(hazard.outcome, "conflict");
    assert_eq!(hazard.conflicting_fields, vec!["device"]);
    let hazard_conflict_id = hazard.conflict_id.unwrap();
    let hazard_rows: Vec<(String, String, String, Option<String>, i64)> = sqlx::query_as(
        "SELECT mutation_id, payload_json, state, depends_on_mutation_id, attempts
         FROM sync_outbox WHERE entity_id = 'hazard' ORDER BY local_seq",
    )
    .fetch_all(pool)
    .await
    .unwrap();
    assert_eq!(hazard_rows[0].0, hazard_root);
    assert_eq!(hazard_rows[0].1, hazard_payload);
    assert_eq!(hazard_rows[0].2, "conflict");
    assert_eq!(hazard_rows[1].0, hazard_child.0);
    assert_eq!(hazard_rows[1].1, hazard_child.1);
    assert_eq!(hazard_rows[1].3.as_deref(), Some(hazard_root.as_str()));
    assert_eq!(hazard_rows[1].4, 0);
    let listed = collaboration::list_open_conflicts(pool, SERVER, ACCOUNT, SESSION)
        .await
        .unwrap();
    assert_eq!(listed.len(), 1);
    assert_eq!(listed[0].conflict_id, hazard_conflict_id);
    assert_eq!(listed[0].local_entity["device"], "local-dependent");
    assert_eq!(
        listed[0].allowed_resolutions,
        vec![
            ConflictResolution::UseRemote,
            ConflictResolution::KeepLocal,
            ConflictResolution::CopyLocalAsNew,
        ]
    );
    let api_list: Value = serde_json::from_str(
        &api::collaboration::list_open_collaboration_conflicts(
            SERVER.to_string(),
            ACCOUNT.to_string(),
            SESSION.to_string(),
        )
        .await
        .unwrap(),
    )
    .unwrap();
    assert_eq!(api_list.as_array().unwrap().len(), 1);

    let hazard_before = materialized_log(pool, "hazard").await;
    let blocked_update =
        try_update_log("hazard", "blocked-qth", "blocked-device", "blocked-update")
            .await
            .unwrap_err();
    assert!(format!("{blocked_update:#}").contains("COLLABORATION_ENTITY_CONFLICTED"));
    let blocked_delete = logs::soft_delete_log("hazard").await.unwrap_err();
    assert!(format!("{blocked_delete:#}").contains("COLLABORATION_ENTITY_CONFLICTED"));
    assert_eq!(materialized_log(pool, "hazard").await, hazard_before);
    let hazard_rows_after_block: Vec<(String, String, String, Option<String>, i64)> =
        sqlx::query_as(
            "SELECT mutation_id, payload_json, state, depends_on_mutation_id, attempts
             FROM sync_outbox WHERE entity_id = 'hazard' ORDER BY local_seq",
        )
        .fetch_all(pool)
        .await
        .unwrap();
    assert_eq!(hazard_rows_after_block, hazard_rows);

    // The freeze is entity-scoped; unrelated local edits continue normally.
    update_log("equal", "remote-qth", "base-device", "other-entity-edit").await;
    assert_eq!(materialized_log(pool, "equal").await.2, "other-entity-edit");

    let use_remote = collaboration::resolve_conflict(
        pool,
        resolution(hazard_conflict_id, 2, ConflictResolution::UseRemote),
    )
    .await
    .unwrap();
    assert!(use_remote.replacement_mutation_id.is_none());
    assert!(use_remote.replacement_entity_id.is_none());
    assert_eq!(outbox_count(pool, "hazard").await, 0);
    assert!(
        collaboration::list_open_conflicts(pool, SERVER, ACCOUNT, SESSION)
            .await
            .unwrap()
            .is_empty()
    );
    let hazard_local = materialized_log(pool, "hazard").await;
    assert_eq!(hazard_local.1, "remote-dependent");
    assert_eq!(hazard_local.2, "base-remarks");
    update_log("hazard", "base-qth", "remote-dependent", "after-resolution").await;
    assert_eq!(outbox_count(pool, "hazard").await, 1);
    assert_eq!(materialized_log(pool, "hazard").await.2, "after-resolution");

    // keepLocal creates a fresh ID on the captured remote baseline and keeps
    // the local desired value in the materialized replica.
    update_log("keep", "base-qth", "base-device", "local-keep").await;
    let (_, keep_root, _, _) = claim_root(pool, "keep").await;
    let keep_remote = remote_log("keep", 2, "remote-qth", "base-device", "remote-keep", false);
    let keep = collaboration::record_mutation_conflict(
        pool,
        conflict_request(&keep_root, keep_remote.clone()),
    )
    .await
    .unwrap();
    let keep_result = collaboration::resolve_conflict(
        pool,
        resolution(keep.conflict_id.unwrap(), 2, ConflictResolution::KeepLocal),
    )
    .await
    .unwrap();
    assert!(keep_result.replacement_entity_id.is_none());
    let keep_replacement = keep_result.replacement_mutation_id.unwrap();
    assert_ne!(keep_replacement, keep_root);
    let keep_row: (String, i64, String) = sqlx::query_as(
        "SELECT mutation_id, base_version, payload_json FROM sync_outbox
         WHERE entity_id = 'keep'",
    )
    .fetch_one(pool)
    .await
    .unwrap();
    assert_eq!(keep_row.0, keep_replacement);
    assert_eq!(keep_row.1, 2);
    assert_eq!(
        serde_json::from_str::<Value>(&keep_row.2).unwrap()["patch"]["remarks"],
        "local-keep"
    );
    let keep_local = materialized_log(pool, "keep").await;
    assert_eq!(keep_local.0, "remote-qth");
    assert_eq!(keep_local.2, "local-keep");

    // Session title updates use the same three-way rule and owner-only
    // keepLocal resolution, while still receiving a brand-new mutation ID.
    collaboration::update_session_title(pool, SESSION, "Local title")
        .await
        .unwrap();
    let (_, session_root, session_payload, _) = claim_root(pool, SESSION).await;
    let session_conflict = collaboration::record_mutation_conflict(
        pool,
        session_conflict_request(&session_root, 2, "Remote title"),
    )
    .await
    .unwrap();
    assert_eq!(session_conflict.conflicting_fields, vec!["title"]);
    let session_conflict_id = session_conflict.conflict_id.unwrap();
    let session_listed = collaboration::list_open_conflicts(pool, SERVER, ACCOUNT, SESSION)
        .await
        .unwrap()
        .into_iter()
        .find(|conflict| conflict.conflict_id == session_conflict_id)
        .unwrap();
    assert_eq!(
        session_listed.allowed_resolutions,
        vec![ConflictResolution::UseRemote, ConflictResolution::KeepLocal,]
    );
    let session_before: (String, String, String) =
        sqlx::query_as("SELECT title, status, updated_at FROM sessions WHERE session_id = ?")
            .bind(SESSION)
            .fetch_one(pool)
            .await
            .unwrap();
    let session_outbox_before: (String, String, i64) = sqlx::query_as(
        "SELECT payload_json, state, attempts FROM sync_outbox WHERE mutation_id = ?",
    )
    .bind(&session_root)
    .fetch_one(pool)
    .await
    .unwrap();
    let blocked_title = collaboration::update_session_title(pool, SESSION, "Blocked title")
        .await
        .unwrap_err();
    assert!(format!("{blocked_title:#}").contains("COLLABORATION_ENTITY_CONFLICTED"));
    let blocked_close = api::sessions::close_session(SESSION.to_string())
        .await
        .unwrap_err();
    assert!(format!("{blocked_close:#}").contains("COLLABORATION_ENTITY_CONFLICTED"));
    let session_after_block: (String, String, String) =
        sqlx::query_as("SELECT title, status, updated_at FROM sessions WHERE session_id = ?")
            .bind(SESSION)
            .fetch_one(pool)
            .await
            .unwrap();
    assert_eq!(session_after_block, session_before);
    let session_outbox_after: (String, String, i64) = sqlx::query_as(
        "SELECT payload_json, state, attempts FROM sync_outbox WHERE mutation_id = ?",
    )
    .bind(&session_root)
    .fetch_one(pool)
    .await
    .unwrap();
    assert_eq!(session_outbox_after, session_outbox_before);
    let session_resolution = collaboration::resolve_conflict(
        pool,
        resolution(session_conflict_id, 2, ConflictResolution::KeepLocal),
    )
    .await
    .unwrap();
    let session_replacement = session_resolution.replacement_mutation_id.unwrap();
    assert_ne!(session_replacement, session_root);
    assert!(session_payload.contains("Local title"));
    let session_row: (String, i64, String) = sqlx::query_as(
        "SELECT mutation_id, base_version, payload_json FROM sync_outbox
         WHERE entity_type = 'session' AND entity_id = ?",
    )
    .bind(SESSION)
    .fetch_one(pool)
    .await
    .unwrap();
    assert_eq!(session_row.0, session_replacement);
    assert_eq!(session_row.1, 2);
    assert_eq!(
        serde_json::from_str::<Value>(&session_row.2).unwrap()["patch"]["title"],
        "Local title"
    );
    let local_session_title: (String,) =
        sqlx::query_as("SELECT title FROM sessions WHERE session_id = ?")
            .bind(SESSION)
            .fetch_one(pool)
            .await
            .unwrap();
    assert_eq!(local_session_title.0, "Local title");
    collaboration::update_session_title(pool, SESSION, "After conflict")
        .await
        .unwrap();
    let after_conflict_title: (String,) =
        sqlx::query_as("SELECT title FROM sessions WHERE session_id = ?")
            .bind(SESSION)
            .fetch_one(pool)
            .await
            .unwrap();
    assert_eq!(after_conflict_title.0, "After conflict");

    // A newer canonical shadow supersedes the conflict response. If it has
    // already reached local desired, keepLocal resolves with no replacement.
    update_log("keep-equal", "base-qth", "base-device", "local-equal").await;
    let (_, keep_equal_root, _, _) = claim_root(pool, "keep-equal").await;
    let keep_equal_remote = remote_log(
        "keep-equal",
        2,
        "remote-v2",
        "base-device",
        "remote-v2",
        false,
    );
    let keep_equal = collaboration::record_mutation_conflict(
        pool,
        conflict_request(&keep_equal_root, keep_equal_remote),
    )
    .await
    .unwrap();
    let keep_equal_conflict_id = keep_equal.conflict_id.unwrap();
    let shadow_v3 = remote_log(
        "keep-equal",
        3,
        "shadow-v3",
        "base-device",
        "local-equal",
        false,
    );
    sqlx::query(
        "UPDATE entity_shadows SET server_version = 3, server_json = ?
         WHERE session_id = ? AND entity_type = 'log' AND entity_id = 'keep-equal'",
    )
    .bind(serde_json::to_string(&shadow_v3).unwrap())
    .bind(SESSION)
    .execute(pool)
    .await
    .unwrap();
    let keep_equal_latest = collaboration::list_open_conflicts(pool, SERVER, ACCOUNT, SESSION)
        .await
        .unwrap()
        .into_iter()
        .find(|conflict| conflict.conflict_id == keep_equal_conflict_id)
        .unwrap();
    assert_eq!(keep_equal_latest.remote_version, 3);
    assert_eq!(keep_equal_latest.remote_entity["qth"], "shadow-v3");
    assert_eq!(keep_equal_latest.remote_entity["remarks"], "local-equal");
    assert!(keep_equal_latest.conflicting_fields.is_empty());
    let keep_equal_result = collaboration::resolve_conflict(
        pool,
        resolution(keep_equal_conflict_id, 3, ConflictResolution::KeepLocal),
    )
    .await
    .unwrap();
    assert!(keep_equal_result.replacement_mutation_id.is_none());
    assert_eq!(outbox_count(pool, "keep-equal").await, 0);
    let keep_equal_local = materialized_log(pool, "keep-equal").await;
    assert_eq!(keep_equal_local.0, "shadow-v3");
    assert_eq!(keep_equal_local.2, "local-equal");

    // Resolution is compare-and-swap against the version shown by the list.
    // If shadow advances after rendering, destructive, keep, and copy choices
    // all fail before touching conflict, outbox, or materialized state.
    update_log("toctou", "base-qth", "base-device", "local-toctou").await;
    let (_, toctou_root, _, _) = claim_root(pool, "toctou").await;
    let toctou_remote_v2 = remote_log("toctou", 2, "remote-v2", "base-device", "remote-v2", false);
    let toctou = collaboration::record_mutation_conflict(
        pool,
        conflict_request(&toctou_root, toctou_remote_v2),
    )
    .await
    .unwrap();
    let toctou_conflict_id = toctou.conflict_id.unwrap();
    let listed_v2 = collaboration::list_open_conflicts(pool, SERVER, ACCOUNT, SESSION)
        .await
        .unwrap()
        .into_iter()
        .find(|conflict| conflict.conflict_id == toctou_conflict_id)
        .unwrap();
    assert_eq!(listed_v2.remote_version, 2);

    let toctou_remote_v3 = remote_log("toctou", 3, "remote-v3", "base-device", "remote-v3", false);
    sqlx::query(
        "UPDATE entity_shadows SET server_version = 3, server_json = ?
         WHERE session_id = ? AND entity_type = 'log' AND entity_id = 'toctou'",
    )
    .bind(serde_json::to_string(&toctou_remote_v3).unwrap())
    .bind(SESSION)
    .execute(pool)
    .await
    .unwrap();
    let toctou_materialized_before = materialized_log(pool, "toctou").await;
    let toctou_outbox_before: (String, String, i64, String) = sqlx::query_as(
        "SELECT payload_json, state, base_version, operation
         FROM sync_outbox WHERE mutation_id = ?",
    )
    .bind(&toctou_root)
    .fetch_one(pool)
    .await
    .unwrap();
    let toctou_conflict_before: (String, i64, String) = sqlx::query_as(
        "SELECT state, remote_version, remote_json FROM sync_conflicts WHERE conflict_id = ?",
    )
    .bind(&toctou_conflict_id)
    .fetch_one(pool)
    .await
    .unwrap();
    let toctou_log_count_before: (i64,) = sqlx::query_as("SELECT COUNT(*) FROM logs")
        .fetch_one(pool)
        .await
        .unwrap();
    for choice in [
        ConflictResolution::UseRemote,
        ConflictResolution::KeepLocal,
        ConflictResolution::CopyLocalAsNew,
    ] {
        let advanced = collaboration::resolve_conflict(
            pool,
            resolution(toctou_conflict_id.clone(), 2, choice),
        )
        .await
        .unwrap_err();
        assert!(format!("{advanced:#}").contains("CONFLICT_REMOTE_ADVANCED"));
        assert_eq!(
            materialized_log(pool, "toctou").await,
            toctou_materialized_before
        );
        let outbox_after: (String, String, i64, String) = sqlx::query_as(
            "SELECT payload_json, state, base_version, operation
             FROM sync_outbox WHERE mutation_id = ?",
        )
        .bind(&toctou_root)
        .fetch_one(pool)
        .await
        .unwrap();
        assert_eq!(outbox_after, toctou_outbox_before);
        let conflict_after: (String, i64, String) = sqlx::query_as(
            "SELECT state, remote_version, remote_json FROM sync_conflicts WHERE conflict_id = ?",
        )
        .bind(&toctou_conflict_id)
        .fetch_one(pool)
        .await
        .unwrap();
        assert_eq!(conflict_after, toctou_conflict_before);
        let log_count_after: (i64,) = sqlx::query_as("SELECT COUNT(*) FROM logs")
            .fetch_one(pool)
            .await
            .unwrap();
        assert_eq!(log_count_after, toctou_log_count_before);
    }
    let listed_v3 = collaboration::list_open_conflicts(pool, SERVER, ACCOUNT, SESSION)
        .await
        .unwrap()
        .into_iter()
        .find(|conflict| conflict.conflict_id == toctou_conflict_id)
        .unwrap();
    assert_eq!(listed_v3.remote_version, 3);
    assert_eq!(listed_v3.remote_entity["qth"], "remote-v3");
    collaboration::resolve_conflict(
        pool,
        resolution(toctou_conflict_id, 3, ConflictResolution::UseRemote),
    )
    .await
    .unwrap();
    assert_eq!(outbox_count(pool, "toctou").await, 0);
    let toctou_materialized = materialized_log(pool, "toctou").await;
    assert_eq!(toctou_materialized.0, "remote-v3");
    assert_eq!(toctou_materialized.2, "remote-v3");

    // Lifecycle operations never auto-rebase. A viewer cannot keepLocal but
    // can still discard the local chain with useRemote.
    logs::soft_delete_log("lifecycle").await.unwrap();
    let (_, lifecycle_root, _, _) = claim_root(pool, "lifecycle").await;
    let lifecycle_remote = remote_log(
        "lifecycle",
        2,
        "remote-life",
        "base-device",
        "remote-life",
        false,
    );
    let lifecycle = collaboration::record_mutation_conflict(
        pool,
        conflict_request(&lifecycle_root, lifecycle_remote),
    )
    .await
    .unwrap();
    assert_eq!(lifecycle.outcome, "conflict");
    assert!(lifecycle
        .conflicting_fields
        .contains(&"deletedAt".to_string()));
    let lifecycle_conflict_id = lifecycle.conflict_id.unwrap();
    let lifecycle_before = materialized_log(pool, "lifecycle").await;
    let lifecycle_outbox_before: (String, String, i64) = sqlx::query_as(
        "SELECT payload_json, state, attempts FROM sync_outbox WHERE mutation_id = ?",
    )
    .bind(&lifecycle_root)
    .fetch_one(pool)
    .await
    .unwrap();
    let blocked_restore = logs::restore_log("lifecycle").await.unwrap_err();
    assert!(format!("{blocked_restore:#}").contains("COLLABORATION_ENTITY_CONFLICTED"));
    assert_eq!(materialized_log(pool, "lifecycle").await, lifecycle_before);
    let lifecycle_outbox_after: (String, String, i64) = sqlx::query_as(
        "SELECT payload_json, state, attempts FROM sync_outbox WHERE mutation_id = ?",
    )
    .bind(&lifecycle_root)
    .fetch_one(pool)
    .await
    .unwrap();
    assert_eq!(lifecycle_outbox_after, lifecycle_outbox_before);
    sqlx::query("UPDATE collaboration_bindings SET role = 'viewer' WHERE session_id = ?")
        .bind(SESSION)
        .execute(pool)
        .await
        .unwrap();
    let viewer_keep = collaboration::resolve_conflict(
        pool,
        resolution(
            lifecycle_conflict_id.clone(),
            2,
            ConflictResolution::KeepLocal,
        ),
    )
    .await
    .unwrap_err();
    assert!(format!("{viewer_keep:#}").contains("COLLABORATION_ROLE_READ_ONLY"));
    assert_eq!(outbox_count(pool, "lifecycle").await, 1);
    collaboration::resolve_conflict(
        pool,
        resolution(lifecycle_conflict_id, 2, ConflictResolution::UseRemote),
    )
    .await
    .unwrap();
    assert_eq!(outbox_count(pool, "lifecycle").await, 0);
    assert!(materialized_log(pool, "lifecycle").await.3.is_none());
    sqlx::query("UPDATE collaboration_bindings SET role = 'owner' WHERE session_id = ?")
        .bind(SESSION)
        .execute(pool)
        .await
        .unwrap();

    // A create/existence collision must never reinterpret keepLocal as an
    // update of the remote entity. copyLocalAsNew preserves both identities.
    let mut collision_entry = local_log("create-collision", "local-collision");
    collision_entry.time = "09:30".to_string();
    collision_entry.created_at = "2024-01-02T03:04:05Z".to_string();
    collision_entry.updated_at = collision_entry.created_at.clone();
    logs::insert_log(&collision_entry).await.unwrap();
    let (_, collision_root, collision_payload, collision_base) =
        claim_root(pool, "create-collision").await;
    assert_eq!(collision_base, 0);
    let collision_remote = remote_log(
        "create-collision",
        1,
        "remote-collision",
        "remote-device",
        "remote-collision",
        false,
    );
    let collision = collaboration::record_mutation_conflict(
        pool,
        conflict_request(&collision_root, collision_remote.clone()),
    )
    .await
    .unwrap();
    let collision_conflict_id = collision.conflict_id.unwrap();
    let collision_listed = collaboration::list_open_conflicts(pool, SERVER, ACCOUNT, SESSION)
        .await
        .unwrap()
        .into_iter()
        .find(|conflict| conflict.conflict_id == collision_conflict_id)
        .unwrap();
    assert_eq!(
        collision_listed.allowed_resolutions,
        vec![
            ConflictResolution::UseRemote,
            ConflictResolution::CopyLocalAsNew,
        ]
    );
    let collision_before = materialized_log(pool, "create-collision").await;
    let forbidden_collision_keep = collaboration::resolve_conflict(
        pool,
        resolution(
            collision_conflict_id.clone(),
            1,
            ConflictResolution::KeepLocal,
        ),
    )
    .await
    .unwrap_err();
    assert!(format!("{forbidden_collision_keep:#}").contains("CONFLICT_RESOLUTION_NOT_ALLOWED"));
    assert_eq!(
        materialized_log(pool, "create-collision").await,
        collision_before
    );
    let collision_root_after: (String, String, i64) = sqlx::query_as(
        "SELECT payload_json, state, base_version FROM sync_outbox WHERE mutation_id = ?",
    )
    .bind(&collision_root)
    .fetch_one(pool)
    .await
    .unwrap();
    assert_eq!(
        collision_root_after,
        (collision_payload, "conflict".to_string(), 0)
    );
    let copied = collaboration::resolve_conflict(
        pool,
        resolution(collision_conflict_id, 1, ConflictResolution::CopyLocalAsNew),
    )
    .await
    .unwrap();
    let copied_wire = serde_json::to_value(&copied).unwrap();
    assert!(copied_wire.get("replacementMutationId").is_some());
    assert!(copied_wire.get("replacementEntityId").is_some());
    let copied_mutation_id = copied.replacement_mutation_id.unwrap();
    let copied_entity_id = copied.replacement_entity_id.unwrap();
    assert_ne!(copied_entity_id, "create-collision");
    assert_ne!(copied_mutation_id, collision_root);
    let copied_outbox: (String, String, i64, String) = sqlx::query_as(
        "SELECT entity_id, operation, base_version, payload_json
         FROM sync_outbox WHERE mutation_id = ?",
    )
    .bind(&copied_mutation_id)
    .fetch_one(pool)
    .await
    .unwrap();
    assert_eq!(copied_outbox.0, copied_entity_id);
    assert_eq!(copied_outbox.1, "create");
    assert_eq!(copied_outbox.2, 0);
    let copied_payload: Value = serde_json::from_str(&copied_outbox.3).unwrap();
    assert_eq!(copied_payload["value"]["syncId"], copied_entity_id);
    assert_eq!(copied_payload["value"]["remarks"], "local-collision");
    let copied_time =
        chrono::DateTime::parse_from_rfc3339(copied_payload["value"]["time"].as_str().unwrap())
            .unwrap();
    assert_eq!(copied_time.date_naive().to_string(), "2024-01-02");
    let old_collision = materialized_log(pool, "create-collision").await;
    assert_eq!(old_collision.0, "remote-collision");
    assert_eq!(old_collision.1, "remote-device");
    assert_eq!(old_collision.2, "remote-collision");
    let new_collision = materialized_log(pool, &copied_entity_id).await;
    assert_eq!(new_collision.0, "local-qth");
    assert_eq!(new_collision.1, "local-device");
    assert_eq!(new_collision.2, "local-collision");
    let copied_materialized_time: (String,) =
        sqlx::query_as("SELECT time FROM logs WHERE sync_id = ?")
            .bind(&copied_entity_id)
            .fetch_one(pool)
            .await
            .unwrap();
    assert_eq!(
        copied_materialized_time.0,
        copied_payload["value"]["time"].as_str().unwrap()
    );

    // A stale update losing to a remote tombstone cannot restore the old ID.
    // The only non-destructive alternatives are accepting deletion or copying.
    update_log(
        "delete-wins",
        "base-qth",
        "base-device",
        "local-after-delete",
    )
    .await;
    let (_, delete_wins_root, delete_wins_payload, _) = claim_root(pool, "delete-wins").await;
    let deleted_remote = remote_log(
        "delete-wins",
        2,
        "remote-deleted",
        "base-device",
        "remote-deleted",
        true,
    );
    let delete_wins = collaboration::record_mutation_conflict(
        pool,
        conflict_request(&delete_wins_root, deleted_remote.clone()),
    )
    .await
    .unwrap();
    let delete_wins_conflict_id = delete_wins.conflict_id.unwrap();
    let delete_wins_listed = collaboration::list_open_conflicts(pool, SERVER, ACCOUNT, SESSION)
        .await
        .unwrap()
        .into_iter()
        .find(|conflict| conflict.conflict_id == delete_wins_conflict_id)
        .unwrap();
    assert_eq!(
        delete_wins_listed.allowed_resolutions,
        vec![
            ConflictResolution::UseRemote,
            ConflictResolution::CopyLocalAsNew,
        ]
    );
    let forbidden_deleted_keep = collaboration::resolve_conflict(
        pool,
        resolution(
            delete_wins_conflict_id.clone(),
            2,
            ConflictResolution::KeepLocal,
        ),
    )
    .await
    .unwrap_err();
    assert!(format!("{forbidden_deleted_keep:#}").contains("CONFLICT_RESOLUTION_NOT_ALLOWED"));
    let delete_wins_root_after: (String, String) =
        sqlx::query_as("SELECT payload_json, state FROM sync_outbox WHERE mutation_id = ?")
            .bind(&delete_wins_root)
            .fetch_one(pool)
            .await
            .unwrap();
    assert_eq!(
        delete_wins_root_after,
        (delete_wins_payload, "conflict".to_string())
    );
    collaboration::resolve_conflict(
        pool,
        resolution(delete_wins_conflict_id, 2, ConflictResolution::UseRemote),
    )
    .await
    .unwrap();
    assert!(materialized_log(pool, "delete-wins").await.3.is_some());

    // Only a root that was explicitly queued as restore may keep the same ID
    // when the latest remote is still a tombstone.
    logs::restore_log("explicit-restore").await.unwrap();
    let (_, restore_root, _, _) = claim_root(pool, "explicit-restore").await;
    let restore_remote = remote_log(
        "explicit-restore",
        2,
        "remote-tombstone",
        "remote-device",
        "remote-tombstone",
        true,
    );
    let restore_conflict = collaboration::record_mutation_conflict(
        pool,
        conflict_request(&restore_root, restore_remote),
    )
    .await
    .unwrap();
    let restore_conflict_id = restore_conflict.conflict_id.unwrap();
    let restore_listed = collaboration::list_open_conflicts(pool, SERVER, ACCOUNT, SESSION)
        .await
        .unwrap()
        .into_iter()
        .find(|conflict| conflict.conflict_id == restore_conflict_id)
        .unwrap();
    assert!(restore_listed
        .allowed_resolutions
        .contains(&ConflictResolution::KeepLocal));
    let restored = collaboration::resolve_conflict(
        pool,
        resolution(restore_conflict_id, 2, ConflictResolution::KeepLocal),
    )
    .await
    .unwrap();
    assert!(restored.replacement_entity_id.is_none());
    let restored_mutation_id = restored.replacement_mutation_id.unwrap();
    let restored_outbox: (String, String, i64) = sqlx::query_as(
        "SELECT entity_id, operation, base_version FROM sync_outbox WHERE mutation_id = ?",
    )
    .bind(restored_mutation_id)
    .fetch_one(pool)
    .await
    .unwrap();
    assert_eq!(restored_outbox.0, "explicit-restore");
    assert_eq!(restored_outbox.1, "restore");
    assert_eq!(restored_outbox.2, 2);
    assert!(materialized_log(pool, "explicit-restore").await.3.is_none());

    // A late failure while inserting the copied materialized row rolls back
    // conflict deletion, old-chain deletion, new outbox, and old remote write.
    update_log(
        "copy-rollback",
        "base-qth",
        "base-device",
        "local-copy-rollback",
    )
    .await;
    let (_, copy_rollback_root, copy_rollback_payload, _) = claim_root(pool, "copy-rollback").await;
    let copy_rollback_remote = remote_log(
        "copy-rollback",
        2,
        "remote-copy-rollback",
        "base-device",
        "remote-copy-rollback",
        true,
    );
    let copy_rollback = collaboration::record_mutation_conflict(
        pool,
        conflict_request(&copy_rollback_root, copy_rollback_remote),
    )
    .await
    .unwrap();
    let copy_rollback_conflict_id = copy_rollback.conflict_id.unwrap();
    let copy_rollback_before = materialized_log(pool, "copy-rollback").await;
    let log_count_before: (i64,) = sqlx::query_as("SELECT COUNT(*) FROM logs")
        .fetch_one(pool)
        .await
        .unwrap();
    sqlx::query(
        "CREATE TRIGGER fail_conflict_copy_insert
         BEFORE INSERT ON logs
         WHEN NEW.sync_id <> 'copy-rollback'
         BEGIN SELECT RAISE(ABORT, 'forced conflict copy failure'); END",
    )
    .execute(pool)
    .await
    .unwrap();
    let copy_failure = collaboration::resolve_conflict(
        pool,
        resolution(
            copy_rollback_conflict_id.clone(),
            2,
            ConflictResolution::CopyLocalAsNew,
        ),
    )
    .await
    .unwrap_err();
    assert!(format!("{copy_failure:#}").contains("forced conflict copy failure"));
    sqlx::query("DROP TRIGGER fail_conflict_copy_insert")
        .execute(pool)
        .await
        .unwrap();
    assert_eq!(
        materialized_log(pool, "copy-rollback").await,
        copy_rollback_before
    );
    let log_count_after: (i64,) = sqlx::query_as("SELECT COUNT(*) FROM logs")
        .fetch_one(pool)
        .await
        .unwrap();
    assert_eq!(log_count_after, log_count_before);
    let copy_rollback_root_after: (String, String) =
        sqlx::query_as("SELECT payload_json, state FROM sync_outbox WHERE mutation_id = ?")
            .bind(&copy_rollback_root)
            .fetch_one(pool)
            .await
            .unwrap();
    assert_eq!(
        copy_rollback_root_after,
        (copy_rollback_payload, "conflict".to_string())
    );
    let copy_conflict_still_open: (i64,) = sqlx::query_as(
        "SELECT COUNT(*) FROM sync_conflicts WHERE conflict_id = ? AND state = 'open'",
    )
    .bind(copy_rollback_conflict_id)
    .fetch_one(pool)
    .await
    .unwrap();
    assert_eq!(copy_conflict_still_open.0, 1);

    // A non-lifecycle VERSION_CONFLICT that did not advance the version is a
    // malformed response. It must leave the already-sent ID byte-for-byte.
    update_log("invalid", "base-qth", "base-device", "local-invalid").await;
    let (_, invalid_root, invalid_payload, _) = claim_root(pool, "invalid").await;
    let invalid_remote = remote_log(
        "invalid",
        1,
        "base-qth",
        "base-device",
        "remote-invalid",
        false,
    );
    let invalid = collaboration::record_mutation_conflict(
        pool,
        conflict_request(&invalid_root, invalid_remote),
    )
    .await
    .unwrap_err();
    assert!(format!("{invalid:#}").contains("CONFLICT_VERSION_NOT_ADVANCED"));
    let invalid_after: (String, String, i64) = sqlx::query_as(
        "SELECT state, payload_json, base_version FROM sync_outbox WHERE mutation_id = ?",
    )
    .bind(&invalid_root)
    .fetch_one(pool)
    .await
    .unwrap();
    assert_eq!(invalid_after, ("sending".to_string(), invalid_payload, 1));

    // Failure after deleting the old chain but before inserting its fresh ID
    // rolls back the whole transaction, including materialized remote merges.
    update_log("rollback", "base-qth", "base-device", "local-rollback").await;
    let (_, rollback_root, rollback_payload, _) = claim_root(pool, "rollback").await;
    sqlx::query(
        "CREATE TRIGGER fail_conflict_rebase_insert
         BEFORE INSERT ON sync_outbox
         WHEN NEW.entity_id = 'rollback' AND NEW.base_version = 2
         BEGIN SELECT RAISE(ABORT, 'forced conflict rebase failure'); END",
    )
    .execute(pool)
    .await
    .unwrap();
    let rollback_remote = remote_log(
        "rollback",
        2,
        "remote-rollback",
        "base-device",
        "base-remarks",
        false,
    );
    let rollback = collaboration::record_mutation_conflict(
        pool,
        conflict_request(&rollback_root, rollback_remote),
    )
    .await
    .unwrap_err();
    assert!(format!("{rollback:#}").contains("forced conflict rebase failure"));
    let rollback_after: (String, String, i64) = sqlx::query_as(
        "SELECT state, payload_json, base_version FROM sync_outbox WHERE mutation_id = ?",
    )
    .bind(&rollback_root)
    .fetch_one(pool)
    .await
    .unwrap();
    assert_eq!(rollback_after, ("sending".to_string(), rollback_payload, 1));
    let rollback_local = materialized_log(pool, "rollback").await;
    assert_eq!(rollback_local.0, "base-qth");
    assert_eq!(rollback_local.2, "local-rollback");
    sqlx::query("DROP TRIGGER fail_conflict_rebase_insert")
        .execute(pool)
        .await
        .unwrap();

    // Equal versions with different canonical payloads are a fork. Resolution
    // must not pick either value or delete the conflict/intent.
    update_log("fork", "base-qth", "base-device", "local-fork").await;
    let (_, fork_root, _, _) = claim_root(pool, "fork").await;
    let fork_remote = remote_log(
        "fork",
        2,
        "remote-fork",
        "base-device",
        "remote-fork",
        false,
    );
    let fork =
        collaboration::record_mutation_conflict(pool, conflict_request(&fork_root, fork_remote))
            .await
            .unwrap();
    let fork_conflict_id = fork.conflict_id.unwrap();
    let fork_shadow = remote_log(
        "fork",
        2,
        "different-same-version",
        "base-device",
        "remote-fork",
        false,
    );
    sqlx::query(
        "UPDATE entity_shadows SET server_version = 2, server_json = ?
         WHERE session_id = ? AND entity_type = 'log' AND entity_id = 'fork'",
    )
    .bind(serde_json::to_string(&fork_shadow).unwrap())
    .bind(SESSION)
    .execute(pool)
    .await
    .unwrap();
    let fork_error = collaboration::resolve_conflict(
        pool,
        resolution(fork_conflict_id.clone(), 2, ConflictResolution::UseRemote),
    )
    .await
    .unwrap_err();
    assert!(format!("{fork_error:#}").contains("CONFLICT_REMOTE_FORK"));
    assert_eq!(outbox_count(pool, "fork").await, 1);
    let fork_still_open: (i64,) = sqlx::query_as(
        "SELECT COUNT(*) FROM sync_conflicts WHERE conflict_id = ? AND state = 'open'",
    )
    .bind(fork_conflict_id)
    .fetch_one(pool)
    .await
    .unwrap();
    assert_eq!(fork_still_open.0, 1);

    let _ = std::fs::remove_file(database_path);
}
