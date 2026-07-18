use crate::get_db;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sqlx::{FromRow, Sqlite, Transaction};
use std::collections::HashSet;

const PERSONAL_RECORDS_VERSION: i64 = 1;
const MAX_PERSONAL_SNAPSHOT_BYTES: usize = 8 * 1024 * 1024;
const MAX_PERSONAL_SNAPSHOT_SESSIONS: usize = 5_000;
const MAX_PERSONAL_SNAPSHOT_LOGS: usize = 100_000;

const SESSION_COLUMNS: &[&str] = &[
    "session_id",
    "title",
    "status",
    "created_at",
    "updated_at",
    "closed_at",
    "deleted_at",
];

const LOG_COLUMNS: &[&str] = &[
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
    "remarks",
    "created_at",
    "updated_at",
    "deleted_at",
    "source_device_id",
];

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, FromRow)]
#[serde(deny_unknown_fields)]
struct PersonalSessionRow {
    session_id: String,
    title: String,
    status: String,
    created_at: String,
    updated_at: String,
    closed_at: Option<String>,
    deleted_at: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, FromRow)]
#[serde(deny_unknown_fields)]
struct PersonalLogRow {
    sync_id: String,
    session_id: String,
    time: String,
    controller: String,
    callsign: String,
    rst_sent: Option<String>,
    rst_rcvd: Option<String>,
    qth: Option<String>,
    device: Option<String>,
    power: Option<String>,
    antenna: Option<String>,
    height: Option<String>,
    remarks: Option<String>,
    created_at: String,
    updated_at: String,
    deleted_at: Option<String>,
    source_device_id: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct PersonalRecordsSnapshot {
    version: i64,
    #[serde(rename = "exportedAt")]
    exported_at: String,
    sessions: Vec<PersonalSessionRow>,
    logs: Vec<PersonalLogRow>,
}

#[derive(Debug, Clone, Copy)]
enum ImportMode {
    Replace,
    Merge,
}

/// Exports only sessions that have no collaboration binding on this
/// installation, together with all of their logs (including tombstones).
///
/// The wire rows mirror the v6 database backup's snake_case session/log
/// metadata, except for installation-local sessions.share_code and logs.id.
pub async fn export_personal_records() -> anyhow::Result<String> {
    let pool = get_db()?;
    let mut tx = pool.begin().await?;

    let sessions = sqlx::query_as::<_, PersonalSessionRow>(
        "SELECT session.session_id, session.title, session.status,
                session.created_at, session.updated_at,
                session.closed_at, session.deleted_at
         FROM sessions session
         WHERE NOT EXISTS (
             SELECT 1 FROM collaboration_bindings binding
             WHERE binding.session_id = session.session_id
         )
         ORDER BY session.created_at ASC, session.session_id ASC",
    )
    .fetch_all(&mut *tx)
    .await?;
    let logs = sqlx::query_as::<_, PersonalLogRow>(
        "SELECT log.sync_id, log.session_id, log.time,
                log.controller, log.callsign, log.rst_sent, log.rst_rcvd,
                log.qth, log.device, log.power, log.antenna, log.height,
                log.remarks, log.created_at, log.updated_at, log.deleted_at,
                log.source_device_id
         FROM logs log
         JOIN sessions session ON session.session_id = log.session_id
         WHERE NOT EXISTS (
             SELECT 1 FROM collaboration_bindings binding
             WHERE binding.session_id = session.session_id
         )
         ORDER BY log.id ASC",
    )
    .fetch_all(&mut *tx)
    .await?;

    tx.commit().await?;
    let snapshot = PersonalRecordsSnapshot {
        version: PERSONAL_RECORDS_VERSION,
        exported_at: chrono::Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Millis, true),
        sessions,
        logs,
    };
    // Local databases can predate the personal-cloud wire protocol. Validate
    // their rows here so invalid legacy data is reported locally instead of
    // producing a snapshot that the server rejects after upload.
    validate_snapshot(&snapshot)?;
    Ok(serde_json::to_string(&snapshot)?)
}

/// Atomically replaces all local-only sessions and logs with a personal cloud
/// snapshot. Collaboration replicas and every other table remain untouched.
pub async fn replace_personal_records(json_data: String) -> anyhow::Result<String> {
    import_personal_records(json_data, ImportMode::Replace, None).await
}

/// Atomically replaces personal records only when their current durable rows
/// still match the snapshot observed before a cloud download. The comparison
/// and replacement share one `BEGIN IMMEDIATE` transaction, so a local save
/// cannot slip between the guard and the destructive clear.
pub async fn replace_personal_records_if_unchanged(
    json_data: String,
    expected_local_json_data: String,
) -> anyhow::Result<String> {
    let expected = parse_snapshot(&expected_local_json_data)?;
    import_personal_records(json_data, ImportMode::Replace, Some(expected)).await
}

/// Atomically merges a personal cloud snapshot by stable session/log identity.
/// Existing local-only records absent from the snapshot remain available.
pub async fn merge_personal_records(json_data: String) -> anyhow::Result<String> {
    import_personal_records(json_data, ImportMode::Merge, None).await
}

async fn import_personal_records(
    json_data: String,
    mode: ImportMode,
    expected_local: Option<PersonalRecordsSnapshot>,
) -> anyhow::Result<String> {
    let snapshot = parse_snapshot(&json_data)?;
    let session_count = snapshot.sessions.len();
    let log_count = snapshot.logs.len();

    let pool = get_db()?;
    let mut tx = pool.begin_with("BEGIN IMMEDIATE").await?;
    if let Some(expected) = expected_local {
        assert_personal_records_unchanged(&mut tx, expected).await?;
    }
    reject_collaboration_identity_collisions(&mut tx, &snapshot).await?;

    if matches!(mode, ImportMode::Replace) {
        clear_personal_records(&mut tx).await?;
    }
    upsert_personal_sessions(&mut tx, &snapshot.sessions).await?;
    upsert_personal_logs(&mut tx, &snapshot.logs).await?;
    verify_installed_snapshot(&mut tx, &snapshot).await?;
    tx.commit().await?;

    Ok(json!({
        "sessionCount": session_count,
        "logCount": log_count,
    })
    .to_string())
}

async fn assert_personal_records_unchanged(
    tx: &mut Transaction<'_, Sqlite>,
    mut expected: PersonalRecordsSnapshot,
) -> anyhow::Result<()> {
    let current_sessions = sqlx::query_as::<_, PersonalSessionRow>(
        "SELECT session.session_id, session.title, session.status,
                session.created_at, session.updated_at,
                session.closed_at, session.deleted_at
         FROM sessions session
         WHERE NOT EXISTS (
             SELECT 1 FROM collaboration_bindings binding
             WHERE binding.session_id = session.session_id
         )
         ORDER BY session.session_id ASC",
    )
    .fetch_all(&mut **tx)
    .await?;
    let current_logs = sqlx::query_as::<_, PersonalLogRow>(
        "SELECT log.sync_id, log.session_id, log.time,
                log.controller, log.callsign, log.rst_sent, log.rst_rcvd,
                log.qth, log.device, log.power, log.antenna, log.height,
                log.remarks, log.created_at, log.updated_at, log.deleted_at,
                log.source_device_id
         FROM logs log
         JOIN sessions session ON session.session_id = log.session_id
         WHERE NOT EXISTS (
             SELECT 1 FROM collaboration_bindings binding
             WHERE binding.session_id = session.session_id
         )
         ORDER BY log.session_id ASC, log.sync_id ASC",
    )
    .fetch_all(&mut **tx)
    .await?;

    expected
        .sessions
        .sort_by(|left, right| left.session_id.cmp(&right.session_id));
    expected.logs.sort_by(|left, right| {
        left.session_id
            .cmp(&right.session_id)
            .then_with(|| left.sync_id.cmp(&right.sync_id))
    });
    if current_sessions != expected.sessions || current_logs != expected.logs {
        anyhow::bail!("PERSONAL_RECORDS_LOCAL_CHANGED");
    }
    Ok(())
}

fn parse_snapshot(json_data: &str) -> anyhow::Result<PersonalRecordsSnapshot> {
    let value: Value = serde_json::from_str(json_data)
        .map_err(|_| anyhow::anyhow!("PERSONAL_RECORDS_INVALID_FORMAT"))?;
    validate_wire_shape(&value)?;
    let snapshot: PersonalRecordsSnapshot = serde_json::from_value(value)
        .map_err(|_| anyhow::anyhow!("PERSONAL_RECORDS_INVALID_FORMAT"))?;
    validate_snapshot(&snapshot)?;
    Ok(snapshot)
}

fn validate_wire_shape(value: &Value) -> anyhow::Result<()> {
    let object = value
        .as_object()
        .ok_or_else(|| anyhow::anyhow!("PERSONAL_RECORDS_INVALID_FORMAT"))?;
    for key in object.keys() {
        if !["version", "exportedAt", "sessions", "logs"].contains(&key.as_str()) {
            anyhow::bail!("PERSONAL_RECORDS_UNKNOWN_FIELD:{key}");
        }
    }
    for key in ["version", "exportedAt", "sessions", "logs"] {
        if !object.contains_key(key) {
            anyhow::bail!("PERSONAL_RECORDS_MISSING_FIELD:{key}");
        }
    }
    validate_rows_shape(object.get("sessions"), "sessions", SESSION_COLUMNS)?;
    validate_rows_shape(object.get("logs"), "logs", LOG_COLUMNS)?;
    Ok(())
}

fn validate_rows_shape(value: Option<&Value>, table: &str, columns: &[&str]) -> anyhow::Result<()> {
    let rows = value
        .and_then(Value::as_array)
        .ok_or_else(|| anyhow::anyhow!("PERSONAL_RECORDS_INVALID_TABLE:{table}"))?;
    for row in rows {
        let fields = row
            .as_object()
            .ok_or_else(|| anyhow::anyhow!("PERSONAL_RECORDS_INVALID_ROW:{table}"))?;
        for field in fields.keys() {
            if !columns.contains(&field.as_str()) {
                anyhow::bail!("PERSONAL_RECORDS_UNKNOWN_COLUMN:{table}.{field}");
            }
        }
        for column in columns {
            if !fields.contains_key(*column) {
                anyhow::bail!("PERSONAL_RECORDS_MISSING_COLUMN:{table}.{column}");
            }
        }
    }
    Ok(())
}

fn validate_snapshot(snapshot: &PersonalRecordsSnapshot) -> anyhow::Result<()> {
    if snapshot.version != PERSONAL_RECORDS_VERSION {
        anyhow::bail!("PERSONAL_RECORDS_UNSUPPORTED_VERSION:{}", snapshot.version);
    }
    if snapshot.sessions.len() > MAX_PERSONAL_SNAPSHOT_SESSIONS {
        anyhow::bail!("PERSONAL_RECORDS_TOO_MANY_SESSIONS");
    }
    if snapshot.logs.len() > MAX_PERSONAL_SNAPSHOT_LOGS {
        anyhow::bail!("PERSONAL_RECORDS_TOO_MANY_LOGS");
    }
    validate_rfc3339("exportedAt", &snapshot.exported_at)?;

    let mut session_ids = HashSet::with_capacity(snapshot.sessions.len());
    for session in &snapshot.sessions {
        validate_stable_id("sessions.session_id", &session.session_id)?;
        validate_string_length("sessions.title", &session.title, 1, 500)?;
        if !["active", "closed", "archived"].contains(&session.status.as_str()) {
            anyhow::bail!("PERSONAL_RECORDS_INVALID_SESSION_STATUS");
        }
        validate_rfc3339("sessions.created_at", &session.created_at)?;
        validate_rfc3339("sessions.updated_at", &session.updated_at)?;
        validate_optional_rfc3339("sessions.closed_at", session.closed_at.as_deref())?;
        validate_optional_rfc3339("sessions.deleted_at", session.deleted_at.as_deref())?;
        if !session_ids.insert(session.session_id.as_str()) {
            anyhow::bail!(
                "PERSONAL_RECORDS_DUPLICATE_SESSION_ID:{}",
                session.session_id
            );
        }
    }

    let mut log_ids = HashSet::with_capacity(snapshot.logs.len());
    for log in &snapshot.logs {
        validate_stable_id("logs.sync_id", &log.sync_id)?;
        validate_stable_id("logs.session_id", &log.session_id)?;
        validate_string_length("logs.controller", &log.controller, 1, 32)?;
        validate_string_length("logs.callsign", &log.callsign, 1, 32)?;
        validate_optional_string_length("logs.rst_sent", log.rst_sent.as_deref(), 0, 16)?;
        validate_optional_string_length("logs.rst_rcvd", log.rst_rcvd.as_deref(), 0, 16)?;
        validate_optional_string_length("logs.qth", log.qth.as_deref(), 0, 200)?;
        validate_optional_string_length("logs.device", log.device.as_deref(), 0, 200)?;
        validate_optional_string_length("logs.power", log.power.as_deref(), 0, 64)?;
        validate_optional_string_length("logs.antenna", log.antenna.as_deref(), 0, 200)?;
        validate_optional_string_length("logs.height", log.height.as_deref(), 0, 64)?;
        validate_optional_string_length("logs.remarks", log.remarks.as_deref(), 0, 2_000)?;
        if !session_ids.contains(log.session_id.as_str()) {
            anyhow::bail!("PERSONAL_RECORDS_ORPHAN_LOG:{}", log.sync_id);
        }
        if !is_valid_log_time(&log.time) {
            anyhow::bail!("PERSONAL_RECORDS_INVALID_TIMESTAMP:logs.time");
        }
        validate_rfc3339("logs.created_at", &log.created_at)?;
        validate_rfc3339("logs.updated_at", &log.updated_at)?;
        validate_optional_rfc3339("logs.deleted_at", log.deleted_at.as_deref())?;
        validate_optional_string_length(
            "logs.source_device_id",
            log.source_device_id.as_deref(),
            1,
            128,
        )?;
        if !log_ids.insert(log.sync_id.as_str()) {
            anyhow::bail!("PERSONAL_RECORDS_DUPLICATE_LOG_ID:{}", log.sync_id);
        }
    }
    if serde_json::to_vec(snapshot)?.len() > MAX_PERSONAL_SNAPSHOT_BYTES {
        anyhow::bail!("PERSONAL_RECORDS_TOO_LARGE");
    }
    Ok(())
}

fn validate_string_length(
    field: &str,
    value: &str,
    minimum: usize,
    maximum: usize,
) -> anyhow::Result<()> {
    // JavaScript's String.length counts UTF-16 code units. Match that here so
    // client-side and server-side boundary decisions are identical.
    let length = value.encode_utf16().count();
    if length < minimum || length > maximum {
        anyhow::bail!("PERSONAL_RECORDS_INVALID_LENGTH:{field}:{minimum}:{maximum}");
    }
    Ok(())
}

fn validate_optional_string_length(
    field: &str,
    value: Option<&str>,
    minimum: usize,
    maximum: usize,
) -> anyhow::Result<()> {
    if let Some(value) = value {
        validate_string_length(field, value, minimum, maximum)?;
    }
    Ok(())
}

fn validate_stable_id(field: &str, value: &str) -> anyhow::Result<()> {
    validate_string_length(field, value, 1, 128)?;
    let mut bytes = value.bytes();
    let Some(first) = bytes.next() else {
        anyhow::bail!("PERSONAL_RECORDS_INVALID_STABLE_ID:{field}");
    };
    if !first.is_ascii_alphanumeric()
        || bytes
            .any(|byte| !byte.is_ascii_alphanumeric() && !matches!(byte, b'.' | b'_' | b':' | b'-'))
    {
        anyhow::bail!("PERSONAL_RECORDS_INVALID_STABLE_ID:{field}");
    }
    Ok(())
}

fn validate_rfc3339(field: &str, value: &str) -> anyhow::Result<()> {
    if !is_strict_rfc3339(value) {
        anyhow::bail!("PERSONAL_RECORDS_INVALID_TIMESTAMP:{field}");
    }
    Ok(())
}

fn validate_optional_rfc3339(field: &str, value: Option<&str>) -> anyhow::Result<()> {
    if let Some(value) = value {
        validate_rfc3339(field, value)?;
    }
    Ok(())
}

fn is_valid_log_time(value: &str) -> bool {
    if is_strict_rfc3339(value) {
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

fn is_strict_rfc3339(value: &str) -> bool {
    if value.encode_utf16().count() > 64 {
        return false;
    }
    let bytes = value.as_bytes();
    if bytes.len() < 20
        || bytes.get(4) != Some(&b'-')
        || bytes.get(7) != Some(&b'-')
        || bytes.get(10) != Some(&b'T')
        || bytes.get(13) != Some(&b':')
        || bytes.get(16) != Some(&b':')
        || ![0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17, 18]
            .into_iter()
            .all(|index| bytes.get(index).is_some_and(u8::is_ascii_digit))
    {
        return false;
    }

    let timezone_start = if bytes.last() == Some(&b'Z') {
        bytes.len() - 1
    } else if bytes.len() >= 25 {
        let start = bytes.len() - 6;
        if !matches!(bytes[start], b'+' | b'-')
            || bytes[start + 3] != b':'
            || ![start + 1, start + 2, start + 4, start + 5]
                .into_iter()
                .all(|index| bytes[index].is_ascii_digit())
        {
            return false;
        }
        let offset_hour = (bytes[start + 1] - b'0') * 10 + (bytes[start + 2] - b'0');
        let offset_minute = (bytes[start + 4] - b'0') * 10 + (bytes[start + 5] - b'0');
        if offset_hour > 23 || offset_minute > 59 {
            return false;
        }
        start
    } else {
        return false;
    };

    if timezone_start != 19
        && (timezone_start <= 20
            || bytes[19] != b'.'
            || !bytes[20..timezone_start].iter().all(u8::is_ascii_digit))
    {
        return false;
    }
    let component = |start: usize| (bytes[start] - b'0') * 10 + (bytes[start + 1] - b'0');
    let year = (bytes[0] - b'0') as u16 * 1_000
        + (bytes[1] - b'0') as u16 * 100
        + (bytes[2] - b'0') as u16 * 10
        + (bytes[3] - b'0') as u16;
    let month = component(5);
    let day = component(8);
    let hour = component(11);
    let minute = component(14);
    let second = component(17);
    let leap_year = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
    let days_in_month = match month {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        2 if leap_year => 29,
        2 => 28,
        _ => 0,
    };
    day >= 1 && day <= days_in_month && hour <= 23 && minute <= 59 && second <= 59
}

async fn reject_collaboration_identity_collisions(
    tx: &mut Transaction<'_, Sqlite>,
    snapshot: &PersonalRecordsSnapshot,
) -> anyhow::Result<()> {
    for session in &snapshot.sessions {
        let bound: (i64,) =
            sqlx::query_as("SELECT COUNT(*) FROM collaboration_bindings WHERE session_id = ?")
                .bind(&session.session_id)
                .fetch_one(&mut **tx)
                .await?;
        if bound.0 != 0 {
            anyhow::bail!(
                "PERSONAL_RECORDS_COLLABORATION_SESSION_CONFLICT:{}",
                session.session_id
            );
        }
    }
    for log in &snapshot.logs {
        let bound: (i64,) = sqlx::query_as(
            "SELECT COUNT(*)
             FROM logs existing
             JOIN collaboration_bindings binding
               ON binding.session_id = existing.session_id
             WHERE existing.sync_id = ?",
        )
        .bind(&log.sync_id)
        .fetch_one(&mut **tx)
        .await?;
        if bound.0 != 0 {
            anyhow::bail!(
                "PERSONAL_RECORDS_COLLABORATION_LOG_CONFLICT:{}",
                log.sync_id
            );
        }
    }
    Ok(())
}

async fn clear_personal_records(tx: &mut Transaction<'_, Sqlite>) -> anyhow::Result<()> {
    sqlx::query(
        "DELETE FROM oplog
         WHERE session_id IN (
             SELECT session.session_id
             FROM sessions session
             WHERE NOT EXISTS (
                 SELECT 1 FROM collaboration_bindings binding
                 WHERE binding.session_id = session.session_id
             )
         )",
    )
    .execute(&mut **tx)
    .await?;
    sqlx::query(
        "DELETE FROM logs
         WHERE session_id IN (
             SELECT session.session_id
             FROM sessions session
             WHERE NOT EXISTS (
                 SELECT 1 FROM collaboration_bindings binding
                 WHERE binding.session_id = session.session_id
             )
         )",
    )
    .execute(&mut **tx)
    .await?;
    sqlx::query(
        "DELETE FROM sessions
         WHERE NOT EXISTS (
             SELECT 1 FROM collaboration_bindings binding
             WHERE binding.session_id = sessions.session_id
         )",
    )
    .execute(&mut **tx)
    .await?;
    Ok(())
}

async fn upsert_personal_sessions(
    tx: &mut Transaction<'_, Sqlite>,
    sessions: &[PersonalSessionRow],
) -> anyhow::Result<()> {
    for session in sessions {
        sqlx::query(
            "INSERT INTO sessions (
                session_id, title, status, share_code,
                created_at, updated_at, closed_at, deleted_at
             ) VALUES (?, ?, ?, NULL, ?, ?, ?, ?)
             ON CONFLICT(session_id) DO UPDATE SET
                title = excluded.title,
                status = excluded.status,
                created_at = excluded.created_at,
                updated_at = excluded.updated_at,
                closed_at = excluded.closed_at,
                deleted_at = excluded.deleted_at",
        )
        .bind(&session.session_id)
        .bind(&session.title)
        .bind(&session.status)
        .bind(&session.created_at)
        .bind(&session.updated_at)
        .bind(&session.closed_at)
        .bind(&session.deleted_at)
        .execute(&mut **tx)
        .await?;
    }
    Ok(())
}

async fn upsert_personal_logs(
    tx: &mut Transaction<'_, Sqlite>,
    logs: &[PersonalLogRow],
) -> anyhow::Result<()> {
    for log in logs {
        sqlx::query(
            "INSERT INTO logs (
                sync_id, session_id, time, controller, callsign,
                rst_sent, rst_rcvd, qth, device, power, antenna, height,
                remarks, created_at, updated_at, deleted_at, source_device_id
             ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
             ON CONFLICT(sync_id) DO UPDATE SET
                session_id = excluded.session_id,
                time = excluded.time,
                controller = excluded.controller,
                callsign = excluded.callsign,
                rst_sent = excluded.rst_sent,
                rst_rcvd = excluded.rst_rcvd,
                qth = excluded.qth,
                device = excluded.device,
                power = excluded.power,
                antenna = excluded.antenna,
                height = excluded.height,
                remarks = excluded.remarks,
                created_at = excluded.created_at,
                updated_at = excluded.updated_at,
                deleted_at = excluded.deleted_at,
                source_device_id = excluded.source_device_id",
        )
        .bind(&log.sync_id)
        .bind(&log.session_id)
        .bind(&log.time)
        .bind(&log.controller)
        .bind(&log.callsign)
        .bind(&log.rst_sent)
        .bind(&log.rst_rcvd)
        .bind(&log.qth)
        .bind(&log.device)
        .bind(&log.power)
        .bind(&log.antenna)
        .bind(&log.height)
        .bind(&log.remarks)
        .bind(&log.created_at)
        .bind(&log.updated_at)
        .bind(&log.deleted_at)
        .bind(&log.source_device_id)
        .execute(&mut **tx)
        .await?;
    }
    Ok(())
}

async fn verify_installed_snapshot(
    tx: &mut Transaction<'_, Sqlite>,
    snapshot: &PersonalRecordsSnapshot,
) -> anyhow::Result<()> {
    for session in &snapshot.sessions {
        let stored: (i64,) = sqlx::query_as(
            "SELECT COUNT(*) FROM sessions
             WHERE session_id = ?
               AND NOT EXISTS (
                   SELECT 1 FROM collaboration_bindings binding
                   WHERE binding.session_id = sessions.session_id
               )",
        )
        .bind(&session.session_id)
        .fetch_one(&mut **tx)
        .await?;
        if stored.0 != 1 {
            anyhow::bail!("PERSONAL_RECORDS_INSTALL_VERIFY_FAILED:sessions");
        }
    }
    for log in &snapshot.logs {
        let stored: (i64,) = sqlx::query_as(
            "SELECT COUNT(*) FROM logs
             WHERE sync_id = ? AND session_id = ?",
        )
        .bind(&log.sync_id)
        .bind(&log.session_id)
        .fetch_one(&mut **tx)
        .await?;
        if stored.0 != 1 {
            anyhow::bail!("PERSONAL_RECORDS_INSTALL_VERIFY_FAILED:logs");
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::parse_snapshot;
    use serde_json::{json, Value};

    fn valid_snapshot() -> serde_json::Value {
        json!({
            "version": 1,
            "exportedAt": "2026-07-18T08:00:00.000Z",
            "sessions": [{
                "session_id": "session-1",
                "title": "Session",
                "status": "closed",
                "created_at": "2026-07-18T08:00:00.000Z",
                "updated_at": "2026-07-18T09:00:00.000Z",
                "closed_at": "2026-07-18T09:00:00.000Z",
                "deleted_at": null
            }],
            "logs": [{
                "sync_id": "log-1",
                "session_id": "session-1",
                "time": "2026-07-18T08:30:00.000Z",
                "controller": "BG5CRL",
                "callsign": "BA4AAA",
                "rst_sent": "59",
                "rst_rcvd": "57",
                "qth": null,
                "device": null,
                "power": null,
                "antenna": null,
                "height": null,
                "remarks": null,
                "created_at": "2026-07-18T08:30:00.000Z",
                "updated_at": "2026-07-18T08:30:00.000Z",
                "deleted_at": null,
                "source_device_id": "device-1"
            }]
        })
    }

    #[test]
    fn validates_complete_v1_snapshot_shape() {
        let parsed = parse_snapshot(&valid_snapshot().to_string()).unwrap();
        assert_eq!(parsed.sessions.len(), 1);
        assert_eq!(parsed.logs.len(), 1);

        let mut archived = valid_snapshot();
        archived["sessions"][0]["status"] = json!("archived");
        assert_eq!(
            parse_snapshot(&archived.to_string()).unwrap().sessions[0].status,
            "archived"
        );
    }

    #[test]
    fn rejects_backup_only_and_unknown_fields() {
        let mut with_log_id = valid_snapshot();
        with_log_id["logs"][0]["id"] = json!(17);
        assert!(parse_snapshot(&with_log_id.to_string())
            .unwrap_err()
            .to_string()
            .contains("PERSONAL_RECORDS_UNKNOWN_COLUMN:logs.id"));

        let mut with_share_code = valid_snapshot();
        with_share_code["sessions"][0]["share_code"] = json!("ABC123");
        assert!(parse_snapshot(&with_share_code.to_string())
            .unwrap_err()
            .to_string()
            .contains("PERSONAL_RECORDS_UNKNOWN_COLUMN:sessions.share_code"));
    }

    #[test]
    fn rejects_orphans_duplicates_and_invalid_timestamps() {
        let mut orphan = valid_snapshot();
        orphan["logs"][0]["session_id"] = json!("missing");
        assert!(parse_snapshot(&orphan.to_string())
            .unwrap_err()
            .to_string()
            .contains("PERSONAL_RECORDS_ORPHAN_LOG"));

        let mut duplicate = valid_snapshot();
        let row = duplicate["logs"][0].clone();
        duplicate["logs"].as_array_mut().unwrap().push(row);
        assert!(parse_snapshot(&duplicate.to_string())
            .unwrap_err()
            .to_string()
            .contains("PERSONAL_RECORDS_DUPLICATE_LOG_ID"));

        let mut invalid_timestamp = valid_snapshot();
        invalid_timestamp["sessions"][0]["created_at"] = json!("today");
        assert!(parse_snapshot(&invalid_timestamp.to_string())
            .unwrap_err()
            .to_string()
            .contains("PERSONAL_RECORDS_INVALID_TIMESTAMP:sessions.created_at"));

        let mut invalid_status = valid_snapshot();
        invalid_status["sessions"][0]["status"] = json!("unknown");
        assert!(parse_snapshot(&invalid_status.to_string())
            .unwrap_err()
            .to_string()
            .contains("PERSONAL_RECORDS_INVALID_SESSION_STATUS"));
    }

    #[test]
    fn enforces_wire_string_boundaries_and_legacy_hour_times() {
        for time in [
            "2026-07-18T19:31:59.987+08:00",
            "2024-02-29T00:00:00Z",
            "0:00",
            "8:05",
            "9:05:07",
            "08:05",
            "20:15:59",
        ] {
            let mut snapshot = valid_snapshot();
            snapshot["logs"][0]["time"] = json!(time);
            assert_eq!(
                parse_snapshot(&snapshot.to_string()).unwrap().logs[0].time,
                time
            );
        }
        for time in [
            " 8:05",
            "8:5",
            "24:00",
            "20:60",
            "20:15:60",
            "2026-07-18T19:31:59",
            "2026-07-18 19:31:59Z",
            "2026-02-29T00:00:00Z",
            "2026-07-18T19:31:59+24:00",
        ] {
            let mut snapshot = valid_snapshot();
            snapshot["logs"][0]["time"] = json!(time);
            assert!(parse_snapshot(&snapshot.to_string()).is_err(), "{time}");
        }

        let mut maximum = valid_snapshot();
        let session_id = format!("s{}", "a".repeat(127));
        maximum["sessions"][0]["session_id"] = json!(session_id);
        maximum["sessions"][0]["title"] = json!("t".repeat(500));
        maximum["logs"][0]["session_id"] = maximum["sessions"][0]["session_id"].clone();
        maximum["logs"][0]["sync_id"] = json!(format!("l{}", "b".repeat(127)));
        maximum["logs"][0]["controller"] = json!("c".repeat(32));
        maximum["logs"][0]["callsign"] = json!("x".repeat(32));
        maximum["logs"][0]["rst_sent"] = json!("s".repeat(16));
        maximum["logs"][0]["rst_rcvd"] = json!("r".repeat(16));
        maximum["logs"][0]["qth"] = json!("q".repeat(200));
        maximum["logs"][0]["device"] = json!("d".repeat(200));
        maximum["logs"][0]["power"] = json!("p".repeat(64));
        maximum["logs"][0]["antenna"] = json!("a".repeat(200));
        maximum["logs"][0]["height"] = json!("h".repeat(64));
        maximum["logs"][0]["remarks"] = json!("m".repeat(2_000));
        maximum["logs"][0]["source_device_id"] = json!("i".repeat(128));
        parse_snapshot(&maximum.to_string()).unwrap();

        let mut empty_optional = valid_snapshot();
        for field in [
            "rst_sent", "rst_rcvd", "qth", "device", "power", "antenna", "height", "remarks",
        ] {
            empty_optional["logs"][0][field] = json!("");
        }
        empty_optional["logs"][0]["source_device_id"] = Value::Null;
        parse_snapshot(&empty_optional.to_string()).unwrap();

        let invalid_cases = [
            ("/sessions/0/session_id", json!("")),
            ("/sessions/0/session_id", json!("bad id")),
            (
                "/sessions/0/session_id",
                json!(format!("s{}", "a".repeat(128))),
            ),
            ("/sessions/0/title", json!("")),
            ("/sessions/0/title", json!("t".repeat(501))),
            ("/logs/0/sync_id", json!("_invalid-first-character")),
            ("/logs/0/sync_id", json!(format!("l{}", "b".repeat(128)))),
            ("/logs/0/controller", json!("")),
            ("/logs/0/controller", json!("c".repeat(33))),
            ("/logs/0/callsign", json!("")),
            ("/logs/0/callsign", json!("x".repeat(33))),
            ("/logs/0/rst_sent", json!("s".repeat(17))),
            ("/logs/0/rst_rcvd", json!("r".repeat(17))),
            ("/logs/0/qth", json!("q".repeat(201))),
            ("/logs/0/device", json!("d".repeat(201))),
            ("/logs/0/power", json!("p".repeat(65))),
            ("/logs/0/antenna", json!("a".repeat(201))),
            ("/logs/0/height", json!("h".repeat(65))),
            ("/logs/0/remarks", json!("m".repeat(2_001))),
            ("/logs/0/source_device_id", json!("")),
            ("/logs/0/source_device_id", json!("i".repeat(129))),
            ("/exportedAt", json!("2026-07-18T12:01:02")),
            ("/sessions/0/created_at", json!("2026-07-18 19:30:00Z")),
        ];
        for (pointer, value) in invalid_cases {
            let mut invalid = valid_snapshot();
            *invalid.pointer_mut(pointer).unwrap() = value;
            assert!(parse_snapshot(&invalid.to_string()).is_err(), "{pointer}");
        }
    }
}
