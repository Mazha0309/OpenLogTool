import 'api.dart' as api;
import 'api/logs.dart' as logs;
import 'api/sessions.dart' as sessions;
import 'api/dictionaries.dart' as dict;
import 'api/settings.dart' as settings;
import 'api/collaboration.dart' as collaboration;
import 'api/database.dart' as database;
import 'api/personal_records.dart' as personal_records;
import 'api/personal_cloud.dart' as personal_cloud;
import 'api/personal_dictionary.dart' as personal_dictionary;
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
    required String time,
    String? rstSent,
    String? rstRcvd,
    String? qth,
    String? device,
    String? power,
    String? antenna,
    String? height,
    String? remarks,
  }) {
    return logs.addLog(
      sessionId: sessionId,
      controller: controller,
      callsign: callsign,
      time: time,
      rstSent: rstSent,
      rstRcvd: rstRcvd,
      qth: qth,
      device: device,
      power: power,
      antenna: antenna,
      height: height,
      remarks: remarks,
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

  static Future<LogEntry> updateLog({
    required String syncId,
    required String controller,
    required String callsign,
    required String time,
    String? rstSent,
    String? rstRcvd,
    String? qth,
    String? device,
    String? power,
    String? antenna,
    String? height,
    String? remarks,
  }) {
    return logs.updateLog(
      syncId: syncId,
      controller: controller,
      callsign: callsign,
      time: time,
      rstSent: rstSent,
      rstRcvd: rstRcvd,
      qth: qth,
      device: device,
      power: power,
      antenna: antenna,
      height: height,
      remarks: remarks,
    );
  }

  static Future<void> deleteLog({required String syncId}) {
    return logs.deleteLog(syncId: syncId);
  }

  static Future<void> undoLastLog({required String sessionId}) {
    return logs.undoLastLog(sessionId: sessionId);
  }

  static Future<LogEntry> restoreLog({required String syncId}) {
    return logs.restoreLog(syncId: syncId);
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

  static Future<Session> reopenLocalSession({required String sessionId}) {
    return sessions.reopenLocalSession(sessionId: sessionId);
  }

  static Future<Session> copyCollaborationSessionToLocal({
    required String sessionId,
    required String title,
  }) {
    return sessions.copyCollaborationSessionToLocal(
      sessionId: sessionId,
      title: title,
    );
  }

  static Future<Session> convertCollaborationSessionToLocal({
    required String sessionId,
  }) {
    return sessions.convertCollaborationSessionToLocal(
      sessionId: sessionId,
    );
  }

  static Future<Session> stopCollaborationSessionLocally({
    required String sessionId,
  }) {
    return sessions.stopCollaborationSessionLocally(sessionId: sessionId);
  }

  static Future<Session> closeSessionLocally({required String sessionId}) {
    return sessions.closeSessionLocally(sessionId: sessionId);
  }

  static Future<void> hardDeleteSession({required String sessionId}) {
    return sessions.hardDeleteSession(sessionId: sessionId);
  }

  static Future<Session> joinSession({required String shareCode}) {
    return sessions.joinSession(shareCode: shareCode);
  }

  static Future<void> updateCollaborationSessionTitle({
    required String sessionId,
    required String title,
  }) {
    return sessions.updateCollaborationSessionTitle(
      sessionId: sessionId,
      title: title,
    );
  }

  static Future<void> reopenCollaborationSession({
    required String sessionId,
  }) {
    return sessions.reopenCollaborationSession(sessionId: sessionId);
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

  static Future<void> upsertDictItem({
    required String dictType,
    required String raw,
    String? pinyin,
    String? abbreviation,
  }) {
    return dict.upsertDictItem(
      dictType: dictType,
      raw: raw,
      pinyin: pinyin,
      abbreviation: abbreviation,
    );
  }

  static Future<void> upsertDictItemIfActive({
    required String dictType,
    required String raw,
    String? pinyin,
    String? abbreviation,
  }) {
    return dict.upsertDictItemIfActive(
      dictType: dictType,
      raw: raw,
      pinyin: pinyin,
      abbreviation: abbreviation,
    );
  }

  static Future<DictItem> renameDictItem({
    required String dictType,
    required String oldRaw,
    required String newRaw,
    String? pinyin,
    String? abbreviation,
  }) {
    return dict.renameDictItem(
      dictType: dictType,
      oldRaw: oldRaw,
      newRaw: newRaw,
      pinyin: pinyin,
      abbreviation: abbreviation,
    );
  }

  static Future<void> bulkUpsertDictItems({required String requestJson}) {
    return dict.bulkUpsertDictItems(requestJson: requestJson);
  }

  static Future<List<DictItem>> getDictItems({required String dictType}) {
    return dict.getDictItems(dictType: dictType);
  }

  static Future<DictItem?> getDictItemByRaw({
    required String dictType,
    required String raw,
  }) {
    return dict.getDictItemByRaw(dictType: dictType, raw: raw);
  }

  static Future<bool> softDeleteDictItem({
    required String dictType,
    required String raw,
  }) {
    return dict.softDeleteDictItem(dictType: dictType, raw: raw);
  }

  static Future<void> softDeleteDictItems({required String dictType}) {
    return dict.softDeleteDictItems(dictType: dictType);
  }

  static Future<void> resetDictionaries() {
    return dict.resetDictionaries();
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

  // Collaboration replica
  static Future<String> getOrCreateDeviceId() {
    return collaboration.getOrCreateDeviceId();
  }

  static Future<String?> getCollaborationBinding({
    required String serverInstanceId,
    required String accountId,
    required String sessionId,
  }) {
    return collaboration.getCollaborationBinding(
      serverInstanceId: serverInstanceId,
      accountId: accountId,
      sessionId: sessionId,
    );
  }

  static Future<String?> getSessionCollaborationBinding({
    required String sessionId,
  }) {
    return collaboration.getSessionCollaborationBinding(
      sessionId: sessionId,
    );
  }

  static Future<String> getPublishSnapshot({required String sessionId}) {
    return collaboration.getPublishSnapshot(sessionId: sessionId);
  }

  static Future<String> beginPublishSnapshot({
    required String serverInstanceId,
    required String serverOrigin,
    required String accountId,
    required String sessionId,
  }) {
    return collaboration.beginPublishSnapshot(
      serverInstanceId: serverInstanceId,
      serverOrigin: serverOrigin,
      accountId: accountId,
      sessionId: sessionId,
    );
  }

  static Future<void> abortPublish({
    required String serverInstanceId,
    required String accountId,
    required String sessionId,
  }) {
    return collaboration.abortPublish(
      serverInstanceId: serverInstanceId,
      accountId: accountId,
      sessionId: sessionId,
    );
  }

  static Future<String> installCollaborationSnapshot({
    required String requestJson,
  }) {
    return collaboration.installCollaborationSnapshot(
      requestJson: requestJson,
    );
  }

  static Future<void> markCollaborationRevoked({
    required String serverInstanceId,
    required String accountId,
    required String sessionId,
  }) {
    return collaboration.markCollaborationRevoked(
      serverInstanceId: serverInstanceId,
      accountId: accountId,
      sessionId: sessionId,
    );
  }

  static Future<String> updateCollaborationMembership({
    required String serverInstanceId,
    required String accountId,
    required String sessionId,
    required String membershipId,
    required int membershipVersion,
    required String role,
  }) {
    return collaboration.updateCollaborationMembership(
      serverInstanceId: serverInstanceId,
      accountId: accountId,
      sessionId: sessionId,
      membershipId: membershipId,
      membershipVersion: membershipVersion,
      role: role,
    );
  }

  static Future<String> listPendingCollaborationMutations({
    required String serverInstanceId,
    required String accountId,
    required String sessionId,
    int? limit,
  }) {
    return collaboration.listPendingCollaborationMutations(
      serverInstanceId: serverInstanceId,
      accountId: accountId,
      sessionId: sessionId,
      limit: limit,
    );
  }

  static Future<void> markCollaborationMutationsSending({
    required String serverInstanceId,
    required String accountId,
    required String sessionId,
    required String mutationIdsJson,
  }) {
    return collaboration.markCollaborationMutationsSending(
      serverInstanceId: serverInstanceId,
      accountId: accountId,
      sessionId: sessionId,
      mutationIdsJson: mutationIdsJson,
    );
  }

  static Future<void> markCollaborationMutationAccepted({
    required String serverInstanceId,
    required String accountId,
    required String sessionId,
    required String mutationId,
    required int acceptedEventSeq,
  }) {
    return collaboration.markCollaborationMutationAccepted(
      serverInstanceId: serverInstanceId,
      accountId: accountId,
      sessionId: sessionId,
      mutationId: mutationId,
      acceptedEventSeq: acceptedEventSeq,
    );
  }

  static Future<void> markCollaborationMutationRetry({
    required String requestJson,
  }) {
    return collaboration.markCollaborationMutationRetry(
      requestJson: requestJson,
    );
  }

  static Future<void> markCollaborationMutationRejected({
    required String serverInstanceId,
    required String accountId,
    required String sessionId,
    required String mutationId,
    required String errorCode,
    required String errorMessage,
    String? detailsJson,
  }) {
    return collaboration.markCollaborationMutationRejected(
      serverInstanceId: serverInstanceId,
      accountId: accountId,
      sessionId: sessionId,
      mutationId: mutationId,
      errorCode: errorCode,
      errorMessage: errorMessage,
      detailsJson: detailsJson,
    );
  }

  static Future<String> recordCollaborationMutationConflict({
    required String requestJson,
  }) {
    return collaboration.recordCollaborationMutationConflict(
      requestJson: requestJson,
    );
  }

  static Future<String> applyCollaborationEvent({
    required String requestJson,
  }) {
    return collaboration.applyCollaborationEvent(requestJson: requestJson);
  }

  static Future<void> setCollaborationHeadSeq({
    required String serverInstanceId,
    required String accountId,
    required String sessionId,
    required int headSeq,
  }) {
    return collaboration.setCollaborationHeadSeq(
      serverInstanceId: serverInstanceId,
      accountId: accountId,
      sessionId: sessionId,
      headSeq: headSeq,
    );
  }

  static Future<String> getCollaborationSyncStatus({
    required String serverInstanceId,
    required String accountId,
    required String sessionId,
  }) {
    return collaboration.getCollaborationSyncStatus(
      serverInstanceId: serverInstanceId,
      accountId: accountId,
      sessionId: sessionId,
    );
  }

  static Future<String> saveCollaborationLiveDraftCache({
    required String requestJson,
  }) {
    return collaboration.saveCollaborationLiveDraftCache(
      requestJson: requestJson,
    );
  }

  static Future<String?> getCollaborationLiveDraftCache({
    required String serverInstanceId,
    required String accountId,
    required String sessionId,
  }) {
    return collaboration.getCollaborationLiveDraftCache(
      serverInstanceId: serverInstanceId,
      accountId: accountId,
      sessionId: sessionId,
    );
  }

  static Future<void> clearCollaborationLiveDraftCache({
    required String serverInstanceId,
    required String accountId,
    required String sessionId,
  }) {
    return collaboration.clearCollaborationLiveDraftCache(
      serverInstanceId: serverInstanceId,
      accountId: accountId,
      sessionId: sessionId,
    );
  }

  static Future<String> queueCollaborationOfflineRecord({
    required String requestJson,
  }) {
    return collaboration.queueCollaborationOfflineRecord(
      requestJson: requestJson,
    );
  }

  static Future<String> listCollaborationOfflineRecords({
    required String serverInstanceId,
    required String accountId,
    required String sessionId,
  }) {
    return collaboration.listCollaborationOfflineRecords(
      serverInstanceId: serverInstanceId,
      accountId: accountId,
      sessionId: sessionId,
    );
  }

  static Future<String> updateCollaborationOfflineRecord({
    required String requestJson,
  }) {
    return collaboration.updateCollaborationOfflineRecord(
      requestJson: requestJson,
    );
  }

  // Database operations
  static Future<String> getDatabaseStatus() {
    return database.getDatabaseStatus();
  }

  static Future<String> exportDatabase() {
    return database.exportDatabase();
  }

  static Future<void> importDatabase({required String jsonData}) {
    return database.importDatabase(jsonData: jsonData);
  }

  static Future<void> clearAllData() {
    return database.clearAllData();
  }

  // Account-scoped personal record snapshots. Collaboration replicas and all
  // non-record tables are deliberately excluded by the Rust transaction.
  static Future<String> exportPersonalRecords() {
    return personal_records.exportPersonalRecords();
  }

  static Future<String> replacePersonalRecords({required String jsonData}) {
    return personal_records.replacePersonalRecords(jsonData: jsonData);
  }

  static Future<String> replacePersonalRecordsIfUnchanged({
    required String jsonData,
    required String expectedLocalJsonData,
  }) {
    return personal_records.replacePersonalRecordsIfUnchanged(
      jsonData: jsonData,
      expectedLocalJsonData: expectedLocalJsonData,
    );
  }

  static Future<String> mergePersonalRecords({required String jsonData}) {
    return personal_records.mergePersonalRecords(jsonData: jsonData);
  }

  static Future<String> loadPersonalCloudState({
    required String scopeHash,
    required String dataset,
  }) {
    return personal_cloud.loadPersonalCloudState(
      scopeHash: scopeHash,
      dataset: dataset,
    );
  }

  static Future<void> savePersonalCloudBaseline({
    required String scopeHash,
    required String dataset,
    required int remoteRevision,
    required String snapshotJson,
    required String checksum,
    required bool claimOwner,
    required bool clearPairingRequirement,
  }) {
    return personal_cloud.savePersonalCloudBaseline(
      scopeHash: scopeHash,
      dataset: dataset,
      remoteRevision: remoteRevision,
      snapshotJson: snapshotJson,
      checksum: checksum,
      claimOwner: claimOwner,
      clearPairingRequirement: clearPairingRequirement,
    );
  }

  static Future<void> requirePersonalCloudPairing({required String reason}) {
    return personal_cloud.requirePersonalCloudPairing(reason: reason);
  }

  static Future<String> exportPersonalDictionary() {
    return personal_dictionary.exportPersonalDictionary();
  }

  static Future<String> replacePersonalDictionaryIfUnchanged({
    required String jsonData,
    required String expectedLocalJsonData,
  }) {
    return personal_dictionary.replacePersonalDictionaryIfUnchanged(
      jsonData: jsonData,
      expectedLocalJsonData: expectedLocalJsonData,
    );
  }
}
