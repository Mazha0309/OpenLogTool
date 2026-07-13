import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openlogtool/models/collaboration_dto.dart';
import 'package:openlogtool/providers/server_provider.dart';
import 'package:openlogtool/services/secure_token_store.dart';
import 'package:openlogtool/services/server_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('restores a persisted session and refreshes it after app restart',
      () async {
    const serverUrl = 'https://example.test';
    SharedPreferences.setMockInitialValues({'server_url': serverUrl});
    final sessions = <String, AuthSessionDto?>{
      serverUrl: AuthSessionDto.fromJson(
        _authSessionJson(
          accessToken: 'old-access',
          refreshToken: 'old-refresh',
          refreshExpiresAt: DateTime.now().add(const Duration(days: 30)),
        ),
      ),
    };
    var accountRequests = 0;
    final client = MockClient((request) async {
      switch ('${request.method} ${request.url.path}') {
        case 'GET /api/v1/account':
          accountRequests += 1;
          if (accountRequests == 1) {
            expect(request.headers['authorization'], 'Bearer old-access');
            return _apiError(401, 'ACCESS_TOKEN_EXPIRED');
          }
          expect(request.headers['authorization'], 'Bearer new-access');
          return _jsonResponse(_accountJson('alice'));
        case 'POST /api/v1/auth/refresh':
          expect(jsonDecode(request.body), {'refreshToken': 'old-refresh'});
          return _jsonResponse(
            _authSessionJson(
              accessToken: 'new-access',
              refreshToken: 'new-refresh',
              refreshExpiresAt: DateTime.now().add(const Duration(days: 30)),
            ),
          );
        default:
          fail('Unexpected request: ${request.method} ${request.url}');
      }
    });
    final provider = ServerProvider(
      autoLoadSettings: false,
      tokenStoreFactory: (url) => _BackedTokenStore(sessions, url),
      apiFactory: ({
        required baseUri,
        required tokenStore,
        required deviceId,
        required onAuthInvalidated,
      }) =>
          ServerApi(
        baseUri: baseUri,
        tokenStore: tokenStore,
        deviceId: deviceId,
        onAuthInvalidated: onAuthInvalidated,
        httpClient: client,
      ),
    );

    await provider.loadSettings();
    expect(provider.isLoggedIn, isTrue);
    expect(provider.username, 'alice');

    await provider.refreshAccount();
    expect(accountRequests, 2);
    expect(sessions[serverUrl]?.accessToken, 'new-access');
    expect(sessions[serverUrl]?.refreshToken, 'new-refresh');
    provider.dispose();
  });

  test('device id update keeps an in-flight refresh rotation persisted',
      () async {
    const serverUrl = 'https://example.test';
    SharedPreferences.setMockInitialValues({'server_url': serverUrl});
    final sessions = <String, AuthSessionDto?>{
      serverUrl: AuthSessionDto.fromJson(
        _authSessionJson(
          accessToken: 'old-access',
          refreshToken: 'old-refresh',
          refreshExpiresAt: DateTime.now().add(const Duration(days: 30)),
        ),
      ),
    };
    final refreshStarted = Completer<void>();
    final refreshResponse = Completer<http.Response>();
    var accountRequests = 0;
    final client = MockClient((request) async {
      switch ('${request.method} ${request.url.path}') {
        case 'GET /api/v1/account':
          accountRequests += 1;
          if (accountRequests == 1) {
            expect(request.headers['authorization'], 'Bearer old-access');
            expect(request.headers['x-device-id'], 'device-old');
            return _apiError(401, 'ACCESS_TOKEN_EXPIRED');
          }
          expect(request.headers['authorization'], 'Bearer new-access');
          expect(request.headers['x-device-id'], 'device-new');
          return _jsonResponse(_accountJson('alice'));
        case 'POST /api/v1/auth/refresh':
          expect(jsonDecode(request.body), {
            'refreshToken': 'old-refresh',
            'deviceId': 'device-old',
          });
          refreshStarted.complete();
          return refreshResponse.future;
        default:
          fail('Unexpected request: ${request.method} ${request.url}');
      }
    });
    final provider = _providerWithBackedStore(client, sessions);
    await provider.loadSettings();
    await provider.setDeviceId('device-old');

    final refreshingAccount = provider.refreshAccount();
    await refreshStarted.future;
    await provider.setDeviceId('device-new');
    refreshResponse.complete(
      _jsonResponse(
        _authSessionJson(
          accessToken: 'new-access',
          refreshToken: 'new-refresh',
          refreshExpiresAt: DateTime.now().add(const Duration(days: 30)),
        ),
      ),
    );
    // Updating the device label must not replace the authentication context:
    // the successfully rotated credential and the retried account response
    // both still belong to the current signed-in user.
    await refreshingAccount;

    expect(accountRequests, 2);
    expect(sessions[serverUrl]?.accessToken, 'new-access');
    expect(sessions[serverUrl]?.refreshToken, 'new-refresh');
    provider.dispose();
  });

  test('does not restore an expired refresh session', () async {
    const serverUrl = 'https://example.test';
    SharedPreferences.setMockInitialValues({'server_url': serverUrl});
    final sessions = <String, AuthSessionDto?>{
      serverUrl: AuthSessionDto.fromJson(
        _authSessionJson(
          accessToken: 'expired-access',
          refreshToken: 'expired-refresh',
          refreshExpiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
        ),
      ),
    };
    final provider = ServerProvider(
      autoLoadSettings: false,
      tokenStoreFactory: (url) => _BackedTokenStore(sessions, url),
    );

    await provider.loadSettings();

    expect(provider.isLoggedIn, isFalse);
    expect(sessions[serverUrl], isNull);
    provider.dispose();
  });

  test('exposes status from the raw store behind the generation scope',
      () async {
    final stores = <String, _StatusTokenStore>{};
    final provider = ServerProvider(
      autoLoadSettings: false,
      tokenStoreFactory: (url) => stores.putIfAbsent(
        url,
        () => _StatusTokenStore(
          const TokenStorageStatus(
            backend: TokenStorageBackend.privateFileFallback,
            reason: 'keyring unavailable',
          ),
        ),
      ),
    );

    await provider.setServerUrl('https://one.example');
    expect(
      provider.tokenStorageStatus.backend,
      TokenStorageBackend.privateFileFallback,
    );
    expect(provider.tokenStorageStatus.reason, 'keyring unavailable');

    stores['https://one.example']!.status.value = const TokenStorageStatus(
      backend: TokenStorageBackend.memoryOnly,
      reason: 'file unavailable',
    );
    expect(
      provider.tokenStorageStatus.backend,
      TokenStorageBackend.memoryOnly,
    );

    await provider.setServerUrl('https://two.example');
    expect(
      provider.tokenStorageStatus.backend,
      TokenStorageBackend.privateFileFallback,
    );
    stores['https://one.example']!.status.value = const TokenStorageStatus(
      backend: TokenStorageBackend.platformSecure,
    );
    expect(
      provider.tokenStorageStatus.backend,
      TokenStorageBackend.privateFileFallback,
    );
    provider.dispose();
  });

  test('a superseded login cannot overwrite the current persisted session',
      () async {
    const serverUrl = 'https://example.test';
    final sessions = <String, AuthSessionDto?>{};
    final aliceRequestStarted = Completer<void>();
    final aliceResponse = Completer<http.Response>();
    final client = MockClient((request) async {
      switch ('${request.method} ${request.url.path}') {
        case 'GET /api/v1/server-info':
          return _jsonResponse(_serverInfoJson);
        case 'POST /api/v1/auth/login':
          final username =
              (jsonDecode(request.body) as Map<String, Object?>)['username'];
          if (username == 'alice') {
            aliceRequestStarted.complete();
            return aliceResponse.future;
          }
          expect(username, 'bob');
          return _jsonResponse(_authJsonFor('bob'));
        default:
          fail('Unexpected request: ${request.method} ${request.url}');
      }
    });
    final provider = _providerWithBackedStore(client, sessions);
    await provider.setServerUrl(serverUrl);
    await provider.checkServer();

    final firstLogin = provider.login('alice', 'alice-password');
    final firstLoginFailure =
        expectLater(firstLogin, throwsA(isA<StateError>()));
    await aliceRequestStarted.future;
    await provider.login('bob', 'bob-password');
    aliceResponse.complete(_jsonResponse(_authJsonFor('alice')));
    await firstLoginFailure;

    expect(provider.username, 'bob');
    expect(provider.accountId, 'user-bob');
    expect(sessions[serverUrl]?.user.username, 'bob');
    expect(sessions[serverUrl]?.refreshToken, 'refresh-bob');
    provider.dispose();
  });

  test('a delayed logout cannot clear a following login', () async {
    const serverUrl = 'https://example.test';
    final sessions = <String, AuthSessionDto?>{};
    final logoutRequestStarted = Completer<void>();
    final logoutResponse = Completer<http.Response>();
    final client = MockClient((request) async {
      switch ('${request.method} ${request.url.path}') {
        case 'GET /api/v1/server-info':
          return _jsonResponse(_serverInfoJson);
        case 'POST /api/v1/auth/login':
          final username = (jsonDecode(request.body)
              as Map<String, Object?>)['username']! as String;
          return _jsonResponse(_authJsonFor(username));
        case 'POST /api/v1/auth/logout':
          expect(request.headers['authorization'], 'Bearer access-alice');
          expect(jsonDecode(request.body), {'refreshToken': 'refresh-alice'});
          logoutRequestStarted.complete();
          return logoutResponse.future;
        default:
          fail('Unexpected request: ${request.method} ${request.url}');
      }
    });
    final provider = _providerWithBackedStore(client, sessions);
    await provider.setServerUrl(serverUrl);
    await provider.login('alice', 'alice-password');

    final delayedLogout = provider.logout();
    await logoutRequestStarted.future;
    expect(provider.isLoggedIn, isFalse);
    await provider.login('bob', 'bob-password');
    logoutResponse.complete(http.Response('', 204));
    await delayedLogout;

    expect(provider.username, 'bob');
    expect(sessions[serverUrl]?.user.username, 'bob');
    expect(sessions[serverUrl]?.refreshToken, 'refresh-bob');
    provider.dispose();
  });

  test('a failed replacement login does not restore the previous session',
      () async {
    const serverUrl = 'https://example.test';
    SharedPreferences.setMockInitialValues({'server_url': serverUrl});
    final sessions = <String, AuthSessionDto?>{
      serverUrl: AuthSessionDto.fromJson(_authJsonFor('alice')),
    };
    final client = MockClient((request) async {
      switch ('${request.method} ${request.url.path}') {
        case 'GET /api/v1/server-info':
          return _jsonResponse(_serverInfoJson);
        case 'POST /api/v1/auth/login':
          return _apiError(401, 'INVALID_CREDENTIALS');
        default:
          fail('Unexpected request: ${request.method} ${request.url}');
      }
    });
    final provider = _providerWithBackedStore(client, sessions);
    await provider.loadSettings();
    expect(provider.isLoggedIn, isTrue);

    await expectLater(
      provider.login('alice', 'wrong-password'),
      throwsA(
        isA<ServerApiException>().having(
          (error) => error.code,
          'code',
          'INVALID_CREDENTIALS',
        ),
      ),
    );

    expect(provider.isLoggedIn, isFalse);
    expect(sessions[serverUrl], isNull);
    provider.dispose();

    final restarted = _providerWithBackedStore(client, sessions);
    await restarted.loadSettings();
    expect(restarted.isLoggedIn, isFalse);
    restarted.dispose();
  });

  test('temporary-password challenge is completed before becoming logged in',
      () async {
    final client = MockClient((request) async {
      switch ('${request.method} ${request.url.path}') {
        case 'GET /api/v1/server-info':
          return _jsonResponse(_serverInfoJson);
        case 'POST /api/v1/auth/login':
          return _apiError(
            403,
            'PASSWORD_CHANGE_REQUIRED',
            details: {
              'passwordChangeToken': 'change-token',
              'passwordChangeTokenExpiresIn': 300,
              'user': _userJson,
            },
          );
        case 'POST /api/v1/auth/complete-password-change':
          expect(jsonDecode(request.body), {
            'passwordChangeToken': 'change-token',
            'newPassword': 'new-secure-password',
          });
          return _jsonResponse(_authJson);
        default:
          fail('Unexpected request: ${request.method} ${request.url}');
      }
    });
    final provider = _provider(client);
    await provider.setServerUrl('https://example.test');

    await expectLater(
      provider.login('alice', 'temporary-password'),
      throwsA(
        isA<ServerApiException>().having(
          (error) => error.code,
          'code',
          'PASSWORD_CHANGE_REQUIRED',
        ),
      ),
    );
    expect(provider.isLoggedIn, isFalse);
    expect(provider.passwordChangeRequired, isTrue);
    expect(provider.passwordChangeChallenge?.user.username, 'alice');

    await provider.completeRequiredPasswordChange('new-secure-password');
    expect(provider.isLoggedIn, isTrue);
    expect(provider.username, 'alice');
    expect(provider.passwordChangeRequired, isFalse);
    provider.dispose();
  });

  test('member manages only their profile and device sessions', () async {
    var username = 'alice';
    final client = MockClient((request) async {
      switch ('${request.method} ${request.url.path}') {
        case 'GET /api/v1/server-info':
          return _jsonResponse(_serverInfoJson);
        case 'POST /api/v1/auth/login':
          return _jsonResponse(_authJson);
        case 'GET /api/v1/account':
          return _jsonResponse(_accountJson(username));
        case 'PATCH /api/v1/account/username':
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['currentPassword'], 'old-secure-password');
          username = body['username'] as String;
          return _jsonResponse(_accountJson(username));
        case 'GET /api/v1/account/sessions':
          return _jsonResponse({
            'items': [_otherDeviceJson, _currentDeviceJson],
          });
        case 'DELETE /api/v1/account/sessions/other-refresh':
          return http.Response('', 204);
        case 'PATCH /api/v1/account/password':
          return _jsonResponse({
            'passwordChangedAt': _now,
            'revokedDeviceSessionCount': 2,
            'reauthenticationRequired': true,
          });
        default:
          fail('Unexpected request: ${request.method} ${request.url}');
      }
    });
    final provider = _provider(client);
    await provider.setServerUrl('https://example.test');
    await provider.login('alice', 'old-secure-password');

    expect((await provider.refreshAccount()).username, 'alice');
    await provider.changeUsername(
      username: 'alice-new',
      currentPassword: 'old-secure-password',
    );
    expect(provider.username, 'alice-new');

    final sessions = await provider.refreshDeviceSessions();
    expect(sessions, hasLength(2));
    await provider.revokeDeviceSession(sessions.first);
    expect(provider.deviceSessions.map((item) => item.sessionId),
        ['current-refresh']);
    expect(provider.isLoggedIn, isTrue);

    final result = await provider.changePassword(
      currentPassword: 'old-secure-password',
      newPassword: 'new-secure-password',
    );
    expect(result.reauthenticationRequired, isTrue);
    expect(provider.isLoggedIn, isFalse);
    expect(provider.deviceSessions, isEmpty);
    provider.dispose();
  });
}

ServerProvider _provider(http.Client client) => ServerProvider(
      autoLoadSettings: false,
      tokenStoreFactory: (_) => MemoryTokenStore(),
      apiFactory: ({
        required baseUri,
        required tokenStore,
        required deviceId,
        required onAuthInvalidated,
      }) =>
          ServerApi(
        baseUri: baseUri,
        tokenStore: tokenStore,
        deviceId: deviceId,
        onAuthInvalidated: onAuthInvalidated,
        httpClient: client,
      ),
    );

ServerProvider _providerWithBackedStore(
  http.Client client,
  Map<String, AuthSessionDto?> sessions,
) =>
    ServerProvider(
      autoLoadSettings: false,
      tokenStoreFactory: (url) => _BackedTokenStore(sessions, url),
      apiFactory: ({
        required baseUri,
        required tokenStore,
        required deviceId,
        required onAuthInvalidated,
      }) =>
          ServerApi(
        baseUri: baseUri,
        tokenStore: tokenStore,
        deviceId: deviceId,
        onAuthInvalidated: onAuthInvalidated,
        httpClient: client,
      ),
    );

const _now = '2026-07-13T00:00:00.000Z';
const _userJson = {'id': 'user-1', 'username': 'alice', 'role': 'user'};
const _serverInfoJson = {
  'serverInstanceId': 'server-1',
  'protocolMin': 1,
  'protocolMax': 1,
  'features': <String>[],
  'serverTime': _now,
  'environment': 'test',
};
const _authJson = {
  'accessToken': 'access-token',
  'accessTokenExpiresIn': 900,
  'refreshToken': 'refresh-token',
  'refreshTokenExpiresAt': '2026-08-13T00:00:00.000Z',
  'user': _userJson,
};

Map<String, Object?> _authJsonFor(String username) => {
      'accessToken': 'access-$username',
      'accessTokenExpiresIn': 900,
      'refreshToken': 'refresh-$username',
      'refreshTokenExpiresAt': '2026-08-13T00:00:00.000Z',
      'user': {
        'id': 'user-$username',
        'username': username,
        'role': 'user',
      },
    };

Map<String, Object?> _accountJson(String username) => {
      'id': 'user-1',
      'username': username,
      'role': 'user',
      'mustChangePassword': false,
      'createdAt': _now,
      'updatedAt': _now,
      'passwordChangedAt': null,
      'usernameChangedAt': null,
    };

const _otherDeviceJson = {
  'sessionId': 'other-refresh',
  'deviceId': 'other-device',
  'createdAt': _now,
  'expiresAt': '2026-08-13T00:00:00.000Z',
  'lastUsedAt': _now,
  'userAgent': null,
  'ipAddress': null,
  'current': false,
};
const _currentDeviceJson = {
  'sessionId': 'current-refresh',
  'deviceId': 'current-device',
  'createdAt': _now,
  'expiresAt': '2026-08-13T00:00:00.000Z',
  'lastUsedAt': _now,
  'userAgent': null,
  'ipAddress': null,
  'current': true,
};

http.Response _jsonResponse(Object? body, [int statusCode = 200]) =>
    http.Response(
      jsonEncode(body),
      statusCode,
      headers: {'content-type': 'application/json'},
    );

http.Response _apiError(
  int statusCode,
  String code, {
  Object? details,
}) =>
    _jsonResponse({
      'error': {
        'code': code,
        'message': code,
        'requestId': 'request-1',
        if (details != null) 'details': details,
      },
    }, statusCode);

Map<String, Object?> _authSessionJson({
  required String accessToken,
  required String refreshToken,
  required DateTime refreshExpiresAt,
}) =>
    {
      'accessToken': accessToken,
      'accessTokenExpiresIn': 900,
      'refreshToken': refreshToken,
      'refreshTokenExpiresAt': refreshExpiresAt.toUtc().toIso8601String(),
      'user': _userJson,
    };

final class _BackedTokenStore implements TokenStore {
  _BackedTokenStore(this.sessions, this.serverUrl);

  final Map<String, AuthSessionDto?> sessions;
  final String serverUrl;

  @override
  Future<AuthSessionDto?> read() async => sessions[serverUrl];

  @override
  Future<void> write(AuthSessionDto session) async {
    sessions[serverUrl] = session;
  }

  @override
  Future<void> clear() async {
    sessions[serverUrl] = null;
  }
}

final class _StatusTokenStore implements TokenStore, TokenStorageStatusSource {
  _StatusTokenStore(TokenStorageStatus initial)
      : status = ValueNotifier(initial);

  final ValueNotifier<TokenStorageStatus> status;
  AuthSessionDto? session;

  @override
  ValueListenable<TokenStorageStatus> get storageStatus => status;

  @override
  Future<AuthSessionDto?> read() async => session;

  @override
  Future<void> write(AuthSessionDto session) async {
    this.session = session;
  }

  @override
  Future<void> clear() async {
    session = null;
  }
}
