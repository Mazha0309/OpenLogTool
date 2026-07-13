use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CallsignQthRecord {
    pub id: Option<i64>,
    pub sync_id: String,
    pub callsign: String,
    pub qth: String,
    pub recorded_at: String,
    pub created_at: String,
    pub updated_at: String,
    pub deleted_at: Option<String>,
    pub source_device_id: Option<String>,
}

impl CallsignQthRecord {
    pub fn new(callsign: String, qth: String) -> Self {
        let now = chrono::Utc::now().to_rfc3339();
        Self {
            id: None,
            sync_id: format!("callsign-qth-{}", uuid::Uuid::new_v4()),
            callsign: callsign.to_uppercase(),
            qth,
            recorded_at: now.clone(),
            created_at: now.clone(),
            updated_at: now,
            deleted_at: None,
            source_device_id: None,
        }
    }
}
