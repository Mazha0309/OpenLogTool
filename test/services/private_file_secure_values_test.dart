import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/models/collaboration_dto.dart';
import 'package:openlogtool/services/private_file_secure_values.dart';
import 'package:openlogtool/services/secure_token_store.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'persists atomically with user-only Linux permissions',
    () async {
      final support = await Directory.systemTemp.createTemp(
        'openlogtool-secure-fallback-',
      );
      addTearDown(() => support.delete(recursive: true));
      final first = PlatformPrivateSecureValueBackend(
        supportDirectory: () async => support.path,
      );

      await Future.wait(<Future<void>>[
        first.write('one', 'secret-one'),
        first.write('two', 'secret-two'),
      ]);

      final directory = Directory(
        p.join(support.path, 'secure_storage_fallback'),
      );
      final file = File(p.join(directory.path, 'auth_sessions.json'));
      expect(await _mode(directory.path), '700');
      expect(await _mode(file.path), '600');
      expect(
        directory.listSync().whereType<File>().map((item) => item.path),
        <String>[file.path],
      );

      final restarted = PlatformPrivateSecureValueBackend(
        supportDirectory: () async => support.path,
      );
      expect(await restarted.read('one'), 'secret-one');
      expect(await restarted.read('two'), 'secret-two');
    },
    skip: !Platform.isLinux,
  );

  test(
    'clears a corrupt private credential file safely',
    () async {
      final support = await Directory.systemTemp.createTemp(
        'openlogtool-secure-fallback-corrupt-',
      );
      addTearDown(() => support.delete(recursive: true));
      final backend = PlatformPrivateSecureValueBackend(
        supportDirectory: () async => support.path,
      );
      await backend.write('session', 'secret');
      final file = File(
        p.join(
          support.path,
          'secure_storage_fallback',
          'auth_sessions.json',
        ),
      );
      await file.writeAsString(jsonEncode(<String, Object?>{'session': 42}));

      expect(await backend.read('session'), isNull);
      expect(await file.exists(), isFalse);
    },
    skip: !Platform.isLinux,
  );

  test(
    'Linux fallback survives replacement of every token-store wrapper',
    () async {
      final support = await Directory.systemTemp.createTemp(
        'openlogtool-secure-fallback-wrapper-',
      );
      addTearDown(() => support.delete(recursive: true));
      final markers = _MemoryDeletionMarkers();
      final firstValues = ResilientSecureValueStore(
        primary: _UnavailableSecureValues(),
        privateFileFallback: PlatformPrivateSecureValueStore(
          PlatformPrivateSecureValueBackend(
            supportDirectory: () async => support.path,
          ),
        ),
        deletionMarkers: markers,
      );
      final first = SecureTokenStore(
        serverUrl: 'https://example.test',
        secureValues: firstValues,
      );
      await first.write(_session());

      final restartedValues = ResilientSecureValueStore(
        primary: _UnavailableSecureValues(),
        privateFileFallback: PlatformPrivateSecureValueStore(
          PlatformPrivateSecureValueBackend(
            supportDirectory: () async => support.path,
          ),
        ),
        deletionMarkers: markers,
      );
      final replacement = SecureTokenStore(
        serverUrl: 'https://example.test/',
        secureValues: restartedValues,
      );

      expect((await replacement.read())?.accessToken, 'file-access');
      expect(
        replacement.storageStatus.value.backend,
        TokenStorageBackend.privateFileFallback,
      );
    },
    skip: !Platform.isLinux,
  );
}

Future<String> _mode(String path) async {
  final result = await Process.run('stat', <String>['-c', '%a', path]);
  if (result.exitCode != 0) {
    throw ProcessException('stat', <String>[path], '${result.stderr}');
  }
  return (result.stdout as String).trim();
}

AuthSessionDto _session() => AuthSessionDto(
      accessToken: 'file-access',
      accessTokenExpiresIn: 900,
      refreshToken: 'file-refresh',
      refreshTokenExpiresAt: DateTime.utc(2030),
      user: const ApiUserDto(
        id: 'user-1',
        username: 'alice',
        role: 'user',
      ),
    );

final class _UnavailableSecureValues implements SecureValueStore {
  @override
  Future<String?> read(String key) =>
      Future<String?>.error(StateError('keyring unavailable'));

  @override
  Future<void> write(String key, String value) =>
      Future<void>.error(StateError('keyring unavailable'));

  @override
  Future<void> delete(String key) =>
      Future<void>.error(StateError('keyring unavailable'));
}

final class _MemoryDeletionMarkers implements DeletionMarkerStore {
  final Map<String, bool> _states = <String, bool>{};

  @override
  Future<bool?> read(String key) async => _states[key];

  @override
  Future<void> mark(String key) async {
    _states[key] = true;
  }

  @override
  Future<void> unmark(String key) async {
    _states[key] = false;
  }

  @override
  Future<void> forget(String key) async {
    _states.remove(key);
  }
}
