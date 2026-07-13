import 'package:flutter/foundation.dart';
import 'package:openlogtool/models/account_dto.dart';
import 'package:openlogtool/models/collaboration_dto.dart';
import 'package:openlogtool/services/server_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef ServerApiFactory = ServerApi Function({
  required Uri baseUri,
  required TokenStore tokenStore,
  required String? deviceId,
  required void Function() onAuthInvalidated,
});

class ServerProvider with ChangeNotifier {
  ServerProvider({
    ServerApiFactory? apiFactory,
    bool autoLoadSettings = true,
  }) : _apiFactory = apiFactory ?? _defaultApiFactory {
    if (autoLoadSettings) {
      Future.microtask(() async {
        try {
          await loadSettings();
        } catch (e) {
          debugPrint('[ServerProvider] loadSettings error: $e');
        }
      });
    }
  }

  final ServerApiFactory _apiFactory;
  String _serverUrl = '';
  MemoryTokenStore _tokenStore = MemoryTokenStore();
  ServerApi? _api;
  ServerInfoDto? _serverInfo;
  ApiUserDto? _user;
  AccountDto? _account;
  PasswordChangeChallengeDto? _passwordChangeChallenge;
  List<DeviceSessionDto> _deviceSessions = const [];
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
  AccountDto? get account => _account;
  PasswordChangeChallengeDto? get passwordChangeChallenge =>
      _passwordChangeChallenge;
  bool get passwordChangeRequired => _passwordChangeChallenge != null;
  List<DeviceSessionDto> get deviceSessions => _deviceSessions;
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
      _account = null;
      _passwordChangeChallenge = null;
      _deviceSessions = const [];
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
    _account = null;
    _passwordChangeChallenge = null;
    _deviceSessions = const [];
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
      late final AuthSessionDto session;
      try {
        session = await requestedApi.login(
          AuthCredentialsDto(
            username: username,
            password: password,
            deviceId: _deviceId,
          ),
        );
      } on ServerApiException catch (error) {
        _ensureCurrentContext(attempt.revision, requestedApi);
        if (error.code == 'PASSWORD_CHANGE_REQUIRED') {
          _passwordChangeChallenge =
              PasswordChangeChallengeDto.fromJson(error.details);
          _lastErrorCode = error.code;
          notifyListeners();
        }
        rethrow;
      }
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
    _account = null;
    _passwordChangeChallenge = null;
    _deviceSessions = const [];
    _lastErrorCode = null;
    notifyListeners();
  }

  Future<String> completeRequiredPasswordChange(String newPassword) async {
    final challenge = _passwordChangeChallenge;
    if (challenge == null) {
      throw StateError('没有待完成的临时密码改密流程');
    }
    _setBusy(true);
    try {
      final requestedAtRevision = _contextRevision;
      final requestedApi = api;
      try {
        final session = await requestedApi.completeRequiredPasswordChange(
          passwordChangeToken: challenge.passwordChangeToken,
          newPassword: newPassword,
          deviceId: _deviceId,
        );
        _ensureCurrentContext(requestedAtRevision, requestedApi);
        _applyAuth(session);
        return session.accessToken;
      } on ServerApiException catch (error) {
        if (error.code == 'PASSWORD_CHANGE_TOKEN_INVALID') {
          _passwordChangeChallenge = null;
          _lastErrorCode = error.code;
          notifyListeners();
        }
        rethrow;
      }
    } finally {
      _setBusy(false);
    }
  }

  void cancelRequiredPasswordChange() {
    if (_passwordChangeChallenge == null) return;
    _passwordChangeChallenge = null;
    _lastErrorCode = null;
    notifyListeners();
  }

  Future<AccountDto> refreshAccount() async {
    _setBusy(true);
    try {
      final requestedAtRevision = _contextRevision;
      final requestedApi = api;
      final account = await requestedApi.getAccount();
      _ensureCurrentContext(requestedAtRevision, requestedApi);
      _account = account;
      _user = account.user;
      _lastErrorCode = null;
      notifyListeners();
      return account;
    } finally {
      _setBusy(false);
    }
  }

  Future<AccountDto> changeUsername({
    required String username,
    required String currentPassword,
  }) async {
    _setBusy(true);
    try {
      final requestedAtRevision = _contextRevision;
      final requestedApi = api;
      final account = await requestedApi.changeUsername(
        username: username,
        currentPassword: currentPassword,
      );
      _ensureCurrentContext(requestedAtRevision, requestedApi);
      _account = account;
      _user = account.user;
      _lastErrorCode = null;
      notifyListeners();
      return account;
    } finally {
      _setBusy(false);
    }
  }

  Future<PasswordChangeResultDto> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    _setBusy(true);
    try {
      final requestedAtRevision = _contextRevision;
      final requestedApi = api;
      final result = await requestedApi.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      _ensureCurrentContext(requestedAtRevision, requestedApi);
      await _clearLocalAuthentication();
      return result;
    } finally {
      _setBusy(false);
    }
  }

  Future<List<DeviceSessionDto>> refreshDeviceSessions() async {
    _setBusy(true);
    try {
      final requestedAtRevision = _contextRevision;
      final requestedApi = api;
      final sessions = await requestedApi.listDeviceSessions();
      _ensureCurrentContext(requestedAtRevision, requestedApi);
      _deviceSessions = sessions;
      _lastErrorCode = null;
      notifyListeners();
      return sessions;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> revokeDeviceSession(DeviceSessionDto session) async {
    _setBusy(true);
    try {
      final requestedAtRevision = _contextRevision;
      final requestedApi = api;
      await requestedApi.revokeDeviceSession(session.sessionId);
      _ensureCurrentContext(requestedAtRevision, requestedApi);
      if (session.current) {
        await _clearLocalAuthentication();
      } else {
        _deviceSessions = List.unmodifiable(
          _deviceSessions.where((item) => item.sessionId != session.sessionId),
        );
        notifyListeners();
      }
    } finally {
      _setBusy(false);
    }
  }

  Future<void> logout() async {
    final apiToLogout = _user != null ? api : null;
    final oldTokenStore = _tokenStore;
    _tokenStore = MemoryTokenStore();
    _api = null;
    _user = null;
    _account = null;
    _passwordChangeChallenge = null;
    _deviceSessions = const [];
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
    builtApi = _apiFactory(
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
    _account = null;
    _deviceSessions = const [];
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
    _account = null;
    _passwordChangeChallenge = null;
    _deviceSessions = const [];
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

  Future<void> _clearLocalAuthentication() async {
    final oldTokenStore = _replaceAuthContext();
    _user = null;
    _account = null;
    _passwordChangeChallenge = null;
    _deviceSessions = const [];
    _lastErrorCode = null;
    _contextRevision += 1;
    notifyListeners();
    await oldTokenStore.clear();
  }

  static ServerApi _defaultApiFactory({
    required Uri baseUri,
    required TokenStore tokenStore,
    required String? deviceId,
    required void Function() onAuthInvalidated,
  }) =>
      ServerApi(
        baseUri: baseUri,
        tokenStore: tokenStore,
        deviceId: deviceId,
        onAuthInvalidated: onAuthInvalidated,
      );

  @override
  void dispose() {
    _api?.close();
    super.dispose();
  }
}
