use crate::dict;
use crate::models::dict_item::DictItem;

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

pub async fn get_dict_items(dict_type: String) -> anyhow::Result<Vec<DictItem>> {
    dict::search::get_dict_items(&dict_type).await
}

pub async fn get_dict_item_by_raw(
    dict_type: String,
    raw: String,
) -> anyhow::Result<Option<DictItem>> {
    dict::search::get_dict_item_by_raw(&dict_type, &raw).await
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
