mod frb_generated; /* AUTO INJECTED BY flutter_rust_bridge. This line may not be accurate, and you can change it according to your needs. */
pub mod api;
pub mod db;
pub mod dict;
pub mod models;

use once_cell::sync::OnceCell;
use sqlx::SqlitePool;

static DB_POOL: OnceCell<SqlitePool> = OnceCell::new();

pub async fn init_database(db_path: &str) -> anyhow::Result<()> {
    let pool = SqlitePool::connect(db_path).await?;
    sqlx::query("PRAGMA journal_mode=WAL").execute(&pool).await?;
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
