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

  List<old.LogEntry> get logs => _logs;
  int get logCount => _logs.length;
  bool get canUndo => _undoStack.isNotEmpty;

  void setOnDataChanged(Future<void> Function()? callback) {
    _onDataChanged = callback;
  }

  void setOnLogChanged(Future<void> Function(old.LogEntry log, bool isDelete)? callback) {
    _onLogChanged = callback;
  }

  Future<void> reloadForSession(String? sessionId) async {
    _currentSessionId = sessionId;
    await _loadLogs();
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

  int get todayLogCount => _logs.length;
  int get last7DaysCount => _logs.length ~/ 2;

  LogProvider() {
    scheduleMicrotask(_loadLogs);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _loadLogs() async {
    try {
      final sid = _currentSessionId;
      if (sid == null) {
        _logs = [];
        _safeNotify();
        return;
      }
      final bridgeLogs = await RustApi.getLogs(sessionId: sid, page: 1, pageSize: 500);
      _logs = bridgeLogs.map(_toOldLog).toList();
    } catch (e, st) {
      debugPrint('[LogProvider] _loadLogs failed: $e\n$st');
      _logs = [];
    }
    _safeNotify();
  }

  Future<void> addLog(old.LogEntry log, {String? sessionId}) async {
    final effectiveSessionId = sessionId ?? _currentSessionId ?? '';
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
    final syncId = original.id;
    if (syncId.isEmpty) return;
    try {
      final sid = original.sessionId ?? _currentSessionId ?? '';
      await RustApi.addLog(
        sessionId: sid,
        controller: log.controller,
        callsign: log.callsign,
        rstSent: log.report,
        rstRcvd: log.rstRcvd,
        qth: log.qth,
        device: log.device,
        power: log.power,
        antenna: log.antenna,
        height: log.height,
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
      return sessions.where((s) => s.deletedAt == null).map((s) => {
        'session_id': s.sessionId,
        'title': s.title,
        'status': s.status,
        'created_at': s.createdAt,
      }).toList();
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

  Future<void> importLogs(List<old.LogEntry> importedLogs, {String? sessionId}) async {
    final effectiveSessionId = sessionId ?? _currentSessionId ?? '';
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
      time: b.time.length >= 16 ? b.time.substring(11, 16) : b.time,
      controller: b.controller,
      callsign: b.callsign,
      report: b.rstSent ?? '',
      qth: b.qth ?? '',
      device: b.device ?? '',
      power: b.power ?? '',
      antenna: b.antenna ?? '',
      height: b.height ?? '',
    );
    entry.rstRcvd = b.rstRcvd ?? '';
    return entry;
  }
}
