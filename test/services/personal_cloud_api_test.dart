import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openlogtool/models/collaboration_dto.dart';
import 'package:openlogtool/models/personal_cloud_dto.dart';
import 'package:openlogtool/providers/personal_cloud_provider.dart';
import 'package:openlogtool/services/server_api.dart';

void main() {
  group('personal cloud DTOs', () {
    test('uses the shared canonical checksum vector', () {
      expect(
        personalSnapshotContentChecksum(const {
          'version': 1,
          'exportedAt': _updatedAt,
          'sessions': <Object?>[],
          'logs': <Object?>[],
        }),
        'ad968e72c01b6c7dbe0b5de438b5d752ed6372b7f9090d3ff3c3694b5c1e431a',
      );
    });

    test('parse metadata, download, and replace envelopes', () {
      final metadata = PersonalCloudSnapshotMeta.fromJson(_metadataJson);
      expect(metadata.exists, isTrue);
      expect(metadata.revision, 7);
      expect(metadata.formatVersion, 1);
      expect(metadata.sessionCount, 2);
      expect(metadata.logCount, 9);
      expect(metadata.byteSize, 1234);
      expect(metadata.checksum, 'abc123');
      expect(metadata.createdAt, DateTime.parse(_createdAt));
      expect(metadata.updatedAt, DateTime.parse(_updatedAt));

      final download = PersonalCloudSnapshotDownload.fromJson({
        'personalSnapshot': {
          ..._metadataJson,
          'snapshot': _snapshot,
        },
      });
      expect(download.meta.revision, 7);
      expect(download.snapshot, _snapshot);

      final replacement = PersonalCloudSnapshotReplaceResult.fromJson({
        'replaced': true,
        'personalSnapshot': _metadataJson,
      });
      expect(replacement.replaced, isTrue);
      expect(replacement.meta.sessionCount, 2);
    });

    test('rejects non-UTC metadata timestamps', () {
      expect(
        () => PersonalCloudSnapshotMeta.fromJson({
          ..._metadataJson,
          'updatedAt': '2026-07-18T21:00:00+08:00',
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('ServerApi personal cloud routes', () {
    test('GET metadata/download and PUT preserve protocol envelopes', () async {
      final seen = <String>[];
      final client = MockClient((request) async {
        seen.add('${request.method} ${request.url.path}');
        expect(request.headers['authorization'], 'Bearer access-token');
        switch ('${request.method} ${request.url.path}') {
          case 'GET /api/v1/account/personal-snapshot':
            return _jsonResponse({'personalSnapshot': _metadataJson});
          case 'GET /api/v1/account/personal-snapshot/download':
            return _jsonResponse({
              'personalSnapshot': {
                ..._metadataJson,
                'snapshot': _snapshot,
              },
            });
          case 'PUT /api/v1/account/personal-snapshot':
            expect(request.headers['if-match'], '"7"');
            expect(jsonDecode(request.body), {
              'expectedRevision': 7,
              'confirmation': 'REPLACE_PERSONAL_CLOUD_SNAPSHOT',
              'snapshot': _snapshot,
            });
            return _jsonResponse({
              'replaced': true,
              'personalSnapshot': {
                ..._metadataJson,
                'revision': 8,
              },
            });
          default:
            fail('Unexpected request: ${request.method} ${request.url}');
        }
      });
      final api = ServerApi(
        baseUri: Uri.parse('https://example.test'),
        tokenStore: MemoryTokenStore(_authSession()),
        httpClient: client,
        deviceId: 'device-1',
      );
      addTearDown(api.close);

      final metadata = await api.getPersonalCloudSnapshotMeta();
      final download = await api.downloadPersonalCloudSnapshot();
      final replacement = await api.replacePersonalCloudSnapshot(
        expectedRevision: 7,
        snapshot: _snapshot,
      );

      expect(metadata.revision, 7);
      expect(download.snapshot, _snapshot);
      expect(replacement.replaced, isTrue);
      expect(replacement.meta.revision, 8);
      expect(seen, [
        'GET /api/v1/account/personal-snapshot',
        'GET /api/v1/account/personal-snapshot/download',
        'PUT /api/v1/account/personal-snapshot',
      ]);
    });

    test('rejects a negative expected revision before sending a request',
        () async {
      var requests = 0;
      final api = ServerApi(
        baseUri: Uri.parse('https://example.test'),
        tokenStore: MemoryTokenStore(_authSession()),
        httpClient: MockClient((_) async {
          requests += 1;
          return _jsonResponse({});
        }),
      );
      addTearDown(api.close);

      await expectLater(
        api.replacePersonalCloudSnapshot(
          expectedRevision: -1,
          snapshot: _snapshot,
        ),
        throwsArgumentError,
      );
      expect(requests, 0);
    });
  });
}

const _createdAt = '2026-07-18T12:00:00.000Z';
const _updatedAt = '2026-07-18T13:00:00.000Z';

const Map<String, Object?> _metadataJson = {
  'exists': true,
  'revision': 7,
  'formatVersion': 1,
  'sessionCount': 2,
  'logCount': 9,
  'byteSize': 1234,
  'checksum': 'abc123',
  'createdAt': _createdAt,
  'updatedAt': _updatedAt,
};

const PersonalCloudJsonObject _snapshot = {
  'version': 1,
  'exportedAt': _updatedAt,
  'sessions': <Object?>[],
  'logs': <Object?>[],
};

AuthSessionDto _authSession() => AuthSessionDto.fromJson({
      'accessToken': 'access-token',
      'accessTokenExpiresIn': 900,
      'refreshToken': 'refresh-token',
      'refreshTokenExpiresAt': '2099-07-18T13:00:00.000Z',
      'user': const {
        'id': 'user-1',
        'username': 'alice',
        'role': 'user',
      },
    });

http.Response _jsonResponse(Object? body, [int statusCode = 200]) =>
    http.Response(
      jsonEncode(body),
      statusCode,
      headers: {'content-type': 'application/json'},
    );
