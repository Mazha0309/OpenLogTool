use crate::get_db;
use crate::models::dict_item::DictItem;

pub async fn search_dict(
    dict_type: &str,
    query: &str,
    limit: i64,
) -> anyhow::Result<Vec<DictItem>> {
    let pool = get_db()?;
    let pattern = format!("%{}%", query);
    let rows = sqlx::query_as::<_, DictItemRow>(
        "SELECT * FROM dictionary_items
         WHERE dict_type = ? AND deleted_at IS NULL
         AND (raw LIKE ? OR pinyin LIKE ? OR abbreviation LIKE ?)
         ORDER BY raw ASC LIMIT ?",
    )
    .bind(dict_type)
    .bind(&pattern)
    .bind(&pattern)
    .bind(&pattern)
    .bind(limit)
    .fetch_all(pool)
    .await?;
    Ok(rows.into_iter().map(|r| r.into_item()).collect())
}

pub async fn add_dict_item(item: &DictItem) -> anyhow::Result<()> {
    let pool = get_db()?;
    sqlx::query(
        "INSERT OR IGNORE INTO dictionary_items (dict_type, raw, pinyin, abbreviation, sync_id, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?)",
    )
    .bind(&item.dict_type)
    .bind(&item.raw)
    .bind(&item.pinyin)
    .bind(&item.abbreviation)
    .bind(&item.sync_id)
    .bind(&item.created_at)
    .bind(&item.updated_at)
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn seed_dict(dict_type: &str, items: Vec<String>) -> anyhow::Result<usize> {
    let pool = get_db()?;
    let count: (i64,) = sqlx::query_as(
        "SELECT COUNT(*) FROM dictionary_items WHERE dict_type = ?",
    )
    .bind(dict_type)
    .fetch_one(pool)
    .await?;
    if count.0 > 0 {
        return Ok(count.0 as usize);
    }
    let now = chrono::Utc::now().to_rfc3339();
    for raw in items {
        let sync_id = format!("dict-{}", uuid::Uuid::new_v4());
        sqlx::query(
            "INSERT OR IGNORE INTO dictionary_items (dict_type, raw, sync_id, created_at, updated_at)
             VALUES (?, ?, ?, ?, ?)",
        )
        .bind(dict_type)
        .bind(&raw)
        .bind(&sync_id)
        .bind(&now)
        .bind(&now)
        .execute(pool)
        .await?;
    }
    let total: (i64,) = sqlx::query_as(
        "SELECT COUNT(*) FROM dictionary_items WHERE dict_type = ?",
    )
    .bind(dict_type)
    .fetch_one(pool)
    .await?;
    Ok(total.0 as usize)
}

#[derive(sqlx::FromRow)]
struct DictItemRow {
    id: Option<i64>,
    dict_type: String,
    raw: String,
    pinyin: Option<String>,
    abbreviation: Option<String>,
    sync_id: String,
    created_at: String,
    updated_at: String,
    deleted_at: Option<String>,
}

impl DictItemRow {
    fn into_item(self) -> DictItem {
        DictItem {
            id: self.id,
            dict_type: self.dict_type,
            raw: self.raw,
            pinyin: self.pinyin,
            abbreviation: self.abbreviation,
            sync_id: self.sync_id,
            created_at: self.created_at,
            updated_at: self.updated_at,
            deleted_at: self.deleted_at,
        }
    }
}
