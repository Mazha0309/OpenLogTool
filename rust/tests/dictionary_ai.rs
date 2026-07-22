use openlogtool_core::api::dictionaries::{apply_dictionary_ai_changes, get_dictionary_ai_source};
use openlogtool_core::dict::search;
use openlogtool_core::models::dict_item::DictItem;
use openlogtool_core::{get_db, init_database};
use serde_json::{json, Value};

const NOW: &str = "2026-07-22T12:00:00Z";

#[tokio::test]
async fn dictionary_ai_uses_aggregates_and_applies_reviewed_changes_atomically() {
    let database_path = std::env::temp_dir().join(format!(
        "openlogtool-dictionary-ai-{}.db",
        uuid::Uuid::new_v4()
    ));
    init_database(database_path.to_str().unwrap())
        .await
        .unwrap();
    let pool = get_db().unwrap();
    sqlx::query(
        "INSERT INTO sessions (
            session_id, title, status, created_at, updated_at
         ) VALUES ('local', 'Private title', 'active', ?, ?)",
    )
    .bind(NOW)
    .bind(NOW)
    .execute(pool)
    .await
    .unwrap();
    for (sync_id, callsign, device, deleted_at) in [
        ("log-1", "BG5CRL", "FT-991A", None),
        ("log-2", "BG5CRL", "FT991A", None),
        ("log-deleted", "BA4AAA", "Deleted radio", Some(NOW)),
    ] {
        sqlx::query(
            "INSERT INTO logs (
                sync_id, session_id, time, controller, callsign, qth, device,
                antenna, remarks, created_at, updated_at, deleted_at
             ) VALUES (?, 'local', ?, 'N5XYZ', ?, 'Hangzhou', ?, 'Dipole',
                       'private remark', ?, ?, ?)",
        )
        .bind(sync_id)
        .bind(NOW)
        .bind(callsign)
        .bind(device)
        .bind(NOW)
        .bind(NOW)
        .bind(deleted_at)
        .execute(pool)
        .await
        .unwrap();
    }

    for (dict_type, raw) in [
        ("device_dictionary", "Old Radio"),
        ("antenna_dictionary", "Dipole"),
        ("antenna_dictionary", "DP"),
    ] {
        search::upsert_dict_item(&DictItem::new(dict_type.into(), raw.into()))
            .await
            .unwrap();
    }

    let encoded = get_dictionary_ai_source().await.unwrap();
    assert!(!encoded.contains("Private title"));
    assert!(!encoded.contains("private remark"));
    assert!(!encoded.contains(NOW));
    assert!(!encoded.contains("N5XYZ"));
    assert!(!encoded.contains("BA4AAA"));
    let source: Value = serde_json::from_str(&encoded).unwrap();
    assert_eq!(source["recordCount"], 2);
    assert_eq!(source["history"]["callsign"][0]["value"], "BG5CRL");
    assert_eq!(source["history"]["callsign"][0]["count"], 2);
    assert_eq!(source["history"]["device"].as_array().unwrap().len(), 2);

    let state_token = source["stateToken"].as_str().unwrap();
    let result: Value = serde_json::from_str(
        &apply_dictionary_ai_changes(
            json!({
                "expectedStateToken": state_token,
                "operations": [
                    {
                        "action": "add",
                        "dictType": "callsign_dictionary",
                        "target": "BG5CRL",
                        "pinyin": "bg5crl",
                        "abbreviation": "BG5CRL"
                    },
                    {
                        "action": "rename",
                        "dictType": "device_dictionary",
                        "source": "Old Radio",
                        "target": "New Radio",
                        "pinyin": "new radio",
                        "abbreviation": "NR"
                    },
                    {
                        "action": "merge",
                        "dictType": "antenna_dictionary",
                        "source": "DP",
                        "target": "Dipole"
                    }
                ]
            })
            .to_string(),
        )
        .await
        .unwrap(),
    )
    .unwrap();
    assert_eq!(result, json!({"added": 1, "renamed": 1, "merged": 1}));
    assert!(
        search::get_dict_item_by_raw("callsign_dictionary", "BG5CRL")
            .await
            .unwrap()
            .is_some()
    );
    assert!(
        search::get_dict_item_by_raw("device_dictionary", "Old Radio")
            .await
            .unwrap()
            .is_none()
    );
    assert!(
        search::get_dict_item_by_raw("device_dictionary", "New Radio")
            .await
            .unwrap()
            .is_some()
    );
    assert!(search::get_dict_item_by_raw("antenna_dictionary", "DP")
        .await
        .unwrap()
        .is_none());

    let stale = apply_dictionary_ai_changes(
        json!({
            "expectedStateToken": state_token,
            "operations": [{
                "action": "add",
                "dictType": "qth_dictionary",
                "target": "Ningbo"
            }]
        })
        .to_string(),
    )
    .await
    .unwrap_err();
    assert!(stale.to_string().contains("DICTIONARY_AI_STATE_CHANGED"));

    let fresh: Value = serde_json::from_str(&get_dictionary_ai_source().await.unwrap()).unwrap();
    let rollback = apply_dictionary_ai_changes(
        json!({
            "expectedStateToken": fresh["stateToken"],
            "operations": [
                {
                    "action": "rename",
                    "dictType": "device_dictionary",
                    "source": "New Radio",
                    "target": "Temporary Radio"
                },
                {
                    "action": "merge",
                    "dictType": "antenna_dictionary",
                    "source": "Missing",
                    "target": "Dipole"
                }
            ]
        })
        .to_string(),
    )
    .await
    .unwrap_err();
    assert!(rollback
        .to_string()
        .contains("DICTIONARY_AI_SOURCE_NOT_FOUND"));
    assert!(
        search::get_dict_item_by_raw("device_dictionary", "New Radio")
            .await
            .unwrap()
            .is_some()
    );
    assert!(
        search::get_dict_item_by_raw("device_dictionary", "Temporary Radio")
            .await
            .unwrap()
            .is_none()
    );

    pool.close().await;
    let _ = std::fs::remove_file(database_path);
}
