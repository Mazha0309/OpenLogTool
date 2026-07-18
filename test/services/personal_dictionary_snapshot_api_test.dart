import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openlogtool/models/collaboration_dto.dart';
import 'package:openlogtool/models/personal_dictionary_snapshot_dto.dart';
import 'package:openlogtool/services/server_api.dart';

void main() {
  group('personal dictionary snapshot DTOs', () {
    test('parse metadata, download, and replace envelopes', () {
      final metadata = PersonalDictionarySnapshotMeta.fromJson(_metadataJson);
      expect(metadata.exists, isTrue);
      expect(metadata.revision, 7);
      expect(metadata.formatVersion, 1);
      expect(metadata.itemCount, 3);
      expect(metadata.activeCount, 2);
      expect(metadata.deletedCount, 1);
      expect(metadata.byteSize, 1234);
      expect(metadata.checksum, 'abc123');
      expect(metadata.createdAt, DateTime.parse(_createdAt));
      expect(metadata.updatedAt, DateTime.parse(_updatedAt));

      final download = PersonalDictionarySnapshotDownload.fromJson({
        'personalDictionarySnapshot': {
          ..._metadataJson,
          'snapshot': _snapshot,
        },
      });
      expect(download.meta.revision, 7);
      expect(download.snapshot, _snapshot);

      final replacement = PersonalDictionarySnapshotReplaceResult.fromJson({
        'replaced': true,
        'personalDictionarySnapshot': _metadataJson,
      });
      expect(replacement.replaced, isTrue);
      expect(replacement.meta.itemCount, 3);
    });

    test('rejects malformed metadata fields', () {
      expect(
        () => PersonalDictionarySnapshotMeta.fromJson({
          ..._metadataJson,
          'updatedAt': '2026-07-19T21:00:00+08:00',
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => PersonalDictionarySnapshotMeta.fromJson({
          ..._metadataJson,
          'deletedCount': -1,
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('ServerApi personal dictionary snapshot routes', () {
    test('GET metadata/download and conditional PUT match protocol', () async {
      final seen = <String>[];
      final client = MockClient((request) async {
        seen.add('${request.method} ${request.url.path}');
        expect(request.headers['authorization'], 'Bearer access-token');
        switch ('${request.method} ${request.url.path}') {
          case 'GET /api/v1/account/personal-dictionary-snapshot':
            return _jsonResponse({
              'personalDictionarySnapshot': _metadataJson,
            });
          case 'GET /api/v1/account/personal-dictionary-snapshot/download':
            return _jsonResponse({
              'personalDictionarySnapshot': {
                ..._metadataJson,
                'snapshot': _snapshot,
              },
            });
          case 'PUT /api/v1/account/personal-dictionary-snapshot':
            expect(request.headers['if-match'], '"7"');
            expect(jsonDecode(request.body), {
              'expectedRevision': 7,
              'confirmation': 'REPLACE_PERSONAL_DICTIONARY_SNAPSHOT',
              'snapshot': _snapshot,
            });
            return _jsonResponse({
              'replaced': true,
              'personalDictionarySnapshot': {
                ..._metadataJson,
                'revision': 8,
              },
            });
          default:
            fail('Unexpected request: ${request.method} ${request.url}');
        }
      });
      final api = _api(client);
      addTearDown(api.close);

      final metadata = await api.getPersonalDictionarySnapshotMeta();
      final download = await api.downloadPersonalDictionarySnapshot();
      final replacement = await api.replacePersonalDictionarySnapshot(
        expectedRevision: 7,
        snapshot: _snapshot,
      );

      expect(metadata.revision, 7);
      expect(download.snapshot, _snapshot);
      expect(replacement.replaced, isTrue);
      expect(replacement.meta.revision, 8);
      expect(seen, [
        'GET /api/v1/account/personal-dictionary-snapshot',
        'GET /api/v1/account/personal-dictionary-snapshot/download',
        'PUT /api/v1/account/personal-dictionary-snapshot',
      ]);
    });

    test('maps a stale conditional PUT to the server conflict', () async {
      final api = _api(
        MockClient((request) async {
          expect(request.method, 'PUT');
          return _jsonResponse({
            'error': {
              'code': 'PERSONAL_DICTIONARY_SNAPSHOT_REVISION_CONFLICT',
              'message':
                  'The personal dictionary snapshot changed concurrently',
              'requestId': 'request-1',
              'details': {
                'expectedRevision': 7,
                'currentRevision': 8,
                'currentChecksum': 'new-checksum',
                'updatedAt': _updatedAt,
              },
            },
          }, 409);
        }),
      );
      addTearDown(api.close);

      await expectLater(
        api.replacePersonalDictionarySnapshot(
          expectedRevision: 7,
          snapshot: _snapshot,
        ),
        throwsA(
          isA<ServerApiException>()
              .having(
                (error) => error.code,
                'code',
                'PERSONAL_DICTIONARY_SNAPSHOT_REVISION_CONFLICT',
              )
              .having((error) => error.statusCode, 'statusCode', 409)
              .having((error) => error.retryable, 'retryable', isFalse)
              .having(
                (error) =>
                    (error.details as Map<String, Object?>)['currentRevision'],
                'current revision',
                8,
              ),
        ),
      );
    });

    test('rejects a negative expected revision without a request', () async {
      var requests = 0;
      final api = _api(
        MockClient((_) async {
          requests += 1;
          return _jsonResponse({});
        }),
      );
      addTearDown(api.close);

      await expectLater(
        api.replacePersonalDictionarySnapshot(
          expectedRevision: -1,
          snapshot: _snapshot,
        ),
        throwsArgumentError,
      );
      expect(requests, 0);
    });
  });
}

const _createdAt = '2026-07-19T12:00:00.000Z';
const _updatedAt = '2026-07-19T13:00:00.000Z';

const PersonalDictionarySnapshotJson _metadataJson = {
  'exists': true,
  'revision': 7,
  'formatVersion': 1,
  'itemCount': 3,
  'activeCount': 2,
  'deletedCount': 1,
  'byteSize': 1234,
  'checksum': 'abc123',
  'createdAt': _createdAt,
  'updatedAt': _updatedAt,
};

const PersonalDictionarySnapshotJson _snapshot = {
  'version': 1,
  'exportedAt': _updatedAt,
  'items': <Object?>[
    {
      'dictType': 'callsign',
      'raw': 'BG5AAA',
      'origin': 'user',
      'state': 'active',
      'pinyin': null,
      'abbreviation': null,
    },
    {
      'dictType': 'qth',
      'raw': 'Hangzhou',
      'origin': 'user',
      'state': 'active',
      'pinyin': 'hang zhou',
      'abbreviation': 'hz',
    },
    {
      'dictType': 'antenna',
      'raw': 'Yagi',
      'origin': 'builtin',
      'state': 'deleted',
      'pinyin': null,
      'abbreviation': null,
    },
  ],
};

ServerApi _api(http.Client client) => ServerApi(
      baseUri: Uri.parse('https://example.test'),
      tokenStore: MemoryTokenStore(_authSession()),
      httpClient: client,
      deviceId: 'device-1',
    );

AuthSessionDto _authSession() => AuthSessionDto.fromJson({
      'accessToken': 'access-token',
      'accessTokenExpiresIn': 900,
      'refreshToken': 'refresh-token',
      'refreshTokenExpiresAt': '2099-07-19T13:00:00.000Z',
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
