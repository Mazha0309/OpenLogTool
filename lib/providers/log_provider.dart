import 'package:flutter/material.dart';
import 'dart:async';
import 'package:openlogtool/models/log_entry.dart' as old;
import 'package:openlogtool/src/bridge/rust_api.dart';
import 'package:openlogtool/src/bridge/models/log_entry.dart' as bridge;

class LogProvider with ChangeNotifier {
  static const int _maxUndoStack = 50;

  bool _disposed = false;
  List<old.LogEntry> _logs = [];
  final List<old.LogEntry> _undoStack = [];
  Future<void> Function()? _onDataChanged;
  Future<void> Function(old.LogEntry log, bool isDelete)? _onLogChanged;
  String? _currentSessionId;
  int _loadGeneration = 0;
  final Set<String> _collaborationReadOnlySessions = <String>{};

  List<old.LogEntry> get logs => _logs;
  int get logCount => _logs.length;
  bool get canUndo => _undoStack.isNotEmpty;
  bool get currentSessionReadOnly =>
      _currentSessionId != null &&
      _collaborationReadOnlySessions.contains(_currentSessionId);

  void setCollaborationReadOnly(String sessionId, bool readOnly) {
    final changed = readOnly
        ? _collaborationReadOnlySessions.add(sessionId)
        : _collaborationReadOnlySessions.remove(sessionId);
    if (changed) _safeNotify();
  }

  void _ensureWritable(String? sessionId) {
    if (sessionId != null &&
        _collaborationReadOnlySessions.contains(sessionId)) {
      throw StateError(
        'COLLABORATION_SESSION_READ_ONLY: 当前角色、会话状态或同步状态不允许写入',
      );
    }
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
    _currentSessionId = sessionId;
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
      if (dt != null) return dt;
    }
    return null;
  }

  LogProvider() {
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
        final batch = await RustApi.getLogs(
          sessionId: sid,
          page: page,
          pageSize: pageSize,
        );
        if (generation != _loadGeneration || _currentSessionId != sid) return;
        bridgeLogs.addAll(batch);
        if (batch.length < pageSize) break;
      }
      if (generation != _loadGeneration || _currentSessionId != sid) return;
      _logs = bridgeLogs.map(_toOldLog).toList();
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
    _ensureWritable(original.sessionId ?? _currentSessionId);
    final syncId = original.id;
    if (syncId.isEmpty) return;
    try {
      await RustApi.updateLog(
        syncId: syncId,
        controller: log.controller,
        callsign: log.callsign,
        time: log.time,
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
    _ensureWritable(log.sessionId ?? _currentSessionId);
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
    _ensureWritable(_currentSessionId);
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

  Future<List<Map<String, dynamic>>> getHistory() async {
    try {
      final sessions = await RustApi.listSessions();
      return sessions
          .where((s) => s.deletedAt == null)
          .map((s) => {
                'session_id': s.sessionId,
                'title': s.title,
                'status': s.status,
                'created_at': s.createdAt,
              })
          .toList();
    } catch (e, st) {
      debugPrint('[LogProvider] getHistory failed: $e\n$st');
      return [];
    }
  }

  Future<void> switchToSession(String sessionId) async {
    _currentSessionId = sessionId;
    await _loadLogs();
  }

  Future<void> hardDeleteSession(String sessionId) async {
    _ensureWritable(sessionId);
    try {
      await RustApi.closeSession(sessionId: sessionId);
      if (_currentSessionId == sessionId) {
        _currentSessionId = null;
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

  old.LogEntry _toOldLog(bridge.LogEntry b) {
    final entry = old.LogEntry(
      id: b.syncId,
      sessionId: b.sessionId,
      time: b.time,
      controller: b.controller,
      callsign: b.callsign,
      report: b.rstSent ?? '',
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
    entry.rstRcvd = b.rstRcvd ?? '';
    return entry;
  }
}
