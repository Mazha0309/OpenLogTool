import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:openlogtool/services/instance_service.dart';

class Session {
  final String sessionId;
  final String title;
  final String status;
  final String createdAt;
  final String updatedAt;
  final String? closedAt;
  final String? deletedAt;
  final String? sourceDeviceId;

  const Session({
    required this.sessionId,
    required this.title,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.closedAt,
    this.deletedAt,
    this.sourceDeviceId,
  });

  static Future<String> generateSessionId() async {
    final instanceId = await InstanceService.getInstanceId();
    final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch.toString();
    final random = Random.secure().nextInt(1 << 32).toRadixString(16);
    final raw = '$instanceId:$timestamp:$random';
    final bytes = utf8.encode(raw);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 32);
  }

  static String migrationSessionId(String historySyncId) {
    final raw = 'history-migration:$historySyncId';
    final bytes = utf8.encode(raw);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 32);
  }

  factory Session.fromMap(Map<String, dynamic> map) {
    return Session(
      sessionId: map['session_id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      status: map['status']?.toString() ?? 'active',
      createdAt: map['created_at']?.toString() ?? DateTime.now().toUtc().toIso8601String(),
      updatedAt: map['updated_at']?.toString() ?? DateTime.now().toUtc().toIso8601String(),
      closedAt: _nullable(map['closed_at']),
      deletedAt: _nullable(map['deleted_at']),
      sourceDeviceId: _nullable(map['source_device_id']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'session_id': sessionId,
      'title': title,
      'status': status,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'closed_at': closedAt,
      'deleted_at': deletedAt,
      'source_device_id': sourceDeviceId,
    };
  }

  static String? _nullable(dynamic value) {
    if (value == null) return null;
    final s = value.toString().trim();
    return s.isEmpty ? null : s;
  }
}
