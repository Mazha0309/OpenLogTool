use crate::db;
use crate::models::callsign_qth_record::CallsignQthRecord;

pub async fn add_callsign_qth_record(callsign: String, qth: String) -> anyhow::Result<()> {
    db::callsign_qth::add_record(&callsign, &qth).await
}

pub async fn get_callsign_qth_history(
    callsign: String,
    limit: Option<i64>,
) -> anyhow::Result<Vec<CallsignQthRecord>> {
    db::callsign_qth::get_history(&callsign, limit.unwrap_or(3)).await
}

pub async fn get_last_recorded_time(
    callsign: String,
    qth: String,
) -> anyhow::Result<Option<String>> {
    db::callsign_qth::get_last_recorded_time(&callsign, &qth).await
}

pub async fn clear_callsign_qth_history() -> anyhow::Result<()> {
    db::callsign_qth::clear_history().await
}
