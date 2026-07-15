import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/models/collaboration_dto.dart';
import 'package:openlogtool/providers/server_provider.dart';
import 'package:openlogtool/providers/snackbar_log_provider.dart';
import 'package:openlogtool/services/secure_token_store.dart';
import 'package:openlogtool/services/server_api.dart';
import 'package:openlogtool/widgets/settings/server_account_settings.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('shows degraded token-storage keys and localized warnings',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = _StatusTokenStore(
      const TokenStorageStatus(
        backend: TokenStorageBackend.privateFileFallback,
        reason: 'keyring unavailable',
      ),
    );
    final provider = ServerProvider(
      autoLoadSettings: false,
      tokenStoreFactory: (_) => store,
    );
    await provider.setServerUrl('https://example.test');

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ServerProvider>.value(value: provider),
          ChangeNotifierProvider(create: (_) => SnackbarLogProvider()),
        ],
        child: const MaterialApp(
          locale: Locale('en', 'US'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ServerAccountSettings(cardPadding: 16),
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(
        const Key('token-storage-warning-privateFileFallback'),
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'The system keyring is unavailable. Your sign-in is stored in a '
        'private file readable only by your Linux user and will move back to '
        'secure storage when a keyring becomes available.',
      ),
      findsOneWidget,
    );

    store.status.value = const TokenStorageStatus(
      backend: TokenStorageBackend.memoryOnly,
      reason: 'secure stores unavailable',
    );
    await tester.pump();

    expect(
      find.byKey(const Key('token-storage-warning-privateFileFallback')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('token-storage-warning-memoryOnly')),
      findsOneWidget,
    );
    expect(
      find.text(
        'Secure credential storage is unavailable. This sign-in lasts only '
        'while the app is running; you will need to sign in again after '
        'exiting.',
      ),
      findsOneWidget,
    );

    provider.dispose();
    store.status.dispose();
  });

  testWidgets(
      'restored server URL updates the field and recheck keeps the session',
      (tester) async {
    const serverUrl = 'https://example.test';
    SharedPreferences.setMockInitialValues({'server_url': serverUrl});
    final restoredSession = AuthSessionDto(
      accessToken: 'restored-access',
      accessTokenExpiresIn: 900,
      refreshToken: 'restored-refresh',
      refreshTokenExpiresAt: DateTime.now().add(const Duration(days: 30)),
      user: const ApiUserDto(
        id: 'user-1',
        username: 'alice',
        role: 'user',
      ),
    );
    Uri? checkedUri;
    final client = MockClient((request) async {
      checkedUri = request.url;
      expect(request.method, 'GET');
      expect(request.url.path, '/api/v1/server-info');
      return _jsonResponse({
        'serverInstanceId': 'server-1',
        'protocolMin': 1,
        'protocolMax': 1,
        'features': <String>[],
        'serverTime': '2026-07-13T00:00:00Z',
        'environment': 'test',
      });
    });
    final provider = ServerProvider(
      autoLoadSettings: false,
      tokenStoreFactory: (_) => MemoryTokenStore(restoredSession),
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

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ServerProvider>.value(value: provider),
          ChangeNotifierProvider(create: (_) => SnackbarLogProvider()),
        ],
        child: const MaterialApp(
          locale: Locale('en', 'US'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ServerAccountSettings(cardPadding: 16),
            ),
          ),
        ),
      ),
    );

    TextField serverUrlField() => tester.widget<TextField>(
          find.byKey(const Key('server-url-field')),
        );

    expect(serverUrlField().controller!.text, isEmpty);

    await provider.loadSettings();
    await tester.pump();

    expect(serverUrlField().controller!.text, serverUrl);
    expect(provider.isLoggedIn, isTrue);
    expect(find.text('alice'), findsOneWidget);

    await tester.tap(find.byKey(const Key('server-check-button')));
    await _pumpUntil(tester, () => provider.serverInfo != null);

    expect(checkedUri, Uri.parse('$serverUrl/api/v1/server-info'));
    expect(provider.serverUrl, serverUrl);
    expect(provider.isLoggedIn, isTrue);
    expect(find.text('alice'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('server-url-field')),
      'https://pending-edit.test',
    );
    await provider.setDeviceId('device-1');
    await tester.pump();

    expect(serverUrlField().controller!.text, 'https://pending-edit.test');

    provider.dispose();
  });

  testWidgets('temporary-password sign-in requires setting a new password',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final client = MockClient((request) async {
      switch ('${request.method} ${request.url.path}') {
        case 'GET /api/v1/server-info':
          return _jsonResponse({
            'serverInstanceId': 'server-1',
            'protocolMin': 1,
            'protocolMax': 1,
            'features': <String>[],
            'serverTime': '2026-07-13T00:00:00Z',
            'environment': 'test',
          });
        case 'POST /api/v1/auth/login':
          return _jsonResponse({
            'error': {
              'code': 'PASSWORD_CHANGE_REQUIRED',
              'message': 'Temporary password must be changed',
              'requestId': 'request-1',
              'details': {
                'passwordChangeToken': 'change-token',
                'passwordChangeTokenExpiresIn': 300,
                'user': {
                  'id': 'user-1',
                  'username': 'alice',
                  'role': 'user',
                },
              },
            },
          }, 403);
        case 'POST /api/v1/auth/complete-password-change':
          return _jsonResponse({
            'accessToken': 'access-token',
            'accessTokenExpiresIn': 900,
            'refreshToken': 'refresh-token',
            'refreshTokenExpiresAt': '2026-08-13T00:00:00Z',
            'user': {
              'id': 'user-1',
              'username': 'alice',
              'role': 'user',
            },
          });
        default:
          fail('Unexpected request: ${request.method} ${request.url}');
      }
    });
    final provider = ServerProvider(
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
    await provider.setServerUrl('https://example.test');

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ServerProvider>.value(value: provider),
          ChangeNotifierProvider(create: (_) => SnackbarLogProvider()),
        ],
        child: const MaterialApp(
          locale: Locale('en', 'US'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ServerAccountSettings(cardPadding: 16),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('server-login-button')));
    await _pumpUntilFound(
      tester,
      find.byKey(const Key('server-auth-submit-button')),
    );
    await tester.enterText(
      find.byKey(const Key('server-auth-username-field')),
      'alice',
    );
    await tester.enterText(
      find.byKey(const Key('server-auth-password-field')),
      'temporary-password',
    );
    await tester.tap(find.byKey(const Key('server-auth-submit-button')));
    await _pumpUntilFound(
      tester,
      find.byKey(const Key('required-password-change-dialog')),
    );

    expect(
      find.text('Temporary password must be changed'),
      findsOneWidget,
    );
    expect(provider.isLoggedIn, isFalse);

    await tester.enterText(
      find.byKey(const Key('required-new-password-field')),
      'new-secure-password',
    );
    await tester.enterText(
      find.byKey(const Key('required-confirm-password-field')),
      'new-secure-password',
    );
    await tester.tap(
      find.byKey(const Key('complete-password-change-button')),
    );
    await _pumpUntilFound(tester, find.byKey(const Key('account-username')));

    expect(
        find.byKey(const Key('required-password-change-dialog')), findsNothing);
    expect(find.byKey(const Key('account-username')), findsOneWidget);
    expect(find.text('alice'), findsOneWidget);
    expect(provider.isLoggedIn, isTrue);
  });

  testWidgets('sign-in keeps legacy non-empty credential compatibility',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    var loginRequested = false;
    final client = MockClient((request) async {
      switch ('${request.method} ${request.url.path}') {
        case 'GET /api/v1/server-info':
          return _jsonResponse({
            'serverInstanceId': 'server-1',
            'protocolMin': 1,
            'protocolMax': 1,
            'features': <String>[],
            'serverTime': '2026-07-13T00:00:00Z',
            'environment': 'test',
          });
        case 'POST /api/v1/auth/login':
          loginRequested = true;
          expect(jsonDecode(request.body), {
            'username': 'x',
            'password': 'short',
          });
          return _jsonResponse({
            'accessToken': 'access-token',
            'accessTokenExpiresIn': 900,
            'refreshToken': 'refresh-token',
            'refreshTokenExpiresAt': '2026-08-13T00:00:00Z',
            'user': {
              'id': 'user-1',
              'username': 'x',
              'role': 'user',
            },
          });
        default:
          fail('Unexpected request: ${request.method} ${request.url}');
      }
    });
    final provider = ServerProvider(
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
    await provider.setServerUrl('https://example.test');

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ServerProvider>.value(value: provider),
          ChangeNotifierProvider(create: (_) => SnackbarLogProvider()),
        ],
        child: const MaterialApp(
          locale: Locale('en', 'US'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ServerAccountSettings(cardPadding: 16),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('server-login-button')));
    await _pumpUntilFound(
      tester,
      find.byKey(const Key('server-auth-submit-button')),
    );
    await tester.enterText(
      find.byKey(const Key('server-auth-username-field')),
      'x',
    );
    await tester.enterText(
      find.byKey(const Key('server-auth-password-field')),
      'short',
    );
    await tester.tap(find.byKey(const Key('server-auth-submit-button')));
    await _pumpUntilFound(tester, find.byKey(const Key('account-username')));

    expect(loginRequested, isTrue);
    expect(provider.isLoggedIn, isTrue);
  });
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 40; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 40; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 50));
    if (condition()) return;
  }
  fail('Timed out waiting for condition');
}

http.Response _jsonResponse(Object? body, [int statusCode = 200]) =>
    http.Response(
      jsonEncode(body),
      statusCode,
      headers: {'content-type': 'application/json'},
    );

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
