import 'dart:convert';

/// A lightweight, read-only preview of a Rust database backup.
///
/// Rust remains authoritative for schema validation and performs the actual
/// import atomically. This preview lets the user verify the selected file
/// before authorizing replacement of the local database.
class DatabaseBackupSummary {
  static const int currentFormatVersion = 6;

  const DatabaseBackupSummary({
    required this.formatVersion,
    required this.exportedAt,
    required this.sessionCount,
    required this.logCount,
    required this.dictionaryItemCount,
    required this.collaborationBindingCount,
    required this.pendingSyncCount,
  });

  final int formatVersion;
  final DateTime? exportedAt;
  final int sessionCount;
  final int logCount;
  final int dictionaryItemCount;
  final int collaborationBindingCount;
  final int pendingSyncCount;

  bool get containsCollaborationData => collaborationBindingCount > 0;

  factory DatabaseBackupSummary.parse(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const FormatException('DATABASE_BACKUP_INVALID_JSON');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('DATABASE_BACKUP_INVALID_ROOT');
    }
    final object = decoded;

    final version = object['version'];
    if (version is! int || version < 1 || version > currentFormatVersion) {
      throw const FormatException('DATABASE_BACKUP_INVALID_VERSION');
    }

    List<Map<String, dynamic>> rows(String key, {bool required = true}) {
      final value = object[key];
      if (value == null && !required) return const [];
      if (value is! List) {
        throw FormatException('DATABASE_BACKUP_INVALID_TABLE:$key');
      }
      return value.map((row) {
        if (row is! Map || row.isEmpty) {
          throw FormatException('DATABASE_BACKUP_INVALID_ROW:$key');
        }
        return row.map(
          (field, value) => MapEntry(field.toString(), value),
        );
      }).toList(growable: false);
    }

    int visibleCount(List<Map<String, dynamic>> tableRows) =>
        tableRows.where((row) => row['deleted_at'] == null).length;

    // These tables exist in every supported backup. Replica tables are checked
    // below according to the declared format version, matching Rust's
    // authoritative validation before a destructive confirmation is shown.
    final sessions = rows('sessions');
    final logs = rows('logs');
    final dictionaryItems = rows('dictionary_items');
    rows('settings');
    rows('oplog');
    rows('callsign_qth_history');

    final exportedAtValue = object['exportedAt'];
    final exportedAt = exportedAtValue is String
        ? DateTime.tryParse(exportedAtValue)?.toLocal()
        : null;

    final collaborationBindings =
        rows('collaboration_bindings', required: version >= 4);
    if (version >= 4) rows('entity_shadows');
    final syncOutbox = rows('sync_outbox', required: version >= 5);
    if (version >= 5) {
      rows('applied_events');
      rows('sync_conflicts');
    }
    if (version >= 6) rows('collaboration_live_drafts');
    final offlineRecords =
        rows('collaboration_offline_records', required: version >= 6);
    final unresolvedOfflineRecords = offlineRecords.where(
      (row) => !const {'resolved', 'discarded'}.contains(row['state']),
    );

    return DatabaseBackupSummary(
      formatVersion: version,
      exportedAt: exportedAt,
      sessionCount: visibleCount(sessions),
      logCount: visibleCount(logs),
      dictionaryItemCount: visibleCount(dictionaryItems),
      collaborationBindingCount: collaborationBindings.length,
      pendingSyncCount: syncOutbox.length + unresolvedOfflineRecords.length,
    );
  }
}
