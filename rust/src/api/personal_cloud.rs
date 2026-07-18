use crate::get_db;
use serde_json::{json, Value};

fn validate_hash(value: &str, field: &str) -> anyhow::Result<()> {
    if value.len() != 64
        || !value
            .bytes()
            .all(|byte| byte.is_ascii_hexdigit() && !byte.is_ascii_uppercase())
    {
        anyhow::bail!("PERSONAL_CLOUD_INVALID_{field}");
    }
    Ok(())
}

fn validate_dataset(dataset: &str) -> anyhow::Result<()> {
    if !matches!(dataset, "records" | "dictionaries") {
        anyhow::bail!("PERSONAL_CLOUD_INVALID_DATASET");
    }
    Ok(())
}

/// Returns device-local pairing state and the requested account baseline.
pub async fn load_personal_cloud_state(
    scope_hash: String,
    dataset: String,
) -> anyhow::Result<String> {
    validate_hash(&scope_hash, "SCOPE_HASH")?;
    validate_dataset(&dataset)?;
    let pool = get_db()?;
    // Pairing state and its baseline form one safety decision. Read both from
    // the same SQLite snapshot so a concurrent clear/import cannot expose a
    // stale "pairing not required" value alongside an already-deleted
    // baseline (which could otherwise trigger an unintended first sync).
    let mut tx = pool.begin().await?;
    let state = sqlx::query_as::<_, (Option<String>, Option<String>)>(
        "SELECT owner_scope_hash, pairing_required_reason
         FROM personal_cloud_state WHERE id = 1",
    )
    .fetch_one(&mut *tx)
    .await?;
    let baseline = sqlx::query_as::<_, (i64, String, String, String)>(
        "SELECT remote_revision, snapshot_json, checksum, updated_at
         FROM personal_cloud_baselines
         WHERE scope_hash = ? AND dataset = ?",
    )
    .bind(&scope_hash)
    .bind(&dataset)
    .fetch_optional(&mut *tx)
    .await?;
    let baseline = baseline
        .map(|row| -> anyhow::Result<Value> {
            Ok(json!({
                "remoteRevision": row.0,
                "snapshot": serde_json::from_str::<Value>(&row.1)?,
                "checksum": row.2,
                "updatedAt": row.3,
            }))
        })
        .transpose()?;
    tx.commit().await?;
    Ok(json!({
        "ownerScopeHash": state.0,
        "pairingRequiredReason": state.1,
        "baseline": baseline,
    })
    .to_string())
}

/// Atomically stores an accepted baseline. Snapshot JSON is local-only and is
/// deliberately excluded from normal database backup/export.
pub async fn save_personal_cloud_baseline(
    scope_hash: String,
    dataset: String,
    remote_revision: i64,
    snapshot_json: String,
    checksum: String,
    claim_owner: bool,
    clear_pairing_requirement: bool,
) -> anyhow::Result<()> {
    validate_hash(&scope_hash, "SCOPE_HASH")?;
    validate_hash(&checksum, "CHECKSUM")?;
    validate_dataset(&dataset)?;
    if remote_revision < 0 {
        anyhow::bail!("PERSONAL_CLOUD_INVALID_REVISION");
    }
    let snapshot: Value = serde_json::from_str(&snapshot_json)
        .map_err(|_| anyhow::anyhow!("PERSONAL_CLOUD_INVALID_BASELINE_JSON"))?;
    if !snapshot.is_object() {
        anyhow::bail!("PERSONAL_CLOUD_INVALID_BASELINE_JSON");
    }

    let pool = get_db()?;
    let mut tx = pool.begin().await?;
    let now = chrono::Utc::now().to_rfc3339();
    sqlx::query(
        "INSERT INTO personal_cloud_baselines (
            scope_hash, dataset, remote_revision, snapshot_json, checksum, updated_at
         ) VALUES (?, ?, ?, ?, ?, ?)
         ON CONFLICT(scope_hash, dataset) DO UPDATE SET
            remote_revision = excluded.remote_revision,
            snapshot_json = excluded.snapshot_json,
            checksum = excluded.checksum,
            updated_at = excluded.updated_at",
    )
    .bind(&scope_hash)
    .bind(&dataset)
    .bind(remote_revision)
    .bind(serde_json::to_string(&snapshot)?)
    .bind(&checksum)
    .bind(&now)
    .execute(&mut *tx)
    .await?;

    if claim_owner || clear_pairing_requirement {
        sqlx::query(
            "UPDATE personal_cloud_state SET
                owner_scope_hash = CASE WHEN ? THEN ? ELSE owner_scope_hash END,
                pairing_required_reason = CASE WHEN ? THEN NULL ELSE pairing_required_reason END,
                updated_at = ?
             WHERE id = 1",
        )
        .bind(claim_owner)
        .bind(&scope_hash)
        .bind(clear_pairing_requirement)
        .bind(&now)
        .execute(&mut *tx)
        .await?;
    }
    tx.commit().await?;
    Ok(())
}

pub async fn require_personal_cloud_pairing(reason: String) -> anyhow::Result<()> {
    if !matches!(
        reason.as_str(),
        "database_replaced" | "local_cleared" | "account_changed"
    ) {
        anyhow::bail!("PERSONAL_CLOUD_INVALID_PAIRING_REASON");
    }
    let pool = get_db()?;
    let mut tx = pool.begin().await?;
    sqlx::query("DELETE FROM personal_cloud_baselines")
        .execute(&mut *tx)
        .await?;
    sqlx::query(
        "UPDATE personal_cloud_state
         SET pairing_required_reason = ?, updated_at = ? WHERE id = 1",
    )
    .bind(reason)
    .bind(chrono::Utc::now().to_rfc3339())
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(())
}
