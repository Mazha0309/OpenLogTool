use crate::dict;
use crate::get_db;
use crate::models::dict_item::DictItem;
use anyhow::Context;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use sqlx::{Sqlite, Transaction};
use std::collections::HashSet;

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

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct DictionaryAiSource {
    version: i64,
    state_token: String,
    record_count: i64,
    dictionaries: serde_json::Value,
    history: serde_json::Value,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct DictionaryAiApplyRequest {
    expected_state_token: String,
    operations: Vec<DictionaryAiOperation>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct DictionaryAiOperation {
    action: String,
    dict_type: String,
    source: Option<String>,
    target: String,
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

pub async fn rename_dict_item(
    dict_type: String,
    old_raw: String,
    new_raw: String,
    pinyin: Option<String>,
    abbreviation: Option<String>,
) -> anyhow::Result<DictItem> {
    dict::search::rename_dict_item(&dict_type, &old_raw, &new_raw, pinyin, abbreviation).await
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

/// Returns an aggregate-only data source for the on-device dictionary
/// assistant. No session IDs, timestamps, remarks, or complete log rows leave
/// SQLite. Collaboration and local sessions are intentionally both included.
pub async fn get_dictionary_ai_source() -> anyhow::Result<String> {
    let pool = get_db()?;
    let mut tx = pool.begin().await?;
    let record_count: (i64,) = sqlx::query_as("SELECT COUNT(*) FROM logs WHERE deleted_at IS NULL")
        .fetch_one(&mut *tx)
        .await?;
    let dictionaries = active_dictionary_rows(&mut tx).await?;
    let state_token = dictionary_state_token(&dictionaries);
    let history = serde_json::json!({
        "callsign": aggregate_log_values(&mut tx, "callsign").await?,
        "device": aggregate_log_values(&mut tx, "device").await?,
        "antenna": aggregate_log_values(&mut tx, "antenna").await?,
        "qth": aggregate_log_values(&mut tx, "qth").await?,
    });
    tx.commit().await?;
    let grouped = serde_json::json!({
        "callsign": dictionary_values(&dictionaries, "callsign_dictionary"),
        "device": dictionary_values(&dictionaries, "device_dictionary"),
        "antenna": dictionary_values(&dictionaries, "antenna_dictionary"),
        "qth": dictionary_values(&dictionaries, "qth_dictionary"),
    });
    Ok(serde_json::to_string(&DictionaryAiSource {
        version: 1,
        state_token,
        record_count: record_count.0,
        dictionaries: grouped,
        history,
    })?)
}

/// Applies a reviewed assistant plan in one immediate SQLite transaction.
/// The state token prevents suggestions generated for an older dictionary
/// snapshot from changing newer user edits.
pub async fn apply_dictionary_ai_changes(request_json: String) -> anyhow::Result<String> {
    let request: DictionaryAiApplyRequest =
        serde_json::from_str(&request_json).context("DICTIONARY_AI_APPLY_INVALID_JSON")?;
    if request.operations.is_empty() {
        anyhow::bail!("DICTIONARY_AI_APPLY_EMPTY");
    }
    let pool = get_db()?;
    let mut tx = pool.begin_with("BEGIN IMMEDIATE").await?;
    let current = active_dictionary_rows(&mut tx).await?;
    if dictionary_state_token(&current) != request.expected_state_token {
        anyhow::bail!("DICTIONARY_AI_STATE_CHANGED");
    }

    let mut sources = HashSet::new();
    for operation in &request.operations {
        let dict_type = operation.dict_type.trim();
        if !IMPORTABLE_DICTIONARY_TYPES.contains(&dict_type) {
            anyhow::bail!("DICTIONARY_AI_UNSUPPORTED_TYPE: {}", operation.dict_type);
        }
        let target = operation.target.trim();
        if target.is_empty() {
            anyhow::bail!("DICTIONARY_AI_EMPTY_TARGET");
        }
        if operation.action != "add" {
            let source = operation.source.as_deref().unwrap_or("").trim();
            if source.is_empty() || !sources.insert((dict_type.to_string(), source.to_string())) {
                anyhow::bail!("DICTIONARY_AI_INVALID_SOURCE");
            }
        }
    }

    let now = chrono::Utc::now().to_rfc3339();
    let mut added = 0;
    let mut renamed = 0;
    let mut merged = 0;
    for operation in request.operations {
        let dict_type = operation.dict_type.trim();
        let target = operation.target.trim();
        match operation.action.as_str() {
            "add" => {
                // Multiple observed values may independently normalize to the
                // same canonical term. Later additions are already satisfied.
                if is_active(&mut tx, dict_type, target).await? {
                    continue;
                }
                upsert_ai_target(&mut tx, &operation, target, &now).await?;
                added += 1;
            }
            "rename" => {
                let source = operation.source.as_deref().unwrap().trim();
                if source == target {
                    anyhow::bail!("DICTIONARY_AI_RENAME_SAME_ITEM");
                }
                ensure_active(&mut tx, dict_type, source).await?;
                if is_active(&mut tx, dict_type, target).await? {
                    // A previous operation may already have created this
                    // target, turning the remaining rename into a merge.
                    tombstone(&mut tx, dict_type, source, &now).await?;
                    merged += 1;
                    continue;
                }
                tombstone(&mut tx, dict_type, source, &now).await?;
                upsert_ai_target(&mut tx, &operation, target, &now).await?;
                renamed += 1;
            }
            "merge" => {
                let source = operation.source.as_deref().unwrap().trim();
                if source == target {
                    anyhow::bail!("DICTIONARY_AI_MERGE_SAME_ITEM");
                }
                ensure_active(&mut tx, dict_type, source).await?;
                ensure_active(&mut tx, dict_type, target).await?;
                tombstone(&mut tx, dict_type, source, &now).await?;
                merged += 1;
            }
            _ => anyhow::bail!("DICTIONARY_AI_UNSUPPORTED_ACTION: {}", operation.action),
        }
    }
    tx.commit().await?;
    Ok(serde_json::json!({
        "added": added,
        "renamed": renamed,
        "merged": merged,
    })
    .to_string())
}

type DictionaryStateRow = (
    String,
    String,
    Option<String>,
    Option<String>,
    String,
    String,
);

async fn active_dictionary_rows(
    tx: &mut Transaction<'_, Sqlite>,
) -> anyhow::Result<Vec<DictionaryStateRow>> {
    Ok(sqlx::query_as(
        "SELECT dict_type, raw, pinyin, abbreviation, origin, updated_at
         FROM dictionary_items WHERE deleted_at IS NULL
         ORDER BY dict_type ASC, raw ASC",
    )
    .fetch_all(&mut **tx)
    .await?)
}

fn dictionary_state_token(rows: &[DictionaryStateRow]) -> String {
    let mut digest = Sha256::new();
    for row in rows {
        digest.update(row.0.as_bytes());
        digest.update([0]);
        digest.update(row.1.as_bytes());
        digest.update([0]);
        digest.update(row.2.as_deref().unwrap_or("").as_bytes());
        digest.update([0]);
        digest.update(row.3.as_deref().unwrap_or("").as_bytes());
        digest.update([0]);
        digest.update(row.4.as_bytes());
        digest.update([0]);
        digest.update(row.5.as_bytes());
        digest.update([0xff]);
    }
    format!("{:x}", digest.finalize())
}

fn dictionary_values(rows: &[DictionaryStateRow], dict_type: &str) -> Vec<serde_json::Value> {
    rows.iter()
        .filter(|row| row.0 == dict_type)
        .map(|row| serde_json::json!({"value": row.1, "origin": row.4}))
        .collect()
}

async fn aggregate_log_values(
    tx: &mut Transaction<'_, Sqlite>,
    column: &str,
) -> anyhow::Result<Vec<serde_json::Value>> {
    if !["callsign", "device", "antenna", "qth"].contains(&column) {
        anyhow::bail!("DICTIONARY_AI_INVALID_HISTORY_COLUMN");
    }
    let query = format!(
        "SELECT TRIM({column}), COUNT(*) FROM logs
         WHERE deleted_at IS NULL AND {column} IS NOT NULL AND TRIM({column}) <> ''
         GROUP BY TRIM({column}) ORDER BY COUNT(*) DESC, TRIM({column}) ASC"
    );
    let rows: Vec<(String, i64)> = sqlx::query_as(&query).fetch_all(&mut **tx).await?;
    Ok(rows
        .into_iter()
        .map(|(value, count)| serde_json::json!({"value": value, "count": count}))
        .collect())
}

async fn ensure_active(
    tx: &mut Transaction<'_, Sqlite>,
    dict_type: &str,
    raw: &str,
) -> anyhow::Result<()> {
    let found: Option<(i64,)> = sqlx::query_as(
        "SELECT id FROM dictionary_items
         WHERE dict_type = ? AND raw = ? AND deleted_at IS NULL",
    )
    .bind(dict_type)
    .bind(raw)
    .fetch_optional(&mut **tx)
    .await?;
    if found.is_none() {
        anyhow::bail!("DICTIONARY_AI_SOURCE_NOT_FOUND: {dict_type}/{raw}");
    }
    Ok(())
}

async fn is_active(
    tx: &mut Transaction<'_, Sqlite>,
    dict_type: &str,
    raw: &str,
) -> anyhow::Result<bool> {
    let found: Option<(i64,)> = sqlx::query_as(
        "SELECT id FROM dictionary_items
         WHERE dict_type = ? AND raw = ? AND deleted_at IS NULL",
    )
    .bind(dict_type)
    .bind(raw)
    .fetch_optional(&mut **tx)
    .await?;
    Ok(found.is_some())
}

async fn tombstone(
    tx: &mut Transaction<'_, Sqlite>,
    dict_type: &str,
    raw: &str,
    now: &str,
) -> anyhow::Result<()> {
    let result = sqlx::query(
        "UPDATE dictionary_items SET deleted_at = ?, updated_at = ?
         WHERE dict_type = ? AND raw = ? AND deleted_at IS NULL",
    )
    .bind(now)
    .bind(now)
    .bind(dict_type)
    .bind(raw)
    .execute(&mut **tx)
    .await?;
    if result.rows_affected() != 1 {
        anyhow::bail!("DICTIONARY_AI_WRITE_FAILED");
    }
    Ok(())
}

async fn upsert_ai_target(
    tx: &mut Transaction<'_, Sqlite>,
    operation: &DictionaryAiOperation,
    target: &str,
    now: &str,
) -> anyhow::Result<()> {
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
    .bind(operation.dict_type.trim())
    .bind(target)
    .bind(
        operation
            .pinyin
            .as_deref()
            .map(str::trim)
            .filter(|v| !v.is_empty()),
    )
    .bind(
        operation
            .abbreviation
            .as_deref()
            .map(str::trim)
            .filter(|v| !v.is_empty()),
    )
    .bind(format!("dict-{}", uuid::Uuid::new_v4()))
    .bind(now)
    .bind(now)
    .execute(&mut **tx)
    .await?;
    Ok(())
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
