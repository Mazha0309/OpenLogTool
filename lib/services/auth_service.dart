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
      if (response.statusCode != 200) return null;
      final result = json.decode(response.body) as Map<String, dynamic>;
      if (result['success'] != true || result['data'] == null) return null;
      return Map<String, dynamic>.from(result['data']);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> login(String token, String username,
      String password) async {
    final uri = Uri.parse('$_baseUrl/api/v1/auth/login');
    try {
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'username': username, 'password': password}),
          )
          .timeout(_timeout);
      if (response.statusCode != 200) return null;
      final result = json.decode(response.body) as Map<String, dynamic>;
      if (result['success'] != true) return null;
      final newToken = result['data']['token']?.toString();
      if (newToken == null || newToken.isEmpty) return null;
      return {'token': newToken, 'result': result};
    } catch (_) {
      return null;
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
      return response.statusCode == 200;
    } catch (_) {
      return false;
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
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
