use crate::get_db;
use crate::models::callsign_qth_record::CallsignQthRecord;

pub async fn add_record(callsign: &str, qth: &str) -> anyhow::Result<()> {
    if callsign.is_empty() || qth.is_empty() {
        return Ok(());
    }
    let pool = get_db()?;
    let record = CallsignQthRecord::new(callsign.to_string(), qth.to_string());
    sqlx::query(
        "INSERT OR IGNORE INTO callsign_qth_history
         (sync_id, callsign, qth, recorded_at, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?)",
    )
    .bind(&record.sync_id)
    .bind(&record.callsign)
    .bind(&record.qth)
    .bind(&record.recorded_at)
    .bind(&record.created_at)
    .bind(&record.updated_at)
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn get_history(callsign: &str, limit: i64) -> anyhow::Result<Vec<CallsignQthRecord>> {
    if callsign.is_empty() {
        return Ok(Vec::new());
    }
    let pool = get_db()?;
    let rows = sqlx::query_as::<_, CallsignQthRecordRow>(
        "SELECT * FROM callsign_qth_history
         WHERE callsign = ? AND deleted_at IS NULL
         ORDER BY recorded_at DESC LIMIT ?",
    )
    .bind(callsign.to_uppercase())
    .bind(limit)
    .fetch_all(pool)
    .await?;
    Ok(rows.into_iter().map(|r| r.into_record()).collect())
}

pub async fn get_last_recorded_time(
    callsign: &str,
    qth: &str,
) -> anyhow::Result<Option<String>> {
    if callsign.is_empty() || qth.is_empty() {
        return Ok(None);
    }
    let pool = get_db()?;
    let row: Option<(String,)> = sqlx::query_as(
        "SELECT recorded_at FROM callsign_qth_history
         WHERE callsign = ? AND qth = ? AND deleted_at IS NULL
         ORDER BY recorded_at DESC LIMIT 1",
    )
    .bind(callsign.to_uppercase())
    .bind(qth)
    .fetch_optional(pool)
    .await?;
    Ok(row.map(|r| r.0))
}

pub async fn clear_history() -> anyhow::Result<()> {
    let pool = get_db()?;
    let now = chrono::Utc::now().to_rfc3339();
    sqlx::query(
        "UPDATE callsign_qth_history SET deleted_at = ?, updated_at = ? WHERE deleted_at IS NULL",
    )
    .bind(&now)
    .bind(&now)
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn get_history_changed_since(since: &str) -> anyhow::Result<Vec<CallsignQthRecord>> {
    let pool = get_db()?;
    let rows = sqlx::query_as::<_, CallsignQthRecordRow>(
        "SELECT * FROM callsign_qth_history
         WHERE updated_at > ? OR deleted_at > ?",
    )
    .bind(since)
    .bind(since)
    .fetch_all(pool)
    .await?;
    Ok(rows.into_iter().map(|r| r.into_record()).collect())
}

#[derive(sqlx::FromRow)]
struct CallsignQthRecordRow {
    id: Option<i64>,
    sync_id: String,
    callsign: String,
    qth: String,
    recorded_at: String,
    created_at: String,
    updated_at: String,
    deleted_at: Option<String>,
    source_device_id: Option<String>,
}

impl CallsignQthRecordRow {
    fn into_record(self) -> CallsignQthRecord {
        CallsignQthRecord {
            id: self.id,
            sync_id: self.sync_id,
            callsign: self.callsign,
            qth: self.qth,
            recorded_at: self.recorded_at,
            created_at: self.created_at,
            updated_at: self.updated_at,
            deleted_at: self.deleted_at,
            source_device_id: self.source_device_id,
        }
    }
}
