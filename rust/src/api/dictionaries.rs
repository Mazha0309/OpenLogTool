use crate::dict;
use crate::models::dict_item::DictItem;
use anyhow::Context;
use serde::Deserialize;

const IMPORTABLE_DICTIONARY_TYPES: [&str; 4] = [
    "device_dictionary",
    "antenna_dictionary",
    "callsign_dictionary",
    "qth_dictionary",
];

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct BulkUpsertDictRequest {
    items: Vec<BulkUpsertDictItem>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct BulkUpsertDictItem {
    dict_type: String,
    raw: String,
    pinyin: Option<String>,
    abbreviation: Option<String>,
}

pub async fn search_dict(
    dict_type: String,
    query: String,
    limit: Option<i64>,
) -> anyhow::Result<Vec<DictItem>> {
    dict::search::search_dict(&dict_type, &query, limit.unwrap_or(20)).await
}

pub async fn add_dict_item(dict_type: String, raw: String) -> anyhow::Result<()> {
    let item = DictItem::new(dict_type, raw);
    dict::search::add_dict_item(&item).await
}

pub async fn upsert_dict_item(
    dict_type: String,
    raw: String,
    pinyin: Option<String>,
    abbreviation: Option<String>,
) -> anyhow::Result<()> {
    let item = DictItem::with_pinyin_abbrev(dict_type, raw, pinyin, abbreviation);
    dict::search::upsert_dict_item(&item).await
}

pub async fn upsert_dict_item_if_active(
    dict_type: String,
    raw: String,
    pinyin: Option<String>,
    abbreviation: Option<String>,
) -> anyhow::Result<()> {
    let item = DictItem::with_pinyin_abbrev(dict_type, raw, pinyin, abbreviation);
    dict::search::upsert_dict_item_if_active(&item).await
}

/// Atomically imports user-supplied dictionary entries.
///
/// Unlike built-in dictionary synchronization, an explicit import revives an
/// existing tombstoned `(dict_type, raw)` row. The whole request is committed
/// in one SQLite transaction, so a failure cannot leave a partially imported
/// file behind.
pub async fn bulk_upsert_dict_items(request_json: String) -> anyhow::Result<()> {
    let request: BulkUpsertDictRequest =
        serde_json::from_str(&request_json).context("DICTIONARY_BATCH_IMPORT_INVALID_JSON")?;
    let mut items = Vec::with_capacity(request.items.len());

    for request_item in request.items {
        let dict_type = request_item.dict_type.trim();
        if !IMPORTABLE_DICTIONARY_TYPES.contains(&dict_type) {
            anyhow::bail!(
                "DICTIONARY_BATCH_IMPORT_UNSUPPORTED_TYPE: {}",
                request_item.dict_type
            );
        }

        let raw = request_item.raw.trim();
        if raw.is_empty() {
            anyhow::bail!("DICTIONARY_BATCH_IMPORT_EMPTY_ITEM");
        }

        let normalized_optional = |value: Option<String>| {
            value.and_then(|value| {
                let value = value.trim().to_string();
                (!value.is_empty()).then_some(value)
            })
        };
        items.push(DictItem::with_pinyin_abbrev(
            dict_type.to_string(),
            raw.to_string(),
            normalized_optional(request_item.pinyin),
            normalized_optional(request_item.abbreviation),
        ));
    }

    dict::search::bulk_upsert_dict_items(&items).await
}

pub async fn get_dict_items(dict_type: String) -> anyhow::Result<Vec<DictItem>> {
    dict::search::get_dict_items(&dict_type).await
}

pub async fn get_dict_item_by_raw(
    dict_type: String,
    raw: String,
) -> anyhow::Result<Option<DictItem>> {
    dict::search::get_dict_item_by_raw(&dict_type, &raw).await
}

pub async fn soft_delete_dict_item(dict_type: String, raw: String) -> anyhow::Result<bool> {
    dict::search::soft_delete_dict_item(&dict_type, &raw).await
}

pub async fn soft_delete_dict_items(dict_type: String) -> anyhow::Result<()> {
    dict::search::soft_delete_dict_items(&dict_type).await
}

pub async fn reset_dictionaries() -> anyhow::Result<()> {
    dict::search::reset_dictionaries().await
}

pub async fn seed_dict(dict_type: String, items: Vec<String>) -> anyhow::Result<usize> {
    dict::search::seed_dict(&dict_type, items).await
}
