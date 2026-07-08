use crate::db;

pub async fn export_json(session_id: String) -> anyhow::Result<Vec<u8>> {
    let entries = db::logs::get_all_logs_in_session(&session_id).await?;
    let json = serde_json::to_string_pretty(&entries)?;
    Ok(json.into_bytes())
}
