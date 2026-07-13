use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LiveDraftIdentity {
    pub server_instance_id: String,
    pub account_id: String,
    pub session_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SaveLiveDraftCacheRequest {
    #[serde(flatten)]
    pub identity: LiveDraftIdentity,
    pub draft_id: String,
    pub draft_version: i64,
    pub remote: Value,
    pub local_fields: Value,
    pub field_revisions: Value,
    #[serde(default)]
    pub dirty_fields: Vec<String>,
    pub client_seq: i64,
    pub remote_updated_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LocalLiveDraftCache {
    #[serde(flatten)]
    pub identity: LiveDraftIdentity,
    pub draft_id: String,
    pub draft_version: i64,
    pub remote: Value,
    pub local_fields: Value,
    pub field_revisions: Value,
    pub dirty_fields: Vec<String>,
    pub client_seq: i64,
    pub remote_updated_at: Option<String>,
    pub local_updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct QueueOfflineRecordRequest {
    #[serde(flatten)]
    pub identity: LiveDraftIdentity,
    pub mutation_id: String,
    pub draft_id: String,
    pub expected_draft_version: i64,
    pub provisional_ordinal: i64,
    pub record: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LocalOfflineRecord {
    #[serde(flatten)]
    pub identity: LiveDraftIdentity,
    pub mutation_id: String,
    pub draft_id: String,
    pub expected_draft_version: i64,
    pub provisional_ordinal: i64,
    pub record: Value,
    pub state: String,
    pub resolution: Option<String>,
    pub last_error_code: Option<String>,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdateOfflineRecordRequest {
    pub mutation_id: String,
    pub state: String,
    pub resolution: Option<String>,
    pub last_error_code: Option<String>,
}
