import 'dart:convert';
import 'package:http/http.dart' as http;

class JoinShareResult {
  final bool success;
  final Map<String, dynamic>? data;
  final String? error;

  const JoinShareResult({required this.success, this.data, this.error});
}

class ShareInfo {
  final String shareId;
  final String shareCode;
  final String sessionId;
  final String? sessionTitle;
  final String? fromUserId;
  final String? toUserId;
  final String status;
  final String permission;

  const ShareInfo({
    required this.shareId,
    required this.shareCode,
    required this.sessionId,
    this.sessionTitle,
    this.fromUserId,
    this.toUserId,
    required this.status,
    required this.permission,
  });

  factory ShareInfo.fromJson(Map<String, dynamic> json) {
    return ShareInfo(
      shareId: json['shareId'] ?? json['id'] ?? '',
      shareCode: json['shareCode'] ?? json['share_code'] ?? '',
      sessionId: json['sessionId'] ?? json['session_id'] ?? '',
      sessionTitle: json['sessionTitle'] ?? json['session_title'],
      fromUserId: json['fromUserId'] ?? json['from_user_id'],
      toUserId: json['toUserId'] ?? json['to_user_id'],
      status: json['status'] ?? 'active',
      permission: json['permission'] ?? 'readwrite',
    );
  }

  bool get isPending => status == 'pending';
  bool get isActive => status == 'active';
  bool get isRevoked => status == 'revoked';
}

class ShareService {
  final String baseUrl;
  final String token;

  const ShareService({required this.baseUrl, required this.token});

  Future<Map<String, dynamic>?> createShare(String sessionId,
      {String permission = 'readwrite'}) async {
    try {
      final uri = Uri.parse('$baseUrl/api/v1/shares');
      final response = await http
          .post(uri,
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: json.encode({
                'sessionId': sessionId,
                'permission': permission,
              }))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['ok'] == true) return Map<String, dynamic>.from(data['data']);
      }
    } catch (_) {}
    return null;
  }

  Future<JoinShareResult> joinShare(String shareCode) async {
    try {
      final uri = Uri.parse('$baseUrl/api/v1/shares/join');
      final response = await http
          .post(uri,
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: json.encode({'shareCode': shareCode}))
          .timeout(const Duration(seconds: 10));
      final data = json.decode(response.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        return JoinShareResult(
          success: true,
          data: Map<String, dynamic>.from(data['data'] ?? {}),
        );
      }
      return JoinShareResult(
        success: false,
        error: data['error']?['message']?.toString() ?? '加入失败',
      );
    } catch (e) {
      return JoinShareResult(success: false, error: '网络错误: $e');
    }
  }

  Future<List<ShareInfo>> listShares() async {
    try {
      final uri = Uri.parse('$baseUrl/api/v1/shares');
      final response = await http
          .get(uri,
              headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['ok'] == true && data['data'] is List) {
          return (data['data'] as List)
              .map((e) => ShareInfo.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        }
      }
    } catch (_) {}
    return [];
  }

  Future<bool> revokeShare(String shareId) async {
    try {
      final uri = Uri.parse('$baseUrl/api/v1/shares/$shareId');
      final response = await http
          .delete(uri,
              headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
