import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/providers/server_provider.dart';
import 'package:openlogtool/providers/snackbar_log_provider.dart';
import 'package:openlogtool/services/server_api.dart';
import 'package:openlogtool/widgets/settings/server_account_settings.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
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

http.Response _jsonResponse(Object? body, [int statusCode = 200]) =>
    http.Response(
      jsonEncode(body),
      statusCode,
      headers: {'content-type': 'application/json'},
    );
