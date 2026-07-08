use crate::get_db;
use crate::models::log_entry::{LogEntry, LogStats};

pub async fn insert_log(entry: &LogEntry) -> anyhow::Result<LogEntry> {
    let pool = get_db()?;
    sqlx::query(
        "INSERT INTO logs (sync_id, session_id, time, controller, callsign,
         rst_sent, rst_rcvd, qth, device, power, antenna, height,
         created_at, updated_at, source_device_id)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
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
    .bind(&entry.created_at)
    .bind(&entry.updated_at)
    .bind(&entry.source_device_id)
    .execute(pool)
    .await?;
    get_log_by_sync_id(&entry.sync_id)
        .await?
        .ok_or_else(|| anyhow::anyhow!("Failed to read back log"))
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
    let row = sqlx::query_as::<_, LogEntryRow>(
        "SELECT * FROM logs WHERE sync_id = ?",
    )
    .bind(sync_id)
    .fetch_optional(pool)
    .await?;
    Ok(row.map(|r| r.into_entry()))
}

pub async fn get_log_stats(session_id: &str) -> anyhow::Result<LogStats> {
    let pool = get_db()?;
    let total: (i64,) = sqlx::query_as(
        "SELECT COUNT(*) FROM logs WHERE session_id = ? AND deleted_at IS NULL",
    )
    .bind(session_id)
    .fetch_one(pool)
    .await?;

    let today_start = chrono::Utc::now().format("%Y-%m-%d").to_string();
    let today: (i64,) = sqlx::query_as(
        "SELECT COUNT(*) FROM logs WHERE session_id = ? AND deleted_at IS NULL AND time >= ?",
    )
    .bind(session_id)
    .bind(&today_start)
    .fetch_one(pool)
    .await?;

    let week_ago = (chrono::Utc::now() - chrono::Duration::days(7)).to_rfc3339();
    let last_7: (i64,) = sqlx::query_as(
        "SELECT COUNT(*) FROM logs WHERE session_id = ? AND deleted_at IS NULL AND time >= ?",
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

pub async fn soft_delete_log(sync_id: &str) -> anyhow::Result<()> {
    let pool = get_db()?;
    let now = chrono::Utc::now().to_rfc3339();
    sqlx::query("UPDATE logs SET deleted_at = ?, updated_at = ? WHERE sync_id = ?")
        .bind(&now)
        .bind(&now)
        .bind(sync_id)
        .execute(pool)
        .await?;
    Ok(())
}

pub async fn get_recent_by_callsign(
    callsign: &str,
    limit: i64,
) -> anyhow::Result<Vec<LogEntry>> {
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

pub async fn undo_last_log(session_id: &str) -> anyhow::Result<()> {
    let pool = get_db()?;
    let row = sqlx::query_as::<_, LogEntryRow>(
        "SELECT * FROM logs WHERE session_id = ? AND deleted_at IS NULL
         ORDER BY id DESC LIMIT 1",
    )
    .bind(session_id)
    .fetch_optional(pool)
    .await?;
    if let Some(entry) = row {
        soft_delete_log(&entry.sync_id).await?;
    }
    Ok(())
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
            created_at: self.created_at,
            updated_at: self.updated_at,
            deleted_at: self.deleted_at,
            source_device_id: self.source_device_id,
        }
    }
}
