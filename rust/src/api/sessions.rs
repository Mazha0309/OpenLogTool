use crate::get_db;
use crate::models::session::Session;
use sqlx::SqlitePool;

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

/// Reopens a closed, local-only session on this device.
///
/// Collaboration sessions must be reopened through the synchronized
/// collaboration API. To keep the local recorder unambiguous, any other
/// active local-only session is closed in the same transaction.
pub async fn reopen_local_session(session_id: String) -> anyhow::Result<Session> {
    reopen_local_session_from_pool(get_db()?, &session_id).await
}

async fn reopen_local_session_from_pool(
    pool: &SqlitePool,
    session_id: &str,
) -> anyhow::Result<Session> {
    if session_id.trim().is_empty() {
        anyhow::bail!("SESSION_ID_REQUIRED");
    }

    let mut tx = pool.begin().await?;
    let session: Option<(String, Option<String>)> =
        sqlx::query_as("SELECT status, deleted_at FROM sessions WHERE session_id = ?")
            .bind(session_id)
            .fetch_optional(&mut *tx)
            .await?;
    let (status, deleted_at) = session.ok_or_else(|| anyhow::anyhow!("SESSION_NOT_FOUND"))?;
    if deleted_at.is_some() {
        anyhow::bail!("SESSION_DELETED");
    }
    if status != "closed" {
        anyhow::bail!("SESSION_NOT_CLOSED");
    }

    let binding_count: (i64,) =
        sqlx::query_as("SELECT COUNT(*) FROM collaboration_bindings WHERE session_id = ?")
            .bind(session_id)
            .fetch_one(&mut *tx)
            .await?;
    if binding_count.0 != 0 {
        anyhow::bail!("LOCAL_REOPEN_COLLABORATION_FORBIDDEN");
    }

    let now = chrono::Utc::now().to_rfc3339();
    // A remote collaboration session may remain active alongside the local
    // recorder. This replacement strategy only closes other local-only
    // sessions affected by this reopen operation.
    sqlx::query(
        "UPDATE sessions
         SET status = 'closed', closed_at = ?, updated_at = ?
         WHERE session_id != ?
           AND status = 'active'
           AND deleted_at IS NULL
           AND NOT EXISTS (
               SELECT 1 FROM collaboration_bindings binding
               WHERE binding.session_id = sessions.session_id
           )",
    )
    .bind(&now)
    .bind(&now)
    .bind(session_id)
    .execute(&mut *tx)
    .await?;
    sqlx::query(
        "UPDATE sessions
         SET status = 'active', closed_at = NULL, updated_at = ?
         WHERE session_id = ?",
    )
    .bind(&now)
    .bind(session_id)
    .execute(&mut *tx)
    .await?;

    let reopened = sqlx::query_as::<_, SessionRow>(
        "SELECT * FROM sessions WHERE session_id = ? AND deleted_at IS NULL",
    )
    .bind(session_id)
    .fetch_one(&mut *tx)
    .await?
    .into_session();
    tx.commit().await?;
    Ok(reopened)
}

/// Permanently removes a closed session from this device.
///
/// This is deliberately a local-only operation. Deleting the collaboration
/// binding also cascades through every local replica table, but no mutation is
/// sent to the server and the shared server session is left untouched.
pub async fn hard_delete_session(session_id: String) -> anyhow::Result<()> {
    hard_delete_session_from_pool(get_db()?, &session_id).await
}

async fn hard_delete_session_from_pool(pool: &SqlitePool, session_id: &str) -> anyhow::Result<()> {
    if session_id.trim().is_empty() {
        anyhow::bail!("SESSION_ID_REQUIRED");
    }

    let mut tx = pool.begin().await?;
    let session: Option<(String,)> =
        sqlx::query_as("SELECT status FROM sessions WHERE session_id = ?")
            .bind(session_id)
            .fetch_optional(&mut *tx)
            .await?;
    let (status,) = session.ok_or_else(|| anyhow::anyhow!("SESSION_NOT_FOUND"))?;
    if status == "active" {
        anyhow::bail!("SESSION_ACTIVE_DELETE_FORBIDDEN");
    }

    // The replica tables all reference collaboration_bindings with ON DELETE
    // CASCADE. Removing the binding first clears shadows, outbox entries,
    // applied events, conflicts, live drafts, and offline records atomically.
    sqlx::query("DELETE FROM collaboration_bindings WHERE session_id = ?")
        .bind(session_id)
        .execute(&mut *tx)
        .await?;
    // logs and the legacy oplog predate foreign keys and need explicit cleanup.
    sqlx::query("DELETE FROM logs WHERE session_id = ?")
        .bind(session_id)
        .execute(&mut *tx)
        .await?;
    sqlx::query("DELETE FROM oplog WHERE session_id = ?")
        .bind(session_id)
        .execute(&mut *tx)
        .await?;
    sqlx::query("DELETE FROM sessions WHERE session_id = ?")
        .bind(session_id)
        .execute(&mut *tx)
        .await?;

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

#[cfg(test)]
mod tests {
    use super::{hard_delete_session_from_pool, reopen_local_session_from_pool};
    use crate::db::migrations;
    use sqlx::sqlite::{SqliteConnectOptions, SqlitePoolOptions};
    use sqlx::SqlitePool;
    use std::str::FromStr;

    const NOW: &str = "2026-07-13T08:00:00Z";

    async fn setup() -> SqlitePool {
        let options = SqliteConnectOptions::from_str("sqlite::memory:")
            .unwrap()
            .foreign_keys(true);
        let pool = SqlitePoolOptions::new()
            .max_connections(1)
            .connect_with(options)
            .await
            .unwrap();
        migrations::run(&pool).await.unwrap();
        pool
    }

    async fn insert_session(pool: &SqlitePool, id: &str, status: &str) {
        sqlx::query(
            "INSERT INTO sessions (
                session_id, title, status, created_at, updated_at, closed_at
             ) VALUES (?, ?, ?, ?, ?, ?)",
        )
        .bind(id)
        .bind(format!("Session {id}"))
        .bind(status)
        .bind(NOW)
        .bind(NOW)
        .bind((status != "active").then_some(NOW))
        .execute(pool)
        .await
        .unwrap();
    }

    #[tokio::test]
    async fn hard_delete_rejects_an_active_session_without_changing_it() {
        let pool = setup().await;
        insert_session(&pool, "active-session", "active").await;

        let error = hard_delete_session_from_pool(&pool, "active-session")
            .await
            .unwrap_err()
            .to_string();

        assert!(error.contains("SESSION_ACTIVE_DELETE_FORBIDDEN"));
        let count: (i64,) =
            sqlx::query_as("SELECT COUNT(*) FROM sessions WHERE session_id = 'active-session'")
                .fetch_one(&pool)
                .await
                .unwrap();
        assert_eq!(count.0, 1);
    }

    #[tokio::test]
    async fn local_reopen_activates_closed_session_and_closes_other_local_active() {
        let pool = setup().await;
        insert_session(&pool, "closed-session", "closed").await;
        insert_session(&pool, "local-active", "active").await;
        insert_session(&pool, "remote-active", "active").await;
        sqlx::query(
            "INSERT INTO collaboration_bindings (
                server_instance_id, server_origin, account_id, session_id,
                membership_id, membership_version, role, replica_state,
                joined_at, updated_at
             ) VALUES (
                'server', 'https://example.test', 'account', 'remote-active',
                'membership', 1, 'owner', 'ready', ?, ?
             )",
        )
        .bind(NOW)
        .bind(NOW)
        .execute(&pool)
        .await
        .unwrap();

        reopen_local_session_from_pool(&pool, "closed-session")
            .await
            .unwrap();

        let reopened: (String, Option<String>, String) = sqlx::query_as(
            "SELECT status, closed_at, updated_at FROM sessions WHERE session_id = ?",
        )
        .bind("closed-session")
        .fetch_one(&pool)
        .await
        .unwrap();
        assert_eq!(reopened.0, "active");
        assert_eq!(reopened.1, None);
        assert_ne!(reopened.2, NOW);

        let local_active: (String, Option<String>) = sqlx::query_as(
            "SELECT status, closed_at FROM sessions WHERE session_id = 'local-active'",
        )
        .fetch_one(&pool)
        .await
        .unwrap();
        assert_eq!(local_active.0, "closed");
        assert!(local_active.1.is_some());

        let remote_active: (String, Option<String>) = sqlx::query_as(
            "SELECT status, closed_at FROM sessions WHERE session_id = 'remote-active'",
        )
        .fetch_one(&pool)
        .await
        .unwrap();
        assert_eq!(remote_active.0, "active");
        assert_eq!(remote_active.1, None);
    }

    #[tokio::test]
    async fn local_reopen_rolls_back_other_session_changes_when_target_update_fails() {
        let pool = setup().await;
        insert_session(&pool, "closed-session", "closed").await;
        insert_session(&pool, "local-active", "active").await;
        sqlx::query(
            "CREATE TRIGGER fail_reopen_target
             BEFORE UPDATE ON sessions
             WHEN OLD.session_id = 'closed-session' AND NEW.status = 'active'
             BEGIN
               SELECT RAISE(ABORT, 'forced reopen failure');
             END",
        )
        .execute(&pool)
        .await
        .unwrap();

        let error = reopen_local_session_from_pool(&pool, "closed-session")
            .await
            .unwrap_err()
            .to_string();

        assert!(error.contains("forced reopen failure"));
        let sessions: Vec<(String, String, Option<String>, String)> = sqlx::query_as(
            "SELECT session_id, status, closed_at, updated_at
             FROM sessions ORDER BY session_id",
        )
        .fetch_all(&pool)
        .await
        .unwrap();
        assert_eq!(
            sessions,
            vec![
                (
                    "closed-session".to_string(),
                    "closed".to_string(),
                    Some(NOW.to_string()),
                    NOW.to_string(),
                ),
                (
                    "local-active".to_string(),
                    "active".to_string(),
                    None,
                    NOW.to_string(),
                ),
            ]
        );
    }

    #[tokio::test]
    async fn local_reopen_rejects_archived_session() {
        let pool = setup().await;
        insert_session(&pool, "archived-session", "archived").await;

        let error = reopen_local_session_from_pool(&pool, "archived-session")
            .await
            .unwrap_err()
            .to_string();

        assert!(error.contains("SESSION_NOT_CLOSED"));
        let session: (String, Option<String>) = sqlx::query_as(
            "SELECT status, closed_at FROM sessions WHERE session_id = 'archived-session'",
        )
        .fetch_one(&pool)
        .await
        .unwrap();
        assert_eq!(session.0, "archived");
        assert!(session.1.is_some());
    }

    #[tokio::test]
    async fn local_reopen_rejects_collaboration_session_without_changes() {
        let pool = setup().await;
        insert_session(&pool, "collaboration-session", "closed").await;
        insert_session(&pool, "local-active", "active").await;
        sqlx::query(
            "INSERT INTO collaboration_bindings (
                server_instance_id, server_origin, account_id, session_id,
                membership_id, membership_version, role, replica_state,
                joined_at, updated_at
             ) VALUES (
                'server', 'https://example.test', 'account', 'collaboration-session',
                'membership', 1, 'owner', 'ready', ?, ?
             )",
        )
        .bind(NOW)
        .bind(NOW)
        .execute(&pool)
        .await
        .unwrap();

        let error = reopen_local_session_from_pool(&pool, "collaboration-session")
            .await
            .unwrap_err()
            .to_string();

        assert!(error.contains("LOCAL_REOPEN_COLLABORATION_FORBIDDEN"));
        let statuses: Vec<(String, String)> =
            sqlx::query_as("SELECT session_id, status FROM sessions ORDER BY session_id")
                .fetch_all(&pool)
                .await
                .unwrap();
        assert_eq!(
            statuses,
            vec![
                ("collaboration-session".to_string(), "closed".to_string()),
                ("local-active".to_string(), "active".to_string()),
            ]
        );
    }

    #[tokio::test]
    async fn hard_delete_removes_closed_session_logs_and_replica_state() {
        let pool = setup().await;
        insert_session(&pool, "closed-session", "closed").await;
        insert_session(&pool, "other-session", "active").await;

        sqlx::query(
            "INSERT INTO logs (
                sync_id, session_id, time, controller, callsign,
                created_at, updated_at
             ) VALUES ('closed-log', 'closed-session', ?, 'BG5CRL', 'BA4AAA', ?, ?)",
        )
        .bind(NOW)
        .bind(NOW)
        .bind(NOW)
        .execute(&pool)
        .await
        .unwrap();
        sqlx::query(
            "INSERT INTO oplog (
                session_id, op_type, entity_type, entity_id, data, created_at
             ) VALUES ('closed-session', 'update', 'log', 'closed-log', '{}', ?)",
        )
        .bind(NOW)
        .execute(&pool)
        .await
        .unwrap();
        sqlx::query(
            "INSERT INTO collaboration_bindings (
                server_instance_id, server_origin, account_id, session_id,
                membership_id, membership_version, role, replica_state,
                joined_at, updated_at
             ) VALUES (
                'server', 'https://example.test', 'account', 'closed-session',
                'membership', 1, 'editor', 'ready', ?, ?
             )",
        )
        .bind(NOW)
        .bind(NOW)
        .execute(&pool)
        .await
        .unwrap();
        sqlx::query(
            "INSERT INTO entity_shadows (
                server_instance_id, account_id, session_id, entity_type,
                entity_id, server_version, last_event_seq, server_json
             ) VALUES (
                'server', 'account', 'closed-session', 'session',
                'closed-session', 1, 1, '{}'
             )",
        )
        .execute(&pool)
        .await
        .unwrap();
        sqlx::query(
            "INSERT INTO sync_outbox (
                server_instance_id, account_id, session_id, mutation_id,
                entity_type, entity_id, operation, base_version, observed_seq,
                payload_json, state, created_at, updated_at
             ) VALUES (
                'server', 'account', 'closed-session', 'mutation',
                'session', 'closed-session', 'close', 1, 1,
                '{}', 'conflict', ?, ?
             )",
        )
        .bind(NOW)
        .bind(NOW)
        .execute(&pool)
        .await
        .unwrap();
        sqlx::query(
            "INSERT INTO applied_events (
                server_instance_id, account_id, session_id, event_id,
                event_seq, mutation_id, applied_at
             ) VALUES (
                'server', 'account', 'closed-session', 'event', 1, NULL, ?
             )",
        )
        .bind(NOW)
        .execute(&pool)
        .await
        .unwrap();
        sqlx::query(
            "INSERT INTO sync_conflicts (
                conflict_id, server_instance_id, account_id, session_id,
                entity_type, entity_id, mutation_id, base_version,
                remote_version, local_json, remote_json,
                conflicting_fields_json, state, created_at
             ) VALUES (
                'conflict', 'server', 'account', 'closed-session',
                'session', 'closed-session', 'mutation', 1, 2,
                '{}', '{}', '[]', 'open', ?
             )",
        )
        .bind(NOW)
        .execute(&pool)
        .await
        .unwrap();
        sqlx::query(
            "INSERT INTO collaboration_live_drafts (
                server_instance_id, account_id, session_id, draft_id,
                draft_version, remote_json, local_fields_json,
                field_revisions_json, dirty_fields_json, local_updated_at
             ) VALUES (
                'server', 'account', 'closed-session', 'draft', 1,
                '{}', '{}', '{}', '[]', ?
             )",
        )
        .bind(NOW)
        .execute(&pool)
        .await
        .unwrap();
        sqlx::query(
            "INSERT INTO collaboration_offline_records (
                mutation_id, server_instance_id, account_id, session_id,
                draft_id, expected_draft_version, provisional_ordinal,
                record_json, state, created_at, updated_at
             ) VALUES (
                'offline-mutation', 'server', 'account', 'closed-session',
                'draft', 1, 1, '{}', 'pending', ?, ?
             )",
        )
        .bind(NOW)
        .bind(NOW)
        .execute(&pool)
        .await
        .unwrap();

        hard_delete_session_from_pool(&pool, "closed-session")
            .await
            .unwrap();

        for table in [
            "sessions",
            "logs",
            "oplog",
            "collaboration_bindings",
            "entity_shadows",
            "sync_outbox",
            "applied_events",
            "sync_conflicts",
            "collaboration_live_drafts",
            "collaboration_offline_records",
        ] {
            let query = format!("SELECT COUNT(*) FROM {table} WHERE session_id = ?");
            let count: (i64,) = sqlx::query_as(&query)
                .bind("closed-session")
                .fetch_one(&pool)
                .await
                .unwrap();
            assert_eq!(count.0, 0, "{table} still contains session data");
        }
        let other_count: (i64,) =
            sqlx::query_as("SELECT COUNT(*) FROM sessions WHERE session_id = 'other-session'")
                .fetch_one(&pool)
                .await
                .unwrap();
        assert_eq!(other_count.0, 1);
    }
}
