import 'dart:math';

class SyncCallsignQthRecord {
  final int? id;
  final String syncId;
  final bool hasExplicitSyncId;
  final String callsign;
  final String qth;
  final String recordedAt;
  final String createdAt;
  final String updatedAt;
  final String? deletedAt;

  factory SyncCallsignQthRecord({
    int? id,
    String? syncId,
    required String callsign,
    required String qth,
    required String recordedAt,
    String? createdAt,
    String? updatedAt,
    String? deletedAt,
  }) {
    final normalizedCreatedAt = _normalizeTimestamp(createdAt, fallback: recordedAt);
    return SyncCallsignQthRecord._internal(
      id: id,
      syncId: _normalizeSyncId(syncId, prefix: 'callsign-qth'),
      hasExplicitSyncId: _hasText(syncId),
      callsign: callsign,
      qth: qth,
      recordedAt: recordedAt,
      createdAt: normalizedCreatedAt,
      updatedAt: _normalizeTimestamp(updatedAt, fallback: normalizedCreatedAt),
      deletedAt: deletedAt,
    );
  }

  const SyncCallsignQthRecord._internal({
    required this.id,
    required this.syncId,
    required this.hasExplicitSyncId,
    required this.callsign,
    required this.qth,
    required this.recordedAt,
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
    if (_isValidIsoTimestamp(normalized)) {
      return normalized!;
    }
    final normalizedFallback = fallback?.trim();
    if (_isValidIsoTimestamp(normalizedFallback)) {
      return normalizedFallback!;
    }
    return DateTime.now().toUtc().toIso8601String();
  }

  static bool _isValidIsoTimestamp(String? value) {
    if (value == null || value.isEmpty) {
      return false;
    }
    return DateTime.tryParse(value) != null;
  }

  static String? _normalizeNullableString(dynamic value) {
    if (value == null) {
      return null;
    }
    final normalized = value.toString().trim();
    return normalized.isEmpty ? null : normalized;
  }

  factory SyncCallsignQthRecord.fromJson(Map<String, dynamic> json) {
    return SyncCallsignQthRecord(
      id: json['id'] as int?,
      syncId: json['syncId']?.toString() ?? json['sync_id']?.toString(),
      callsign: json['callsign']?.toString() ?? '',
      qth: json['qth']?.toString() ?? '',
      recordedAt: json['recordedAt']?.toString() ?? json['recorded_at']?.toString() ?? '',
      createdAt: json['createdAt']?.toString() ?? json['created_at']?.toString(),
      updatedAt: json['updatedAt']?.toString() ?? json['updated_at']?.toString(),
      deletedAt: _normalizeNullableString(json['deletedAt'] ?? json['deleted_at']),
    );
  }

  factory SyncCallsignQthRecord.fromMap(Map<String, dynamic> map) {
    return SyncCallsignQthRecord(
      id: map['id'] as int?,
      syncId: map['sync_id']?.toString() ?? map['syncId']?.toString(),
      callsign: map['callsign']?.toString() ?? '',
      qth: map['qth']?.toString() ?? '',
      recordedAt: map['recorded_at']?.toString() ?? map['recordedAt']?.toString() ?? '',
      createdAt: map['created_at']?.toString() ?? map['createdAt']?.toString(),
      updatedAt: map['updated_at']?.toString() ?? map['updatedAt']?.toString(),
      deletedAt: _normalizeNullableString(map['deleted_at'] ?? map['deletedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'syncId': syncId,
      'callsign': callsign,
      'qth': qth,
      'recordedAt': recordedAt,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'deletedAt': deletedAt,
    };
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'sync_id': syncId,
      'callsign': callsign,
      'qth': qth,
      'recorded_at': recordedAt,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'deleted_at': deletedAt,
    };
  }

  SyncCallsignQthRecord copyWith({
    int? id,
    String? syncId,
    String? callsign,
    String? qth,
    String? recordedAt,
    String? createdAt,
    String? updatedAt,
    Object? deletedAt = _syncCallsignQthCopyWithSentinel,
  }) {
    return SyncCallsignQthRecord(
      id: id ?? this.id,
      syncId: syncId ?? this.syncId,
      callsign: callsign ?? this.callsign,
      qth: qth ?? this.qth,
      recordedAt: recordedAt ?? this.recordedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: identical(deletedAt, _syncCallsignQthCopyWithSentinel) ? this.deletedAt : deletedAt as String?,
    );
  }
}

const Object _syncCallsignQthCopyWithSentinel = Object();
