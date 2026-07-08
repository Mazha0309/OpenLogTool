pub mod callsign_qth;
pub mod dictionaries;
pub mod export;
pub mod logs;
pub mod sessions;
pub mod settings;

use crate::init_database as rust_init_database;

pub async fn init_database(db_path: String) -> anyhow::Result<()> {
    rust_init_database(&db_path).await
}
