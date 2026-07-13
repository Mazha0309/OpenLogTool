import 'dart:convert';

import 'package:openlogtool/models/collaboration_dto.dart';

const int collaborationBootstrapMaxItems = 500;
const int collaborationBootstrapMaxBodyBytes = 768 * 1024;

final class PreparedCollaborationPublish {
  const PreparedCollaborationPublish({
    required this.title,
    required this.batches,
  });

  final String title;
  final List<List<BootstrapLogDto>> batches;
}

final class CollaborationPublishValidationException implements Exception {
  const CollaborationPublishValidationException(this.message);

  final String message;

  String get code => 'PUBLISH_PREFLIGHT_VALIDATION_FAILED';

  @override
  String toString() => '$code: $message';
}

PreparedCollaborationPublish prepareCollaborationPublish({
  required String sessionId,
  required String title,
  required List<BootstrapLogDto> logs,
  int maxItems = collaborationBootstrapMaxItems,
  int maxBodyBytes = collaborationBootstrapMaxBodyBytes,
}) {
  if (maxItems < 1 || maxItems > collaborationBootstrapMaxItems) {
    throw ArgumentError.value(
        maxItems, 'maxItems', 'must be between 1 and 500');
  }
  if (maxBodyBytes < 1) {
    throw ArgumentError.value(maxBodyBytes, 'maxBodyBytes', 'must be positive');
  }

  _requireStableId(sessionId, 'sessionId');
  final normalizedTitle = title.trim();
  _requireLength(normalizedTitle, 'title', min: 1, max: 200);

  final seenIds = <String>{};
  for (var index = 0; index < logs.length; index += 1) {
    final log = logs[index];
    final prefix = 'logs[$index]';
    _requireStableId(log.syncId, '$prefix.syncId');
    if (!seenIds.add(log.syncId)) {
      throw CollaborationPublishValidationException(
        '$prefix.syncId 与另一条记录重复',
      );
    }
    _requireLength(log.controller, '$prefix.controller', min: 1, max: 32);
    _requireLength(log.callsign, '$prefix.callsign', min: 1, max: 32);
    _requireOptionalLength(log.rstSent, '$prefix.rstSent', 16);
    _requireOptionalLength(log.rstRcvd, '$prefix.rstRcvd', 16);
    _requireOptionalLength(log.qth, '$prefix.qth', 200);
    _requireOptionalLength(log.device, '$prefix.device', 200);
    _requireOptionalLength(log.power, '$prefix.power', 64);
    _requireOptionalLength(log.antenna, '$prefix.antenna', 200);
    _requireOptionalLength(log.height, '$prefix.height', 64);
    _requireOptionalLength(log.remarks, '$prefix.remarks', 2000);
  }

  const prefixBytes = 10; // UTF-8 length of {"items":[
  const suffixBytes = 2; // UTF-8 length of ]}
  final batches = <List<BootstrapLogDto>>[];
  var current = <BootstrapLogDto>[];
  var currentBytes = prefixBytes + suffixBytes;

  for (var index = 0; index < logs.length; index += 1) {
    final log = logs[index];
    final itemBytes = utf8.encode(jsonEncode(log.toJson())).length;
    final singleItemBytes = prefixBytes + itemBytes + suffixBytes;
    if (singleItemBytes > maxBodyBytes) {
      throw CollaborationPublishValidationException(
        'logs[$index] 单条记录编码后超过上传请求大小限制',
      );
    }
    final separatorBytes = current.isEmpty ? 0 : 1;
    if (current.isNotEmpty &&
        (current.length >= maxItems ||
            currentBytes + separatorBytes + itemBytes > maxBodyBytes)) {
      batches.add(List.unmodifiable(current));
      current = <BootstrapLogDto>[];
      currentBytes = prefixBytes + suffixBytes;
    }
    current.add(log);
    currentBytes += (current.length == 1 ? 0 : 1) + itemBytes;
  }
  if (current.isNotEmpty) batches.add(List.unmodifiable(current));

  return PreparedCollaborationPublish(
    title: normalizedTitle,
    batches: List.unmodifiable(batches),
  );
}

void validatePublishedCollaborationSnapshot({
  required String sessionId,
  required String title,
  required List<BootstrapLogDto> localLogs,
  required SessionSnapshotDto snapshot,
}) {
  if (snapshot.protocolVersion != 1 ||
      snapshot.session.sessionId != sessionId ||
      snapshot.session.title != title ||
      snapshot.session.status != 'active' ||
      snapshot.session.deletedAt != null ||
      localLogs.length != snapshot.logs.length) {
    throw StateError('PUBLISH_REMOTE_CONTENT_MISMATCH');
  }

  final remoteById = <String, CollaborationLogDto>{};
  for (final remote in snapshot.logs) {
    if (remote.sessionId != sessionId ||
        remote.deletedAt != null ||
        remoteById.containsKey(remote.syncId)) {
      throw StateError('PUBLISH_REMOTE_CONTENT_MISMATCH');
    }
    remoteById[remote.syncId] = remote;
  }
  for (final local in localLogs) {
    final remote = remoteById[local.syncId];
    if (remote == null ||
        !remote.time.toUtc().isAtSameMomentAs(local.time.toUtc()) ||
        remote.controller != local.controller ||
        remote.callsign != local.callsign ||
        remote.rstSent != local.rstSent ||
        remote.rstRcvd != local.rstRcvd ||
        remote.qth != local.qth ||
        remote.device != local.device ||
        remote.power != local.power ||
        remote.antenna != local.antenna ||
        remote.height != local.height ||
        remote.remarks != local.remarks) {
      throw StateError('PUBLISH_REMOTE_CONTENT_MISMATCH');
    }
  }
}

void _requireStableId(String value, String field) {
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$').hasMatch(value)) {
    throw CollaborationPublishValidationException('$field 不是有效的稳定 ID');
  }
}

void _requireLength(
  String value,
  String field, {
  required int min,
  required int max,
}) {
  if (value.length < min || value.length > max) {
    throw CollaborationPublishValidationException(
      '$field 长度必须在 $min 到 $max 之间',
    );
  }
}

void _requireOptionalLength(String? value, String field, int max) {
  if (value != null && value.length > max) {
    throw CollaborationPublishValidationException('$field 长度不能超过 $max');
  }
}
