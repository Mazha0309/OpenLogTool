use crate::get_db;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sqlx::{Sqlite, Transaction};
use std::collections::HashSet;

const PERSONAL_DICTIONARY_VERSION: i64 = 1;
const MAX_ITEMS: usize = 100_000;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct DictionaryOverride {
    dict_type: String,
    raw: String,
    origin: String,
    state: String,
    pinyin: Option<String>,
    abbreviation: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct PersonalDictionarySnapshot {
    version: i64,
    exported_at: String,
    items: Vec<DictionaryOverride>,
}

fn wire_type(value: &str) -> Option<&'static str> {
    match value {
        "device_dictionary" | "device" => Some("device"),
        "antenna_dictionary" | "antenna" => Some("antenna"),
        "callsign_dictionary" | "callsign" => Some("callsign"),
        "qth_dictionary" | "qth" => Some("qth"),
        _ => None,
    }
}

fn database_type(value: &str) -> Option<&'static str> {
    match value {
        "device" => Some("device_dictionary"),
        "antenna" => Some("antenna_dictionary"),
        "callsign" => Some("callsign_dictionary"),
        "qth" => Some("qth_dictionary"),
        _ => None,
    }
}

fn validate_snapshot(snapshot: &PersonalDictionarySnapshot) -> anyhow::Result<()> {
    if snapshot.version != PERSONAL_DICTIONARY_VERSION {
        anyhow::bail!(
            "PERSONAL_DICTIONARY_UNSUPPORTED_VERSION:{}",
            snapshot.version
        );
    }
    if snapshot.items.len() > MAX_ITEMS {
        anyhow::bail!("PERSONAL_DICTIONARY_TOO_MANY_ITEMS");
    }
    chrono::DateTime::parse_from_rfc3339(&snapshot.exported_at)
        .map_err(|_| anyhow::anyhow!("PERSONAL_DICTIONARY_INVALID_EXPORTED_AT"))?;
    let mut identities = HashSet::with_capacity(snapshot.items.len());
    for item in &snapshot.items {
        if database_type(&item.dict_type).is_none() {
            anyhow::bail!("PERSONAL_DICTIONARY_INVALID_TYPE:{}", item.dict_type);
        }
        if item.raw.trim().is_empty() || item.raw.len() > 500 {
            anyhow::bail!("PERSONAL_DICTIONARY_INVALID_RAW");
        }
        if !matches!(item.origin.as_str(), "user" | "builtin")
            || !matches!(item.state.as_str(), "active" | "deleted")
            || (item.state == "active" && item.origin != "user")
        {
            anyhow::bail!("PERSONAL_DICTIONARY_INVALID_OVERRIDE");
        }
        if item
            .pinyin
            .as_ref()
            .is_some_and(|value| value.len() > 1_000)
            || item
                .abbreviation
                .as_ref()
                .is_some_and(|value| value.len() > 1_000)
        {
            anyhow::bail!("PERSONAL_DICTIONARY_VALUE_TOO_LONG");
        }
        if !identities.insert((item.dict_type.as_str(), item.raw.as_str())) {
            anyhow::bail!("PERSONAL_DICTIONARY_DUPLICATE_ITEM");
        }
    }
    Ok(())
}

async fn export_in_transaction(
    tx: &mut Transaction<'_, Sqlite>,
) -> anyhow::Result<PersonalDictionarySnapshot> {
    let unknown: (i64,) =
        sqlx::query_as("SELECT COUNT(*) FROM dictionary_items WHERE origin = 'unknown'")
            .fetch_one(&mut **tx)
            .await?;
    if unknown.0 != 0 {
        anyhow::bail!("PERSONAL_DICTIONARY_ORIGIN_NOT_READY");
    }
    let rows = sqlx::query_as::<
        _,
        (
            String,
            String,
            Option<String>,
            Option<String>,
            String,
            Option<String>,
        ),
    >(
        "SELECT dict_type, raw, pinyin, abbreviation, origin, deleted_at
         FROM dictionary_items
         WHERE origin = 'user' OR (origin = 'builtin' AND deleted_at IS NOT NULL)
         ORDER BY dict_type, raw",
    )
    .fetch_all(&mut **tx)
    .await?;
    let items = rows
        .into_iter()
        .map(|row| {
            let deleted = row.5.is_some();
            DictionaryOverride {
                dict_type: wire_type(&row.0).unwrap_or("unknown").to_string(),
                raw: row.1,
                // Tombstones carry identity only. Keeping stale search values
                // would violate the server wire contract and makes a deleted
                // built-in look like editable user content on another device.
                pinyin: (!deleted)
                    .then(|| row.2.filter(|value| !value.is_empty()))
                    .flatten(),
                abbreviation: (!deleted)
                    .then(|| row.3.filter(|value| !value.is_empty()))
                    .flatten(),
                origin: row.4,
                state: if deleted { "deleted" } else { "active" }.to_string(),
            }
        })
        .collect();
    Ok(PersonalDictionarySnapshot {
        version: PERSONAL_DICTIONARY_VERSION,
        exported_at: chrono::Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Millis, true),
        items,
    })
}

pub async fn export_personal_dictionary() -> anyhow::Result<String> {
    let pool = get_db()?;
    let mut tx = pool.begin().await?;
    let snapshot = export_in_transaction(&mut tx).await?;
    tx.commit().await?;
    validate_snapshot(&snapshot)?;
    Ok(serde_json::to_string(&snapshot)?)
}

fn parse_snapshot(value: &str) -> anyhow::Result<PersonalDictionarySnapshot> {
    let parsed: Value = serde_json::from_str(value)
        .map_err(|_| anyhow::anyhow!("PERSONAL_DICTIONARY_INVALID_FORMAT"))?;
    let snapshot: PersonalDictionarySnapshot = serde_json::from_value(parsed)
        .map_err(|_| anyhow::anyhow!("PERSONAL_DICTIONARY_INVALID_FORMAT"))?;
    validate_snapshot(&snapshot)?;
    Ok(snapshot)
}

pub async fn replace_personal_dictionary_if_unchanged(
    json_data: String,
    expected_local_json_data: String,
) -> anyhow::Result<String> {
    let incoming = parse_snapshot(&json_data)?;
    let mut expected = parse_snapshot(&expected_local_json_data)?;
    let pool = get_db()?;
    let mut tx = pool.begin_with("BEGIN IMMEDIATE").await?;
    let mut current = export_in_transaction(&mut tx).await?;
    current.exported_at.clear();
    expected.exported_at.clear();
    if current != expected {
        anyhow::bail!("PERSONAL_DICTIONARY_LOCAL_CHANGED");
    }

    sqlx::query("DELETE FROM dictionary_items WHERE origin = 'user'")
        .execute(&mut *tx)
        .await?;
    sqlx::query(
        "UPDATE dictionary_items SET deleted_at = NULL
         WHERE origin = 'builtin' AND deleted_at IS NOT NULL",
    )
    .execute(&mut *tx)
    .await?;

    let now = chrono::Utc::now().to_rfc3339();
    for item in &incoming.items {
        let dict_type = database_type(&item.dict_type)
            .ok_or_else(|| anyhow::anyhow!("PERSONAL_DICTIONARY_INVALID_TYPE"))?;
        let deleted_at = (item.state == "deleted").then_some(now.as_str());
        sqlx::query(
            "INSERT INTO dictionary_items (
                dict_type, raw, pinyin, abbreviation, sync_id,
                created_at, updated_at, deleted_at, origin
             ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
             ON CONFLICT(dict_type, raw) DO UPDATE SET
                pinyin = excluded.pinyin,
                abbreviation = excluded.abbreviation,
                updated_at = excluded.updated_at,
                deleted_at = excluded.deleted_at,
                origin = excluded.origin",
        )
        .bind(dict_type)
        .bind(&item.raw)
        .bind(&item.pinyin)
        .bind(&item.abbreviation)
        .bind(format!("dict-{}", uuid::Uuid::new_v4()))
        .bind(&now)
        .bind(&now)
        .bind(deleted_at)
        .bind(&item.origin)
        .execute(&mut *tx)
        .await?;
    }
    tx.commit().await?;
    Ok(json!({"itemCount": incoming.items.len()}).to_string())
}
