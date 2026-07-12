import 'dart:convert';

enum CollaborationConflictEntityType {
  session,
  log;

  static CollaborationConflictEntityType fromJson(Object? value) =>
      switch (value) {
        'session' => CollaborationConflictEntityType.session,
        'log' => CollaborationConflictEntityType.log,
        _ => throw const FormatException(
            'conflict.entityType must be session or log',
          ),
      };
}

final class CollaborationConflict {
  const CollaborationConflict({
    required this.conflictId,
    required this.sessionId,
    required this.entityType,
    required this.entityId,
    required this.mutationId,
    required this.baseVersion,
    required this.remoteVersion,
    required this.baseEntity,
    required this.localEntity,
    required this.remoteEntity,
    required this.conflictingFields,
    required this.allowedResolutions,
    required this.createdAt,
  });

  factory CollaborationConflict.fromJson(Object? json) {
    final object = _object(json, 'conflict');
    final fields = object['conflictingFields'];
    if (fields is! List) {
      throw const FormatException(
        'conflict.conflictingFields must be an array',
      );
    }
    final allowed = object['allowedResolutions'];
    if (allowed is! List) {
      throw const FormatException(
        'conflict.allowedResolutions must be an array',
      );
    }
    final allowedResolutions =
        List<CollaborationConflictResolution>.unmodifiable(
      allowed.map(CollaborationConflictResolution.fromJson),
    );
    if (allowedResolutions.isEmpty ||
        allowedResolutions.toSet().length != allowedResolutions.length ||
        !allowedResolutions
            .contains(CollaborationConflictResolution.useRemote)) {
      throw const FormatException(
        'conflict.allowedResolutions must be unique and include useRemote',
      );
    }
    return CollaborationConflict(
      conflictId: _string(object, 'conflictId'),
      sessionId: _string(object, 'sessionId'),
      entityType: CollaborationConflictEntityType.fromJson(
        object['entityType'],
      ),
      entityId: _string(object, 'entityId'),
      mutationId: _string(object, 'mutationId'),
      baseVersion: _integer(object, 'baseVersion', minimum: 0),
      remoteVersion: _integer(object, 'remoteVersion', minimum: 1),
      baseEntity: _nullableObject(
        object['baseEntity'],
        'conflict.baseEntity',
      ),
      localEntity: _object(object['localEntity'], 'conflict.localEntity'),
      remoteEntity: _object(object['remoteEntity'], 'conflict.remoteEntity'),
      conflictingFields: List.unmodifiable(
        fields.asMap().entries.map(
              (entry) => _nonEmptyString(
                entry.value,
                'conflict.conflictingFields[${entry.key}]',
              ),
            ),
      ),
      allowedResolutions: allowedResolutions,
      createdAt: _dateTime(object, 'createdAt'),
    );
  }

  final String conflictId;
  final String sessionId;
  final CollaborationConflictEntityType entityType;
  final String entityId;
  final String mutationId;
  final int baseVersion;
  final int remoteVersion;
  final Map<String, Object?>? baseEntity;
  final Map<String, Object?> localEntity;
  final Map<String, Object?> remoteEntity;
  final List<String> conflictingFields;
  final List<CollaborationConflictResolution> allowedResolutions;
  final DateTime createdAt;
}

final class CollaborationConflictList {
  const CollaborationConflictList({required this.conflicts});

  factory CollaborationConflictList.fromJson(Object? json) {
    if (json is! List) {
      throw const FormatException('conflictList must be an array');
    }
    return CollaborationConflictList(
      conflicts: List.unmodifiable(
        json.map(CollaborationConflict.fromJson),
      ),
    );
  }

  final List<CollaborationConflict> conflicts;
}

enum CollaborationConflictResolution {
  useRemote,
  keepLocal,
  copyLocalAsNew;

  String toJson() => name;

  static CollaborationConflictResolution fromJson(Object? value) =>
      switch (value) {
        'useRemote' => CollaborationConflictResolution.useRemote,
        'keepLocal' => CollaborationConflictResolution.keepLocal,
        'copyLocalAsNew' => CollaborationConflictResolution.copyLocalAsNew,
        _ => throw const FormatException(
            'conflict resolution must be useRemote, keepLocal, or copyLocalAsNew',
          ),
      };
}

final class CollaborationConflictResolutionResult {
  const CollaborationConflictResolutionResult({
    required this.resolution,
    required this.replacementMutationId,
    required this.replacementEntityId,
  });

  factory CollaborationConflictResolutionResult.fromJson(Object? json) {
    final object = _object(json, 'conflictResolution');
    if (object['outcome'] != 'resolved') {
      throw const FormatException(
        'conflictResolution.outcome must be resolved',
      );
    }
    final replacement = object['replacementMutationId'];
    if (replacement != null &&
        (replacement is! String || replacement.trim().isEmpty)) {
      throw const FormatException(
        'conflictResolution.replacementMutationId must be non-empty',
      );
    }
    final replacementEntity = object['replacementEntityId'];
    if (replacementEntity != null &&
        (replacementEntity is! String || replacementEntity.trim().isEmpty)) {
      throw const FormatException(
        'conflictResolution.replacementEntityId must be non-empty',
      );
    }
    final resolution = CollaborationConflictResolution.fromJson(
      object['resolution'],
    );
    if (resolution == CollaborationConflictResolution.copyLocalAsNew &&
        (replacement == null || replacementEntity == null)) {
      throw const FormatException(
        'copyLocalAsNew requires replacement mutation and entity IDs',
      );
    }
    if (resolution != CollaborationConflictResolution.copyLocalAsNew &&
        replacementEntity != null) {
      throw const FormatException(
        'only copyLocalAsNew may return replacementEntityId',
      );
    }
    if (resolution == CollaborationConflictResolution.useRemote &&
        replacement != null) {
      throw const FormatException(
        'useRemote resolution cannot return replacementMutationId',
      );
    }
    return CollaborationConflictResolutionResult(
      resolution: resolution,
      replacementMutationId: replacement as String?,
      replacementEntityId: replacementEntity as String?,
    );
  }

  final CollaborationConflictResolution resolution;
  final String? replacementMutationId;
  final String? replacementEntityId;
}

String collaborationConflictEntitySummary(Map<String, Object?>? entity) {
  if (entity == null) return '无（本地新建）';
  final parts = <String>[];
  void add(String label, String key) {
    if (!entity.containsKey(key)) return;
    final value = entity[key];
    final text = switch (value) {
      null => '空',
      String value when value.trim().isEmpty => '空',
      String value => value,
      num value => value.toString(),
      bool value => value ? '是' : '否',
      _ => jsonEncode(value),
    };
    parts.add('$label=$text');
  }

  if (entity.containsKey('callsign')) {
    add('呼号', 'callsign');
    add('时间', 'time');
    add('备注', 'remarks');
    add('删除', 'deletedAt');
  } else {
    add('标题', 'title');
    add('状态', 'status');
    add('关闭', 'closedAt');
    add('删除', 'deletedAt');
  }
  add('版本', 'version');
  if (parts.isEmpty) {
    final encoded = jsonEncode(entity);
    return encoded.length <= 240 ? encoded : '${encoded.substring(0, 237)}…';
  }
  final summary = parts.join(' · ');
  return summary.length <= 240 ? summary : '${summary.substring(0, 237)}…';
}

Map<String, Object?> _object(Object? value, String field) {
  if (value is! Map) throw FormatException('$field must be an object');
  return Map<String, Object?>.from(value);
}

Map<String, Object?>? _nullableObject(Object? value, String field) =>
    value == null ? null : _object(value, field);

String _string(Map<String, Object?> object, String field) =>
    _nonEmptyString(object[field], 'conflict.$field');

String _nonEmptyString(Object? value, String field) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$field must be a non-empty string');
  }
  return value;
}

int _integer(
  Map<String, Object?> object,
  String field, {
  required int minimum,
}) {
  final value = object[field];
  if (value is! int || value < minimum) {
    throw FormatException('$field must be an integer >= $minimum');
  }
  return value;
}

DateTime _dateTime(Map<String, Object?> object, String field) {
  final value = object[field];
  if (value is! String) {
    throw FormatException('$field must be an RFC 3339 time');
  }
  try {
    return DateTime.parse(value);
  } on FormatException {
    throw FormatException('$field must be an RFC 3339 time');
  }
}
