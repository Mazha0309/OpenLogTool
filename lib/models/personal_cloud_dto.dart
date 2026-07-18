typedef PersonalCloudJsonObject = Map<String, Object?>;

final class PersonalCloudSnapshotMeta {
  const PersonalCloudSnapshotMeta({
    required this.exists,
    required this.revision,
    required this.formatVersion,
    required this.sessionCount,
    required this.logCount,
    required this.byteSize,
    required this.checksum,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PersonalCloudSnapshotMeta.fromJson(Object? json) {
    final object = _object(json, 'personalSnapshot');
    return PersonalCloudSnapshotMeta(
      exists: _boolean(object, 'exists'),
      revision: _integer(object, 'revision'),
      formatVersion: _integer(object, 'formatVersion'),
      sessionCount: _integer(object, 'sessionCount'),
      logCount: _integer(object, 'logCount'),
      byteSize: _integer(object, 'byteSize'),
      checksum: _nullableString(object, 'checksum'),
      createdAt: _nullableDateTime(object, 'createdAt'),
      updatedAt: _nullableDateTime(object, 'updatedAt'),
    );
  }

  final bool exists;
  final int revision;
  final int formatVersion;
  final int sessionCount;
  final int logCount;
  final int byteSize;
  final String? checksum;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}

final class PersonalCloudSnapshotDownload {
  const PersonalCloudSnapshotDownload({
    required this.meta,
    required this.snapshot,
  });

  factory PersonalCloudSnapshotDownload.fromJson(Object? json) {
    final envelope = _object(json, 'personalSnapshotDownload');
    final value = _object(envelope['personalSnapshot'], 'personalSnapshot');
    return PersonalCloudSnapshotDownload(
      meta: PersonalCloudSnapshotMeta.fromJson(value),
      snapshot: _object(value['snapshot'], 'snapshot'),
    );
  }

  final PersonalCloudSnapshotMeta meta;
  final PersonalCloudJsonObject snapshot;
}

final class PersonalCloudSnapshotReplaceResult {
  const PersonalCloudSnapshotReplaceResult({
    required this.replaced,
    required this.meta,
  });

  factory PersonalCloudSnapshotReplaceResult.fromJson(Object? json) {
    final envelope = _object(json, 'personalSnapshotReplaceResult');
    return PersonalCloudSnapshotReplaceResult(
      replaced: _boolean(envelope, 'replaced'),
      meta: PersonalCloudSnapshotMeta.fromJson(
        envelope['personalSnapshot'],
      ),
    );
  }

  final bool replaced;
  final PersonalCloudSnapshotMeta meta;
}

PersonalCloudJsonObject _object(Object? value, String field) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    try {
      return Map<String, Object?>.from(value);
    } on TypeError {
      // Report a stable protocol error below.
    }
  }
  throw FormatException('$field must be a JSON object');
}

int _integer(PersonalCloudJsonObject object, String field) {
  final value = object[field];
  if (value is int && value >= 0) return value;
  throw FormatException('$field must be a non-negative integer');
}

bool _boolean(PersonalCloudJsonObject object, String field) {
  final value = object[field];
  if (value is bool) return value;
  throw FormatException('$field must be a boolean');
}

String? _nullableString(PersonalCloudJsonObject object, String field) {
  final value = object[field];
  if (value == null) return null;
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('$field must be a non-empty string or null');
}

DateTime? _nullableDateTime(PersonalCloudJsonObject object, String field) {
  final value = object[field];
  if (value == null) return null;
  if (value is! String || value.isEmpty) {
    throw FormatException('$field must be an RFC3339 string or null');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !value.endsWith('Z')) {
    throw FormatException('$field must be an RFC3339 UTC timestamp or null');
  }
  return parsed.toUtc();
}
