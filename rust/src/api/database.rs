use crate::get_db;
use serde_json::{json, Value};
use sqlx::{Column, Row, TypeInfo, sqlite::SqliteRow};

const EXPORT_VERSION: i32 = 3;

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

    let logs = query_table(pool, "logs").await?;
    let sessions = query_table(pool, "sessions").await?;
    let dictionary_items = query_table(pool, "dictionary_items").await?;
    let settings = query_table(pool, "settings").await?;
    let oplog = query_table(pool, "oplog").await?;
    let callsign_qth_history = query_table(pool, "callsign_qth_history").await?;

    let export = json!({
        "version": EXPORT_VERSION,
        "exportedAt": chrono::Utc::now().to_rfc3339(),
        "logs": logs,
        "sessions": sessions,
        "dictionary_items": dictionary_items,
        "settings": settings,
        "oplog": oplog,
        "callsign_qth_history": callsign_qth_history,
    });

    Ok(export.to_string())
}

pub async fn import_database(json_data: String) -> anyhow::Result<()> {
    let pool = get_db()?;
    let data: Value = serde_json::from_str(&json_data)?;

    if data.get("version").is_none() {
        anyhow::bail!("未知的数据库备份格式");
    }

    let mut tx = pool.begin().await?;

    // 清空现有数据（保留表结构）
    sqlx::query("DELETE FROM logs").execute(&mut *tx).await?;
    sqlx::query("DELETE FROM sessions").execute(&mut *tx).await?;
    sqlx::query("DELETE FROM dictionary_items").execute(&mut *tx).await?;
    sqlx::query("DELETE FROM settings").execute(&mut *tx).await?;
    sqlx::query("DELETE FROM oplog").execute(&mut *tx).await?;
    sqlx::query("DELETE FROM callsign_qth_history").execute(&mut *tx).await?;

    insert_from_json(&mut tx, "logs", data.get("logs")).await?;
    insert_from_json(&mut tx, "sessions", data.get("sessions")).await?;
    insert_from_json(&mut tx, "dictionary_items", data.get("dictionary_items")).await?;
    insert_from_json(&mut tx, "settings", data.get("settings")).await?;
    insert_from_json(&mut tx, "oplog", data.get("oplog")).await?;
    insert_from_json(&mut tx, "callsign_qth_history", data.get("callsign_qth_history")).await?;

    tx.commit().await?;
    Ok(())
}

pub async fn clear_all_data() -> anyhow::Result<()> {
    let pool = get_db()?;
    let mut tx = pool.begin().await?;

    sqlx::query("DELETE FROM logs").execute(&mut *tx).await?;
    sqlx::query("DELETE FROM sessions").execute(&mut *tx).await?;
    sqlx::query("DELETE FROM dictionary_items").execute(&mut *tx).await?;
    sqlx::query("DELETE FROM settings").execute(&mut *tx).await?;
    sqlx::query("DELETE FROM oplog").execute(&mut *tx).await?;
    sqlx::query("DELETE FROM callsign_qth_history").execute(&mut *tx).await?;

    tx.commit().await?;
    Ok(())
}

async fn query_table(pool: &sqlx::SqlitePool, table: &str) -> anyhow::Result<Vec<Value>> {
    let rows: Vec<SqliteRow> = sqlx::query(&format!("SELECT * FROM \"{}\"", table))
        .fetch_all(pool)
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
