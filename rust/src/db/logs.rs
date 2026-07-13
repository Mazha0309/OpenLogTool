use crate::get_db;
use crate::models::log_entry::{LogEntry, LogStats};
use sqlx::{Sqlite, Transaction};

async fn get_log_by_sync_id_in_tx(
    tx: &mut Transaction<'_, Sqlite>,
    sync_id: &str,
) -> anyhow::Result<Option<LogEntry>> {
    let row = sqlx::query_as::<_, LogEntryRow>("SELECT * FROM logs WHERE sync_id = ?")
        .bind(sync_id)
        .fetch_optional(&mut **tx)
        .await?;
    Ok(row.map(LogEntryRow::into_entry))
}

async fn ensure_active_session_in_tx(
    tx: &mut Transaction<'_, Sqlite>,
    session_id: &str,
) -> anyhow::Result<()> {
    let session: Option<(String, Option<String>)> =
        sqlx::query_as("SELECT status, deleted_at FROM sessions WHERE session_id = ?")
            .bind(session_id)
            .fetch_optional(&mut **tx)
            .await?;
    let Some((status, deleted_at)) = session else {
        anyhow::bail!("SESSION_NOT_FOUND");
    };
    if deleted_at.is_some() {
        anyhow::bail!("SESSION_NOT_FOUND");
    }
    if status != "active" {
        anyhow::bail!("SESSION_CLOSED");
    }
    Ok(())
}

pub async fn insert_log(entry: &LogEntry) -> anyhow::Result<LogEntry> {
    let pool = get_db()?;
    let mut tx = pool.begin().await?;
    ensure_active_session_in_tx(&mut tx, &entry.session_id).await?;
    sqlx::query(
        "INSERT INTO logs (sync_id, session_id, time, controller, callsign,
         rst_sent, rst_rcvd, qth, device, power, antenna, height, remarks,
         created_at, updated_at, source_device_id)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
    )
    .bind(&entry.sync_id)
    .bind(&entry.session_id)
    .bind(&entry.time)
    .bind(&entry.controller)
    .bind(&entry.callsign)
    .bind(&entry.rst_sent)
    .bind(&entry.rst_rcvd)
    .bind(&entry.qth)
    .bind(&entry.device)
    .bind(&entry.power)
    .bind(&entry.antenna)
    .bind(&entry.height)
    .bind(&entry.remarks)
    .bind(&entry.created_at)
    .bind(&entry.updated_at)
    .bind(&entry.source_device_id)
    .execute(&mut *tx)
    .await?;
    let inserted = get_log_by_sync_id_in_tx(&mut tx, &entry.sync_id)
        .await?
        .ok_or_else(|| anyhow::anyhow!("Failed to read back log"))?;
    crate::db::collaboration::queue_log_create(&mut tx, &inserted).await?;
    tx.commit().await?;
    Ok(inserted)
}

pub async fn get_logs(
    session_id: &str,
    page: i64,
    page_size: i64,
    search: Option<&str>,
) -> anyhow::Result<Vec<LogEntry>> {
    let pool = get_db()?;
    let offset = (page - 1) * page_size;
    let rows = if let Some(q) = search {
        let pattern = format!("%{}%", q);
        sqlx::query_as::<_, LogEntryRow>(
            "SELECT * FROM logs WHERE session_id = ? AND deleted_at IS NULL
             AND (callsign LIKE ? OR controller LIKE ? OR qth LIKE ? OR device LIKE ?)
             ORDER BY time DESC LIMIT ? OFFSET ?",
        )
        .bind(session_id)
        .bind(&pattern)
        .bind(&pattern)
        .bind(&pattern)
        .bind(&pattern)
        .bind(page_size)
        .bind(offset)
        .fetch_all(pool)
        .await?
    } else {
        sqlx::query_as::<_, LogEntryRow>(
            "SELECT * FROM logs WHERE session_id = ? AND deleted_at IS NULL
             ORDER BY time DESC LIMIT ? OFFSET ?",
        )
        .bind(session_id)
        .bind(page_size)
        .bind(offset)
        .fetch_all(pool)
        .await?
    };
    Ok(rows.into_iter().map(|r| r.into_entry()).collect())
}

pub async fn get_log_by_sync_id(sync_id: &str) -> anyhow::Result<Option<LogEntry>> {
    let pool = get_db()?;
    let row = sqlx::query_as::<_, LogEntryRow>("SELECT * FROM logs WHERE sync_id = ?")
        .bind(sync_id)
        .fetch_optional(pool)
        .await?;
    Ok(row.map(|r| r.into_entry()))
}

pub async fn get_log_stats(session_id: &str) -> anyhow::Result<LogStats> {
    let pool = get_db()?;
    let total: (i64,) =
        sqlx::query_as("SELECT COUNT(*) FROM logs WHERE session_id = ? AND deleted_at IS NULL")
            .bind(session_id)
            .fetch_one(pool)
            .await?;

    // Stats are based on created_at (reliable RFC3339 timestamp) instead of the user-editable
    // time field which may only store HH:mm.
    let today_start = chrono::Utc::now().date_naive().to_string();
    let today: (i64,) = sqlx::query_as(
        "SELECT COUNT(*) FROM logs WHERE session_id = ? AND deleted_at IS NULL AND date(created_at) >= ?",
    )
    .bind(session_id)
    .bind(&today_start)
    .fetch_one(pool)
    .await?;

    let week_ago = (chrono::Utc::now() - chrono::Duration::days(7)).to_rfc3339();
    let last_7: (i64,) = sqlx::query_as(
        "SELECT COUNT(*) FROM logs WHERE session_id = ? AND deleted_at IS NULL AND created_at >= ?",
    )
    .bind(session_id)
    .bind(&week_ago)
    .fetch_one(pool)
    .await?;

    Ok(LogStats {
        total: total.0,
        today: today.0,
        last_7_days: last_7.0,
    })
}

pub async fn update_log(
    sync_id: &str,
    controller: &str,
    callsign: &str,
    time: &str,
    rst_sent: Option<&str>,
    rst_rcvd: Option<&str>,
    qth: Option<&str>,
    device: Option<&str>,
    power: Option<&str>,
    antenna: Option<&str>,
    height: Option<&str>,
    remarks: Option<&str>,
) -> anyhow::Result<LogEntry> {
    let pool = get_db()?;
    let mut tx = pool.begin().await?;
    let before = get_log_by_sync_id_in_tx(&mut tx, sync_id)
        .await?
        .filter(|entry| entry.deleted_at.is_none())
        .ok_or_else(|| anyhow::anyhow!("Log not found or already deleted"))?;
    ensure_active_session_in_tx(&mut tx, &before.session_id).await?;
    let now = chrono::Utc::now().to_rfc3339();
    let result = sqlx::query(
        "UPDATE logs SET
            controller = ?, callsign = ?, time = ?, rst_sent = ?, rst_rcvd = ?,
            qth = ?, device = ?, power = ?, antenna = ?, height = ?, remarks = ?, updated_at = ?
         WHERE sync_id = ? AND deleted_at IS NULL",
    )
    .bind(controller)
    .bind(callsign)
    .bind(time)
    .bind(rst_sent)
    .bind(rst_rcvd)
    .bind(qth)
    .bind(device)
    .bind(power)
    .bind(antenna)
    .bind(height)
    .bind(remarks)
    .bind(&now)
    .bind(sync_id)
    .execute(&mut *tx)
    .await?;
    if result.rows_affected() == 0 {
        return Err(anyhow::anyhow!("Log not found or already deleted"));
    }
    let updated = get_log_by_sync_id_in_tx(&mut tx, sync_id)
        .await?
        .ok_or_else(|| anyhow::anyhow!("Updated log not found"))?;
    crate::db::collaboration::queue_log_update(&mut tx, &before, &updated).await?;
    tx.commit().await?;
    Ok(updated)
}

pub async fn soft_delete_log(sync_id: &str) -> anyhow::Result<()> {
    let pool = get_db()?;
    let mut tx = pool.begin().await?;
    let Some(entry) = get_log_by_sync_id_in_tx(&mut tx, sync_id).await? else {
        tx.commit().await?;
        return Ok(());
    };
    if entry.deleted_at.is_some() {
        tx.commit().await?;
        return Ok(());
    }
    ensure_active_session_in_tx(&mut tx, &entry.session_id).await?;
    let remove_row = crate::db::collaboration::queue_log_delete(&mut tx, &entry).await?;
    if remove_row {
        sqlx::query("DELETE FROM logs WHERE sync_id = ?")
            .bind(sync_id)
            .execute(&mut *tx)
            .await?;
        tx.commit().await?;
        return Ok(());
    }
    let now = chrono::Utc::now().to_rfc3339();
    sqlx::query("UPDATE logs SET deleted_at = ?, updated_at = ? WHERE sync_id = ?")
        .bind(&now)
        .bind(&now)
        .bind(sync_id)
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;
    Ok(())
}

pub async fn get_recent_by_callsign(callsign: &str, limit: i64) -> anyhow::Result<Vec<LogEntry>> {
    let pool = get_db()?;
    let rows = sqlx::query_as::<_, LogEntryRow>(
        "SELECT * FROM logs WHERE callsign = ? AND deleted_at IS NULL
         ORDER BY time DESC LIMIT ?",
    )
    .bind(callsign)
    .bind(limit)
    .fetch_all(pool)
    .await?;
    Ok(rows.into_iter().map(|r| r.into_entry()).collect())
}

pub async fn get_all_logs_in_session(session_id: &str) -> anyhow::Result<Vec<LogEntry>> {
    let pool = get_db()?;
    let rows = sqlx::query_as::<_, LogEntryRow>(
        "SELECT * FROM logs WHERE session_id = ? AND deleted_at IS NULL ORDER BY time ASC",
    )
    .bind(session_id)
    .fetch_all(pool)
    .await?;
    Ok(rows.into_iter().map(|r| r.into_entry()).collect())
}

pub async fn undo_last_log(session_id: &str) -> anyhow::Result<()> {
    let pool = get_db()?;
    let mut tx = pool.begin().await?;
    ensure_active_session_in_tx(&mut tx, session_id).await?;
    let row = sqlx::query_as::<_, LogEntryRow>(
        "SELECT * FROM logs WHERE session_id = ? AND deleted_at IS NULL
         ORDER BY id DESC LIMIT 1",
    )
    .bind(session_id)
    .fetch_optional(&mut *tx)
    .await?;
    if let Some(entry) = row {
        let entry = entry.into_entry();
        let remove_row = crate::db::collaboration::queue_log_delete(&mut tx, &entry).await?;
        if remove_row {
            sqlx::query("DELETE FROM logs WHERE sync_id = ?")
                .bind(&entry.sync_id)
                .execute(&mut *tx)
                .await?;
            tx.commit().await?;
            return Ok(());
        }
        let now = chrono::Utc::now().to_rfc3339();
        sqlx::query("UPDATE logs SET deleted_at = ?, updated_at = ? WHERE sync_id = ?")
            .bind(&now)
            .bind(&now)
            .bind(&entry.sync_id)
            .execute(&mut *tx)
            .await?;
    }
    tx.commit().await?;
    Ok(())
}

pub async fn restore_log(sync_id: &str) -> anyhow::Result<LogEntry> {
    let pool = get_db()?;
    let mut tx = pool.begin().await?;
    let mut entry = get_log_by_sync_id_in_tx(&mut tx, sync_id)
        .await?
        .filter(|entry| entry.deleted_at.is_some())
        .ok_or_else(|| anyhow::anyhow!("Log not found or not deleted"))?;
    ensure_active_session_in_tx(&mut tx, &entry.session_id).await?;
    entry.deleted_at = None;
    entry.updated_at = chrono::Utc::now().to_rfc3339();
    crate::db::collaboration::queue_log_restore(&mut tx, &entry).await?;
    sqlx::query("UPDATE logs SET deleted_at = NULL, updated_at = ? WHERE sync_id = ?")
        .bind(&entry.updated_at)
        .bind(sync_id)
        .execute(&mut *tx)
        .await?;
    let restored = get_log_by_sync_id_in_tx(&mut tx, sync_id)
        .await?
        .ok_or_else(|| anyhow::anyhow!("Restored log not found"))?;
    tx.commit().await?;
    Ok(restored)
}

#[derive(sqlx::FromRow)]
struct LogEntryRow {
    id: Option<i64>,
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
    source_device_id: Option<String>,
}

impl LogEntryRow {
    fn into_entry(self) -> LogEntry {
        LogEntry {
            id: self.id,
            sync_id: self.sync_id,
            session_id: self.session_id,
            time: self.time,
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
            created_at: self.created_at,
            updated_at: self.updated_at,
            deleted_at: self.deleted_at,
            source_device_id: self.source_device_id,
        }
    }
}
