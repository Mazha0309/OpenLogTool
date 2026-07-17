use openlogtool_core::api::dictionaries::bulk_upsert_dict_items;
use openlogtool_core::dict::search;
use openlogtool_core::models::dict_item::DictItem;
use openlogtool_core::{get_db, init_database};

#[tokio::test]
async fn batch_import_rolls_back_on_mid_transaction_failure_and_revives_tombstones() {
    let database_path = std::env::temp_dir().join(format!(
        "openlogtool-dictionary-atomic-import-{}.db",
        uuid::Uuid::new_v4()
    ));
    init_database(database_path.to_str().unwrap())
        .await
        .unwrap();

    let deleted = DictItem::new("callsign_dictionary".to_string(), "BG5CRL".to_string());
    search::upsert_dict_item(&deleted).await.unwrap();
    search::soft_delete_dict_item("callsign_dictionary", "BG5CRL")
        .await
        .unwrap();

    let pool = get_db().unwrap();
    sqlx::query(
        "CREATE TRIGGER reject_failed_dictionary_import
         BEFORE INSERT ON dictionary_items
         WHEN NEW.raw = 'FORCED_FAILURE'
         BEGIN
             SELECT RAISE(ABORT, 'forced dictionary import failure');
         END",
    )
    .execute(pool)
    .await
    .unwrap();

    let failed_request = serde_json::json!({
        "items": [
            {
                "dictType": "device_dictionary",
                "raw": "FT-991A",
                "pinyin": "FT991A",
                "abbreviation": "FT991A"
            },
            {
                "dictType": "antenna_dictionary",
                "raw": "FORCED_FAILURE"
            }
        ]
    });
    assert!(bulk_upsert_dict_items(failed_request.to_string())
        .await
        .is_err());
    assert!(search::get_dict_item_by_raw("device_dictionary", "FT-991A")
        .await
        .unwrap()
        .is_none());
    assert!(
        search::get_dict_item_by_raw("antenna_dictionary", "FORCED_FAILURE")
            .await
            .unwrap()
            .is_none()
    );

    let successful_request = serde_json::json!({
        "items": [
            {
                "dictType": "callsign_dictionary",
                "raw": "BG5CRL",
                "pinyin": "BG5CRL",
                "abbreviation": "BG5CRL"
            },
            {
                "dictType": "qth_dictionary",
                "raw": "浙江杭州",
                "pinyin": "zhe jiang hang zhou",
                "abbreviation": "ZJHZ"
            }
        ]
    });
    bulk_upsert_dict_items(successful_request.to_string())
        .await
        .unwrap();

    assert!(
        search::get_dict_item_by_raw("callsign_dictionary", "BG5CRL")
            .await
            .unwrap()
            .is_some()
    );
    assert!(search::get_dict_item_by_raw("qth_dictionary", "浙江杭州")
        .await
        .unwrap()
        .is_some());

    pool.close().await;
    let _ = std::fs::remove_file(database_path);
}
