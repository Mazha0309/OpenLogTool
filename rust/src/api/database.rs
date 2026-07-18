use crate::get_db;
use chrono::DateTime;
use serde_json::{json, Value};
use sqlx::{sqlite::SqliteRow, Column, Row, TypeInfo};

const EXPORT_VERSION: i32 = 7;

pub async fn get_database_status() -> anyhow::Result<String> {
    let pool = get_db()?;
    let mut tx = pool.begin().await?;
    let tables = sqlx::query_as::<_, (String,)>(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
    )
    .fetch_all(&mut *tx)
    .await?;
    let schema_version: (Option<i64>,) = sqlx::query_as("SELECT MAX(version) FROM schema_version")
        .fetch_one(&mut *tx)
        .await?;
    let mut table_status = Vec::with_capacity(tables.len());
    for (name,) in tables {
        let quoted_name = format!("\"{}\"", name.replace('"', "\"\""));
        let count: (i64,) = sqlx::query_as(&format!("SELECT COUNT(*) FROM {quoted_name}"))
            .fetch_one(&mut *tx)
            .await?;
        table_status.push(json!({"name": name, "rowCount": count.0}));
    }

    let sessions: (i64, i64, i64, i64) = sqlx::query_as(
        "SELECT
            COALESCE(SUM(CASE WHEN deleted_at IS NULL AND status = 'active' THEN 1 ELSE 0 END), 0),
            COALESCE(SUM(CASE WHEN deleted_at IS NULL AND status = 'closed' THEN 1 ELSE 0 END), 0),
            COALESCE(SUM(CASE WHEN deleted_at IS NULL AND status = 'archived' THEN 1 ELSE 0 END), 0),
            COALESCE(SUM(CASE WHEN deleted_at IS NOT NULL THEN 1 ELSE 0 END), 0)
         FROM sessions",
    )
    .fetch_one(&mut *tx)
    .await?;
    let logs: (i64, i64) = sqlx::query_as(
        "SELECT
            COALESCE(SUM(CASE WHEN deleted_at IS NULL THEN 1 ELSE 0 END), 0),
            COALESCE(SUM(CASE WHEN deleted_at IS NOT NULL THEN 1 ELSE 0 END), 0)
         FROM logs",
    )
    .fetch_one(&mut *tx)
    .await?;
    let dictionary_rows = sqlx::query_as::<_, (String, i64, i64)>(
        "SELECT dict_type,
            COALESCE(SUM(CASE WHEN deleted_at IS NULL THEN 1 ELSE 0 END), 0),
            COALESCE(SUM(CASE WHEN deleted_at IS NOT NULL THEN 1 ELSE 0 END), 0)
         FROM dictionary_items GROUP BY dict_type ORDER BY dict_type",
    )
    .fetch_all(&mut *tx)
    .await?;
    let mut dictionaries = serde_json::Map::new();
    for (dict_type, active, deleted) in dictionary_rows {
        dictionaries.insert(dict_type, json!({"active": active, "deleted": deleted}));
    }
    let collaboration: (i64, i64, i64, i64, i64) = sqlx::query_as(
        "SELECT
            (SELECT COUNT(*) FROM collaboration_bindings),
            (SELECT COUNT(*) FROM sync_outbox WHERE state IN ('pending', 'sending', 'retrying')),
            (SELECT COUNT(*) FROM sync_conflicts WHERE state != 'resolved'),
            (SELECT COUNT(*) FROM collaboration_offline_records
                WHERE state NOT IN ('resolved', 'discarded')),
            (SELECT COUNT(*) FROM collaboration_live_drafts)",
    )
    .fetch_one(&mut *tx)
    .await?;
    tx.commit().await?;

    Ok(json!({
        "statusVersion": 2,
        "schemaVersion": schema_version.0,
        "backupFormatVersion": EXPORT_VERSION,
        "collectedAt": chrono::Utc::now().to_rfc3339(),
        "localContent": {
            "sessions": {
                "active": sessions.0,
                "closed": sessions.1,
                "archived": sessions.2,
                "deleted": sessions.3,
            },
            "logs": {"active": logs.0, "deleted": logs.1},
            "dictionaries": dictionaries,
        },
        "collaboration": {
            "bindings": collaboration.0,
            "pendingOutbox": collaboration.1,
            "openConflicts": collaboration.2,
            "offlineRecords": collaboration.3,
            "draftCaches": collaboration.4,
        },
        "tables": table_status,
    })
    .to_string())
}

pub async fn export_database() -> anyhow::Result<String> {
    let pool = get_db()?;
    let mut tx = pool.begin().await?;

    let logs = query_table(&mut tx, "logs").await?;
    let sessions = query_table(&mut tx, "sessions").await?;
    let dictionary_items = query_table(&mut tx, "dictionary_items").await?;
    let settings = query_table(&mut tx, "settings").await?;
    let oplog = query_table(&mut tx, "oplog").await?;
    let collaboration_bindings = query_table(&mut tx, "collaboration_bindings").await?;
    let entity_shadows = query_table(&mut tx, "entity_shadows").await?;
    let sync_outbox = query_table(&mut tx, "sync_outbox").await?;
    let applied_events = query_table(&mut tx, "applied_events").await?;
    let sync_conflicts = query_table(&mut tx, "sync_conflicts").await?;
    let collaboration_live_drafts = query_table(&mut tx, "collaboration_live_drafts").await?;
    let collaboration_offline_records =
        query_table(&mut tx, "collaboration_offline_records").await?;

    let export = json!({
        "version": EXPORT_VERSION,
        "exportedAt": chrono::Utc::now().to_rfc3339(),
        "logs": logs,
        "sessions": sessions,
        "dictionary_items": dictionary_items,
        "settings": settings,
        "oplog": oplog,
        "collaboration_bindings": collaboration_bindings,
        "entity_shadows": entity_shadows,
        "sync_outbox": sync_outbox,
        "applied_events": applied_events,
        "sync_conflicts": sync_conflicts,
        "collaboration_live_drafts": collaboration_live_drafts,
        "collaboration_offline_records": collaboration_offline_records,
    });

    tx.commit().await?;
    Ok(export.to_string())
}

pub async fn import_database(json_data: String) -> anyhow::Result<()> {
    let pool = get_db()?;
    let data: Value = serde_json::from_str(&json_data)?;
    validate_backup(&data)?;
    let version = data["version"]
        .as_i64()
        .ok_or_else(|| anyhow::anyhow!("DATABASE_BACKUP_INVALID_FORMAT"))?;

    let mut tx = pool.begin().await?;
    // sync_outbox rows may reference an earlier mutation. JSON array order is
    // not a relational guarantee, so defer FK checks until every table and row
    // has been restored instead of requiring parent-first backup ordering.
    sqlx::query("PRAGMA defer_foreign_keys = ON")
        .execute(&mut *tx)
        .await?;
    // Clear identity-scoped replica data before its materialized Sessions. The
    // installation-level device_state is intentionally not imported/exported:
    // restoring a backup on another device must not clone its device identity.
    clear_database_tables(&mut tx).await?;
    reset_personal_cloud_pairing(&mut tx, "database_replaced").await?;

    insert_from_json(&mut tx, "sessions", data.get("sessions")).await?;
    insert_from_json(&mut tx, "logs", data.get("logs")).await?;
    insert_from_json(&mut tx, "dictionary_items", data.get("dictionary_items")).await?;
    insert_from_json(&mut tx, "settings", data.get("settings")).await?;
    insert_from_json(&mut tx, "oplog", data.get("oplog")).await?;
    if version >= 4 {
        insert_from_json(
            &mut tx,
            "collaboration_bindings",
            data.get("collaboration_bindings"),
        )
        .await?;
        insert_from_json(&mut tx, "entity_shadows", data.get("entity_shadows")).await?;
    }
    if version >= 5 {
        insert_from_json(&mut tx, "sync_outbox", data.get("sync_outbox")).await?;
        insert_from_json(&mut tx, "applied_events", data.get("applied_events")).await?;
        insert_from_json(&mut tx, "sync_conflicts", data.get("sync_conflicts")).await?;
    }
    if version >= 6 {
        insert_from_json(
            &mut tx,
            "collaboration_live_drafts",
            data.get("collaboration_live_drafts"),
        )
        .await?;
        insert_from_json(
            &mut tx,
            "collaboration_offline_records",
            data.get("collaboration_offline_records"),
        )
        .await?;
    }

    validate_restored_database(&mut tx).await?;
    tx.commit().await?;
    Ok(())
}

fn validate_backup(data: &Value) -> anyhow::Result<()> {
    let object = data
        .as_object()
        .ok_or_else(|| anyhow::anyhow!("DATABASE_BACKUP_INVALID_FORMAT"))?;
    let version = object
        .get("version")
        .and_then(Value::as_i64)
        .ok_or_else(|| anyhow::anyhow!("DATABASE_BACKUP_INVALID_FORMAT"))?;
    if !(1..=i64::from(EXPORT_VERSION)).contains(&version) {
        anyhow::bail!("DATABASE_BACKUP_UNSUPPORTED_VERSION:{version}");
    }

    let mut required_tables = vec!["logs", "sessions", "dictionary_items", "settings", "oplog"];
    if version >= 4 {
        required_tables.extend(["collaboration_bindings", "entity_shadows"]);
    }
    if version >= 5 {
        required_tables.extend(["sync_outbox", "applied_events", "sync_conflicts"]);
    }
    if version >= 6 {
        required_tables.extend(["collaboration_live_drafts", "collaboration_offline_records"]);
    }
    for table in required_tables {
        let rows = object
            .get(table)
            .and_then(Value::as_array)
            .ok_or_else(|| anyhow::anyhow!("DATABASE_BACKUP_INVALID_TABLE:{table}"))?;
        for row in rows {
            let fields = row
                .as_object()
                .filter(|fields| !fields.is_empty())
                .ok_or_else(|| anyhow::anyhow!("DATABASE_BACKUP_INVALID_ROW:{table}"))?;
            for field in fields.keys() {
                if !allowed_columns(table).contains(&field.as_str()) {
                    anyhow::bail!("DATABASE_BACKUP_UNKNOWN_COLUMN:{table}.{field}");
                }
            }
        }
    }
    Ok(())
}

pub async fn clear_all_data() -> anyhow::Result<()> {
    let pool = get_db()?;
    let mut tx = pool.begin().await?;
    clear_database_tables(&mut tx).await?;
    reset_personal_cloud_pairing(&mut tx, "local_cleared").await?;

    tx.commit().await?;
    Ok(())
}

async fn clear_database_tables(tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>) -> anyhow::Result<()> {
    // Delete children before parents so this remains correct even when a
    // restored database has foreign-key enforcement enabled.
    for table in [
        "collaboration_offline_records",
        "collaboration_live_drafts",
        "sync_conflicts",
        "applied_events",
        "sync_outbox",
        "entity_shadows",
        "collaboration_bindings",
        "logs",
        "sessions",
        "dictionary_items",
        "settings",
        "oplog",
    ] {
        sqlx::query(&format!("DELETE FROM \"{table}\""))
            .execute(&mut **tx)
            .await?;
    }
    Ok(())
}

async fn reset_personal_cloud_pairing(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    reason: &str,
) -> anyhow::Result<()> {
    sqlx::query("DELETE FROM personal_cloud_baselines")
        .execute(&mut **tx)
        .await?;
    sqlx::query(
        "UPDATE personal_cloud_state
         SET pairing_required_reason = ?, updated_at = ?
         WHERE id = 1",
    )
    .bind(reason)
    .bind(chrono::Utc::now().to_rfc3339())
    .execute(&mut **tx)
    .await?;
    Ok(())
}

fn allowed_columns(table: &str) -> &'static [&'static str] {
    match table {
        "logs" => &[
            "id",
            "sync_id",
            "session_id",
            "time",
            "controller",
            "callsign",
            "rst_sent",
            "rst_rcvd",
            "qth",
            "device",
            "power",
            "antenna",
            "height",
            "created_at",
            "updated_at",
            "deleted_at",
            "source_device_id",
            "remarks",
        ],
        "sessions" => &[
            "session_id",
            "title",
            "status",
            "share_code",
            "created_at",
            "updated_at",
            "closed_at",
            "deleted_at",
        ],
        "dictionary_items" => &[
            "id",
            "dict_type",
            "raw",
            "pinyin",
            "abbreviation",
            "sync_id",
            "created_at",
            "updated_at",
            "deleted_at",
            "origin",
        ],
        "settings" => &["key", "value"],
        "oplog" => &[
            "id",
            "session_id",
            "op_type",
            "entity_type",
            "entity_id",
            "data",
            "device_id",
            "created_at",
            "applied",
        ],
        "collaboration_bindings" => &[
            "server_instance_id",
            "server_origin",
            "account_id",
            "session_id",
            "membership_id",
            "membership_version",
            "role",
            "replica_state",
            "last_applied_seq",
            "last_seen_head_seq",
            "joined_at",
            "updated_at",
            "revoked_at",
        ],
        "entity_shadows" => &[
            "server_instance_id",
            "account_id",
            "session_id",
            "entity_type",
            "entity_id",
            "server_version",
            "last_event_seq",
            "server_json",
            "deleted",
        ],
        "sync_outbox" => &[
            "local_seq",
            "server_instance_id",
            "account_id",
            "session_id",
            "mutation_id",
            "entity_type",
            "entity_id",
            "operation",
            "base_version",
            "observed_seq",
            "base_json",
            "payload_json",
            "state",
            "attempts",
            "next_attempt_at",
            "accepted_event_seq",
            "depends_on_mutation_id",
            "last_error_code",
            "last_error_message",
            "last_error_details_json",
            "created_at",
            "updated_at",
        ],
        "applied_events" => &[
            "server_instance_id",
            "account_id",
            "session_id",
            "event_id",
            "event_seq",
            "mutation_id",
            "applied_at",
        ],
        "sync_conflicts" => &[
            "conflict_id",
            "server_instance_id",
            "account_id",
            "session_id",
            "entity_type",
            "entity_id",
            "mutation_id",
            "base_version",
            "remote_version",
            "base_json",
            "local_json",
            "remote_json",
            "conflicting_fields_json",
            "state",
            "resolution_mutation_id",
            "created_at",
            "resolved_at",
        ],
        "collaboration_live_drafts" => &[
            "server_instance_id",
            "account_id",
            "session_id",
            "draft_id",
            "draft_version",
            "remote_json",
            "local_fields_json",
            "field_revisions_json",
            "dirty_fields_json",
            "client_seq",
            "remote_updated_at",
            "local_updated_at",
        ],
        "collaboration_offline_records" => &[
            "mutation_id",
            "server_instance_id",
            "account_id",
            "session_id",
            "draft_id",
            "expected_draft_version",
            "provisional_ordinal",
            "record_json",
            "state",
            "resolution",
            "last_error_code",
            "created_at",
            "updated_at",
        ],
        _ => &[],
    }
}

async fn validate_restored_database(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
) -> anyhow::Result<()> {
    for table in backup_tables() {
        let required_text = required_text_columns(table);
        let optional_text = optional_text_columns(table);
        let required_integer = required_integer_columns(table);
        let optional_integer = optional_integer_columns(table);

        // Keep the validator exhaustive as the export schema evolves. Adding a
        // column without defining its stored type must fail development/tests,
        // never silently weaken backup validation.
        for column in allowed_columns(table) {
            if !required_text.contains(column)
                && !optional_text.contains(column)
                && !required_integer.contains(column)
                && !optional_integer.contains(column)
            {
                anyhow::bail!("DATABASE_BACKUP_VALIDATOR_MISSING:{table}.{column}");
            }
        }

        for column in required_text {
            ensure_sqlite_column_type(tx, table, column, "text", false).await?;
        }
        for column in optional_text {
            ensure_sqlite_column_type(tx, table, column, "text", true).await?;
        }
        for column in required_integer {
            ensure_sqlite_column_type(tx, table, column, "integer", false).await?;
        }
        for column in optional_integer {
            ensure_sqlite_column_type(tx, table, column, "integer", true).await?;
        }
    }

    for (table, column) in json_object_columns() {
        ensure_json_column_type(tx, table, column, "object").await?;
    }
    for (table, column) in json_array_columns() {
        ensure_json_column_type(tx, table, column, "array").await?;
    }
    for (table, column) in json_any_columns() {
        ensure_json_column_type(tx, table, column, "").await?;
    }

    for (table, columns) in required_identifier_columns() {
        for column in *columns {
            ensure_nonblank_identifier(tx, table, column, false).await?;
        }
    }
    for (table, columns) in optional_identifier_columns() {
        for column in *columns {
            ensure_nonblank_identifier(tx, table, column, true).await?;
        }
    }
    for (table, columns) in required_value_columns() {
        for column in *columns {
            ensure_nonblank_required_value(tx, table, column).await?;
        }
    }
    ensure_dictionary_types(tx).await?;

    for (table, columns) in required_rfc3339_columns() {
        for column in *columns {
            ensure_rfc3339_column(tx, table, column, false).await?;
        }
    }
    for (table, columns) in optional_rfc3339_columns() {
        for column in *columns {
            ensure_rfc3339_column(tx, table, column, true).await?;
        }
    }
    ensure_log_time_column(tx).await?;

    let invalid_status: (i64,) = sqlx::query_as(
        "SELECT COUNT(*) FROM sessions
         WHERE status NOT IN ('active', 'closed', 'archived')",
    )
    .fetch_one(&mut **tx)
    .await?;
    if invalid_status.0 != 0 {
        anyhow::bail!("DATABASE_BACKUP_INVALID_SESSION_STATUS");
    }

    for (child_table, session_column) in [("logs", "session_id"), ("oplog", "session_id")] {
        let orphan_count: (i64,) = sqlx::query_as(&format!(
            "SELECT COUNT(*) FROM \"{child_table}\" child
             WHERE NOT EXISTS (
                 SELECT 1 FROM sessions parent
                 WHERE parent.session_id = child.\"{session_column}\"
             )"
        ))
        .fetch_one(&mut **tx)
        .await?;
        if orphan_count.0 != 0 {
            anyhow::bail!("DATABASE_BACKUP_ORPHAN_SESSION:{child_table}");
        }
    }

    if let Some(violation) = sqlx::query("PRAGMA foreign_key_check")
        .fetch_optional(&mut **tx)
        .await?
    {
        let table = violation
            .try_get::<String, _>(0)
            .unwrap_or_else(|_| "unknown".to_string());
        anyhow::bail!("DATABASE_BACKUP_FOREIGN_KEY_VIOLATION:{table}");
    }
    Ok(())
}

async fn ensure_sqlite_column_type(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    table: &str,
    column: &str,
    expected_type: &str,
    nullable: bool,
) -> anyhow::Result<()> {
    let nullable_clause = if nullable {
        format!("\"{column}\" IS NOT NULL AND ")
    } else {
        String::new()
    };
    let invalid: (i64,) = sqlx::query_as(&format!(
        "SELECT COUNT(*) FROM \"{table}\"
         WHERE {nullable_clause}typeof(\"{column}\") != ?"
    ))
    .bind(expected_type)
    .fetch_one(&mut **tx)
    .await?;
    if invalid.0 != 0 {
        anyhow::bail!("DATABASE_BACKUP_UNREADABLE_COLUMN:{table}.{column}:{expected_type}");
    }
    Ok(())
}

async fn ensure_json_column_type(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    table: &str,
    column: &str,
    expected_json_type: &str,
) -> anyhow::Result<()> {
    let invalid_json = if expected_json_type.is_empty() {
        format!("json_valid(\"{column}\") = 0")
    } else {
        format!(
            "CASE
                WHEN json_valid(\"{column}\") = 0 THEN 1
                WHEN json_type(\"{column}\") != '{expected_json_type}' THEN 1
                ELSE 0
             END = 1"
        )
    };
    let invalid: (i64,) = sqlx::query_as(&format!(
        "SELECT COUNT(*) FROM \"{table}\"
         WHERE \"{column}\" IS NOT NULL
           AND ({invalid_json})"
    ))
    .fetch_one(&mut **tx)
    .await?;
    if invalid.0 != 0 {
        anyhow::bail!("DATABASE_BACKUP_INVALID_JSON_COLUMN:{table}.{column}");
    }
    Ok(())
}

async fn ensure_nonblank_identifier(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    table: &str,
    column: &str,
    nullable: bool,
) -> anyhow::Result<()> {
    let invalid = if nullable {
        let values: Vec<(Option<String>,)> =
            sqlx::query_as(&format!("SELECT \"{column}\" FROM \"{table}\""))
                .fetch_all(&mut **tx)
                .await?;
        values.iter().any(|(value,)| {
            value
                .as_deref()
                .is_some_and(|value| value.trim().is_empty())
        })
    } else {
        let values: Vec<(String,)> =
            sqlx::query_as(&format!("SELECT \"{column}\" FROM \"{table}\""))
                .fetch_all(&mut **tx)
                .await?;
        values.iter().any(|(value,)| value.trim().is_empty())
    };
    if invalid {
        anyhow::bail!("DATABASE_BACKUP_EMPTY_IDENTIFIER:{table}.{column}");
    }
    Ok(())
}

async fn ensure_nonblank_required_value(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    table: &str,
    column: &str,
) -> anyhow::Result<()> {
    let values: Vec<(String,)> = sqlx::query_as(&format!("SELECT \"{column}\" FROM \"{table}\""))
        .fetch_all(&mut **tx)
        .await?;
    if values.iter().any(|(value,)| value.trim().is_empty()) {
        anyhow::bail!("DATABASE_BACKUP_EMPTY_REQUIRED_VALUE:{table}.{column}");
    }
    Ok(())
}

async fn ensure_dictionary_types(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
) -> anyhow::Result<()> {
    let invalid: (i64,) = sqlx::query_as(
        "SELECT COUNT(*) FROM dictionary_items
         WHERE dict_type NOT IN (
             'device_dictionary', 'antenna_dictionary',
             'callsign_dictionary', 'qth_dictionary'
         )",
    )
    .fetch_one(&mut **tx)
    .await?;
    if invalid.0 != 0 {
        anyhow::bail!("DATABASE_BACKUP_INVALID_DICTIONARY_TYPE");
    }
    let invalid_origin: (i64,) = sqlx::query_as(
        "SELECT COUNT(*) FROM dictionary_items
         WHERE origin NOT IN ('unknown', 'builtin', 'user')",
    )
    .fetch_one(&mut **tx)
    .await?;
    if invalid_origin.0 != 0 {
        anyhow::bail!("DATABASE_BACKUP_INVALID_DICTIONARY_ORIGIN");
    }
    Ok(())
}

async fn ensure_rfc3339_column(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    table: &str,
    column: &str,
    nullable: bool,
) -> anyhow::Result<()> {
    let nullable_clause = if nullable {
        format!("WHERE \"{column}\" IS NOT NULL")
    } else {
        String::new()
    };
    let values: Vec<(String,)> = sqlx::query_as(&format!(
        "SELECT \"{column}\" FROM \"{table}\" {nullable_clause}"
    ))
    .fetch_all(&mut **tx)
    .await?;
    if values
        .iter()
        .any(|(value,)| DateTime::parse_from_rfc3339(value).is_err())
    {
        anyhow::bail!("DATABASE_BACKUP_INVALID_TIMESTAMP:{table}.{column}");
    }
    Ok(())
}

async fn ensure_log_time_column(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
) -> anyhow::Result<()> {
    let values: Vec<(String,)> = sqlx::query_as("SELECT time FROM logs")
        .fetch_all(&mut **tx)
        .await?;
    if values.iter().any(|(value,)| !is_valid_log_time(value)) {
        anyhow::bail!("DATABASE_BACKUP_INVALID_LOG_TIME:logs.time");
    }
    Ok(())
}

fn is_valid_log_time(value: &str) -> bool {
    let value = value.trim();
    if DateTime::parse_from_rfc3339(value).is_ok() {
        return true;
    }

    let parts: Vec<&str> = value.split(':').collect();
    if !(2..=3).contains(&parts.len())
        || !(1..=2).contains(&parts[0].len())
        || parts[1].len() != 2
        || (parts.len() == 3 && parts[2].len() != 2)
        || parts
            .iter()
            .any(|part| part.is_empty() || !part.bytes().all(|byte| byte.is_ascii_digit()))
    {
        return false;
    }

    let Ok(hour) = parts[0].parse::<u8>() else {
        return false;
    };
    let Ok(minute) = parts[1].parse::<u8>() else {
        return false;
    };
    let second = if parts.len() == 3 {
        let Ok(second) = parts[2].parse::<u8>() else {
            return false;
        };
        second
    } else {
        0
    };
    hour <= 23 && minute <= 59 && second <= 59
}

fn backup_tables() -> &'static [&'static str] {
    &[
        "logs",
        "sessions",
        "dictionary_items",
        "settings",
        "oplog",
        "collaboration_bindings",
        "entity_shadows",
        "sync_outbox",
        "applied_events",
        "sync_conflicts",
        "collaboration_live_drafts",
        "collaboration_offline_records",
    ]
}

fn required_text_columns(table: &str) -> &'static [&'static str] {
    match table {
        "logs" => &[
            "sync_id",
            "session_id",
            "time",
            "controller",
            "callsign",
            "created_at",
            "updated_at",
        ],
        "sessions" => &["session_id", "title", "status", "created_at", "updated_at"],
        "dictionary_items" => &[
            "dict_type",
            "raw",
            "sync_id",
            "created_at",
            "updated_at",
            "origin",
        ],
        "settings" => &["key", "value"],
        "oplog" => &[
            "session_id",
            "op_type",
            "entity_type",
            "entity_id",
            "data",
            "created_at",
        ],
        "collaboration_bindings" => &[
            "server_instance_id",
            "server_origin",
            "account_id",
            "session_id",
            "membership_id",
            "role",
            "replica_state",
            "joined_at",
            "updated_at",
        ],
        "entity_shadows" => &[
            "server_instance_id",
            "account_id",
            "session_id",
            "entity_type",
            "entity_id",
            "server_json",
        ],
        "sync_outbox" => &[
            "server_instance_id",
            "account_id",
            "session_id",
            "mutation_id",
            "entity_type",
            "entity_id",
            "operation",
            "payload_json",
            "state",
            "created_at",
            "updated_at",
        ],
        "applied_events" => &[
            "server_instance_id",
            "account_id",
            "session_id",
            "event_id",
            "applied_at",
        ],
        "sync_conflicts" => &[
            "conflict_id",
            "server_instance_id",
            "account_id",
            "session_id",
            "entity_type",
            "entity_id",
            "mutation_id",
            "local_json",
            "remote_json",
            "conflicting_fields_json",
            "state",
            "created_at",
        ],
        "collaboration_live_drafts" => &[
            "server_instance_id",
            "account_id",
            "session_id",
            "draft_id",
            "remote_json",
            "local_fields_json",
            "field_revisions_json",
            "dirty_fields_json",
            "local_updated_at",
        ],
        "collaboration_offline_records" => &[
            "mutation_id",
            "server_instance_id",
            "account_id",
            "session_id",
            "draft_id",
            "record_json",
            "state",
            "created_at",
            "updated_at",
        ],
        _ => &[],
    }
}

fn optional_text_columns(table: &str) -> &'static [&'static str] {
    match table {
        "logs" => &[
            "rst_sent",
            "rst_rcvd",
            "qth",
            "device",
            "power",
            "antenna",
            "height",
            "deleted_at",
            "source_device_id",
            "remarks",
        ],
        "sessions" => &["share_code", "closed_at", "deleted_at"],
        "dictionary_items" => &["pinyin", "abbreviation", "deleted_at"],
        "oplog" => &["device_id"],
        "collaboration_bindings" => &["revoked_at"],
        "sync_outbox" => &[
            "base_json",
            "next_attempt_at",
            "depends_on_mutation_id",
            "last_error_code",
            "last_error_message",
            "last_error_details_json",
        ],
        "applied_events" => &["mutation_id"],
        "sync_conflicts" => &["base_json", "resolution_mutation_id", "resolved_at"],
        "collaboration_live_drafts" => &["remote_updated_at"],
        "collaboration_offline_records" => &["resolution", "last_error_code"],
        _ => &[],
    }
}

fn required_integer_columns(table: &str) -> &'static [&'static str] {
    match table {
        "logs" | "dictionary_items" => &["id"],
        "oplog" => &["id", "applied"],
        "collaboration_bindings" => &[
            "membership_version",
            "last_applied_seq",
            "last_seen_head_seq",
        ],
        "entity_shadows" => &["server_version", "last_event_seq", "deleted"],
        "sync_outbox" => &["local_seq", "base_version", "observed_seq", "attempts"],
        "applied_events" => &["event_seq"],
        "sync_conflicts" => &["base_version", "remote_version"],
        "collaboration_live_drafts" => &["draft_version", "client_seq"],
        "collaboration_offline_records" => &["expected_draft_version", "provisional_ordinal"],
        _ => &[],
    }
}

fn optional_integer_columns(table: &str) -> &'static [&'static str] {
    match table {
        "sync_outbox" => &["accepted_event_seq"],
        _ => &[],
    }
}

fn json_object_columns() -> &'static [(&'static str, &'static str)] {
    &[
        ("entity_shadows", "server_json"),
        ("sync_outbox", "base_json"),
        ("sync_outbox", "payload_json"),
        ("sync_conflicts", "base_json"),
        ("sync_conflicts", "local_json"),
        ("sync_conflicts", "remote_json"),
        ("collaboration_live_drafts", "remote_json"),
        ("collaboration_live_drafts", "local_fields_json"),
        ("collaboration_live_drafts", "field_revisions_json"),
        ("collaboration_offline_records", "record_json"),
    ]
}

fn json_array_columns() -> &'static [(&'static str, &'static str)] {
    &[
        ("sync_conflicts", "conflicting_fields_json"),
        ("collaboration_live_drafts", "dirty_fields_json"),
    ]
}

fn json_any_columns() -> &'static [(&'static str, &'static str)] {
    &[
        ("oplog", "data"),
        ("sync_outbox", "last_error_details_json"),
    ]
}

fn required_identifier_columns() -> &'static [(&'static str, &'static [&'static str])] {
    &[
        ("logs", &["sync_id", "session_id"]),
        ("sessions", &["session_id"]),
        ("dictionary_items", &["sync_id"]),
        ("settings", &["key"]),
        ("oplog", &["session_id", "entity_id"]),
        (
            "collaboration_bindings",
            &[
                "server_instance_id",
                "server_origin",
                "account_id",
                "session_id",
                "membership_id",
            ],
        ),
        (
            "entity_shadows",
            &[
                "server_instance_id",
                "account_id",
                "session_id",
                "entity_id",
            ],
        ),
        (
            "sync_outbox",
            &[
                "server_instance_id",
                "account_id",
                "session_id",
                "mutation_id",
                "entity_id",
            ],
        ),
        (
            "applied_events",
            &["server_instance_id", "account_id", "session_id", "event_id"],
        ),
        (
            "sync_conflicts",
            &[
                "conflict_id",
                "server_instance_id",
                "account_id",
                "session_id",
                "entity_id",
                "mutation_id",
            ],
        ),
        (
            "collaboration_live_drafts",
            &["server_instance_id", "account_id", "session_id", "draft_id"],
        ),
        (
            "collaboration_offline_records",
            &[
                "mutation_id",
                "server_instance_id",
                "account_id",
                "session_id",
                "draft_id",
            ],
        ),
    ]
}

fn optional_identifier_columns() -> &'static [(&'static str, &'static [&'static str])] {
    &[
        ("logs", &["source_device_id"]),
        ("oplog", &["device_id"]),
        ("sync_outbox", &["depends_on_mutation_id"]),
        ("applied_events", &["mutation_id"]),
        ("sync_conflicts", &["resolution_mutation_id"]),
    ]
}

fn required_value_columns() -> &'static [(&'static str, &'static [&'static str])] {
    &[
        ("logs", &["controller", "callsign"]),
        ("sessions", &["title"]),
        ("dictionary_items", &["dict_type", "raw"]),
    ]
}

fn required_rfc3339_columns() -> &'static [(&'static str, &'static [&'static str])] {
    &[
        ("logs", &["created_at", "updated_at"]),
        ("sessions", &["created_at", "updated_at"]),
        ("collaboration_bindings", &["joined_at", "updated_at"]),
        ("sync_outbox", &["created_at", "updated_at"]),
        ("applied_events", &["applied_at"]),
        ("sync_conflicts", &["created_at"]),
        ("collaboration_live_drafts", &["local_updated_at"]),
        (
            "collaboration_offline_records",
            &["created_at", "updated_at"],
        ),
    ]
}

fn optional_rfc3339_columns() -> &'static [(&'static str, &'static [&'static str])] {
    &[
        ("logs", &["deleted_at"]),
        ("sessions", &["closed_at", "deleted_at"]),
        ("collaboration_bindings", &["revoked_at"]),
        ("sync_outbox", &["next_attempt_at"]),
        ("sync_conflicts", &["resolved_at"]),
        ("collaboration_live_drafts", &["remote_updated_at"]),
    ]
}

async fn query_table(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    table: &str,
) -> anyhow::Result<Vec<Value>> {
    let rows: Vec<SqliteRow> = sqlx::query(&format!("SELECT * FROM \"{}\"", table))
        .fetch_all(&mut **tx)
        .await?;

    let mut result = Vec::with_capacity(rows.len());
    for row in rows {
        result.push(row_to_json(&row)?);
    }
    Ok(result)
}

fn row_to_json(row: &SqliteRow) -> anyhow::Result<Value> {
    let mut map = serde_json::Map::new();
    for (i, column) in row.columns().iter().enumerate() {
        let name = column.name();
        let type_name = column.type_info().name();
        let value: Value = match type_name {
            "INTEGER" => row
                .try_get::<Option<i64>, _>(i)
                .map_err(|error| export_column_decode_error(name, type_name, error))?
                .map_or(Value::Null, |v| json!(v)),
            "REAL" => row
                .try_get::<Option<f64>, _>(i)
                .map_err(|error| export_column_decode_error(name, type_name, error))?
                .map_or(Value::Null, |v| json!(v)),
            "TEXT" => row
                .try_get::<Option<String>, _>(i)
                .map_err(|error| export_column_decode_error(name, type_name, error))?
                .map_or(Value::Null, |v| json!(v)),
            "BLOB" => row
                .try_get::<Option<Vec<u8>>, _>(i)
                .map_err(|error| export_column_decode_error(name, type_name, error))?
                .map_or(Value::Null, |v| json!(v)),
            _ => row
                .try_get::<Option<String>, _>(i)
                .map_err(|error| export_column_decode_error(name, type_name, error))?
                .map_or(Value::Null, |v| json!(v)),
        };
        map.insert(name.to_string(), value);
    }
    Ok(Value::Object(map))
}

fn export_column_decode_error(column: &str, type_name: &str, error: sqlx::Error) -> anyhow::Error {
    anyhow::anyhow!("DATABASE_BACKUP_EXPORT_UNREADABLE_COLUMN:{column}:{type_name}:{error}")
}

async fn insert_from_json<'a>(
    tx: &mut sqlx::Transaction<'a, sqlx::Sqlite>,
    table: &str,
    data: Option<&Value>,
) -> anyhow::Result<()> {
    let rows = match data {
        Some(Value::Array(arr)) => arr,
        _ => return Ok(()),
    };

    for row in rows {
        let Value::Object(map) = row else { continue };
        if map.is_empty() {
            continue;
        }

        let columns: Vec<&str> = map.keys().map(String::as_str).collect();
        let allowed = allowed_columns(table);
        for column in &columns {
            if !allowed.contains(column) {
                anyhow::bail!("DATABASE_BACKUP_UNKNOWN_COLUMN:{table}.{column}");
            }
        }
        let placeholders: Vec<String> = (1..=columns.len()).map(|i| format!("?{i}")).collect();
        let quoted_columns: Vec<String> = columns
            .iter()
            .map(|column| format!("\"{column}\""))
            .collect();

        let sql = format!(
            "INSERT INTO \"{}\" ({}) VALUES ({})",
            table,
            quoted_columns.join(", "),
            placeholders.join(", ")
        );

        let mut query = sqlx::query(&sql);
        for col in &columns {
            query = bind_value(query, map.get(*col).unwrap_or(&Value::Null));
        }
        query.execute(&mut **tx).await?;
    }

    Ok(())
}

fn bind_value<'a>(
    query: sqlx::query::Query<'a, sqlx::Sqlite, sqlx::sqlite::SqliteArguments<'a>>,
    value: &'a Value,
) -> sqlx::query::Query<'a, sqlx::Sqlite, sqlx::sqlite::SqliteArguments<'a>> {
    match value {
        Value::Null => query.bind(None::<String>),
        Value::Bool(b) => query.bind(*b as i64),
        Value::Number(n) => {
            if let Some(i) = n.as_i64() {
                query.bind(i)
            } else if let Some(f) = n.as_f64() {
                query.bind(f)
            } else {
                query.bind(n.to_string())
            }
        }
        Value::String(s) => query.bind(s.as_str()),
        Value::Array(_) | Value::Object(_) => query.bind(value.to_string()),
    }
}

#[cfg(test)]
mod tests {
    use super::query_table;
    use sqlx::sqlite::SqlitePoolOptions;

    #[tokio::test]
    async fn query_table_propagates_text_decode_errors() {
        let pool = SqlitePoolOptions::new()
            .max_connections(1)
            .connect("sqlite::memory:")
            .await
            .unwrap();
        sqlx::query("CREATE TABLE malformed_export (value TEXT NOT NULL)")
            .execute(&pool)
            .await
            .unwrap();
        sqlx::query("INSERT INTO malformed_export (value) VALUES (CAST(X'80' AS TEXT))")
            .execute(&pool)
            .await
            .unwrap();

        let mut tx = pool.begin().await.unwrap();
        let error = query_table(&mut tx, "malformed_export").await.unwrap_err();

        let message = error.to_string();
        assert!(message.contains("DATABASE_BACKUP_EXPORT_UNREADABLE_COLUMN:value:TEXT"));
        assert!(message.contains("invalid utf-8"));
    }

    #[test]
    fn log_time_accepts_rfc3339_and_historical_clock_values() {
        assert!(super::is_valid_log_time("2026-07-17T10:30:45+08:00"));
        assert!(super::is_valid_log_time("8:05"));
        assert!(super::is_valid_log_time("23:59:59"));
        assert!(!super::is_valid_log_time("24:00"));
        assert!(!super::is_valid_log_time("08:60"));
        assert!(!super::is_valid_log_time("2026-07-17 10:30"));
    }
}
