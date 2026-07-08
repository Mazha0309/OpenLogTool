import 'dart:typed_data';
import 'api.dart' as api;
import 'api/logs.dart' as logs;
import 'api/sessions.dart' as sessions;
import 'api/dictionaries.dart' as dict;
import 'api/settings.dart' as settings;
import 'api/export.dart' as export_api;
import 'models/log_entry.dart';
import 'models/session.dart';
import 'models/dict_item.dart';

class RustApi {
  static Future<void> init({required String dbPath}) async {
    await api.initDatabase(dbPath: dbPath);
  }

  // Logs
  static Future<LogEntry> addLog({
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
  }) {
    return logs.addLog(
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
  }

  static Future<List<LogEntry>> getLogs({
    required String sessionId,
    int? page,
    int? pageSize,
    String? search,
  }) {
    return logs.getLogs(
      sessionId: sessionId,
      page: page,
      pageSize: pageSize,
      search: search,
    );
  }

  static Future<LogStats> getLogStats({required String sessionId}) {
    return logs.getLogStats(sessionId: sessionId);
  }

  static Future<List<LogEntry>> getRecentByCallsign({
    required String callsign,
    int? limit,
  }) {
    return logs.getRecentByCallsign(callsign: callsign, limit: limit);
  }

  static Future<void> deleteLog({required String syncId}) {
    return logs.deleteLog(syncId: syncId);
  }

  static Future<void> undoLastLog({required String sessionId}) {
    return logs.undoLastLog(sessionId: sessionId);
  }

  // Sessions
  static Future<Session> createSession({required String title}) {
    return sessions.createSession(title: title);
  }

  static Future<List<Session>> listSessions() {
    return sessions.listSessions();
  }

  static Future<void> closeSession({required String sessionId}) {
    return sessions.closeSession(sessionId: sessionId);
  }

  static Future<Session> joinSession({required String shareCode}) {
    return sessions.joinSession(shareCode: shareCode);
  }

  // Dictionaries
  static Future<List<DictItem>> searchDict({
    required String dictType,
    required String query,
    int? limit,
  }) {
    return dict.searchDict(dictType: dictType, query: query, limit: limit);
  }

  static Future<void> addDictItem({
    required String dictType,
    required String raw,
  }) {
    return dict.addDictItem(dictType: dictType, raw: raw);
  }

  static Future<BigInt> seedDict({
    required String dictType,
    required List<String> items,
  }) {
    return dict.seedDict(dictType: dictType, items: items);
  }

  // Settings
  static Future<String?> getSetting({required String key}) {
    return settings.getSetting(key: key);
  }

  static Future<void> setSetting({required String key, required String value}) {
    return settings.setSetting(key: key, value: value);
  }

  static Future<List<(String, String)>> getAllSettings() {
    return settings.getAllSettings();
  }

  // Export
  static Future<Uint8List> exportJson({required String sessionId}) {
    return export_api.exportJson(sessionId: sessionId);
  }

  static Future<Uint8List> exportExcel({required String sessionId}) {
    return export_api.exportExcel(sessionId: sessionId);
  }
}
