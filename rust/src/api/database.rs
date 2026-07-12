use crate::get_db;
use serde_json::{json, Value};
use sqlx::{sqlite::SqliteRow, Column, Row, TypeInfo};

const EXPORT_VERSION: i32 = 5;

pub async fn get_database_status() -> anyhow::Result<String> {
    let pool = get_db()?;
    let mut info = String::new();

    info.push_str("=== 应用状态 ===\n");

    let tables = sqlx::query_as::<_, (String,)>(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
    )
    .fetch_all(pool)
    .await?;

    for (name,) in &tables {
        let count: (i64,) = sqlx::query_as(&format!("SELECT COUNT(*) FROM \"{}\"", name))
            .fetch_one(pool)
            .await?;
        info.push_str(&format!("{}: {}\n", name, count.0));
    }

    info.push_str("\n=== 数据库表 ===\n");
    for (name,) in tables {
        let count: (i64,) = match sqlx::query_as(&format!("SELECT COUNT(*) FROM \"{}\"", name))
            .fetch_one(pool)
            .await
        {
            Ok(c) => c,
            Err(_) => (0,),
        };
        info.push_str(&format!("表: {}\n  行数: {}\n", name, count.0));
    }

    Ok(info)
}

pub async fn export_database() -> anyhow::Result<String> {
    let pool = get_db()?;
    let mut tx = pool.begin().await?;

    let logs = query_table(&mut tx, "logs").await?;
    let sessions = query_table(&mut tx, "sessions").await?;
    let dictionary_items = query_table(&mut tx, "dictionary_items").await?;
    let settings = query_table(&mut tx, "settings").await?;
    let oplog = query_table(&mut tx, "oplog").await?;
    let callsign_qth_history = query_table(&mut tx, "callsign_qth_history").await?;
    let collaboration_bindings = query_table(&mut tx, "collaboration_bindings").await?;
    let entity_shadows = query_table(&mut tx, "entity_shadows").await?;
    let sync_outbox = query_table(&mut tx, "sync_outbox").await?;
    let applied_events = query_table(&mut tx, "applied_events").await?;
    let sync_conflicts = query_table(&mut tx, "sync_conflicts").await?;

    let export = json!({
        "version": EXPORT_VERSION,
        "exportedAt": chrono::Utc::now().to_rfc3339(),
        "logs": logs,
        "sessions": sessions,
        "dictionary_items": dictionary_items,
        "settings": settings,
        "oplog": oplog,
        "callsign_qth_history": callsign_qth_history,
        "collaboration_bindings": collaboration_bindings,
        "entity_shadows": entity_shadows,
        "sync_outbox": sync_outbox,
        "applied_events": applied_events,
        "sync_conflicts": sync_conflicts,
    });

    tx.commit().await?;
    Ok(export.to_string())
}

pub async fn import_database(json_data: String) -> anyhow::Result<()> {
    let pool = get_db()?;
    let data: Value = serde_json::from_str(&json_data)?;
    validate_backup(&data)?;

    let mut tx = pool.begin().await?;
    let active_bindings: (i64,) = sqlx::query_as("SELECT COUNT(*) FROM collaboration_bindings")
        .fetch_one(&mut *tx)
        .await?;
    if active_bindings.0 > 0 {
        anyhow::bail!("COLLABORATION_SESSION_READ_ONLY");
    }

    // Clear identity-scoped replica data before its materialized Sessions. The
    // installation-level device_state is intentionally not imported/exported:
    // restoring a backup on another device must not clone its device identity.
    sqlx::query("DELETE FROM entity_shadows")
        .execute(&mut *tx)
        .await?;
    sqlx::query("DELETE FROM collaboration_bindings")
        .execute(&mut *tx)
        .await?;

    // 清空现有数据（保留表结构）
    sqlx::query("DELETE FROM logs").execute(&mut *tx).await?;
    sqlx::query("DELETE FROM sessions")
        .execute(&mut *tx)
        .await?;
    sqlx::query("DELETE FROM dictionary_items")
        .execute(&mut *tx)
        .await?;
    sqlx::query("DELETE FROM settings")
        .execute(&mut *tx)
        .await?;
    sqlx::query("DELETE FROM oplog").execute(&mut *tx).await?;
    sqlx::query("DELETE FROM callsign_qth_history")
        .execute(&mut *tx)
        .await?;

    insert_from_json(&mut tx, "sessions", data.get("sessions")).await?;
    insert_from_json(&mut tx, "logs", data.get("logs")).await?;
    insert_from_json(&mut tx, "dictionary_items", data.get("dictionary_items")).await?;
    insert_from_json(&mut tx, "settings", data.get("settings")).await?;
    insert_from_json(&mut tx, "oplog", data.get("oplog")).await?;
    insert_from_json(
        &mut tx,
        "callsign_qth_history",
        data.get("callsign_qth_history"),
    )
    .await?;
    insert_from_json(
        &mut tx,
        "collaboration_bindings",
        data.get("collaboration_bindings"),
    )
    .await?;
    insert_from_json(&mut tx, "entity_shadows", data.get("entity_shadows")).await?;
    insert_from_json(&mut tx, "sync_outbox", data.get("sync_outbox")).await?;
    insert_from_json(&mut tx, "applied_events", data.get("applied_events")).await?;
    insert_from_json(&mut tx, "sync_conflicts", data.get("sync_conflicts")).await?;

    tx.commit().await?;
    Ok(())
}

fn validate_backup(data: &Value) -> anyhow::Result<()> {
    let object = data
        .as_object()
        .ok_or_else(|| anyhow::anyhow!("未知的数据库备份格式"))?;
    let version = object
        .get("version")
        .and_then(Value::as_i64)
        .ok_or_else(|| anyhow::anyhow!("未知的数据库备份格式"))?;
    if !(1..=i64::from(EXPORT_VERSION)).contains(&version) {
        anyhow::bail!("不支持的数据库备份版本: {version}");
    }

    let mut required_tables = vec![
        "logs",
        "sessions",
        "dictionary_items",
        "settings",
        "oplog",
        "callsign_qth_history",
    ];
    if version >= 4 {
        required_tables.extend(["collaboration_bindings", "entity_shadows"]);
    }
    if version >= 5 {
        required_tables.extend(["sync_outbox", "applied_events", "sync_conflicts"]);
    }
    for table in required_tables {
        let rows = object
            .get(table)
            .and_then(Value::as_array)
            .ok_or_else(|| anyhow::anyhow!("数据库备份缺少有效表: {table}"))?;
        if rows.iter().any(|row| !row.is_object()) {
            anyhow::bail!("数据库备份表包含无效行: {table}");
        }
    }
    Ok(())
}

pub async fn clear_all_data() -> anyhow::Result<()> {
    let pool = get_db()?;
    let mut tx = pool.begin().await?;

    let active_bindings: (i64,) = sqlx::query_as("SELECT COUNT(*) FROM collaboration_bindings")
        .fetch_one(&mut *tx)
        .await?;
    if active_bindings.0 > 0 {
        anyhow::bail!("COLLABORATION_SESSION_READ_ONLY");
    }

    sqlx::query("DELETE FROM entity_shadows")
        .execute(&mut *tx)
        .await?;
    sqlx::query("DELETE FROM collaboration_bindings")
        .execute(&mut *tx)
        .await?;
    sqlx::query("DELETE FROM logs").execute(&mut *tx).await?;
    sqlx::query("DELETE FROM sessions")
        .execute(&mut *tx)
        .await?;
    sqlx::query("DELETE FROM dictionary_items")
        .execute(&mut *tx)
        .await?;
    sqlx::query("DELETE FROM settings")
        .execute(&mut *tx)
        .await?;
    sqlx::query("DELETE FROM oplog").execute(&mut *tx).await?;
    sqlx::query("DELETE FROM callsign_qth_history")
        .execute(&mut *tx)
        .await?;

    tx.commit().await?;
    Ok(())
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
        result.push(row_to_json(&row));
    }
    Ok(result)
}

fn row_to_json(row: &SqliteRow) -> Value {
    let mut map = serde_json::Map::new();
    for (i, column) in row.columns().iter().enumerate() {
        let name = column.name();
        let value: Value = match column.type_info().name() {
            "INTEGER" => row
                .try_get::<Option<i64>, _>(i)
                .ok()
                .flatten()
                .map(|v| json!(v))
                .unwrap_or(Value::Null),
            "REAL" => row
                .try_get::<Option<f64>, _>(i)
                .ok()
                .flatten()
                .map(|v| json!(v))
                .unwrap_or(Value::Null),
            "TEXT" => row
                .try_get::<Option<String>, _>(i)
                .ok()
                .flatten()
                .map(|v| json!(v))
                .unwrap_or(Value::Null),
            "BLOB" => row
                .try_get::<Option<Vec<u8>>, _>(i)
                .ok()
                .flatten()
                .map(|v| json!(v))
                .unwrap_or(Value::Null),
            _ => row
                .try_get::<Option<String>, _>(i)
                .ok()
                .flatten()
                .map(|v| json!(v))
                .unwrap_or(Value::Null),
        };
        map.insert(name.to_string(), value);
    }
    Value::Object(map)
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

        let columns: Vec<String> = map.keys().cloned().collect();
        let placeholders: Vec<String> = (1..=columns.len()).map(|i| format!("?{i}")).collect();

        let sql = format!(
            "INSERT INTO \"{}\" ({}) VALUES ({})",
            table,
            columns.join(", "),
            placeholders.join(", ")
        );

        let mut query = sqlx::query(&sql);
        for col in &columns {
            query = bind_value(query, map.get(col).unwrap_or(&Value::Null));
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
