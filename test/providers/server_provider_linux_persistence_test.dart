import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openlogtool/providers/server_provider.dart';
import 'package:openlogtool/services/private_file_secure_values.dart';
import 'package:openlogtool/services/secure_token_store.dart';
import 'package:openlogtool/services/server_api.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'restart restores newer Linux fallback over stale recovered keyring',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final support = await Directory.systemTemp.createTemp(
        'openlogtool-provider-linux-persistence-',
      );
      addTearDown(() => support.delete(recursive: true));
      final primary = _ControllableSecureValues();
      final deletionMarkers = _MemoryDeletionMarkers();
      final client = MockClient((request) async {
        switch ('${request.method} ${request.url.path}') {
          case 'GET /api/v1/server-info':
            return _jsonResponse(<String, Object?>{
              'serverInstanceId': 'server-1',
              'protocolMin': 1,
              'protocolMax': 1,
              'features': <String>[],
              'serverTime': '2026-07-13T00:00:00.000Z',
              'environment': 'test',
            });
          case 'POST /api/v1/auth/login':
            final username = (jsonDecode(request.body)
                as Map<String, Object?>)['username']! as String;
            return _jsonResponse(_authJson(username));
          default:
            fail('Unexpected request: ${request.method} ${request.url}');
        }
      });
      TokenStore tokenStoreFactory(String serverUrl) => SecureTokenStore(
            serverUrl: serverUrl,
            secureValues: ResilientSecureValueStore(
              primary: primary,
              privateFileFallback: PlatformPrivateSecureValueStore(
                PlatformPrivateSecureValueBackend(
                  supportDirectory: () async => support.path,
                ),
              ),
              deletionMarkers: deletionMarkers,
            ),
          );
      ServerProvider createProvider() => ServerProvider(
            autoLoadSettings: false,
            tokenStoreFactory: tokenStoreFactory,
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

      final first = createProvider();
      await first.setServerUrl('https://example.test');
      await first.login('alice', 'password');
      expect(_storedUsername(primary), 'alice');

      // The next login rotates the server session while Secret Service is
      // unavailable. The keyring retains Alice, while Bob is persisted in the
      // private fallback.
      primary.available = false;
      await first.login('bob', 'password');
      expect(first.username, 'bob');
      expect(_storedUsername(primary), 'alice');
      final fallbackFile = File(
        p.join(
          support.path,
          'secure_storage_fallback',
          'auth_sessions.json',
        ),
      );
      expect(await fallbackFile.exists(), isTrue);
      first.dispose();

      // Simulate the next process with Secret Service available again.
      primary.available = true;
      final restarted = createProvider();
      await restarted.loadSettings();

      expect(restarted.isLoggedIn, isTrue);
      expect(restarted.username, 'bob');
      expect(_storedUsername(primary), 'bob');
      expect(await fallbackFile.exists(), isFalse);
      restarted.dispose();
    },
    skip: !Platform.isLinux,
  );
}

Map<String, Object?> _authJson(String username) => <String, Object?>{
      'accessToken': 'access-$username',
      'accessTokenExpiresIn': 900,
      'refreshToken': 'refresh-$username',
      'refreshTokenExpiresAt': '2030-01-01T00:00:00.000Z',
      'user': <String, Object?>{
        'id': 'user-$username',
        'username': username,
        'role': 'user',
      },
    };

http.Response _jsonResponse(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: const <String, String>{'content-type': 'application/json'},
    );

String? _storedUsername(_ControllableSecureValues values) {
  if (values.values.isEmpty) return null;
  final session =
      jsonDecode(values.values.values.single) as Map<String, Object?>;
  return (session['user']! as Map<String, Object?>)['username']! as String;
}

final class _ControllableSecureValues implements SecureValueStore {
  final Map<String, String> values = <String, String>{};
  bool available = true;

  @override
  Future<String?> read(String key) async {
    if (!available) throw StateError('keyring unavailable');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (!available) throw StateError('keyring unavailable');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    if (!available) throw StateError('keyring unavailable');
    values.remove(key);
  }
}

final class _MemoryDeletionMarkers implements DeletionMarkerStore {
  final Map<String, bool> states = <String, bool>{};

  @override
  Future<bool?> read(String key) async => states[key];

  @override
  Future<void> mark(String key) async {
    states[key] = true;
  }

  @override
  Future<void> unmark(String key) async {
    states[key] = false;
  }

  @override
  Future<void> forget(String key) async {
    states.remove(key);
  }
}
