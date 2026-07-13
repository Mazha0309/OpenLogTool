import 'package:openlogtool/models/collaboration_dto.dart';

const List<String> liveDraftFieldNames = [
  'time',
  'controller',
  'callsign',
  'rstSent',
  'rstRcvd',
  'qth',
  'device',
  'power',
  'antenna',
  'height',
  'remarks',
];

final class LiveDraftFieldsDto {
  LiveDraftFieldsDto(Map<String, String> values)
      : values = Map.unmodifiable({
          for (final field in liveDraftFieldNames) field: values[field] ?? '',
        });

  factory LiveDraftFieldsDto.empty() => LiveDraftFieldsDto(const {});

  factory LiveDraftFieldsDto.fromJson(Object? json) {
    final object = _object(json, 'liveDraft.fields');
    final unknown =
        object.keys.where((key) => !liveDraftFieldNames.contains(key));
    if (unknown.isNotEmpty) {
      throw FormatException(
          'liveDraft.fields contains unknown field ${unknown.first}');
    }
    return LiveDraftFieldsDto({
      for (final field in liveDraftFieldNames)
        field: _nullableText(object[field], 'liveDraft.fields.$field'),
    });
  }

  final Map<String, String> values;

  String operator [](String field) => values[field] ?? '';

  LiveDraftFieldsDto withField(String field, String value) {
    _requireLiveDraftField(field);
    return LiveDraftFieldsDto({...values, field: value});
  }

  JsonObject toJson() => Map<String, Object?>.from(values);
}

final class LiveDraftDto {
  const LiveDraftDto({
    required this.draftId,
    required this.sessionId,
    required this.version,
    required this.fields,
    required this.fieldRevisions,
    required this.lastUpdatedBy,
    required this.createdAt,
    required this.lastUpdatedAt,
  });

  factory LiveDraftDto.fromJson(Object? json) {
    final object = _object(json, 'liveDraft');
    final revisions = _object(object['fieldRevisions'], 'fieldRevisions');
    return LiveDraftDto(
      draftId: _string(object, 'draftId'),
      sessionId: _string(object, 'sessionId'),
      version: _nonNegativeInteger(object, 'version', minimum: 1),
      fields: LiveDraftFieldsDto.fromJson(object['fields']),
      fieldRevisions: Map.unmodifiable({
        for (final field in liveDraftFieldNames)
          field: _optionalNonNegativeInteger(revisions[field], field),
      }),
      lastUpdatedBy: object['lastUpdatedBy'] == null
          ? null
          : LiveDraftActorDto.fromJson(object['lastUpdatedBy']),
      createdAt: _dateTime(object, 'createdAt'),
      lastUpdatedAt: _dateTime(object, 'lastUpdatedAt'),
    );
  }

  final String draftId;
  final String sessionId;
  final int version;
  final LiveDraftFieldsDto fields;
  final Map<String, int> fieldRevisions;
  final LiveDraftActorDto? lastUpdatedBy;
  final DateTime createdAt;
  final DateTime lastUpdatedAt;

  JsonObject toJson() => {
        'draftId': draftId,
        'sessionId': sessionId,
        'version': version,
        'fields': fields.toJson(),
        'fieldRevisions': fieldRevisions,
        'lastUpdatedBy': lastUpdatedBy?.toJson(),
        'createdAt': createdAt.toUtc().toIso8601String(),
        'lastUpdatedAt': lastUpdatedAt.toUtc().toIso8601String(),
      };
}

final class LiveDraftActorDto {
  const LiveDraftActorDto({required this.userId, required this.username});

  factory LiveDraftActorDto.fromJson(Object? json) {
    final object = _object(json, 'liveDraftActor');
    return LiveDraftActorDto(
      userId: _string(object, 'userId'),
      username: _string(object, 'username'),
    );
  }

  final String userId;
  final String username;

  JsonObject toJson() => {'userId': userId, 'username': username};
}

final class LiveDraftLockDto {
  const LiveDraftLockDto({
    required this.leaseId,
    required this.sessionId,
    required this.field,
    required this.userId,
    required this.username,
    required this.deviceId,
    required this.expiresAt,
  });

  factory LiveDraftLockDto.fromJson(Object? json) {
    final object = _object(json, 'liveDraftLock');
    final field = _string(object, 'field');
    _requireLiveDraftField(field);
    return LiveDraftLockDto(
      leaseId: _string(object, 'leaseId'),
      sessionId: _string(object, 'sessionId'),
      field: field,
      userId: _string(object, 'userId'),
      username: _string(object, 'username'),
      deviceId: _string(object, 'deviceId'),
      expiresAt: _dateTime(object, 'expiresAt'),
    );
  }

  final String leaseId;
  final String sessionId;
  final String field;
  final String userId;
  final String username;
  final String deviceId;
  final DateTime expiresAt;

  JsonObject toJson() => {
        'leaseId': leaseId,
        'sessionId': sessionId,
        'field': field,
        'userId': userId,
        'username': username,
        'deviceId': deviceId,
        'expiresAt': expiresAt.toUtc().toIso8601String(),
      };
}

final class LiveDraftSnapshotDto {
  const LiveDraftSnapshotDto({
    required this.draft,
    required this.locks,
    required this.currentOrdinal,
    required this.totalRecords,
    required this.previousRecord,
  });

  factory LiveDraftSnapshotDto.fromJson(Object? json) {
    final object = _object(json, 'liveDraftSnapshot');
    final locks = object['locks'];
    if (locks is! List) {
      throw const FormatException('locks must be a JSON array');
    }
    return LiveDraftSnapshotDto(
      draft: LiveDraftDto.fromJson(object['draft']),
      locks: List.unmodifiable(locks.map(LiveDraftLockDto.fromJson)),
      currentOrdinal: _nonNegativeInteger(object, 'currentOrdinal', minimum: 1),
      totalRecords: _nonNegativeInteger(object, 'totalRecords'),
      previousRecord: object['previousRecord'] == null
          ? null
          : CollaborationLogDto.fromJson(object['previousRecord']),
    );
  }

  final LiveDraftDto draft;
  final List<LiveDraftLockDto> locks;
  final int currentOrdinal;
  final int totalRecords;
  final CollaborationLogDto? previousRecord;

  JsonObject toJson() => {
        'draft': draft.toJson(),
        'locks': locks.map((lock) => lock.toJson()).toList(growable: false),
        'currentOrdinal': currentOrdinal,
        'totalRecords': totalRecords,
        'previousRecord': previousRecord?.toJson(),
      };
}

final class LiveDraftPatchUpdateDto {
  LiveDraftPatchUpdateDto({
    required this.field,
    required this.value,
    required this.expectedRevision,
    required this.leaseId,
  }) {
    _requireLiveDraftField(field);
    if (expectedRevision < 0) {
      throw ArgumentError.value(expectedRevision, 'expectedRevision');
    }
  }

  final String field;
  final String? value;
  final int expectedRevision;
  final String leaseId;

  JsonObject toJson() => {
        'field': field,
        'value': value,
        'expectedRevision': expectedRevision,
        'leaseId': leaseId,
      };
}

final class LiveDraftPatchResultDto {
  const LiveDraftPatchResultDto({
    required this.draft,
    required this.appliedClientSeq,
    required this.replayed,
  });

  factory LiveDraftPatchResultDto.fromJson(Object? json) {
    final object = _object(json, 'liveDraftPatchResult');
    return LiveDraftPatchResultDto(
      draft: LiveDraftDto.fromJson(object['draft']),
      appliedClientSeq:
          _nonNegativeInteger(object, 'appliedClientSeq', minimum: 1),
      replayed: _boolean(object, 'replayed'),
    );
  }

  final LiveDraftDto draft;
  final int appliedClientSeq;
  final bool replayed;
}

final class LiveDraftCommitResultDto {
  const LiveDraftCommitResultDto({
    required this.committedDraftId,
    required this.record,
    required this.event,
    required this.nextDraft,
    required this.committedOrdinal,
    required this.currentOrdinal,
    required this.totalRecords,
  });

  factory LiveDraftCommitResultDto.fromJson(Object? json) {
    final object = _object(json, 'liveDraftCommitResult');
    return LiveDraftCommitResultDto(
      committedDraftId: _string(object, 'committedDraftId'),
      record: CollaborationLogDto.fromJson(object['record']),
      event: CollaborationEventDto.fromJson(object['event']),
      nextDraft: LiveDraftDto.fromJson(object['nextDraft']),
      committedOrdinal:
          _nonNegativeInteger(object, 'committedOrdinal', minimum: 1),
      currentOrdinal: _nonNegativeInteger(object, 'currentOrdinal', minimum: 1),
      totalRecords: _nonNegativeInteger(object, 'totalRecords'),
    );
  }

  final String committedDraftId;
  final CollaborationLogDto record;
  final CollaborationEventDto event;
  final LiveDraftDto nextDraft;
  final int committedOrdinal;
  final int currentOrdinal;
  final int totalRecords;
}

final class LiveDraftDiscardResultDto {
  const LiveDraftDiscardResultDto({
    required this.discardedDraftId,
    required this.nextDraft,
    required this.currentOrdinal,
    required this.totalRecords,
  });

  factory LiveDraftDiscardResultDto.fromJson(Object? json) {
    final object = _object(json, 'liveDraftDiscardResult');
    return LiveDraftDiscardResultDto(
      discardedDraftId: _string(object, 'discardedDraftId'),
      nextDraft: LiveDraftDto.fromJson(object['nextDraft']),
      currentOrdinal: _nonNegativeInteger(object, 'currentOrdinal', minimum: 1),
      totalRecords: _nonNegativeInteger(object, 'totalRecords'),
    );
  }

  final String discardedDraftId;
  final LiveDraftDto nextDraft;
  final int currentOrdinal;
  final int totalRecords;
}

enum OfflineRecordState { pending, submitting, reviewing, resolved, discarded }

enum OfflineRecordResolution { discard, submitAsDuplicate, copyToCurrentDraft }

final class LocalOfflineRecordDto {
  const LocalOfflineRecordDto({
    required this.serverInstanceId,
    required this.accountId,
    required this.sessionId,
    required this.mutationId,
    required this.draftId,
    required this.expectedDraftVersion,
    required this.provisionalOrdinal,
    required this.record,
    required this.state,
    required this.resolution,
    required this.lastErrorCode,
    required this.createdAt,
    required this.updatedAt,
  });

  factory LocalOfflineRecordDto.fromJson(Object? json) {
    final object = _object(json, 'localOfflineRecord');
    return LocalOfflineRecordDto(
      serverInstanceId: _string(object, 'serverInstanceId'),
      accountId: _string(object, 'accountId'),
      sessionId: _string(object, 'sessionId'),
      mutationId: _string(object, 'mutationId'),
      draftId: _string(object, 'draftId'),
      expectedDraftVersion:
          _nonNegativeInteger(object, 'expectedDraftVersion', minimum: 1),
      provisionalOrdinal:
          _nonNegativeInteger(object, 'provisionalOrdinal', minimum: 1),
      record: LiveDraftFieldsDto.fromJson(object['record']),
      state: OfflineRecordState.values.byName(_string(object, 'state')),
      resolution: object['resolution'] == null
          ? null
          : OfflineRecordResolution.values
              .byName(_string(object, 'resolution')),
      lastErrorCode: _optionalString(object['lastErrorCode'], 'lastErrorCode'),
      createdAt: _dateTime(object, 'createdAt'),
      updatedAt: _dateTime(object, 'updatedAt'),
    );
  }

  final String serverInstanceId;
  final String accountId;
  final String sessionId;
  final String mutationId;
  final String draftId;
  final int expectedDraftVersion;
  final int provisionalOrdinal;
  final LiveDraftFieldsDto record;
  final OfflineRecordState state;
  final OfflineRecordResolution? resolution;
  final String? lastErrorCode;
  final DateTime createdAt;
  final DateTime updatedAt;
}

void _requireLiveDraftField(String field) {
  if (!liveDraftFieldNames.contains(field)) {
    throw ArgumentError.value(field, 'field', 'unknown live draft field');
  }
}

JsonObject _object(Object? value, String field) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return Map<String, Object?>.from(value);
  throw FormatException('$field must be a JSON object');
}

String _string(JsonObject object, String field) {
  final value = object[field];
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('$field must be a non-empty string');
}

String _nullableText(Object? value, String field) {
  if (value == null) return '';
  if (value is String) return value;
  throw FormatException('$field must be a string or null');
}

String? _optionalString(Object? value, String field) {
  if (value == null) return null;
  if (value is String) return value;
  throw FormatException('$field must be a string or null');
}

int _nonNegativeInteger(JsonObject object, String field, {int minimum = 0}) {
  final value = object[field];
  if (value is int && value >= minimum) return value;
  throw FormatException('$field must be an integer >= $minimum');
}

int _optionalNonNegativeInteger(Object? value, String field) {
  if (value == null) return 0;
  if (value is int && value >= 0) return value;
  throw FormatException('$field must be a non-negative integer');
}

bool _boolean(JsonObject object, String field) {
  final value = object[field];
  if (value is bool) return value;
  throw FormatException('$field must be a boolean');
}

DateTime _dateTime(JsonObject object, String field) {
  final value = object[field];
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed;
  }
  throw FormatException('$field must be an ISO timestamp');
}
