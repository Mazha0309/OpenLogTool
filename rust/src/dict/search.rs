use crate::get_db;
use crate::models::dict_item::DictItem;

pub async fn search_dict(
    dict_type: &str,
    query: &str,
    limit: i64,
) -> anyhow::Result<Vec<DictItem>> {
    let pool = get_db()?;
    let pattern = format!("%{}%", query.trim());
    let limit = limit.clamp(1, 200);
    let rows = sqlx::query_as::<_, DictItemRow>(
        "SELECT
            id, dict_type, raw, pinyin, abbreviation, sync_id,
            created_at, updated_at, deleted_at, origin
         FROM dictionary_items
         WHERE dict_type = ? AND deleted_at IS NULL
         AND (
             LOWER(raw) LIKE LOWER(?) OR
             LOWER(COALESCE(pinyin, '')) LIKE LOWER(?) OR
             LOWER(COALESCE(abbreviation, '')) LIKE LOWER(?)
         )
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

/// Renames one active dictionary row as a tombstone plus a new user row.
///
/// Treating rename as delete + create gives cloud synchronization a stable,
/// unambiguous representation and preserves deletion overrides for built-ins.
pub async fn rename_dict_item(
    dict_type: &str,
    old_raw: &str,
    new_raw: &str,
    pinyin: Option<String>,
    abbreviation: Option<String>,
) -> anyhow::Result<DictItem> {
    let old_raw = old_raw.trim();
    let new_raw = new_raw.trim();
    if old_raw.is_empty() || new_raw.is_empty() {
        anyhow::bail!("DICTIONARY_RENAME_EMPTY_ITEM");
    }

    let pool = get_db()?;
    let mut tx = pool.begin().await?;
    let source: Option<(i64,)> = sqlx::query_as(
        "SELECT id FROM dictionary_items
         WHERE dict_type = ? AND raw = ? AND deleted_at IS NULL",
    )
    .bind(dict_type)
    .bind(old_raw)
    .fetch_optional(&mut *tx)
    .await?;
    if source.is_none() {
        anyhow::bail!("DICTIONARY_RENAME_SOURCE_NOT_FOUND");
    }

    if old_raw != new_raw {
        let active_target: Option<(i64,)> = sqlx::query_as(
            "SELECT id FROM dictionary_items
             WHERE dict_type = ? AND raw = ? AND deleted_at IS NULL",
        )
        .bind(dict_type)
        .bind(new_raw)
        .fetch_optional(&mut *tx)
        .await?;
        if active_target.is_some() {
            anyhow::bail!("DICTIONARY_RENAME_TARGET_EXISTS");
        }
    }

    let now = chrono::Utc::now().to_rfc3339();
    if old_raw == new_raw {
        let result = sqlx::query(
            "UPDATE dictionary_items
             SET pinyin = ?, abbreviation = ?, origin = 'user', updated_at = ?
             WHERE dict_type = ? AND raw = ? AND deleted_at IS NULL",
        )
        .bind(pinyin)
        .bind(abbreviation)
        .bind(&now)
        .bind(dict_type)
        .bind(old_raw)
        .execute(&mut *tx)
        .await?;
        if result.rows_affected() != 1 {
            anyhow::bail!("DICTIONARY_RENAME_WRITE_FAILED");
        }
    } else {
        let deleted = sqlx::query(
            "UPDATE dictionary_items
             SET deleted_at = ?, updated_at = ?
             WHERE dict_type = ? AND raw = ? AND deleted_at IS NULL",
        )
        .bind(&now)
        .bind(&now)
        .bind(dict_type)
        .bind(old_raw)
        .execute(&mut *tx)
        .await?;
        if deleted.rows_affected() != 1 {
            anyhow::bail!("DICTIONARY_RENAME_WRITE_FAILED");
        }

        sqlx::query(
            "INSERT INTO dictionary_items (
                dict_type, raw, pinyin, abbreviation, sync_id,
                created_at, updated_at, deleted_at, origin
             ) VALUES (?, ?, ?, ?, ?, ?, ?, NULL, 'user')
             ON CONFLICT(dict_type, raw) DO UPDATE SET
                pinyin = excluded.pinyin,
                abbreviation = excluded.abbreviation,
                sync_id = excluded.sync_id,
                created_at = excluded.created_at,
                updated_at = excluded.updated_at,
                deleted_at = NULL,
                origin = 'user'",
        )
        .bind(dict_type)
        .bind(new_raw)
        .bind(pinyin)
        .bind(abbreviation)
        .bind(format!("dict-{}", uuid::Uuid::new_v4()))
        .bind(&now)
        .bind(&now)
        .execute(&mut *tx)
        .await?;
    }

    let renamed = sqlx::query_as::<_, DictItemRow>(
        "SELECT
            id, dict_type, raw, pinyin, abbreviation, sync_id,
            created_at, updated_at, deleted_at, origin
         FROM dictionary_items
         WHERE dict_type = ? AND raw = ? AND deleted_at IS NULL",
    )
    .bind(dict_type)
    .bind(new_raw)
    .fetch_one(&mut *tx)
    .await?
    .into_item();
    tx.commit().await?;
    Ok(renamed)
}

pub async fn add_dict_item(item: &DictItem) -> anyhow::Result<()> {
    let pool = get_db()?;
    sqlx::query(
        "INSERT INTO dictionary_items (dict_type, raw, pinyin, abbreviation, sync_id, created_at, updated_at, origin)
         VALUES (?, ?, ?, ?, ?, ?, ?, 'user')
         ON CONFLICT(dict_type, raw) DO UPDATE SET
             pinyin = excluded.pinyin,
             abbreviation = excluded.abbreviation,
             updated_at = excluded.updated_at,
             deleted_at = NULL,
             origin = 'user'",
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

pub async fn upsert_dict_item(item: &DictItem) -> anyhow::Result<()> {
    let pool = get_db()?;
    sqlx::query(
        "INSERT INTO dictionary_items (dict_type, raw, pinyin, abbreviation, sync_id, created_at, updated_at, origin)
         VALUES (?, ?, ?, ?, ?, ?, ?, 'user')
         ON CONFLICT(dict_type, raw) DO UPDATE SET
             pinyin = excluded.pinyin,
             abbreviation = excluded.abbreviation,
             updated_at = excluded.updated_at,
             deleted_at = NULL,
             origin = 'user'",
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

pub async fn upsert_dict_item_if_active(item: &DictItem) -> anyhow::Result<()> {
    let pool = get_db()?;
    sqlx::query(
        "INSERT INTO dictionary_items (dict_type, raw, pinyin, abbreviation, sync_id, created_at, updated_at, origin)
         VALUES (?, ?, ?, ?, ?, ?, ?, 'builtin')
         ON CONFLICT(dict_type, raw) DO UPDATE SET
             pinyin = CASE WHEN origin = 'user' THEN pinyin
                           ELSE COALESCE(NULLIF(pinyin, ''), excluded.pinyin) END,
             abbreviation = CASE WHEN origin = 'user' THEN abbreviation
                                  ELSE COALESCE(NULLIF(abbreviation, ''), excluded.abbreviation) END,
             updated_at = CASE WHEN origin = 'user' THEN updated_at ELSE excluded.updated_at END,
             origin = CASE WHEN origin = 'unknown' THEN 'builtin' ELSE origin END
         WHERE deleted_at IS NULL",
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

/// Upserts every item in a single transaction.
///
/// This is the explicit user-import path, so conflicts revive tombstoned rows
/// in the same way as [upsert_dict_item].
pub async fn bulk_upsert_dict_items(items: &[DictItem]) -> anyhow::Result<()> {
    let pool = get_db()?;
    let mut tx = pool.begin().await?;

    for item in items {
        sqlx::query(
            "INSERT INTO dictionary_items (dict_type, raw, pinyin, abbreviation, sync_id, created_at, updated_at, origin)
             VALUES (?, ?, ?, ?, ?, ?, ?, 'user')
             ON CONFLICT(dict_type, raw) DO UPDATE SET
                 pinyin = excluded.pinyin,
                 abbreviation = excluded.abbreviation,
                 updated_at = excluded.updated_at,
                 deleted_at = NULL,
                 origin = 'user'",
        )
        .bind(&item.dict_type)
        .bind(&item.raw)
        .bind(&item.pinyin)
        .bind(&item.abbreviation)
        .bind(&item.sync_id)
        .bind(&item.created_at)
        .bind(&item.updated_at)
        .execute(&mut *tx)
        .await?;
    }

    tx.commit().await?;
    Ok(())
}

pub async fn get_dict_items(dict_type: &str) -> anyhow::Result<Vec<DictItem>> {
    let pool = get_db()?;
    let rows = sqlx::query_as::<_, DictItemRow>(
        "SELECT
            id, dict_type, raw, pinyin, abbreviation, sync_id,
            created_at, updated_at, deleted_at, origin
         FROM dictionary_items
         WHERE dict_type = ? AND deleted_at IS NULL
         ORDER BY raw ASC",
    )
    .bind(dict_type)
    .fetch_all(pool)
    .await?;
    Ok(rows.into_iter().map(|r| r.into_item()).collect())
}

pub async fn get_dict_item_by_raw(dict_type: &str, raw: &str) -> anyhow::Result<Option<DictItem>> {
    let pool = get_db()?;
    let row = sqlx::query_as::<_, DictItemRow>(
        "SELECT
            id, dict_type, raw, pinyin, abbreviation, sync_id,
            created_at, updated_at, deleted_at, origin
         FROM dictionary_items
         WHERE dict_type = ? AND raw = ? AND deleted_at IS NULL",
    )
    .bind(dict_type)
    .bind(raw)
    .fetch_optional(pool)
    .await?;
    Ok(row.map(|r| r.into_item()))
}

pub async fn soft_delete_dict_item(dict_type: &str, raw: &str) -> anyhow::Result<bool> {
    let pool = get_db()?;
    let now = chrono::Utc::now().to_rfc3339();
    let result = sqlx::query(
        "UPDATE dictionary_items SET deleted_at = ?, updated_at = ?
         WHERE dict_type = ? AND raw = ? AND deleted_at IS NULL",
    )
    .bind(&now)
    .bind(&now)
    .bind(dict_type)
    .bind(raw)
    .execute(pool)
    .await?;
    Ok(result.rows_affected() > 0)
}

pub async fn soft_delete_dict_items(dict_type: &str) -> anyhow::Result<()> {
    let pool = get_db()?;
    let now = chrono::Utc::now().to_rfc3339();
    sqlx::query(
        "UPDATE dictionary_items SET deleted_at = ?, updated_at = ?
         WHERE dict_type = ? AND deleted_at IS NULL",
    )
    .bind(&now)
    .bind(&now)
    .bind(dict_type)
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn reset_dictionaries() -> anyhow::Result<()> {
    let pool = get_db()?;
    sqlx::query("DELETE FROM dictionary_items")
        .execute(pool)
        .await?;
    Ok(())
}

pub async fn seed_dict(dict_type: &str, items: Vec<String>) -> anyhow::Result<usize> {
    let pool = get_db()?;
    let mut tx = pool.begin().await?;
    let now = chrono::Utc::now().to_rfc3339();
    for raw in items {
        let sync_id = format!("dict-{}", uuid::Uuid::new_v4());
        sqlx::query(
            "INSERT OR IGNORE INTO dictionary_items (
                dict_type, raw, sync_id, created_at, updated_at, origin
             ) VALUES (?, ?, ?, ?, ?, 'builtin')",
        )
        .bind(dict_type)
        .bind(&raw)
        .bind(&sync_id)
        .bind(&now)
        .bind(&now)
        .execute(&mut *tx)
        .await?;
        sqlx::query(
            "UPDATE dictionary_items SET origin = 'builtin'
             WHERE dict_type = ? AND raw = ? AND origin = 'unknown'",
        )
        .bind(dict_type)
        .bind(&raw)
        .execute(&mut *tx)
        .await?;
    }
    sqlx::query(
        "UPDATE dictionary_items SET origin = 'user'
         WHERE dict_type = ? AND origin = 'unknown'",
    )
    .bind(dict_type)
    .execute(&mut *tx)
    .await?;
    let total: (i64,) = sqlx::query_as("SELECT COUNT(*) FROM dictionary_items WHERE dict_type = ?")
        .bind(dict_type)
        .fetch_one(&mut *tx)
        .await?;
    tx.commit().await?;
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
    origin: String,
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
            origin: self.origin,
        }
    }
}
