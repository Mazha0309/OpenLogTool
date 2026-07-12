use crate::models::collaboration::{
    ApplyEventRequest, ApplyEventResult, CollaborationBinding, CollaborationRole,
    ConflictResolution, InstallSnapshotRequest, MutationConflictOutcome, MutationConflictRequest,
    MutationFailureRequest, OpenSyncConflict, PublishLog, PublishSession, PublishSnapshot,
    RemoteLog, ResolveConflictRequest, ResolveConflictResult, SnapshotInstallMode, SyncStatus,
};
use crate::models::log_entry::LogEntry;
use chrono::{DateTime, NaiveTime, TimeZone};
use serde::Deserialize;
use serde_json::{json, Map, Value};
use sqlx::{FromRow, Sqlite, SqlitePool, Transaction};
use std::collections::{HashMap, HashSet};

const PUBLISH_PLACEHOLDER_MEMBERSHIP_PREFIX: &str = "local-publish:";

#[derive(Debug, FromRow)]
struct BindingRow {
    server_instance_id: String,
    server_origin: String,
    account_id: String,
    session_id: String,
    membership_id: String,
    membership_version: i64,
    role: String,
    replica_state: String,
    last_applied_seq: i64,
    last_seen_head_seq: i64,
    joined_at: String,
    updated_at: String,
    revoked_at: Option<String>,
}

#[derive(Debug, FromRow)]
struct OutboxRow {
    #[sqlx(rename = "local_seq")]
    _local_seq: i64,
    mutation_id: String,
    entity_type: String,
    entity_id: String,
    operation: String,
    base_version: i64,
    observed_seq: i64,
    base_json: Option<String>,
    payload_json: String,
    state: String,
    attempts: i64,
    #[sqlx(rename = "next_attempt_at")]
    _next_attempt_at: Option<String>,
    depends_on_mutation_id: Option<String>,
    created_at: String,
}

#[derive(Debug, FromRow)]
struct ConflictRow {
    conflict_id: String,
    server_instance_id: String,
    account_id: String,
    session_id: String,
    entity_type: String,
    entity_id: String,
    mutation_id: String,
    base_version: i64,
    remote_version: i64,
    base_json: Option<String>,
    local_json: String,
    remote_json: String,
    state: String,
    created_at: String,
}

#[derive(Debug, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
struct CanonicalSessionEntity {
    session_id: String,
    title: String,
    status: String,
    version: i64,
    created_at: String,
    updated_at: String,
    closed_at: Option<String>,
    deleted_at: Option<String>,
}

/// Removes an accepted outbox root once an authoritative canonical baseline is
/// known to contain that mutation. A direct successor can only be rebased when
/// the canonical entity is exactly the root's `base + 1` version. If another
/// remote mutation has already advanced the entity further, retaining the
/// successor's old base deliberately lets the server return VERSION_CONFLICT
/// instead of silently applying a stale patch to a newer entity.
async fn acknowledge_outbox_root_covered_by_canonical(
    tx: &mut Transaction<'_, Sqlite>,
    server_instance_id: &str,
    account_id: &str,
    session_id: &str,
    mutation_id: &str,
    entity_type: &str,
    entity_id: &str,
    base_version: i64,
    canonical_version: i64,
    canonical_json: &str,
    canonical_cursor: i64,
    now: &str,
) -> anyhow::Result<bool> {
    let expected_version = base_version
        .checked_add(1)
        .ok_or_else(|| anyhow::anyhow!("OUTBOX_BASE_VERSION_INVALID"))?;
    if canonical_version < expected_version {
        return Ok(false);
    }

    if canonical_version == expected_version {
        sqlx::query(
            "UPDATE sync_outbox
             SET base_version = ?, base_json = ?, observed_seq = ?,
                 depends_on_mutation_id = NULL, updated_at = ?
             WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
               AND depends_on_mutation_id = ?
               AND entity_type = ? AND entity_id = ?",
        )
        .bind(canonical_version)
        .bind(canonical_json)
        .bind(canonical_cursor)
        .bind(now)
        .bind(server_instance_id)
        .bind(account_id)
        .bind(session_id)
        .bind(mutation_id)
        .bind(entity_type)
        .bind(entity_id)
        .execute(&mut **tx)
        .await?;
    }

    // Cross-entity dependencies are not produced by the current writer, but a
    // restored/older database must still be handled without assigning the
    // wrong entity JSON as its base. The same update also handles successors
    // when canonical_version > expected_version.
    sqlx::query(
        "UPDATE sync_outbox
         SET depends_on_mutation_id = NULL, updated_at = ?
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
           AND depends_on_mutation_id = ?",
    )
    .bind(now)
    .bind(server_instance_id)
    .bind(account_id)
    .bind(session_id)
    .bind(mutation_id)
    .execute(&mut **tx)
    .await?;

    let removed = sqlx::query(
        "DELETE FROM sync_outbox
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
           AND mutation_id = ? AND state = 'accepted'",
    )
    .bind(server_instance_id)
    .bind(account_id)
    .bind(session_id)
    .bind(mutation_id)
    .execute(&mut **tx)
    .await?;
    if removed.rows_affected() != 1 {
        anyhow::bail!("OUTBOX_ACCEPTED_MUTATION_NOT_FOUND");
    }
    Ok(true)
}

#[derive(Debug, FromRow)]
struct MaterializedLogRow {
    sync_id: String,
    session_id: String,
    time: String,
    controller: String,
    callsign: String,
    rst_sent: Option<String>,
    rst_rcvd: Option<String>,
    qth: Option<String>,
    device: Option<String>,
    power: Option<String>,
    antenna: Option<String>,
    height: Option<String>,
    remarks: Option<String>,
    created_at: String,
    updated_at: String,
    deleted_at: Option<String>,
}

impl MaterializedLogRow {
    fn into_json(self, version: i64) -> Value {
        json!({
            "syncId": self.sync_id,
            "sessionId": self.session_id,
            "version": version,
            "time": self.time,
            "controller": self.controller,
            "callsign": self.callsign,
            "rstSent": self.rst_sent,
            "rstRcvd": self.rst_rcvd,
            "qth": self.qth,
            "device": self.device,
            "power": self.power,
            "antenna": self.antenna,
            "height": self.height,
            "remarks": self.remarks,
            "createdAt": self.created_at,
            "updatedAt": self.updated_at,
            "deletedAt": self.deleted_at,
        })
    }
}

impl BindingRow {
    fn into_binding(self) -> anyhow::Result<CollaborationBinding> {
        Ok(CollaborationBinding {
            server_instance_id: self.server_instance_id,
            server_origin: self.server_origin,
            account_id: self.account_id,
            session_id: self.session_id,
            membership_id: self.membership_id,
            membership_version: self.membership_version,
            role: CollaborationRole::parse(&self.role)?,
            replica_state: self.replica_state,
            last_applied_seq: self.last_applied_seq,
            last_seen_head_seq: self.last_seen_head_seq,
            joined_at: self.joined_at,
            updated_at: self.updated_at,
            revoked_at: self.revoked_at,
        })
    }
}

#[derive(Debug, FromRow)]
struct LocalSessionRow {
    session_id: String,
    title: String,
    status: String,
    created_at: String,
    updated_at: String,
    closed_at: Option<String>,
    deleted_at: Option<String>,
}

impl LocalSessionRow {
    fn into_publish_session(self) -> PublishSession {
        PublishSession {
            session_id: self.session_id,
            title: self.title,
            status: self.status,
            created_at: self.created_at,
            updated_at: self.updated_at,
            closed_at: self.closed_at,
            deleted_at: self.deleted_at,
        }
    }
}

#[derive(Debug, FromRow)]
struct LocalLogRow {
    sync_id: String,
    time: String,
    controller: String,
    callsign: String,
    rst_sent: Option<String>,
    rst_rcvd: Option<String>,
    qth: Option<String>,
    device: Option<String>,
    power: Option<String>,
    antenna: Option<String>,
    height: Option<String>,
    remarks: Option<String>,
    created_at: String,
}

impl LocalLogRow {
    fn into_publish_log(self) -> anyhow::Result<PublishLog> {
        let time = normalize_publish_time(&self.time, &self.created_at, &self.sync_id)?;
        Ok(PublishLog {
            sync_id: self.sync_id,
            time,
            controller: self.controller,
            callsign: self.callsign,
            rst_sent: self.rst_sent,
            rst_rcvd: self.rst_rcvd,
            qth: self.qth,
            device: self.device,
            power: self.power,
            antenna: self.antenna,
            height: self.height,
            remarks: self.remarks,
        })
    }
}

fn normalize_publish_time(value: &str, created_at: &str, sync_id: &str) -> anyhow::Result<String> {
    let value = value.trim();
    if DateTime::parse_from_rfc3339(value).is_ok() {
        return Ok(value.to_string());
    }

    if let Ok(time) = NaiveTime::parse_from_str(value, "%H:%M") {
        let created = DateTime::parse_from_rfc3339(created_at)
            .map_err(|_| anyhow::anyhow!("LOCAL_LOG_TIME_INVALID:{sync_id}"))?;
        let combined = created
            .offset()
            .from_local_datetime(&created.date_naive().and_time(time))
            .single()
            .ok_or_else(|| anyhow::anyhow!("LOCAL_LOG_TIME_INVALID:{sync_id}"))?;
        return Ok(combined.to_rfc3339());
    }

    anyhow::bail!("LOCAL_LOG_TIME_INVALID:{sync_id}")
}

fn require_text(value: &str, code: &str) -> anyhow::Result<()> {
    if value.trim().is_empty() {
        anyhow::bail!(code.to_string());
    }
    Ok(())
}

fn validate_install_request(request: &InstallSnapshotRequest) -> anyhow::Result<()> {
    require_text(&request.server_instance_id, "SNAPSHOT_SERVER_ID_REQUIRED")?;
    require_text(&request.server_origin, "SNAPSHOT_SERVER_ORIGIN_REQUIRED")?;
    require_text(&request.account_id, "SNAPSHOT_ACCOUNT_ID_REQUIRED")?;

    let snapshot = &request.snapshot;
    if snapshot.protocol_version != 1 {
        anyhow::bail!("SNAPSHOT_PROTOCOL_MISMATCH");
    }
    if !snapshot.includes_deleted_logs && snapshot.logs.iter().any(|log| log.deleted_at.is_some()) {
        anyhow::bail!("SNAPSHOT_DELETED_LOGS_FLAG_INVALID");
    }
    if snapshot.high_watermark_seq < 0
        || snapshot.session.high_watermark_seq != snapshot.high_watermark_seq
    {
        anyhow::bail!("SNAPSHOT_CURSOR_INVALID");
    }
    if snapshot.session.version < 1 || request.membership.version < 1 {
        anyhow::bail!("SNAPSHOT_VERSION_INVALID");
    }
    if snapshot.session.deleted_at.is_some() {
        anyhow::bail!("SNAPSHOT_SESSION_DELETED");
    }
    if snapshot.session.status != "active" && snapshot.session.status != "closed" {
        anyhow::bail!("SNAPSHOT_SESSION_STATUS_INVALID");
    }
    for value in [&snapshot.session.created_at, &snapshot.session.updated_at] {
        DateTime::parse_from_rfc3339(value)
            .map_err(|_| anyhow::anyhow!("SNAPSHOT_SESSION_TIME_INVALID"))?;
    }
    if let Some(value) = &snapshot.session.closed_at {
        DateTime::parse_from_rfc3339(value)
            .map_err(|_| anyhow::anyhow!("SNAPSHOT_SESSION_TIME_INVALID"))?;
    }
    if request.membership.removed_at.is_some() {
        anyhow::bail!("SNAPSHOT_MEMBERSHIP_REVOKED");
    }
    for value in [
        &request.membership.joined_at,
        &request.membership.updated_at,
    ] {
        DateTime::parse_from_rfc3339(value)
            .map_err(|_| anyhow::anyhow!("SNAPSHOT_MEMBERSHIP_TIME_INVALID"))?;
    }
    if request.membership.session_id != snapshot.session.session_id
        || request.membership.user_id != request.account_id
        || request.membership.role != snapshot.session.role
    {
        anyhow::bail!("SNAPSHOT_IDENTITY_MISMATCH");
    }
    require_text(&snapshot.session.session_id, "SNAPSHOT_SESSION_ID_REQUIRED")?;
    require_text(
        &request.membership.membership_id,
        "SNAPSHOT_MEMBERSHIP_ID_REQUIRED",
    )?;
    if request
        .membership
        .membership_id
        .starts_with(PUBLISH_PLACEHOLDER_MEMBERSHIP_PREFIX)
    {
        anyhow::bail!("SNAPSHOT_MEMBERSHIP_ID_RESERVED");
    }

    let mut sync_ids = HashSet::with_capacity(snapshot.logs.len());
    for log in &snapshot.logs {
        if log.session_id != snapshot.session.session_id {
            anyhow::bail!("SNAPSHOT_LOG_SESSION_MISMATCH");
        }
        if log.version < 1 {
            anyhow::bail!("SNAPSHOT_VERSION_INVALID");
        }
        for value in [&log.time, &log.created_at, &log.updated_at] {
            DateTime::parse_from_rfc3339(value)
                .map_err(|_| anyhow::anyhow!("SNAPSHOT_LOG_TIME_INVALID"))?;
        }
        if let Some(value) = &log.deleted_at {
            DateTime::parse_from_rfc3339(value)
                .map_err(|_| anyhow::anyhow!("SNAPSHOT_LOG_TIME_INVALID"))?;
        }
        require_text(&log.sync_id, "SNAPSHOT_LOG_ID_REQUIRED")?;
        if !sync_ids.insert(log.sync_id.as_str()) {
            anyhow::bail!("SNAPSHOT_DUPLICATE_LOG_ID");
        }
    }
    Ok(())
}

async fn writable_binding(
    tx: &mut Transaction<'_, Sqlite>,
    session_id: &str,
    session_owner_only: bool,
) -> anyhow::Result<Option<BindingRow>> {
    let binding = sqlx::query_as::<_, BindingRow>(
        "SELECT * FROM collaboration_bindings WHERE session_id = ?",
    )
    .bind(session_id)
    .fetch_optional(&mut **tx)
    .await?;
    let Some(binding) = binding else {
        return Ok(None);
    };

    if binding.replica_state == "revoked" || binding.revoked_at.is_some() {
        anyhow::bail!("COLLABORATION_MEMBERSHIP_REVOKED");
    }
    if binding.replica_state != "ready" {
        anyhow::bail!("COLLABORATION_SESSION_READ_ONLY");
    }
    if session_owner_only && binding.role != "owner" {
        anyhow::bail!("COLLABORATION_OWNER_REQUIRED");
    }
    if !session_owner_only && binding.role != "owner" && binding.role != "editor" {
        anyhow::bail!("COLLABORATION_ROLE_READ_ONLY");
    }

    let status: Option<(String, Option<String>)> =
        sqlx::query_as("SELECT status, deleted_at FROM sessions WHERE session_id = ?")
            .bind(session_id)
            .fetch_optional(&mut **tx)
            .await?;
    let Some((status, deleted_at)) = status else {
        anyhow::bail!("LOCAL_SESSION_NOT_FOUND");
    };
    if deleted_at.is_some() {
        anyhow::bail!("SESSION_DELETED");
    }
    if status == "closed" {
        anyhow::bail!("SESSION_CLOSED");
    }
    if status != "active" {
        anyhow::bail!("COLLABORATION_SESSION_READ_ONLY");
    }
    let canonical_status = canonical_session_status_in_tx(
        tx,
        &binding.server_instance_id,
        &binding.account_id,
        session_id,
    )
    .await?;
    match canonical_status.as_str() {
        "active" => {}
        "closed" => anyhow::bail!("SESSION_CLOSED"),
        "deleted" => anyhow::bail!("SESSION_DELETED"),
        _ => anyhow::bail!("COLLABORATION_SESSION_SHADOW_INVALID"),
    }
    Ok(Some(binding))
}

pub async fn get_or_create_device_id(pool: &SqlitePool) -> anyhow::Result<String> {
    let mut tx = pool.begin().await?;
    let candidate = uuid::Uuid::new_v4().to_string();
    sqlx::query("INSERT OR IGNORE INTO device_state (id, device_id, created_at) VALUES (1, ?, ?)")
        .bind(candidate)
        .bind(chrono::Utc::now().to_rfc3339())
        .execute(&mut *tx)
        .await?;
    let (device_id,): (String,) = sqlx::query_as("SELECT device_id FROM device_state WHERE id = 1")
        .fetch_one(&mut *tx)
        .await?;
    tx.commit().await?;
    Ok(device_id)
}

pub async fn get_binding(
    pool: &SqlitePool,
    server_instance_id: &str,
    account_id: &str,
    session_id: &str,
) -> anyhow::Result<Option<CollaborationBinding>> {
    let row = sqlx::query_as::<_, BindingRow>(
        "SELECT * FROM collaboration_bindings
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?",
    )
    .bind(server_instance_id)
    .bind(account_id)
    .bind(session_id)
    .fetch_optional(pool)
    .await?;
    row.map(BindingRow::into_binding).transpose()
}

pub async fn get_binding_for_session(
    pool: &SqlitePool,
    session_id: &str,
) -> anyhow::Result<Option<CollaborationBinding>> {
    let row = sqlx::query_as::<_, BindingRow>(
        "SELECT * FROM collaboration_bindings WHERE session_id = ?",
    )
    .bind(session_id)
    .fetch_optional(pool)
    .await?;
    row.map(BindingRow::into_binding).transpose()
}

async fn read_publish_snapshot(
    tx: &mut Transaction<'_, Sqlite>,
    session_id: &str,
) -> anyhow::Result<PublishSnapshot> {
    let session = sqlx::query_as::<_, LocalSessionRow>(
        "SELECT session_id, title, status, created_at, updated_at, closed_at, deleted_at
         FROM sessions WHERE session_id = ? AND deleted_at IS NULL",
    )
    .bind(session_id)
    .fetch_optional(&mut **tx)
    .await?
    .ok_or_else(|| anyhow::anyhow!("LOCAL_SESSION_NOT_FOUND"))?;
    let logs = sqlx::query_as::<_, LocalLogRow>(
        "SELECT sync_id, time, controller, callsign,
                rst_sent, rst_rcvd, qth, device, power, antenna, height, remarks,
                created_at
         FROM logs
         WHERE session_id = ? AND deleted_at IS NULL
         ORDER BY time, sync_id",
    )
    .bind(session_id)
    .fetch_all(&mut **tx)
    .await?;
    Ok(PublishSnapshot {
        lease_created: false,
        session: session.into_publish_session(),
        logs: logs
            .into_iter()
            .map(LocalLogRow::into_publish_log)
            .collect::<anyhow::Result<Vec<_>>>()?,
    })
}

pub async fn begin_publish_snapshot(
    pool: &SqlitePool,
    server_instance_id: &str,
    server_origin: &str,
    account_id: &str,
    session_id: &str,
) -> anyhow::Result<PublishSnapshot> {
    require_text(server_instance_id, "PUBLISH_SERVER_ID_REQUIRED")?;
    require_text(server_origin, "PUBLISH_SERVER_ORIGIN_REQUIRED")?;
    require_text(account_id, "PUBLISH_ACCOUNT_ID_REQUIRED")?;
    require_text(session_id, "PUBLISH_SESSION_ID_REQUIRED")?;

    let mut tx = pool.begin().await?;
    let local_session: (i64,) =
        sqlx::query_as("SELECT COUNT(*) FROM sessions WHERE session_id = ? AND deleted_at IS NULL")
            .bind(session_id)
            .fetch_one(&mut *tx)
            .await?;
    if local_session.0 == 0 {
        anyhow::bail!("LOCAL_SESSION_NOT_FOUND");
    }

    let existing = sqlx::query_as::<_, BindingRow>(
        "SELECT * FROM collaboration_bindings WHERE session_id = ?",
    )
    .bind(session_id)
    .fetch_optional(&mut *tx)
    .await?;
    let now = chrono::Utc::now().to_rfc3339();
    let lease_created = existing.is_none();
    if let Some(binding) = existing {
        if binding.server_instance_id != server_instance_id || binding.account_id != account_id {
            anyhow::bail!("BINDING_IDENTITY_CONFLICT");
        }
        if binding.replica_state != "publishing" {
            anyhow::bail!("PUBLISH_NOT_ACTIVE");
        }
        sqlx::query(
            "UPDATE collaboration_bindings
             SET server_origin = ?, updated_at = ?
             WHERE server_instance_id = ? AND account_id = ? AND session_id = ?",
        )
        .bind(server_origin)
        .bind(&now)
        .bind(server_instance_id)
        .bind(account_id)
        .bind(session_id)
        .execute(&mut *tx)
        .await?;
    } else {
        let placeholder_membership_id = format!(
            "{PUBLISH_PLACEHOLDER_MEMBERSHIP_PREFIX}{}",
            uuid::Uuid::new_v4()
        );
        sqlx::query(
            "INSERT INTO collaboration_bindings (
                server_instance_id, server_origin, account_id, session_id,
                membership_id, membership_version, role, replica_state,
                last_applied_seq, last_seen_head_seq, joined_at, updated_at, revoked_at
             ) VALUES (?, ?, ?, ?, ?, 1, 'owner', 'publishing', 0, 0, ?, ?, NULL)",
        )
        .bind(server_instance_id)
        .bind(server_origin)
        .bind(account_id)
        .bind(session_id)
        .bind(placeholder_membership_id)
        .bind(&now)
        .bind(&now)
        .execute(&mut *tx)
        .await?;
    }

    let mut snapshot = read_publish_snapshot(&mut tx, session_id).await?;
    snapshot.lease_created = lease_created;
    tx.commit().await?;
    Ok(snapshot)
}

pub async fn abort_publish(
    pool: &SqlitePool,
    server_instance_id: &str,
    account_id: &str,
    session_id: &str,
) -> anyhow::Result<()> {
    let mut tx = pool.begin().await?;
    let existing = sqlx::query_as::<_, BindingRow>(
        "SELECT * FROM collaboration_bindings WHERE session_id = ?",
    )
    .bind(session_id)
    .fetch_optional(&mut *tx)
    .await?;
    let Some(binding) = existing else {
        tx.commit().await?;
        return Ok(());
    };
    if binding.server_instance_id != server_instance_id || binding.account_id != account_id {
        anyhow::bail!("BINDING_IDENTITY_CONFLICT");
    }
    if binding.replica_state != "publishing" {
        anyhow::bail!("PUBLISH_NOT_ACTIVE");
    }
    sqlx::query(
        "DELETE FROM collaboration_bindings
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
           AND replica_state = 'publishing'",
    )
    .bind(server_instance_id)
    .bind(account_id)
    .bind(session_id)
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(())
}

pub async fn get_publish_snapshot(
    pool: &SqlitePool,
    session_id: &str,
) -> anyhow::Result<PublishSnapshot> {
    let mut tx = pool.begin().await?;
    let publishing: (i64,) = sqlx::query_as(
        "SELECT COUNT(*) FROM collaboration_bindings
         WHERE session_id = ? AND replica_state = 'publishing'",
    )
    .bind(session_id)
    .fetch_one(&mut *tx)
    .await?;
    if publishing.0 != 1 {
        anyhow::bail!("PUBLISH_NOT_STARTED");
    }
    let snapshot = read_publish_snapshot(&mut tx, session_id).await?;
    tx.commit().await?;
    Ok(snapshot)
}

pub async fn install_snapshot(
    pool: &SqlitePool,
    request: InstallSnapshotRequest,
) -> anyhow::Result<CollaborationBinding> {
    validate_install_request(&request)?;
    let snapshot = &request.snapshot;
    let session_id = snapshot.session.session_id.as_str();
    let mut tx = pool.begin().await?;

    let local_session_exists: (i64,) =
        sqlx::query_as("SELECT COUNT(*) FROM sessions WHERE session_id = ?")
            .bind(session_id)
            .fetch_one(&mut *tx)
            .await?;
    let existing_binding = sqlx::query_as::<_, BindingRow>(
        "SELECT * FROM collaboration_bindings WHERE session_id = ?",
    )
    .bind(session_id)
    .fetch_optional(&mut *tx)
    .await?;
    let complete_reinstall =
        request.mode == SnapshotInstallMode::Join && existing_binding.is_some();

    if let Some(existing) = &existing_binding {
        if existing.server_instance_id != request.server_instance_id
            || existing.account_id != request.account_id
        {
            anyhow::bail!("BINDING_IDENTITY_CONFLICT");
        }
    }
    match request.mode {
        SnapshotInstallMode::Publish => {
            if local_session_exists.0 == 0 {
                anyhow::bail!("LOCAL_SESSION_NOT_FOUND");
            }
            let existing = existing_binding
                .as_ref()
                .ok_or_else(|| anyhow::anyhow!("PUBLISH_NOT_STARTED"))?;
            if existing.replica_state != "publishing" {
                anyhow::bail!("PUBLISH_NOT_ACTIVE");
            }
        }
        SnapshotInstallMode::Join => {
            if let Some(existing) = &existing_binding {
                if !snapshot.includes_deleted_logs {
                    anyhow::bail!("SNAPSHOT_TOMBSTONES_REQUIRED");
                }
                let explicit_rejoin = existing.replica_state == "revoked"
                    && existing.membership_id == request.membership.membership_id
                    && request.membership.version > existing.membership_version;
                if existing.replica_state == "revoked" && !explicit_rejoin {
                    anyhow::bail!("BINDING_REVOKED");
                }
                if existing.replica_state != "ready" && !explicit_rejoin {
                    anyhow::bail!("BINDING_STATE_CONFLICT");
                }
                if existing.membership_id != request.membership.membership_id {
                    anyhow::bail!("BINDING_MEMBERSHIP_CONFLICT");
                }
                if snapshot.high_watermark_seq < existing.last_applied_seq {
                    anyhow::bail!("SNAPSHOT_CURSOR_REGRESSION");
                }
                if snapshot.high_watermark_seq < existing.last_seen_head_seq {
                    anyhow::bail!("SNAPSHOT_HEAD_REGRESSION");
                }
                if request.membership.version < existing.membership_version {
                    anyhow::bail!("SNAPSHOT_MEMBERSHIP_VERSION_REGRESSION");
                }
                if request.membership.version == existing.membership_version
                    && request.membership.role.as_str() != existing.role
                {
                    anyhow::bail!("SNAPSHOT_MEMBERSHIP_VERSION_FORK");
                }
            } else if local_session_exists.0 > 0 {
                anyhow::bail!("LOCAL_SESSION_ID_CONFLICT");
            }
        }
    }

    for log in &snapshot.logs {
        let collision: Option<(String,)> = sqlx::query_as(
            "SELECT session_id FROM logs
             WHERE sync_id = ? AND session_id <> ? LIMIT 1",
        )
        .bind(&log.sync_id)
        .bind(session_id)
        .fetch_optional(&mut *tx)
        .await?;
        if collision.is_some() {
            anyhow::bail!("LOCAL_LOG_ID_CONFLICT");
        }
    }

    let source_devices = sqlx::query_as::<_, (String, Option<String>)>(
        "SELECT sync_id, source_device_id FROM logs WHERE session_id = ?",
    )
    .bind(session_id)
    .fetch_all(&mut *tx)
    .await?
    .into_iter()
    .collect::<HashMap<_, _>>();
    let pending_materialized_logs = sqlx::query_as::<_, MaterializedLogRow>(
        "SELECT DISTINCT
                l.sync_id, l.session_id, l.time, l.controller, l.callsign,
                l.rst_sent, l.rst_rcvd, l.qth, l.device, l.power, l.antenna,
                l.height, l.remarks, l.created_at, l.updated_at, l.deleted_at
         FROM logs l
         JOIN sync_outbox o
           ON o.session_id = l.session_id AND o.entity_type = 'log'
          AND o.entity_id = l.sync_id
         WHERE o.server_instance_id = ? AND o.account_id = ? AND o.session_id = ?",
    )
    .bind(&request.server_instance_id)
    .bind(&request.account_id)
    .bind(session_id)
    .fetch_all(&mut *tx)
    .await?
    .into_iter()
    .map(|row| (row.sync_id.clone(), row.into_json(0)))
    .collect::<HashMap<_, _>>();

    sqlx::query(
        "INSERT INTO sessions (
            session_id, title, status, share_code, created_at, updated_at, closed_at, deleted_at
         ) VALUES (?, ?, ?, NULL, ?, ?, ?, ?)
         ON CONFLICT(session_id) DO UPDATE SET
            title = excluded.title,
            status = excluded.status,
            share_code = NULL,
            created_at = excluded.created_at,
            updated_at = excluded.updated_at,
            closed_at = excluded.closed_at,
            deleted_at = excluded.deleted_at",
    )
    .bind(session_id)
    .bind(&snapshot.session.title)
    .bind(&snapshot.session.status)
    .bind(&snapshot.session.created_at)
    .bind(&snapshot.session.updated_at)
    .bind(&snapshot.session.closed_at)
    .bind(&snapshot.session.deleted_at)
    .execute(&mut *tx)
    .await?;

    let now = chrono::Utc::now().to_rfc3339();
    sqlx::query(
        "INSERT INTO collaboration_bindings (
            server_instance_id, server_origin, account_id, session_id,
            membership_id, membership_version, role, replica_state,
            last_applied_seq, last_seen_head_seq, joined_at, updated_at, revoked_at
         ) VALUES (?, ?, ?, ?, ?, ?, ?, 'ready', ?, ?, ?, ?, NULL)
         ON CONFLICT(server_instance_id, account_id, session_id) DO UPDATE SET
            server_origin = excluded.server_origin,
            membership_id = excluded.membership_id,
            membership_version = excluded.membership_version,
            role = excluded.role,
            replica_state = 'ready',
            last_applied_seq = excluded.last_applied_seq,
            last_seen_head_seq = excluded.last_seen_head_seq,
            joined_at = excluded.joined_at,
            updated_at = excluded.updated_at,
            revoked_at = NULL",
    )
    .bind(&request.server_instance_id)
    .bind(&request.server_origin)
    .bind(&request.account_id)
    .bind(session_id)
    .bind(&request.membership.membership_id)
    .bind(request.membership.version)
    .bind(request.membership.role.as_str())
    .bind(snapshot.high_watermark_seq)
    .bind(snapshot.high_watermark_seq)
    .bind(&request.membership.joined_at)
    .bind(&now)
    .execute(&mut *tx)
    .await?;

    sqlx::query("DELETE FROM logs WHERE session_id = ?")
        .bind(session_id)
        .execute(&mut *tx)
        .await?;

    for log in &snapshot.logs {
        sqlx::query(
            "INSERT INTO logs (
                sync_id, session_id, time, controller, callsign,
                rst_sent, rst_rcvd, qth, device, power, antenna, height, remarks,
                created_at, updated_at, deleted_at, source_device_id
             ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        )
        .bind(&log.sync_id)
        .bind(&log.session_id)
        .bind(&log.time)
        .bind(&log.controller)
        .bind(&log.callsign)
        .bind(&log.rst_sent)
        .bind(&log.rst_rcvd)
        .bind(&log.qth)
        .bind(&log.device)
        .bind(&log.power)
        .bind(&log.antenna)
        .bind(&log.height)
        .bind(&log.remarks)
        .bind(&log.created_at)
        .bind(&log.updated_at)
        .bind(&log.deleted_at)
        .bind(source_devices.get(&log.sync_id).cloned().flatten())
        .execute(&mut *tx)
        .await?;
    }

    sqlx::query(
        "DELETE FROM entity_shadows
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?",
    )
    .bind(&request.server_instance_id)
    .bind(&request.account_id)
    .bind(session_id)
    .execute(&mut *tx)
    .await?;

    let session_json = serde_json::to_string(&snapshot.session)?;
    sqlx::query(
        "INSERT INTO entity_shadows (
            server_instance_id, account_id, session_id, entity_type, entity_id,
            server_version, last_event_seq, server_json, deleted
         ) VALUES (?, ?, ?, 'session', ?, ?, ?, ?, ?)",
    )
    .bind(&request.server_instance_id)
    .bind(&request.account_id)
    .bind(session_id)
    .bind(session_id)
    .bind(snapshot.session.version)
    .bind(snapshot.high_watermark_seq)
    .bind(session_json)
    .bind(i64::from(snapshot.session.deleted_at.is_some()))
    .execute(&mut *tx)
    .await?;

    for log in &snapshot.logs {
        let log_json = serde_json::to_string(log)?;
        sqlx::query(
            "INSERT INTO entity_shadows (
                server_instance_id, account_id, session_id, entity_type, entity_id,
                server_version, last_event_seq, server_json, deleted
             ) VALUES (?, ?, ?, 'log', ?, ?, ?, ?, ?)",
        )
        .bind(&request.server_instance_id)
        .bind(&request.account_id)
        .bind(session_id)
        .bind(&log.sync_id)
        .bind(log.version)
        .bind(snapshot.high_watermark_seq)
        .bind(log_json)
        .bind(i64::from(log.deleted_at.is_some()))
        .execute(&mut *tx)
        .await?;
    }

    // A snapshot establishes a new cursor baseline. Old event IDs no longer
    // participate in duplicate validation, while pending/outbox state remains
    // partitioned and is overlaid again below.
    sqlx::query(
        "DELETE FROM applied_events
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?",
    )
    .bind(&request.server_instance_id)
    .bind(&request.account_id)
    .bind(session_id)
    .execute(&mut *tx)
    .await?;

    let acknowledged = sqlx::query_as::<_, (String, String, String, i64)>(
        "SELECT mutation_id, entity_type, entity_id, base_version
         FROM sync_outbox
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
           AND state = 'accepted' AND accepted_event_seq <= ?
         ORDER BY local_seq",
    )
    .bind(&request.server_instance_id)
    .bind(&request.account_id)
    .bind(session_id)
    .bind(snapshot.high_watermark_seq)
    .fetch_all(&mut *tx)
    .await?;
    for (mutation_id, entity_type, entity_id, base_version) in acknowledged {
        let canonical: Option<(i64, String)> = sqlx::query_as(
            "SELECT server_version, server_json FROM entity_shadows
             WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
               AND entity_type = ? AND entity_id = ?",
        )
        .bind(&request.server_instance_id)
        .bind(&request.account_id)
        .bind(session_id)
        .bind(&entity_type)
        .bind(&entity_id)
        .fetch_optional(&mut *tx)
        .await?;
        let Some((version, server_json)) = canonical else {
            // A complete reinstall includes tombstones, so an accepted entity
            // covered by the new cursor cannot be absent. Abort rather than
            // advance the cursor and strand an acknowledgement below it.
            anyhow::bail!("SNAPSHOT_ACCEPTED_ENTITY_MISSING");
        };
        acknowledge_outbox_root_covered_by_canonical(
            &mut tx,
            &request.server_instance_id,
            &request.account_id,
            session_id,
            &mutation_id,
            &entity_type,
            &entity_id,
            base_version,
            version,
            &server_json,
            snapshot.high_watermark_seq,
            &now,
        )
        .await?;
    }

    let pending_entities = sqlx::query_as::<_, (String, String)>(
        "SELECT DISTINCT entity_type, entity_id FROM sync_outbox
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?",
    )
    .bind(&request.server_instance_id)
    .bind(&request.account_id)
    .bind(session_id)
    .fetch_all(&mut *tx)
    .await?;
    for (entity_type, entity_id) in pending_entities {
        let canonical: Option<(String,)> = sqlx::query_as(
            "SELECT server_json FROM entity_shadows
             WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
               AND entity_type = ? AND entity_id = ?",
        )
        .bind(&request.server_instance_id)
        .bind(&request.account_id)
        .bind(session_id)
        .bind(&entity_type)
        .bind(&entity_id)
        .fetch_optional(&mut *tx)
        .await?;
        let base = if let Some((server_json,)) = canonical {
            serde_json::from_str(&server_json)?
        } else if entity_type == "log" {
            if complete_reinstall {
                let root: Option<(String, i64, Option<String>)> = sqlx::query_as(
                    "SELECT operation, base_version, depends_on_mutation_id
                     FROM sync_outbox
                     WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
                       AND entity_type = ? AND entity_id = ?
                     ORDER BY local_seq LIMIT 1",
                )
                .bind(&request.server_instance_id)
                .bind(&request.account_id)
                .bind(session_id)
                .bind(&entity_type)
                .bind(&entity_id)
                .fetch_optional(&mut *tx)
                .await?;
                if !root.is_some_and(|(operation, base_version, dependency)| {
                    operation == "create" && base_version == 0 && dependency.is_none()
                }) {
                    anyhow::bail!("SNAPSHOT_PENDING_ENTITY_MISSING");
                }
            }
            pending_materialized_logs
                .get(&entity_id)
                .cloned()
                .ok_or_else(|| anyhow::anyhow!("SNAPSHOT_PENDING_ENTITY_MISSING"))?
        } else {
            anyhow::bail!("SNAPSHOT_PENDING_ENTITY_MISSING");
        };
        let overlay_request = ApplyEventRequest {
            server_instance_id: request.server_instance_id.clone(),
            account_id: request.account_id.clone(),
            event: crate::models::collaboration::CanonicalEvent {
                protocol_version: 1,
                event_id: "snapshot-overlay".to_string(),
                session_id: session_id.to_string(),
                seq: snapshot.high_watermark_seq.max(1),
                event_type: if entity_type == "log" {
                    "log.updated".to_string()
                } else {
                    "session.updated".to_string()
                },
                entity_type: entity_type.clone(),
                entity_id: entity_id.clone(),
                entity_version: base.get("version").and_then(Value::as_i64).unwrap_or(1),
                mutation_id: None,
                occurred_at: now.clone(),
                payload: base.clone(),
            },
        };
        let materialized = apply_pending_overlay(&mut tx, &overlay_request, base).await?;
        if entity_type == "log" {
            write_materialized_log(&mut tx, materialized).await?;
            if let Some(source_device) = source_devices.get(&entity_id) {
                sqlx::query("UPDATE logs SET source_device_id = ? WHERE sync_id = ?")
                    .bind(source_device)
                    .bind(&entity_id)
                    .execute(&mut *tx)
                    .await?;
            }
        } else {
            write_materialized_session(&mut tx, materialized).await?;
        }
    }

    let installed = sqlx::query_as::<_, BindingRow>(
        "SELECT * FROM collaboration_bindings
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?",
    )
    .bind(&request.server_instance_id)
    .bind(&request.account_id)
    .bind(session_id)
    .fetch_one(&mut *tx)
    .await?
    .into_binding()?;
    tx.commit().await?;
    Ok(installed)
}

pub async fn mark_revoked(
    pool: &SqlitePool,
    server_instance_id: &str,
    account_id: &str,
    session_id: &str,
) -> anyhow::Result<()> {
    let now = chrono::Utc::now().to_rfc3339();
    let result = sqlx::query(
        "UPDATE collaboration_bindings
         SET replica_state = 'revoked', revoked_at = ?, updated_at = ?
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?",
    )
    .bind(&now)
    .bind(&now)
    .bind(server_instance_id)
    .bind(account_id)
    .bind(session_id)
    .execute(pool)
    .await?;
    if result.rows_affected() != 1 {
        anyhow::bail!("BINDING_NOT_FOUND");
    }
    Ok(())
}

pub async fn update_membership(
    pool: &SqlitePool,
    server_instance_id: &str,
    account_id: &str,
    session_id: &str,
    membership_id: &str,
    membership_version: i64,
    role: CollaborationRole,
) -> anyhow::Result<CollaborationBinding> {
    if membership_version < 1 {
        anyhow::bail!("MEMBERSHIP_VERSION_INVALID");
    }
    let mut tx = pool.begin().await?;
    let binding =
        require_partition_binding(&mut tx, server_instance_id, account_id, session_id).await?;
    if binding.membership_id != membership_id {
        anyhow::bail!("BINDING_MEMBERSHIP_CONFLICT");
    }
    if membership_version < binding.membership_version {
        anyhow::bail!("MEMBERSHIP_VERSION_REGRESSION");
    }
    if membership_version == binding.membership_version && role.as_str() != binding.role {
        anyhow::bail!("MEMBERSHIP_VERSION_FORK");
    }
    if membership_version > binding.membership_version {
        sqlx::query(
            "UPDATE collaboration_bindings
             SET membership_version = ?, role = ?, updated_at = ?
             WHERE server_instance_id = ? AND account_id = ? AND session_id = ?",
        )
        .bind(membership_version)
        .bind(role.as_str())
        .bind(chrono::Utc::now().to_rfc3339())
        .bind(server_instance_id)
        .bind(account_id)
        .bind(session_id)
        .execute(&mut *tx)
        .await?;
    }
    let updated = sqlx::query_as::<_, BindingRow>(
        "SELECT * FROM collaboration_bindings
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?",
    )
    .bind(server_instance_id)
    .bind(account_id)
    .bind(session_id)
    .fetch_one(&mut *tx)
    .await?
    .into_binding()?;
    tx.commit().await?;
    Ok(updated)
}

fn log_mutation_value(entry: &LogEntry) -> anyhow::Result<Value> {
    let time = normalize_publish_time(&entry.time, &entry.created_at, &entry.sync_id)?;
    Ok(json!({
        "syncId": entry.sync_id,
        "sessionId": entry.session_id,
        "time": time,
        "controller": entry.controller,
        "callsign": entry.callsign,
        "rstSent": entry.rst_sent,
        "rstRcvd": entry.rst_rcvd,
        "qth": entry.qth,
        "device": entry.device,
        "power": entry.power,
        "antenna": entry.antenna,
        "height": entry.height,
        "remarks": entry.remarks,
    }))
}

fn log_patch(before: &LogEntry, after: &LogEntry) -> anyhow::Result<Map<String, Value>> {
    let before = log_mutation_value(before)?;
    let after = log_mutation_value(after)?;
    let before = before
        .as_object()
        .ok_or_else(|| anyhow::anyhow!("OUTBOX_LOG_VALUE_INVALID"))?;
    let after = after
        .as_object()
        .ok_or_else(|| anyhow::anyhow!("OUTBOX_LOG_VALUE_INVALID"))?;
    Ok(after
        .iter()
        .filter_map(|(key, value)| {
            if key == "syncId" || key == "sessionId" || before.get(key) == Some(value) {
                None
            } else {
                Some((key.clone(), value.clone()))
            }
        })
        .collect())
}

async fn shadow_base(
    tx: &mut Transaction<'_, Sqlite>,
    binding: &BindingRow,
    entity_type: &str,
    entity_id: &str,
) -> anyhow::Result<(i64, String)> {
    sqlx::query_as(
        "SELECT server_version, server_json FROM entity_shadows
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
           AND entity_type = ? AND entity_id = ?",
    )
    .bind(&binding.server_instance_id)
    .bind(&binding.account_id)
    .bind(&binding.session_id)
    .bind(entity_type)
    .bind(entity_id)
    .fetch_optional(&mut **tx)
    .await?
    .ok_or_else(|| anyhow::anyhow!("COLLABORATION_SHADOW_MISSING"))
}

async fn latest_entity_outbox(
    tx: &mut Transaction<'_, Sqlite>,
    binding: &BindingRow,
    entity_type: &str,
    entity_id: &str,
) -> anyhow::Result<Option<OutboxRow>> {
    Ok(sqlx::query_as::<_, OutboxRow>(
        "SELECT local_seq, mutation_id, entity_type, entity_id, operation,
                base_version, observed_seq, base_json, payload_json, state,
                attempts, next_attempt_at, depends_on_mutation_id, created_at
         FROM sync_outbox
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
           AND entity_type = ? AND entity_id = ?
         ORDER BY local_seq DESC LIMIT 1",
    )
    .bind(&binding.server_instance_id)
    .bind(&binding.account_id)
    .bind(&binding.session_id)
    .bind(entity_type)
    .bind(entity_id)
    .fetch_optional(&mut **tx)
    .await?)
}

async fn insert_outbox(
    tx: &mut Transaction<'_, Sqlite>,
    binding: &BindingRow,
    entity_type: &str,
    entity_id: &str,
    operation: &str,
    base_version: i64,
    base_json: Option<&str>,
    payload: &Value,
    depends_on_mutation_id: Option<&str>,
) -> anyhow::Result<String> {
    let mutation_id = uuid::Uuid::new_v4().to_string();
    let now = chrono::Utc::now().to_rfc3339();
    sqlx::query(
        "INSERT INTO sync_outbox (
            server_instance_id, account_id, session_id, mutation_id,
            entity_type, entity_id, operation, base_version, observed_seq,
            base_json, payload_json, state, attempts, next_attempt_at,
            accepted_event_seq, depends_on_mutation_id,
            last_error_code, last_error_message, created_at, updated_at
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', 0, NULL,
                   NULL, ?, NULL, NULL, ?, ?)",
    )
    .bind(&binding.server_instance_id)
    .bind(&binding.account_id)
    .bind(&binding.session_id)
    .bind(&mutation_id)
    .bind(entity_type)
    .bind(entity_id)
    .bind(operation)
    .bind(base_version)
    .bind(binding.last_applied_seq)
    .bind(base_json)
    .bind(serde_json::to_string(payload)?)
    .bind(depends_on_mutation_id)
    .bind(&now)
    .bind(&now)
    .execute(&mut **tx)
    .await?;
    Ok(mutation_id)
}

async fn discard_rejected_entity_chain(
    tx: &mut Transaction<'_, Sqlite>,
    binding: &BindingRow,
    entity_type: &str,
    entity_id: &str,
) -> anyhow::Result<Option<(i64, Option<String>)>> {
    let rejected: Option<(i64, i64, Option<String>)> = sqlx::query_as(
        "SELECT local_seq, base_version, base_json FROM sync_outbox
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
           AND entity_type = ? AND entity_id = ? AND state = 'rejected'
         ORDER BY local_seq LIMIT 1",
    )
    .bind(&binding.server_instance_id)
    .bind(&binding.account_id)
    .bind(&binding.session_id)
    .bind(entity_type)
    .bind(entity_id)
    .fetch_optional(&mut **tx)
    .await?;
    let Some((rejected_seq, rejected_base_version, rejected_base_json)) = rejected else {
        return Ok(None);
    };

    let earlier: (i64,) = sqlx::query_as(
        "SELECT COUNT(*) FROM sync_outbox
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
           AND entity_type = ? AND entity_id = ? AND local_seq < ?",
    )
    .bind(&binding.server_instance_id)
    .bind(&binding.account_id)
    .bind(&binding.session_id)
    .bind(entity_type)
    .bind(entity_id)
    .bind(rejected_seq)
    .fetch_one(&mut **tx)
    .await?;
    if earlier.0 != 0 {
        anyhow::bail!("REJECTED_CHAIN_NOT_HEAD");
    }

    let cross_entity_dependents: (i64,) = sqlx::query_as(
        "SELECT COUNT(*) FROM sync_outbox dependent
         WHERE dependent.depends_on_mutation_id IN (
             SELECT mutation_id FROM sync_outbox
             WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
               AND entity_type = ? AND entity_id = ? AND local_seq >= ?
         )
           AND (dependent.entity_type <> ? OR dependent.entity_id <> ?)",
    )
    .bind(&binding.server_instance_id)
    .bind(&binding.account_id)
    .bind(&binding.session_id)
    .bind(entity_type)
    .bind(entity_id)
    .bind(rejected_seq)
    .bind(entity_type)
    .bind(entity_id)
    .fetch_one(&mut **tx)
    .await?;
    if cross_entity_dependents.0 != 0 {
        anyhow::bail!("REJECTED_CHAIN_CROSS_ENTITY_DEPENDENCY");
    }

    sqlx::query(
        "DELETE FROM sync_outbox
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
           AND entity_type = ? AND entity_id = ? AND local_seq >= ?",
    )
    .bind(&binding.server_instance_id)
    .bind(&binding.account_id)
    .bind(&binding.session_id)
    .bind(entity_type)
    .bind(entity_id)
    .bind(rejected_seq)
    .execute(&mut **tx)
    .await?;
    Ok(Some((rejected_base_version, rejected_base_json)))
}

fn log_patch_from_canonical(
    canonical: &Value,
    desired: &Value,
) -> anyhow::Result<Map<String, Value>> {
    let canonical = canonical
        .as_object()
        .ok_or_else(|| anyhow::anyhow!("COLLABORATION_SHADOW_INVALID"))?;
    let desired = desired
        .as_object()
        .ok_or_else(|| anyhow::anyhow!("OUTBOX_LOG_VALUE_INVALID"))?;
    Ok(desired
        .iter()
        .filter_map(|(key, value)| {
            if key == "syncId" || key == "sessionId" || canonical.get(key) == Some(value) {
                None
            } else {
                Some((key.clone(), value.clone()))
            }
        })
        .collect())
}

/// Rebuilds one corrected logical mutation from the canonical shadow and the
/// current materialized value after a permanent rejection. The old mutation
/// IDs and every dependent row in that rejected chain have already been
/// removed by `discard_rejected_entity_chain`.
async fn queue_log_from_canonical(
    tx: &mut Transaction<'_, Sqlite>,
    binding: &BindingRow,
    entry: &LogEntry,
    desired_deleted: bool,
    rejected_base: Option<(i64, Option<String>)>,
) -> anyhow::Result<bool> {
    let shadow: Option<(i64, String)> = sqlx::query_as(
        "SELECT server_version, server_json FROM entity_shadows
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
           AND entity_type = 'log' AND entity_id = ?",
    )
    .bind(&binding.server_instance_id)
    .bind(&binding.account_id)
    .bind(&binding.session_id)
    .bind(&entry.sync_id)
    .fetch_optional(&mut **tx)
    .await?
    .or_else(|| rejected_base.and_then(|(version, json)| json.map(|json| (version, json))));

    let Some((base_version, base_json)) = shadow else {
        if desired_deleted {
            return Ok(true);
        }
        insert_outbox(
            tx,
            binding,
            "log",
            &entry.sync_id,
            "create",
            0,
            None,
            &json!({"value": log_mutation_value(entry)?}),
            None,
        )
        .await?;
        return Ok(false);
    };

    let canonical: Value = serde_json::from_str(&base_json)
        .map_err(|error| anyhow::anyhow!("COLLABORATION_SHADOW_INVALID: {error}"))?;
    let canonical_deleted = canonical
        .get("deletedAt")
        .is_some_and(|value| !value.is_null());
    if desired_deleted {
        if canonical_deleted {
            return Ok(false);
        }
        insert_outbox(
            tx,
            binding,
            "log",
            &entry.sync_id,
            "delete",
            base_version,
            Some(&base_json),
            &json!({}),
            None,
        )
        .await?;
        return Ok(false);
    }

    let desired = log_mutation_value(entry)?;
    if canonical_deleted {
        insert_outbox(
            tx,
            binding,
            "log",
            &entry.sync_id,
            "restore",
            base_version,
            Some(&base_json),
            &json!({"value": desired}),
            None,
        )
        .await?;
        return Ok(false);
    }

    let patch = log_patch_from_canonical(&canonical, &desired)?;
    if !patch.is_empty() {
        insert_outbox(
            tx,
            binding,
            "log",
            &entry.sync_id,
            "update",
            base_version,
            Some(&base_json),
            &json!({"patch": patch}),
            None,
        )
        .await?;
    }
    Ok(false)
}

async fn queue_session_from_canonical(
    tx: &mut Transaction<'_, Sqlite>,
    binding: &BindingRow,
    session_id: &str,
) -> anyhow::Result<()> {
    let (base_version, base_json): (i64, String) =
        shadow_base(tx, binding, "session", session_id).await?;
    let canonical: CanonicalSessionEntity = serde_json::from_str(&base_json)
        .map_err(|error| anyhow::anyhow!("COLLABORATION_SHADOW_INVALID: {error}"))?;
    if canonical.deleted_at.is_some() {
        anyhow::bail!("SESSION_DELETED");
    }
    let desired: (String, String) =
        sqlx::query_as("SELECT title, status FROM sessions WHERE session_id = ?")
            .bind(session_id)
            .fetch_one(&mut **tx)
            .await?;
    // A status-changing re-edit represents the user's newest action. It does
    // not silently resend a title payload from the rejected chain: close or
    // reopen is queued alone, and its canonical echo restores the canonical
    // title. A title is resent only when the current action leaves both sides
    // active and the materialized title still differs.
    let (operation, payload) = match (canonical.status.as_str(), desired.1.as_str()) {
        ("active", "closed") => (Some("close"), json!({})),
        ("closed", "active") => (Some("reopen"), json!({})),
        ("active", "active") if canonical.title != desired.0 => {
            (Some("update"), json!({"patch": {"title": desired.0}}))
        }
        ("active", "active") | ("closed", "closed") => (None, json!({})),
        _ => anyhow::bail!("INVALID_SESSION_STATE"),
    };
    if let Some(operation) = operation {
        insert_outbox(
            tx,
            binding,
            "session",
            session_id,
            operation,
            base_version,
            Some(&base_json),
            &payload,
            None,
        )
        .await?;
    }
    Ok(())
}

async fn ensure_entity_not_conflicted(
    tx: &mut Transaction<'_, Sqlite>,
    binding: &BindingRow,
    entity_type: &str,
    entity_id: &str,
) -> anyhow::Result<()> {
    let conflicted: (i64,) = sqlx::query_as(
        "SELECT COUNT(*) FROM sync_conflicts
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
           AND entity_type = ? AND entity_id = ? AND state = 'open'",
    )
    .bind(&binding.server_instance_id)
    .bind(&binding.account_id)
    .bind(&binding.session_id)
    .bind(entity_type)
    .bind(entity_id)
    .fetch_one(&mut **tx)
    .await?;
    if conflicted.0 != 0 {
        anyhow::bail!("COLLABORATION_ENTITY_CONFLICTED");
    }
    Ok(())
}

pub(crate) async fn queue_log_create(
    tx: &mut Transaction<'_, Sqlite>,
    entry: &LogEntry,
) -> anyhow::Result<()> {
    let Some(binding) = writable_binding(tx, &entry.session_id, false).await? else {
        return Ok(());
    };
    ensure_entity_not_conflicted(tx, &binding, "log", &entry.sync_id).await?;
    if let Some(rejected_base) =
        discard_rejected_entity_chain(tx, &binding, "log", &entry.sync_id).await?
    {
        queue_log_from_canonical(tx, &binding, entry, false, Some(rejected_base)).await?;
        return Ok(());
    }
    let shadow_exists: (i64,) = sqlx::query_as(
        "SELECT COUNT(*) FROM entity_shadows
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
           AND entity_type = 'log' AND entity_id = ?",
    )
    .bind(&binding.server_instance_id)
    .bind(&binding.account_id)
    .bind(&binding.session_id)
    .bind(&entry.sync_id)
    .fetch_one(&mut **tx)
    .await?;
    if shadow_exists.0 != 0 {
        anyhow::bail!("COLLABORATION_LOG_ALREADY_EXISTS");
    }
    insert_outbox(
        tx,
        &binding,
        "log",
        &entry.sync_id,
        "create",
        0,
        None,
        &json!({"value": log_mutation_value(entry)?}),
        None,
    )
    .await?;
    Ok(())
}

pub(crate) async fn queue_log_update(
    tx: &mut Transaction<'_, Sqlite>,
    before: &LogEntry,
    after: &LogEntry,
) -> anyhow::Result<()> {
    let Some(binding) = writable_binding(tx, &after.session_id, false).await? else {
        return Ok(());
    };
    ensure_entity_not_conflicted(tx, &binding, "log", &after.sync_id).await?;
    if let Some(rejected_base) =
        discard_rejected_entity_chain(tx, &binding, "log", &after.sync_id).await?
    {
        queue_log_from_canonical(tx, &binding, after, false, Some(rejected_base)).await?;
        return Ok(());
    }
    let patch = log_patch(before, after)?;
    if patch.is_empty() {
        return Ok(());
    }
    if let Some(latest) = latest_entity_outbox(tx, &binding, "log", &after.sync_id).await? {
        if latest.state == "pending" && latest.attempts == 0 {
            if latest.operation == "create" {
                sqlx::query(
                    "UPDATE sync_outbox SET payload_json = ?, updated_at = ?
                     WHERE mutation_id = ?",
                )
                .bind(serde_json::to_string(
                    &json!({"value": log_mutation_value(after)?}),
                )?)
                .bind(chrono::Utc::now().to_rfc3339())
                .bind(&latest.mutation_id)
                .execute(&mut **tx)
                .await?;
                return Ok(());
            }
            if latest.operation == "update" {
                let mut payload: Value = serde_json::from_str(&latest.payload_json)?;
                let target = payload
                    .get_mut("patch")
                    .and_then(Value::as_object_mut)
                    .ok_or_else(|| anyhow::anyhow!("OUTBOX_PAYLOAD_INVALID"))?;
                target.extend(patch);
                sqlx::query(
                    "UPDATE sync_outbox SET payload_json = ?, updated_at = ?
                     WHERE mutation_id = ?",
                )
                .bind(serde_json::to_string(&payload)?)
                .bind(chrono::Utc::now().to_rfc3339())
                .bind(&latest.mutation_id)
                .execute(&mut **tx)
                .await?;
                return Ok(());
            }
        }
    }

    let latest = latest_entity_outbox(tx, &binding, "log", &after.sync_id).await?;
    let dependency = latest.as_ref().map(|row| row.mutation_id.clone());
    let (base_version, base_json) = if latest.as_ref().is_some_and(|row| row.operation == "create")
    {
        (0, None)
    } else {
        let (version, value) = shadow_base(tx, &binding, "log", &after.sync_id).await?;
        (version, Some(value))
    };
    insert_outbox(
        tx,
        &binding,
        "log",
        &after.sync_id,
        "update",
        base_version,
        base_json.as_deref(),
        &json!({"patch": patch}),
        dependency.as_deref(),
    )
    .await?;
    Ok(())
}

/// Returns true when an unsent local create was cancelled and the caller must
/// physically remove the materialized row instead of leaving a tombstone.
pub(crate) async fn queue_log_delete(
    tx: &mut Transaction<'_, Sqlite>,
    entry: &LogEntry,
) -> anyhow::Result<bool> {
    let Some(binding) = writable_binding(tx, &entry.session_id, false).await? else {
        return Ok(false);
    };
    ensure_entity_not_conflicted(tx, &binding, "log", &entry.sync_id).await?;
    if let Some(rejected_base) =
        discard_rejected_entity_chain(tx, &binding, "log", &entry.sync_id).await?
    {
        return queue_log_from_canonical(tx, &binding, entry, true, Some(rejected_base)).await;
    }
    if let Some(latest) = latest_entity_outbox(tx, &binding, "log", &entry.sync_id).await? {
        if latest.state == "pending" && latest.attempts == 0 {
            if latest.operation == "create" {
                sqlx::query("DELETE FROM sync_outbox WHERE mutation_id = ?")
                    .bind(&latest.mutation_id)
                    .execute(&mut **tx)
                    .await?;
                return Ok(true);
            }
            if latest.operation == "update" {
                sqlx::query(
                    "UPDATE sync_outbox
                     SET operation = 'delete', payload_json = '{}', updated_at = ?
                     WHERE mutation_id = ?",
                )
                .bind(chrono::Utc::now().to_rfc3339())
                .bind(&latest.mutation_id)
                .execute(&mut **tx)
                .await?;
                return Ok(false);
            }
        }
    }
    let latest = latest_entity_outbox(tx, &binding, "log", &entry.sync_id).await?;
    let dependency = latest.as_ref().map(|row| row.mutation_id.clone());
    let (base_version, base_json) = if latest.as_ref().is_some_and(|row| row.operation == "create")
    {
        (0, None)
    } else {
        let (version, value) = shadow_base(tx, &binding, "log", &entry.sync_id).await?;
        (version, Some(value))
    };
    insert_outbox(
        tx,
        &binding,
        "log",
        &entry.sync_id,
        "delete",
        base_version,
        base_json.as_deref(),
        &json!({}),
        dependency.as_deref(),
    )
    .await?;
    Ok(false)
}

pub(crate) async fn queue_log_restore(
    tx: &mut Transaction<'_, Sqlite>,
    entry: &LogEntry,
) -> anyhow::Result<()> {
    let Some(binding) = writable_binding(tx, &entry.session_id, false).await? else {
        return Ok(());
    };
    ensure_entity_not_conflicted(tx, &binding, "log", &entry.sync_id).await?;
    if let Some(rejected_base) =
        discard_rejected_entity_chain(tx, &binding, "log", &entry.sync_id).await?
    {
        queue_log_from_canonical(tx, &binding, entry, false, Some(rejected_base)).await?;
        return Ok(());
    }
    let latest = latest_entity_outbox(tx, &binding, "log", &entry.sync_id).await?;
    if let Some(latest) = &latest {
        if latest.operation == "delete" && latest.state == "pending" && latest.attempts == 0 {
            let base = if let Some(base_json) = &latest.base_json {
                serde_json::from_str::<Value>(base_json)?
            } else if let Some(dependency) = &latest.depends_on_mutation_id {
                let (payload_json,): (String,) =
                    sqlx::query_as("SELECT payload_json FROM sync_outbox WHERE mutation_id = ?")
                        .bind(dependency)
                        .fetch_one(&mut **tx)
                        .await?;
                serde_json::from_str::<Value>(&payload_json)?
                    .get("value")
                    .cloned()
                    .ok_or_else(|| anyhow::anyhow!("OUTBOX_PAYLOAD_INVALID"))?
            } else {
                anyhow::bail!("OUTBOX_BASE_MISSING");
            };
            let local = log_mutation_value(entry)?;
            let base_object = base
                .as_object()
                .ok_or_else(|| anyhow::anyhow!("OUTBOX_BASE_INVALID"))?;
            let patch: Map<String, Value> = local
                .as_object()
                .ok_or_else(|| anyhow::anyhow!("OUTBOX_LOG_VALUE_INVALID"))?
                .iter()
                .filter_map(|(key, value)| {
                    if key == "syncId" || key == "sessionId" || base_object.get(key) == Some(value)
                    {
                        None
                    } else {
                        Some((key.clone(), value.clone()))
                    }
                })
                .collect();
            if patch.is_empty() {
                sqlx::query("DELETE FROM sync_outbox WHERE mutation_id = ?")
                    .bind(&latest.mutation_id)
                    .execute(&mut **tx)
                    .await?;
            } else {
                sqlx::query(
                    "UPDATE sync_outbox
                     SET operation = 'update', payload_json = ?, updated_at = ?
                     WHERE mutation_id = ?",
                )
                .bind(serde_json::to_string(&json!({"patch": patch}))?)
                .bind(chrono::Utc::now().to_rfc3339())
                .bind(&latest.mutation_id)
                .execute(&mut **tx)
                .await?;
            }
            return Ok(());
        }
    }
    let (base_version, base_json) = shadow_base(tx, &binding, "log", &entry.sync_id).await?;
    let shadow: Value = serde_json::from_str(&base_json)?;
    let follows_attempted_delete = latest.as_ref().is_some_and(|row| row.operation == "delete");
    if !follows_attempted_delete && shadow.get("deletedAt").is_none_or(Value::is_null) {
        anyhow::bail!("COLLABORATION_LOG_NOT_DELETED");
    }
    let dependency = latest.map(|row| row.mutation_id);
    insert_outbox(
        tx,
        &binding,
        "log",
        &entry.sync_id,
        "restore",
        base_version,
        Some(&base_json),
        &json!({"value": log_mutation_value(entry)?}),
        dependency.as_deref(),
    )
    .await?;
    Ok(())
}

pub(crate) async fn mutate_session_in_tx(
    tx: &mut Transaction<'_, Sqlite>,
    session_id: &str,
    operation: &str,
    title: Option<&str>,
) -> anyhow::Result<()> {
    let current: (String, String, Option<String>) =
        sqlx::query_as("SELECT title, status, deleted_at FROM sessions WHERE session_id = ?")
            .bind(session_id)
            .fetch_optional(&mut **tx)
            .await?
            .ok_or_else(|| anyhow::anyhow!("LOCAL_SESSION_NOT_FOUND"))?;
    if current.2.is_some() {
        anyhow::bail!("SESSION_DELETED");
    }
    match operation {
        "update" | "close" if current.1 != "active" => anyhow::bail!("SESSION_CLOSED"),
        "reopen" if current.1 != "closed" => anyhow::bail!("SESSION_NOT_CLOSED"),
        "update" | "close" | "reopen" => {}
        _ => anyhow::bail!("INVALID_SESSION_OPERATION"),
    }

    let binding = sqlx::query_as::<_, BindingRow>(
        "SELECT * FROM collaboration_bindings WHERE session_id = ?",
    )
    .bind(session_id)
    .fetch_optional(&mut **tx)
    .await?;
    if let Some(binding) = &binding {
        if binding.replica_state == "revoked" || binding.revoked_at.is_some() {
            anyhow::bail!("COLLABORATION_MEMBERSHIP_REVOKED");
        }
        if binding.replica_state != "ready" {
            anyhow::bail!("COLLABORATION_SESSION_READ_ONLY");
        }
        if binding.role != "owner" {
            anyhow::bail!("COLLABORATION_OWNER_REQUIRED");
        }
        ensure_entity_not_conflicted(tx, binding, "session", session_id).await?;
        let canonical_status = canonical_session_status_in_tx(
            tx,
            &binding.server_instance_id,
            &binding.account_id,
            session_id,
        )
        .await?;
        let rejected_chain: (i64,) = sqlx::query_as(
            "SELECT COUNT(*) FROM sync_outbox
             WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
               AND entity_type = 'session' AND entity_id = ? AND state = 'rejected'",
        )
        .bind(&binding.server_instance_id)
        .bind(&binding.account_id)
        .bind(session_id)
        .bind(session_id)
        .fetch_one(&mut **tx)
        .await?;
        match operation {
            "update" if canonical_status == "closed" => {
                anyhow::bail!("SESSION_CLOSED")
            }
            "close" if canonical_status == "closed" && rejected_chain.0 == 0 => {
                anyhow::bail!("SESSION_CLOSED")
            }
            "update" | "close" if canonical_status == "deleted" => {
                anyhow::bail!("SESSION_DELETED")
            }
            "reopen" if canonical_status == "deleted" => anyhow::bail!("SESSION_DELETED"),
            "reopen" if canonical_status == "active" => {
                let pending_close: (i64,) = sqlx::query_as(
                    "SELECT COUNT(*) FROM sync_outbox
                     WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
                       AND entity_type = 'session' AND entity_id = ? AND operation = 'close'",
                )
                .bind(&binding.server_instance_id)
                .bind(&binding.account_id)
                .bind(session_id)
                .bind(session_id)
                .fetch_one(&mut **tx)
                .await?;
                if pending_close.0 == 0 {
                    anyhow::bail!("SESSION_NOT_CLOSED");
                }
            }
            _ => {}
        }
    }

    let now = chrono::Utc::now().to_rfc3339();
    match operation {
        "update" => {
            let title = title.ok_or_else(|| anyhow::anyhow!("SESSION_TITLE_REQUIRED"))?;
            if title.trim().is_empty() {
                anyhow::bail!("SESSION_TITLE_REQUIRED");
            }
            sqlx::query("UPDATE sessions SET title = ?, updated_at = ? WHERE session_id = ?")
                .bind(title)
                .bind(&now)
                .bind(session_id)
                .execute(&mut **tx)
                .await?;
        }
        "close" => {
            sqlx::query(
                "UPDATE sessions
                 SET status = 'closed', closed_at = ?, updated_at = ?
                 WHERE session_id = ?",
            )
            .bind(&now)
            .bind(&now)
            .bind(session_id)
            .execute(&mut **tx)
            .await?;
        }
        "reopen" => {
            sqlx::query(
                "UPDATE sessions
                 SET status = 'active', closed_at = NULL, updated_at = ?
                 WHERE session_id = ?",
            )
            .bind(&now)
            .bind(session_id)
            .execute(&mut **tx)
            .await?;
        }
        _ => unreachable!(),
    }

    let Some(binding) = binding else {
        return Ok(());
    };
    if discard_rejected_entity_chain(tx, &binding, "session", session_id)
        .await?
        .is_some()
    {
        queue_session_from_canonical(tx, &binding, session_id).await?;
        return Ok(());
    }
    let payload = if operation == "update" {
        let title = title.ok_or_else(|| anyhow::anyhow!("SESSION_TITLE_REQUIRED"))?;
        json!({"patch": {"title": title}})
    } else {
        json!({})
    };
    if operation == "update" {
        if let Some(latest) = latest_entity_outbox(tx, &binding, "session", session_id).await? {
            if latest.state == "pending" && latest.attempts == 0 && latest.operation == "update" {
                let mut existing: Value = serde_json::from_str(&latest.payload_json)?;
                let title = title.ok_or_else(|| anyhow::anyhow!("SESSION_TITLE_REQUIRED"))?;
                existing["patch"]["title"] = Value::String(title.to_string());
                sqlx::query(
                    "UPDATE sync_outbox SET payload_json = ?, updated_at = ?
                     WHERE mutation_id = ?",
                )
                .bind(serde_json::to_string(&existing)?)
                .bind(&now)
                .bind(&latest.mutation_id)
                .execute(&mut **tx)
                .await?;
                return Ok(());
            }
        }
    }
    let (base_version, base_json) = shadow_base(tx, &binding, "session", session_id).await?;
    let dependency = latest_entity_outbox(tx, &binding, "session", session_id)
        .await?
        .map(|row| row.mutation_id);
    insert_outbox(
        tx,
        &binding,
        "session",
        session_id,
        operation,
        base_version,
        Some(&base_json),
        &payload,
        dependency.as_deref(),
    )
    .await?;
    Ok(())
}

pub async fn update_session_title(
    pool: &SqlitePool,
    session_id: &str,
    title: &str,
) -> anyhow::Result<()> {
    let mut tx = pool.begin().await?;
    mutate_session_in_tx(&mut tx, session_id, "update", Some(title)).await?;
    tx.commit().await?;
    Ok(())
}

pub async fn reopen_session(pool: &SqlitePool, session_id: &str) -> anyhow::Result<()> {
    let mut tx = pool.begin().await?;
    mutate_session_in_tx(&mut tx, session_id, "reopen", None).await?;
    tx.commit().await?;
    Ok(())
}

async fn require_partition_binding(
    tx: &mut Transaction<'_, Sqlite>,
    server_instance_id: &str,
    account_id: &str,
    session_id: &str,
) -> anyhow::Result<BindingRow> {
    let binding = sqlx::query_as::<_, BindingRow>(
        "SELECT * FROM collaboration_bindings
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?",
    )
    .bind(server_instance_id)
    .bind(account_id)
    .bind(session_id)
    .fetch_optional(&mut **tx)
    .await?
    .ok_or_else(|| anyhow::anyhow!("BINDING_NOT_FOUND"))?;
    if binding.replica_state == "revoked" || binding.revoked_at.is_some() {
        anyhow::bail!("COLLABORATION_MEMBERSHIP_REVOKED");
    }
    Ok(binding)
}

fn parse_canonical_session_status(server_json: &str) -> anyhow::Result<String> {
    let session_shadow: Value = serde_json::from_str(server_json)
        .map_err(|error| anyhow::anyhow!("COLLABORATION_SESSION_SHADOW_INVALID: {error}"))?;
    if session_shadow
        .get("deletedAt")
        .is_some_and(|value| !value.is_null())
    {
        return Ok("deleted".to_string());
    }
    match session_shadow.get("status").and_then(Value::as_str) {
        Some("active") => Ok("active".to_string()),
        Some("closed") => Ok("closed".to_string()),
        _ => anyhow::bail!("COLLABORATION_SESSION_SHADOW_INVALID"),
    }
}

async fn canonical_session_status_in_tx(
    tx: &mut Transaction<'_, Sqlite>,
    server_instance_id: &str,
    account_id: &str,
    session_id: &str,
) -> anyhow::Result<String> {
    let (server_json,): (String,) = sqlx::query_as(
        "SELECT server_json FROM entity_shadows
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
           AND entity_type = 'session' AND entity_id = ?",
    )
    .bind(server_instance_id)
    .bind(account_id)
    .bind(session_id)
    .bind(session_id)
    .fetch_optional(&mut **tx)
    .await?
    .ok_or_else(|| anyhow::anyhow!("COLLABORATION_SESSION_SHADOW_MISSING"))?;
    parse_canonical_session_status(&server_json)
}

pub async fn list_pending_mutations(
    pool: &SqlitePool,
    server_instance_id: &str,
    account_id: &str,
    session_id: &str,
    limit: i64,
) -> anyhow::Result<Value> {
    let limit = limit.clamp(1, 100) as usize;
    let mut tx = pool.begin().await?;
    let binding =
        require_partition_binding(&mut tx, server_instance_id, account_id, session_id).await?;
    if binding.replica_state != "ready" {
        anyhow::bail!("COLLABORATION_NOT_READY");
    }
    if binding.role == "viewer" {
        anyhow::bail!("COLLABORATION_ROLE_READ_ONLY");
    }
    let canonical_session_status =
        canonical_session_status_in_tx(&mut tx, server_instance_id, account_id, session_id).await?;

    // A process can die after persisting `sending` and before recording the
    // HTTP result. Recover those rows before listing; mutation_id is retained,
    // so retrying is safe against the server's durable idempotency table.
    let now = chrono::Utc::now().to_rfc3339();
    sqlx::query(
        "UPDATE sync_outbox
         SET state = 'retrying', next_attempt_at = NULL,
             last_error_code = COALESCE(last_error_code, 'SEND_INTERRUPTED'),
             updated_at = ?
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
           AND state = 'sending'",
    )
    .bind(&now)
    .bind(server_instance_id)
    .bind(account_id)
    .bind(session_id)
    .execute(&mut *tx)
    .await?;

    let rows = sqlx::query_as::<_, OutboxRow>(
        "SELECT local_seq, mutation_id, entity_type, entity_id, operation,
                base_version, observed_seq, base_json, payload_json, state,
                attempts, next_attempt_at, depends_on_mutation_id, created_at
         FROM sync_outbox
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
         ORDER BY local_seq",
    )
    .bind(server_instance_id)
    .bind(account_id)
    .bind(session_id)
    .fetch_all(&mut *tx)
    .await?;

    let mut seen_entities = HashSet::new();
    let mut candidates = Vec::new();
    for row in rows {
        let entity_key = format!("{}\0{}", row.entity_type, row.entity_id);
        if !seen_entities.insert(entity_key) {
            continue;
        }
        if row.depends_on_mutation_id.is_some()
            || (row.state != "pending" && row.state != "retrying")
        {
            continue;
        }
        if canonical_session_status != "active"
            && !(row.entity_type == "session" && row.operation == "reopen")
        {
            continue;
        }
        candidates.push(row);
    }
    candidates.sort_by_key(|row| {
        (
            i32::from(!(row.entity_type == "session" && row.operation == "reopen")),
            row._local_seq,
        )
    });

    let mut operations = Vec::new();
    let mut selected_mutation_ids = Vec::new();
    for row in candidates.into_iter().take(limit) {
        let payload: Value = serde_json::from_str(&row.payload_json)
            .map_err(|error| anyhow::anyhow!("OUTBOX_PAYLOAD_INVALID: {error}"))?;
        let mut operation = Map::new();
        selected_mutation_ids.push(row.mutation_id.clone());
        operation.insert("mutationId".into(), Value::String(row.mutation_id));
        operation.insert("entityType".into(), Value::String(row.entity_type));
        operation.insert("entityId".into(), Value::String(row.entity_id));
        operation.insert("operation".into(), Value::String(row.operation.clone()));
        operation.insert("baseVersion".into(), Value::from(row.base_version));
        operation.insert("observedSeq".into(), Value::from(row.observed_seq));
        operation.insert("queuedAt".into(), Value::String(row.created_at));
        match row.operation.as_str() {
            "create" | "restore" => {
                let value = payload
                    .get("value")
                    .cloned()
                    .ok_or_else(|| anyhow::anyhow!("OUTBOX_PAYLOAD_INVALID"))?;
                operation.insert("value".into(), value);
            }
            "update" => {
                let patch = payload
                    .get("patch")
                    .cloned()
                    .ok_or_else(|| anyhow::anyhow!("OUTBOX_PAYLOAD_INVALID"))?;
                operation.insert("patch".into(), patch);
            }
            "delete" | "close" | "reopen" => {}
            _ => anyhow::bail!("OUTBOX_OPERATION_INVALID"),
        }
        operations.push(Value::Object(operation));
    }

    // Claim exactly the serialized rows before returning them. Without this
    // write in the same transaction, a UI edit could merge into a merely
    // listed pending row while Dart is still holding its older payload. Once a
    // row is sending, later local edits form a dependent mutation instead.
    for mutation_id in &selected_mutation_ids {
        let claimed = sqlx::query(
            "UPDATE sync_outbox
             SET state = 'sending', attempts = attempts + 1,
                 next_attempt_at = NULL, last_error_code = NULL,
                 last_error_message = NULL, last_error_details_json = NULL,
                 updated_at = ?
             WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
               AND mutation_id = ? AND state IN ('pending', 'retrying')",
        )
        .bind(&now)
        .bind(server_instance_id)
        .bind(account_id)
        .bind(session_id)
        .bind(mutation_id)
        .execute(&mut *tx)
        .await?;
        if claimed.rows_affected() != 1 {
            anyhow::bail!("OUTBOX_CLAIM_RACE:{mutation_id}");
        }
    }

    let candidate = uuid::Uuid::new_v4().to_string();
    sqlx::query("INSERT OR IGNORE INTO device_state (id, device_id, created_at) VALUES (1, ?, ?)")
        .bind(candidate)
        .bind(&now)
        .execute(&mut *tx)
        .await?;
    let (device_id,): (String,) = sqlx::query_as("SELECT device_id FROM device_state WHERE id = 1")
        .fetch_one(&mut *tx)
        .await?;
    tx.commit().await?;
    Ok(json!({
        "protocolVersion": 1,
        "deviceId": device_id,
        "operations": operations,
    }))
}

pub async fn mark_mutations_sending(
    pool: &SqlitePool,
    server_instance_id: &str,
    account_id: &str,
    session_id: &str,
    mutation_ids: &[String],
) -> anyhow::Result<()> {
    if mutation_ids.is_empty() || mutation_ids.len() > 100 {
        anyhow::bail!("MUTATION_BATCH_INVALID");
    }
    let mut unique = HashSet::new();
    if mutation_ids.iter().any(|id| !unique.insert(id)) {
        anyhow::bail!("MUTATION_BATCH_DUPLICATE_ID");
    }
    let mut tx = pool.begin().await?;
    require_partition_binding(&mut tx, server_instance_id, account_id, session_id).await?;
    let now = chrono::Utc::now().to_rfc3339();
    for mutation_id in mutation_ids {
        let result = sqlx::query(
            "UPDATE sync_outbox
             SET state = 'sending', attempts = attempts + 1,
                 next_attempt_at = NULL, last_error_code = NULL,
                 last_error_message = NULL, last_error_details_json = NULL,
                 updated_at = ?
             WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
               AND mutation_id = ? AND state IN ('pending', 'retrying')",
        )
        .bind(&now)
        .bind(server_instance_id)
        .bind(account_id)
        .bind(session_id)
        .bind(mutation_id)
        .execute(&mut *tx)
        .await?;
        if result.rows_affected() == 0 {
            let already_claimed: (i64,) = sqlx::query_as(
                "SELECT COUNT(*) FROM sync_outbox
                 WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
                   AND mutation_id = ? AND state = 'sending'",
            )
            .bind(server_instance_id)
            .bind(account_id)
            .bind(session_id)
            .bind(mutation_id)
            .fetch_one(&mut *tx)
            .await?;
            if already_claimed.0 != 1 {
                anyhow::bail!("OUTBOX_MUTATION_NOT_SENDABLE:{mutation_id}");
            }
        }
    }
    tx.commit().await?;
    Ok(())
}

pub async fn mark_mutation_accepted(
    pool: &SqlitePool,
    server_instance_id: &str,
    account_id: &str,
    session_id: &str,
    mutation_id: &str,
    accepted_event_seq: i64,
) -> anyhow::Result<()> {
    if accepted_event_seq < 1 {
        anyhow::bail!("EVENT_SEQUENCE_INVALID");
    }
    let mut tx = pool.begin().await?;
    require_partition_binding(&mut tx, server_instance_id, account_id, session_id).await?;
    let current: Option<(String, Option<i64>)> = sqlx::query_as(
        "SELECT state, accepted_event_seq FROM sync_outbox
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
           AND mutation_id = ?",
    )
    .bind(server_instance_id)
    .bind(account_id)
    .bind(session_id)
    .bind(mutation_id)
    .fetch_optional(&mut *tx)
    .await?;
    if current
        .as_ref()
        .and_then(|(state, seq)| (state == "accepted").then_some(*seq).flatten())
        .is_some_and(|seq| seq != accepted_event_seq)
    {
        anyhow::bail!("ACCEPTED_EVENT_SEQUENCE_MISMATCH");
    }
    let result = sqlx::query(
        "UPDATE sync_outbox
         SET state = 'accepted', accepted_event_seq = ?, next_attempt_at = NULL,
             last_error_code = NULL, last_error_message = NULL,
             last_error_details_json = NULL, updated_at = ?
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
           AND mutation_id = ? AND state IN ('pending', 'sending', 'retrying', 'accepted')",
    )
    .bind(accepted_event_seq)
    .bind(chrono::Utc::now().to_rfc3339())
    .bind(server_instance_id)
    .bind(account_id)
    .bind(session_id)
    .bind(mutation_id)
    .execute(&mut *tx)
    .await?;
    if result.rows_affected() == 0 {
        let echoed: (i64,) = sqlx::query_as(
            "SELECT COUNT(*) FROM applied_events
             WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
               AND mutation_id = ?",
        )
        .bind(server_instance_id)
        .bind(account_id)
        .bind(session_id)
        .bind(mutation_id)
        .fetch_one(&mut *tx)
        .await?;
        if echoed.0 == 0 {
            anyhow::bail!("OUTBOX_MUTATION_NOT_FOUND");
        }
    }
    tx.commit().await?;
    Ok(())
}

pub async fn mark_mutation_retry(
    pool: &SqlitePool,
    request: MutationFailureRequest,
) -> anyhow::Result<()> {
    let mut tx = pool.begin().await?;
    require_partition_binding(
        &mut tx,
        &request.server_instance_id,
        &request.account_id,
        &request.session_id,
    )
    .await?;
    if let Some(value) = &request.next_attempt_at {
        DateTime::parse_from_rfc3339(value)
            .map_err(|_| anyhow::anyhow!("NEXT_ATTEMPT_AT_INVALID"))?;
    }
    let result = sqlx::query(
        "UPDATE sync_outbox
         SET state = 'retrying', next_attempt_at = ?, last_error_code = ?,
             last_error_message = ?, last_error_details_json = NULL, updated_at = ?
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
           AND mutation_id = ? AND state IN ('pending', 'sending', 'retrying')",
    )
    .bind(&request.next_attempt_at)
    .bind(&request.error_code)
    .bind(&request.error_message)
    .bind(chrono::Utc::now().to_rfc3339())
    .bind(&request.server_instance_id)
    .bind(&request.account_id)
    .bind(&request.session_id)
    .bind(&request.mutation_id)
    .execute(&mut *tx)
    .await?;
    if result.rows_affected() != 1 {
        anyhow::bail!("OUTBOX_MUTATION_NOT_RETRYABLE");
    }
    tx.commit().await?;
    Ok(())
}

pub async fn mark_mutation_rejected(
    pool: &SqlitePool,
    server_instance_id: &str,
    account_id: &str,
    session_id: &str,
    mutation_id: &str,
    error_code: &str,
    error_message: &str,
    details_json: Option<&str>,
) -> anyhow::Result<()> {
    if let Some(details) = details_json {
        serde_json::from_str::<Value>(details)
            .map_err(|error| anyhow::anyhow!("ERROR_DETAILS_JSON_INVALID: {error}"))?;
    }
    let mut tx = pool.begin().await?;
    require_partition_binding(&mut tx, server_instance_id, account_id, session_id).await?;
    let result = sqlx::query(
        "UPDATE sync_outbox
         SET state = 'rejected', next_attempt_at = NULL,
             last_error_code = ?, last_error_message = ?,
             last_error_details_json = ?, updated_at = ?
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
           AND mutation_id = ? AND state IN ('pending', 'sending', 'retrying', 'rejected')",
    )
    .bind(error_code)
    .bind(error_message)
    .bind(details_json)
    .bind(chrono::Utc::now().to_rfc3339())
    .bind(server_instance_id)
    .bind(account_id)
    .bind(session_id)
    .bind(mutation_id)
    .execute(&mut *tx)
    .await?;
    if result.rows_affected() != 1 {
        anyhow::bail!("OUTBOX_MUTATION_NOT_REJECTABLE");
    }
    tx.commit().await?;
    Ok(())
}

async fn materialized_entity_json(
    tx: &mut Transaction<'_, Sqlite>,
    entity_type: &str,
    entity_id: &str,
    version: i64,
) -> anyhow::Result<Value> {
    match entity_type {
        "log" => {
            let row = sqlx::query_as::<_, MaterializedLogRow>(
                "SELECT sync_id, session_id, time, controller, callsign,
                        rst_sent, rst_rcvd, qth, device, power, antenna, height,
                        remarks, created_at, updated_at, deleted_at
                 FROM logs WHERE sync_id = ?",
            )
            .bind(entity_id)
            .fetch_optional(&mut **tx)
            .await?
            .ok_or_else(|| anyhow::anyhow!("LOCAL_LOG_NOT_FOUND"))?;
            Ok(row.into_json(version))
        }
        "session" => {
            let row: (
                String,
                String,
                String,
                String,
                String,
                Option<String>,
                Option<String>,
            ) = sqlx::query_as(
                "SELECT session_id, title, status, created_at, updated_at, closed_at, deleted_at
                     FROM sessions WHERE session_id = ?",
            )
            .bind(entity_id)
            .fetch_optional(&mut **tx)
            .await?
            .ok_or_else(|| anyhow::anyhow!("LOCAL_SESSION_NOT_FOUND"))?;
            Ok(json!({
                "sessionId": row.0,
                "title": row.1,
                "status": row.2,
                "version": version,
                "createdAt": row.3,
                "updatedAt": row.4,
                "closedAt": row.5,
                "deletedAt": row.6,
            }))
        }
        _ => anyhow::bail!("ENTITY_TYPE_INVALID"),
    }
}

const LOG_EDITABLE_FIELDS: &[&str] = &[
    "time",
    "controller",
    "callsign",
    "rstSent",
    "rstRcvd",
    "qth",
    "device",
    "power",
    "antenna",
    "height",
    "remarks",
];
const SESSION_EDITABLE_FIELDS: &[&str] = &["title"];

fn editable_fields(entity_type: &str) -> anyhow::Result<&'static [&'static str]> {
    match entity_type {
        "log" => Ok(LOG_EDITABLE_FIELDS),
        "session" => Ok(SESSION_EDITABLE_FIELDS),
        _ => anyhow::bail!("ENTITY_TYPE_INVALID"),
    }
}

fn object_field<'a>(value: &'a Value, field: &str) -> anyhow::Result<Option<&'a Value>> {
    value
        .as_object()
        .map(|object| object.get(field))
        .ok_or_else(|| anyhow::anyhow!("CONFLICT_ENTITY_INVALID"))
}

fn changed_fields(base: &Value, desired: &Value, fields: &[&str]) -> anyhow::Result<Vec<String>> {
    let mut changed = Vec::new();
    for field in fields {
        if object_field(base, field)? != object_field(desired, field)? {
            changed.push((*field).to_string());
        }
    }
    Ok(changed)
}

fn three_way_conflicting_fields(
    base: &Value,
    desired: &Value,
    remote: &Value,
    fields: &[String],
) -> anyhow::Result<Vec<String>> {
    let mut conflicting = Vec::new();
    for field in fields {
        let base_value = object_field(base, field)?;
        let desired_value = object_field(desired, field)?;
        let remote_value = object_field(remote, field)?;
        if remote_value != base_value && remote_value != desired_value {
            conflicting.push(field.clone());
        }
    }
    Ok(conflicting)
}

fn patch_for_fields(desired: &Value, fields: &[String]) -> anyhow::Result<Map<String, Value>> {
    let desired = desired
        .as_object()
        .ok_or_else(|| anyhow::anyhow!("CONFLICT_LOCAL_ENTITY_INVALID"))?;
    fields
        .iter()
        .map(|field| {
            desired
                .get(field)
                .cloned()
                .map(|value| (field.clone(), value))
                .ok_or_else(|| anyhow::anyhow!("CONFLICT_LOCAL_FIELD_MISSING:{field}"))
        })
        .collect()
}

fn validate_conflict_entity(
    entity_type: &str,
    entity_id: &str,
    session_id: &str,
    version: i64,
    value: &Value,
) -> anyhow::Result<()> {
    if version < 1 || !value.is_object() {
        anyhow::bail!("CONFLICT_ENTITY_INVALID");
    }
    match entity_type {
        "log" => {
            let log: RemoteLog = serde_json::from_value(value.clone())
                .map_err(|error| anyhow::anyhow!("CONFLICT_LOG_INVALID: {error}"))?;
            if log.sync_id != entity_id || log.session_id != session_id || log.version != version {
                anyhow::bail!("CONFLICT_ENTITY_MISMATCH");
            }
            for timestamp in [&log.time, &log.created_at, &log.updated_at] {
                DateTime::parse_from_rfc3339(timestamp)
                    .map_err(|_| anyhow::anyhow!("CONFLICT_LOG_TIME_INVALID"))?;
            }
            if let Some(timestamp) = &log.deleted_at {
                DateTime::parse_from_rfc3339(timestamp)
                    .map_err(|_| anyhow::anyhow!("CONFLICT_LOG_TIME_INVALID"))?;
            }
        }
        "session" => {
            let session: CanonicalSessionEntity = serde_json::from_value(value.clone())
                .map_err(|error| anyhow::anyhow!("CONFLICT_SESSION_INVALID: {error}"))?;
            if session.session_id != entity_id
                || session.session_id != session_id
                || session.version != version
            {
                anyhow::bail!("CONFLICT_ENTITY_MISMATCH");
            }
            if !matches!(session.status.as_str(), "active" | "closed") {
                anyhow::bail!("CONFLICT_SESSION_STATUS_INVALID");
            }
            for timestamp in [&session.created_at, &session.updated_at] {
                DateTime::parse_from_rfc3339(timestamp)
                    .map_err(|_| anyhow::anyhow!("CONFLICT_SESSION_TIME_INVALID"))?;
            }
            for timestamp in [session.closed_at.as_deref(), session.deleted_at.as_deref()]
                .into_iter()
                .flatten()
            {
                DateTime::parse_from_rfc3339(timestamp)
                    .map_err(|_| anyhow::anyhow!("CONFLICT_SESSION_TIME_INVALID"))?;
            }
        }
        _ => anyhow::bail!("ENTITY_TYPE_INVALID"),
    }
    Ok(())
}

async fn load_entity_chain_from_root(
    tx: &mut Transaction<'_, Sqlite>,
    binding: &BindingRow,
    root: &OutboxRow,
) -> anyhow::Result<Vec<OutboxRow>> {
    if root.depends_on_mutation_id.is_some() {
        anyhow::bail!("CONFLICT_MUTATION_NOT_CHAIN_ROOT");
    }
    let earlier: (i64,) = sqlx::query_as(
        "SELECT COUNT(*) FROM sync_outbox
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
           AND entity_type = ? AND entity_id = ? AND local_seq < ?",
    )
    .bind(&binding.server_instance_id)
    .bind(&binding.account_id)
    .bind(&binding.session_id)
    .bind(&root.entity_type)
    .bind(&root.entity_id)
    .bind(root._local_seq)
    .fetch_one(&mut **tx)
    .await?;
    if earlier.0 != 0 {
        anyhow::bail!("CONFLICT_MUTATION_NOT_CHAIN_ROOT");
    }

    let chain = sqlx::query_as::<_, OutboxRow>(
        "SELECT local_seq, mutation_id, entity_type, entity_id, operation,
                base_version, observed_seq, base_json, payload_json, state,
                attempts, next_attempt_at, depends_on_mutation_id, created_at
         FROM sync_outbox
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
           AND entity_type = ? AND entity_id = ? AND local_seq >= ?
         ORDER BY local_seq",
    )
    .bind(&binding.server_instance_id)
    .bind(&binding.account_id)
    .bind(&binding.session_id)
    .bind(&root.entity_type)
    .bind(&root.entity_id)
    .bind(root._local_seq)
    .fetch_all(&mut **tx)
    .await?;
    if chain.first().map(|row| row.mutation_id.as_str()) != Some(root.mutation_id.as_str()) {
        anyhow::bail!("CONFLICT_CHAIN_INVALID");
    }
    for pair in chain.windows(2) {
        if pair[1].depends_on_mutation_id.as_deref() != Some(pair[0].mutation_id.as_str()) {
            anyhow::bail!("CONFLICT_CHAIN_NOT_LINEAR");
        }
    }
    for row in &chain {
        let external_dependents: (i64,) = sqlx::query_as(
            "SELECT COUNT(*) FROM sync_outbox
             WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
               AND depends_on_mutation_id = ?
               AND (entity_type <> ? OR entity_id <> ?)",
        )
        .bind(&binding.server_instance_id)
        .bind(&binding.account_id)
        .bind(&binding.session_id)
        .bind(&row.mutation_id)
        .bind(&root.entity_type)
        .bind(&root.entity_id)
        .fetch_one(&mut **tx)
        .await?;
        if external_dependents.0 != 0 {
            anyhow::bail!("CONFLICT_CHAIN_CROSS_ENTITY_DEPENDENCY");
        }
    }
    Ok(chain)
}

fn fold_update_chain(base: &Value, chain: &[OutboxRow]) -> anyhow::Result<Value> {
    let mut desired = base.clone();
    let allowed = editable_fields(&chain[0].entity_type)?;
    for row in chain {
        if row.operation != "update" {
            anyhow::bail!("CONFLICT_CHAIN_LIFECYCLE_OPERATION");
        }
        let payload: Value = serde_json::from_str(&row.payload_json)
            .map_err(|error| anyhow::anyhow!("OUTBOX_PAYLOAD_INVALID: {error}"))?;
        let patch = payload
            .get("patch")
            .and_then(Value::as_object)
            .ok_or_else(|| anyhow::anyhow!("OUTBOX_PAYLOAD_INVALID"))?;
        if patch.is_empty() || patch.keys().any(|field| !allowed.contains(&field.as_str())) {
            anyhow::bail!("OUTBOX_PAYLOAD_INVALID");
        }
        merge_object(&mut desired, &Value::Object(patch.clone()))?;
    }
    Ok(desired)
}

fn lifecycle_conflict_fields(entity_type: &str, chain: &[OutboxRow]) -> Vec<String> {
    let mut fields = Vec::new();
    for row in chain {
        match (entity_type, row.operation.as_str()) {
            ("log", "create") => fields.push("existence".to_string()),
            ("log", "delete" | "restore") => fields.push("deletedAt".to_string()),
            ("session", "close" | "reopen") => fields.push("status".to_string()),
            _ => {}
        }
    }
    fields.sort();
    fields.dedup();
    fields
}

fn remote_blocks_update(entity_type: &str, remote: &Value) -> anyhow::Result<Vec<String>> {
    let mut fields = Vec::new();
    if remote
        .get("deletedAt")
        .is_some_and(|deleted_at| !deleted_at.is_null())
    {
        fields.push("deletedAt".to_string());
    }
    if entity_type == "session" && remote.get("status").and_then(Value::as_str) != Some("active") {
        fields.push("status".to_string());
    }
    Ok(fields)
}

fn same_version_conflict_proven(entity_type: &str, operation: &str, remote: &Value) -> bool {
    let remote_deleted = remote
        .get("deletedAt")
        .is_some_and(|value| !value.is_null());
    matches!(
        (entity_type, operation, remote_deleted),
        ("log", "update" | "delete", true) | ("log", "restore", false)
    )
}

async fn delete_entity_chain(
    tx: &mut Transaction<'_, Sqlite>,
    binding: &BindingRow,
    root: &OutboxRow,
    expected_count: usize,
) -> anyhow::Result<()> {
    let deleted = sqlx::query(
        "DELETE FROM sync_outbox
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
           AND entity_type = ? AND entity_id = ? AND local_seq >= ?",
    )
    .bind(&binding.server_instance_id)
    .bind(&binding.account_id)
    .bind(&binding.session_id)
    .bind(&root.entity_type)
    .bind(&root.entity_id)
    .bind(root._local_seq)
    .execute(&mut **tx)
    .await?;
    if deleted.rows_affected() != expected_count as u64 {
        anyhow::bail!("CONFLICT_CHAIN_DELETE_RACE");
    }
    Ok(())
}

struct ReplacementOutbox<'a> {
    local_seq: i64,
    entity_type: &'a str,
    entity_id: &'a str,
    operation: &'a str,
    base_version: i64,
    base_json: Option<&'a str>,
    payload: &'a Value,
}

async fn insert_replacement_intent(
    tx: &mut Transaction<'_, Sqlite>,
    binding: &BindingRow,
    replacement: ReplacementOutbox<'_>,
) -> anyhow::Result<String> {
    let mutation_id = uuid::Uuid::new_v4().to_string();
    let now = chrono::Utc::now().to_rfc3339();
    sqlx::query(
        "INSERT INTO sync_outbox (
            local_seq, server_instance_id, account_id, session_id, mutation_id,
            entity_type, entity_id, operation, base_version, observed_seq,
            base_json, payload_json, state, attempts, next_attempt_at,
            accepted_event_seq, depends_on_mutation_id,
            last_error_code, last_error_message, last_error_details_json,
            created_at, updated_at
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', 0, NULL,
                   NULL, NULL, NULL, NULL, NULL, ?, ?)",
    )
    .bind(replacement.local_seq)
    .bind(&binding.server_instance_id)
    .bind(&binding.account_id)
    .bind(&binding.session_id)
    .bind(&mutation_id)
    .bind(replacement.entity_type)
    .bind(replacement.entity_id)
    .bind(replacement.operation)
    .bind(replacement.base_version)
    .bind(binding.last_applied_seq)
    .bind(replacement.base_json)
    .bind(serde_json::to_string(replacement.payload)?)
    .bind(&now)
    .bind(&now)
    .execute(&mut **tx)
    .await?;
    Ok(mutation_id)
}

async fn write_materialized_entity(
    tx: &mut Transaction<'_, Sqlite>,
    entity_type: &str,
    value: Value,
) -> anyhow::Result<()> {
    match entity_type {
        "log" => write_materialized_log(tx, value).await,
        "session" => write_materialized_session(tx, value).await,
        _ => anyhow::bail!("ENTITY_TYPE_INVALID"),
    }
}

pub async fn record_mutation_conflict(
    pool: &SqlitePool,
    request: MutationConflictRequest,
) -> anyhow::Result<MutationConflictOutcome> {
    if request.current_version < 1 || !request.current_entity.is_object() {
        anyhow::bail!("CONFLICT_ENTITY_INVALID");
    }
    let mut tx = pool.begin().await?;
    let binding = require_partition_binding(
        &mut tx,
        &request.server_instance_id,
        &request.account_id,
        &request.session_id,
    )
    .await?;
    let existing: Option<(String, String)> = sqlx::query_as(
        "SELECT conflict_id, conflicting_fields_json FROM sync_conflicts
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
           AND mutation_id = ?",
    )
    .bind(&request.server_instance_id)
    .bind(&request.account_id)
    .bind(&request.session_id)
    .bind(&request.mutation_id)
    .fetch_optional(&mut *tx)
    .await?;
    if let Some((conflict_id, fields_json)) = existing {
        let conflicting_fields = serde_json::from_str(&fields_json)
            .map_err(|error| anyhow::anyhow!("CONFLICT_FIELDS_INVALID: {error}"))?;
        tx.commit().await?;
        return Ok(MutationConflictOutcome {
            outcome: "conflict".to_string(),
            conflict_id: Some(conflict_id),
            replacement_mutation_id: None,
            conflicting_fields,
        });
    }

    let outbox = sqlx::query_as::<_, OutboxRow>(
        "SELECT local_seq, mutation_id, entity_type, entity_id, operation,
                base_version, observed_seq, base_json, payload_json, state,
                attempts, next_attempt_at, depends_on_mutation_id, created_at
         FROM sync_outbox
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
           AND mutation_id = ?",
    )
    .bind(&request.server_instance_id)
    .bind(&request.account_id)
    .bind(&request.session_id)
    .bind(&request.mutation_id)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or_else(|| anyhow::anyhow!("OUTBOX_MUTATION_NOT_FOUND"))?;
    if outbox.state == "accepted" {
        anyhow::bail!("OUTBOX_ALREADY_ACCEPTED");
    }
    if !matches!(outbox.state.as_str(), "pending" | "sending" | "retrying") {
        anyhow::bail!("OUTBOX_MUTATION_NOT_CONFLICTABLE");
    }
    validate_conflict_entity(
        &outbox.entity_type,
        &outbox.entity_id,
        &request.session_id,
        request.current_version,
        &request.current_entity,
    )?;
    let chain = load_entity_chain_from_root(&mut tx, &binding, &outbox).await?;
    if request.current_version < outbox.base_version
        || (request.current_version == outbox.base_version
            && !same_version_conflict_proven(
                &outbox.entity_type,
                &outbox.operation,
                &request.current_entity,
            ))
    {
        anyhow::bail!("CONFLICT_VERSION_NOT_ADVANCED");
    }
    let base_value = outbox
        .base_json
        .as_deref()
        .map(serde_json::from_str::<Value>)
        .transpose()?;
    let local_value = materialized_entity_json(
        &mut tx,
        &outbox.entity_type,
        &outbox.entity_id,
        request.current_version,
    )
    .await?;

    let auto_rebase_candidate = base_value.is_some()
        && chain.iter().all(|row| row.operation == "update")
        && chain
            .iter()
            .skip(1)
            .all(|row| row.state == "pending" && row.attempts == 0);
    let mut conflicting_fields = lifecycle_conflict_fields(&outbox.entity_type, &chain);
    let mut auto_desired = None;
    let mut local_changed_fields = Vec::new();
    if auto_rebase_candidate {
        let base = base_value.as_ref().expect("checked above");
        let desired = fold_update_chain(base, &chain)?;
        local_changed_fields =
            changed_fields(base, &desired, editable_fields(&outbox.entity_type)?)?;
        conflicting_fields.extend(three_way_conflicting_fields(
            base,
            &desired,
            &request.current_entity,
            &local_changed_fields,
        )?);
        conflicting_fields.extend(remote_blocks_update(
            &outbox.entity_type,
            &request.current_entity,
        )?);
        auto_desired = Some(desired);
    } else if let Some(base) = base_value.as_ref() {
        let local_fields =
            changed_fields(base, &local_value, editable_fields(&outbox.entity_type)?)?;
        conflicting_fields.extend(three_way_conflicting_fields(
            base,
            &local_value,
            &request.current_entity,
            &local_fields,
        )?);
        if chain.iter().all(|row| row.operation == "update") {
            conflicting_fields.extend(remote_blocks_update(
                &outbox.entity_type,
                &request.current_entity,
            )?);
        }
    }
    if !auto_rebase_candidate && conflicting_fields.is_empty() {
        conflicting_fields.push("chain".to_string());
    }
    conflicting_fields.sort();
    conflicting_fields.dedup();

    if auto_rebase_candidate && conflicting_fields.is_empty() {
        let desired = auto_desired.expect("auto rebase desired exists");
        let patch = patch_for_fields(&desired, &local_changed_fields)?;
        let patch: Map<String, Value> = patch
            .into_iter()
            .filter(|(field, value)| request.current_entity.get(field) != Some(value))
            .collect();
        delete_entity_chain(&mut tx, &binding, &outbox, chain.len()).await?;
        let replacement_mutation_id = if patch.is_empty() {
            None
        } else {
            let base_json = serde_json::to_string(&request.current_entity)?;
            let payload = json!({"patch": patch.clone()});
            Some(
                insert_replacement_intent(
                    &mut tx,
                    &binding,
                    ReplacementOutbox {
                        local_seq: outbox._local_seq,
                        entity_type: &outbox.entity_type,
                        entity_id: &outbox.entity_id,
                        operation: "update",
                        base_version: request.current_version,
                        base_json: Some(&base_json),
                        payload: &payload,
                    },
                )
                .await?,
            )
        };
        let mut materialized = request.current_entity.clone();
        if !patch.is_empty() {
            merge_object(&mut materialized, &Value::Object(patch))?;
        }
        write_materialized_entity(&mut tx, &outbox.entity_type, materialized).await?;
        tx.commit().await?;
        return Ok(MutationConflictOutcome {
            outcome: "rebased".to_string(),
            conflict_id: None,
            replacement_mutation_id,
            conflicting_fields: Vec::new(),
        });
    }

    let conflict_id = uuid::Uuid::new_v4().to_string();
    let now = chrono::Utc::now().to_rfc3339();
    sqlx::query(
        "INSERT INTO sync_conflicts (
            conflict_id, server_instance_id, account_id, session_id,
            entity_type, entity_id, mutation_id, base_version, remote_version,
            base_json, local_json, remote_json, conflicting_fields_json,
            state, resolution_mutation_id, created_at, resolved_at
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'open', NULL, ?, NULL)",
    )
    .bind(&conflict_id)
    .bind(&request.server_instance_id)
    .bind(&request.account_id)
    .bind(&request.session_id)
    .bind(&outbox.entity_type)
    .bind(&outbox.entity_id)
    .bind(&outbox.mutation_id)
    .bind(outbox.base_version)
    .bind(request.current_version)
    .bind(&outbox.base_json)
    .bind(serde_json::to_string(&local_value)?)
    .bind(serde_json::to_string(&request.current_entity)?)
    .bind(serde_json::to_string(&conflicting_fields)?)
    .bind(&now)
    .execute(&mut *tx)
    .await?;
    sqlx::query(
        "UPDATE sync_outbox
         SET state = 'conflict', next_attempt_at = NULL,
             last_error_code = 'VERSION_CONFLICT', updated_at = ?
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
           AND mutation_id = ?",
    )
    .bind(&now)
    .bind(&request.server_instance_id)
    .bind(&request.account_id)
    .bind(&request.session_id)
    .bind(&request.mutation_id)
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(MutationConflictOutcome {
        outcome: "conflict".to_string(),
        conflict_id: Some(conflict_id),
        replacement_mutation_id: None,
        conflicting_fields,
    })
}

fn parse_json_field(value: &str, code: &str) -> anyhow::Result<Value> {
    serde_json::from_str(value).map_err(|error| anyhow::anyhow!("{code}: {error}"))
}

fn conflict_row_to_model(
    row: &ConflictRow,
    remote_version: i64,
    remote_entity: Value,
    conflicting_fields: Vec<String>,
    allowed_resolutions: Vec<ConflictResolution>,
) -> anyhow::Result<OpenSyncConflict> {
    Ok(OpenSyncConflict {
        conflict_id: row.conflict_id.clone(),
        session_id: row.session_id.clone(),
        entity_type: row.entity_type.clone(),
        entity_id: row.entity_id.clone(),
        mutation_id: row.mutation_id.clone(),
        base_version: row.base_version,
        remote_version,
        base_entity: row
            .base_json
            .as_deref()
            .map(|value| parse_json_field(value, "CONFLICT_BASE_INVALID"))
            .transpose()?,
        local_entity: parse_json_field(&row.local_json, "CONFLICT_LOCAL_INVALID")?,
        remote_entity,
        conflicting_fields,
        allowed_resolutions,
        created_at: row.created_at.clone(),
    })
}

fn latest_conflicting_fields(
    conflict: &ConflictRow,
    chain: &[OutboxRow],
    local: &Value,
    remote: &Value,
) -> anyhow::Result<Vec<String>> {
    let mut fields = lifecycle_conflict_fields(&conflict.entity_type, chain);
    let base = conflict
        .base_json
        .as_deref()
        .map(|value| parse_json_field(value, "CONFLICT_BASE_INVALID"))
        .transpose()?;
    if let Some(base) = base.as_ref() {
        let local_fields = changed_fields(base, local, editable_fields(&conflict.entity_type)?)?;
        fields.extend(three_way_conflicting_fields(
            base,
            local,
            remote,
            &local_fields,
        )?);
        if chain.iter().all(|row| row.operation == "update") {
            fields.extend(remote_blocks_update(&conflict.entity_type, remote)?);
        }
    }
    let safely_foldable_update_chain = base.is_some()
        && chain.iter().all(|row| row.operation == "update")
        && chain
            .iter()
            .skip(1)
            .all(|row| row.state == "pending" && row.attempts == 0);
    if fields.is_empty() && !safely_foldable_update_chain {
        fields.push("chain".to_string());
    }
    fields.sort();
    fields.dedup();
    Ok(fields)
}

pub async fn list_open_conflicts(
    pool: &SqlitePool,
    server_instance_id: &str,
    account_id: &str,
    session_id: &str,
) -> anyhow::Result<Vec<OpenSyncConflict>> {
    let mut tx = pool.begin().await?;
    let binding =
        require_partition_binding(&mut tx, server_instance_id, account_id, session_id).await?;
    let rows = sqlx::query_as::<_, ConflictRow>(
        "SELECT conflict_id, server_instance_id, account_id, session_id,
                entity_type, entity_id, mutation_id, base_version, remote_version,
                base_json, local_json, remote_json, state, created_at
         FROM sync_conflicts
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
           AND state = 'open'
         ORDER BY created_at, conflict_id",
    )
    .bind(server_instance_id)
    .bind(account_id)
    .bind(session_id)
    .fetch_all(&mut *tx)
    .await?;
    let canonical_session_status =
        canonical_session_status_in_tx(&mut tx, server_instance_id, account_id, session_id).await?;
    let mut conflicts = Vec::with_capacity(rows.len());
    for row in &rows {
        let root = sqlx::query_as::<_, OutboxRow>(
            "SELECT local_seq, mutation_id, entity_type, entity_id, operation,
                    base_version, observed_seq, base_json, payload_json, state,
                    attempts, next_attempt_at, depends_on_mutation_id, created_at
             FROM sync_outbox
             WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
               AND mutation_id = ?",
        )
        .bind(server_instance_id)
        .bind(account_id)
        .bind(session_id)
        .bind(&row.mutation_id)
        .fetch_optional(&mut *tx)
        .await?
        .ok_or_else(|| anyhow::anyhow!("CONFLICT_INTENT_NOT_FOUND"))?;
        let chain = load_entity_chain_from_root(&mut tx, &binding, &root).await?;
        let (remote_version, remote, _) = latest_resolution_remote(&mut tx, row).await?;
        let local = parse_json_field(&row.local_json, "CONFLICT_LOCAL_INVALID")?;
        let conflicting_fields = latest_conflicting_fields(row, &chain, &local, &remote)?;
        let allowed_resolutions = allowed_conflict_resolutions(
            &binding,
            row,
            &root,
            &local,
            &remote,
            &canonical_session_status,
        )?;
        conflicts.push(conflict_row_to_model(
            row,
            remote_version,
            remote,
            conflicting_fields,
            allowed_resolutions,
        )?);
    }
    tx.commit().await?;
    Ok(conflicts)
}

fn canonical_conflict_entities_equal(
    entity_type: &str,
    left: &Value,
    right: &Value,
) -> anyhow::Result<bool> {
    match entity_type {
        "log" => {
            let left: RemoteLog = serde_json::from_value(left.clone())
                .map_err(|error| anyhow::anyhow!("CONFLICT_LOG_INVALID: {error}"))?;
            let right: RemoteLog = serde_json::from_value(right.clone())
                .map_err(|error| anyhow::anyhow!("CONFLICT_LOG_INVALID: {error}"))?;
            Ok(left == right)
        }
        "session" => {
            let left: CanonicalSessionEntity = serde_json::from_value(left.clone())
                .map_err(|error| anyhow::anyhow!("CONFLICT_SESSION_INVALID: {error}"))?;
            let right: CanonicalSessionEntity = serde_json::from_value(right.clone())
                .map_err(|error| anyhow::anyhow!("CONFLICT_SESSION_INVALID: {error}"))?;
            Ok(left == right)
        }
        _ => anyhow::bail!("ENTITY_TYPE_INVALID"),
    }
}

async fn latest_resolution_remote(
    tx: &mut Transaction<'_, Sqlite>,
    conflict: &ConflictRow,
) -> anyhow::Result<(i64, Value, String)> {
    let mut version = conflict.remote_version;
    let mut json = conflict.remote_json.clone();
    let shadow: Option<(i64, String)> = sqlx::query_as(
        "SELECT server_version, server_json FROM entity_shadows
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
           AND entity_type = ? AND entity_id = ?",
    )
    .bind(&conflict.server_instance_id)
    .bind(&conflict.account_id)
    .bind(&conflict.session_id)
    .bind(&conflict.entity_type)
    .bind(&conflict.entity_id)
    .fetch_optional(&mut **tx)
    .await?;
    if let Some((shadow_version, shadow_json)) = shadow {
        if shadow_version == version {
            let conflict_value = parse_json_field(&json, "CONFLICT_REMOTE_INVALID")?;
            let shadow_value = parse_json_field(&shadow_json, "COLLABORATION_SHADOW_INVALID")?;
            if !canonical_conflict_entities_equal(
                &conflict.entity_type,
                &conflict_value,
                &shadow_value,
            )? {
                anyhow::bail!("CONFLICT_REMOTE_FORK");
            }
        } else if shadow_version > version {
            version = shadow_version;
            json = shadow_json;
        }
    }
    let value = parse_json_field(&json, "CONFLICT_REMOTE_INVALID")?;
    validate_conflict_entity(
        &conflict.entity_type,
        &conflict.entity_id,
        &conflict.session_id,
        version,
        &value,
    )?;
    Ok((version, value, json))
}

fn local_intent_fields(
    entity_type: &str,
    base: Option<&Value>,
    local: &Value,
) -> anyhow::Result<Vec<String>> {
    let fields = editable_fields(entity_type)?;
    match base {
        Some(base) => changed_fields(base, local, fields),
        None => {
            for field in fields {
                if object_field(local, field)?.is_none() {
                    anyhow::bail!("CONFLICT_LOCAL_FIELD_MISSING:{field}");
                }
            }
            Ok(fields.iter().map(|field| (*field).to_string()).collect())
        }
    }
}

fn log_restore_value(value: &Value) -> anyhow::Result<Value> {
    let object = value
        .as_object()
        .ok_or_else(|| anyhow::anyhow!("CONFLICT_LOCAL_ENTITY_INVALID"))?;
    let mut restored = Map::new();
    for field in ["syncId", "sessionId"]
        .into_iter()
        .chain(LOG_EDITABLE_FIELDS.iter().copied())
    {
        restored.insert(
            field.to_string(),
            object
                .get(field)
                .cloned()
                .ok_or_else(|| anyhow::anyhow!("CONFLICT_LOCAL_FIELD_MISSING:{field}"))?,
        );
    }
    Ok(Value::Object(restored))
}

fn build_keep_local_resolution(
    entity_type: &str,
    base: Option<&Value>,
    local: &Value,
    remote: &Value,
) -> anyhow::Result<(Value, Option<(String, Value)>)> {
    let intent_fields = local_intent_fields(entity_type, base, local)?;
    let mut desired = remote.clone();
    let local_object = local
        .as_object()
        .ok_or_else(|| anyhow::anyhow!("CONFLICT_LOCAL_ENTITY_INVALID"))?;
    let desired_object = desired
        .as_object_mut()
        .ok_or_else(|| anyhow::anyhow!("CONFLICT_REMOTE_ENTITY_INVALID"))?;
    for field in &intent_fields {
        desired_object.insert(
            field.clone(),
            local_object
                .get(field)
                .cloned()
                .ok_or_else(|| anyhow::anyhow!("CONFLICT_LOCAL_FIELD_MISSING:{field}"))?,
        );
    }

    match entity_type {
        "log" => {
            let local_deleted = local.get("deletedAt").is_some_and(|value| !value.is_null());
            let remote_deleted = remote
                .get("deletedAt")
                .is_some_and(|value| !value.is_null());
            desired["deletedAt"] = if local_deleted && remote_deleted {
                remote.get("deletedAt").cloned().unwrap_or(Value::Null)
            } else if local_deleted {
                local.get("deletedAt").cloned().unwrap_or(Value::Null)
            } else {
                Value::Null
            };
            if local_deleted && !remote_deleted {
                return Ok((desired, Some(("delete".to_string(), json!({})))));
            }
            if !local_deleted && remote_deleted {
                let value = log_restore_value(&desired)?;
                return Ok((
                    desired,
                    Some(("restore".to_string(), json!({"value": value}))),
                ));
            }
            let patch = patch_for_fields(&desired, &intent_fields)?;
            let patch: Map<String, Value> = patch
                .into_iter()
                .filter(|(field, value)| remote.get(field) != Some(value))
                .collect();
            if local_deleted && !patch.is_empty() {
                anyhow::bail!("CONFLICT_KEEP_LOCAL_TOMBSTONE_UPDATE_UNSUPPORTED");
            }
            Ok((
                desired,
                (!patch.is_empty()).then(|| ("update".to_string(), json!({"patch": patch}))),
            ))
        }
        "session" => {
            if local.get("deletedAt").is_some_and(|value| !value.is_null()) {
                anyhow::bail!("CONFLICT_KEEP_LOCAL_SESSION_DELETE_UNSUPPORTED");
            }
            let local_status = local
                .get("status")
                .and_then(Value::as_str)
                .ok_or_else(|| anyhow::anyhow!("CONFLICT_LOCAL_ENTITY_INVALID"))?;
            let remote_status = remote
                .get("status")
                .and_then(Value::as_str)
                .ok_or_else(|| anyhow::anyhow!("CONFLICT_REMOTE_ENTITY_INVALID"))?;
            if !matches!(local_status, "active" | "closed")
                || !matches!(remote_status, "active" | "closed")
            {
                anyhow::bail!("CONFLICT_SESSION_STATUS_INVALID");
            }
            desired["status"] = Value::String(local_status.to_string());
            desired["closedAt"] = if local_status == "active" {
                Value::Null
            } else if remote_status == "closed" {
                remote.get("closedAt").cloned().unwrap_or(Value::Null)
            } else {
                local.get("closedAt").cloned().unwrap_or(Value::Null)
            };
            let title_changed = remote.get("title") != desired.get("title");
            let intent = match (remote_status, local_status, title_changed) {
                ("active", "active", true) => Some((
                    "update".to_string(),
                    json!({"patch": {"title": desired["title"].clone()}}),
                )),
                ("active", "active", false) | ("closed", "closed", false) => None,
                ("active", "closed", false) => Some(("close".to_string(), json!({}))),
                ("closed", "active", false) => Some(("reopen".to_string(), json!({}))),
                _ => anyhow::bail!("CONFLICT_KEEP_LOCAL_MULTI_STEP_UNSUPPORTED"),
            };
            Ok((desired, intent))
        }
        _ => anyhow::bail!("ENTITY_TYPE_INVALID"),
    }
}

fn allowed_conflict_resolutions(
    binding: &BindingRow,
    conflict: &ConflictRow,
    root: &OutboxRow,
    local: &Value,
    remote: &Value,
    canonical_session_status: &str,
) -> anyhow::Result<Vec<ConflictResolution>> {
    let mut allowed = vec![ConflictResolution::UseRemote];
    let local_deleted = local.get("deletedAt").is_some_and(|value| !value.is_null());
    let remote_deleted = remote
        .get("deletedAt")
        .is_some_and(|value| !value.is_null());
    let can_write_entity = match conflict.entity_type.as_str() {
        "log" => binding.role != "viewer" && canonical_session_status == "active",
        "session" => binding.role == "owner",
        _ => false,
    };
    let base = conflict
        .base_json
        .as_deref()
        .map(|value| parse_json_field(value, "CONFLICT_BASE_INVALID"))
        .transpose()?;
    let keep_local_semantically_safe = base.is_some()
        && root.operation != "create"
        && !(conflict.entity_type == "log"
            && remote_deleted
            && !local_deleted
            && root.operation != "restore");
    if can_write_entity
        && keep_local_semantically_safe
        && build_keep_local_resolution(&conflict.entity_type, base.as_ref(), local, remote).is_ok()
    {
        allowed.push(ConflictResolution::KeepLocal);
    }
    if conflict.entity_type == "log"
        && binding.role != "viewer"
        && canonical_session_status == "active"
        && !local_deleted
    {
        allowed.push(ConflictResolution::CopyLocalAsNew);
    }
    Ok(allowed)
}

fn build_local_log_copy(local: &Value, new_sync_id: &str) -> anyhow::Result<(Value, Value)> {
    let local_log: RemoteLog = serde_json::from_value(local.clone())
        .map_err(|error| anyhow::anyhow!("CONFLICT_LOCAL_LOG_INVALID: {error}"))?;
    if local_log.deleted_at.is_some() {
        anyhow::bail!("CONFLICT_COPY_DELETED_LOG_NOT_ALLOWED");
    }
    let normalized_time =
        normalize_publish_time(&local_log.time, &local_log.created_at, new_sync_id)?;
    let now = chrono::Utc::now().to_rfc3339();
    let mut copy = local.clone();
    copy["syncId"] = Value::String(new_sync_id.to_string());
    copy["version"] = Value::from(1);
    copy["createdAt"] = Value::String(now.clone());
    copy["updatedAt"] = Value::String(now.clone());
    copy["deletedAt"] = Value::Null;
    copy["time"] = Value::String(normalized_time);
    let value = log_restore_value(&copy)?;
    Ok((copy, json!({"value": value})))
}

async fn allocate_copy_sync_id(
    tx: &mut Transaction<'_, Sqlite>,
    binding: &BindingRow,
) -> anyhow::Result<String> {
    for _ in 0..8 {
        let candidate = uuid::Uuid::new_v4().to_string();
        let exists: (i64,) = sqlx::query_as(
            "SELECT
                (SELECT COUNT(*) FROM logs WHERE sync_id = ?) +
                (SELECT COUNT(*) FROM sync_outbox
                 WHERE server_instance_id = ? AND account_id = ? AND entity_id = ?) +
                (SELECT COUNT(*) FROM entity_shadows
                 WHERE server_instance_id = ? AND account_id = ?
                   AND entity_type = 'log' AND entity_id = ?)",
        )
        .bind(&candidate)
        .bind(&binding.server_instance_id)
        .bind(&binding.account_id)
        .bind(&candidate)
        .bind(&binding.server_instance_id)
        .bind(&binding.account_id)
        .bind(&candidate)
        .fetch_one(&mut **tx)
        .await?;
        if exists.0 == 0 {
            return Ok(candidate);
        }
    }
    anyhow::bail!("CONFLICT_COPY_ID_ALLOCATION_FAILED")
}

async fn delete_open_conflict(
    tx: &mut Transaction<'_, Sqlite>,
    conflict: &ConflictRow,
) -> anyhow::Result<()> {
    let deleted = sqlx::query(
        "DELETE FROM sync_conflicts
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
           AND conflict_id = ? AND state = 'open'",
    )
    .bind(&conflict.server_instance_id)
    .bind(&conflict.account_id)
    .bind(&conflict.session_id)
    .bind(&conflict.conflict_id)
    .execute(&mut **tx)
    .await?;
    if deleted.rows_affected() != 1 {
        anyhow::bail!("CONFLICT_RESOLUTION_RACE");
    }
    Ok(())
}

pub async fn resolve_conflict(
    pool: &SqlitePool,
    request: ResolveConflictRequest,
) -> anyhow::Result<ResolveConflictResult> {
    if request.conflict_id.trim().is_empty() {
        anyhow::bail!("CONFLICT_ID_REQUIRED");
    }
    let mut tx = pool.begin().await?;
    let binding = require_partition_binding(
        &mut tx,
        &request.server_instance_id,
        &request.account_id,
        &request.session_id,
    )
    .await?;
    if binding.replica_state != "ready" {
        anyhow::bail!("COLLABORATION_NOT_READY");
    }
    let conflict = sqlx::query_as::<_, ConflictRow>(
        "SELECT conflict_id, server_instance_id, account_id, session_id,
                entity_type, entity_id, mutation_id, base_version, remote_version,
                base_json, local_json, remote_json, state, created_at
         FROM sync_conflicts
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
           AND conflict_id = ? AND state = 'open'",
    )
    .bind(&request.server_instance_id)
    .bind(&request.account_id)
    .bind(&request.session_id)
    .bind(&request.conflict_id)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or_else(|| anyhow::anyhow!("OPEN_CONFLICT_NOT_FOUND"))?;
    if conflict.state != "open" {
        anyhow::bail!("OPEN_CONFLICT_NOT_FOUND");
    }
    let root = sqlx::query_as::<_, OutboxRow>(
        "SELECT local_seq, mutation_id, entity_type, entity_id, operation,
                base_version, observed_seq, base_json, payload_json, state,
                attempts, next_attempt_at, depends_on_mutation_id, created_at
         FROM sync_outbox
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
           AND mutation_id = ?",
    )
    .bind(&request.server_instance_id)
    .bind(&request.account_id)
    .bind(&request.session_id)
    .bind(&conflict.mutation_id)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or_else(|| anyhow::anyhow!("CONFLICT_INTENT_NOT_FOUND"))?;
    if root.state != "conflict" {
        anyhow::bail!("CONFLICT_INTENT_STATE_INVALID");
    }
    let chain = load_entity_chain_from_root(&mut tx, &binding, &root).await?;
    let (remote_version, remote, remote_json) =
        latest_resolution_remote(&mut tx, &conflict).await?;
    if remote_version != request.expected_remote_version {
        anyhow::bail!("CONFLICT_REMOTE_ADVANCED");
    }
    let local = parse_json_field(&conflict.local_json, "CONFLICT_LOCAL_INVALID")?;
    let canonical_session_status = canonical_session_status_in_tx(
        &mut tx,
        &request.server_instance_id,
        &request.account_id,
        &request.session_id,
    )
    .await?;
    let allowed = allowed_conflict_resolutions(
        &binding,
        &conflict,
        &root,
        &local,
        &remote,
        &canonical_session_status,
    )?;
    if request.resolution != ConflictResolution::UseRemote && binding.role == "viewer" {
        anyhow::bail!("COLLABORATION_ROLE_READ_ONLY");
    }
    if request.resolution == ConflictResolution::KeepLocal
        && conflict.entity_type == "session"
        && binding.role != "owner"
    {
        anyhow::bail!("COLLABORATION_OWNER_REQUIRED");
    }
    if request.resolution != ConflictResolution::UseRemote
        && conflict.entity_type == "log"
        && canonical_session_status != "active"
    {
        anyhow::bail!("SESSION_NOT_ACTIVE");
    }
    if !allowed.contains(&request.resolution) {
        anyhow::bail!("CONFLICT_RESOLUTION_NOT_ALLOWED");
    }

    let mut replacement_entity_id = None;
    let mut copied_materialized = None;
    let (materialized, intent): (Value, Option<(String, String, i64, Option<String>, Value)>) =
        match request.resolution {
            ConflictResolution::UseRemote => (remote.clone(), None),
            ConflictResolution::KeepLocal => {
                let base = conflict
                    .base_json
                    .as_deref()
                    .map(|value| parse_json_field(value, "CONFLICT_BASE_INVALID"))
                    .transpose()?;
                let (desired, intent) = build_keep_local_resolution(
                    &conflict.entity_type,
                    base.as_ref(),
                    &local,
                    &remote,
                )?;
                (
                    desired,
                    intent.map(|(operation, payload)| {
                        (
                            root.entity_id.clone(),
                            operation,
                            remote_version,
                            Some(remote_json.clone()),
                            payload,
                        )
                    }),
                )
            }
            ConflictResolution::CopyLocalAsNew => {
                let new_sync_id = allocate_copy_sync_id(&mut tx, &binding).await?;
                let (copy, payload) = build_local_log_copy(&local, &new_sync_id)?;
                replacement_entity_id = Some(new_sync_id.clone());
                copied_materialized = Some(copy);
                (
                    remote.clone(),
                    Some((new_sync_id, "create".to_string(), 0, None, payload)),
                )
            }
        };

    delete_open_conflict(&mut tx, &conflict).await?;
    delete_entity_chain(&mut tx, &binding, &root, chain.len()).await?;
    let replacement_mutation_id =
        if let Some((entity_id, operation, base_version, base_json, payload)) = intent {
            Some(
                insert_replacement_intent(
                    &mut tx,
                    &binding,
                    ReplacementOutbox {
                        local_seq: root._local_seq,
                        entity_type: &root.entity_type,
                        entity_id: &entity_id,
                        operation: &operation,
                        base_version,
                        base_json: base_json.as_deref(),
                        payload: &payload,
                    },
                )
                .await?,
            )
        } else {
            None
        };
    write_materialized_entity(&mut tx, &root.entity_type, materialized).await?;
    if let Some(copy) = copied_materialized {
        write_materialized_log(&mut tx, copy).await?;
    }
    tx.commit().await?;
    Ok(ResolveConflictResult {
        outcome: "resolved".to_string(),
        resolution: request.resolution,
        replacement_mutation_id,
        replacement_entity_id,
    })
}

fn validate_event(request: &ApplyEventRequest) -> anyhow::Result<()> {
    let event = &request.event;
    if event.protocol_version != 1 {
        anyhow::bail!("EVENT_PROTOCOL_MISMATCH");
    }
    require_text(&request.server_instance_id, "EVENT_SERVER_ID_REQUIRED")?;
    require_text(&request.account_id, "EVENT_ACCOUNT_ID_REQUIRED")?;
    require_text(&event.event_id, "EVENT_ID_REQUIRED")?;
    require_text(&event.session_id, "EVENT_SESSION_ID_REQUIRED")?;
    require_text(&event.entity_id, "EVENT_ENTITY_ID_REQUIRED")?;
    if event.seq < 1 || event.entity_version < 1 {
        anyhow::bail!("EVENT_SEQUENCE_OR_VERSION_INVALID");
    }
    DateTime::parse_from_rfc3339(&event.occurred_at)
        .map_err(|_| anyhow::anyhow!("EVENT_TIME_INVALID"))?;
    if event.mutation_id.as_deref().is_some_and(str::is_empty) {
        anyhow::bail!("EVENT_MUTATION_ID_INVALID");
    }
    match (event.entity_type.as_str(), event.event_type.as_str()) {
        (
            "session",
            "session.activated" | "session.updated" | "session.closed" | "session.reopened"
            | "session.deleted",
        ) => {
            let session: CanonicalSessionEntity = serde_json::from_value(event.payload.clone())
                .map_err(|error| anyhow::anyhow!("EVENT_SESSION_PAYLOAD_INVALID: {error}"))?;
            if session.session_id != event.session_id
                || event.entity_id != event.session_id
                || session.version != event.entity_version
            {
                anyhow::bail!("EVENT_ENTITY_MISMATCH");
            }
            for value in [&session.created_at, &session.updated_at] {
                DateTime::parse_from_rfc3339(value)
                    .map_err(|_| anyhow::anyhow!("EVENT_SESSION_TIME_INVALID"))?;
            }
            for value in [session.closed_at.as_deref(), session.deleted_at.as_deref()]
                .into_iter()
                .flatten()
            {
                DateTime::parse_from_rfc3339(value)
                    .map_err(|_| anyhow::anyhow!("EVENT_SESSION_TIME_INVALID"))?;
            }
            if event.event_type != "session.deleted"
                && session.status != "active"
                && session.status != "closed"
            {
                anyhow::bail!("EVENT_SESSION_STATE_INVALID");
            }
            match event.event_type.as_str() {
                "session.closed" if session.status != "closed" => {
                    anyhow::bail!("EVENT_SESSION_STATE_INVALID")
                }
                "session.activated" | "session.reopened" if session.status != "active" => {
                    anyhow::bail!("EVENT_SESSION_STATE_INVALID")
                }
                "session.deleted" if session.deleted_at.is_none() => {
                    anyhow::bail!("EVENT_SESSION_STATE_INVALID")
                }
                _ => {}
            }
        }
        ("log", "log.created" | "log.updated" | "log.deleted" | "log.restored") => {
            let log: RemoteLog = serde_json::from_value(event.payload.clone())
                .map_err(|error| anyhow::anyhow!("EVENT_LOG_PAYLOAD_INVALID: {error}"))?;
            if log.session_id != event.session_id
                || log.sync_id != event.entity_id
                || log.version != event.entity_version
            {
                anyhow::bail!("EVENT_ENTITY_MISMATCH");
            }
            for value in [&log.time, &log.created_at, &log.updated_at] {
                DateTime::parse_from_rfc3339(value)
                    .map_err(|_| anyhow::anyhow!("EVENT_LOG_TIME_INVALID"))?;
            }
            if let Some(value) = &log.deleted_at {
                DateTime::parse_from_rfc3339(value)
                    .map_err(|_| anyhow::anyhow!("EVENT_LOG_TIME_INVALID"))?;
            }
            match event.event_type.as_str() {
                "log.deleted" if log.deleted_at.is_none() => {
                    anyhow::bail!("EVENT_LOG_STATE_INVALID")
                }
                "log.created" | "log.updated" | "log.restored" if log.deleted_at.is_some() => {
                    anyhow::bail!("EVENT_LOG_STATE_INVALID")
                }
                _ => {}
            }
        }
        _ => anyhow::bail!("EVENT_TYPE_INVALID"),
    }
    Ok(())
}

async fn write_shadow(
    tx: &mut Transaction<'_, Sqlite>,
    request: &ApplyEventRequest,
) -> anyhow::Result<()> {
    let event = &request.event;
    let deleted = match event.entity_type.as_str() {
        "log" | "session" => i64::from(
            event
                .payload
                .get("deletedAt")
                .is_some_and(|value| !value.is_null()),
        ),
        _ => unreachable!(),
    };
    sqlx::query(
        "INSERT INTO entity_shadows (
            server_instance_id, account_id, session_id, entity_type, entity_id,
            server_version, last_event_seq, server_json, deleted
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(server_instance_id, account_id, session_id, entity_type, entity_id)
         DO UPDATE SET
            server_version = excluded.server_version,
            last_event_seq = excluded.last_event_seq,
            server_json = excluded.server_json,
            deleted = excluded.deleted",
    )
    .bind(&request.server_instance_id)
    .bind(&request.account_id)
    .bind(&event.session_id)
    .bind(&event.entity_type)
    .bind(&event.entity_id)
    .bind(event.entity_version)
    .bind(event.seq)
    .bind(serde_json::to_string(&event.payload)?)
    .bind(deleted)
    .execute(&mut **tx)
    .await?;
    Ok(())
}

fn merge_object(target: &mut Value, source: &Value) -> anyhow::Result<()> {
    let target = target
        .as_object_mut()
        .ok_or_else(|| anyhow::anyhow!("MATERIALIZED_ENTITY_INVALID"))?;
    let source = source
        .as_object()
        .ok_or_else(|| anyhow::anyhow!("OUTBOX_PAYLOAD_INVALID"))?;
    target.extend(
        source
            .iter()
            .map(|(key, value)| (key.clone(), value.clone())),
    );
    Ok(())
}

async fn apply_pending_overlay(
    tx: &mut Transaction<'_, Sqlite>,
    request: &ApplyEventRequest,
    mut value: Value,
) -> anyhow::Result<Value> {
    let rows = sqlx::query_as::<_, OutboxRow>(
        "SELECT local_seq, mutation_id, entity_type, entity_id, operation,
                base_version, observed_seq, base_json, payload_json, state,
                attempts, next_attempt_at, depends_on_mutation_id, created_at
         FROM sync_outbox
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
           AND entity_type = ? AND entity_id = ?
         ORDER BY local_seq",
    )
    .bind(&request.server_instance_id)
    .bind(&request.account_id)
    .bind(&request.event.session_id)
    .bind(&request.event.entity_type)
    .bind(&request.event.entity_id)
    .fetch_all(&mut **tx)
    .await?;
    for row in rows {
        let payload: Value = serde_json::from_str(&row.payload_json)
            .map_err(|error| anyhow::anyhow!("OUTBOX_PAYLOAD_INVALID: {error}"))?;
        match row.operation.as_str() {
            "create" | "restore" => {
                merge_object(
                    &mut value,
                    payload
                        .get("value")
                        .ok_or_else(|| anyhow::anyhow!("OUTBOX_PAYLOAD_INVALID"))?,
                )?;
                value["deletedAt"] = Value::Null;
            }
            "update" => merge_object(
                &mut value,
                payload
                    .get("patch")
                    .ok_or_else(|| anyhow::anyhow!("OUTBOX_PAYLOAD_INVALID"))?,
            )?,
            "delete" => value["deletedAt"] = Value::String(row.created_at),
            "close" => {
                value["status"] = Value::String("closed".to_string());
                value["closedAt"] = Value::String(row.created_at);
            }
            "reopen" => {
                value["status"] = Value::String("active".to_string());
                value["closedAt"] = Value::Null;
            }
            _ => anyhow::bail!("OUTBOX_OPERATION_INVALID"),
        }
    }
    Ok(value)
}

async fn write_materialized_log(
    tx: &mut Transaction<'_, Sqlite>,
    value: Value,
) -> anyhow::Result<()> {
    let log: RemoteLog = serde_json::from_value(value)
        .map_err(|error| anyhow::anyhow!("MATERIALIZED_LOG_INVALID: {error}"))?;
    let collision: Option<(String,)> =
        sqlx::query_as("SELECT session_id FROM logs WHERE sync_id = ? AND session_id <> ?")
            .bind(&log.sync_id)
            .bind(&log.session_id)
            .fetch_optional(&mut **tx)
            .await?;
    if collision.is_some() {
        anyhow::bail!("LOCAL_LOG_ID_CONFLICT");
    }
    sqlx::query(
        "INSERT INTO logs (
            sync_id, session_id, time, controller, callsign,
            rst_sent, rst_rcvd, qth, device, power, antenna, height, remarks,
            created_at, updated_at, deleted_at, source_device_id
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)
         ON CONFLICT(sync_id) DO UPDATE SET
            session_id = excluded.session_id,
            time = excluded.time,
            controller = excluded.controller,
            callsign = excluded.callsign,
            rst_sent = excluded.rst_sent,
            rst_rcvd = excluded.rst_rcvd,
            qth = excluded.qth,
            device = excluded.device,
            power = excluded.power,
            antenna = excluded.antenna,
            height = excluded.height,
            remarks = excluded.remarks,
            created_at = excluded.created_at,
            updated_at = excluded.updated_at,
            deleted_at = excluded.deleted_at",
    )
    .bind(&log.sync_id)
    .bind(&log.session_id)
    .bind(&log.time)
    .bind(&log.controller)
    .bind(&log.callsign)
    .bind(&log.rst_sent)
    .bind(&log.rst_rcvd)
    .bind(&log.qth)
    .bind(&log.device)
    .bind(&log.power)
    .bind(&log.antenna)
    .bind(&log.height)
    .bind(&log.remarks)
    .bind(&log.created_at)
    .bind(&log.updated_at)
    .bind(&log.deleted_at)
    .execute(&mut **tx)
    .await?;
    Ok(())
}

async fn write_materialized_session(
    tx: &mut Transaction<'_, Sqlite>,
    value: Value,
) -> anyhow::Result<()> {
    let session: CanonicalSessionEntity = serde_json::from_value(value)
        .map_err(|error| anyhow::anyhow!("MATERIALIZED_SESSION_INVALID: {error}"))?;
    sqlx::query(
        "INSERT INTO sessions (
            session_id, title, status, share_code, created_at, updated_at,
            closed_at, deleted_at
         ) VALUES (?, ?, ?, NULL, ?, ?, ?, ?)
         ON CONFLICT(session_id) DO UPDATE SET
            title = excluded.title,
            status = excluded.status,
            share_code = NULL,
            created_at = excluded.created_at,
            updated_at = excluded.updated_at,
            closed_at = excluded.closed_at,
            deleted_at = excluded.deleted_at",
    )
    .bind(&session.session_id)
    .bind(&session.title)
    .bind(&session.status)
    .bind(&session.created_at)
    .bind(&session.updated_at)
    .bind(&session.closed_at)
    .bind(&session.deleted_at)
    .execute(&mut **tx)
    .await?;
    Ok(())
}

fn shadow_matches_duplicate_event(
    entity_type: &str,
    shadow_json: &str,
    event_payload: &Value,
) -> anyhow::Result<bool> {
    if entity_type == "session" {
        // Snapshot session objects additionally carry the requesting member's
        // role and the snapshot watermark. Compare only the canonical entity
        // fields that also exist in session events.
        let shadow: CanonicalSessionEntity = serde_json::from_str(shadow_json)
            .map_err(|error| anyhow::anyhow!("COLLABORATION_SHADOW_INVALID: {error}"))?;
        let event: CanonicalSessionEntity = serde_json::from_value(event_payload.clone())
            .map_err(|error| anyhow::anyhow!("EVENT_SESSION_PAYLOAD_INVALID: {error}"))?;
        return Ok(shadow == event);
    }
    let shadow: Value = serde_json::from_str(shadow_json)
        .map_err(|error| anyhow::anyhow!("COLLABORATION_SHADOW_INVALID: {error}"))?;
    Ok(shadow == *event_payload)
}

/// A mutation replay after snapshot reinstall can return its original event,
/// whose sequence is already below the new cursor. The ordinary duplicate
/// fast-path must still retire that accepted outbox row. This is safe only when
/// the current canonical shadow proves that the event (or a later entity
/// version) is already represented by the installed baseline.
async fn reconcile_duplicate_event_outbox(
    tx: &mut Transaction<'_, Sqlite>,
    binding: &BindingRow,
    request: &ApplyEventRequest,
) -> anyhow::Result<()> {
    let event = &request.event;
    let Some(mutation_id) = event.mutation_id.as_deref() else {
        return Ok(());
    };
    let matched = sqlx::query_as::<_, OutboxRow>(
        "SELECT local_seq, mutation_id, entity_type, entity_id, operation,
                base_version, observed_seq, base_json, payload_json, state,
                attempts, next_attempt_at, depends_on_mutation_id, created_at
         FROM sync_outbox
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
           AND mutation_id = ?",
    )
    .bind(&request.server_instance_id)
    .bind(&request.account_id)
    .bind(&event.session_id)
    .bind(mutation_id)
    .fetch_optional(&mut **tx)
    .await?;
    let Some(matched) = matched else {
        return Ok(());
    };
    if matched.entity_type != event.entity_type || matched.entity_id != event.entity_id {
        anyhow::bail!("EVENT_MUTATION_ENTITY_MISMATCH");
    }
    if matched.state != "accepted" {
        anyhow::bail!("DUPLICATE_EVENT_MUTATION_NOT_ACCEPTED");
    }
    let (accepted_event_seq,): (Option<i64>,) = sqlx::query_as(
        "SELECT accepted_event_seq FROM sync_outbox
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
           AND mutation_id = ?",
    )
    .bind(&request.server_instance_id)
    .bind(&request.account_id)
    .bind(&event.session_id)
    .bind(mutation_id)
    .fetch_one(&mut **tx)
    .await?;
    if accepted_event_seq != Some(event.seq) {
        anyhow::bail!("ACCEPTED_EVENT_SEQUENCE_MISMATCH");
    }
    let expected_version = matched
        .base_version
        .checked_add(1)
        .ok_or_else(|| anyhow::anyhow!("OUTBOX_BASE_VERSION_INVALID"))?;
    if event.entity_version != expected_version {
        anyhow::bail!("EVENT_MUTATION_VERSION_MISMATCH");
    }

    let shadow: Option<(i64, String)> = sqlx::query_as(
        "SELECT server_version, server_json FROM entity_shadows
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
           AND entity_type = ? AND entity_id = ?",
    )
    .bind(&request.server_instance_id)
    .bind(&request.account_id)
    .bind(&event.session_id)
    .bind(&event.entity_type)
    .bind(&event.entity_id)
    .fetch_optional(&mut **tx)
    .await?;
    let Some((canonical_version, canonical_json)) = shadow else {
        anyhow::bail!("DUPLICATE_EVENT_SHADOW_MISSING");
    };
    if canonical_version < event.entity_version {
        anyhow::bail!("DUPLICATE_EVENT_SHADOW_BEHIND");
    }
    if canonical_version == event.entity_version
        && !shadow_matches_duplicate_event(&event.entity_type, &canonical_json, &event.payload)?
    {
        anyhow::bail!("DUPLICATE_EVENT_CANONICAL_FORK");
    }

    let now = chrono::Utc::now().to_rfc3339();
    let acknowledged = acknowledge_outbox_root_covered_by_canonical(
        tx,
        &request.server_instance_id,
        &request.account_id,
        &event.session_id,
        mutation_id,
        &event.entity_type,
        &event.entity_id,
        matched.base_version,
        canonical_version,
        &canonical_json,
        binding.last_applied_seq,
        &now,
    )
    .await?;
    if !acknowledged {
        anyhow::bail!("DUPLICATE_EVENT_NOT_COVERED");
    }

    let canonical: Value = serde_json::from_str(&canonical_json)
        .map_err(|error| anyhow::anyhow!("COLLABORATION_SHADOW_INVALID: {error}"))?;
    let materialized = apply_pending_overlay(tx, request, canonical).await?;
    match event.entity_type.as_str() {
        "log" => write_materialized_log(tx, materialized).await?,
        "session" => write_materialized_session(tx, materialized).await?,
        _ => unreachable!(),
    }
    Ok(())
}

pub async fn apply_event(
    pool: &SqlitePool,
    request: ApplyEventRequest,
) -> anyhow::Result<ApplyEventResult> {
    validate_event(&request)?;
    let event = &request.event;
    let mut tx = pool.begin().await?;
    let binding = require_partition_binding(
        &mut tx,
        &request.server_instance_id,
        &request.account_id,
        &event.session_id,
    )
    .await?;
    if binding.replica_state != "ready" {
        anyhow::bail!("COLLABORATION_NOT_READY");
    }
    let cursor = binding.last_applied_seq;

    let event_id_row: Option<(i64,)> = sqlx::query_as(
        "SELECT event_seq FROM applied_events
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
           AND event_id = ?",
    )
    .bind(&request.server_instance_id)
    .bind(&request.account_id)
    .bind(&event.session_id)
    .bind(&event.event_id)
    .fetch_optional(&mut *tx)
    .await?;
    if let Some((stored_seq,)) = event_id_row {
        if stored_seq != event.seq {
            anyhow::bail!("EVENT_ID_SEQUENCE_FORK");
        }
    }
    if event.seq <= cursor {
        let seq_row: Option<(String,)> = sqlx::query_as(
            "SELECT event_id FROM applied_events
             WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
               AND event_seq = ?",
        )
        .bind(&request.server_instance_id)
        .bind(&request.account_id)
        .bind(&event.session_id)
        .bind(event.seq)
        .fetch_optional(&mut *tx)
        .await?;
        if let Some((stored_event_id,)) = seq_row {
            if stored_event_id != event.event_id {
                anyhow::bail!("EVENT_SEQUENCE_FORK");
            }
        }
        reconcile_duplicate_event_outbox(&mut tx, &binding, &request).await?;
        tx.commit().await?;
        return Ok(ApplyEventResult {
            outcome: "duplicate".to_string(),
            cursor,
            expected_seq: cursor + 1,
        });
    }
    if event.seq != cursor + 1 {
        tx.commit().await?;
        return Ok(ApplyEventResult {
            outcome: "gap".to_string(),
            cursor,
            expected_seq: cursor + 1,
        });
    }

    write_shadow(&mut tx, &request).await?;
    if let Some(mutation_id) = &event.mutation_id {
        let matched = sqlx::query_as::<_, OutboxRow>(
            "SELECT local_seq, mutation_id, entity_type, entity_id, operation,
                    base_version, observed_seq, base_json, payload_json, state,
                    attempts, next_attempt_at, depends_on_mutation_id, created_at
             FROM sync_outbox
             WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
               AND mutation_id = ?",
        )
        .bind(&request.server_instance_id)
        .bind(&request.account_id)
        .bind(&event.session_id)
        .bind(mutation_id)
        .fetch_optional(&mut *tx)
        .await?;
        if let Some(matched) = matched {
            if matched.entity_type != event.entity_type || matched.entity_id != event.entity_id {
                anyhow::bail!("EVENT_MUTATION_ENTITY_MISMATCH");
            }
            let accepted_seq: Option<(Option<i64>,)> =
                sqlx::query_as("SELECT accepted_event_seq FROM sync_outbox WHERE mutation_id = ?")
                    .bind(mutation_id)
                    .fetch_optional(&mut *tx)
                    .await?;
            if accepted_seq
                .and_then(|row| row.0)
                .is_some_and(|seq| seq != event.seq)
            {
                anyhow::bail!("ACCEPTED_EVENT_SEQUENCE_MISMATCH");
            }
            sqlx::query(
                "UPDATE sync_outbox
                 SET base_version = ?, base_json = ?, observed_seq = ?,
                     depends_on_mutation_id = NULL, updated_at = ?
                 WHERE depends_on_mutation_id = ?",
            )
            .bind(event.entity_version)
            .bind(serde_json::to_string(&event.payload)?)
            .bind(event.seq)
            .bind(chrono::Utc::now().to_rfc3339())
            .bind(mutation_id)
            .execute(&mut *tx)
            .await?;
            sqlx::query("DELETE FROM sync_outbox WHERE mutation_id = ?")
                .bind(mutation_id)
                .execute(&mut *tx)
                .await?;
        }
    }

    let materialized = apply_pending_overlay(&mut tx, &request, event.payload.clone()).await?;
    match event.entity_type.as_str() {
        "log" => write_materialized_log(&mut tx, materialized).await?,
        "session" => write_materialized_session(&mut tx, materialized).await?,
        _ => unreachable!(),
    }
    sqlx::query(
        "INSERT INTO applied_events (
            server_instance_id, account_id, session_id, event_id,
            event_seq, mutation_id, applied_at
         ) VALUES (?, ?, ?, ?, ?, ?, ?)",
    )
    .bind(&request.server_instance_id)
    .bind(&request.account_id)
    .bind(&event.session_id)
    .bind(&event.event_id)
    .bind(event.seq)
    .bind(&event.mutation_id)
    .bind(chrono::Utc::now().to_rfc3339())
    .execute(&mut *tx)
    .await?;
    sqlx::query(
        "UPDATE collaboration_bindings
         SET last_applied_seq = ?,
             last_seen_head_seq = MAX(last_seen_head_seq, ?),
             updated_at = ?
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?",
    )
    .bind(event.seq)
    .bind(event.seq)
    .bind(chrono::Utc::now().to_rfc3339())
    .bind(&request.server_instance_id)
    .bind(&request.account_id)
    .bind(&event.session_id)
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(ApplyEventResult {
        outcome: "applied".to_string(),
        cursor: event.seq,
        expected_seq: event.seq + 1,
    })
}

pub async fn set_head_seq(
    pool: &SqlitePool,
    server_instance_id: &str,
    account_id: &str,
    session_id: &str,
    head_seq: i64,
) -> anyhow::Result<()> {
    if head_seq < 0 {
        anyhow::bail!("HEAD_SEQUENCE_INVALID");
    }
    let mut tx = pool.begin().await?;
    let binding =
        require_partition_binding(&mut tx, server_instance_id, account_id, session_id).await?;
    if head_seq < binding.last_applied_seq {
        anyhow::bail!("HEAD_SEQUENCE_BEHIND_CURSOR");
    }
    sqlx::query(
        "UPDATE collaboration_bindings
         SET last_seen_head_seq = MAX(last_seen_head_seq, ?), updated_at = ?
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?",
    )
    .bind(head_seq)
    .bind(chrono::Utc::now().to_rfc3339())
    .bind(server_instance_id)
    .bind(account_id)
    .bind(session_id)
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(())
}

pub async fn get_sync_status(
    pool: &SqlitePool,
    server_instance_id: &str,
    account_id: &str,
    session_id: &str,
) -> anyhow::Result<SyncStatus> {
    let mut tx = pool.begin().await?;
    let binding = sqlx::query_as::<_, BindingRow>(
        "SELECT * FROM collaboration_bindings
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?",
    )
    .bind(server_instance_id)
    .bind(account_id)
    .bind(session_id)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or_else(|| anyhow::anyhow!("BINDING_NOT_FOUND"))?;
    let pending: (i64,) = sqlx::query_as(
        "SELECT COUNT(*) FROM sync_outbox
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
           AND state IN ('pending', 'sending', 'accepted', 'retrying', 'rejected')",
    )
    .bind(server_instance_id)
    .bind(account_id)
    .bind(session_id)
    .fetch_one(&mut *tx)
    .await?;
    let conflicts: (i64,) = sqlx::query_as(
        "SELECT COUNT(*) FROM sync_conflicts
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
           AND state <> 'resolved'",
    )
    .bind(server_instance_id)
    .bind(account_id)
    .bind(session_id)
    .fetch_one(&mut *tx)
    .await?;
    let rejected: (i64,) = sqlx::query_as(
        "SELECT COUNT(*) FROM sync_outbox
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
           AND state = 'rejected'",
    )
    .bind(server_instance_id)
    .bind(account_id)
    .bind(session_id)
    .fetch_one(&mut *tx)
    .await?;
    let canonical_session_status =
        canonical_session_status_in_tx(&mut tx, server_instance_id, account_id, session_id).await?;
    let status = SyncStatus {
        session_id: session_id.to_string(),
        role: CollaborationRole::parse(&binding.role)?,
        replica_state: binding.replica_state,
        canonical_session_status,
        last_applied_seq: binding.last_applied_seq,
        last_seen_head_seq: binding.last_seen_head_seq,
        pending_count: pending.0,
        conflict_count: conflicts.0,
        rejected_count: rejected.0,
    };
    tx.commit().await?;
    Ok(status)
}
