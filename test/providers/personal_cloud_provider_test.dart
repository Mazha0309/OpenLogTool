import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openlogtool/models/collaboration_dto.dart';
import 'package:openlogtool/models/log_entry.dart' as model;
import 'package:openlogtool/providers/collaboration_provider.dart';
import 'package:openlogtool/providers/log_provider.dart';
import 'package:openlogtool/providers/personal_cloud_provider.dart';
import 'package:openlogtool/providers/server_provider.dart';
import 'package:openlogtool/providers/session_provider.dart';
import 'package:openlogtool/services/server_api.dart';
import 'package:openlogtool/src/bridge/models/log_entry.dart' as bridge;
import 'package:openlogtool/src/bridge/models/session.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('matches the shared complete non-empty checksum vector', () {
    expect(
      personalSnapshotContentChecksum(_canonicalNonEmptySnapshot),
      'b00518f22d8b76988bdc3c7c0228e5ef8b3b5fd13755da5881f3406d07d6d510',
    );
  });

  test(
    'established baseline automatically uploads an ordinary local record change',
    () async {
      const baselineRevision = 6;
      final baselineChecksum = _snapshotChecksum(
        _canonicalSessionOnlySnapshot,
      );
      SharedPreferences.setMockInitialValues({
        'server_url': _serverUrl,
        'personal_cloud_v1_local_owner_scope': _scopeIdentity('user-1'),
        ..._baselinePreferences(
          accountId: 'user-1',
          revision: baselineRevision,
          localChecksum: baselineChecksum,
          databaseRevision: 0,
        ),
        'local_database_replacement_revision': 0,
      });
      var metadataReads = 0;
      var uploads = 0;
      final client = MockClient((request) async {
        if (_isServerInfoRequest(request)) {
          return _jsonResponse(_serverInfoJson());
        }
        switch ('${request.method} ${request.url.path}') {
          case 'GET /api/v1/account/personal-snapshot':
            metadataReads += 1;
            return _jsonResponse({
              'personalSnapshot': _metadataFor(
                revision: baselineRevision,
                snapshot: _canonicalSessionOnlySnapshot,
              ),
            });
          case 'PUT /api/v1/account/personal-snapshot':
            uploads += 1;
            expect(request.headers['if-match'], '"$baselineRevision"');
            final body =
                Map<String, Object?>.from(jsonDecode(request.body) as Map);
            expect(body['expectedRevision'], baselineRevision);
            expect(
              body['confirmation'],
              'REPLACE_PERSONAL_CLOUD_SNAPSHOT',
            );
            expect(body['snapshot'], _canonicalNonEmptySnapshot);
            return _jsonResponse({
              'replaced': true,
              'personalSnapshot': _metadataFor(
                revision: baselineRevision + 1,
                snapshot: _canonicalNonEmptySnapshot,
              ),
            });
          default:
            fail('Unexpected request: ${request.method} ${request.url}');
        }
      });
      final harness = await _createHarness(
        client: client,
        exporter: () async => jsonEncode(_canonicalNonEmptySnapshot),
      );

      await _waitFor(
        () => harness.cloud.state == PersonalCloudSyncState.upToDate,
      );

      expect(metadataReads, 1);
      expect(uploads, 1);
      expect(harness.cloud.cloudMeta?.revision, baselineRevision + 1);
      expect(
        harness.cloud.localSnapshotToken,
        _snapshotChecksum(_canonicalNonEmptySnapshot),
      );
      expect(harness.cloud.decisionReason, isNull);
    },
  );

  test(
    'unchanged local baseline automatically compare-replaces a newer cloud revision',
    () async {
      final localChecksum = _snapshotChecksum(_localSnapshot);
      SharedPreferences.setMockInitialValues({
        'server_url': _serverUrl,
        'personal_cloud_v1_local_owner_scope': _scopeIdentity('user-1'),
        ..._baselinePreferences(
          accountId: 'user-1',
          revision: 1,
          localChecksum: localChecksum,
          databaseRevision: 0,
        ),
        'local_database_replacement_revision': 0,
      });
      var downloads = 0;
      var replacerCalls = 0;
      final client = MockClient((request) async {
        if (_isServerInfoRequest(request)) {
          return _jsonResponse(_serverInfoJson());
        }
        switch ('${request.method} ${request.url.path}') {
          case 'GET /api/v1/account/personal-snapshot':
            return _jsonResponse({
              'personalSnapshot': _metadataFor(
                revision: 2,
                snapshot: _canonicalNonEmptySnapshot,
              ),
            });
          case 'GET /api/v1/account/personal-snapshot/download':
            downloads += 1;
            return _downloadResponse(
              revision: 2,
              snapshot: _canonicalNonEmptySnapshot,
            );
          default:
            fail('Unexpected request: ${request.method} ${request.url}');
        }
      });
      final harness = await _createHarness(
        client: client,
        replacer: (jsonData, expectedLocalJsonData) async {
          replacerCalls += 1;
          expect(jsonDecode(jsonData), _canonicalNonEmptySnapshot);
          expect(jsonDecode(expectedLocalJsonData), _localSnapshot);
          return '{"sessionCount":1,"logCount":1}';
        },
      );

      await _waitFor(
        () => harness.cloud.state == PersonalCloudSyncState.upToDate,
      );

      expect(downloads, 1);
      expect(replacerCalls, 1);
      expect(harness.collaboration.maintenanceCalls, 1);
      expect(harness.cloud.cloudMeta?.revision, 2);
      expect(harness.cloud.localSessionCount, 1);
      expect(harness.cloud.localLogCount, 1);
      expect(
        harness.cloud.localSnapshotToken,
        _snapshotChecksum(_canonicalNonEmptySnapshot),
      );
      expect(harness.cloud.decisionReason, isNull);
    },
  );

  test(
    'new account with local data and empty cloud waits for explicit replace',
    () async {
      SharedPreferences.setMockInitialValues({
        'server_url': _serverUrl,
      });
      var metadataReads = 0;
      var replacements = 0;
      final client = MockClient((request) async {
        if (_isServerInfoRequest(request)) {
          return _jsonResponse(_serverInfoJson());
        }
        expect(request.headers['authorization'], 'Bearer access-token');
        switch ('${request.method} ${request.url.path}') {
          case 'GET /api/v1/account/personal-snapshot':
            metadataReads += 1;
            return _jsonResponse({
              'personalSnapshot': _emptyMetadata,
            });
          case 'PUT /api/v1/account/personal-snapshot':
            replacements += 1;
            expect(request.headers['if-match'], '"0"');
            final body =
                Map<String, Object?>.from(jsonDecode(request.body) as Map);
            expect(body['expectedRevision'], 0);
            expect(
              body['confirmation'],
              'REPLACE_PERSONAL_CLOUD_SNAPSHOT',
            );
            expect(body['snapshot'], _localSnapshot);
            return _jsonResponse({
              'replaced': true,
              'personalSnapshot': _metadataFor(
                revision: 1,
                snapshot: _localSnapshot,
              ),
            });
          default:
            fail('Unexpected request: ${request.method} ${request.url}');
        }
      });
      final harness = await _createHarness(client: client);

      await _waitFor(
        () => harness.cloud.state == PersonalCloudSyncState.decisionRequired,
      );
      expect(
        harness.cloud.decisionReason,
        PersonalCloudDecisionReason.differentAccountData,
      );
      expect(harness.cloud.localSessionCount, 1);
      expect(
        harness.cloud.localSnapshotToken,
        _snapshotChecksum(_localSnapshot),
      );
      expect(harness.cloud.cloudMeta?.exists, isFalse);
      expect(metadataReads, 1);
      expect(replacements, 0, reason: 'first login must never upload silently');

      await harness.cloud.replaceCloudWithLocal(
        expectedCloudRevision: harness.cloud.cloudMeta!.revision,
        expectedLocalSnapshotToken: harness.cloud.localSnapshotToken!,
      );

      expect(harness.cloud.state, PersonalCloudSyncState.upToDate);
      expect(harness.cloud.cloudMeta?.revision, 1);
      expect(replacements, 1);
    },
  );

  test('different local owner scope blocks automatic upload and download',
      () async {
    SharedPreferences.setMockInitialValues({
      'server_url': _serverUrl,
      'personal_cloud_v1_local_owner_scope': _scopeIdentity('user-a'),
    });
    var metadataReads = 0;
    var downloads = 0;
    var replacements = 0;
    var replacerCalls = 0;
    final client = MockClient((request) async {
      if (_isServerInfoRequest(request)) {
        return _jsonResponse(_serverInfoJson());
      }
      switch ('${request.method} ${request.url.path}') {
        case 'GET /api/v1/account/personal-snapshot':
          metadataReads += 1;
          return _jsonResponse({
            'personalSnapshot': _metadataFor(
              revision: 7,
              snapshot: _remoteSnapshot,
            ),
          });
        case 'GET /api/v1/account/personal-snapshot/download':
          downloads += 1;
          return _downloadResponse(revision: 7, snapshot: _remoteSnapshot);
        case 'PUT /api/v1/account/personal-snapshot':
          replacements += 1;
          return _jsonResponse({});
        default:
          fail('Unexpected request: ${request.method} ${request.url}');
      }
    });
    final harness = await _createHarness(
      client: client,
      accountId: 'user-b',
      replacer: (jsonData, expectedLocalJsonData) async {
        replacerCalls += 1;
        return '{}';
      },
    );

    await _waitFor(
      () => harness.cloud.state == PersonalCloudSyncState.decisionRequired,
    );

    expect(
      harness.cloud.decisionReason,
      PersonalCloudDecisionReason.differentAccountData,
    );
    expect(metadataReads, 1);
    expect(downloads, 0);
    expect(replacements, 0);
    expect(replacerCalls, 0);
  });

  test(
    'same URL with a different server instance never reuses owner or baseline',
    () async {
      final localChecksum = _snapshotChecksum(_localSnapshot);
      SharedPreferences.setMockInitialValues({
        'server_url': _serverUrl,
        'personal_cloud_v1_local_owner_scope': _scopeIdentity('user-1'),
        ..._baselinePreferences(
          accountId: 'user-1',
          revision: 1,
          localChecksum: localChecksum,
          databaseRevision: 0,
        ),
        'local_database_replacement_revision': 0,
      });
      var serverInstanceId = 'server-1';
      var metadataReads = 0;
      var uploads = 0;
      final client = MockClient((request) async {
        if (_isServerInfoRequest(request)) {
          return _jsonResponse(
            _serverInfoJson(serverInstanceId: serverInstanceId),
          );
        }
        switch ('${request.method} ${request.url.path}') {
          case 'GET /api/v1/account/personal-snapshot':
            metadataReads += 1;
            return _jsonResponse({
              'personalSnapshot': _metadataFor(
                revision: 1,
                snapshot: _localSnapshot,
              ),
            });
          case 'PUT /api/v1/account/personal-snapshot':
            uploads += 1;
            return _jsonResponse({});
          default:
            fail('Unexpected request: ${request.method} ${request.url}');
        }
      });
      final harness = await _createHarness(client: client);
      await _waitFor(
        () => harness.cloud.state == PersonalCloudSyncState.upToDate,
      );

      serverInstanceId = 'server-2';
      await harness.server.checkServer();
      harness.cloud.updateDependencies(
        harness.server,
        harness.sessions,
        harness.logs,
        harness.collaboration,
      );
      await _waitFor(
        () =>
            harness.cloud.state == PersonalCloudSyncState.decisionRequired &&
            harness.cloud.decisionReason ==
                PersonalCloudDecisionReason.differentAccountData,
      );

      expect(metadataReads, 2);
      expect(uploads, 0);
    },
  );

  test(
    'interrupted replacement stays fail closed until explicit local upload',
    () async {
      final localChecksum = _snapshotChecksum(_localSnapshot);
      SharedPreferences.setMockInitialValues({
        'server_url': _serverUrl,
        'personal_cloud_v1_local_owner_scope': _scopeIdentity('user-1'),
        ..._baselinePreferences(
          accountId: 'user-1',
          revision: 1,
          localChecksum: localChecksum,
          databaseRevision: 0,
        ),
        'local_database_replacement_revision': 0,
        'local_database_replacement_pending': true,
      });
      var uploads = 0;
      final client = MockClient((request) async {
        if (_isServerInfoRequest(request)) {
          return _jsonResponse(_serverInfoJson());
        }
        switch ('${request.method} ${request.url.path}') {
          case 'GET /api/v1/account/personal-snapshot':
            return _jsonResponse({
              'personalSnapshot': _metadataFor(
                revision: 1,
                snapshot: _localSnapshot,
              ),
            });
          case 'PUT /api/v1/account/personal-snapshot':
            uploads += 1;
            expect(request.headers['if-match'], '"1"');
            return _jsonResponse({
              // The server deduplicates identical content, but the explicit
              // acknowledgement must still clear the crash sentinel.
              'replaced': false,
              'personalSnapshot': _metadataFor(
                revision: 1,
                snapshot: _localSnapshot,
              ),
            });
          default:
            fail('Unexpected request: ${request.method} ${request.url}');
        }
      });
      final harness = await _createHarness(client: client);
      await _waitFor(
        () => harness.cloud.state == PersonalCloudSyncState.decisionRequired,
      );

      expect(
        harness.cloud.decisionReason,
        PersonalCloudDecisionReason.databaseReplaced,
      );
      expect(uploads, 0);
      expect(harness.sessions.databaseReplacementPending, isTrue);

      await harness.cloud.replaceCloudWithLocal(
        expectedCloudRevision: harness.cloud.cloudMeta!.revision,
        expectedLocalSnapshotToken: harness.cloud.localSnapshotToken!,
      );

      expect(uploads, 1);
      expect(harness.cloud.state, PersonalCloudSyncState.upToDate);
      expect(harness.cloud.cloudMeta?.revision, 1);
      expect(harness.sessions.databaseReplacementPending, isFalse);
      expect(
        (await SharedPreferences.getInstance())
            .containsKey('local_database_replacement_pending'),
        isFalse,
      );
    },
  );

  test('identical cloud checksum safely advances a lost-response baseline',
      () async {
    SharedPreferences.setMockInitialValues({
      'server_url': _serverUrl,
      'personal_cloud_v1_local_owner_scope': _scopeIdentity('user-1'),
      ..._baselinePreferences(
        accountId: 'user-1',
        revision: 1,
        localChecksum: _snapshotChecksum(_canonicalSessionOnlySnapshot),
        databaseRevision: 0,
      ),
      'local_database_replacement_revision': 0,
    });
    var uploads = 0;
    var downloads = 0;
    final client = MockClient((request) async {
      if (_isServerInfoRequest(request)) {
        return _jsonResponse(_serverInfoJson());
      }
      switch ('${request.method} ${request.url.path}') {
        case 'GET /api/v1/account/personal-snapshot':
          return _jsonResponse({
            'personalSnapshot': _metadataFor(
              revision: 2,
              snapshot: _canonicalNonEmptySnapshot,
            ),
          });
        case 'PUT /api/v1/account/personal-snapshot':
          uploads += 1;
          return _jsonResponse({});
        case 'GET /api/v1/account/personal-snapshot/download':
          downloads += 1;
          return _downloadResponse(
            revision: 2,
            snapshot: _canonicalNonEmptySnapshot,
          );
        default:
          fail('Unexpected request: ${request.method} ${request.url}');
      }
    });
    final harness = await _createHarness(
      client: client,
      exporter: () async => jsonEncode(_canonicalNonEmptySnapshot),
    );

    await _waitFor(
      () => harness.cloud.state == PersonalCloudSyncState.upToDate,
    );

    expect(uploads, 0);
    expect(downloads, 0);
    expect(harness.cloud.cloudMeta?.revision, 2);
    final prefs = await SharedPreferences.getInstance();
    final prefix = _preferencePrefix('user-1');
    expect(prefs.getInt('${prefix}revision'), 2);
    expect(
      prefs.getString('${prefix}local_checksum'),
      _snapshotChecksum(_canonicalNonEmptySnapshot),
    );
  });

  test('database revision change blocks automatic cloud replacement', () async {
    final localChecksum = _snapshotChecksum(_localSnapshot);
    SharedPreferences.setMockInitialValues({
      'server_url': _serverUrl,
      'personal_cloud_v1_local_owner_scope': _scopeIdentity('user-1'),
      ..._baselinePreferences(
        accountId: 'user-1',
        revision: 1,
        localChecksum: localChecksum,
        databaseRevision: 0,
      ),
      'local_database_replacement_revision': 0,
    });
    var cloudRevision = 1;
    var downloads = 0;
    var replacerCalls = 0;
    final client = MockClient((request) async {
      if (_isServerInfoRequest(request)) {
        return _jsonResponse(_serverInfoJson());
      }
      switch ('${request.method} ${request.url.path}') {
        case 'GET /api/v1/account/personal-snapshot':
          return _jsonResponse({
            'personalSnapshot': _metadataFor(
              revision: cloudRevision,
              // Even identical content must not bypass a whole-database
              // generation mismatch.
              snapshot: _localSnapshot,
            ),
          });
        case 'GET /api/v1/account/personal-snapshot/download':
          downloads += 1;
          return _downloadResponse(
            revision: cloudRevision,
            snapshot: _remoteSnapshot,
          );
        default:
          fail('Unexpected request: ${request.method} ${request.url}');
      }
    });
    final harness = await _createHarness(
      client: client,
      replacer: (jsonData, expectedLocalJsonData) async {
        replacerCalls += 1;
        return '{}';
      },
    );
    await _waitFor(
      () => harness.cloud.state == PersonalCloudSyncState.upToDate,
    );

    await harness.sessions.reloadAfterDatabaseReplacement();
    expect(harness.sessions.databaseRevision, 1);
    cloudRevision = 2;
    harness.cloud.updateDependencies(
      harness.server,
      harness.sessions,
      harness.logs,
      harness.collaboration,
    );
    await harness.cloud.syncNow();

    expect(
      harness.cloud.state,
      PersonalCloudSyncState.decisionRequired,
    );
    expect(
      harness.cloud.decisionReason,
      PersonalCloudDecisionReason.databaseReplaced,
    );
    expect(downloads, 0, reason: 'a replaced database must not be overwritten');
    expect(replacerCalls, 0);
  });

  test(
    'automatic download compare-replaces and local race requires a decision',
    () async {
      final localChecksum = _snapshotChecksum(_localSnapshot);
      SharedPreferences.setMockInitialValues({
        'server_url': _serverUrl,
        'personal_cloud_v1_local_owner_scope': _scopeIdentity('user-1'),
        ..._baselinePreferences(
          accountId: 'user-1',
          revision: 1,
          localChecksum: localChecksum,
          databaseRevision: 0,
        ),
        'local_database_replacement_revision': 0,
      });
      var downloads = 0;
      var replacerCalls = 0;
      String? downloadedJson;
      String? comparedLocalJson;
      final client = MockClient((request) async {
        if (_isServerInfoRequest(request)) {
          return _jsonResponse(_serverInfoJson());
        }
        switch ('${request.method} ${request.url.path}') {
          case 'GET /api/v1/account/personal-snapshot':
            return _jsonResponse({
              'personalSnapshot': _metadataFor(
                revision: 2,
                snapshot: _remoteSnapshot,
              ),
            });
          case 'GET /api/v1/account/personal-snapshot/download':
            downloads += 1;
            return _downloadResponse(
              revision: 2,
              snapshot: _remoteSnapshot,
            );
          default:
            fail('Unexpected request: ${request.method} ${request.url}');
        }
      });
      final harness = await _createHarness(
        client: client,
        replacer: (jsonData, expectedLocalJsonData) async {
          replacerCalls += 1;
          downloadedJson = jsonData;
          comparedLocalJson = expectedLocalJsonData;
          throw StateError('PERSONAL_RECORDS_LOCAL_CHANGED');
        },
      );

      await _waitFor(
        () => harness.cloud.state == PersonalCloudSyncState.decisionRequired,
      );

      expect(
        harness.cloud.decisionReason,
        PersonalCloudDecisionReason.concurrentChanges,
      );
      expect(downloads, 1);
      expect(harness.collaboration.maintenanceCalls, 1);
      expect(replacerCalls, 1);
      expect(jsonDecode(downloadedJson!), _remoteSnapshot);
      expect(jsonDecode(comparedLocalJson!), _localSnapshot);
    },
  );

  test('collaboration-only notifications do not schedule personal API reads',
      () async {
    final localChecksum = _snapshotChecksum(_localSnapshot);
    SharedPreferences.setMockInitialValues({
      'server_url': _serverUrl,
      'personal_cloud_v1_local_owner_scope': _scopeIdentity('user-1'),
      ..._baselinePreferences(
        accountId: 'user-1',
        revision: 1,
        localChecksum: localChecksum,
        databaseRevision: 0,
      ),
      'local_database_replacement_revision': 0,
    });
    var metadataReads = 0;
    final client = MockClient((request) async {
      if (_isServerInfoRequest(request)) {
        return _jsonResponse(_serverInfoJson());
      }
      if ('${request.method} ${request.url.path}' ==
          'GET /api/v1/account/personal-snapshot') {
        metadataReads += 1;
        return _jsonResponse({
          'personalSnapshot': _metadataFor(
            revision: 1,
            snapshot: _localSnapshot,
          ),
        });
      }
      fail('Unexpected request: ${request.method} ${request.url}');
    });
    final harness = await _createHarness(
      client: client,
      automaticChangeDebounce: const Duration(milliseconds: 20),
    );
    await _waitFor(
      () => harness.cloud.state == PersonalCloudSyncState.upToDate,
    );

    // ChangeNotifierProxyProvider calls updateDependencies when a draft/lock
    // notification fires. No personal-data revision changed here.
    harness.collaboration.notifyListeners();
    harness.cloud.updateDependencies(
      harness.server,
      harness.sessions,
      harness.logs,
      harness.collaboration,
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(metadataReads, 1);
  });

  test('ordinary durable log save revision schedules one debounced upload',
      () async {
    var exportedSnapshot = _canonicalSessionOnlySnapshot;
    SharedPreferences.setMockInitialValues({
      'server_url': _serverUrl,
      'current_session_id': 'local-session-2026-07-18',
      'personal_cloud_v1_local_owner_scope': _scopeIdentity('user-1'),
      ..._baselinePreferences(
        accountId: 'user-1',
        revision: 6,
        localChecksum: _snapshotChecksum(_canonicalSessionOnlySnapshot),
        databaseRevision: 0,
      ),
      'local_database_replacement_revision': 0,
    });
    var metadataReads = 0;
    var uploads = 0;
    final client = MockClient((request) async {
      if (_isServerInfoRequest(request)) {
        return _jsonResponse(_serverInfoJson());
      }
      switch ('${request.method} ${request.url.path}') {
        case 'GET /api/v1/account/personal-snapshot':
          metadataReads += 1;
          return _jsonResponse({
            'personalSnapshot': _metadataFor(
              revision: 6,
              snapshot: _canonicalSessionOnlySnapshot,
            ),
          });
        case 'PUT /api/v1/account/personal-snapshot':
          uploads += 1;
          expect(request.headers['if-match'], '"6"');
          final body =
              Map<String, Object?>.from(jsonDecode(request.body) as Map);
          expect(body['snapshot'], _canonicalNonEmptySnapshot);
          return _jsonResponse({
            'replaced': true,
            'personalSnapshot': _metadataFor(
              revision: 7,
              snapshot: _canonicalNonEmptySnapshot,
            ),
          });
        default:
          fail('Unexpected request: ${request.method} ${request.url}');
      }
    });
    const activeSession = Session(
      sessionId: 'local-session-2026-07-18',
      title: '晚间点名',
      status: 'active',
      createdAt: '2026-07-18T19:30:00.000+08:00',
      updatedAt: '2026-07-18T20:45:00.123+08:00',
    );
    final harness = await _createHarness(
      client: client,
      exporter: () async => jsonEncode(exportedSnapshot),
      automaticChangeDebounce: const Duration(milliseconds: 20),
      sessionRows: const [activeSession],
      logCreator: (_, __) async {
        exportedSnapshot = _canonicalNonEmptySnapshot;
        return const bridge.LogEntry(
          syncId: 'local-log-1',
          sessionId: 'local-session-2026-07-18',
          time: '2026-07-18T19:31:59.987+08:00',
          controller: 'BG5AAA',
          callsign: 'BG5CRL',
          rstSent: '59',
          rstRcvd: '58',
          qth: '杭州',
          device: 'IC-9700',
          power: '25W',
          antenna: 'X520',
          height: '100m',
          remarks: '完整时间保留',
          createdAt: '2026-07-18T19:32:00.001+08:00',
          updatedAt: '2026-07-18T19:32:00.002+08:00',
          sourceDeviceId: 'windows-shack-pc',
        );
      },
    );
    await _waitFor(
      () => harness.cloud.state == PersonalCloudSyncState.upToDate,
    );
    await harness.logs.reloadForSession(activeSession.sessionId);

    await harness.logs.addLog(
      model.LogEntry(
        id: 'local-log-1',
        sessionId: activeSession.sessionId,
        time: '2026-07-18T19:31:59.987+08:00',
        controller: 'BG5AAA',
        callsign: 'BG5CRL',
        report: '59',
        rstRcvd: '58',
        qth: '杭州',
        device: 'IC-9700',
        power: '25W',
        antenna: 'X520',
        height: '100m',
      ),
    );
    harness.cloud.updateDependencies(
      harness.server,
      harness.sessions,
      harness.logs,
      harness.collaboration,
    );
    await _waitFor(() => uploads == 1);

    expect(harness.logs.dataRevision, 1);
    expect(metadataReads, 2);
    expect(harness.cloud.cloudMeta?.revision, 7);
  });

  test('missing capability never requests personal cloud API', () async {
    SharedPreferences.setMockInitialValues({
      'server_url': _serverUrl,
    });
    var personalApiRequests = 0;
    var exporterCalls = 0;
    final client = MockClient((request) async {
      if (_isServerInfoRequest(request)) {
        return _jsonResponse(_serverInfoJson(features: const []));
      }
      if (request.url.path.contains('/account/personal-snapshot')) {
        personalApiRequests += 1;
      }
      fail('Unexpected request: ${request.method} ${request.url}');
    });
    final harness = await _createHarness(
      client: client,
      exporter: () async {
        exporterCalls += 1;
        return jsonEncode(_localSnapshot);
      },
    );

    expect(harness.cloud.state, PersonalCloudSyncState.unsupported);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(personalApiRequests, 0);
    expect(exporterCalls, 0);
  });
}

Future<_Harness> _createHarness({
  required MockClient client,
  String accountId = 'user-1',
  PersonalRecordsExporter? exporter,
  PersonalRecordsCompareReplacer? replacer,
  Duration automaticChangeDebounce = const Duration(seconds: 10),
  List<Session> sessionRows = const [],
  LogCreator? logCreator,
}) async {
  final session = _authSession(accountId: accountId);
  final server = ServerProvider(
    autoLoadSettings: false,
    tokenStoreFactory: (_) => MemoryTokenStore(session),
    apiFactory: ({
      required baseUri,
      required tokenStore,
      required deviceId,
      required onAuthInvalidated,
    }) =>
        ServerApi(
      baseUri: baseUri,
      tokenStore: tokenStore,
      httpClient: client,
      deviceId: deviceId,
      onAuthInvalidated: onAuthInvalidated,
    ),
  );
  final sessions = SessionProvider(sessionListLoader: () async => sessionRows);
  final logs = LogProvider(
    sessionListLoader: () async => sessionRows,
    sessionLogPageLoader: (_, __, ___) async => [],
    logCreator: logCreator,
  );
  final collaboration = _TestCollaborationProvider(sessions, logs);
  final cloud = PersonalCloudProvider(
    exporter: exporter ?? () async => jsonEncode(_localSnapshot),
    replacer: replacer,
    automaticChangeDebounce: automaticChangeDebounce,
  );
  addTearDown(cloud.dispose);
  addTearDown(collaboration.dispose);
  addTearDown(logs.dispose);
  addTearDown(sessions.dispose);
  addTearDown(server.dispose);

  await server.loadSettings();
  await sessions.ready;
  await server.checkServer();
  expect(server.isLoggedIn, isTrue);
  cloud.updateDependencies(server, sessions, logs, collaboration);
  return _Harness(
    server: server,
    sessions: sessions,
    logs: logs,
    collaboration: collaboration,
    cloud: cloud,
  );
}

Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for personal cloud state');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

bool _isServerInfoRequest(http.Request request) =>
    '${request.method} ${request.url.path}' == 'GET /api/v1/server-info';

Map<String, Object> _baselinePreferences({
  required String accountId,
  required int revision,
  required String localChecksum,
  required int databaseRevision,
  String serverInstanceId = 'server-1',
}) {
  final prefix = _preferencePrefix(
    accountId,
    serverInstanceId: serverInstanceId,
  );
  return {
    '${prefix}revision': revision,
    '${prefix}local_checksum': localChecksum,
    '${prefix}database_revision': databaseRevision,
  };
}

String _preferencePrefix(
  String accountId, {
  String serverInstanceId = 'server-1',
}) =>
    'personal_cloud_v1_${sha256.convert(utf8.encode(_scope(accountId, serverInstanceId: serverInstanceId)))}_';

String _scopeIdentity(
  String accountId, {
  String serverInstanceId = 'server-1',
}) =>
    sha256
        .convert(
          utf8.encode(
            _scope(accountId, serverInstanceId: serverInstanceId),
          ),
        )
        .toString();

String _scope(
  String accountId, {
  String serverInstanceId = 'server-1',
}) =>
    '$_serverUrl\n$serverInstanceId\n$accountId';

String _snapshotChecksum(Map<String, Object?> snapshot) {
  return personalSnapshotContentChecksum(snapshot);
}

Map<String, Object?> _metadataFor({
  required int revision,
  required Map<String, Object?> snapshot,
}) =>
    {
      'exists': true,
      'revision': revision,
      'formatVersion': 1,
      'sessionCount': (snapshot['sessions']! as List).length,
      'logCount': (snapshot['logs']! as List).length,
      'byteSize': utf8.encode(jsonEncode(snapshot)).length,
      'checksum': _snapshotChecksum(snapshot),
      'createdAt': '2026-07-18T11:00:00.000Z',
      'updatedAt': '2026-07-18T12:00:00.000Z',
    };

http.Response _downloadResponse({
  required int revision,
  required Map<String, Object?> snapshot,
}) =>
    _jsonResponse({
      'personalSnapshot': {
        ..._metadataFor(revision: revision, snapshot: snapshot),
        'snapshot': snapshot,
      },
    });

const String _serverUrl = 'https://example.test';

const Map<String, Object?> _localSnapshot = {
  'version': 1,
  'exportedAt': '2026-07-18T12:00:00.000Z',
  'sessions': [
    {
      'session_id': 'local-session-1',
      'title': 'BR5AI',
    },
  ],
  'logs': <Object?>[],
};

const Map<String, Object?> _remoteSnapshot = {
  'version': 1,
  'exportedAt': '2026-07-18T12:05:00.000Z',
  'sessions': [
    {
      'session_id': 'remote-session-1',
      'title': 'Remote',
    },
  ],
  'logs': <Object?>[],
};

const Map<String, Object?> _canonicalSessionOnlySnapshot = {
  'version': 1,
  'exportedAt': '2026-07-18T12:01:02.345+08:00',
  'sessions': [
    {
      'session_id': 'local-session-2026-07-18',
      'title': '晚间点名',
      'status': 'closed',
      'created_at': '2026-07-18T19:30:00.000+08:00',
      'updated_at': '2026-07-18T20:45:00.123+08:00',
      'closed_at': '2026-07-18T20:45:00.123+08:00',
      'deleted_at': null,
    },
  ],
  'logs': <Object?>[],
};

const Map<String, Object?> _canonicalNonEmptySnapshot = {
  'version': 1,
  'exportedAt': '2026-07-18T12:01:02.345+08:00',
  'sessions': [
    {
      'session_id': 'local-session-2026-07-18',
      'title': '晚间点名',
      'status': 'closed',
      'created_at': '2026-07-18T19:30:00.000+08:00',
      'updated_at': '2026-07-18T20:45:00.123+08:00',
      'closed_at': '2026-07-18T20:45:00.123+08:00',
      'deleted_at': null,
    },
  ],
  'logs': [
    {
      'sync_id': 'local-log-1',
      'session_id': 'local-session-2026-07-18',
      'time': '2026-07-18T19:31:59.987+08:00',
      'controller': 'BG5AAA',
      'callsign': 'BG5CRL',
      'rst_sent': '59',
      'rst_rcvd': '58',
      'qth': '杭州',
      'device': 'IC-9700',
      'power': '25W',
      'antenna': 'X520',
      'height': '100m',
      'remarks': '完整时间保留',
      'created_at': '2026-07-18T19:32:00.001+08:00',
      'updated_at': '2026-07-18T19:32:00.002+08:00',
      'deleted_at': null,
      'source_device_id': 'windows-shack-pc',
    },
  ],
};

const Map<String, Object?> _emptyMetadata = {
  'exists': false,
  'revision': 0,
  'formatVersion': 1,
  'sessionCount': 0,
  'logCount': 0,
  'byteSize': 0,
  'checksum': null,
  'createdAt': null,
  'updatedAt': null,
};

Map<String, Object?> _serverInfoJson({
  List<String> features = const ['personalCloudSnapshots'],
  String serverInstanceId = 'server-1',
}) =>
    {
      'serverInstanceId': serverInstanceId,
      'protocolMin': 1,
      'protocolMax': 1,
      'features': features,
      'serverTime': '2026-07-18T12:00:00.000Z',
      'environment': 'test',
    };

AuthSessionDto _authSession({required String accountId}) =>
    AuthSessionDto.fromJson({
      'accessToken': 'access-token',
      'accessTokenExpiresIn': 900,
      'refreshToken': 'refresh-token',
      'refreshTokenExpiresAt': '2099-07-18T13:00:00.000Z',
      'user': {
        'id': accountId,
        'username': accountId,
        'role': 'user',
      },
    });

http.Response _jsonResponse(Object? body, [int statusCode = 200]) =>
    http.Response(
      jsonEncode(body),
      statusCode,
      headers: {'content-type': 'application/json'},
    );

final class _Harness {
  const _Harness({
    required this.server,
    required this.sessions,
    required this.logs,
    required this.collaboration,
    required this.cloud,
  });

  final ServerProvider server;
  final SessionProvider sessions;
  final LogProvider logs;
  final _TestCollaborationProvider collaboration;
  final PersonalCloudProvider cloud;
}

final class _TestCollaborationProvider extends CollaborationProvider {
  _TestCollaborationProvider(this.sessions, this.logs);

  final SessionProvider sessions;
  final LogProvider logs;
  int maintenanceCalls = 0;

  @override
  Future<T> runLocalDatabaseMaintenance<T>(
    Future<T> Function() operation,
  ) async {
    maintenanceCalls += 1;
    final preparedByThisRun = await sessions.prepareForDatabaseReplacement();
    var committed = false;
    try {
      final result = await operation();
      committed = true;
      await sessions.reloadAfterDatabaseReplacement();
      await logs.reloadAfterDatabaseReplacement(sessions.currentSessionId);
      await sessions.acknowledgeDatabaseReplacement();
      return result;
    } catch (_) {
      if (!committed && preparedByThisRun) {
        await sessions.rollbackFailedDatabaseReplacement();
      }
      rethrow;
    }
  }
}
