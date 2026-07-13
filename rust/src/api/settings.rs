use crate::get_db;

pub async fn get_setting(key: String) -> anyhow::Result<Option<String>> {
    let pool = get_db()?;
    let row: Option<(String,)> =
        sqlx::query_as("SELECT value FROM settings WHERE key = ?")
            .bind(&key)
            .fetch_optional(pool)
            .await?;
    Ok(row.map(|r| r.0))
}

pub async fn set_setting(key: String, value: String) -> anyhow::Result<()> {
    let pool = get_db()?;
    sqlx::query("INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)")
        .bind(&key)
        .bind(&value)
        .execute(pool)
        .await?;
    Ok(())
}

pub async fn get_all_settings() -> anyhow::Result<Vec<(String, String)>> {
    let pool = get_db()?;
    let rows: Vec<(String, String)> =
        sqlx::query_as("SELECT key, value FROM settings")
            .fetch_all(pool)
            .await?;
    Ok(rows)
}
