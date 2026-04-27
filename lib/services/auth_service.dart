import 'dart:convert';
import 'package:http/http.dart' as http;

class AuthService {
  final String _baseUrl;

  AuthService(String serverUrl)
      : _baseUrl = serverUrl.replaceAll(RegExp(r'/$'), '');

  Future<Map<String, dynamic>?> fetchCurrentUser(String token) async {
    final uri = Uri.parse('$_baseUrl/api/v1/auth/me');
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode != 200) return null;
    final result = json.decode(response.body) as Map<String, dynamic>;
    if (result['success'] != true || result['data'] == null) return null;
    return Map<String, dynamic>.from(result['data']);
  }

  Future<Map<String, dynamic>?> login(String token, String username,
      String password) async {
    final uri = Uri.parse('$_baseUrl/api/v1/auth/login');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'username': username, 'password': password}),
    );
    if (response.statusCode != 200) return null;
    final result = json.decode(response.body) as Map<String, dynamic>;
    if (result['success'] != true) return null;
    final newToken = result['data']['token']?.toString();
    if (newToken == null || newToken.isEmpty) return null;
    return {'token': newToken, 'result': result};
  }

  Future<bool> changePassword(
      String token, String oldPassword, String newPassword) async {
    final uri = Uri.parse('$_baseUrl/api/v1/auth/password');
    final response = await http.put(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: json.encode({'oldPassword': oldPassword, 'newPassword': newPassword}),
    );
    return response.statusCode == 200;
  }

  Future<bool> setTheme(String token, String theme) async {
    final uri = Uri.parse('$_baseUrl/api/v1/auth/theme');
    final response = await http.put(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: json.encode({'theme': theme}),
    );
    return response.statusCode == 200;
  }
}
