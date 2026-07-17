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

/// Lightweight session metadata used by lifecycle/history surfaces.
///
/// Keeping the collaboration marker beside the Session avoids an N+1 binding
/// lookup when rendering history and, more importantly, lets callers decide
/// whether a closed row can be reopened locally before offering the action.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionSummary {
    pub session: Session,
    pub has_collaboration_binding: bool,
}

impl Session {
    pub fn new(title: String) -> Self {
        use rand::Rng;
        let now = chrono::Utc::now();
        let random: u64 = rand::thread_rng().gen();
        let hash = Sha256::digest(format!(
            "{}{}",
            now.timestamp_nanos_opt().unwrap_or(0),
            random
        ));
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
