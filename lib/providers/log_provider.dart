import 'package:flutter/material.dart';
import 'dart:async';
import 'package:openlogtool/models/log_entry.dart';
import 'package:openlogtool/database/database_helper.dart';

class LogProvider with ChangeNotifier {
  List<LogEntry> _logs = [];
  List<LogEntry> _undoStack = [];
  bool _isInitialized = false;
  Future<void> Function()? _onLogAdded;

  List<LogEntry> get logs => _logs;
  int get logCount => _logs.length;
  bool get canUndo => _logs.isNotEmpty;

  void setOnLogAdded(Future<void> Function()? callback) {
    _onLogAdded = callback;
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
    _logs = await db.getAllLogs();
    _isInitialized = true;
    notifyListeners();
  }

  Future<void> addLog(LogEntry log) async {
    final db = DatabaseHelper();
    await db.insertLog(log);
    _logs.add(log);
    notifyListeners();
    if (_onLogAdded != null) {
      unawaited(_onLogAdded!());
    }
  }

  Future<void> updateLog(int index, LogEntry log) async {
    if (index >= 0 && index < _logs.length) {
      final db = DatabaseHelper();
      await db.updateLog(index, log);
      _logs[index] = log;
      notifyListeners();
    }
  }

  Future<void> deleteLog(int index) async {
    if (index >= 0 && index < _logs.length) {
      final db = DatabaseHelper();
      await db.deleteLog(index);
      _undoStack.add(_logs[index]);
      _logs.removeAt(index);
      notifyListeners();
    }
  }

  Future<void> undoLastLog() async {
    if (_logs.isNotEmpty) {
      final db = DatabaseHelper();
      await db.deleteLog(_logs.length - 1);
      _undoStack.add(_logs.last);
      _logs.removeLast();
      notifyListeners();
    }
  }

  Future<void> clearAllLogs() async {
    if (_logs.isEmpty) return;
    _undoStack = List.from(_logs);
    final db = DatabaseHelper();
    final now = DateTime.now();
    final historyName = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} (${_logs.length}条记录)';
    await db.insertHistory(historyName, _logs);
    await db.deleteAllLogs();
    _logs.clear();
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> getHistory() async {
    final db = DatabaseHelper();
    return await db.getAllHistory();
  }

  Future<void> restoreFromHistory(int historyId) async {
    final db = DatabaseHelper();
    final historyLogs = await db.getHistoryLogs(historyId);
    await db.deleteAllLogs();
    _logs.clear();
    for (final log in historyLogs) {
      await db.insertLog(log);
      _logs.add(log);
    }
    notifyListeners();
  }

  Future<void> deleteHistoryRecord(int historyId) async {
    final db = DatabaseHelper();
    await db.deleteHistory(historyId);
    notifyListeners();
  }

  Future<void> importLogs(List<LogEntry> importedLogs) async {
    final db = DatabaseHelper();
    await db.importLogs(importedLogs);
    _logs.addAll(importedLogs);
    notifyListeners();
  }

  List<List<String>> getLogsAsList() {
    return _logs.map((log) => log.toList()).toList();
  }
}
