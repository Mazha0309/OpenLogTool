# Flutter 客户端简化同步/协作实施计划

**Goal:** 移除旧 SyncProvider 及其相关服务，改为简单的 ServerProvider + REST API 上传/下载 session。

**Tech Stack:** Flutter/Dart, http package, Provider

---

## Task 1: 创建 ServerProvider

**Files:**
- Create: `lib/providers/server_provider.dart`
- Remove: `lib/services/auth_service.dart`, `lib/services/instance_service.dart`, `lib/services/live_share_service.dart`, `lib/services/collaboration_service.dart`, `lib/services/share_service.dart`

**Details:**

`ServerProvider` 替代旧的 `SyncProvider`，功能：
- 保存服务器 URL（持久化到 SharedPreferences）
- 登录/注册（调用 REST API）
- 上传当前 session（`POST /api/sessions + logs`）
- 下载 session 列表 + 选中后下载 logs
- 不涉及 WebSocket/liveshare

```dart
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

  // Headers for authenticated requests
  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  /// Upload current session (session + logs) to server
  Future<void> uploadSession(String sessionId, String title, List<Map<String, dynamic>> logs) async {
    // 1. Create session on server
    final sessionRes = await http.post(
      Uri.parse('$_serverUrl/api/sessions'),
      headers: _headers,
      body: jsonEncode({'id': sessionId, 'title': title}),
    );
    // 2. Upload each log
    for (final log in logs) {
      await http.post(
        Uri.parse('$_serverUrl/api/sessions/$sessionId/logs'),
        headers: _headers,
        body: jsonEncode(log),
      );
    }
  }

  /// List sessions from server
  Future<List<Map<String, dynamic>>> listSessions() async {
    final res = await http.get(Uri.parse('$_serverUrl/api/sessions'), headers: _headers);
    if (res.statusCode != 200) throw Exception('Failed to list sessions');
    return (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
  }

  /// Download a session with its logs
  Future<Map<String, dynamic>> downloadSession(String sessionId) async {
    final res = await http.get(Uri.parse('$_serverUrl/api/sessions/$sessionId'), headers: _headers);
    if (res.statusCode != 200) throw Exception('Failed to download session');
    return jsonDecode(res.body);
  }
}
```

Remove old service files:
- `lib/services/auth_service.dart`
- `lib/services/instance_service.dart`
- `lib/services/live_share_service.dart`
- `lib/services/collaboration_service.dart`
- `lib/services/share_service.dart`

**Commit:**
```bash
git add -A
git commit -m "feat(server): 新增 ServerProvider，移除旧 sync 相关 services"
```

---

## Task 2: 更新 SettingsPanel - 简化服务器设置

**Files:**
- Modify: `lib/widgets/settings_panel.dart`
- Modify: `lib/widgets/settings/subwidgets.dart` (or remove if it's only sync-related)

**Details:**
- 移除 `Consumer<SyncProvider>` 部分，替换为 `Consumer<ServerProvider>`。
- 只保留：服务器 URL 输入框 + 登录/注册按钮 + 显示当前用户名/退出。
- 去掉所有同步策略、间隔、模式等配置。

Read current settings_panel.dart to craft the edit. The changes are in the `Consumer<SyncProvider>` block around line 57-100.

**Commit:**
```bash
git add lib/widgets/settings_panel.dart lib/widgets/settings/subwidgets.dart
git commit -m "refactor(settings): 简化服务器设置，仅保留 URL + 登录/注册"
```

---

## Task 3: 更新 HomeScreen - 替换同步相关按钮

**Files:**
- Modify: `lib/screens/home_screen.dart`

**Details:**
- 移除 `_generateAndShowLink` 方法。
- 移除所有 `SyncProvider` 引用，替换为 `ServerProvider`。
- 添加"上传到服务器"和"从服务器下载"按钮（可在右上角菜单或浮动按钮）。

**Commit:**
```bash
git add lib/screens/home_screen.dart
git commit -m "refactor(home): 替换 SyncProvider 引用，添加上传/下载按钮"
```

---

## Task 4: 移除 SyncProvider 并更新 main.dart

**Files:**
- Remove: `lib/providers/sync_provider.dart`
- Modify: `lib/main.dart`
- Maybe: `lib/providers/dictionary_provider.dart` (remove SyncProvider import/usage)

**Details:**
- `main.dart`:
  - 移除 `SyncProvider` import 和 `ChangeNotifierProvider(create: (_) => SyncProvider())`。
  - `ChangeNotifierProxyProvider<SyncProvider, DictionaryProvider>` 改为不需要 SyncProvider。
  - `ChangeNotifierProxyProvider<SyncProvider, LogProvider>` 同理。
- `dictionary_provider.dart`: 移除 `syncProvider` 相关逻辑。

**Commit:**
```bash
git add lib/main.dart lib/providers/sync_provider.dart lib/providers/dictionary_provider.dart
git commit -m "refactor: 移除 SyncProvider，清理 main.dart 依赖"
```

---

## Task 5: 验证

**Details:**
- `flutter analyze --no-fatal-infos`
- `flutter test`
- `flutter build linux --debug`

**Commit:**
```bash
git add -A
git commit -m "chore: final cleanup and verification"
```
