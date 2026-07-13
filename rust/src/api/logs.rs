use crate::db;
use crate::models::log_entry::{LogEntry, LogStats};

pub async fn add_log(
    session_id: String,
    controller: String,
    callsign: String,
    time: String,
    rst_sent: Option<String>,
    rst_rcvd: Option<String>,
    qth: Option<String>,
    device: Option<String>,
    power: Option<String>,
    antenna: Option<String>,
    height: Option<String>,
    remarks: Option<String>,
) -> anyhow::Result<LogEntry> {
    let mut entry = LogEntry::new(session_id, controller, callsign);
    entry.time = canonical_log_time(&time)?;
    entry.rst_sent = rst_sent;
    entry.rst_rcvd = rst_rcvd;
    entry.qth = qth;
    entry.device = device;
    entry.power = power;
    entry.antenna = antenna;
    entry.height = height;
    entry.remarks = remarks;
    db::logs::insert_log(&entry).await
}

pub async fn get_logs(
    session_id: String,
    page: Option<i64>,
    page_size: Option<i64>,
    search: Option<String>,
) -> anyhow::Result<Vec<LogEntry>> {
    db::logs::get_logs(
        &session_id,
        page.unwrap_or(1),
        page_size.unwrap_or(50),
        search.as_deref(),
    )
    .await
}

pub async fn get_log_stats(session_id: String) -> anyhow::Result<LogStats> {
    db::logs::get_log_stats(&session_id).await
}

pub async fn get_recent_by_callsign(
    callsign: String,
    limit: Option<i64>,
) -> anyhow::Result<Vec<LogEntry>> {
    db::logs::get_recent_by_callsign(&callsign.to_uppercase(), limit.unwrap_or(3)).await
}

pub async fn update_log(
    sync_id: String,
    controller: String,
    callsign: String,
    time: String,
    rst_sent: Option<String>,
    rst_rcvd: Option<String>,
    qth: Option<String>,
    device: Option<String>,
    power: Option<String>,
    antenna: Option<String>,
    height: Option<String>,
    remarks: Option<String>,
) -> anyhow::Result<LogEntry> {
    let time = canonical_log_time(&time)?;
    db::logs::update_log(
        &sync_id,
        &controller,
        &callsign,
        &time,
        rst_sent.as_deref(),
        rst_rcvd.as_deref(),
        qth.as_deref(),
        device.as_deref(),
        power.as_deref(),
        antenna.as_deref(),
        height.as_deref(),
        remarks.as_deref(),
    )
    .await
}

fn canonical_log_time(value: &str) -> anyhow::Result<String> {
    let parsed = chrono::DateTime::parse_from_rfc3339(value.trim())
        .map_err(|_| anyhow::anyhow!("LOG_TIME_INVALID"))?;
    Ok(parsed
        .with_timezone(&chrono::Utc)
        .to_rfc3339_opts(chrono::SecondsFormat::Millis, true))
}

#[cfg(test)]
mod tests {
    use super::canonical_log_time;

    #[test]
    fn canonicalizes_log_time_to_utc() {
        assert_eq!(
            canonical_log_time("2026-07-13T16:49:00+08:00").unwrap(),
            "2026-07-13T08:49:00.000Z",
        );
    }

    #[test]
    fn rejects_a_wall_clock_without_an_offset() {
        assert!(canonical_log_time("16:49").is_err());
    }
}

pub async fn delete_log(sync_id: String) -> anyhow::Result<()> {
    db::logs::soft_delete_log(&sync_id).await
}

pub async fn undo_last_log(session_id: String) -> anyhow::Result<()> {
    db::logs::undo_last_log(&session_id).await
}

pub async fn restore_log(sync_id: String) -> anyhow::Result<LogEntry> {
    db::logs::restore_log(&sync_id).await
}
