use crate::models::live_draft::{
    LiveDraftIdentity, LocalLiveDraftCache, LocalOfflineRecord, QueueOfflineRecordRequest,
    SaveLiveDraftCacheRequest, UpdateOfflineRecordRequest,
};
use serde_json::Value;
use sqlx::{FromRow, SqlitePool};
use std::collections::HashSet;

const DRAFT_FIELDS: [&str; 11] = [
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

#[derive(Debug, FromRow)]
struct DraftRow {
    server_instance_id: String,
    account_id: String,
    session_id: String,
    draft_id: String,
    draft_version: i64,
    remote_json: String,
    local_fields_json: String,
    field_revisions_json: String,
    dirty_fields_json: String,
    client_seq: i64,
    remote_updated_at: Option<String>,
    local_updated_at: String,
}

#[derive(Debug, FromRow)]
struct OfflineRow {
    mutation_id: String,
    server_instance_id: String,
    account_id: String,
    session_id: String,
    draft_id: String,
    expected_draft_version: i64,
    provisional_ordinal: i64,
    record_json: String,
    state: String,
    resolution: Option<String>,
    last_error_code: Option<String>,
    created_at: String,
    updated_at: String,
}

fn require_text(value: &str, code: &str) -> anyhow::Result<()> {
    if value.trim().is_empty() {
        anyhow::bail!(code.to_string());
    }
    Ok(())
}

fn validate_identity(identity: &LiveDraftIdentity) -> anyhow::Result<()> {
    require_text(
        &identity.server_instance_id,
        "LIVE_DRAFT_SERVER_ID_REQUIRED",
    )?;
    require_text(&identity.account_id, "LIVE_DRAFT_ACCOUNT_ID_REQUIRED")?;
    require_text(&identity.session_id, "LIVE_DRAFT_SESSION_ID_REQUIRED")
}

fn validate_field_object(value: &Value, code: &str) -> anyhow::Result<()> {
    let object = value
        .as_object()
        .ok_or_else(|| anyhow::anyhow!(code.to_string()))?;
    if object
        .keys()
        .any(|key| !DRAFT_FIELDS.contains(&key.as_str()))
    {
        anyhow::bail!(code.to_string());
    }
    if object
        .values()
        .any(|child| !child.is_null() && !child.is_string())
    {
        anyhow::bail!(code.to_string());
    }
    Ok(())
}

fn validate_revisions(value: &Value) -> anyhow::Result<()> {
    let object = value
        .as_object()
        .ok_or_else(|| anyhow::anyhow!("LIVE_DRAFT_REVISIONS_INVALID"))?;
    if object
        .keys()
        .any(|key| !DRAFT_FIELDS.contains(&key.as_str()))
        || object
            .values()
            .any(|revision| revision.as_i64().is_none_or(|number| number < 0))
    {
        anyhow::bail!("LIVE_DRAFT_REVISIONS_INVALID");
    }
    Ok(())
}

fn validate_dirty_fields(fields: &[String]) -> anyhow::Result<()> {
    let mut unique = HashSet::new();
    if fields
        .iter()
        .any(|field| !DRAFT_FIELDS.contains(&field.as_str()) || !unique.insert(field.as_str()))
    {
        anyhow::bail!("LIVE_DRAFT_DIRTY_FIELDS_INVALID");
    }
    Ok(())
}

impl DraftRow {
    fn into_model(self) -> anyhow::Result<LocalLiveDraftCache> {
        Ok(LocalLiveDraftCache {
            identity: LiveDraftIdentity {
                server_instance_id: self.server_instance_id,
                account_id: self.account_id,
                session_id: self.session_id,
            },
            draft_id: self.draft_id,
            draft_version: self.draft_version,
            remote: serde_json::from_str(&self.remote_json)?,
            local_fields: serde_json::from_str(&self.local_fields_json)?,
            field_revisions: serde_json::from_str(&self.field_revisions_json)?,
            dirty_fields: serde_json::from_str(&self.dirty_fields_json)?,
            client_seq: self.client_seq,
            remote_updated_at: self.remote_updated_at,
            local_updated_at: self.local_updated_at,
        })
    }
}

impl OfflineRow {
    fn into_model(self) -> anyhow::Result<LocalOfflineRecord> {
        Ok(LocalOfflineRecord {
            identity: LiveDraftIdentity {
                server_instance_id: self.server_instance_id,
                account_id: self.account_id,
                session_id: self.session_id,
            },
            mutation_id: self.mutation_id,
            draft_id: self.draft_id,
            expected_draft_version: self.expected_draft_version,
            provisional_ordinal: self.provisional_ordinal,
            record: serde_json::from_str(&self.record_json)?,
            state: self.state,
            resolution: self.resolution,
            last_error_code: self.last_error_code,
            created_at: self.created_at,
            updated_at: self.updated_at,
        })
    }
}

pub async fn save_cache(
    pool: &SqlitePool,
    request: SaveLiveDraftCacheRequest,
) -> anyhow::Result<LocalLiveDraftCache> {
    validate_identity(&request.identity)?;
    require_text(&request.draft_id, "LIVE_DRAFT_ID_REQUIRED")?;
    if request.draft_version < 1 || request.client_seq < 0 {
        anyhow::bail!("LIVE_DRAFT_VERSION_INVALID");
    }
    if !request.remote.is_object() {
        anyhow::bail!("LIVE_DRAFT_REMOTE_INVALID");
    }
    validate_field_object(&request.local_fields, "LIVE_DRAFT_FIELDS_INVALID")?;
    validate_revisions(&request.field_revisions)?;
    validate_dirty_fields(&request.dirty_fields)?;

    let now = chrono::Utc::now().to_rfc3339();
    let mut tx = pool.begin().await?;
    let binding: (i64,) = sqlx::query_as(
        "SELECT COUNT(*) FROM collaboration_bindings
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?",
    )
    .bind(&request.identity.server_instance_id)
    .bind(&request.identity.account_id)
    .bind(&request.identity.session_id)
    .fetch_one(&mut *tx)
    .await?;
    if binding.0 != 1 {
        anyhow::bail!("LIVE_DRAFT_BINDING_NOT_FOUND");
    }
    sqlx::query(
        "INSERT INTO collaboration_live_drafts (
            server_instance_id, account_id, session_id, draft_id, draft_version,
            remote_json, local_fields_json, field_revisions_json, dirty_fields_json,
            client_seq, remote_updated_at, local_updated_at
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(server_instance_id, account_id, session_id) DO UPDATE SET
            draft_id = excluded.draft_id,
            draft_version = excluded.draft_version,
            remote_json = excluded.remote_json,
            local_fields_json = excluded.local_fields_json,
            field_revisions_json = excluded.field_revisions_json,
            dirty_fields_json = excluded.dirty_fields_json,
            client_seq = excluded.client_seq,
            remote_updated_at = excluded.remote_updated_at,
            local_updated_at = excluded.local_updated_at",
    )
    .bind(&request.identity.server_instance_id)
    .bind(&request.identity.account_id)
    .bind(&request.identity.session_id)
    .bind(&request.draft_id)
    .bind(request.draft_version)
    .bind(serde_json::to_string(&request.remote)?)
    .bind(serde_json::to_string(&request.local_fields)?)
    .bind(serde_json::to_string(&request.field_revisions)?)
    .bind(serde_json::to_string(&request.dirty_fields)?)
    .bind(request.client_seq)
    .bind(&request.remote_updated_at)
    .bind(&now)
    .execute(&mut *tx)
    .await?;
    let row = read_cache_row(&mut tx, &request.identity).await?;
    tx.commit().await?;
    row.ok_or_else(|| anyhow::anyhow!("LIVE_DRAFT_CACHE_NOT_FOUND"))?
        .into_model()
}

async fn read_cache_row(
    executor: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    identity: &LiveDraftIdentity,
) -> anyhow::Result<Option<DraftRow>> {
    Ok(sqlx::query_as::<_, DraftRow>(
        "SELECT * FROM collaboration_live_drafts
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?",
    )
    .bind(&identity.server_instance_id)
    .bind(&identity.account_id)
    .bind(&identity.session_id)
    .fetch_optional(&mut **executor)
    .await?)
}

pub async fn get_cache(
    pool: &SqlitePool,
    identity: LiveDraftIdentity,
) -> anyhow::Result<Option<LocalLiveDraftCache>> {
    validate_identity(&identity)?;
    let row = sqlx::query_as::<_, DraftRow>(
        "SELECT * FROM collaboration_live_drafts
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?",
    )
    .bind(&identity.server_instance_id)
    .bind(&identity.account_id)
    .bind(&identity.session_id)
    .fetch_optional(pool)
    .await?;
    row.map(DraftRow::into_model).transpose()
}

pub async fn clear_cache(pool: &SqlitePool, identity: LiveDraftIdentity) -> anyhow::Result<()> {
    validate_identity(&identity)?;
    sqlx::query(
        "DELETE FROM collaboration_live_drafts
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?",
    )
    .bind(identity.server_instance_id)
    .bind(identity.account_id)
    .bind(identity.session_id)
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn queue_offline_record(
    pool: &SqlitePool,
    request: QueueOfflineRecordRequest,
) -> anyhow::Result<LocalOfflineRecord> {
    validate_identity(&request.identity)?;
    require_text(&request.mutation_id, "OFFLINE_RECORD_MUTATION_ID_REQUIRED")?;
    require_text(&request.draft_id, "OFFLINE_RECORD_DRAFT_ID_REQUIRED")?;
    if request.expected_draft_version < 1 || request.provisional_ordinal < 1 {
        anyhow::bail!("OFFLINE_RECORD_VERSION_INVALID");
    }
    if !request.record.is_object() {
        anyhow::bail!("OFFLINE_RECORD_VALUE_INVALID");
    }
    let now = chrono::Utc::now().to_rfc3339();
    sqlx::query(
        "INSERT INTO collaboration_offline_records (
            mutation_id, server_instance_id, account_id, session_id,
            draft_id, expected_draft_version, provisional_ordinal, record_json,
            state, resolution, last_error_code, created_at, updated_at
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'pending', NULL, NULL, ?, ?)",
    )
    .bind(&request.mutation_id)
    .bind(&request.identity.server_instance_id)
    .bind(&request.identity.account_id)
    .bind(&request.identity.session_id)
    .bind(&request.draft_id)
    .bind(request.expected_draft_version)
    .bind(request.provisional_ordinal)
    .bind(serde_json::to_string(&request.record)?)
    .bind(&now)
    .bind(&now)
    .execute(pool)
    .await?;
    get_offline_record(pool, &request.mutation_id).await
}

async fn get_offline_record(
    pool: &SqlitePool,
    mutation_id: &str,
) -> anyhow::Result<LocalOfflineRecord> {
    let row = sqlx::query_as::<_, OfflineRow>(
        "SELECT * FROM collaboration_offline_records WHERE mutation_id = ?",
    )
    .bind(mutation_id)
    .fetch_optional(pool)
    .await?
    .ok_or_else(|| anyhow::anyhow!("OFFLINE_RECORD_NOT_FOUND"))?;
    row.into_model()
}

pub async fn list_offline_records(
    pool: &SqlitePool,
    identity: LiveDraftIdentity,
) -> anyhow::Result<Vec<LocalOfflineRecord>> {
    validate_identity(&identity)?;
    let rows = sqlx::query_as::<_, OfflineRow>(
        "SELECT * FROM collaboration_offline_records
         WHERE server_instance_id = ? AND account_id = ? AND session_id = ?
           AND state NOT IN ('resolved', 'discarded')
         ORDER BY created_at, mutation_id",
    )
    .bind(identity.server_instance_id)
    .bind(identity.account_id)
    .bind(identity.session_id)
    .fetch_all(pool)
    .await?;
    rows.into_iter().map(OfflineRow::into_model).collect()
}

pub async fn update_offline_record(
    pool: &SqlitePool,
    request: UpdateOfflineRecordRequest,
) -> anyhow::Result<LocalOfflineRecord> {
    require_text(&request.mutation_id, "OFFLINE_RECORD_MUTATION_ID_REQUIRED")?;
    let valid_state = matches!(
        request.state.as_str(),
        "pending" | "submitting" | "reviewing" | "resolved" | "discarded"
    );
    let valid_resolution = request.resolution.as_deref().is_none_or(|resolution| {
        matches!(
            resolution,
            "discard" | "submitAsDuplicate" | "copyToCurrentDraft"
        )
    });
    if !valid_state || !valid_resolution {
        anyhow::bail!("OFFLINE_RECORD_STATE_INVALID");
    }
    if matches!(request.state.as_str(), "resolved" | "discarded") && request.resolution.is_none() {
        anyhow::bail!("OFFLINE_RECORD_RESOLUTION_REQUIRED");
    }
    let now = chrono::Utc::now().to_rfc3339();
    let updated = sqlx::query(
        "UPDATE collaboration_offline_records
         SET state = ?, resolution = ?, last_error_code = ?, updated_at = ?
         WHERE mutation_id = ?",
    )
    .bind(&request.state)
    .bind(&request.resolution)
    .bind(&request.last_error_code)
    .bind(&now)
    .bind(&request.mutation_id)
    .execute(pool)
    .await?;
    if updated.rows_affected() != 1 {
        anyhow::bail!("OFFLINE_RECORD_NOT_FOUND");
    }
    get_offline_record(pool, &request.mutation_id).await
}
