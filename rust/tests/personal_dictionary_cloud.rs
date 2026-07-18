use openlogtool_core::api::personal_cloud::{
    load_personal_cloud_state, require_personal_cloud_pairing, save_personal_cloud_baseline,
};
use openlogtool_core::api::personal_dictionary::{
    export_personal_dictionary, replace_personal_dictionary_if_unchanged,
};
use openlogtool_core::db::migrations;
use openlogtool_core::dict::search;
use openlogtool_core::models::dict_item::DictItem;
use openlogtool_core::{get_db, init_database};
use serde_json::{json, Value};
use sqlx::sqlite::{SqliteConnectOptions, SqlitePoolOptions};
use std::str::FromStr;

const NOW: &str = "2026-07-19T08:00:00.000Z";

#[tokio::test]
async fn v6_upgrade_removes_qth_cache_and_installs_v7_local_cloud_schema() {
    let options = SqliteConnectOptions::from_str("sqlite::memory:")
        .unwrap()
        .create_if_missing(true)
        .foreign_keys(true);
    let pool = SqlitePoolOptions::new()
        .max_connections(1)
        .connect_with(options)
        .await
        .unwrap();

    sqlx::query(
        "CREATE TABLE schema_version (
            version INTEGER PRIMARY KEY,
            applied_at TEXT NOT NULL
         )",
    )
    .execute(&pool)
    .await
    .unwrap();
    sqlx::query("INSERT INTO schema_version (version, applied_at) VALUES (6, ?)")
        .bind(NOW)
        .execute(&pool)
        .await
        .unwrap();
    sqlx::query(
        "CREATE TABLE dictionary_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            dict_type TEXT NOT NULL,
            raw TEXT NOT NULL,
            pinyin TEXT,
            abbreviation TEXT,
            sync_id TEXT UNIQUE,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            deleted_at TEXT,
            UNIQUE(dict_type, raw)
         )",
    )
    .execute(&pool)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO dictionary_items (
            dict_type, raw, sync_id, created_at, updated_at
         ) VALUES ('device_dictionary', 'Legacy radio', 'legacy-dict', ?, ?)",
    )
    .bind(NOW)
    .bind(NOW)
    .execute(&pool)
    .await
    .unwrap();
    sqlx::query(
        "CREATE TABLE callsign_qth_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sync_id TEXT UNIQUE,
            callsign TEXT NOT NULL,
            qth TEXT NOT NULL,
            recorded_at TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            deleted_at TEXT,
            source_device_id TEXT
         )",
    )
    .execute(&pool)
    .await
    .unwrap();
    sqlx::query(
        "CREATE INDEX idx_callsign_qth_callsign
         ON callsign_qth_history(callsign)",
    )
    .execute(&pool)
    .await
    .unwrap();

    migrations::run(&pool).await.unwrap();

    let version: (i64,) = sqlx::query_as("SELECT MAX(version) FROM schema_version")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(version.0, 7);
    let obsolete_objects: (i64,) = sqlx::query_as(
        "SELECT COUNT(*) FROM sqlite_master
         WHERE name IN ('callsign_qth_history', 'idx_callsign_qth_callsign')",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(obsolete_objects.0, 0);
    let migrated_origin: (String,) =
        sqlx::query_as("SELECT origin FROM dictionary_items WHERE raw = 'Legacy radio'")
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(migrated_origin.0, "unknown");
    let cloud_tables: (i64,) = sqlx::query_as(
        "SELECT COUNT(*) FROM sqlite_master
         WHERE type = 'table'
           AND name IN ('personal_cloud_baselines', 'personal_cloud_state')",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(cloud_tables.0, 2);
    let state: (Option<String>, Option<String>) = sqlx::query_as(
        "SELECT owner_scope_hash, pairing_required_reason
         FROM personal_cloud_state WHERE id = 1",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(state, (None, None));
}

#[tokio::test]
async fn incomplete_v7_dictionary_shape_is_repaired_idempotently() {
    let options = SqliteConnectOptions::from_str("sqlite::memory:")
        .unwrap()
        .create_if_missing(true)
        .foreign_keys(true);
    let pool = SqlitePoolOptions::new()
        .max_connections(1)
        .connect_with(options)
        .await
        .unwrap();

    sqlx::query(
        "CREATE TABLE schema_version (
            version INTEGER PRIMARY KEY,
            applied_at TEXT NOT NULL
         )",
    )
    .execute(&pool)
    .await
    .unwrap();
    sqlx::query("INSERT INTO schema_version (version, applied_at) VALUES (7, ?)")
        .bind(NOW)
        .execute(&pool)
        .await
        .unwrap();
    // This is the transient v7 shape that produced `row len 9, index 9`:
    // schema_version was advanced but dictionary_items still had the v6
    // columns. Migration startup must repair it instead of trusting the marker.
    sqlx::query(
        "CREATE TABLE dictionary_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            dict_type TEXT NOT NULL,
            raw TEXT NOT NULL,
            pinyin TEXT,
            abbreviation TEXT,
            sync_id TEXT UNIQUE,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            deleted_at TEXT,
            UNIQUE(dict_type, raw)
         )",
    )
    .execute(&pool)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO dictionary_items (
            dict_type, raw, sync_id, created_at, updated_at
         ) VALUES ('device_dictionary', 'Partial v7 radio', 'partial-v7', ?, ?)",
    )
    .bind(NOW)
    .bind(NOW)
    .execute(&pool)
    .await
    .unwrap();

    migrations::run(&pool).await.unwrap();
    // A second startup proves the repair path remains idempotent.
    migrations::run(&pool).await.unwrap();

    let row: (String, String) = sqlx::query_as(
        "SELECT raw, origin FROM dictionary_items
         WHERE sync_id = 'partial-v7'",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(row, ("Partial v7 radio".to_string(), "unknown".to_string()));
    let cloud_state: (i64,) = sqlx::query_as("SELECT COUNT(*) FROM personal_cloud_state")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(cloud_state.0, 1);
}

#[tokio::test]
async fn personal_dictionary_and_cloud_state_are_canonical_and_compare_replaced() {
    let database_path = std::env::temp_dir().join(format!(
        "openlogtool-personal-dictionary-cloud-{}.db",
        uuid::Uuid::new_v4()
    ));
    init_database(database_path.to_str().unwrap())
        .await
        .unwrap();
    let pool = get_db().unwrap();

    // Simulate rows upgraded from v6. Seeding classifies matching assets as
    // built-ins and every remaining legacy row of that type as user content.
    sqlx::query(
        "INSERT INTO dictionary_items (
            dict_type, raw, pinyin, abbreviation, sync_id,
            created_at, updated_at, origin
         ) VALUES
            ('device_dictionary', 'Built-in radio', 'built in', 'BI',
             'legacy-built-in', ?, ?, 'unknown'),
            ('device_dictionary', 'My legacy radio', 'my radio', 'MR',
             'legacy-user', ?, ?, 'unknown')",
    )
    .bind(NOW)
    .bind(NOW)
    .bind(NOW)
    .bind(NOW)
    .execute(pool)
    .await
    .unwrap();
    search::seed_dict("device_dictionary", vec!["Built-in radio".to_string()])
        .await
        .unwrap();
    let origins: Vec<(String, String)> = sqlx::query_as(
        "SELECT raw, origin FROM dictionary_items
         WHERE dict_type = 'device_dictionary' ORDER BY raw",
    )
    .fetch_all(pool)
    .await
    .unwrap();
    assert_eq!(
        origins,
        vec![
            ("Built-in radio".to_string(), "builtin".to_string()),
            ("My legacy radio".to_string(), "user".to_string()),
        ]
    );

    search::soft_delete_dict_item("device_dictionary", "Built-in radio")
        .await
        .unwrap();
    let mut added = DictItem::with_pinyin_abbrev(
        "antenna_dictionary".to_string(),
        "My antenna".to_string(),
        Some("my antenna".to_string()),
        Some("MA".to_string()),
    );
    added.origin = "builtin".to_string();
    // User mutation APIs own the provenance decision; a forged caller-side
    // origin must never turn user content into a built-in row.
    search::upsert_dict_item(&added).await.unwrap();

    let expected_json = export_personal_dictionary().await.unwrap();
    let expected: Value = serde_json::from_str(&expected_json).unwrap();
    let builtin_tombstone = expected["items"]
        .as_array()
        .unwrap()
        .iter()
        .find(|item| item["raw"] == "Built-in radio")
        .unwrap();
    assert_eq!(builtin_tombstone["origin"], "builtin");
    assert_eq!(builtin_tombstone["state"], "deleted");
    assert_eq!(builtin_tombstone["pinyin"], Value::Null);
    assert_eq!(builtin_tombstone["abbreviation"], Value::Null);
    let user_item = expected["items"]
        .as_array()
        .unwrap()
        .iter()
        .find(|item| item["raw"] == "My antenna")
        .unwrap();
    assert_eq!(user_item["origin"], "user");
    assert_eq!(user_item["state"], "active");

    let incoming = json!({
        "version": 1,
        "exportedAt": "2026-07-19T09:00:00.000Z",
        "items": [
            {
                "dictType": "device",
                "raw": "Built-in radio",
                "origin": "builtin",
                "state": "deleted",
                "pinyin": null,
                "abbreviation": null
            },
            {
                "dictType": "qth",
                "raw": "Remote QTH",
                "origin": "user",
                "state": "active",
                "pinyin": "remote qth",
                "abbreviation": "RQ"
            }
        ]
    });
    let result: Value = serde_json::from_str(
        &replace_personal_dictionary_if_unchanged(incoming.to_string(), expected_json.clone())
            .await
            .unwrap(),
    )
    .unwrap();
    assert_eq!(result["itemCount"], 2);
    assert!(
        search::get_dict_item_by_raw("antenna_dictionary", "My antenna")
            .await
            .unwrap()
            .is_none()
    );
    let remote = search::get_dict_item_by_raw("qth_dictionary", "Remote QTH")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(remote.origin, "user");
    assert_eq!(remote.abbreviation.as_deref(), Some("RQ"));
    let stale_error = replace_personal_dictionary_if_unchanged(incoming.to_string(), expected_json)
        .await
        .unwrap_err()
        .to_string();
    assert!(stale_error.contains("PERSONAL_DICTIONARY_LOCAL_CHANGED"));

    let scope_a = "a".repeat(64);
    let scope_b = "c".repeat(64);
    let checksum = "b".repeat(64);
    let record_snapshot = json!({"version": 1, "sessions": [], "logs": []});
    save_personal_cloud_baseline(
        scope_a.clone(),
        "records".to_string(),
        4,
        record_snapshot.to_string(),
        checksum.clone(),
        true,
        true,
    )
    .await
    .unwrap();
    save_personal_cloud_baseline(
        scope_a.clone(),
        "dictionaries".to_string(),
        2,
        incoming.to_string(),
        checksum.clone(),
        false,
        false,
    )
    .await
    .unwrap();
    let loaded: Value = serde_json::from_str(
        &load_personal_cloud_state(scope_a.clone(), "records".to_string())
            .await
            .unwrap(),
    )
    .unwrap();
    assert_eq!(loaded["ownerScopeHash"], scope_a);
    assert_eq!(loaded["pairingRequiredReason"], Value::Null);
    assert_eq!(loaded["baseline"]["remoteRevision"], 4);
    assert_eq!(loaded["baseline"]["snapshot"], record_snapshot);
    assert_eq!(loaded["baseline"]["checksum"], checksum);

    require_personal_cloud_pairing("account_changed".to_string())
        .await
        .unwrap();
    let pairing: Value = serde_json::from_str(
        &load_personal_cloud_state(scope_a.clone(), "records".to_string())
            .await
            .unwrap(),
    )
    .unwrap();
    assert_eq!(pairing["ownerScopeHash"], scope_a);
    assert_eq!(pairing["pairingRequiredReason"], "account_changed");
    assert_eq!(pairing["baseline"], Value::Null);
    let remaining_baselines: (i64,) =
        sqlx::query_as("SELECT COUNT(*) FROM personal_cloud_baselines")
            .fetch_one(pool)
            .await
            .unwrap();
    assert_eq!(remaining_baselines.0, 0);

    save_personal_cloud_baseline(
        scope_b.clone(),
        "records".to_string(),
        5,
        record_snapshot.to_string(),
        checksum,
        true,
        true,
    )
    .await
    .unwrap();
    let repaired: Value = serde_json::from_str(
        &load_personal_cloud_state(scope_b.clone(), "records".to_string())
            .await
            .unwrap(),
    )
    .unwrap();
    assert_eq!(repaired["ownerScopeHash"], scope_b);
    assert_eq!(repaired["pairingRequiredReason"], Value::Null);
    assert_eq!(repaired["baseline"]["remoteRevision"], 5);

    pool.close().await;
    let _ = std::fs::remove_file(database_path);
}
