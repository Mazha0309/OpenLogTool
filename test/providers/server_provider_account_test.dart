import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openlogtool/providers/server_provider.dart';
import 'package:openlogtool/services/server_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

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
