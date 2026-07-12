import 'package:flutter/foundation.dart';
import 'package:openlogtool/models/collaboration_dto.dart';
import 'package:openlogtool/services/server_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ServerProvider with ChangeNotifier {
  String _serverUrl = '';
  MemoryTokenStore _tokenStore = MemoryTokenStore();
  ServerApi? _api;
  ServerInfoDto? _serverInfo;
  ApiUserDto? _user;
  String? _deviceId;
  bool _isBusy = false;
  String? _lastErrorCode;
  Future<void> _lastUrlSave = Future<void>.value();
  int _contextRevision = 0;

  String get serverUrl => _serverUrl;
  bool get isLoggedIn => _user != null;
  bool get isBusy => _isBusy;
  String? get username => _user?.username;
  String? get accountId => _user?.id;
  String? get deviceId => _deviceId;
  String? get lastErrorCode => _lastErrorCode;
  ServerInfoDto? get serverInfo => _serverInfo;
  int get contextRevision => _contextRevision;

  ServerApi get api {
    if (_serverUrl.isEmpty) {
      throw StateError('请先配置服务器地址');
    }
    return _api ??= _buildApi();
  }

  ServerProvider() {
    Future.microtask(() async {
      try {
        await loadSettings();
      } catch (e) {
        debugPrint('[ServerProvider] loadSettings error: $e');
      }
    });
  }

  Future<void> loadSettings() async {
    final startedAtRevision = _contextRevision;
    final prefs = await SharedPreferences.getInstance();
    final savedServerUrl = prefs.getString('server_url') ?? '';
    // v0 stored a long-lived token in SharedPreferences. v1 deliberately keeps
    // credentials in the TokenStore boundary; the default app store is memory-only
    // until a platform secure-storage implementation is wired in.
    await prefs.remove('server_token');
    await prefs.remove('server_username');
    if (_contextRevision != startedAtRevision) return;
    if (_serverUrl != savedServerUrl) {
      _serverUrl = savedServerUrl;
      final oldTokenStore = _replaceAuthContext();
      await oldTokenStore.clear();
      _serverInfo = null;
      _lastErrorCode = null;
      _user = null;
      _contextRevision += 1;
    }
    notifyListeners();
  }

  Future<void> setServerUrl(String url) async {
    final normalized = url.replaceAll(RegExp(r'/$'), '');
    if (_serverUrl == normalized) return;
    _serverUrl = normalized;
    final oldTokenStore = _replaceAuthContext();
    _serverInfo = null;
    _lastErrorCode = null;
    _user = null;
    _contextRevision += 1;
    notifyListeners();
    await oldTokenStore.clear();
    _lastUrlSave = _lastUrlSave.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('server_url', normalized);
    });
    await _lastUrlSave;
  }

  Future<void> setDeviceId(String deviceId) async {
    if (_deviceId == deviceId) return;
    _deviceId = deviceId;
    _api?.close();
    _api = null;
    _contextRevision += 1;
    notifyListeners();
  }

  Future<ServerInfoDto> checkServer() async {
    _setBusy(true);
    try {
      return await _fetchServerInfo();
    } on ServerApiException catch (error) {
      _lastErrorCode = error.code;
      notifyListeners();
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<String> register(String username, String password) async {
    _setBusy(true);
    try {
      final attempt = _beginAuthentication();
      await attempt.oldTokenStore.clear();
      _ensureCurrentRevision(attempt.revision);
      await _ensureServerInfo();
      final requestedApi = api;
      _ensureCurrentContext(attempt.revision, requestedApi);
      final session = await requestedApi.register(
        AuthCredentialsDto(
          username: username,
          password: password,
          deviceId: _deviceId,
        ),
      );
      _ensureCurrentContext(attempt.revision, requestedApi);
      _applyAuth(session);
      return session.accessToken;
    } finally {
      _setBusy(false);
    }
  }

  Future<String> login(String username, String password) async {
    _setBusy(true);
    try {
      final attempt = _beginAuthentication();
      await attempt.oldTokenStore.clear();
      _ensureCurrentRevision(attempt.revision);
      await _ensureServerInfo();
      final requestedApi = api;
      _ensureCurrentContext(attempt.revision, requestedApi);
      final session = await requestedApi.login(
        AuthCredentialsDto(
          username: username,
          password: password,
          deviceId: _deviceId,
        ),
      );
      _ensureCurrentContext(attempt.revision, requestedApi);
      _applyAuth(session);
      return session.accessToken;
    } finally {
      _setBusy(false);
    }
  }

  void _applyAuth(AuthSessionDto session) {
    _contextRevision += 1;
    _user = session.user;
    _lastErrorCode = null;
    notifyListeners();
  }

  Future<void> logout() async {
    final apiToLogout = _user != null ? api : null;
    final oldTokenStore = _tokenStore;
    _tokenStore = MemoryTokenStore();
    _api = null;
    _user = null;
    _lastErrorCode = null;
    _contextRevision += 1;
    notifyListeners();
    try {
      await apiToLogout?.logout();
    } finally {
      await oldTokenStore.clear();
      apiToLogout?.close();
    }
  }

  Future<ServerInfoDto> _ensureServerInfo() async {
    final cached = _serverInfo;
    if (cached != null) return cached;
    return _fetchServerInfo();
  }

  Future<ServerInfoDto> _fetchServerInfo() async {
    final requestedAtRevision = _contextRevision;
    final requestedApi = api;
    final info = await requestedApi.getServerInfo();
    if (_contextRevision != requestedAtRevision ||
        !identical(_api, requestedApi)) {
      throw StateError('服务器上下文已变更，请重试');
    }
    if (info.protocolMin > 1 || info.protocolMax < 1) {
      throw StateError('服务器不支持协作协议 v1');
    }
    _serverInfo = info;
    _lastErrorCode = null;
    notifyListeners();
    return info;
  }

  ServerApi _buildApi() {
    final uri = Uri.tryParse(_serverUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw StateError('服务器地址必须是完整的 http(s) URL');
    }
    late final ServerApi builtApi;
    builtApi = ServerApi(
      baseUri: uri,
      tokenStore: _tokenStore,
      deviceId: _deviceId,
      onAuthInvalidated: () => _handleAuthInvalidated(builtApi),
    );
    return builtApi;
  }

  void _handleAuthInvalidated(ServerApi source) {
    if (!identical(_api, source) || _user == null) return;
    _user = null;
    _lastErrorCode = 'AUTH_REQUIRED';
    _contextRevision += 1;
    notifyListeners();
  }

  MemoryTokenStore _replaceAuthContext() {
    final oldTokenStore = _tokenStore;
    _tokenStore = MemoryTokenStore();
    _api?.close();
    _api = null;
    return oldTokenStore;
  }

  ({int revision, MemoryTokenStore oldTokenStore}) _beginAuthentication() {
    final oldTokenStore = _replaceAuthContext();
    _user = null;
    _lastErrorCode = null;
    _contextRevision += 1;
    final revision = _contextRevision;
    notifyListeners();
    return (revision: revision, oldTokenStore: oldTokenStore);
  }

  void _ensureCurrentRevision(int revision) {
    if (_contextRevision != revision) {
      throw StateError('服务器上下文已变更，请重试');
    }
  }

  void _ensureCurrentContext(int revision, ServerApi requestedApi) {
    if (_contextRevision != revision || !identical(_api, requestedApi)) {
      throw StateError('服务器上下文已变更，请重试');
    }
  }

  void _setBusy(bool value) {
    if (_isBusy == value) return;
    _isBusy = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _api?.close();
    super.dispose();
  }
}
