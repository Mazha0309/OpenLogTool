use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LogEntry {
    pub id: Option<i64>,
    pub sync_id: String,
    pub session_id: String,
    pub time: String,
    pub controller: String,
    pub callsign: String,
    pub rst_sent: Option<String>,
    pub rst_rcvd: Option<String>,
    pub qth: Option<String>,
    pub device: Option<String>,
    pub power: Option<String>,
    pub antenna: Option<String>,
    pub height: Option<String>,
    pub remarks: Option<String>,
    pub created_at: String,
    pub updated_at: String,
    pub deleted_at: Option<String>,
    pub source_device_id: Option<String>,
}

impl LogEntry {
    pub fn new(session_id: String, controller: String, callsign: String) -> Self {
        let now = chrono::Utc::now().to_rfc3339();
        Self {
            id: None,
            sync_id: format!("log-{}", uuid::Uuid::new_v4()),
            session_id,
            time: now.clone(),
            controller: controller.to_uppercase(),
            callsign: callsign.to_uppercase(),
            rst_sent: None,
            rst_rcvd: None,
            qth: None,
            device: None,
            power: None,
            antenna: None,
            height: None,
            remarks: None,
            created_at: now.clone(),
            updated_at: now,
            deleted_at: None,
            source_device_id: None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LogStats {
    pub total: i64,
    pub today: i64,
    pub last_7_days: i64,
}
