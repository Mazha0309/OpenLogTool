use openlogtool_core::dict::search;
use openlogtool_core::models::dict_item::DictItem;
use openlogtool_core::{get_db, init_database};

#[tokio::test]
async fn dictionary_deletion_is_scoped_and_explicit_readd_resurrects() {
    let database_path = std::env::temp_dir().join(format!(
        "openlogtool-dictionary-deletion-{}.db",
        uuid::Uuid::new_v4()
    ));
    init_database(database_path.to_str().unwrap())
        .await
        .unwrap();

    let deleted_radio = DictItem::with_pinyin_abbrev(
        "device_dictionary".to_string(),
        "FT-991A".to_string(),
        Some("FT991A".to_string()),
        Some("FT991A".to_string()),
    );
    let retained_radio = DictItem::new("device_dictionary".to_string(), "IC-7300".to_string());
    let retained_antenna = DictItem::new("antenna_dictionary".to_string(), "Yagi".to_string());
    let fresh_builtin = DictItem::new("qth_dictionary".to_string(), "浙江杭州".to_string());

    // The non-resurrecting built-in path still seeds a genuinely new row.
    search::upsert_dict_item_if_active(&fresh_builtin)
        .await
        .unwrap();
    assert!(search::get_dict_item_by_raw("qth_dictionary", "浙江杭州")
        .await
        .unwrap()
        .is_some());
    search::upsert_dict_item(&deleted_radio).await.unwrap();
    search::upsert_dict_item(&retained_radio).await.unwrap();
    search::upsert_dict_item(&retained_antenna).await.unwrap();

    assert!(
        search::soft_delete_dict_item("device_dictionary", "FT-991A")
            .await
            .unwrap()
    );
    assert!(search::get_dict_item_by_raw("device_dictionary", "FT-991A")
        .await
        .unwrap()
        .is_none());
    assert!(search::get_dict_item_by_raw("device_dictionary", "IC-7300")
        .await
        .unwrap()
        .is_some());
    assert!(search::get_dict_item_by_raw("antenna_dictionary", "Yagi")
        .await
        .unwrap()
        .is_some());

    // Built-in synchronization may enrich active rows, but it must respect a
    // user's tombstone and keep a deliberately deleted built-in item hidden.
    search::upsert_dict_item_if_active(&deleted_radio)
        .await
        .unwrap();
    assert!(search::get_dict_item_by_raw("device_dictionary", "FT-991A")
        .await
        .unwrap()
        .is_none());

    // An explicit add/import is user intent and therefore may reactivate the
    // same unique (type, raw) row.
    search::upsert_dict_item(&deleted_radio).await.unwrap();
    assert!(search::get_dict_item_by_raw("device_dictionary", "FT-991A")
        .await
        .unwrap()
        .is_some());

    search::soft_delete_dict_items("device_dictionary")
        .await
        .unwrap();
    assert!(search::get_dict_items("device_dictionary")
        .await
        .unwrap()
        .is_empty());
    assert_eq!(
        search::get_dict_items("antenna_dictionary")
            .await
            .unwrap()
            .len(),
        1
    );

    let pool = get_db().unwrap();
    pool.close().await;
    let _ = std::fs::remove_file(database_path);
}
