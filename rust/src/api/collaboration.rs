use crate::db;
use crate::get_db;
use crate::models::collaboration::{
    ApplyEventRequest, CollaborationRole, InstallSnapshotRequest, MutationConflictRequest,
    MutationFailureRequest, ResolveConflictRequest,
};
use crate::models::live_draft::{
    LiveDraftIdentity, QueueOfflineRecordRequest, SaveLiveDraftCacheRequest,
    UpdateOfflineRecordRequest,
};

pub async fn get_or_create_device_id() -> anyhow::Result<String> {
    db::collaboration::get_or_create_device_id(get_db()?).await
}

pub async fn get_collaboration_binding(
    server_instance_id: String,
    account_id: String,
    session_id: String,
) -> anyhow::Result<Option<String>> {
    let binding =
        db::collaboration::get_binding(get_db()?, &server_instance_id, &account_id, &session_id)
            .await?;
    binding
        .map(|value| serde_json::to_string(&value))
        .transpose()
        .map_err(Into::into)
}

pub async fn get_session_collaboration_binding(
    session_id: String,
) -> anyhow::Result<Option<String>> {
    let binding = db::collaboration::get_binding_for_session(get_db()?, &session_id).await?;
    binding
        .map(|value| serde_json::to_string(&value))
        .transpose()
        .map_err(Into::into)
}

pub async fn get_publish_snapshot(session_id: String) -> anyhow::Result<String> {
    let snapshot = db::collaboration::get_publish_snapshot(get_db()?, &session_id).await?;
    Ok(serde_json::to_string(&snapshot)?)
}

pub async fn begin_publish_snapshot(
    server_instance_id: String,
    server_origin: String,
    account_id: String,
    session_id: String,
) -> anyhow::Result<String> {
    let snapshot = db::collaboration::begin_publish_snapshot(
        get_db()?,
        &server_instance_id,
        &server_origin,
        &account_id,
        &session_id,
    )
    .await?;
    Ok(serde_json::to_string(&snapshot)?)
}

pub async fn abort_publish(
    server_instance_id: String,
    account_id: String,
    session_id: String,
) -> anyhow::Result<()> {
    db::collaboration::abort_publish(get_db()?, &server_instance_id, &account_id, &session_id).await
}

pub async fn install_collaboration_snapshot(request_json: String) -> anyhow::Result<String> {
    let request: InstallSnapshotRequest = serde_json::from_str(&request_json)
        .map_err(|error| anyhow::anyhow!("SNAPSHOT_JSON_INVALID: {error}"))?;
    let binding = db::collaboration::install_snapshot(get_db()?, request).await?;
    Ok(serde_json::to_string(&binding)?)
}

pub async fn mark_collaboration_revoked(
    server_instance_id: String,
    account_id: String,
    session_id: String,
) -> anyhow::Result<()> {
    db::collaboration::mark_revoked(get_db()?, &server_instance_id, &account_id, &session_id).await
}

pub async fn update_collaboration_membership(
    server_instance_id: String,
    account_id: String,
    session_id: String,
    membership_id: String,
    membership_version: i64,
    role: String,
) -> anyhow::Result<String> {
    let role = CollaborationRole::parse(&role)?;
    let binding = db::collaboration::update_membership(
        get_db()?,
        &server_instance_id,
        &account_id,
        &session_id,
        &membership_id,
        membership_version,
        role,
    )
    .await?;
    Ok(serde_json::to_string(&binding)?)
}

pub async fn list_pending_collaboration_mutations(
    server_instance_id: String,
    account_id: String,
    session_id: String,
    limit: Option<i64>,
) -> anyhow::Result<String> {
    let batch = db::collaboration::list_pending_mutations(
        get_db()?,
        &server_instance_id,
        &account_id,
        &session_id,
        limit.unwrap_or(100),
    )
    .await?;
    Ok(serde_json::to_string(&batch)?)
}

pub async fn mark_collaboration_mutations_sending(
    server_instance_id: String,
    account_id: String,
    session_id: String,
    mutation_ids_json: String,
) -> anyhow::Result<()> {
    let mutation_ids: Vec<String> = serde_json::from_str(&mutation_ids_json)
        .map_err(|error| anyhow::anyhow!("MUTATION_IDS_JSON_INVALID: {error}"))?;
    db::collaboration::mark_mutations_sending(
        get_db()?,
        &server_instance_id,
        &account_id,
        &session_id,
        &mutation_ids,
    )
    .await
}

pub async fn mark_collaboration_mutation_accepted(
    server_instance_id: String,
    account_id: String,
    session_id: String,
    mutation_id: String,
    accepted_event_seq: i64,
) -> anyhow::Result<()> {
    db::collaboration::mark_mutation_accepted(
        get_db()?,
        &server_instance_id,
        &account_id,
        &session_id,
        &mutation_id,
        accepted_event_seq,
    )
    .await
}

pub async fn mark_collaboration_mutation_retry(request_json: String) -> anyhow::Result<()> {
    let request: MutationFailureRequest = serde_json::from_str(&request_json)
        .map_err(|error| anyhow::anyhow!("MUTATION_RETRY_JSON_INVALID: {error}"))?;
    db::collaboration::mark_mutation_retry(get_db()?, request).await
}

pub async fn mark_collaboration_mutation_rejected(
    server_instance_id: String,
    account_id: String,
    session_id: String,
    mutation_id: String,
    error_code: String,
    error_message: String,
    details_json: Option<String>,
) -> anyhow::Result<()> {
    db::collaboration::mark_mutation_rejected(
        get_db()?,
        &server_instance_id,
        &account_id,
        &session_id,
        &mutation_id,
        &error_code,
        &error_message,
        details_json.as_deref(),
    )
    .await
}

pub async fn record_collaboration_mutation_conflict(
    request_json: String,
) -> anyhow::Result<String> {
    let request: MutationConflictRequest = serde_json::from_str(&request_json)
        .map_err(|error| anyhow::anyhow!("MUTATION_CONFLICT_JSON_INVALID: {error}"))?;
    let conflict = db::collaboration::record_mutation_conflict(get_db()?, request).await?;
    Ok(serde_json::to_string(&conflict)?)
}

pub async fn list_open_collaboration_conflicts(
    server_instance_id: String,
    account_id: String,
    session_id: String,
) -> anyhow::Result<String> {
    let conflicts = db::collaboration::list_open_conflicts(
        get_db()?,
        &server_instance_id,
        &account_id,
        &session_id,
    )
    .await?;
    Ok(serde_json::to_string(&conflicts)?)
}

pub async fn resolve_collaboration_conflict(request_json: String) -> anyhow::Result<String> {
    let request: ResolveConflictRequest = serde_json::from_str(&request_json)
        .map_err(|error| anyhow::anyhow!("CONFLICT_RESOLUTION_JSON_INVALID: {error}"))?;
    let result = db::collaboration::resolve_conflict(get_db()?, request).await?;
    Ok(serde_json::to_string(&result)?)
}

pub async fn apply_collaboration_event(request_json: String) -> anyhow::Result<String> {
    let request: ApplyEventRequest = serde_json::from_str(&request_json)
        .map_err(|error| anyhow::anyhow!("EVENT_JSON_INVALID: {error}"))?;
    let result = db::collaboration::apply_event(get_db()?, request).await?;
    Ok(serde_json::to_string(&result)?)
}

pub async fn set_collaboration_head_seq(
    server_instance_id: String,
    account_id: String,
    session_id: String,
    head_seq: i64,
) -> anyhow::Result<()> {
    db::collaboration::set_head_seq(
        get_db()?,
        &server_instance_id,
        &account_id,
        &session_id,
        head_seq,
    )
    .await
}

pub async fn get_collaboration_sync_status(
    server_instance_id: String,
    account_id: String,
    session_id: String,
) -> anyhow::Result<String> {
    let status = db::collaboration::get_sync_status(
        get_db()?,
        &server_instance_id,
        &account_id,
        &session_id,
    )
    .await?;
    Ok(serde_json::to_string(&status)?)
}

pub async fn save_collaboration_live_draft_cache(request_json: String) -> anyhow::Result<String> {
    let request: SaveLiveDraftCacheRequest = serde_json::from_str(&request_json)
        .map_err(|error| anyhow::anyhow!("LIVE_DRAFT_CACHE_JSON_INVALID: {error}"))?;
    let draft = db::live_draft::save_cache(get_db()?, request).await?;
    Ok(serde_json::to_string(&draft)?)
}

pub async fn get_collaboration_live_draft_cache(
    server_instance_id: String,
    account_id: String,
    session_id: String,
) -> anyhow::Result<Option<String>> {
    let draft = db::live_draft::get_cache(
        get_db()?,
        LiveDraftIdentity {
            server_instance_id,
            account_id,
            session_id,
        },
    )
    .await?;
    draft
        .map(|value| serde_json::to_string(&value))
        .transpose()
        .map_err(Into::into)
}

pub async fn clear_collaboration_live_draft_cache(
    server_instance_id: String,
    account_id: String,
    session_id: String,
) -> anyhow::Result<()> {
    db::live_draft::clear_cache(
        get_db()?,
        LiveDraftIdentity {
            server_instance_id,
            account_id,
            session_id,
        },
    )
    .await
}

pub async fn queue_collaboration_offline_record(request_json: String) -> anyhow::Result<String> {
    let request: QueueOfflineRecordRequest = serde_json::from_str(&request_json)
        .map_err(|error| anyhow::anyhow!("OFFLINE_RECORD_JSON_INVALID: {error}"))?;
    let record = db::live_draft::queue_offline_record(get_db()?, request).await?;
    Ok(serde_json::to_string(&record)?)
}

pub async fn list_collaboration_offline_records(
    server_instance_id: String,
    account_id: String,
    session_id: String,
) -> anyhow::Result<String> {
    let records = db::live_draft::list_offline_records(
        get_db()?,
        LiveDraftIdentity {
            server_instance_id,
            account_id,
            session_id,
        },
    )
    .await?;
    Ok(serde_json::to_string(&records)?)
}

pub async fn update_collaboration_offline_record(request_json: String) -> anyhow::Result<String> {
    let request: UpdateOfflineRecordRequest = serde_json::from_str(&request_json)
        .map_err(|error| anyhow::anyhow!("OFFLINE_RECORD_UPDATE_JSON_INVALID: {error}"))?;
    let record = db::live_draft::update_offline_record(get_db()?, request).await?;
    Ok(serde_json::to_string(&record)?)
}
