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

/// Result of acquiring a field lease.
///
/// Servers predating the high-latency live-draft protocol enhancement only
/// return [lock]. Newer servers also include the canonical [draft] captured
/// when the lease was granted, allowing the client to rebase without another
/// network round trip.
final class LiveDraftLockAcquisitionDto {
  const LiveDraftLockAcquisitionDto({
    required this.lock,
    required this.draft,
  });

  factory LiveDraftLockAcquisitionDto.fromJson(Object? json) {
    final object = _object(json, 'liveDraftLockResult');
    return LiveDraftLockAcquisitionDto(
      lock: LiveDraftLockDto.fromJson(object['lock']),
      draft: object['draft'] == null
          ? null
          : LiveDraftDto.fromJson(object['draft']),
    );
  }

  final LiveDraftLockDto lock;
  final LiveDraftDto? draft;
}

final class LiveDraftSnapshotDto {
  const LiveDraftSnapshotDto({
    required this.draft,
    required this.locks,
    required this.currentOrdinal,
    required this.totalRecords,
    required this.previousRecord,
    this.historyPreview,
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
      historyPreview: object['historyPreview'] == null
          ? null
          : LiveDraftHistoryPreviewDto.fromJson(object['historyPreview']),
    );
  }

  final LiveDraftDto draft;
  final List<LiveDraftLockDto> locks;
  final int currentOrdinal;
  final int totalRecords;
  final CollaborationLogDto? previousRecord;
  final LiveDraftHistoryPreviewDto? historyPreview;

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

final class LiveDraftReleasedLeaseDto {
  const LiveDraftReleasedLeaseDto({
    required this.field,
    required this.leaseId,
  });

  factory LiveDraftReleasedLeaseDto.fromJson(Object? json) {
    final object = _object(json, 'releasedLease');
    final field = _string(object, 'field');
    if (!liveDraftFieldNames.contains(field)) {
      throw FormatException('releasedLease.field is unsupported: $field');
    }
    return LiveDraftReleasedLeaseDto(
      field: field,
      leaseId: _string(object, 'leaseId'),
    );
  }

  final String field;
  final String leaseId;

  JsonObject toJson() => {'field': field, 'leaseId': leaseId};
}

const Set<String> liveDraftHistoryReusableFieldNames = <String>{
  'qth',
  'device',
  'power',
  'antenna',
  'height',
};

/// One local-history row that may be previewed to the other scribes.
///
/// [sourceTime] is provenance only. Applying a candidate never writes it into
/// the shared draft's `time` field.
final class LiveDraftHistoryCandidateDto {
  const LiveDraftHistoryCandidateDto({
    required this.candidateId,
    required this.sourceTime,
    required this.qth,
    required this.device,
    required this.power,
    required this.antenna,
    required this.height,
  });

  factory LiveDraftHistoryCandidateDto.fromJson(Object? json) {
    final object = _object(json, 'liveDraftHistoryCandidate');
    return LiveDraftHistoryCandidateDto(
      candidateId: _string(object, 'candidateId'),
      sourceTime: _string(object, 'sourceTime'),
      qth: _nullableText(object['qth'], 'qth'),
      device: _nullableText(object['device'], 'device'),
      power: _nullableText(object['power'], 'power'),
      antenna: _nullableText(object['antenna'], 'antenna'),
      height: _nullableText(object['height'], 'height'),
    );
  }

  final String candidateId;
  final String sourceTime;
  final String qth;
  final String device;
  final String power;
  final String antenna;
  final String height;

  Map<String, String> get reusableValues => <String, String>{
        if (qth.isNotEmpty) 'qth': qth,
        if (device.isNotEmpty) 'device': device,
        if (power.isNotEmpty) 'power': power,
        if (antenna.isNotEmpty) 'antenna': antenna,
        if (height.isNotEmpty) 'height': height,
      };

  JsonObject toJson() => {
        'candidateId': candidateId,
        'sourceTime': sourceTime,
        'qth': qth,
        'device': device,
        'power': power,
        'antenna': antenna,
        'height': height,
      };
}

/// Ephemeral history dropdown owned by the device editing `callsign`.
final class LiveDraftHistoryPreviewDto {
  const LiveDraftHistoryPreviewDto({
    required this.previewId,
    required this.draftId,
    required this.deviceId,
    required this.callsign,
    required this.actor,
    required this.expiresAt,
    required this.candidates,
  });

  factory LiveDraftHistoryPreviewDto.fromJson(Object? json) {
    final object = _object(json, 'liveDraftHistoryPreview');
    final candidateValues = object['candidates'];
    if (candidateValues is! List) {
      throw const FormatException('historyPreview.candidates must be an array');
    }
    return LiveDraftHistoryPreviewDto(
      previewId: _string(object, 'previewId'),
      draftId: _string(object, 'draftId'),
      deviceId: _string(object, 'deviceId'),
      callsign: _string(object, 'callsign').trim().toUpperCase(),
      actor: LiveDraftActorDto.fromJson(object['actor']),
      expiresAt: _dateTime(object, 'expiresAt'),
      candidates: List<LiveDraftHistoryCandidateDto>.unmodifiable(
        candidateValues.map(LiveDraftHistoryCandidateDto.fromJson),
      ),
    );
  }

  final String previewId;
  final String draftId;
  final String deviceId;
  final String callsign;
  final LiveDraftActorDto actor;
  final DateTime expiresAt;
  final List<LiveDraftHistoryCandidateDto> candidates;

  JsonObject toJson() => {
        'previewId': previewId,
        'draftId': draftId,
        'deviceId': deviceId,
        'callsign': callsign,
        'actor': actor.toJson(),
        'expiresAt': expiresAt.toUtc().toIso8601String(),
        'candidates': candidates
            .map((candidate) => candidate.toJson())
            .toList(growable: false),
      };
}

/// Metadata proving that a canonical update came from an explicit history
/// candidate selection, rather than ordinary remote typing.
final class LiveDraftHistoryReuseDto {
  const LiveDraftHistoryReuseDto({
    required this.previewId,
    required this.candidateId,
    required this.affectedFields,
  });

  factory LiveDraftHistoryReuseDto.fromJson(Object? json) {
    final object = _object(json, 'liveDraftHistoryReuse');
    final fieldValues = object['affectedFields'];
    if (fieldValues is! List || fieldValues.any((value) => value is! String)) {
      throw const FormatException(
          'historyReuse.affectedFields must be an array');
    }
    final fields = fieldValues.cast<String>().toSet();
    if (!liveDraftHistoryReusableFieldNames.containsAll(fields)) {
      throw const FormatException('historyReuse contains an unsupported field');
    }
    return LiveDraftHistoryReuseDto(
      previewId: _string(object, 'previewId'),
      candidateId: _string(object, 'candidateId'),
      affectedFields: Set<String>.unmodifiable(fields),
    );
  }

  final String previewId;
  final String candidateId;
  final Set<String> affectedFields;

  JsonObject toJson() => {
        'previewId': previewId,
        'candidateId': candidateId,
        'affectedFields': affectedFields.toList(growable: false),
      };
}

final class LiveDraftHistoryPreviewResultDto {
  const LiveDraftHistoryPreviewResultDto({
    required this.historyPreview,
    required this.draft,
    required this.locks,
  });

  factory LiveDraftHistoryPreviewResultDto.fromJson(Object? json) {
    final object = _object(json, 'liveDraftHistoryPreviewResult');
    final lockValues = object['locks'];
    if (lockValues is! List) {
      throw const FormatException('history preview locks must be an array');
    }
    return LiveDraftHistoryPreviewResultDto(
      historyPreview:
          LiveDraftHistoryPreviewDto.fromJson(object['historyPreview']),
      draft: LiveDraftDto.fromJson(object['draft']),
      locks: List<LiveDraftLockDto>.unmodifiable(
        lockValues.map(LiveDraftLockDto.fromJson),
      ),
    );
  }

  final LiveDraftHistoryPreviewDto historyPreview;
  final LiveDraftDto draft;
  final List<LiveDraftLockDto> locks;
}

final class LiveDraftHistoryReuseResultDto {
  const LiveDraftHistoryReuseResultDto({
    required this.draft,
    required this.updatedFields,
    required this.releasedLeases,
    required this.historyReuse,
    required this.locks,
  });

  factory LiveDraftHistoryReuseResultDto.fromJson(Object? json) {
    final object = _object(json, 'liveDraftHistoryReuseResult');
    final lockValues = object['locks'];
    final updatedFieldValues = object['updatedFields'];
    if (updatedFieldValues is! List ||
        updatedFieldValues.any((value) => value is! String)) {
      throw const FormatException(
        'history reuse updatedFields must be an array',
      );
    }
    final updatedFields = updatedFieldValues.cast<String>().toSet();
    if (!liveDraftHistoryReusableFieldNames.containsAll(updatedFields)) {
      throw const FormatException(
        'history reuse updatedFields contains an unsupported field',
      );
    }
    if (lockValues is! List) {
      throw const FormatException('history reuse locks must be an array');
    }
    final historyReuse =
        LiveDraftHistoryReuseDto.fromJson(object['historyReuse']);
    if (updatedFields.length != historyReuse.affectedFields.length ||
        !updatedFields.containsAll(historyReuse.affectedFields)) {
      throw const FormatException(
        'history reuse updatedFields do not match affectedFields',
      );
    }
    if (object['historyPreview'] != null) {
      throw const FormatException(
        'history reuse must clear the active history preview',
      );
    }
    return LiveDraftHistoryReuseResultDto(
      draft: LiveDraftDto.fromJson(object['draft']),
      updatedFields: Set<String>.unmodifiable(updatedFields),
      releasedLeases: _optionalReleasedLeases(object['releasedLeases']),
      historyReuse: historyReuse,
      locks: List<LiveDraftLockDto>.unmodifiable(
        lockValues.map(LiveDraftLockDto.fromJson),
      ),
    );
  }

  final LiveDraftDto draft;
  final Set<String> updatedFields;
  final List<LiveDraftReleasedLeaseDto> releasedLeases;
  final LiveDraftHistoryReuseDto historyReuse;
  final List<LiveDraftLockDto> locks;
}

final class LiveDraftPatchResultDto {
  const LiveDraftPatchResultDto({
    required this.draft,
    required this.appliedClientSeq,
    required this.replayed,
    this.releasedLeases = const <LiveDraftReleasedLeaseDto>[],
  });

  factory LiveDraftPatchResultDto.fromJson(Object? json) {
    final object = _object(json, 'liveDraftPatchResult');
    return LiveDraftPatchResultDto(
      draft: LiveDraftDto.fromJson(object['draft']),
      appliedClientSeq:
          _nonNegativeInteger(object, 'appliedClientSeq', minimum: 1),
      replayed: _boolean(object, 'replayed'),
      releasedLeases: _optionalReleasedLeases(object['releasedLeases']),
    );
  }

  final LiveDraftDto draft;
  final int appliedClientSeq;
  final bool replayed;
  final List<LiveDraftReleasedLeaseDto> releasedLeases;
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

List<LiveDraftReleasedLeaseDto> _optionalReleasedLeases(Object? value) {
  if (value == null) return const <LiveDraftReleasedLeaseDto>[];
  if (value is! List) {
    throw const FormatException('releasedLeases must be an array');
  }
  return List<LiveDraftReleasedLeaseDto>.unmodifiable(
    value.map(LiveDraftReleasedLeaseDto.fromJson),
  );
}

DateTime _dateTime(JsonObject object, String field) {
  final value = object[field];
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed;
  }
  throw FormatException('$field must be an ISO timestamp');
}
