import 'package:flutter/material.dart';
import 'dart:async';
import 'package:openlogtool/models/log_entry.dart' as old;
import 'package:openlogtool/src/bridge/rust_api.dart';
import 'package:openlogtool/src/bridge/models/log_entry.dart' as bridge;
import 'package:openlogtool/src/bridge/models/session.dart' as session_bridge;
import 'package:openlogtool/utils/log_time.dart';

typedef LogMutationGuard = String? Function(old.LogEntry log);
typedef SessionListLoader = Future<List<session_bridge.Session>> Function();
typedef SessionLogPageLoader = Future<List<bridge.LogEntry>> Function(
  String sessionId,
  int page,
  int pageSize,
);

class LogProvider with ChangeNotifier {
  static const int _maxUndoStack = 50;

  bool _disposed = false;
  // Keep the client-side contract chronological (oldest -> newest). The Rust
  // query returns newest first for efficient paging, while the table reverses
  // this list for display and other consumers use `logs.last` as the latest
  // completed record.
  List<old.LogEntry> _logs = [];
  final List<old.LogEntry> _undoStack = [];
  Future<void> Function()? _onDataChanged;
  Future<void> Function(old.LogEntry log, bool isDelete)? _onLogChanged;
  LogMutationGuard? _logMutationGuard;
  final SessionListLoader _sessionListLoader;
  final SessionLogPageLoader _sessionLogPageLoader;
  String? _currentSessionId;
  bool _currentSessionWritable = false;
  int _sessionStateGeneration = 0;
  int _loadGeneration = 0;
  final Set<String> _collaborationReadOnlySessions = <String>{};

  List<old.LogEntry> get logs => _logs;
  int get logCount => _logs.length;
  bool get canUndo =>
      _undoStack.isNotEmpty &&
      !currentSessionReadOnly &&
      mutationBlockReason(_undoStack.last) == null;
  bool get canClearAllLogs =>
      _logs.isNotEmpty &&
      !currentSessionReadOnly &&
      _logs.every((log) => mutationBlockReason(log) == null);
  bool get currentSessionReadOnly =>
      _currentSessionId != null &&
      (!_currentSessionWritable ||
          _collaborationReadOnlySessions.contains(_currentSessionId));

  void setCollaborationReadOnly(String sessionId, bool readOnly) {
    final changed = readOnly
        ? _collaborationReadOnlySessions.add(sessionId)
        : _collaborationReadOnlySessions.remove(sessionId);
    if (changed) _safeNotify();
  }

  void setLogMutationGuard(LogMutationGuard? guard) {
    if (identical(_logMutationGuard, guard)) return;
    _logMutationGuard = guard;
  }

  void refreshMutationPermissions() => _safeNotify();

  String? mutationBlockReason(old.LogEntry log) {
    final sessionId = log.sessionId ?? _currentSessionId;
    if (sessionId != null &&
        _collaborationReadOnlySessions.contains(sessionId)) {
      return 'COLLABORATION_SESSION_READ_ONLY';
    }
    return _logMutationGuard?.call(log);
  }

  bool canMutateLog(old.LogEntry log) => mutationBlockReason(log) == null;

  void _ensureWritable(String? sessionId) {
    if (sessionId != null &&
        sessionId == _currentSessionId &&
        !_currentSessionWritable) {
      throw StateError('SESSION_CLOSED: 已关闭的会话只能查看');
    }
    if (sessionId != null &&
        _collaborationReadOnlySessions.contains(sessionId)) {
      throw StateError(
        'COLLABORATION_SESSION_READ_ONLY: 当前角色、会话状态或同步状态不允许写入',
      );
    }
  }

  void _ensureLogWritable(old.LogEntry log) {
    _ensureWritable(log.sessionId ?? _currentSessionId);
    final reason = _logMutationGuard?.call(log);
    if (reason != null) throw StateError(reason);
  }

  void setOnDataChanged(Future<void> Function()? callback) {
    _onDataChanged = callback;
  }

  void setOnLogChanged(
      Future<void> Function(old.LogEntry log, bool isDelete)? callback) {
    _onLogChanged = callback;
  }

  Future<void> reloadForSession(
    String? sessionId, {
    bool propagateErrors = false,
  }) async {
    final stateGeneration = ++_sessionStateGeneration;
    _currentSessionId = sessionId;
    _currentSessionWritable = false;
    if (sessionId != null) {
      try {
        final sessions = await _sessionListLoader();
        if (stateGeneration != _sessionStateGeneration ||
            _currentSessionId != sessionId) {
          return;
        }
        _currentSessionWritable = sessions.any(
          (session) =>
              session.sessionId == sessionId &&
              session.status == 'active' &&
              session.deletedAt == null,
        );
      } catch (error, stackTrace) {
        debugPrint(
          '[LogProvider] session state load failed: $error\n$stackTrace',
        );
        if (stateGeneration != _sessionStateGeneration ||
            _currentSessionId != sessionId) {
          return;
        }
        _safeNotify();
        if (propagateErrors) rethrow;
      }
    }
    await _loadLogs(propagateErrors: propagateErrors);
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  Future<void> _notifyDataChanged() async {
    if (_onDataChanged != null) {
      unawaited(_onDataChanged!());
    }
  }

  int get todayLogCount {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _logs.where((log) {
      final dt = _parseLogTimestamp(log);
      if (dt == null) return false;
      return dt.year == today.year &&
          dt.month == today.month &&
          dt.day == today.day;
    }).length;
  }

  int get last7DaysCount {
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));
    return _logs.where((log) {
      final dt = _parseLogTimestamp(log);
      if (dt == null) return false;
      return dt.isAfter(weekAgo) || dt.isAtSameMomentAs(weekAgo);
    }).length;
  }

  DateTime? _parseLogTimestamp(old.LogEntry log) {
    // Prefer creation timestamp; fall back to QSO time if it is a full ISO/RFC3339 string.
    final candidates = [log.createdAt, log.time];
    for (final value in candidates) {
      if (value.isEmpty) continue;
      final dt = DateTime.tryParse(value);
      if (dt != null) return dt.toLocal();
    }
    return null;
  }

  LogProvider({
    SessionListLoader? sessionListLoader,
    SessionLogPageLoader? sessionLogPageLoader,
  })  : _sessionListLoader = sessionListLoader ?? RustApi.listSessions,
        _sessionLogPageLoader = sessionLogPageLoader ??
            ((sessionId, page, pageSize) => RustApi.getLogs(
                  sessionId: sessionId,
                  page: page,
                  pageSize: pageSize,
                )) {
    scheduleMicrotask(_loadLogs);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _loadLogs({bool propagateErrors = false}) async {
    final generation = ++_loadGeneration;
    final sid = _currentSessionId;
    try {
      if (sid == null) {
        if (generation != _loadGeneration || _currentSessionId != sid) return;
        _logs = [];
        _safeNotify();
        return;
      }
      const pageSize = 500;
      final bridgeLogs = <bridge.LogEntry>[];
      for (var page = 1;; page += 1) {
        final batch = await _sessionLogPageLoader(sid, page, pageSize);
        if (generation != _loadGeneration || _currentSessionId != sid) return;
        bridgeLogs.addAll(batch);
        if (batch.length < pageSize) break;
      }
      if (generation != _loadGeneration || _currentSessionId != sid) return;
      _logs = normalizeLoadedLogs(bridgeLogs);
    } catch (e, st) {
      debugPrint('[LogProvider] _loadLogs failed: $e\n$st');
      if (generation != _loadGeneration || _currentSessionId != sid) return;
      _logs = [];
      if (propagateErrors) {
        _safeNotify();
        rethrow;
      }
    }
    _safeNotify();
  }

  Future<void> addLog(old.LogEntry log, {String? sessionId}) async {
    final effectiveSessionId = sessionId ?? _currentSessionId ?? '';
    _ensureWritable(effectiveSessionId);
    try {
      await RustApi.addLog(
        sessionId: effectiveSessionId,
        controller: log.controller,
        callsign: log.callsign,
        time: normalizeLogTimeForStorage(
          log.time,
          reference: DateTime.tryParse(log.createdAt),
        ),
        rstSent: log.report,
        rstRcvd: log.rstRcvd,
        qth: log.qth,
        device: log.device,
        power: log.power,
        antenna: log.antenna,
        height: log.height,
        remarks: log.remarks.isNotEmpty ? log.remarks : null,
      );
      await _loadLogs();
      _safeNotify();
      await _notifyDataChanged();
      if (_onLogChanged != null) {
        await _onLogChanged!(log, false);
      }
    } catch (e, st) {
      debugPrint('[LogProvider] addLog failed: $e\n$st');
      rethrow;
    }
  }

  Future<void> updateLog(int index, old.LogEntry log) async {
    if (index < 0 || index >= _logs.length) return;
    final original = _logs[index];
    _ensureLogWritable(original);
    final syncId = original.id;
    if (syncId.isEmpty) return;
    try {
      await RustApi.updateLog(
        syncId: syncId,
        controller: log.controller,
        callsign: log.callsign,
        time: normalizeLogTimeForStorage(
          log.time,
          reference: DateTime.tryParse(original.time) ??
              DateTime.tryParse(original.createdAt),
        ),
        rstSent: log.report,
        rstRcvd: log.rstRcvd,
        qth: log.qth,
        device: log.device,
        power: log.power,
        antenna: log.antenna,
        height: log.height,
        remarks: log.remarks.isNotEmpty ? log.remarks : null,
      );
      await _loadLogs();
      _safeNotify();
      await _notifyDataChanged();
    } catch (e, st) {
      debugPrint('[LogProvider] updateLog failed: $e\n$st');
      rethrow;
    }
  }

  Future<void> deleteLog(int index) async {
    if (index < 0 || index >= _logs.length) return;
    final log = _logs[index];
    _ensureLogWritable(log);
    final syncId = log.id;
    if (syncId.isEmpty) return;
    try {
      await RustApi.deleteLog(syncId: syncId);
      _pushUndo(log);
      _logs.removeAt(index);
      _safeNotify();
      await _notifyDataChanged();
      if (_onLogChanged != null) {
        await _onLogChanged!(log, true);
      }
    } catch (e, st) {
      debugPrint('[LogProvider] deleteLog failed: $e\n$st');
      rethrow;
    }
  }

  Future<void> undoLastLog() async {
    if (_undoStack.isEmpty) return;
    final pendingRestore = _undoStack.last;
    _ensureLogWritable(pendingRestore);
    final log = _undoStack.removeLast();
    final sessionId = _currentSessionId;
    if (sessionId == null) {
      _safeNotify();
      return;
    }
    try {
      await RustApi.undoLastLog(sessionId: sessionId);
      await _loadLogs();
      if (_onLogChanged != null) {
        await _onLogChanged!(log, false);
      }
      await _notifyDataChanged();
    } catch (e, st) {
      debugPrint('[LogProvider] undoLastLog failed: $e\n$st');
      _undoStack.add(log);
      _safeNotify();
    }
  }

  void _pushUndo(old.LogEntry log) {
    _undoStack.add(log);
    if (_undoStack.length > _maxUndoStack) {
      _undoStack.removeAt(0);
    }
  }

  Future<void> clearAllLogs() async {
    if (_logs.isEmpty) return;
    _ensureWritable(_currentSessionId);
    final snapshot = List<old.LogEntry>.from(_logs);
    for (final log in snapshot) {
      _ensureLogWritable(log);
    }
    try {
      for (final log in snapshot) {
        if (log.id.isNotEmpty) {
          await RustApi.deleteLog(syncId: log.id);
        }
      }
      for (final log in snapshot) {
        _pushUndo(log);
      }
      _logs.clear();
      _safeNotify();
      await _notifyDataChanged();
    } catch (e, st) {
      debugPrint('[LogProvider] clearAllLogs failed: $e\n$st');
      await _loadLogs();
      rethrow;
    }
  }

  Future<void> switchToSession(String sessionId) async {
    await reloadForSession(sessionId);
  }

  Future<void> hardDeleteSession(String sessionId) async {
    _ensureWritable(sessionId);
    try {
      await RustApi.closeSession(sessionId: sessionId);
      if (_currentSessionId == sessionId) {
        _currentSessionId = null;
        _currentSessionWritable = false;
        _sessionStateGeneration += 1;
        _logs = [];
        _safeNotify();
      }
    } catch (e, st) {
      debugPrint('[LogProvider] hardDeleteSession failed: $e\n$st');
      rethrow;
    }
  }

  Future<int> purgeDeletedRecords() async => 0;

  Future<void> importLogs(List<old.LogEntry> importedLogs,
      {String? sessionId}) async {
    final effectiveSessionId = sessionId ?? _currentSessionId ?? '';
    _ensureWritable(effectiveSessionId);
    try {
      for (final log in importedLogs) {
        await RustApi.addLog(
          sessionId: effectiveSessionId,
          controller: log.controller,
          callsign: log.callsign,
          time: normalizeLogTimeForStorage(
            log.time,
            reference: DateTime.tryParse(log.createdAt),
          ),
          rstSent: log.report,
          rstRcvd: log.rstRcvd,
          qth: log.qth,
          device: log.device,
          power: log.power,
          antenna: log.antenna,
          height: log.height,
          remarks: log.remarks.isNotEmpty ? log.remarks : null,
        );
      }
      await _loadLogs();
      _safeNotify();
      await _notifyDataChanged();
    } catch (e, st) {
      debugPrint('[LogProvider] importLogs failed: $e\n$st');
      await _loadLogs();
      rethrow;
    }
  }

  List<List<String>> getLogsAsList() {
    return _logs.map((log) => log.toList()).toList();
  }

  @visibleForTesting
  static List<old.LogEntry> normalizeLoadedLogs(
    List<bridge.LogEntry> newestFirst,
  ) =>
      newestFirst.reversed.map(_toOldLog).toList();

  static old.LogEntry _toOldLog(bridge.LogEntry b) {
    return old.LogEntry(
      id: b.syncId,
      sessionId: b.sessionId,
      time: b.time,
      controller: b.controller,
      callsign: b.callsign,
      report: b.rstSent ?? '',
      rstRcvd: b.rstRcvd ?? '',
      qth: b.qth ?? '',
      device: b.device ?? '',
      power: b.power ?? '',
      antenna: b.antenna ?? '',
      height: b.height ?? '',
      remarks: b.remarks ?? '',
      createdAt: b.createdAt,
      updatedAt: b.updatedAt,
      deletedAt: b.deletedAt,
      sourceDeviceId: b.sourceDeviceId,
    );
  }
}
