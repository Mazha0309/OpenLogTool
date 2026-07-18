typedef PersonalDictionarySnapshotJson = Map<String, Object?>;

/// Metadata for the account-scoped personal dictionary-change snapshot.
///
/// This snapshot has its own revision stream and is deliberately independent
/// from the personal records snapshot.
final class PersonalDictionarySnapshotMeta {
  const PersonalDictionarySnapshotMeta({
    required this.exists,
    required this.revision,
    required this.formatVersion,
    required this.itemCount,
    required this.activeCount,
    required this.deletedCount,
    required this.byteSize,
    required this.checksum,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PersonalDictionarySnapshotMeta.fromJson(Object? json) {
    final object = _object(json, 'personalDictionarySnapshot');
    return PersonalDictionarySnapshotMeta(
      exists: _boolean(object, 'exists'),
      revision: _integer(object, 'revision'),
      formatVersion: _integer(object, 'formatVersion'),
      itemCount: _integer(object, 'itemCount'),
      activeCount: _integer(object, 'activeCount'),
      deletedCount: _integer(object, 'deletedCount'),
      byteSize: _integer(object, 'byteSize'),
      checksum: _nullableString(object, 'checksum'),
      createdAt: _nullableDateTime(object, 'createdAt'),
      updatedAt: _nullableDateTime(object, 'updatedAt'),
    );
  }

  final bool exists;
  final int revision;
  final int formatVersion;
  final int itemCount;
  final int activeCount;
  final int deletedCount;
  final int byteSize;
  final String? checksum;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}

final class PersonalDictionarySnapshotDownload {
  const PersonalDictionarySnapshotDownload({
    required this.meta,
    required this.snapshot,
  });

  factory PersonalDictionarySnapshotDownload.fromJson(Object? json) {
    final envelope = _object(json, 'personalDictionarySnapshotDownload');
    final value = _object(
      envelope['personalDictionarySnapshot'],
      'personalDictionarySnapshot',
    );
    return PersonalDictionarySnapshotDownload(
      meta: PersonalDictionarySnapshotMeta.fromJson(value),
      snapshot: _object(value['snapshot'], 'snapshot'),
    );
  }

  final PersonalDictionarySnapshotMeta meta;
  final PersonalDictionarySnapshotJson snapshot;
}

final class PersonalDictionarySnapshotReplaceResult {
  const PersonalDictionarySnapshotReplaceResult({
    required this.replaced,
    required this.meta,
  });

  factory PersonalDictionarySnapshotReplaceResult.fromJson(Object? json) {
    final envelope = _object(json, 'personalDictionarySnapshotReplaceResult');
    return PersonalDictionarySnapshotReplaceResult(
      replaced: _boolean(envelope, 'replaced'),
      meta: PersonalDictionarySnapshotMeta.fromJson(
        envelope['personalDictionarySnapshot'],
      ),
    );
  }

  final bool replaced;
  final PersonalDictionarySnapshotMeta meta;
}

PersonalDictionarySnapshotJson _object(Object? value, String field) {
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

int _integer(PersonalDictionarySnapshotJson object, String field) {
  final value = object[field];
  if (value is int && value >= 0) return value;
  throw FormatException('$field must be a non-negative integer');
}

bool _boolean(PersonalDictionarySnapshotJson object, String field) {
  final value = object[field];
  if (value is bool) return value;
  throw FormatException('$field must be a boolean');
}

String? _nullableString(
  PersonalDictionarySnapshotJson object,
  String field,
) {
  final value = object[field];
  if (value == null) return null;
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('$field must be a non-empty string or null');
}

DateTime? _nullableDateTime(
  PersonalDictionarySnapshotJson object,
  String field,
) {
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
