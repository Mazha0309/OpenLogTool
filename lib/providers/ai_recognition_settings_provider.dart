import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:openlogtool/services/ai_credential_store.dart';
import 'package:openlogtool/services/ai_recognition/models.dart';
import 'package:openlogtool/services/ai_recognition/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// On-device AI configuration. Provider profiles are ordinary exportable JSON;
/// credentials are referenced by ID and live only in [AiCredentialStore].
final class AiRecognitionSettingsProvider with ChangeNotifier {
  AiRecognitionSettingsProvider({
    Future<SharedPreferences> Function()? preferencesLoader,
    AiCredentialStore? credentialStore,
  })  : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance,
        _credentialStore = credentialStore ?? AiCredentialStore() {
    unawaited(_load());
  }

  static const int schemaVersion = 1;
  static const String _storageKey = 'openlogtool.ai.settings.v1';

  final Future<SharedPreferences> Function() _preferencesLoader;
  final AiCredentialStore _credentialStore;
  final Completer<void> _initialized = Completer<void>();
  Future<void> _mutationTail = Future<void>.value();
  Future<void> _saveTail = Future<void>.value();

  List<AiProviderProfile> _profiles = const [];
  String? _activeAsrProfileId;
  String? _activeFieldExtractionProfileId;
  bool _enabled = false;
  bool _useLocalReferenceContext = true;
  Object? _loadError;
  bool _disposed = false;

  Future<void> get initialized => _initialized.future;
  bool get enabled => _enabled;
  bool get useLocalReferenceContext => _useLocalReferenceContext;
  Object? get loadError => _loadError;
  List<AiProviderProfile> get profiles => _profiles;
  Iterable<AiProviderProfile> get asrProfiles => _profiles.where(
        (profile) => profile.kind == AiProviderKind.speechRecognition,
      );
  Iterable<AiProviderProfile> get fieldExtractionProfiles => _profiles.where(
        (profile) => profile.kind == AiProviderKind.fieldExtraction,
      );
  String? get activeAsrProfileId => _activeAsrProfileId;
  String? get activeFieldExtractionProfileId => _activeFieldExtractionProfileId;
  AiProviderProfile? get activeAsrProfile => _profileById(_activeAsrProfileId);
  AiProviderProfile? get activeFieldExtractionProfile =>
      _profileById(_activeFieldExtractionProfileId);

  AiCredentialResolver get credentialResolver => resolveCredentials;

  Future<void> _load() async {
    try {
      final preferences = await _preferencesLoader();
      if (_disposed) return;
      final encoded = preferences.getString(_storageKey);
      if (encoded != null) _restore(jsonDecode(encoded));
    } catch (error) {
      _loadError = error;
      _profiles = const [];
      _activeAsrProfileId = null;
      _activeFieldExtractionProfileId = null;
      _enabled = false;
      _useLocalReferenceContext = true;
    } finally {
      if (!_initialized.isCompleted) _initialized.complete();
      if (!_disposed) notifyListeners();
    }
  }

  void _restore(Object? value) {
    if (value is! Map) {
      throw const FormatException('AI settings must be a JSON object');
    }
    final json = Map<String, Object?>.from(value);
    if (json['schemaVersion'] != schemaVersion) {
      throw FormatException(
        'Unsupported AI settings schema: ${json['schemaVersion']}',
      );
    }
    final rawProfiles = json['profiles'];
    if (rawProfiles is! List) {
      throw const FormatException('AI settings profiles must be a list');
    }
    final restored =
        rawProfiles.map(AiProviderProfile.fromJson).toList(growable: false);
    _ensureUniqueIds(restored);
    _profiles = List.unmodifiable(restored);
    _activeAsrProfileId = _validActiveId(
      json['activeAsrProfileId'],
      AiProviderKind.speechRecognition,
    );
    _activeFieldExtractionProfileId = _validActiveId(
      json['activeFieldExtractionProfileId'],
      AiProviderKind.fieldExtraction,
    );
    _enabled = json['enabled'] == true && _activeAsrProfileId != null;
    _useLocalReferenceContext = json['useLocalReferenceContext'] != false;
  }

  Future<void> setEnabled(bool value) => _mutate(() async {
        await initialized;
        if (value && activeAsrProfile == null) {
          throw StateError('AI_ASR_PROFILE_REQUIRED');
        }
        if (_enabled == value) return;
        _enabled = value;
        notifyListeners();
        await _persist();
      });

  Future<void> setUseLocalReferenceContext(bool value) => _mutate(() async {
        await initialized;
        if (_useLocalReferenceContext == value) return;
        _useLocalReferenceContext = value;
        notifyListeners();
        await _persist();
      });

  Future<void> setActiveAsrProfile(String? profileId) => _mutate(() async {
        await initialized;
        _requireKind(profileId, AiProviderKind.speechRecognition);
        if (_activeAsrProfileId == profileId) return;
        _activeAsrProfileId = profileId;
        if (profileId == null) _enabled = false;
        notifyListeners();
        await _persist();
      });

  Future<void> setActiveFieldExtractionProfile(String? profileId) =>
      _mutate(() async {
        await initialized;
        _requireKind(profileId, AiProviderKind.fieldExtraction);
        if (_activeFieldExtractionProfileId == profileId) return;
        _activeFieldExtractionProfileId = profileId;
        notifyListeners();
        await _persist();
      });

  Future<void> upsertProfile(AiProviderProfile profile) => _mutate(() async {
        await initialized;
        _ensureSharedCredentialDestination(profile);
        final updated = List<AiProviderProfile>.from(_profiles);
        final index =
            updated.indexWhere((candidate) => candidate.id == profile.id);
        final previous = index < 0 ? null : updated[index];
        if (previous != null &&
            _credentialBindingChanged(previous, profile) &&
            previous.credentialId != null &&
            previous.credentialId == profile.credentialId) {
          throw StateError('AI_CREDENTIAL_REBIND_REQUIRED');
        }
        if (index < 0) {
          updated.add(profile);
        } else {
          updated[index] = profile;
        }
        _profiles = List.unmodifiable(updated);

        if (_activeAsrProfileId == profile.id &&
            profile.kind != AiProviderKind.speechRecognition) {
          _activeAsrProfileId = null;
          _enabled = false;
        }
        if (_activeFieldExtractionProfileId == profile.id &&
            profile.kind != AiProviderKind.fieldExtraction) {
          _activeFieldExtractionProfileId = null;
        }
        notifyListeners();
        await _persist();

        final previousCredentialId = previous?.credentialId;
        if (previousCredentialId != null &&
            previousCredentialId != profile.credentialId &&
            !_profiles
                .any((item) => item.credentialId == previousCredentialId)) {
          await _credentialStore.delete(previousCredentialId);
        }
      });

  Future<void> removeProfile(String profileId) => _mutate(() async {
        await initialized;
        final profile = _profileById(profileId);
        if (profile == null) return;
        _profiles = List.unmodifiable(
          _profiles.where((candidate) => candidate.id != profileId),
        );
        if (_activeAsrProfileId == profileId) {
          _activeAsrProfileId = null;
          _enabled = false;
        }
        if (_activeFieldExtractionProfileId == profileId) {
          _activeFieldExtractionProfileId = null;
        }
        notifyListeners();
        await _persist();

        final credentialId = profile.credentialId;
        if (credentialId != null &&
            !_profiles.any((item) => item.credentialId == credentialId)) {
          await _credentialStore.delete(credentialId);
        }
      });

  Future<void> saveCredential(String profileId, String secret) =>
      _mutate(() async {
        await initialized;
        final profile = _profileById(profileId);
        if (profile == null) throw StateError('AI_PROFILE_NOT_FOUND');
        final credentialId = profile.credentialId;
        if (credentialId == null ||
            profile.credentialTransport.location == AiCredentialLocation.none) {
          throw StateError('AI_PROFILE_DOES_NOT_USE_CREDENTIALS');
        }
        await _credentialStore.write(credentialId, secret);
        notifyListeners();
      });

  Future<bool> hasCredential(String profileId) async {
    await initialized;
    final profile = _profileById(profileId);
    final credentialId = profile?.credentialId;
    if (credentialId == null) return false;
    return (await _credentialStore.read(credentialId)) != null;
  }

  Future<AiCredentials?> resolveCredentials(AiCredentialRequest request) async {
    await initialized;
    final credentialId = request.credentialId;
    if (credentialId == null) return null;
    final profile = _profileById(request.providerId);
    if (profile == null || profile.credentialId != credentialId) return null;
    final value = await _credentialStore.read(credentialId);
    return value == null ? null : AiCredentials(apiKey: value);
  }

  /// Exports provider definitions only. Enabling state and secure credential
  /// values remain private to this installation. Custom provider metadata is
  /// intentionally portable and must not be used to store authentication.
  String exportProfiles() => const JsonEncoder.withIndent('  ').convert({
        'schemaVersion': schemaVersion,
        'profiles': _profiles.map((profile) {
          final portable = profile.toJson();
          portable.remove('credentialId');
          return portable;
        }).toList(),
      });

  /// Replaces provider definitions from a portable, credential-free profile
  /// bundle. Imported credential IDs are references only and need a local key.
  Future<void> importProfiles(String encoded) => _mutate(() async {
        await initialized;
        final value = jsonDecode(encoded);
        if (value is! Map) {
          throw const FormatException('AI profile bundle must be an object');
        }
        final json = Map<String, Object?>.from(value);
        if (json['schemaVersion'] != schemaVersion) {
          throw FormatException(
            'Unsupported AI profile schema: ${json['schemaVersion']}',
          );
        }
        final rawProfiles = json['profiles'];
        if (rawProfiles is! List) {
          throw const FormatException('AI profiles must be a list');
        }
        final imported = rawProfiles.map((value) {
          if (value is! Map) {
            throw const FormatException(
              'AI provider profile must be an object',
            );
          }
          // A portable profile must never gain authority over a credential
          // already on this device, even when a hand-written bundle tries to
          // smuggle in a known credential reference.
          final portable = Map<String, Object?>.from(value)
            ..remove('credentialId');
          return AiProviderProfile.fromJson(portable);
        }).toList(growable: false);
        _ensureUniqueIds(imported);
        final replacedCredentialIds = _profiles
            .map((profile) => profile.credentialId)
            .whereType<String>()
            .toSet();
        _profiles = List.unmodifiable(imported);
        _activeAsrProfileId = null;
        _activeFieldExtractionProfileId = null;
        _enabled = false;
        _useLocalReferenceContext = true;
        notifyListeners();
        await _persist();
        for (final credentialId in replacedCredentialIds) {
          if (!_profiles.any((item) => item.credentialId == credentialId)) {
            await _credentialStore.delete(credentialId);
          }
        }
      });

  Future<void> reset() => _mutate(() async {
        await initialized;
        final credentialIds = _profiles
            .map((profile) => profile.credentialId)
            .whereType<String>()
            .toSet();
        _profiles = const [];
        _activeAsrProfileId = null;
        _activeFieldExtractionProfileId = null;
        _enabled = false;
        _loadError = null;
        notifyListeners();
        await _removePersistedSettings();
        for (final credentialId in credentialIds) {
          await _credentialStore.delete(credentialId);
        }
      });

  Future<void> _persist() {
    final encoded = jsonEncode({
      'schemaVersion': schemaVersion,
      'enabled': _enabled,
      'useLocalReferenceContext': _useLocalReferenceContext,
      'activeAsrProfileId': _activeAsrProfileId,
      'activeFieldExtractionProfileId': _activeFieldExtractionProfileId,
      'profiles': _profiles.map((profile) => profile.toJson()).toList(),
    });
    return _enqueuePreferenceOperation((preferences) async {
      final saved = await preferences.setString(_storageKey, encoded);
      if (!saved) throw StateError('Unable to persist AI settings');
    });
  }

  Future<void> _removePersistedSettings() =>
      _enqueuePreferenceOperation((preferences) async {
        final removed = await preferences.remove(_storageKey);
        if (!removed) throw StateError('Unable to remove AI settings');
      });

  Future<void> _enqueuePreferenceOperation(
    Future<void> Function(SharedPreferences preferences) operation,
  ) {
    final result = Completer<void>();
    _saveTail = _saveTail.then((_) async {
      try {
        final preferences = await _preferencesLoader();
        await operation(preferences);
        result.complete();
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  Future<void> _mutate(Future<void> Function() mutation) {
    final result = Completer<void>();
    _mutationTail = _mutationTail.then((_) async {
      try {
        await mutation();
        result.complete();
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  AiProviderProfile? _profileById(String? id) {
    if (id == null) return null;
    for (final profile in _profiles) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  String? _validActiveId(Object? value, AiProviderKind kind) {
    if (value == null) return null;
    if (value is! String) {
      throw const FormatException('Active AI profile ID must be a string');
    }
    return _profileExistsWithKind(value, kind) ? value : null;
  }

  bool _profileExistsWithKind(
    String? id,
    AiProviderKind kind, {
    List<AiProviderProfile>? profiles,
  }) =>
      id != null &&
      (profiles ?? _profiles)
          .any((profile) => profile.id == id && profile.kind == kind);

  static bool _credentialBindingChanged(
    AiProviderProfile previous,
    AiProviderProfile next,
  ) =>
      previous.baseUrl.origin != next.baseUrl.origin ||
      previous.protocol != next.protocol ||
      _credentialTransportChanged(previous, next);

  static bool _credentialTransportChanged(
    AiProviderProfile previous,
    AiProviderProfile next,
  ) =>
      previous.credentialTransport.location !=
          next.credentialTransport.location ||
      previous.credentialTransport.name != next.credentialTransport.name ||
      previous.credentialTransport.prefix != next.credentialTransport.prefix;

  /// A credential may be shared by ASR and extraction profiles for one API,
  /// but an opaque ID must never silently authorize a second origin or a
  /// different credential destination.
  void _ensureSharedCredentialDestination(AiProviderProfile profile) {
    final credentialId = profile.credentialId;
    if (credentialId == null) return;
    for (final existing in _profiles) {
      if (existing.id == profile.id || existing.credentialId != credentialId) {
        continue;
      }
      if (existing.baseUrl.origin != profile.baseUrl.origin ||
          _credentialTransportChanged(existing, profile)) {
        throw StateError('AI_CREDENTIAL_REBIND_REQUIRED');
      }
    }
  }

  void _requireKind(String? id, AiProviderKind kind) {
    if (id == null) return;
    if (!_profileExistsWithKind(id, kind)) {
      throw StateError('AI_PROFILE_KIND_MISMATCH');
    }
  }

  static void _ensureUniqueIds(List<AiProviderProfile> profiles) {
    final ids = <String>{};
    for (final profile in profiles) {
      if (!ids.add(profile.id)) {
        throw FormatException('Duplicate AI profile ID: ${profile.id}');
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
