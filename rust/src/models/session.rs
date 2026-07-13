use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Session {
    pub session_id: String,
    pub title: String,
    pub status: String,
    pub share_code: Option<String>,
    pub created_at: String,
    pub updated_at: String,
    pub closed_at: Option<String>,
    pub deleted_at: Option<String>,
}

impl Session {
    pub fn new(title: String) -> Self {
        use rand::Rng;
        let now = chrono::Utc::now();
        let random: u64 = rand::thread_rng().gen();
        let hash = Sha256::digest(format!("{}{}", now.timestamp_nanos_opt().unwrap_or(0), random));
        let session_id = format!("{:x}", hash);
        let ts = now.to_rfc3339();
        let share_code = Some(format!("{:06X}", rand::thread_rng().gen_range(0..0xFFFFFF)));
        Self {
            session_id,
            title,
            status: "active".to_string(),
            share_code,
            created_at: ts.clone(),
            updated_at: ts,
            closed_at: None,
            deleted_at: None,
        }
    }
}
