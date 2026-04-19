import 'dart:math';

class SyncHistoryRecord {
  final int? id;
  final String syncId;
  final bool hasExplicitSyncId;
  final String name;
  final String logsData;
  final int logCount;
  final String createdAt;
  final String updatedAt;
  final String? deletedAt;

  factory SyncHistoryRecord({
    int? id,
    String? syncId,
    required String name,
    required String logsData,
    required int logCount,
    String? createdAt,
    String? updatedAt,
    String? deletedAt,
  }) {
    final normalizedCreatedAt = _normalizeTimestamp(createdAt);
    return SyncHistoryRecord._internal(
      id: id,
      syncId: _normalizeSyncId(syncId, prefix: 'history'),
      hasExplicitSyncId: _hasText(syncId),
      name: name,
      logsData: logsData,
      logCount: logCount,
      createdAt: normalizedCreatedAt,
      updatedAt: _normalizeTimestamp(updatedAt, fallback: normalizedCreatedAt),
      deletedAt: deletedAt,
    );
  }

  const SyncHistoryRecord._internal({
    required this.id,
    required this.syncId,
    required this.hasExplicitSyncId,
    required this.name,
    required this.logsData,
    required this.logCount,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
  });

  static bool _hasText(String? value) => value != null && value.trim().isNotEmpty;

  static String _normalizeSyncId(String? value, {required String prefix}) {
    final normalized = value?.trim();
    if (normalized != null && normalized.isNotEmpty) {
      return normalized;
    }
    return _generateSyncId(prefix);
  }

  static String _generateSyncId(String prefix) {
    final random = Random.secure();
    final suffix = List<String>.generate(
      4,
      (_) => random.nextInt(1 << 16).toRadixString(16).padLeft(4, '0'),
    ).join();
    return '$prefix-${DateTime.now().toUtc().microsecondsSinceEpoch}-$suffix';
  }

  static String _normalizeTimestamp(String? value, {String? fallback}) {
    final normalized = value?.trim();
    if (normalized != null && normalized.isNotEmpty) {
      return normalized;
    }
    final normalizedFallback = fallback?.trim();
    if (normalizedFallback != null && normalizedFallback.isNotEmpty) {
      return normalizedFallback;
    }
    return DateTime.now().toIso8601String();
  }

  static String? _normalizeNullableString(dynamic value) {
    if (value == null) {
      return null;
    }
    final normalized = value.toString().trim();
    return normalized.isEmpty ? null : normalized;
  }

  factory SyncHistoryRecord.fromJson(Map<String, dynamic> json) {
    return SyncHistoryRecord(
      id: json['id'] as int?,
      syncId: json['syncId']?.toString() ?? json['sync_id']?.toString(),
      name: json['name']?.toString() ?? '',
      logsData: json['logsData']?.toString() ?? json['logs_data']?.toString() ?? '',
      logCount: (json['logCount'] ?? json['log_count'] ?? 0) as int,
      createdAt: json['createdAt']?.toString() ?? json['created_at']?.toString(),
      updatedAt: json['updatedAt']?.toString() ?? json['updated_at']?.toString(),
      deletedAt: _normalizeNullableString(json['deletedAt'] ?? json['deleted_at']),
    );
  }

  factory SyncHistoryRecord.fromMap(Map<String, dynamic> map) {
    return SyncHistoryRecord(
      id: map['id'] as int?,
      syncId: map['sync_id']?.toString() ?? map['syncId']?.toString(),
      name: map['name']?.toString() ?? '',
      logsData: map['logs_data']?.toString() ?? map['logsData']?.toString() ?? '',
      logCount: (map['log_count'] ?? map['logCount'] ?? 0) as int,
      createdAt: map['created_at']?.toString() ?? map['createdAt']?.toString(),
      updatedAt: map['updated_at']?.toString() ?? map['updatedAt']?.toString(),
      deletedAt: _normalizeNullableString(map['deleted_at'] ?? map['deletedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'syncId': syncId,
      'name': name,
      'logsData': logsData,
      'logCount': logCount,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'deletedAt': deletedAt,
    };
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'sync_id': syncId,
      'name': name,
      'logs_data': logsData,
      'log_count': logCount,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'deleted_at': deletedAt,
    };
  }

  SyncHistoryRecord copyWith({
    int? id,
    String? syncId,
    String? name,
    String? logsData,
    int? logCount,
    String? createdAt,
    String? updatedAt,
    Object? deletedAt = _syncHistoryCopyWithSentinel,
  }) {
    return SyncHistoryRecord(
      id: id ?? this.id,
      syncId: syncId ?? this.syncId,
      name: name ?? this.name,
      logsData: logsData ?? this.logsData,
      logCount: logCount ?? this.logCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: identical(deletedAt, _syncHistoryCopyWithSentinel) ? this.deletedAt : deletedAt as String?,
    );
  }
}

const Object _syncHistoryCopyWithSentinel = Object();
