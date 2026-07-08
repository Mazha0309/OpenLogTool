import 'dart:convert';
import 'package:http/http.dart' as http;

class AuthService {
  static const Duration _timeout = Duration(seconds: 15);

  final String _baseUrl;

  AuthService(String serverUrl)
      : _baseUrl = serverUrl.replaceAll(RegExp(r'/$'), '');

  Future<Map<String, dynamic>?> fetchCurrentUser(String token) async {
    final uri = Uri.parse('$_baseUrl/api/v1/auth/me');
    try {
      final response = await http
          .get(uri, headers: {'Authorization': 'Bearer $token'})
          .timeout(_timeout);
      if (response.statusCode != 200) {
        throw AuthException('获取用户信息失败: HTTP ${response.statusCode}');
      }
      final result = json.decode(response.body) as Map<String, dynamic>;
      if (result['success'] != true || result['data'] == null) {
        throw AuthException(result['message']?.toString() ?? '获取用户信息失败');
      }
      return Map<String, dynamic>.from(result['data']);
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException('网络错误: $e');
    }
  }

  Future<Map<String, dynamic>?> login(String username, String password) async {
    final uri = Uri.parse('$_baseUrl/api/v1/auth/login');
    try {
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'username': username, 'password': password}),
          )
          .timeout(_timeout);
      if (response.statusCode != 200) {
        throw AuthException('登录失败: HTTP ${response.statusCode}');
      }
      final result = json.decode(response.body) as Map<String, dynamic>;
      if (result['success'] != true) {
        throw AuthException(result['message']?.toString() ?? '登录失败');
      }
      final newToken = result['data']['token']?.toString();
      if (newToken == null || newToken.isEmpty) {
        throw AuthException('服务端未返回有效令牌');
      }
      return {'token': newToken, 'result': result};
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException('网络错误: $e');
    }
  }

  Future<bool> changePassword(
      String token, String oldPassword, String newPassword) async {
    final uri = Uri.parse('$_baseUrl/api/v1/auth/password');
    try {
      final response = await http
          .put(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: json
                .encode({'oldPassword': oldPassword, 'newPassword': newPassword}),
          )
          .timeout(_timeout);
      if (response.statusCode != 200) {
        throw AuthException('修改密码失败: HTTP ${response.statusCode}');
      }
      return true;
    } catch (e) {
      throw AuthException('修改密码失败: $e');
    }
  }

  Future<bool> setTheme(String token, String theme) async {
    final uri = Uri.parse('$_baseUrl/api/v1/auth/theme');
    try {
      final response = await http
          .put(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: json.encode({'theme': theme}),
          )
          .timeout(_timeout);
      if (response.statusCode != 200) {
        throw AuthException('设置主题失败: HTTP ${response.statusCode}');
      }
      return true;
    } catch (e) {
      throw AuthException('设置主题失败: $e');
    }
  }
}

class AuthException implements Exception {
  final String message;
  AuthException(this.message);

  @override
  String toString() => message;
}
