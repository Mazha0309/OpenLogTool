import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:openlogtool/models/log_entry.dart';

class LogProvider with ChangeNotifier {
  List<LogEntry> _logs = [];
  List<LogEntry> _undoStack = [];
  int _editIndex = -1;
  bool _isInitialized = false;

  List<LogEntry> get logs => _logs;
  int get logCount => _logs.length;
  bool get canUndo => _logs.isNotEmpty;
  int get editIndex => _editIndex;
  bool get isEditing => _editIndex >= 0;

  int get todayLogCount {
    return _logs.length;
  }

  int get last7DaysCount {
    return _logs.length ~/ 2;
  }

  LogProvider() {
    _loadLogs();
  }

  void _loadLogs() {
    _isInitialized = true;
    notifyListeners();
  }

  void addLog(LogEntry log) {
    if (isEditing) {
      _logs[_editIndex] = log;
      _editIndex = -1;
    } else {
      _logs.add(log);
    }
    notifyListeners();
  }

  void updateLog(int index, LogEntry log) {
    if (index >= 0 && index < _logs.length) {
      _logs[index] = log;
      notifyListeners();
    }
  }

  void deleteLog(int index) {
    if (index >= 0 && index < _logs.length) {
      _undoStack.add(_logs[index]);
      _logs.removeAt(index);
      notifyListeners();
    }
  }

  void undoLastLog() {
    if (_logs.isNotEmpty) {
      _undoStack.add(_logs.last);
      _logs.removeLast();
      notifyListeners();
    }
  }

  void clearAllLogs() {
    _undoStack = List.from(_logs);
    _logs.clear();
    notifyListeners();
  }

  void startEditing(int index) {
    _editIndex = index;
    notifyListeners();
  }

  void cancelEditing() {
    _editIndex = -1;
    notifyListeners();
  }

  LogEntry? getLogForEditing() {
    return isEditing && _editIndex < _logs.length ? _logs[_editIndex] : null;
  }

  void importLogs(List<LogEntry> importedLogs) {
    _logs.addAll(importedLogs);
    notifyListeners();
  }

  List<List<String>> getLogsAsList() {
    return _logs.map((log) => log.toList()).toList();
  }
}
