import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:openlogtool/models/collaboration_dto.dart';
import 'package:openlogtool/services/private_file_secure_values.dart';
import 'package:openlogtool/services/server_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum TokenStorageBackend {
  platformSecure,
  privateFileFallback,
  memoryOnly,
}

@immutable
final class TokenStorageStatus {
  const TokenStorageStatus({
    required this.backend,
    this.reason,
  });

  final TokenStorageBackend backend;
  final String? reason;

  bool get isDegraded => backend != TokenStorageBackend.platformSecure;
  bool get survivesRestart => backend != TokenStorageBackend.memoryOnly;
}

abstract interface class TokenStorageStatusSource {
  ValueListenable<TokenStorageStatus> get storageStatus;
}

abstract interface class SecureValueStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

final class FlutterSecureValueStore implements SecureValueStore {
  const FlutterSecureValueStore([
    this._storage = const FlutterSecureStorage(
      aOptions: AndroidOptions(storageNamespace: 'openlogtool_auth_v1'),
    ),
  ]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

abstract interface class DeletionMarkerStore {
  /// Returns null when this key has never had a persisted authority state.
  Future<bool?> read(String key);

  Future<void> mark(String key);

  /// Records that the platform-secure value is authoritative.
  Future<void> unmark(String key);

  /// Removes the authority state when the private fallback is authoritative.
  Future<void> forget(String key);
}

final class SharedPreferencesDeletionMarkerStore
    implements DeletionMarkerStore {
  const SharedPreferencesDeletionMarkerStore();

  @override
  Future<bool?> read(String key) async =>
      (await SharedPreferences.getInstance()).getBool(_markerKey(key));

  @override
  Future<void> mark(String key) async {
    final written = await (await SharedPreferences.getInstance())
        .setBool(_markerKey(key), true);
    if (!written) {
      throw StateError('Unable to persist credential deletion marker');
    }
  }

  @override
  Future<void> unmark(String key) async {
    // Persist false rather than removing the key. A live private fallback uses
    // the absent state, while false makes a recovered keyring authoritative.
    final written = await (await SharedPreferences.getInstance())
        .setBool(_markerKey(key), false);
    if (!written) {
      throw StateError('Unable to persist platform credential authority');
    }
  }

  @override
  Future<void> forget(String key) async {
    final preferences = await SharedPreferences.getInstance();
    final markerKey = _markerKey(key);
    if (!preferences.containsKey(markerKey)) return;
    final removed = await preferences.remove(markerKey);
    if (!removed) {
      throw StateError('Unable to persist private fallback authority');
    }
  }

  static String _markerKey(String key) =>
      'openlogtool.auth.deleted.v1.${sha256.convert(utf8.encode(key))}';
}

final class PlatformPrivateSecureValueStore implements SecureValueStore {
  PlatformPrivateSecureValueStore(this._backend);

  final PlatformPrivateSecureValueBackend _backend;

  @override
  Future<String?> read(String key) => _backend.read(key);

  @override
  Future<void> write(String key, String value) => _backend.write(key, value);

  @override
  Future<void> delete(String key) => _backend.delete(key);
}

/// Keeps authentication usable when a platform credential service is
/// temporarily unavailable. Linux gets a 0600 private-file fallback; other
/// platforms fall back to memory only. A non-secret deletion marker and a
/// Linux file tombstone prevent a failed secure-store delete from reviving an
/// old session later.
final class ResilientSecureValueStore
    implements SecureValueStore, TokenStorageStatusSource {
  ResilientSecureValueStore({
    required SecureValueStore primary,
    SecureValueStore? privateFileFallback,
    DeletionMarkerStore deletionMarkers =
        const SharedPreferencesDeletionMarkerStore(),
  })  : _primary = primary,
        _privateFileFallback = privateFileFallback,
        _deletionMarkers = deletionMarkers;

  static const _deletionTombstone = '\u0000openlogtool-auth-deleted-v1';

  final SecureValueStore _primary;
  final SecureValueStore? _privateFileFallback;
  final DeletionMarkerStore _deletionMarkers;
  final _MemorySecureValueStore _memory = _MemorySecureValueStore();
  final Set<String> _activeValues = <String>{};
  final Set<String> _memoryDeletionMarkers = <String>{};
  final ValueNotifier<TokenStorageStatus> _status = ValueNotifier(
    const TokenStorageStatus(backend: TokenStorageBackend.platformSecure),
  );
  Future<void> _operationTail = Future<void>.value();

  @override
  ValueListenable<TokenStorageStatus> get storageStatus => _status;

  @override
  Future<String?> read(String key) => _synchronized(() => _read(key));

  @override
  Future<void> write(String key, String value) =>
      _synchronized(() => _write(key, value));

  @override
  Future<void> delete(String key) => _synchronized(() => _delete(key));

  Future<String?> _read(String key) async {
    if (_activeValues.contains(key)) {
      final activeValue = await _memory.read(key);
      if (activeValue != null) return activeValue;
      _activeValues.remove(key);
    }

    String? fallbackValue;
    Object? fallbackError;
    final fallback = _privateFileFallback;
    if (fallback != null) {
      try {
        fallbackValue = await fallback.read(key);
      } catch (error) {
        fallbackError = error;
      }
    }

    final deletionState = await _deletionState(key);
    final fallbackIsTombstone = fallbackValue == _deletionTombstone;
    if (deletionState.marked || (!deletionState.known && fallbackIsTombstone)) {
      await _purgeDeletedValue(
        key,
        fallbackAlreadyUnavailable: fallbackError != null,
      );
      return null;
    }
    if (fallbackIsTombstone) {
      fallbackValue = null;
      await _tryDeleteFallback(key);
    }

    if (fallbackValue != null && !deletionState.known) {
      // A live fallback is written only after the platform store failed (or
      // when no platform-current marker exists. It can therefore be newer
      // than a stale platform value left behind before token rotation.
      return _promoteFallback(key, fallbackValue);
    }

    try {
      final primaryValue = await _primary.read(key);
      if (primaryValue != null) {
        await _rememberActive(key, primaryValue);
        if (fallbackValue != null) await _tryDeleteFallback(key);
        _report(TokenStorageBackend.platformSecure);
        return primaryValue;
      }

      if (fallbackValue != null) {
        return _promoteFallback(key, fallbackValue);
      }

      final memoryValue = await _memory.read(key);
      if (memoryValue != null) {
        _activeValues.add(key);
        return memoryValue;
      }
      _report(TokenStorageBackend.platformSecure);
      return null;
    } catch (primaryError) {
      if (fallbackValue != null) {
        await _rememberActive(key, fallbackValue);
        _report(TokenStorageBackend.privateFileFallback, primaryError);
        return fallbackValue;
      }
      final memoryValue = await _memory.read(key);
      _report(
        fallback != null && fallbackError == null
            ? TokenStorageBackend.privateFileFallback
            : TokenStorageBackend.memoryOnly,
        primaryError,
      );
      return memoryValue;
    }
  }

  Future<void> _write(String key, String value) async {
    Object? primaryError;
    var primaryWritten = false;
    try {
      await _primary.write(key, value);
      primaryWritten = true;
    } catch (error) {
      primaryError = error;
    }

    final fallback = _privateFileFallback;
    var fallbackWritten = false;
    if (fallback != null) {
      try {
        // Overwrite any old deletion tombstone before the marker is cleared.
        // This makes a crash prefer logging out over reviving a stale session.
        await fallback.write(key, value);
        fallbackWritten = true;
      } catch (_) {
        // Memory remains the final availability fallback.
      }
    }

    await _rememberActive(key, value);
    final safelyPersistent = primaryWritten || fallbackWritten;
    final markerCleared = safelyPersistent &&
        (primaryWritten
            ? await _tryUnmarkDeletion(key)
            : await _tryForgetDeletion(key));
    if (!markerCleared) {
      await _tryMarkDeletion(key);
    }

    if (primaryWritten && fallbackWritten && markerCleared) {
      await _tryDeleteFallback(key);
    }

    if (primaryWritten && (fallback == null || markerCleared)) {
      _report(TokenStorageBackend.platformSecure);
    } else if (fallbackWritten && markerCleared) {
      _report(TokenStorageBackend.privateFileFallback, primaryError);
    } else {
      _report(TokenStorageBackend.memoryOnly, primaryError);
    }
  }

  Future<void> _delete(String key) async {
    _activeValues.remove(key);
    _memoryDeletionMarkers.add(key);
    await _memory.delete(key);

    final markerWritten = await _tryMarkDeletion(key);
    var tombstoneWritten = false;
    final fallback = _privateFileFallback;
    if (fallback != null) {
      try {
        await fallback.write(key, _deletionTombstone);
        tombstoneWritten = true;
      } catch (_) {
        // The regular deletion marker may still protect against resurrection.
      }
    }

    Object? primaryError;
    var primaryDeleted = false;
    try {
      await _primary.delete(key);
      primaryDeleted = true;
    } catch (error) {
      primaryError = error;
    }

    var fallbackDeleted = fallback == null;
    if (fallback != null && primaryDeleted) {
      try {
        await fallback.delete(key);
        fallbackDeleted = true;
      } catch (_) {
        fallbackDeleted = false;
      }
    }

    if (primaryDeleted && fallbackDeleted) {
      await _tryUnmarkDeletion(key);
      _memoryDeletionMarkers.remove(key);
      _report(TokenStorageBackend.platformSecure);
    } else if (markerWritten || tombstoneWritten) {
      _report(
        tombstoneWritten
            ? TokenStorageBackend.privateFileFallback
            : TokenStorageBackend.memoryOnly,
        primaryError,
      );
    } else {
      _report(TokenStorageBackend.memoryOnly, primaryError);
    }
  }

  Future<void> _purgeDeletedValue(
    String key, {
    required bool fallbackAlreadyUnavailable,
  }) async {
    _activeValues.remove(key);
    _memoryDeletionMarkers.add(key);
    await _memory.delete(key);

    Object? primaryError;
    var primaryDeleted = false;
    try {
      await _primary.delete(key);
      primaryDeleted = true;
    } catch (error) {
      primaryError = error;
    }

    final fallback = _privateFileFallback;
    var fallbackDeleted = fallback == null;
    if (fallback != null && !fallbackAlreadyUnavailable && primaryDeleted) {
      try {
        await fallback.delete(key);
        fallbackDeleted = true;
      } catch (_) {
        fallbackDeleted = false;
      }
    }

    if (primaryDeleted && fallbackDeleted) {
      await _tryUnmarkDeletion(key);
      _memoryDeletionMarkers.remove(key);
      _report(TokenStorageBackend.platformSecure);
    } else {
      _report(
        fallback != null && !fallbackAlreadyUnavailable
            ? TokenStorageBackend.privateFileFallback
            : TokenStorageBackend.memoryOnly,
        primaryError,
      );
    }
  }

  Future<({bool marked, bool known})> _deletionState(String key) async {
    if (_memoryDeletionMarkers.contains(key)) {
      return (marked: true, known: true);
    }
    try {
      final marked = await _deletionMarkers.read(key);
      if (marked == true) _memoryDeletionMarkers.add(key);
      return (marked: marked ?? false, known: marked != null);
    } catch (_) {
      return (marked: false, known: false);
    }
  }

  Future<bool> _tryMarkDeletion(String key) async {
    _memoryDeletionMarkers.add(key);
    try {
      await _deletionMarkers.mark(key);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _tryUnmarkDeletion(String key) async {
    try {
      await _deletionMarkers.unmark(key);
      _memoryDeletionMarkers.remove(key);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _tryForgetDeletion(String key) async {
    try {
      await _deletionMarkers.forget(key);
      _memoryDeletionMarkers.remove(key);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String> _promoteFallback(String key, String value) async {
    await _rememberActive(key, value);
    try {
      await _primary.write(key, value);
      if (await _tryUnmarkDeletion(key)) {
        await _tryDeleteFallback(key);
        _report(TokenStorageBackend.platformSecure);
      } else {
        await _tryMarkDeletion(key);
        _report(
          TokenStorageBackend.memoryOnly,
          StateError('Unable to persist token authority marker'),
        );
      }
    } catch (error) {
      _report(TokenStorageBackend.privateFileFallback, error);
    }
    return value;
  }

  Future<void> _rememberActive(String key, String value) async {
    await _memory.write(key, value);
    _activeValues.add(key);
    _memoryDeletionMarkers.remove(key);
  }

  Future<void> _tryDeleteFallback(String key) async {
    try {
      await _privateFileFallback?.delete(key);
    } catch (_) {
      // A same-user private copy may remain, but the platform store remains
      // authoritative and the copy will be retried on the next read/write.
    }
  }

  void _report(TokenStorageBackend backend, [Object? error]) {
    final next = TokenStorageStatus(
      backend: backend,
      reason: error?.toString(),
    );
    final current = _status.value;
    if (current.backend == next.backend && current.reason == next.reason) {
      return;
    }
    _status.value = next;
  }

  Future<T> _synchronized<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _operationTail = _operationTail.then((_) async {
      try {
        result.complete(await operation());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }
}

final class _MemorySecureValueStore implements SecureValueStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}

/// Persists one server's refreshable authentication session in the platform
/// credential store. Passwords are never stored.
final class SecureTokenStore implements TokenStore, TokenStorageStatusSource {
  SecureTokenStore({
    required String serverUrl,
    SecureValueStore? secureValues,
  })  : _secureValues = secureValues ?? _defaultSecureValues,
        _key = _keyForServer(serverUrl);

  static final ValueNotifier<TokenStorageStatus> _secureStatus = ValueNotifier(
    const TokenStorageStatus(backend: TokenStorageBackend.platformSecure),
  );
  static final SecureValueStore _defaultSecureValues = _buildDefaultStore();

  final SecureValueStore _secureValues;
  final String _key;

  @override
  ValueListenable<TokenStorageStatus> get storageStatus =>
      _secureValues is TokenStorageStatusSource
          ? (_secureValues as TokenStorageStatusSource).storageStatus
          : _secureStatus;

  @override
  Future<AuthSessionDto?> read() async {
    final encoded = await _secureValues.read(_key);
    if (encoded == null) return null;
    try {
      return AuthSessionDto.fromJson(jsonDecode(encoded));
    } on FormatException {
      await _secureValues.delete(_key);
      return null;
    }
  }

  @override
  Future<void> write(AuthSessionDto session) =>
      _secureValues.write(_key, jsonEncode(session.toJson()));

  @override
  Future<void> clear() => _secureValues.delete(_key);

  static String _keyForServer(String serverUrl) {
    final normalized = serverUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final digest = sha256.convert(utf8.encode(normalized)).toString();
    return 'openlogtool.auth.v1.$digest';
  }

  static SecureValueStore _buildDefaultStore() {
    final privateBackend = PlatformPrivateSecureValueBackend();
    return ResilientSecureValueStore(
      primary: const FlutterSecureValueStore(),
      privateFileFallback: privateBackend.isSupported
          ? PlatformPrivateSecureValueStore(privateBackend)
          : null,
    );
  }
}
