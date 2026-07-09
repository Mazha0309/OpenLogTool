import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ServerProvider with ChangeNotifier {
  String _serverUrl = '';
  String? _token;
  String? _userId;
  String? _username;
  bool _isLoggedIn = false;

  String get serverUrl => _serverUrl;
  bool get isLoggedIn => _isLoggedIn;
  String? get username => _username;
  String? get token => _token;

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _serverUrl = prefs.getString('server_url') ?? '';
    _token = prefs.getString('server_token');
    _userId = prefs.getString('server_user_id');
    _username = prefs.getString('server_username');
    _isLoggedIn = _token != null;
    notifyListeners();
  }

  Future<void> setServerUrl(String url) async {
    _serverUrl = url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_url', url);
    notifyListeners();
  }

  Future<String> register(String username, String password) async {
    final res = await http.post(
      Uri.parse('$_serverUrl/api/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    if (res.statusCode != 200) throw Exception(jsonDecode(res.body)['error'] ?? 'Register failed');
    final data = jsonDecode(res.body);
    _saveAuth(data['token'], data['user']['id'], data['user']['username']);
    return data['token'];
  }

  Future<String> login(String username, String password) async {
    final res = await http.post(
      Uri.parse('$_serverUrl/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    if (res.statusCode != 200) throw Exception(jsonDecode(res.body)['error'] ?? 'Login failed');
    final data = jsonDecode(res.body);
    _saveAuth(data['token'], data['user']['id'], data['user']['username']);
    return data['token'];
  }

  void _saveAuth(String token, String userId, String username) {
    _token = token;
    _userId = userId;
    _username = username;
    _isLoggedIn = true;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('server_token', token);
      prefs.setString('server_user_id', userId);
      prefs.setString('server_username', username);
    });
    notifyListeners();
  }

  Future<void> logout() async {
    _token = null;
    _userId = null;
    _username = null;
    _isLoggedIn = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('server_token');
    await prefs.remove('server_user_id');
    await prefs.remove('server_username');
    notifyListeners();
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  Future<void> uploadSession(String sessionId, String title, List<Map<String, dynamic>> logs) async {
    await http.post(
      Uri.parse('$_serverUrl/api/sessions'),
      headers: _headers,
      body: jsonEncode({'id': sessionId, 'title': title}),
    );
    for (final log in logs) {
      await http.post(
        Uri.parse('$_serverUrl/api/sessions/$sessionId/logs'),
        headers: _headers,
        body: jsonEncode(log),
      );
    }
  }

  Future<List<Map<String, dynamic>>> listSessions() async {
    final res = await http.get(Uri.parse('$_serverUrl/api/sessions'), headers: _headers);
    if (res.statusCode != 200) throw Exception('Failed to list sessions');
    return (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> downloadSession(String sessionId) async {
    final res = await http.get(Uri.parse('$_serverUrl/api/sessions/$sessionId'), headers: _headers);
    if (res.statusCode != 200) throw Exception('Failed to download session');
    return jsonDecode(res.body);
  }
}
