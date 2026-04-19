import 'dart:math';

class LogEntry {
  final int? localId;
  final String id;
  final bool hasExplicitSyncId;
  final String time;
  final String controller;
  final String callsign;
  final String report;
  final String qth;
  final String device;
  final String power;
  final String antenna;
  final String height;
  final String createdAt;
  final String updatedAt;
  final String? deletedAt;
  final String? sourceDeviceId;

  factory LogEntry({
    int? localId,
    String? id,
    required String time,
    required String controller,
    required String callsign,
    required String report,
    required String qth,
    required String device,
    required String power,
    required String antenna,
    required String height,
    String? createdAt,
    String? updatedAt,
    String? deletedAt,
    String? sourceDeviceId,
  }) {
    final normalizedId = _normalizeSyncId(id, prefix: 'log');
    final normalizedCreatedAt = _normalizeTimestamp(createdAt);
    return LogEntry._internal(
      localId: localId,
      id: normalizedId,
      hasExplicitSyncId: _hasText(id),
      time: time,
      controller: controller,
      callsign: callsign,
      report: report,
      qth: qth,
      device: device,
      power: power,
      antenna: antenna,
      height: height,
      createdAt: normalizedCreatedAt,
      updatedAt: _normalizeTimestamp(updatedAt, fallback: normalizedCreatedAt),
      deletedAt: deletedAt,
      sourceDeviceId: sourceDeviceId,
    );
  }

  const LogEntry._internal({
    required this.localId,
    required this.id,
    required this.hasExplicitSyncId,
    required this.time,
    required this.controller,
    required this.callsign,
    required this.report,
    required this.qth,
    required this.device,
    required this.power,
    required this.antenna,
    required this.height,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
    required this.sourceDeviceId,
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

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'time': time,
      'controller': controller,
      'callsign': callsign,
      'report': report,
      'qth': qth,
      'device': device,
      'power': power,
      'antenna': antenna,
      'height': height,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'deletedAt': deletedAt,
      'sourceDeviceId': sourceDeviceId,
    };
  }

  Map<String, dynamic> toMap() {
    return {
      if (localId != null) 'id': localId,
      'sync_id': id,
      'time': time,
      'controller': controller,
      'callsign': callsign,
      'report': report,
      'qth': qth,
      'device': device,
      'power': power,
      'antenna': antenna,
      'height': height,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'deleted_at': deletedAt,
      'source_device_id': sourceDeviceId,
    };
  }

  factory LogEntry.fromJson(Map<String, dynamic> json) {
    return LogEntry(
      localId: json['localId'] is int ? json['localId'] as int : (json['id'] is int ? json['id'] as int : null),
      id: _normalizeNullableString(json['id'] ?? json['sync_id']),
      time: json['time']?.toString() ?? '',
      controller: json['controller']?.toString() ?? '',
      callsign: json['callsign']?.toString() ?? '',
      report: json['report']?.toString() ?? '',
      qth: json['qth']?.toString() ?? '',
      device: json['device']?.toString() ?? '',
      power: json['power']?.toString() ?? '',
      antenna: json['antenna']?.toString() ?? '',
      height: json['height']?.toString() ?? '',
      createdAt: json['createdAt']?.toString() ?? json['created_at']?.toString(),
      updatedAt: json['updatedAt']?.toString() ?? json['updated_at']?.toString(),
      deletedAt: _normalizeNullableString(json['deletedAt'] ?? json['deleted_at']),
      sourceDeviceId: _normalizeNullableString(json['sourceDeviceId'] ?? json['source_device_id']),
    );
  }

  factory LogEntry.fromMap(Map<String, dynamic> map) {
    return LogEntry(
      localId: map['id'] is int ? map['id'] as int : int.tryParse('${map['id'] ?? ''}'),
      id: _normalizeNullableString(map['sync_id'] ?? map['id']),
      time: map['time']?.toString() ?? '',
      controller: map['controller']?.toString() ?? '',
      callsign: map['callsign']?.toString() ?? '',
      report: map['report']?.toString() ?? '',
      qth: map['qth']?.toString() ?? '',
      device: map['device']?.toString() ?? '',
      power: map['power']?.toString() ?? '',
      antenna: map['antenna']?.toString() ?? '',
      height: map['height']?.toString() ?? '',
      createdAt: map['created_at']?.toString() ?? map['createdAt']?.toString(),
      updatedAt: map['updated_at']?.toString() ?? map['updatedAt']?.toString(),
      deletedAt: _normalizeNullableString(map['deleted_at'] ?? map['deletedAt']),
      sourceDeviceId: _normalizeNullableString(map['source_device_id'] ?? map['sourceDeviceId']),
    );
  }

  List<String> toList() {
    return [
      time,
      controller,
      callsign,
      report,
      qth,
      device,
      power,
      antenna,
      height,
    ];
  }

  LogEntry copyWith({
    int? localId,
    String? id,
    String? time,
    String? controller,
    String? callsign,
    String? report,
    String? qth,
    String? device,
    String? power,
    String? antenna,
    String? height,
    String? createdAt,
    String? updatedAt,
    Object? deletedAt = _copyWithSentinel,
    Object? sourceDeviceId = _copyWithSentinel,
  }) {
    return LogEntry(
      localId: localId ?? this.localId,
      id: id ?? this.id,
      time: time ?? this.time,
      controller: controller ?? this.controller,
      callsign: callsign ?? this.callsign,
      report: report ?? this.report,
      qth: qth ?? this.qth,
      device: device ?? this.device,
      power: power ?? this.power,
      antenna: antenna ?? this.antenna,
      height: height ?? this.height,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: identical(deletedAt, _copyWithSentinel) ? this.deletedAt : deletedAt as String?,
      sourceDeviceId: identical(sourceDeviceId, _copyWithSentinel)
          ? this.sourceDeviceId
          : sourceDeviceId as String?,
    );
  }
}

const Object _copyWithSentinel = Object();
