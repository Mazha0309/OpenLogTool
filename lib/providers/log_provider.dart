import 'package:flutter/material.dart';
import 'dart:async';
import 'package:openlogtool/models/log_entry.dart';
import 'package:openlogtool/database/database_helper.dart';

class LogProvider with ChangeNotifier {
  List<LogEntry> _logs = [];
  List<LogEntry> _undoStack = [];
  Future<void> Function()? _onDataChanged;
  Future<void> Function(LogEntry log, bool isDelete)? _onLogChanged;
  String? _currentSessionId;

  List<LogEntry> get logs => _logs;
  int get logCount => _logs.length;
  bool get canUndo => _logs.isNotEmpty;

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
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    final db = DatabaseHelper();
    _logs = await db.getVisibleLogs(_currentSessionId);
    notifyListeners();
  }

  Future<void> addLog(LogEntry log, {String? sessionId}) async {
    final db = DatabaseHelper();
    final effectiveLog = sessionId != null ? log.copyWith(sessionId: sessionId) : log;
    final localId = await db.insertLog(effectiveLog);
    final persistedLog = await db.getLogByLocalId(localId);
    _logs.add(persistedLog ?? effectiveLog);
    notifyListeners();
    await _notifyDataChanged();
    if (_onLogChanged != null) {
      await _onLogChanged!(effectiveLog, false);
    }
  }

  Future<void> updateLog(int index, LogEntry log) async {
    if (index >= 0 && index < _logs.length) {
      final db = DatabaseHelper();
      final localId = _logs[index].localId;
      if (localId == null) {
        return;
      }
      await db.updateLog(localId, log);
      final persistedLog = await db.getLogByLocalId(localId);
      _logs[index] = persistedLog ?? _logs[index].copyWith(
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
      notifyListeners();
      await _notifyDataChanged();
    }
  }

  Future<void> deleteLog(int index) async {
    if (index >= 0 && index < _logs.length) {
      final db = DatabaseHelper();
      final log = _logs[index];
      final localId = log.localId;
      if (localId == null) {
        return;
      }
      await db.softDeleteLog(log.id, DateTime.now().toUtc().toIso8601String());
      _undoStack.add(log);
      _logs.removeAt(index);
      notifyListeners();
      await _notifyDataChanged();
      if (_onLogChanged != null) {
        await _onLogChanged!(log, true);
      }
    }
  }

  Future<void> undoLastLog() async {
    if (_logs.isNotEmpty) {
      final db = DatabaseHelper();
      final log = _logs.last;
      final localId = log.localId;
      if (localId == null) {
        return;
      }
      await db.softDeleteLog(log.id, DateTime.now().toUtc().toIso8601String());
      _undoStack.add(log);
      _logs.removeLast();
      notifyListeners();
      await _notifyDataChanged();
    }
  }

  Future<void> clearAllLogs() async {
    if (_logs.isEmpty) return;
    _undoStack = List.from(_logs);
    _logs.clear();
    notifyListeners();
    await _notifyDataChanged();
  }

  Future<List<Map<String, dynamic>>> getHistory() async {
    final db = DatabaseHelper();
    return await db.getClosedSessions();
  }

  Future<void> switchToSession(String sessionId) async {
    _currentSessionId = sessionId;
    await _loadLogs();
  }

  Future<void> deleteSession(String sessionId) async {
    final db = DatabaseHelper();
    await db.softDeleteSession(sessionId, DateTime.now().toUtc().toIso8601String());
  }

  Future<void> importLogs(List<LogEntry> importedLogs, {String? sessionId}) async {
    final db = DatabaseHelper();
    for (final log in importedLogs) {
      final effectiveLog = sessionId != null ? log.copyWith(sessionId: sessionId) : log;
      final localId = await db.insertLog(effectiveLog);
      final persistedLog = await db.getLogByLocalId(localId);
      _logs.add(persistedLog ?? effectiveLog);
    }
    notifyListeners();
    await _notifyDataChanged();
  }

  List<List<String>> getLogsAsList() {
    return _logs.map((log) => log.toList()).toList();
  }
}
