import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openlogtool/src/bridge/api/sessions.dart' as session_api;
import 'package:openlogtool/src/bridge/rust_api.dart';
import 'package:openlogtool/src/bridge/models/session.dart';

typedef LocalSessionReopener = Future<Session> Function(String sessionId);
typedef LocalSessionStarter = Future<Session> Function(String title);
typedef CollaborationSessionLocalCopier = Future<Session> Function(
  String sessionId,
  String title,
);
typedef CollaborationSessionLocalConverter = Future<Session> Function(
  String sessionId,
);
typedef CollaborationSessionLocalStopper = Future<Session> Function(
  String sessionId,
);
typedef LocalSessionCloser = Future<Session> Function(String sessionId);
typedef LocalSessionDeleter = Future<void> Function(String sessionId);
typedef CurrentSessionIdWriter = Future<bool> Function(String sessionId);
typedef SessionListLoader = Future<List<Session>> Function();
typedef SessionSummaryLoader = Future<List<SessionSummary>> Function();
typedef SessionCollaborationBindingChecker = Future<bool> Function(
  String sessionId,
);

@immutable
class SessionListEntry {
  const SessionListEntry({
    required this.session,
    required this.hasCollaborationBinding,
  });

  final Session session;
  final bool hasCollaborationBinding;
}

class SessionProvider with ChangeNotifier {
  static const _key = 'current_session_id';

  final LocalSessionReopener _localSessionReopener;
  final LocalSessionStarter _localSessionStarter;
  final CollaborationSessionLocalCopier _collaborationSessionLocalCopier;
  final CollaborationSessionLocalConverter _collaborationSessionLocalConverter;
  final CollaborationSessionLocalStopper _collaborationSessionLocalStopper;
  final LocalSessionCloser _localSessionCloser;
  final LocalSessionDeleter _localSessionDeleter;
  final CurrentSessionIdWriter? _currentSessionIdWriter;
  final SessionListLoader _sessionListLoader;
  final SessionSummaryLoader? _sessionSummaryLoader;
  final SessionCollaborationBindingChecker _sessionBindingChecker;
  bool _disposed = false;
  String? _currentSessionId;
  Session? _currentSession;
  Completer<void>? _initCompleter;

  String? get currentSessionId => _currentSessionId;
  Session? get currentSession => _currentSession;

  Future<void> get ready => _initCompleter?.future ?? Future.value();

  SessionProvider({
    LocalSessionStarter? localSessionStarter,
    LocalSessionReopener? localSessionReopener,
    CollaborationSessionLocalCopier? collaborationSessionLocalCopier,
    CollaborationSessionLocalConverter? collaborationSessionLocalConverter,
    CollaborationSessionLocalStopper? collaborationSessionLocalStopper,
    LocalSessionCloser? localSessionCloser,
    LocalSessionDeleter? localSessionDeleter,
    CurrentSessionIdWriter? currentSessionIdWriter,
    SessionListLoader? sessionListLoader,
    SessionSummaryLoader? sessionSummaryLoader,
    SessionCollaborationBindingChecker? sessionBindingChecker,
  })  : _localSessionStarter = localSessionStarter ??
            ((title) => session_api.startLocalSession(title: title)),
        _localSessionReopener = localSessionReopener ??
            ((sessionId) => RustApi.reopenLocalSession(sessionId: sessionId)),
        _collaborationSessionLocalCopier = collaborationSessionLocalCopier ??
            ((sessionId, title) => RustApi.copyCollaborationSessionToLocal(
                  sessionId: sessionId,
                  title: title,
                )),
        _collaborationSessionLocalConverter =
            collaborationSessionLocalConverter ??
                ((sessionId) => RustApi.convertCollaborationSessionToLocal(
                      sessionId: sessionId,
                    )),
        _collaborationSessionLocalStopper = collaborationSessionLocalStopper ??
            ((sessionId) => RustApi.stopCollaborationSessionLocally(
                  sessionId: sessionId,
                )),
        _localSessionCloser = localSessionCloser ??
            ((sessionId) => RustApi.closeSessionLocally(sessionId: sessionId)),
        _localSessionDeleter = localSessionDeleter ??
            ((sessionId) => RustApi.hardDeleteSession(sessionId: sessionId)),
        _currentSessionIdWriter = currentSessionIdWriter,
        _sessionListLoader = sessionListLoader ?? RustApi.listSessions,
        _sessionSummaryLoader = sessionSummaryLoader ??
            (sessionListLoader == null
                ? session_api.listSessionSummaries
                : null),
        _sessionBindingChecker = sessionBindingChecker ??
            ((sessionId) async =>
                await RustApi.getSessionCollaborationBinding(
                  sessionId: sessionId,
                ) !=
                null) {
    final completer = Completer<void>();
    _initCompleter = completer;
    scheduleMicrotask(() async {
      try {
        await _init();
      } catch (e, st) {
        debugPrint('[Session] init failed: $e\n$st');
      } finally {
        if (!completer.isCompleted) completer.complete();
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final storedId = prefs.getString(_key);

    if (storedId != null && storedId.isNotEmpty) {
      try {
        final sessions = await _sessionListLoader();
        final match = sessions
            .where((s) => s.sessionId == storedId && s.deletedAt == null)
            .toList();
        if (match.isNotEmpty) {
          _currentSession = match.first;
          _currentSessionId = match.first.sessionId;
        } else {
          debugPrint(
              '[Session] stored session $storedId no longer exists, clearing');
          await prefs.remove(_key);
        }
      } catch (_) {}
    }

    // Don't auto-create — wait for user to create via dialog
    _safeNotify();
  }

  Future<String> getOrCreateSessionId() async {
    await ready;
    if (_currentSessionId == null) {
      await _ensureActiveSession();
    }
    return _currentSessionId!;
  }

  Future<void> _ensureActiveSession() async {
    try {
      final sessions = await _sessionListLoader();
      final active = sessions
          .where((s) => s.status == 'active' && s.deletedAt == null)
          .toList();
      if (active.isNotEmpty) {
        _currentSession = active.first;
        _currentSessionId = active.first.sessionId;
        await _saveCurrentSessionId();
        _safeNotify();
        return;
      }
    } catch (_) {}
  }

  Future<void> startNewSession(
      {String? title, bool autoGenerated = false}) async {
    try {
      final now = DateTime.now();
      final defaultTitle = autoGenerated
          ? '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} 记录'
          : ((title?.trim().isNotEmpty ?? false) ? title!.trim() : '新记录');

      // Rust closes the previous local-only recorder and inserts the
      // replacement in one transaction. Collaboration replicas stay intact.
      final session = await _localSessionStarter(defaultTitle);
      // The database transaction has already committed, so adopt its
      // canonical result even if preference storage is temporarily broken.
      _currentSession = session;
      _currentSessionId = session.sessionId;
      _safeNotify();
      try {
        await _persistCurrentSessionId(session.sessionId);
      } catch (error, stackTrace) {
        debugPrint(
          '[Session] failed to persist new session selection: '
          '$error\n$stackTrace',
        );
      }
      debugPrint('[Session] new session ready: ${session.sessionId}');
    } catch (e, st) {
      debugPrint('[Session] startNewSession ERROR: $e\n$st');
      rethrow;
    }
  }

  Future<List<Session>> listAvailableSessions() async {
    await ready;
    final sessions = await _sessionListLoader();
    final available = sessions
        .where((session) => session.deletedAt == null)
        .toList(growable: false);
    return [...available]
      ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
  }

  Future<List<SessionListEntry>> listAvailableSessionEntries() async {
    await ready;
    final summaryLoader = _sessionSummaryLoader;
    if (summaryLoader != null) {
      final summaries = await summaryLoader();
      final entries = summaries
          .where((summary) => summary.session.deletedAt == null)
          .map(
            (summary) => SessionListEntry(
              session: summary.session,
              hasCollaborationBinding: summary.hasCollaborationBinding,
            ),
          )
          .toList(growable: false)
        ..sort(
          (left, right) =>
              right.session.createdAt.compareTo(left.session.createdAt),
        );
      return entries;
    }

    // Injection-friendly fallback used by provider tests and embedders that
    // supply an alternate session list source.
    final sessions = await listAvailableSessions();
    return Future.wait(
      sessions.map(
        (session) async => SessionListEntry(
          session: session,
          hasCollaborationBinding:
              await _sessionBindingChecker(session.sessionId),
        ),
      ),
    );
  }

  Future<void> switchToSession(String sessionId) async {
    final sessions = await listAvailableSessions();
    final match = sessions.where((s) => s.sessionId == sessionId).toList();
    if (match.isEmpty) {
      throw StateError('Session not found: $sessionId');
    }

    final nextSession = match.first;
    await _persistCurrentSessionId(nextSession.sessionId);
    _currentSession = nextSession;
    _currentSessionId = nextSession.sessionId;
    _safeNotify();
  }

  /// Reactivates and selects a closed local-only session.
  ///
  /// Rust atomically closes any other active local-only session and returns
  /// the new canonical local row, so this provider cannot keep presenting the
  /// previous session as writable after the operation succeeds.
  Future<void> reopenLocalSession(String sessionId) async {
    final reopened = await _localSessionReopener(sessionId);

    // The database transaction has already committed. Adopt its canonical
    // result before touching preferences so an I/O failure cannot leave the
    // in-memory provider pointing at a session Rust just closed.
    _currentSession = reopened;
    _currentSessionId = reopened.sessionId;
    _safeNotify();
    try {
      await _persistCurrentSessionId(reopened.sessionId);
    } catch (error, stackTrace) {
      // Persistence only controls which session is restored on next launch.
      // The committed database state remains authoritative for this process.
      debugPrint(
        '[Session] failed to persist reopened session selection: '
        '$error\n$stackTrace',
      );
    }
  }

  /// Creates and selects an independent local copy of the current
  /// collaboration session without contacting its server.
  Future<Session> copyCurrentCollaborationSessionToLocal({
    required String title,
  }) async {
    await ready;
    final sourceSessionId = _currentSessionId;
    if (sourceSessionId == null || _currentSession == null) {
      throw StateError('NO_CURRENT_SESSION');
    }
    final normalized = title.trim();
    if (normalized.isEmpty || normalized.runes.length > 200) {
      throw ArgumentError('会话标题长度应为 1–200 个字符');
    }

    final local = await _collaborationSessionLocalCopier(
      sourceSessionId,
      normalized,
    );
    if (local.sessionId == sourceSessionId || local.status != 'active') {
      throw StateError('LOCAL_SESSION_COPY_INVALID');
    }
    if (_currentSessionId != sourceSessionId) {
      debugPrint(
        '[Session] local collaboration copy committed after the user selected '
        'another session; preserving the newer selection',
      );
      return local;
    }

    _currentSession = local;
    _currentSessionId = local.sessionId;
    _safeNotify();
    try {
      await _persistCurrentSessionId(local.sessionId);
    } catch (error, stackTrace) {
      debugPrint(
        '[Session] failed to persist local collaboration copy selection: '
        '$error\n$stackTrace',
      );
    }
    return local;
  }

  /// Replaces the current synchronized replica with one independent local
  /// Session. Rust changes the Session and Log IDs atomically so rejoining the
  /// server Session later cannot collide with the converted local record.
  Future<Session> convertCurrentCollaborationSessionToLocal() async {
    await ready;
    final sourceSessionId = _currentSessionId;
    if (sourceSessionId == null || _currentSession == null) {
      throw StateError('NO_CURRENT_SESSION');
    }

    final local = await _collaborationSessionLocalConverter(sourceSessionId);
    if (local.sessionId == sourceSessionId || local.status != 'active') {
      throw StateError('LOCAL_SESSION_CONVERSION_INVALID');
    }
    if (_currentSessionId != sourceSessionId) {
      debugPrint(
        '[Session] collaboration conversion committed after the user selected '
        'another session; preserving the newer selection',
      );
      return local;
    }

    _currentSession = local;
    _currentSessionId = local.sessionId;
    _safeNotify();
    try {
      await _persistCurrentSessionId(local.sessionId);
    } catch (error, stackTrace) {
      debugPrint(
        '[Session] failed to persist converted local Session selection: '
        '$error\n$stackTrace',
      );
    }
    return local;
  }

  /// Stops synchronization for the current collaboration replica without
  /// contacting its server. Saved rows are retained in a replacement local
  /// session; replica queues and draft-only state are discarded by Rust.
  Future<Session> stopCurrentCollaborationSessionLocally() async {
    await ready;
    final sourceSessionId = _currentSessionId;
    if (sourceSessionId == null || _currentSession == null) {
      throw StateError('NO_CURRENT_SESSION');
    }

    final local = await _collaborationSessionLocalStopper(sourceSessionId);
    if (local.sessionId == sourceSessionId || local.status != 'active') {
      throw StateError('LOCAL_SESSION_CONVERSION_INVALID');
    }
    if (_currentSessionId != sourceSessionId) {
      debugPrint(
        '[Session] local collaboration stop committed after the user selected '
        'another session; preserving the newer selection',
      );
      return local;
    }

    await _adoptCurrentSession(local, operation: 'stopped collaboration');
    return local;
  }

  /// Closes one session only on this device. A collaboration replica may be
  /// replaced by a closed local-only row with a new identifier; the selected
  /// session pointer follows that replacement when necessary.
  Future<Session> closeSessionLocally(String sessionId) async {
    await ready;
    final wasCurrent = _currentSessionId == sessionId;
    final closed = await _localSessionCloser(sessionId);
    if (wasCurrent && _currentSessionId == sessionId) {
      await _adoptCurrentSession(closed, operation: 'closed local session');
    }
    return closed;
  }

  /// Permanently deletes one device-local session or collaboration replica.
  /// This method never contacts the server.
  Future<void> deleteSessionLocally(String sessionId) async {
    await ready;
    await _localSessionDeleter(sessionId);
    if (_currentSessionId != sessionId) return;
    _currentSession = null;
    _currentSessionId = null;
    _safeNotify();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (error, stackTrace) {
      debugPrint(
        '[Session] failed to clear deleted session selection: '
        '$error\n$stackTrace',
      );
    }
  }

  Future<void> _adoptCurrentSession(
    Session session, {
    required String operation,
  }) async {
    _currentSession = session;
    _currentSessionId = session.sessionId;
    _safeNotify();
    try {
      await _persistCurrentSessionId(session.sessionId);
    } catch (error, stackTrace) {
      debugPrint(
        '[Session] failed to persist $operation selection: '
        '$error\n$stackTrace',
      );
    }
  }

  Future<void> reloadCurrentSession() async {
    final sessionId = _currentSessionId;
    if (sessionId == null) return;
    final sessions = await _sessionListLoader();
    final matches = sessions.where((session) => session.sessionId == sessionId);
    if (matches.isEmpty) {
      await handleSessionDeleted(sessionId);
      _safeNotify();
      return;
    }
    _currentSession = matches.first;
    _safeNotify();
  }

  /// Reconciles the selected session after the entire local database has been
  /// cleared or replaced from a backup.
  ///
  /// The previous selection is retained when the imported database contains
  /// it. Otherwise the newest active local row is selected so imported records
  /// become visible immediately; an empty database clears the selection.
  Future<void> reloadAfterDatabaseReplacement() async {
    await ready;
    final previousSessionId = _currentSessionId;
    final sessions = (await _sessionListLoader())
        .where((session) => session.deletedAt == null)
        .toList(growable: false);

    Session? selected;
    for (final session in sessions) {
      if (session.sessionId == previousSessionId) {
        selected = session;
        break;
      }
    }
    if (selected == null) {
      final active = sessions
          .where((session) => session.status == 'active')
          .toList(growable: false)
        ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
      if (active.isNotEmpty) selected = active.first;
    }

    _currentSession = selected;
    _currentSessionId = selected?.sessionId;
    _safeNotify();

    try {
      final prefs = await SharedPreferences.getInstance();
      if (selected == null) {
        await prefs.remove(_key);
      } else {
        await _persistCurrentSessionId(selected.sessionId);
      }
    } catch (error, stackTrace) {
      // The database replacement has already committed. A preference failure
      // must not put the in-memory providers back on stale database rows.
      debugPrint(
        '[Session] failed to persist database replacement selection: '
        '$error\n$stackTrace',
      );
    }
  }

  Future<void> renameCurrentSession(String title) async {
    final normalized = title.trim();
    if (normalized.isEmpty || normalized.length > 200) {
      throw ArgumentError('会话标题长度应为 1–200 个字符');
    }
    final sessionId = _currentSessionId;
    final session = _currentSession;
    if (sessionId == null || session == null) {
      throw StateError('NO_CURRENT_SESSION');
    }
    if (session.status != 'active') {
      throw StateError('SESSION_CLOSED');
    }
    if (normalized == session.title) return;

    await RustApi.updateCollaborationSessionTitle(
      sessionId: sessionId,
      title: normalized,
    );
    if (_currentSessionId == sessionId) {
      await reloadCurrentSession();
    }
  }

  Future<void> handleSessionDeleted(String sessionId) async {
    if (_currentSessionId == sessionId) {
      _currentSession = null;
      _currentSessionId = null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    }
  }

  Future<void> _saveCurrentSessionId() async {
    if (_currentSessionId != null) {
      await _persistCurrentSessionId(_currentSessionId!);
    }
  }

  Future<void> _persistCurrentSessionId(String sessionId) async {
    final writer = _currentSessionIdWriter;
    final saved = writer != null
        ? await writer(sessionId)
        : await (await SharedPreferences.getInstance()).setString(
            _key,
            sessionId,
          );
    if (!saved) {
      throw StateError('Failed to persist current session: $sessionId');
    }
  }
}
