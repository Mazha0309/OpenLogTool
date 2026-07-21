import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:openlogtool/services/secure_token_store.dart';

/// Stores AI provider credentials separately from exportable provider
/// profiles.
///
/// Profiles persist only an opaque credential ID. The ID is hashed before it
/// becomes a platform-storage key, so user supplied IDs cannot escape this
/// namespace or collide with account sessions.
final class AiCredentialStore implements TokenStorageStatusSource {
  AiCredentialStore({SecureValueStore? secureValues})
      : _secureValues = secureValues ?? _defaultSecureValues;

  static final SecureValueStore _defaultSecureValues =
      defaultSecureValueStore();
  static final ValueNotifier<TokenStorageStatus> _secureStatus = ValueNotifier(
    const TokenStorageStatus(backend: TokenStorageBackend.platformSecure),
  );

  final SecureValueStore _secureValues;

  @override
  ValueListenable<TokenStorageStatus> get storageStatus =>
      _secureValues is TokenStorageStatusSource
          ? (_secureValues as TokenStorageStatusSource).storageStatus
          : _secureStatus;

  Future<String?> read(String credentialId) =>
      _secureValues.read(_keyFor(credentialId));

  Future<void> write(String credentialId, String secret) {
    if (secret.isEmpty) {
      throw ArgumentError.value(secret, 'secret', 'must not be empty');
    }
    return _secureValues.write(_keyFor(credentialId), secret);
  }

  Future<void> delete(String credentialId) =>
      _secureValues.delete(_keyFor(credentialId));

  static String _keyFor(String credentialId) {
    final normalized = credentialId.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(
        credentialId,
        'credentialId',
        'must not be empty',
      );
    }
    final digest = sha256.convert(utf8.encode(normalized));
    return 'openlogtool.ai.credential.v1.$digest';
  }
}
