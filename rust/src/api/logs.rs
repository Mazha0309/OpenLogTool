use crate::db;
use crate::models::log_entry::{LogEntry, LogStats};

pub async fn add_log(
    session_id: String,
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
) -> anyhow::Result<LogEntry> {
    let mut entry = LogEntry::new(session_id, controller, callsign);
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

pub async fn delete_log(sync_id: String) -> anyhow::Result<()> {
    db::logs::soft_delete_log(&sync_id).await
}

pub async fn undo_last_log(session_id: String) -> anyhow::Result<()> {
    db::logs::undo_last_log(&session_id).await
}

pub async fn restore_log(sync_id: String) -> anyhow::Result<LogEntry> {
    db::logs::restore_log(&sync_id).await
}
