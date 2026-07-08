mod frb_generated; /* AUTO INJECTED BY flutter_rust_bridge. This line may not be accurate, and you can change it according to your needs. */
pub mod api;
pub mod db;
pub mod dict;
pub mod models;

use once_cell::sync::OnceCell;
use sqlx::sqlite::SqliteConnectOptions;
use sqlx::SqlitePool;
use std::str::FromStr;

static DB_POOL: OnceCell<SqlitePool> = OnceCell::new();

pub async fn init_database(db_path: &str) -> anyhow::Result<()> {
    let conn_str = if db_path.starts_with("sqlite:") || db_path.starts_with("file:") {
        db_path.to_string()
    } else {
        format!("sqlite://{}", db_path)
    };
    let opts = SqliteConnectOptions::from_str(&conn_str)?
        .create_if_missing(true)
        .journal_mode(sqlx::sqlite::SqliteJournalMode::Wal);
    let pool = SqlitePool::connect_with(opts).await?;
    sqlx::query("PRAGMA foreign_keys=ON").execute(&pool).await?;
    db::migrations::run(&pool).await?;
    DB_POOL
        .set(pool)
        .map_err(|_| anyhow::anyhow!("DB already initialized"))?;
    Ok(())
}

pub fn get_db() -> anyhow::Result<&'static SqlitePool> {
    DB_POOL
        .get()
        .ok_or_else(|| anyhow::anyhow!("DB not initialized"))
}
