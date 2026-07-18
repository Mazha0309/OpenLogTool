import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:openlogtool/models/personal_cloud_dto.dart';
import 'package:openlogtool/providers/collaboration_provider.dart';
import 'package:openlogtool/providers/log_provider.dart';
import 'package:openlogtool/providers/server_provider.dart';
import 'package:openlogtool/providers/session_provider.dart';
import 'package:openlogtool/services/server_api.dart';
import 'package:openlogtool/src/bridge/rust_api.dart';
import 'package:openlogtool/utils/server_url.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum PersonalCloudSyncState {
  signedOut,
  unsupported,
  checking,
  syncing,
  upToDate,
  decisionRequired,
  error,
}

enum PersonalCloudDecisionReason {
  differentInitialData,
  differentAccountData,
  databaseReplaced,
  localClearWouldDeleteCloud,
  concurrentChanges,
}

typedef PersonalRecordsExporter = Future<String> Function();
typedef PersonalRecordsCompareReplacer = Future<String> Function(
  String jsonData,
  String expectedLocalJsonData,
);

String personalSnapshotContentChecksum(PersonalCloudJsonObject snapshot) {
  final sessions = snapshot['sessions'];
  final logs = snapshot['logs'];
  if (snapshot['version'] != 1 || sessions is! List || logs is! List) {
    throw const FormatException('unsupported personal snapshot format');
  }
  final canonical = _personalCanonicalValue(<String, Object?>{
    'version': 1,
    'sessions': _personalCanonicalRows(sessions, 'session_id'),
    'logs': _personalCanonicalRows(logs, 'sync_id'),
  });
  return sha256.convert(utf8.encode(jsonEncode(canonical))).toString();
}

List<Object?> _personalCanonicalRows(List<Object?> rows, String idField) {
  final normalized = rows.map(_personalCanonicalValue).toList(growable: false);
  normalized.sort((left, right) {
    final leftId = left is Map ? left[idField]?.toString() ?? '' : '';
    final rightId = right is Map ? right[idField]?.toString() ?? '' : '';
    return leftId.compareTo(rightId);
  });
  return normalized;
}

Object? _personalCanonicalValue(Object? value) {
  if (value is Map) {
    final sorted = SplayTreeMap<String, Object?>();
    for (final entry in value.entries) {
      sorted[entry.key.toString()] = _personalCanonicalValue(entry.value);
    }
    return sorted;
  }
  if (value is List) return value.map(_personalCanonicalValue).toList();
  return value;
}

/// Account-scoped synchronization for personal sessions and records.
///
/// Collaboration replicas remain on their existing realtime protocol. This
/// provider synchronizes only sessions without a collaboration binding, using
/// a revisioned complete snapshot so deletes and closed historical sessions
/// retain their exact local metadata across devices.
class PersonalCloudProvider with ChangeNotifier {
  PersonalCloudProvider({
    PersonalRecordsExporter? exporter,
    PersonalRecordsCompareReplacer? replacer,
    bool automaticSync = true,
    Duration automaticChangeDebounce = const Duration(seconds: 10),
    Duration periodicInterval = const Duration(seconds: 30),
  })  : _exporter = exporter ?? RustApi.exportPersonalRecords,
        _replacer = replacer ??
            ((jsonData, expectedLocalJsonData) =>
                RustApi.replacePersonalRecordsIfUnchanged(
                  jsonData: jsonData,
                  expectedLocalJsonData: expectedLocalJsonData,
                )),
        _automaticSync = automaticSync,
        _automaticChangeDebounce = automaticChangeDebounce,
        _periodicInterval = periodicInterval;

  final PersonalRecordsExporter _exporter;
  final PersonalRecordsCompareReplacer _replacer;
  final bool _automaticSync;
  final Duration _automaticChangeDebounce;
  final Duration _periodicInterval;

  ServerProvider? _server;
  SessionProvider? _sessions;
  LogProvider? _logs;
  CollaborationProvider? _collaboration;
  String? _scope;
  bool _supported = false;
  Timer? _debounce;
  Timer? _periodic;
  Future<void>? _activeOperation;
  bool _automaticRerunRequested = false;
  bool _disposed = false;
  bool _suppressDependencySignal = false;
  int? _observedSessionDataRevision;
  int? _observedLogDataRevision;
  int? _observedDatabaseRevision;

  PersonalCloudSyncState _state = PersonalCloudSyncState.signedOut;
  PersonalCloudDecisionReason? _decisionReason;
  PersonalCloudSnapshotMeta? _cloudMeta;
  int _localSessionCount = 0;
  int _localLogCount = 0;
  String? _localSnapshotToken;
  String? _lastError;
  DateTime? _lastSyncedAt;
  _PersonalCloudBaseline? _baseline;
  bool _baselineLoaded = false;
  String? _localOwnerScope;

  PersonalCloudSyncState get state => _state;
  PersonalCloudDecisionReason? get decisionReason => _decisionReason;
  PersonalCloudSnapshotMeta? get cloudMeta => _cloudMeta;
  int get localSessionCount => _localSessionCount;
  int get localLogCount => _localLogCount;
  String? get lastError => _lastError;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  bool get isBusy =>
      _state == PersonalCloudSyncState.checking ||
      _state == PersonalCloudSyncState.syncing;
  bool get isSignedIn => _scope != null;
  bool get isSupported => _supported;
  String? get localSnapshotToken => _localSnapshotToken;

  void updateDependencies(
    ServerProvider server,
    SessionProvider sessions,
    LogProvider logs,
    CollaborationProvider collaboration,
  ) {
    _server = server;
    _sessions = sessions;
    _logs = logs;
    _collaboration = collaboration;
    final accountId = server.accountId;
    final serverInfo = server.serverInfo;
    final canonicalOrigin = normalizeServerUrl(server.serverUrl);
    final nextScope = server.isLoggedIn &&
            !server.passwordChangeRequired &&
            accountId != null &&
            canonicalOrigin.isNotEmpty &&
            serverInfo != null &&
            serverInfo.serverInstanceId.isNotEmpty
        ? '$canonicalOrigin\n${serverInfo.serverInstanceId}\n$accountId'
        : null;
    final nextSupported = nextScope != null &&
        (serverInfo?.features.contains('personalCloudSnapshots') ?? false);

    final sessionDataRevision = sessions.dataRevision;
    final logDataRevision = logs.dataRevision;
    final databaseRevision = sessions.databaseRevision;
    final personalDataChanged = _observedSessionDataRevision != null &&
        (_observedSessionDataRevision != sessionDataRevision ||
            _observedLogDataRevision != logDataRevision ||
            _observedDatabaseRevision != databaseRevision);
    _observedSessionDataRevision = sessionDataRevision;
    _observedLogDataRevision = logDataRevision;
    _observedDatabaseRevision = databaseRevision;

    if (nextScope != _scope || nextSupported != _supported) {
      _scope = nextScope;
      _supported = nextSupported;
      _baseline = null;
      _baselineLoaded = false;
      _localOwnerScope = null;
      _cloudMeta = null;
      _localSnapshotToken = null;
      _decisionReason = null;
      _lastError = null;
      _debounce?.cancel();
      _periodic?.cancel();
      if (nextScope == null) {
        _state = PersonalCloudSyncState.signedOut;
      } else if (!nextSupported) {
        _state = PersonalCloudSyncState.unsupported;
      } else {
        _state = PersonalCloudSyncState.checking;
        if (_automaticSync) {
          _periodic = Timer.periodic(
            _periodicInterval,
            (_) => _scheduleAutomaticSync(Duration.zero),
          );
          _scheduleAutomaticSync(Duration.zero);
        }
      }
      _notifySoon();
      return;
    }

    if (nextScope != null &&
        _supported &&
        _automaticSync &&
        !_suppressDependencySignal &&
        personalDataChanged) {
      _scheduleAutomaticSync(_automaticChangeDebounce);
    }
  }

  Future<void> syncNow() => _runExclusive(
        () => _reconcile(automatic: false),
        automatic: false,
      );

  /// Explicitly replaces the account snapshot with this device's personal
  /// sessions. This is the only path allowed to resolve an initial mismatch in
  /// favor of local data or to clear non-empty cloud content.
  Future<void> replaceCloudWithLocal({
    required int expectedCloudRevision,
    required String expectedLocalSnapshotToken,
  }) =>
      _runExclusive(
        () => _replaceCloudWithLocal(
          expectedCloudRevision: expectedCloudRevision,
          expectedLocalSnapshotToken: expectedLocalSnapshotToken,
        ),
        automatic: false,
      );

  /// Explicitly replaces personal sessions on this device with the current
  /// account snapshot. Dictionaries, settings, QTH history and collaboration
  /// replicas are preserved by the Rust transaction.
  Future<void> restoreCloudToLocal({
    required int expectedCloudRevision,
    required String expectedLocalSnapshotToken,
  }) =>
      _runExclusive(
        () => _restoreCloudToLocal(
          expectedCloudRevision: expectedCloudRevision,
          expectedLocalSnapshotToken: expectedLocalSnapshotToken,
        ),
        automatic: false,
      );

  void _scheduleAutomaticSync(Duration delay) {
    if (_scope == null || !_supported || _disposed) return;
    _debounce?.cancel();
    _debounce = Timer(delay, () {
      _runExclusive(
        () => _reconcile(automatic: true),
        automatic: true,
      ).catchError((Object error, StackTrace stackTrace) {
        debugPrint(
            '[PersonalCloud] automatic sync failed: $error\n$stackTrace');
      });
    });
  }

  Future<void> _runExclusive(
    Future<void> Function() operation, {
    required bool automatic,
  }) async {
    final operationScope = _scope;
    final active = _activeOperation;
    if (active != null) {
      if (automatic) {
        _automaticRerunRequested = true;
        return active;
      }
      await active;
      return _runExclusive(operation, automatic: false);
    }

    late final Future<void> running;
    running = operation();
    _activeOperation = running;
    try {
      await running;
    } catch (error) {
      if (_scope != operationScope || _disposed) rethrow;
      if (_requiresDecision(error)) {
        _decisionReason = PersonalCloudDecisionReason.concurrentChanges;
        _lastError = null;
        _state = PersonalCloudSyncState.decisionRequired;
        _safeNotify();
        rethrow;
      }
      _lastError = error.toString();
      _state = PersonalCloudSyncState.error;
      _safeNotify();
      rethrow;
    } finally {
      if (identical(_activeOperation, running)) _activeOperation = null;
      if (_automaticRerunRequested && !_disposed) {
        _automaticRerunRequested = false;
        _scheduleAutomaticSync(_automaticChangeDebounce);
      }
    }
  }

  static bool _requiresDecision(Object error) =>
      (error is ServerApiException &&
          error.code == 'PERSONAL_SNAPSHOT_REVISION_CONFLICT') ||
      error.toString().contains('PERSONAL_RECORDS_LOCAL_CHANGED') ||
      error.toString().contains('PERSONAL_SNAPSHOT_REVISION_CONFLICT');

  Future<void> _reconcile({required bool automatic}) async {
    final context = _captureContext();
    if (context == null) return;
    _state = PersonalCloudSyncState.checking;
    _lastError = null;
    _safeNotify();

    await context.sessions.ready;
    if (!_isCurrent(context)) return;
    final local = await _readLocalSnapshot();
    final meta = await context.server.api.getPersonalCloudSnapshotMeta();
    if (!_isCurrent(context)) return;
    await _ensureSyncStateLoaded(context.scope);
    if (!_isCurrent(context)) return;
    _adoptVisibleSnapshot(local, meta);

    if (context.sessions.databaseReplacementPending) {
      _requireDecision(PersonalCloudDecisionReason.databaseReplaced);
      return;
    }

    final ownsLocalData = _localOwnerScope == _scopeIdentity(context.scope);
    if (!ownsLocalData) {
      if (!local.hasContent && !meta.exists) {
        await _claimLocalOwnership(context.scope);
        if (!_isCurrent(context)) return;
        await _saveBaseline(
          context.scope,
          _PersonalCloudBaseline(
            revision: 0,
            localChecksum: local.checksum,
            databaseRevision: context.sessions.databaseRevision,
          ),
        );
        if (!_isCurrent(context)) return;
        _markUpToDate();
      } else {
        _requireDecision(PersonalCloudDecisionReason.differentAccountData);
      }
      return;
    }

    final baseline = _baseline;
    if (baseline == null) {
      _requireDecision(PersonalCloudDecisionReason.differentInitialData);
      return;
    }
    if (baseline.databaseRevision != context.sessions.databaseRevision) {
      _requireDecision(PersonalCloudDecisionReason.databaseReplaced);
      return;
    }

    // A PUT may have committed even when its response was lost. Once the
    // database-generation guard has passed, identical content proves that
    // advancing the baseline is non-destructive and avoids a false conflict.
    if (meta.exists && meta.checksum == local.checksum) {
      await _saveBaseline(
        context.scope,
        _PersonalCloudBaseline(
          revision: meta.revision,
          localChecksum: local.checksum,
          databaseRevision: context.sessions.databaseRevision,
        ),
      );
      if (!_isCurrent(context)) return;
      _markUpToDate();
      return;
    }

    if (!meta.exists) {
      if (local.hasContent) {
        await _upload(
          context,
          local,
          expectedRevision: 0,
        );
      } else {
        await _saveBaseline(
          context.scope,
          _PersonalCloudBaseline(
            revision: 0,
            localChecksum: local.checksum,
            databaseRevision: context.sessions.databaseRevision,
          ),
        );
        _markUpToDate();
      }
      return;
    }

    final localChanged = local.checksum != baseline.localChecksum;
    final cloudChanged = meta.revision != baseline.revision;
    if (!localChanged && !cloudChanged) {
      _markUpToDate();
      return;
    }
    if (localChanged && cloudChanged) {
      _requireDecision(PersonalCloudDecisionReason.concurrentChanges);
      return;
    }
    if (localChanged) {
      if (!local.hasContent && meta.sessionCount > 0) {
        _requireDecision(
          PersonalCloudDecisionReason.localClearWouldDeleteCloud,
        );
        return;
      }
      await _upload(
        context,
        local,
        expectedRevision: baseline.revision,
      );
      return;
    }

    await _downloadAndReplace(
      context,
      expectedCloudRevision: meta.revision,
      expectedLocal: local,
    );
  }

  Future<void> _replaceCloudWithLocal({
    required int expectedCloudRevision,
    required String expectedLocalSnapshotToken,
  }) async {
    final context = _captureContext();
    if (context == null) throw StateError('PERSONAL_CLOUD_SIGN_IN_REQUIRED');
    _state = PersonalCloudSyncState.syncing;
    _lastError = null;
    _safeNotify();
    final local = await _readLocalSnapshot();
    if (!_isCurrent(context)) return;
    if (local.checksum != expectedLocalSnapshotToken) {
      throw StateError('PERSONAL_RECORDS_LOCAL_CHANGED');
    }
    await _upload(
      context,
      local,
      expectedRevision: expectedCloudRevision,
      claimOwnership: true,
      acknowledgeReplacement: true,
    );
  }

  Future<void> _restoreCloudToLocal({
    required int expectedCloudRevision,
    required String expectedLocalSnapshotToken,
  }) async {
    final context = _captureContext();
    if (context == null) throw StateError('PERSONAL_CLOUD_SIGN_IN_REQUIRED');
    _state = PersonalCloudSyncState.syncing;
    _lastError = null;
    _safeNotify();
    final local = await _readLocalSnapshot();
    if (!_isCurrent(context)) return;
    if (local.checksum != expectedLocalSnapshotToken) {
      throw StateError('PERSONAL_RECORDS_LOCAL_CHANGED');
    }
    await _downloadAndReplace(
      context,
      expectedCloudRevision: expectedCloudRevision,
      expectedLocal: local,
      claimOwnership: true,
    );
  }

  Future<void> _upload(
    _PersonalCloudContext context,
    _LocalPersonalSnapshot local, {
    required int expectedRevision,
    bool claimOwnership = false,
    bool acknowledgeReplacement = false,
  }) async {
    _state = PersonalCloudSyncState.syncing;
    _safeNotify();
    final result = await context.server.api.replacePersonalCloudSnapshot(
      expectedRevision: expectedRevision,
      snapshot: local.json,
    );
    if (!_isCurrent(context)) return;
    if (claimOwnership) await _claimLocalOwnership(context.scope);
    if (!_isCurrent(context)) return;
    await _saveBaseline(
      context.scope,
      _PersonalCloudBaseline(
        revision: result.meta.revision,
        localChecksum: local.checksum,
        databaseRevision: context.sessions.databaseRevision,
      ),
    );
    if (!_isCurrent(context)) return;
    _cloudMeta = result.meta;
    if (acknowledgeReplacement) {
      await context.sessions.acknowledgeDatabaseReplacement();
      if (!_isCurrent(context)) return;
    }
    _markUpToDate();
  }

  Future<void> _downloadAndReplace(
    _PersonalCloudContext context, {
    required int expectedCloudRevision,
    required _LocalPersonalSnapshot expectedLocal,
    bool claimOwnership = false,
  }) async {
    _state = PersonalCloudSyncState.syncing;
    _safeNotify();
    final download = await context.server.api.downloadPersonalCloudSnapshot();
    if (!_isCurrent(context)) return;
    if (download.meta.revision != expectedCloudRevision) {
      throw StateError('PERSONAL_SNAPSHOT_REVISION_CONFLICT');
    }
    final encoded = jsonEncode(download.snapshot);
    final replacement = _snapshotFromJson(
      download.snapshot,
      rawJson: encoded,
    );
    _validateDownload(download, replacement);
    _suppressDependencySignal = true;
    try {
      await context.collaboration.runLocalDatabaseMaintenance(
        () async {
          if (!_isCurrent(context)) {
            throw StateError('PERSONAL_CLOUD_CONTEXT_CHANGED');
          }
          return _replacer(encoded, expectedLocal.rawJson);
        },
      );
    } finally {
      _suppressDependencySignal = false;
    }
    if (!_isCurrent(context)) return;
    if (claimOwnership) await _claimLocalOwnership(context.scope);
    if (!_isCurrent(context)) return;
    await _saveBaseline(
      context.scope,
      _PersonalCloudBaseline(
        revision: download.meta.revision,
        localChecksum: replacement.checksum,
        databaseRevision: context.sessions.databaseRevision,
      ),
    );
    if (!_isCurrent(context)) return;
    _adoptVisibleSnapshot(replacement, download.meta);
    _markUpToDate();
  }

  void _validateDownload(
    PersonalCloudSnapshotDownload download,
    _LocalPersonalSnapshot replacement,
  ) {
    final meta = download.meta;
    if (!meta.exists ||
        meta.formatVersion != 1 ||
        meta.sessionCount != replacement.sessionCount ||
        meta.logCount != replacement.logCount ||
        meta.checksum != replacement.checksum) {
      throw const FormatException('PERSONAL_SNAPSHOT_INTEGRITY_FAILED');
    }
  }

  void _requireDecision(PersonalCloudDecisionReason reason) {
    _decisionReason = reason;
    _state = PersonalCloudSyncState.decisionRequired;
    _safeNotify();
  }

  void _markUpToDate() {
    _decisionReason = null;
    _state = PersonalCloudSyncState.upToDate;
    _lastSyncedAt = DateTime.now();
    _safeNotify();
  }

  Future<_LocalPersonalSnapshot> _readLocalSnapshot() async {
    final raw = await _exporter();
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('personal snapshot must be a JSON object');
    }
    return _snapshotFromJson(
      Map<String, Object?>.from(decoded),
      rawJson: raw,
    );
  }

  static _LocalPersonalSnapshot _snapshotFromJson(
    Map<String, Object?> snapshot, {
    String? rawJson,
  }) {
    final sessions = snapshot['sessions'];
    final logs = snapshot['logs'];
    if (snapshot['version'] != 1 || sessions is! List || logs is! List) {
      throw const FormatException('unsupported personal snapshot format');
    }
    return _LocalPersonalSnapshot(
      json: Map<String, Object?>.from(snapshot),
      rawJson: rawJson ?? jsonEncode(snapshot),
      checksum: personalSnapshotContentChecksum(snapshot),
      sessionCount: sessions.length,
      logCount: logs.length,
    );
  }

  void _adoptVisibleSnapshot(
    _LocalPersonalSnapshot local,
    PersonalCloudSnapshotMeta meta,
  ) {
    _localSessionCount = local.sessionCount;
    _localLogCount = local.logCount;
    _localSnapshotToken = local.checksum;
    _cloudMeta = meta;
  }

  _PersonalCloudContext? _captureContext() {
    final scope = _scope;
    final server = _server;
    final sessions = _sessions;
    final logs = _logs;
    final collaboration = _collaboration;
    if (scope == null ||
        !_supported ||
        server == null ||
        sessions == null ||
        logs == null ||
        collaboration == null ||
        !server.isLoggedIn) {
      return null;
    }
    return _PersonalCloudContext(
      scope: scope,
      server: server,
      sessions: sessions,
      logs: logs,
      collaboration: collaboration,
    );
  }

  bool _isCurrent(_PersonalCloudContext context) =>
      !_disposed &&
      _supported &&
      _scope == context.scope &&
      identical(_server, context.server) &&
      identical(_sessions, context.sessions) &&
      identical(_logs, context.logs) &&
      context.server.isLoggedIn &&
      !context.server.passwordChangeRequired;

  Future<void> _ensureSyncStateLoaded(String scope) async {
    if (_baselineLoaded) return;
    final prefs = await SharedPreferences.getInstance();
    if (_scope != scope) return;
    final prefix = _preferencePrefix(scope);
    final revision = prefs.getInt('${prefix}revision');
    final checksum = prefs.getString('${prefix}local_checksum');
    final databaseRevision = prefs.getInt('${prefix}database_revision');
    _localOwnerScope = prefs.getString('personal_cloud_v1_local_owner_scope');
    _baseline = revision == null || checksum == null || databaseRevision == null
        ? null
        : _PersonalCloudBaseline(
            revision: revision,
            localChecksum: checksum,
            databaseRevision: databaseRevision,
          );
    _baselineLoaded = true;
  }

  Future<void> _saveBaseline(
    String scope,
    _PersonalCloudBaseline baseline,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    if (_scope != scope) return;
    final prefix = _preferencePrefix(scope);
    final revisionSaved =
        await prefs.setInt('${prefix}revision', baseline.revision);
    final checksumSaved = await prefs.setString(
      '${prefix}local_checksum',
      baseline.localChecksum,
    );
    final databaseRevisionSaved = await prefs.setInt(
      '${prefix}database_revision',
      baseline.databaseRevision,
    );
    if (!revisionSaved || !checksumSaved || !databaseRevisionSaved) {
      throw StateError('PERSONAL_CLOUD_BASELINE_PERSIST_FAILED');
    }
    if (_scope == scope) {
      _baseline = baseline;
      _baselineLoaded = true;
    }
  }

  static String _preferencePrefix(String scope) =>
      'personal_cloud_v1_${sha256.convert(utf8.encode(scope))}_';

  static String _scopeIdentity(String scope) =>
      sha256.convert(utf8.encode(scope)).toString();

  Future<void> _claimLocalOwnership(String scope) async {
    final identity = _scopeIdentity(scope);
    final prefs = await SharedPreferences.getInstance();
    if (_scope != scope) return;
    final saved = await prefs.setString(
      'personal_cloud_v1_local_owner_scope',
      identity,
    );
    if (!saved) {
      throw StateError('PERSONAL_CLOUD_OWNER_PERSIST_FAILED');
    }
    if (_scope == scope) _localOwnerScope = identity;
  }

  void _notifySoon() {
    scheduleMicrotask(_safeNotify);
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _periodic?.cancel();
    super.dispose();
  }
}

@immutable
final class _PersonalCloudBaseline {
  const _PersonalCloudBaseline({
    required this.revision,
    required this.localChecksum,
    required this.databaseRevision,
  });

  final int revision;
  final String localChecksum;
  final int databaseRevision;
}

@immutable
final class _LocalPersonalSnapshot {
  const _LocalPersonalSnapshot({
    required this.json,
    required this.rawJson,
    required this.checksum,
    required this.sessionCount,
    required this.logCount,
  });

  final PersonalCloudJsonObject json;
  final String rawJson;
  final String checksum;
  final int sessionCount;
  final int logCount;

  bool get hasContent => sessionCount > 0 || logCount > 0;
}

@immutable
final class _PersonalCloudContext {
  const _PersonalCloudContext({
    required this.scope,
    required this.server,
    required this.sessions,
    required this.logs,
    required this.collaboration,
  });

  final String scope;
  final ServerProvider server;
  final SessionProvider sessions;
  final LogProvider logs;
  final CollaborationProvider collaboration;
}
