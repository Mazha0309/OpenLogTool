import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/models/collaboration_dto.dart';
import 'package:openlogtool/services/secure_token_store.dart';

void main() {
  test('persists a session across token-store instances for the same server',
      () async {
    final values = _MemorySecureValues();
    final session = _session();
    final first = SecureTokenStore(
      serverUrl: '  HTTPS://EXAMPLE.TEST:443/api/v1/  ',
      secureValues: values,
    );

    await first.write(session);
    final restarted = SecureTokenStore(
      serverUrl: 'https://example.test',
      secureValues: values,
    );
    final restored = await restarted.read();

    expect(restored?.accessToken, session.accessToken);
    expect(restored?.refreshToken, session.refreshToken);
    expect(restored?.user.id, session.user.id);
  });

  test('migrates a credential stored under the legacy raw URL key', () async {
    const legacyUrl = 'HTTPS://EXAMPLE.TEST:443/api/v1/';
    final values = _MemorySecureValues();
    final session = _session();
    final legacyNormalized = legacyUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final legacyDigest =
        sha256.convert(utf8.encode(legacyNormalized)).toString();
    final legacyKey = 'openlogtool.auth.v1.$legacyDigest';
    values.values[legacyKey] = jsonEncode(session.toJson());
    final store = SecureTokenStore(
      serverUrl: legacyUrl,
      secureValues: values,
    );

    final restored = await store.read();

    expect(restored?.refreshToken, session.refreshToken);
    expect(values.values.containsKey(legacyKey), isFalse);
    expect(values.values, hasLength(1));
  });

  test('returns a legacy credential when key migration cannot be written',
      () async {
    const legacyUrl = 'HTTPS://EXAMPLE.TEST:443/api/v1/';
    final values = _ControllableSecureValues();
    final session = _session();
    final legacyNormalized = legacyUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final legacyDigest =
        sha256.convert(utf8.encode(legacyNormalized)).toString();
    final legacyKey = 'openlogtool.auth.v1.$legacyDigest';
    values.values[legacyKey] = jsonEncode(session.toJson());
    values.failWrite = true;
    final store = SecureTokenStore(
      serverUrl: legacyUrl,
      secureValues: values,
    );

    final restored = await store.read();

    expect(restored?.refreshToken, session.refreshToken);
    expect(values.values[legacyKey], isNotNull);
  });

  test('isolates sessions by server origin and clears only its own session',
      () async {
    final values = _MemorySecureValues();
    final first = SecureTokenStore(
      serverUrl: 'https://one.example',
      secureValues: values,
    );
    final second = SecureTokenStore(
      serverUrl: 'https://two.example',
      secureValues: values,
    );
    await first.write(_session(accessToken: 'one'));
    await second.write(_session(accessToken: 'two'));

    await first.clear();

    expect(await first.read(), isNull);
    expect((await second.read())?.accessToken, 'two');
  });

  test('deletes a corrupt persisted session instead of breaking startup',
      () async {
    final values = _MemorySecureValues();
    final store = SecureTokenStore(
      serverUrl: 'https://example.test',
      secureValues: values,
    );
    values.values['unknown'] = 'unrelated';
    // Discover the namespaced key without exposing its server-derived digest.
    await store.write(_session());
    final sessionKey = values.values.keys.singleWhere(
      (key) => key != 'unknown',
    );
    values.values[sessionKey] = '{broken';

    expect(await store.read(), isNull);
    expect(values.values.containsKey(sessionKey), isFalse);
    expect(values.values['unknown'], 'unrelated');
  });

  test('uses private fallback without failing a successful login write',
      () async {
    final primary = _ControllableSecureValues()..failWrite = true;
    final fallback = _ControllableSecureValues();
    final markers = _MemoryDeletionMarkers();
    final first = ResilientSecureValueStore(
      primary: primary,
      privateFileFallback: fallback,
      deletionMarkers: markers,
    );

    await first.write('session', 'current');

    expect(await first.read('session'), 'current');
    expect(
      first.storageStatus.value.backend,
      TokenStorageBackend.privateFileFallback,
    );
    expect(fallback.values['session'], 'current');

    primary.failWrite = false;
    final restarted = ResilientSecureValueStore(
      primary: primary,
      privateFileFallback: fallback,
      deletionMarkers: markers,
    );
    expect(await restarted.read('session'), 'current');
    expect(primary.values['session'], 'current');
    expect(fallback.values['session'], isNull);
    expect(
      restarted.storageStatus.value.backend,
      TokenStorageBackend.platformSecure,
    );
  });

  test('newer private fallback replaces a stale recovered platform session',
      () async {
    final primary = _ControllableSecureValues()
      ..values['session'] = 'stale-platform'
      ..failWrite = true;
    final fallback = _ControllableSecureValues();
    final markers = _MemoryDeletionMarkers();
    final first = ResilientSecureValueStore(
      primary: primary,
      privateFileFallback: fallback,
      deletionMarkers: markers,
    );
    await first.write('session', 'rotated-fallback');
    expect(primary.values['session'], 'stale-platform');
    expect(fallback.values['session'], 'rotated-fallback');

    primary.failWrite = false;
    final restarted = ResilientSecureValueStore(
      primary: primary,
      privateFileFallback: fallback,
      deletionMarkers: markers,
    );

    expect(await restarted.read('session'), 'rotated-fallback');
    expect(primary.values['session'], 'rotated-fallback');
    expect(fallback.values['session'], isNull);
  });

  test('newer platform value replaces an older retained private fallback',
      () async {
    final primary = _ControllableSecureValues();
    final fallback = _ControllableSecureValues()..failDelete = true;
    final markers = _MemoryDeletionMarkers();
    final first = ResilientSecureValueStore(
      primary: primary,
      privateFileFallback: fallback,
      deletionMarkers: markers,
    );
    await first.write('session', 'old-both');
    expect(fallback.values['session'], 'old-both');

    fallback.failWrite = true;
    await first.write('session', 'new-platform');
    expect(primary.values['session'], 'new-platform');
    expect(fallback.values['session'], 'old-both');

    fallback
      ..failWrite = false
      ..failDelete = false;
    final restarted = ResilientSecureValueStore(
      primary: primary,
      privateFileFallback: fallback,
      deletionMarkers: markers,
    );

    expect(await restarted.read('session'), 'new-platform');
    expect(fallback.values['session'], isNull);
  });

  test('keeps a successful login usable in memory when persistence fails',
      () async {
    final primary = _ControllableSecureValues()..failWrite = true;
    final store = ResilientSecureValueStore(
      primary: primary,
      deletionMarkers: _MemoryDeletionMarkers(),
    );

    await store.write('session', 'current');

    expect(await store.read('session'), 'current');
    expect(
      store.storageStatus.value.backend,
      TokenStorageBackend.memoryOnly,
    );
    expect(store.storageStatus.value.survivesRestart, isFalse);
  });

  test('memory fallback survives replacement of the token-store wrapper',
      () async {
    final primary = _ControllableSecureValues()..failWrite = true;
    final resilient = ResilientSecureValueStore(
      primary: primary,
      deletionMarkers: _MemoryDeletionMarkers(),
    );
    final first = SecureTokenStore(
      serverUrl: 'https://example.test',
      secureValues: resilient,
    );
    final session = _session(accessToken: 'memory-access');
    await first.write(session);

    final replacement = SecureTokenStore(
      serverUrl: 'https://example.test/',
      secureValues: resilient,
    );

    expect((await replacement.read())?.accessToken, 'memory-access');
    expect(
      replacement.storageStatus.value.backend,
      TokenStorageBackend.memoryOnly,
    );
  });

  test('failed primary clear cannot resurrect an old credential', () async {
    final primary = _ControllableSecureValues()
      ..values['session'] = 'stale'
      ..failDelete = true;
    final fallback = _ControllableSecureValues();
    final markers = _MemoryDeletionMarkers();
    final first = ResilientSecureValueStore(
      primary: primary,
      privateFileFallback: fallback,
      deletionMarkers: markers,
    );

    await first.delete('session');
    expect(primary.values['session'], 'stale');
    expect(markers.marked, contains('session'));

    primary.failDelete = false;
    final restarted = ResilientSecureValueStore(
      primary: primary,
      privateFileFallback: fallback,
      deletionMarkers: markers,
    );
    expect(await restarted.read('session'), isNull);
    expect(primary.values['session'], isNull);
    expect(fallback.values['session'], isNull);
    expect(markers.marked, isNot(contains('session')));
  });

  test('a new write replaces a prior deletion tombstone', () async {
    final primary = _ControllableSecureValues()
      ..values['session'] = 'stale'
      ..failDelete = true;
    final fallback = _ControllableSecureValues();
    final markers = _MemoryDeletionMarkers();
    final first = ResilientSecureValueStore(
      primary: primary,
      privateFileFallback: fallback,
      deletionMarkers: markers,
    );
    await first.delete('session');

    primary.failDelete = false;
    await first.write('session', 'new');

    final restarted = ResilientSecureValueStore(
      primary: primary,
      privateFileFallback: fallback,
      deletionMarkers: markers,
    );
    expect(await restarted.read('session'), 'new');
  });

  test('primary success survives an unavailable stale-tombstone fallback',
      () async {
    final primary = _ControllableSecureValues()
      ..values['session'] = 'stale'
      ..failDelete = true;
    final fallback = _ControllableSecureValues();
    final markers = _MemoryDeletionMarkers();
    final first = ResilientSecureValueStore(
      primary: primary,
      privateFileFallback: fallback,
      deletionMarkers: markers,
    );
    await first.delete('session');

    primary.failDelete = false;
    fallback.failWrite = true;
    await first.write('session', 'new');
    expect(
      first.storageStatus.value.backend,
      TokenStorageBackend.platformSecure,
    );

    fallback.failWrite = false;
    final restarted = ResilientSecureValueStore(
      primary: primary,
      privateFileFallback: fallback,
      deletionMarkers: markers,
    );
    expect(await restarted.read('session'), 'new');
    expect(primary.values['session'], 'new');
    expect(fallback.values['session'], isNull);
  });
}

AuthSessionDto _session({String accessToken = 'access'}) => AuthSessionDto(
      accessToken: accessToken,
      accessTokenExpiresIn: 900,
      refreshToken: 'refresh-$accessToken',
      refreshTokenExpiresAt: DateTime.utc(2030),
      user: const ApiUserDto(
        id: 'user-1',
        username: 'alice',
        role: 'user',
      ),
    );

final class _MemorySecureValues implements SecureValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

final class _ControllableSecureValues implements SecureValueStore {
  final Map<String, String> values = <String, String>{};
  bool failRead = false;
  bool failWrite = false;
  bool failDelete = false;

  @override
  Future<String?> read(String key) async {
    if (failRead) throw StateError('read unavailable');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (failWrite) throw StateError('write unavailable');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    if (failDelete) throw StateError('delete unavailable');
    values.remove(key);
  }
}

final class _MemoryDeletionMarkers implements DeletionMarkerStore {
  final Map<String, bool> states = <String, bool>{};

  Iterable<String> get marked =>
      states.entries.where((entry) => entry.value).map((entry) => entry.key);

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
