import 'package:flutter/material.dart';
import 'dart:async';
import 'package:openlogtool/models/log_entry.dart';
import 'package:openlogtool/database/database_helper.dart';

class LogProvider with ChangeNotifier {
  List<LogEntry> _logs = [];
  List<LogEntry> _undoStack = [];
  Future<void> Function()? _onDataChanged;

  List<LogEntry> get logs => _logs;
  int get logCount => _logs.length;
  bool get canUndo => _logs.isNotEmpty;

  void setOnDataChanged(Future<void> Function()? callback) {
    _onDataChanged = callback;
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
    _logs = await db.getVisibleLogs();
    notifyListeners();
  }

  Future<void> addLog(LogEntry log) async {
    final db = DatabaseHelper();
    final localId = await db.insertLog(log);
    final persistedLog = await db.getLogByLocalId(localId);
    _logs.add(persistedLog ?? log);
    notifyListeners();
    await _notifyDataChanged();
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
    final db = DatabaseHelper();
    final now = DateTime.now();
    final historyName = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} (${_logs.length}条记录)';
    await db.insertHistory(historyName, _logs);
    final deletedAt = now.toUtc().toIso8601String();
    for (final log in _logs) {
      await db.softDeleteLog(log.id, deletedAt);
    }
    _logs.clear();
    notifyListeners();
    await _notifyDataChanged();
  }

  Future<List<Map<String, dynamic>>> getHistory() async {
    final db = DatabaseHelper();
    return await db.getAllHistory();
  }

  Future<void> restoreFromHistory(int historyId) async {
    final db = DatabaseHelper();
    final historyLogs = await db.getHistoryLogs(historyId);
    final deletedAt = DateTime.now().toUtc().toIso8601String();
    for (final log in _logs) {
      await db.softDeleteLog(log.id, deletedAt);
    }
    _logs.clear();
    for (final log in historyLogs) {
      final localId = await db.insertLog(log);
      final persistedLog = await db.getLogByLocalId(localId);
      _logs.add(persistedLog ?? log);
    }
    notifyListeners();
    await _notifyDataChanged();
  }

  Future<void> deleteHistoryRecord(int historyId) async {
    final db = DatabaseHelper();
    await db.deleteHistory(historyId);
    notifyListeners();
    await _notifyDataChanged();
  }

  Future<void> importLogs(List<LogEntry> importedLogs) async {
    final db = DatabaseHelper();
    for (final log in importedLogs) {
      final localId = await db.insertLog(log);
      final persistedLog = await db.getLogByLocalId(localId);
      _logs.add(persistedLog ?? log);
    }
    notifyListeners();
    await _notifyDataChanged();
  }

  List<List<String>> getLogsAsList() {
    return _logs.map((log) => log.toList()).toList();
  }
}
