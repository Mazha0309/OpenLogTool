import 'package:flutter/foundation.dart';
import 'package:openlogtool/src/bridge/rust_api.dart';
import 'package:openlogtool/src/bridge/models/log_entry.dart';

class RustLogProvider extends ChangeNotifier {
  List<LogEntry> _logs = [];
  LogStats? _stats;
  bool _loading = false;
  String? _error;

  List<LogEntry> get logs => _logs;
  LogStats? get stats => _stats;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> loadLogs(String sessionId, {String? search}) async {
    _loading = true;
    notifyListeners();
    try {
      _logs = await RustApi.getLogs(
        sessionId: sessionId,
        page: 1,
        pageSize: 200,
        search: search,
      );
      _stats = await RustApi.getLogStats(sessionId: sessionId);
      _error = null;
    } catch (e) {
      _error = e.toString();
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> addLog({
    required String sessionId,
    required String controller,
    required String callsign,
    String? rstSent,
    String? rstRcvd,
    String? qth,
    String? device,
    String? power,
    String? antenna,
    String? height,
  }) async {
    try {
      await RustApi.addLog(
        sessionId: sessionId,
        controller: controller,
        callsign: callsign,
        rstSent: rstSent,
        rstRcvd: rstRcvd,
        qth: qth,
        device: device,
        power: power,
        antenna: antenna,
        height: height,
      );
      await loadLogs(sessionId);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> deleteLog(String sessionId, String syncId) async {
    try {
      await RustApi.deleteLog(syncId: syncId);
      await loadLogs(sessionId);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> undoLastLog(String sessionId) async {
    try {
      await RustApi.undoLastLog(sessionId: sessionId);
      await loadLogs(sessionId);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }
}
