import 'dart:convert';

/// Semantic snapshot returned by Rust's `get_database_status` API.
///
/// Raw table counts remain available for diagnostics, but application UI
/// should normally present [localContent] and [collaboration] instead. A table
/// being empty is not itself an error (for example, an outbox at zero is the
/// healthy steady state).
class DatabaseStatus {
  const DatabaseStatus({
    required this.statusVersion,
    required this.schemaVersion,
    required this.backupFormatVersion,
    required this.collectedAt,
    required this.localContent,
    required this.collaboration,
    required this.tables,
  });

  final int statusVersion;
  final int? schemaVersion;
  final int? backupFormatVersion;
  final DateTime? collectedAt;
  final DatabaseLocalContentStatus localContent;
  final DatabaseCollaborationStatus collaboration;
  final List<DatabaseTableStatus> tables;

  factory DatabaseStatus.parse(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const FormatException('DATABASE_STATUS_INVALID_JSON');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('DATABASE_STATUS_INVALID_ROOT');
    }
    return DatabaseStatus.fromJson(decoded);
  }

  factory DatabaseStatus.fromJson(Map<String, dynamic> json) {
    final statusVersion = _integer(json['statusVersion']);
    if (statusVersion == null || statusVersion < 2) {
      throw const FormatException('DATABASE_STATUS_UNSUPPORTED_VERSION');
    }
    final localContent = _map(json['localContent'], 'localContent');
    final collaboration = _map(json['collaboration'], 'collaboration');
    final rawTables = json['tables'];
    if (rawTables is! List) {
      throw const FormatException('DATABASE_STATUS_INVALID_TABLES');
    }

    return DatabaseStatus(
      statusVersion: statusVersion,
      schemaVersion: _integer(json['schemaVersion']),
      backupFormatVersion: _integer(json['backupFormatVersion']),
      collectedAt: json['collectedAt'] is String
          ? DateTime.tryParse(json['collectedAt'] as String)?.toLocal()
          : null,
      localContent: DatabaseLocalContentStatus.fromJson(localContent),
      collaboration: DatabaseCollaborationStatus.fromJson(collaboration),
      tables: rawTables.map((rawTable) {
        if (rawTable is! Map) {
          throw const FormatException('DATABASE_STATUS_INVALID_TABLE');
        }
        return DatabaseTableStatus.fromJson(
          rawTable.map((key, value) => MapEntry(key.toString(), value)),
        );
      }).toList(growable: false),
    );
  }
}

class DatabaseLocalContentStatus {
  const DatabaseLocalContentStatus({
    required this.sessions,
    required this.logs,
    required this.dictionaries,
  });

  final DatabaseSessionCounts sessions;
  final DatabaseLifecycleCounts logs;
  final Map<String, DatabaseLifecycleCounts> dictionaries;

  int get activeDictionaryItems => dictionaries.values.fold(
        0,
        (total, counts) => total + counts.active,
      );

  int get deletedDictionaryItems => dictionaries.values.fold(
        0,
        (total, counts) => total + counts.deleted,
      );

  factory DatabaseLocalContentStatus.fromJson(Map<String, dynamic> json) {
    final dictionariesJson = _map(json['dictionaries'], 'dictionaries');
    return DatabaseLocalContentStatus(
      sessions: DatabaseSessionCounts.fromJson(
        _map(json['sessions'], 'sessions'),
      ),
      logs: DatabaseLifecycleCounts.fromJson(_map(json['logs'], 'logs')),
      dictionaries: dictionariesJson.map((type, rawCounts) {
        return MapEntry(
          type,
          DatabaseLifecycleCounts.fromJson(
            _map(rawCounts, 'dictionaries.$type'),
          ),
        );
      }),
    );
  }
}

class DatabaseSessionCounts {
  const DatabaseSessionCounts({
    required this.active,
    required this.closed,
    required this.archived,
    required this.deleted,
  });

  final int active;
  final int closed;
  final int archived;
  final int deleted;

  int get available => active + closed + archived;

  factory DatabaseSessionCounts.fromJson(Map<String, dynamic> json) =>
      DatabaseSessionCounts(
        active: _requiredCount(json['active'], 'sessions.active'),
        closed: _requiredCount(json['closed'], 'sessions.closed'),
        archived: _requiredCount(json['archived'], 'sessions.archived'),
        deleted: _requiredCount(json['deleted'], 'sessions.deleted'),
      );
}

class DatabaseLifecycleCounts {
  const DatabaseLifecycleCounts({
    required this.active,
    required this.deleted,
  });

  final int active;
  final int deleted;

  factory DatabaseLifecycleCounts.fromJson(Map<String, dynamic> json) =>
      DatabaseLifecycleCounts(
        active: _requiredCount(json['active'], 'active'),
        deleted: _requiredCount(json['deleted'], 'deleted'),
      );
}

class DatabaseCollaborationStatus {
  const DatabaseCollaborationStatus({
    required this.bindings,
    required this.pendingOutbox,
    required this.openConflicts,
    required this.offlineRecords,
    required this.draftCaches,
  });

  final int bindings;
  final int pendingOutbox;
  final int openConflicts;
  final int offlineRecords;
  final int draftCaches;

  bool get hasPendingWork =>
      pendingOutbox > 0 || openConflicts > 0 || offlineRecords > 0;

  factory DatabaseCollaborationStatus.fromJson(Map<String, dynamic> json) =>
      DatabaseCollaborationStatus(
        bindings: _requiredCount(json['bindings'], 'collaboration.bindings'),
        pendingOutbox: _requiredCount(
          json['pendingOutbox'],
          'collaboration.pendingOutbox',
        ),
        openConflicts: _requiredCount(
          json['openConflicts'],
          'collaboration.openConflicts',
        ),
        offlineRecords: _requiredCount(
          json['offlineRecords'],
          'collaboration.offlineRecords',
        ),
        draftCaches: _requiredCount(
          json['draftCaches'],
          'collaboration.draftCaches',
        ),
      );
}

class DatabaseTableStatus {
  const DatabaseTableStatus({required this.name, required this.rowCount});

  final String name;
  final int rowCount;

  factory DatabaseTableStatus.fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    if (name is! String || name.isEmpty) {
      throw const FormatException('DATABASE_STATUS_INVALID_TABLE_NAME');
    }
    return DatabaseTableStatus(
      name: name,
      rowCount: _requiredCount(json['rowCount'], 'tables.$name'),
    );
  }
}

Map<String, dynamic> _map(Object? value, String field) {
  if (value is! Map) {
    throw FormatException('DATABASE_STATUS_INVALID_FIELD:$field');
  }
  return value.map((key, value) => MapEntry(key.toString(), value));
}

int? _integer(Object? value) => value is int
    ? value
    : value is num && value.isFinite && value == value.roundToDouble()
        ? value.toInt()
        : null;

int _requiredCount(Object? value, String field) {
  final count = _integer(value);
  if (count == null || count < 0) {
    throw FormatException('DATABASE_STATUS_INVALID_COUNT:$field');
  }
  return count;
}
