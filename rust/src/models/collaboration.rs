use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum CollaborationRole {
    Owner,
    Editor,
    Viewer,
}

impl CollaborationRole {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Owner => "owner",
            Self::Editor => "editor",
            Self::Viewer => "viewer",
        }
    }

    pub fn parse(value: &str) -> anyhow::Result<Self> {
        match value {
            "owner" => Ok(Self::Owner),
            "editor" => Ok(Self::Editor),
            "viewer" => Ok(Self::Viewer),
            _ => anyhow::bail!("INVALID_COLLABORATION_ROLE"),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum SnapshotInstallMode {
    Publish,
    Join,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteMembership {
    pub membership_id: String,
    pub session_id: String,
    pub user_id: String,
    pub role: CollaborationRole,
    pub version: i64,
    pub joined_at: String,
    pub updated_at: String,
    pub removed_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteSession {
    pub session_id: String,
    pub title: String,
    pub status: String,
    pub version: i64,
    pub role: CollaborationRole,
    pub high_watermark_seq: i64,
    pub created_at: String,
    pub updated_at: String,
    pub closed_at: Option<String>,
    pub deleted_at: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteLog {
    pub sync_id: String,
    pub session_id: String,
    pub version: i64,
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
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CollaborationSnapshot {
    pub protocol_version: i32,
    /// True when the snapshot contains both active logs and canonical log
    /// tombstones. Replica reinstall must never infer deletion from absence.
    pub includes_deleted_logs: bool,
    pub session: RemoteSession,
    pub high_watermark_seq: i64,
    pub logs: Vec<RemoteLog>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InstallSnapshotRequest {
    pub mode: SnapshotInstallMode,
    pub server_instance_id: String,
    pub server_origin: String,
    pub account_id: String,
    pub membership: RemoteMembership,
    pub snapshot: CollaborationSnapshot,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CollaborationBinding {
    pub server_instance_id: String,
    pub server_origin: String,
    pub account_id: String,
    pub session_id: String,
    pub membership_id: String,
    pub membership_version: i64,
    pub role: CollaborationRole,
    pub replica_state: String,
    pub last_applied_seq: i64,
    pub last_seen_head_seq: i64,
    pub joined_at: String,
    pub updated_at: String,
    pub revoked_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PublishSession {
    pub session_id: String,
    pub title: String,
    pub status: String,
    pub created_at: String,
    pub updated_at: String,
    pub closed_at: Option<String>,
    pub deleted_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PublishLog {
    pub sync_id: String,
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
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PublishSnapshot {
    /// True only when this exact begin call created the local publishing lease.
    /// A retry against an existing lease must never assume the remote was untouched.
    pub lease_created: bool,
    pub session: PublishSession,
    pub logs: Vec<PublishLog>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CanonicalEvent {
    pub protocol_version: i32,
    pub event_id: String,
    pub session_id: String,
    pub seq: i64,
    #[serde(rename = "type")]
    pub event_type: String,
    pub entity_type: String,
    pub entity_id: String,
    pub entity_version: i64,
    pub mutation_id: Option<String>,
    pub occurred_at: String,
    pub payload: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ApplyEventRequest {
    pub server_instance_id: String,
    pub account_id: String,
    pub event: CanonicalEvent,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ApplyEventResult {
    pub outcome: String,
    pub cursor: i64,
    pub expected_seq: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MutationConflictRequest {
    pub server_instance_id: String,
    pub account_id: String,
    pub session_id: String,
    pub mutation_id: String,
    pub current_version: i64,
    pub current_entity: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MutationConflictOutcome {
    pub outcome: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub conflict_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub replacement_mutation_id: Option<String>,
    pub conflicting_fields: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct OpenSyncConflict {
    pub conflict_id: String,
    pub session_id: String,
    pub entity_type: String,
    pub entity_id: String,
    pub mutation_id: String,
    pub base_version: i64,
    pub remote_version: i64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub base_entity: Option<serde_json::Value>,
    pub local_entity: serde_json::Value,
    pub remote_entity: serde_json::Value,
    pub conflicting_fields: Vec<String>,
    pub allowed_resolutions: Vec<ConflictResolution>,
    pub created_at: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ConflictResolution {
    UseRemote,
    KeepLocal,
    CopyLocalAsNew,
}

impl ConflictResolution {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::UseRemote => "useRemote",
            Self::KeepLocal => "keepLocal",
            Self::CopyLocalAsNew => "copyLocalAsNew",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ResolveConflictRequest {
    pub server_instance_id: String,
    pub account_id: String,
    pub session_id: String,
    pub conflict_id: String,
    pub expected_remote_version: i64,
    pub resolution: ConflictResolution,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ResolveConflictResult {
    pub outcome: String,
    pub resolution: ConflictResolution,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub replacement_mutation_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub replacement_entity_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MutationFailureRequest {
    pub server_instance_id: String,
    pub account_id: String,
    pub session_id: String,
    pub mutation_id: String,
    pub error_code: Option<String>,
    pub error_message: Option<String>,
    pub next_attempt_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncStatus {
    pub session_id: String,
    pub role: CollaborationRole,
    pub replica_state: String,
    pub canonical_session_status: String,
    pub last_applied_seq: i64,
    pub last_seen_head_seq: i64,
    pub pending_count: i64,
    pub conflict_count: i64,
    pub rejected_count: i64,
}
