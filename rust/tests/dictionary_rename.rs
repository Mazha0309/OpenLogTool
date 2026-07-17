use openlogtool_core::api::dictionaries::rename_dict_item;
use openlogtool_core::dict::search;
use openlogtool_core::models::dict_item::DictItem;
use openlogtool_core::{get_db, init_database};

#[tokio::test]
async fn rename_is_atomic_and_searches_raw_pinyin_and_abbreviation() {
    let database_path = std::env::temp_dir().join(format!(
        "openlogtool-dictionary-rename-{}.db",
        uuid::Uuid::new_v4()
    ));
    init_database(database_path.to_str().unwrap())
        .await
        .unwrap();

    let source = DictItem::with_pinyin_abbrev(
        "device_dictionary".to_string(),
        "Old radio".to_string(),
        Some("old radio".to_string()),
        Some("OLD".to_string()),
    );
    let source_sync_id = source.sync_id.clone();
    let target = DictItem::new(
        "device_dictionary".to_string(),
        "Existing radio".to_string(),
    );
    search::upsert_dict_item(&source).await.unwrap();
    search::upsert_dict_item(&target).await.unwrap();

    let conflict = rename_dict_item(
        "device_dictionary".to_string(),
        "Old radio".to_string(),
        "Existing radio".to_string(),
        Some("existing radio".to_string()),
        Some("EXISTING".to_string()),
    )
    .await
    .unwrap_err();
    assert!(conflict
        .to_string()
        .contains("DICTIONARY_RENAME_TARGET_EXISTS"));
    assert!(
        search::get_dict_item_by_raw("device_dictionary", "Old radio")
            .await
            .unwrap()
            .is_some()
    );
    assert!(
        search::get_dict_item_by_raw("device_dictionary", "Existing radio")
            .await
            .unwrap()
            .is_some()
    );

    search::soft_delete_dict_item("device_dictionary", "Existing radio")
        .await
        .unwrap();
    let renamed = rename_dict_item(
        "device_dictionary".to_string(),
        "Old radio".to_string(),
        "Existing radio".to_string(),
        Some("xin she bei".to_string()),
        Some("XSB".to_string()),
    )
    .await
    .unwrap();
    assert_eq!(renamed.raw, "Existing radio");
    assert_eq!(renamed.sync_id, source_sync_id);
    assert_eq!(renamed.pinyin.as_deref(), Some("xin she bei"));
    assert_eq!(renamed.abbreviation.as_deref(), Some("XSB"));
    assert!(
        search::get_dict_item_by_raw("device_dictionary", "Old radio")
            .await
            .unwrap()
            .is_none()
    );

    assert_eq!(
        search::search_dict("device_dictionary", "existing", 20)
            .await
            .unwrap()
            .len(),
        1
    );
    assert_eq!(
        search::search_dict("device_dictionary", "XIN SHE", 20)
            .await
            .unwrap()
            .len(),
        1
    );
    assert_eq!(
        search::search_dict("device_dictionary", "xsb", 20)
            .await
            .unwrap()
            .len(),
        1
    );

    let pool = get_db().unwrap();
    pool.close().await;
    let _ = std::fs::remove_file(database_path);
}
