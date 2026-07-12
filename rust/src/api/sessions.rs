use crate::get_db;
use crate::models::session::Session;

pub async fn create_session(title: String) -> anyhow::Result<Session> {
    let pool = get_db()?;
    let session = Session::new(title);
    sqlx::query(
        "INSERT INTO sessions (session_id, title, status, share_code, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?)",
    )
    .bind(&session.session_id)
    .bind(&session.title)
    .bind(&session.status)
    .bind(&session.share_code)
    .bind(&session.created_at)
    .bind(&session.updated_at)
    .execute(pool)
    .await?;
    Ok(session)
}

pub async fn list_sessions() -> anyhow::Result<Vec<Session>> {
    let pool = get_db()?;
    let rows = sqlx::query_as::<_, SessionRow>(
        "SELECT * FROM sessions WHERE deleted_at IS NULL ORDER BY created_at DESC",
    )
    .fetch_all(pool)
    .await?;
    Ok(rows.into_iter().map(|r| r.into_session()).collect())
}

pub async fn close_session(session_id: String) -> anyhow::Result<()> {
    let pool = get_db()?;
    let mut tx = pool.begin().await?;
    crate::db::collaboration::mutate_session_in_tx(&mut tx, &session_id, "close", None).await?;
    tx.commit().await?;
    Ok(())
}

pub async fn join_session(share_code: String) -> anyhow::Result<Session> {
    let pool = get_db()?;
    let row = sqlx::query_as::<_, SessionRow>(
        "SELECT * FROM sessions WHERE share_code = ? AND deleted_at IS NULL AND status = 'active'",
    )
    .bind(&share_code)
    .fetch_optional(pool)
    .await?
    .ok_or_else(|| anyhow::anyhow!("Session not found"))?;
    Ok(row.into_session())
}

pub async fn update_collaboration_session_title(
    session_id: String,
    title: String,
) -> anyhow::Result<()> {
    crate::db::collaboration::update_session_title(get_db()?, &session_id, &title).await
}

pub async fn reopen_collaboration_session(session_id: String) -> anyhow::Result<()> {
    crate::db::collaboration::reopen_session(get_db()?, &session_id).await
}

#[derive(sqlx::FromRow)]
struct SessionRow {
    session_id: String,
    title: String,
    status: String,
    share_code: Option<String>,
    created_at: String,
    updated_at: String,
    closed_at: Option<String>,
    deleted_at: Option<String>,
}

impl SessionRow {
    fn into_session(self) -> Session {
        Session {
            session_id: self.session_id,
            title: self.title,
            status: self.status,
            share_code: self.share_code,
            created_at: self.created_at,
            updated_at: self.updated_at,
            closed_at: self.closed_at,
            deleted_at: self.deleted_at,
        }
    }
}
