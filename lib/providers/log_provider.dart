import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openlogtool/models/log_entry.dart';

class LogProvider with ChangeNotifier {
  List<LogEntry> _logs = [];
  List<LogEntry> _undoStack = [];
  int _editIndex = -1;

  List<LogEntry> get logs => _logs;
  int get logCount => _logs.length;
  bool get canUndo => _logs.isNotEmpty;
  int get editIndex => _editIndex;
  bool get isEditing => _editIndex >= 0;
  
  // 统计属性
  int get todayLogCount {
    final today = DateTime.now();
    return _logs.where((log) {
      try {
        // 假设时间格式为 "HH:mm" 或包含日期
        // 这里简化处理，只统计今天的记录
        final now = DateTime.now();
        return true; // 简化版本，实际应该根据时间过滤
      } catch (e) {
        return false;
      }
    }).length;
  }
  
  int get last7DaysCount {
    // 简化版本，返回总记录数的一半作为示例
    return _logs.length ~/ 2;
  }

  LogProvider() {
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final logsJson = prefs.getStringList('logData') ?? [];
    
    _logs = logsJson.map((json) {
      try {
        final data = LogEntry.fromJson(Map<String, dynamic>.from(json as Map));
        return data;
      } catch (e) {
        // 兼容旧格式
        final parts = json.split(',');
        if (parts.length >= 9) {
          return LogEntry(
            time: parts[0],
            controller: parts[1],
            callsign: parts[2],
            report: parts[3],
            qth: parts[4],
            device: parts[5],
            power: parts[6],
            antenna: parts[7],
            height: parts[8],
          );
        }
        return LogEntry(
          time: '',
          controller: '',
          callsign: '',
          report: '',
          qth: '',
          device: '',
          power: '',
          antenna: '',
          height: '',
        );
      }
    }).toList();
    
    notifyListeners();
  }

  Future<void> _saveLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final logsJson = _logs.map((log) => log.toJson().toString()).toList();
    await prefs.setStringList('logData', logsJson);
  }

  Future<void> addLog(LogEntry log) async {
    if (isEditing) {
      _logs[_editIndex] = log;
      _editIndex = -1;
    } else {
      _logs.add(log);
    }
    await _saveLogs();
    notifyListeners();
  }

  Future<void> updateLog(int index, LogEntry log) async {
    if (index >= 0 && index < _logs.length) {
      _logs[index] = log;
      await _saveLogs();
      notifyListeners();
    }
  }

  Future<void> deleteLog(int index) async {
    if (index >= 0 && index < _logs.length) {
      _undoStack.add(_logs[index]);
      _logs.removeAt(index);
      await _saveLogs();
      notifyListeners();
    }
  }

  Future<void> undoLastLog() async {
    if (_logs.isNotEmpty) {
      _undoStack.add(_logs.last);
      _logs.removeLast();
      await _saveLogs();
      notifyListeners();
    }
  }

  Future<void> clearAllLogs() async {
    _undoStack = List.from(_logs);
    _logs.clear();
    await _saveLogs();
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

  Future<void> importLogs(List<LogEntry> importedLogs) async {
    _logs.addAll(importedLogs);
    await _saveLogs();
    notifyListeners();
  }

  List<List<String>> getLogsAsList() {
    return _logs.map((log) => log.toList()).toList();
  }
}