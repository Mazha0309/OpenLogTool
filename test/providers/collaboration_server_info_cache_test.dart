import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openlogtool/models/collaboration_dto.dart';
import 'package:openlogtool/providers/collaboration_provider.dart';
import 'package:openlogtool/providers/log_provider.dart';
import 'package:openlogtool/providers/server_provider.dart';
import 'package:openlogtool/providers/session_provider.dart';
import 'package:openlogtool/services/server_api.dart';
import 'package:openlogtool/src/bridge/frb_generated.dart';
import 'package:openlogtool/src/bridge/models/session.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('first collaboration refresh caches capabilities after login restore',
      () async {
    const serverUrl = 'https://example.test';
    SharedPreferences.setMockInitialValues({'server_url': serverUrl});
    RustLib.initMock(api: _RustApiMock(jsonEncode(_bindingJson)));
    addTearDown(RustLib.dispose);

    final storedSessions = <String, AuthSessionDto?>{
      serverUrl: AuthSessionDto(
        accessToken: 'restored-access',
        accessTokenExpiresIn: 900,
        refreshToken: 'restored-refresh',
        refreshTokenExpiresAt: DateTime.now().add(const Duration(days: 30)),
        user: const ApiUserDto(
          id: 'user-1',
          username: 'owner',
          role: 'user',
        ),
      ),
    };
    var serverInfoRequests = 0;
    final client = MockClient((request) async {
      switch ('${request.method} ${request.url.path}') {
        case 'GET /api/v1/server-info':
          serverInfoRequests += 1;
          return _jsonResponse(_serverInfoJson);
        case 'GET /api/v1/sessions/session-1/membership':
          return _jsonResponse({'membership': _membershipJson});
        case 'GET /api/v1/sessions/session-1/snapshot':
          return _jsonResponse(_snapshotJson);
        case 'GET /api/v1/sessions/session-1/members':
          return _jsonResponse({
            'members': [_membershipJson],
          });
        default:
          fail('Unexpected request: ${request.method} ${request.url}');
      }
    });
    final server = ServerProvider(
      autoLoadSettings: false,
      tokenStoreFactory: (url) => _BackedTokenStore(storedSessions, url),
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
    final sessions = _TestSessionProvider();
    final logs = LogProvider(
      sessionListLoader: () async => const [_session],
      sessionLogPageLoader: (_, __, ___) async => const [],
    );
    final collaboration = CollaborationProvider();
    addTearDown(collaboration.dispose);
    addTearDown(logs.dispose);
    addTearDown(sessions.dispose);
    addTearDown(server.dispose);

    await server.loadSettings();
    await server.setDeviceId('device-1');
    expect(server.isLoggedIn, isTrue);
    expect(server.serverInfo, isNull);
    expect(collaboration.supportsPublicShareManagement, isFalse);

    collaboration.updateDependencies(server, sessions, logs);
    await _waitUntil(
      () => collaboration.state == CollaborationState.ready,
    );

    expect(serverInfoRequests, 1);
    expect(server.serverInfo, isNotNull);
    expect(
      server.serverInfo!.features,
      containsAll(const ['publicLiveshare', 'publicLivesharePage']),
    );
    expect(collaboration.isOwner, isTrue);
    expect(collaboration.supportsPublicShareManagement, isTrue);
  });
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Collaboration refresh did not reach the expected state');
}

http.Response _jsonResponse(Object? body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );

const _session = Session(
  sessionId: 'session-1',
  title: 'Restored net',
  status: 'active',
  createdAt: '2026-07-13T00:00:00.000Z',
  updatedAt: '2026-07-13T00:00:00.000Z',
);

const _serverInfoJson = {
  'serverInstanceId': 'server-1',
  'protocolMin': 1,
  'protocolMax': 1,
  'features': [
    'sessionSnapshots',
    'sessionSnapshotTombstones',
    'sessionMembership',
    'publicLiveshare',
    'publicLivesharePage',
  ],
  'serverTime': '2026-07-13T00:00:00.000Z',
  'environment': 'test',
};

const _membershipJson = {
  'membershipId': 'membership-1',
  'sessionId': 'session-1',
  'userId': 'user-1',
  'username': 'owner',
  'role': 'owner',
  'version': 1,
  'joinedAt': '2026-07-13T00:00:00.000Z',
  'updatedAt': '2026-07-13T00:00:00.000Z',
  'removedAt': null,
};

const _bindingJson = {
  'serverInstanceId': 'server-1',
  'serverOrigin': 'https://example.test',
  'accountId': 'user-1',
  'sessionId': 'session-1',
  'membershipId': 'membership-1',
  'membershipVersion': 1,
  'role': 'owner',
  'replicaState': 'ready',
  'lastAppliedSeq': 0,
  'lastSeenHeadSeq': 0,
  'revokedAt': null,
};

const _snapshotJson = {
  'protocolVersion': 1,
  'session': {
    'sessionId': 'session-1',
    'title': 'Restored net',
    'status': 'active',
    'version': 1,
    'role': 'owner',
    'highWatermarkSeq': 0,
    'createdAt': '2026-07-13T00:00:00.000Z',
    'updatedAt': '2026-07-13T00:00:00.000Z',
    'closedAt': null,
    'deletedAt': null,
  },
  'highWatermarkSeq': 0,
  'includesDeletedLogs': true,
  'logs': [],
};

class _TestSessionProvider extends SessionProvider {
  @override
  Future<void> get ready => Future<void>.value();

  @override
  String get currentSessionId => _session.sessionId;

  @override
  Session get currentSession => _session;
}

class _BackedTokenStore implements TokenStore {
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

class _RustApiMock implements RustLibApi {
  _RustApiMock(this.bindingJson);

  final String bindingJson;

  @override
  Future<String> crateApiCollaborationGetOrCreateDeviceId() async => 'device-1';

  @override
  Future<String?> crateApiCollaborationGetSessionCollaborationBinding({
    required String sessionId,
  }) async {
    expect(sessionId, 'session-1');
    return bindingJson;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
