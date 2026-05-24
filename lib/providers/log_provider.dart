import 'package:flutter/material.dart';
import 'dart:async';
import 'package:openlogtool/models/log_entry.dart';
import 'package:openlogtool/database/database_helper.dart';

class LogProvider with ChangeNotifier {
  static const int _maxUndoStack = 50;

  bool _disposed = false;
  List<LogEntry> _logs = [];
  final List<LogEntry> _undoStack = [];
  Future<void> Function()? _onDataChanged;
  Future<void> Function(LogEntry log, bool isDelete)? _onLogChanged;
  String? _currentSessionId;

  List<LogEntry> get logs => _logs;
  int get logCount => _logs.length;
  bool get canUndo => _undoStack.isNotEmpty;

  void setOnDataChanged(Future<void> Function()? callback) {
    _onDataChanged = callback;
  }

  void setOnLogChanged(Future<void> Function(LogEntry log, bool isDelete)? callback) {
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

  int get todayLogCount {
    return _logs.length;
  }

  int get last7DaysCount {
    return _logs.length ~/ 2;
  }

  LogProvider() {
    // Defer first load to next microtask so Provider tree is constructed
    // before any notifyListeners fires.
    scheduleMicrotask(_loadLogs);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _loadLogs() async {
    try {
      final db = DatabaseHelper();
      _logs = await db.getVisibleLogs(_currentSessionId);
    } catch (e, st) {
      debugPrint('[LogProvider] _loadLogs failed: $e\n$st');
      _logs = [];
    }
    _safeNotify();
  }

  Future<void> addLog(LogEntry log, {String? sessionId}) async {
    final effectiveSessionId = sessionId ?? _currentSessionId;
    final effectiveLog = effectiveSessionId != null && effectiveSessionId != log.sessionId
        ? log.copyWith(sessionId: effectiveSessionId)
        : log;
    try {
      final db = DatabaseHelper();
      final localId = await db.insertLog(effectiveLog);
      final persistedLog = await db.getLogByLocalId(localId);
      _logs.add(persistedLog ?? effectiveLog);
      _safeNotify();
      await _notifyDataChanged();
      if (_onLogChanged != null) {
        await _onLogChanged!(effectiveLog, false);
      }
    } catch (e, st) {
      debugPrint('[LogProvider] addLog failed: $e\n$st');
      rethrow;
    }
  }

  Future<void> updateLog(int index, LogEntry log) async {
    if (index < 0 || index >= _logs.length) return;
    final db = DatabaseHelper();
    final original = _logs[index];
    final localId = original.localId;
    if (localId == null) return;

    // Preserve identity fields from the original record so editing
    // never produces a new sync_id, drops the session link, or
    // resets created_at.
    final merged = original.copyWith(
      time: log.time,
      controller: log.controller,
      callsign: log.callsign,
      report: log.report,
      qth: log.qth,
      device: log.device,
      power: log.power,
      antenna: log.antenna,
      height: log.height,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );

    try {
      await db.updateLog(localId, merged);
      final persistedLog = await db.getLogByLocalId(localId);
      _logs[index] = persistedLog ?? merged;
      _safeNotify();
      await _notifyDataChanged();
      if (_onLogChanged != null) {
        await _onLogChanged!(_logs[index], false);
      }
    } catch (e, st) {
      debugPrint('[LogProvider] updateLog failed: $e\n$st');
      rethrow;
    }
  }

  Future<void> deleteLog(int index) async {
    if (index < 0 || index >= _logs.length) return;
    final log = _logs[index];
    final localId = log.localId;
    if (localId == null) return;
    try {
      final db = DatabaseHelper();
      await db.softDeleteLog(log.id, DateTime.now().toUtc().toIso8601String());
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
    final localId = log.localId;
    if (localId == null) {
      _safeNotify();
      return;
    }
    try {
      final db = DatabaseHelper();
      // Restore the soft-deleted row by re-inserting via the same sync_id.
      // insertLog already handles the upsert-and-clear-deleted_at path.
      final restoredLocalId = await db.insertLog(
        log.copyWith(updatedAt: DateTime.now().toUtc().toIso8601String()),
      );
      final restored = await db.getLogByLocalId(restoredLocalId);
      final effective = restored ?? log;
      // Reload from DB to pick the right ordering rather than guessing.
      await _loadLogs();
      if (_onLogChanged != null) {
        await _onLogChanged!(effective, false);
      }
      await _notifyDataChanged();
    } catch (e, st) {
      debugPrint('[LogProvider] undoLastLog failed: $e\n$st');
      _undoStack.add(log); // restore to stack so user can retry
      _safeNotify();
      rethrow;
    }
  }

  void _pushUndo(LogEntry log) {
    _undoStack.add(log);
    if (_undoStack.length > _maxUndoStack) {
      _undoStack.removeAt(0);
    }
  }

  Future<void> clearAllLogs() async {
    if (_logs.isEmpty) return;
    final db = DatabaseHelper();
    final deletedAt = DateTime.now().toUtc().toIso8601String();
    final snapshot = List<LogEntry>.from(_logs);
    try {
      for (final log in snapshot) {
        await db.softDeleteLog(log.id, deletedAt);
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
    final db = DatabaseHelper();
    return await db.getClosedSessions();
  }

  Future<void> switchToSession(String sessionId) async {
    _currentSessionId = sessionId;
    await _loadLogs();
  }

  Future<void> hardDeleteSession(String sessionId) async {
    final db = DatabaseHelper();
    await db.hardDeleteSession(sessionId);
  }

  Future<int> purgeDeletedRecords() async {
    final db = DatabaseHelper();
    return db.purgeDeletedRecords();
  }


  Future<void> importLogs(List<LogEntry> importedLogs, {String? sessionId}) async {
    final db = DatabaseHelper();
    final effectiveSessionId = sessionId ?? _currentSessionId;
    try {
      for (final log in importedLogs) {
        final effectiveLog = effectiveSessionId != null
            ? log.copyWith(sessionId: effectiveSessionId)
            : log;
        final localId = await db.insertLog(effectiveLog);
        final persistedLog = await db.getLogByLocalId(localId);
        _logs.add(persistedLog ?? effectiveLog);
      }
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
}
