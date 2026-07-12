use openlogtool_core::db::{live_draft, migrations};
use openlogtool_core::models::live_draft::{
    LiveDraftIdentity, QueueOfflineRecordRequest, SaveLiveDraftCacheRequest,
    UpdateOfflineRecordRequest,
};
use serde_json::json;
use sqlx::sqlite::{SqliteConnectOptions, SqlitePoolOptions};
use sqlx::SqlitePool;
use std::str::FromStr;

const NOW: &str = "2026-07-13T08:00:00Z";

async fn setup() -> (SqlitePool, std::path::PathBuf) {
    let path = std::env::temp_dir().join(format!(
        "openlogtool-live-draft-{}.db",
        uuid::Uuid::new_v4()
    ));
    let options = SqliteConnectOptions::from_str(&format!("sqlite://{}", path.display()))
        .unwrap()
        .create_if_missing(true)
        .foreign_keys(true);
    let pool = SqlitePoolOptions::new()
        .max_connections(1)
        .connect_with(options)
        .await
        .unwrap();
    migrations::run(&pool).await.unwrap();
    sqlx::query(
        "INSERT INTO sessions (
            session_id, title, status, share_code, created_at, updated_at
         ) VALUES ('draft-session', 'Draft test', 'active', NULL, ?, ?)",
    )
    .bind(NOW)
    .bind(NOW)
    .execute(&pool)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO collaboration_bindings (
            server_instance_id, server_origin, account_id, session_id,
            membership_id, membership_version, role, replica_state,
            last_applied_seq, last_seen_head_seq, joined_at, updated_at
         ) VALUES (
            'draft-server', 'https://draft.example', 'draft-account',
            'draft-session', 'draft-membership', 1, 'editor', 'ready',
            0, 0, ?, ?
         )",
    )
    .bind(NOW)
    .bind(NOW)
    .execute(&pool)
    .await
    .unwrap();
    (pool, path)
}

fn identity() -> LiveDraftIdentity {
    LiveDraftIdentity {
        server_instance_id: "draft-server".to_string(),
        account_id: "draft-account".to_string(),
        session_id: "draft-session".to_string(),
    }
}

#[tokio::test]
async fn live_draft_cache_upserts_validated_fields_and_cascades_with_binding() {
    let (pool, path) = setup().await;
    let first = live_draft::save_cache(
        &pool,
        SaveLiveDraftCacheRequest {
            identity: identity(),
            draft_id: "draft-one".to_string(),
            draft_version: 1,
            remote: json!({"draftId": "draft-one", "version": 1}),
            local_fields: json!({"callsign": "BA4AAA", "rstSent": "59"}),
            field_revisions: json!({"callsign": 0, "rstSent": 0}),
            dirty_fields: vec!["callsign".to_string()],
            client_seq: 1,
            remote_updated_at: Some(NOW.to_string()),
        },
    )
    .await
    .unwrap();
    assert_eq!(first.draft_id, "draft-one");
    assert_eq!(first.local_fields["callsign"], "BA4AAA");
    assert_eq!(first.dirty_fields, vec!["callsign"]);

    let second = live_draft::save_cache(
        &pool,
        SaveLiveDraftCacheRequest {
            identity: identity(),
            draft_id: "draft-one".to_string(),
            draft_version: 2,
            remote: json!({"draftId": "draft-one", "version": 2}),
            local_fields: json!({"callsign": "BA4BBB"}),
            field_revisions: json!({"callsign": 1}),
            dirty_fields: vec![],
            client_seq: 2,
            remote_updated_at: Some(NOW.to_string()),
        },
    )
    .await
    .unwrap();
    assert_eq!(second.draft_version, 2);
    assert_eq!(second.client_seq, 2);
    assert!(second.dirty_fields.is_empty());

    let loaded = live_draft::get_cache(&pool, identity())
        .await
        .unwrap()
        .unwrap();
    assert_eq!(loaded.local_fields["callsign"], "BA4BBB");
    let invalid = live_draft::save_cache(
        &pool,
        SaveLiveDraftCacheRequest {
            identity: identity(),
            draft_id: "draft-one".to_string(),
            draft_version: 2,
            remote: json!({}),
            local_fields: json!({"unknown": "value"}),
            field_revisions: json!({}),
            dirty_fields: vec![],
            client_seq: 2,
            remote_updated_at: None,
        },
    )
    .await
    .unwrap_err()
    .to_string();
    assert!(invalid.contains("LIVE_DRAFT_FIELDS_INVALID"));

    sqlx::query("DELETE FROM collaboration_bindings WHERE session_id = 'draft-session'")
        .execute(&pool)
        .await
        .unwrap();
    assert!(live_draft::get_cache(&pool, identity())
        .await
        .unwrap()
        .is_none());
    pool.close().await;
    let _ = std::fs::remove_file(path);
}

#[tokio::test]
async fn offline_records_follow_manual_review_lifecycle() {
    let (pool, path) = setup().await;
    let queued = live_draft::queue_offline_record(
        &pool,
        QueueOfflineRecordRequest {
            identity: identity(),
            mutation_id: "00000000-0000-4000-8000-000000000001".to_string(),
            draft_id: "draft-one".to_string(),
            expected_draft_version: 3,
            provisional_ordinal: 8,
            record: json!({"callsign": "BA4AAA", "controller": "BG5CRL"}),
        },
    )
    .await
    .unwrap();
    assert_eq!(queued.state, "pending");
    assert_eq!(queued.provisional_ordinal, 8);

    let reviewing = live_draft::update_offline_record(
        &pool,
        UpdateOfflineRecordRequest {
            mutation_id: queued.mutation_id.clone(),
            state: "reviewing".to_string(),
            resolution: None,
            last_error_code: Some("LIVE_DRAFT_VERSION_CONFLICT".to_string()),
        },
    )
    .await
    .unwrap();
    assert_eq!(reviewing.state, "reviewing");
    assert_eq!(
        reviewing.last_error_code.as_deref(),
        Some("LIVE_DRAFT_VERSION_CONFLICT")
    );
    assert_eq!(
        live_draft::list_offline_records(&pool, identity())
            .await
            .unwrap()
            .len(),
        1
    );

    let missing_resolution = live_draft::update_offline_record(
        &pool,
        UpdateOfflineRecordRequest {
            mutation_id: queued.mutation_id.clone(),
            state: "resolved".to_string(),
            resolution: None,
            last_error_code: None,
        },
    )
    .await
    .unwrap_err()
    .to_string();
    assert!(missing_resolution.contains("OFFLINE_RECORD_RESOLUTION_REQUIRED"));

    let resolved = live_draft::update_offline_record(
        &pool,
        UpdateOfflineRecordRequest {
            mutation_id: queued.mutation_id,
            state: "resolved".to_string(),
            resolution: Some("copyToCurrentDraft".to_string()),
            last_error_code: None,
        },
    )
    .await
    .unwrap();
    assert_eq!(resolved.resolution.as_deref(), Some("copyToCurrentDraft"));
    assert!(live_draft::list_offline_records(&pool, identity())
        .await
        .unwrap()
        .is_empty());

    pool.close().await;
    let _ = std::fs::remove_file(path);
}
