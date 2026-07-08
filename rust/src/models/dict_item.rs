use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DictItem {
    pub id: Option<i64>,
    pub dict_type: String,
    pub raw: String,
    pub pinyin: Option<String>,
    pub abbreviation: Option<String>,
    pub sync_id: String,
    pub created_at: String,
    pub updated_at: String,
    pub deleted_at: Option<String>,
}

impl DictItem {
    pub fn new(dict_type: String, raw: String) -> Self {
        let now = chrono::Utc::now().to_rfc3339();
        Self {
            id: None,
            dict_type,
            raw,
            pinyin: None,
            abbreviation: None,
            sync_id: format!("dict-{}", uuid::Uuid::new_v4()),
            created_at: now.clone(),
            updated_at: now,
            deleted_at: None,
        }
    }
}
