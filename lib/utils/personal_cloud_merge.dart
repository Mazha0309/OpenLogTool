import 'dart:convert';

enum PersonalCloudDataset { records, dictionaries }

enum PersonalCloudConflictChoice { local, remote }

final class PersonalCloudMergeConflict {
  const PersonalCloudMergeConflict({
    required this.dataset,
    required this.conflictId,
    required this.entityType,
    required this.entityId,
    required this.kind,
    required this.basePresent,
    required this.localPresent,
    required this.remotePresent,
    this.sessionId,
    this.fieldGroup,
    this.baseValue,
    this.localValue,
    this.remoteValue,
  });

  final PersonalCloudDataset dataset;
  final String conflictId;
  final String entityType;
  final String entityId;
  final String? sessionId;
  final String kind;
  final String? fieldGroup;
  final bool basePresent;
  final bool localPresent;
  final bool remotePresent;
  final Object? baseValue;
  final Object? localValue;
  final Object? remoteValue;

  Map<String, Object?> toJson() => {
        'dataset': dataset.name,
        'conflictId': conflictId,
        'entityType': entityType,
        'entityId': entityId,
        if (sessionId != null) 'sessionId': sessionId,
        'kind': kind,
        if (fieldGroup != null) 'fieldGroup': fieldGroup,
        'basePresent': basePresent,
        'localPresent': localPresent,
        'remotePresent': remotePresent,
        'baseValue': baseValue,
        'localValue': localValue,
        'remoteValue': remoteValue,
      };
}

final class PersonalCloudMergeResult {
  const PersonalCloudMergeResult({
    required this.snapshot,
    required this.conflicts,
  });

  final Map<String, Object?> snapshot;
  final List<PersonalCloudMergeConflict> conflicts;
  bool get hasConflicts => conflicts.isNotEmpty;
}

PersonalCloudMergeResult mergePersonalCloudSnapshots({
  required PersonalCloudDataset dataset,
  required Map<String, Object?> base,
  required Map<String, Object?> local,
  required Map<String, Object?> remote,
  Map<String, PersonalCloudConflictChoice> resolutions = const {},
  DateTime? exportedAt,
}) {
  final conflicts = <PersonalCloudMergeConflict>[];
  final output = <String, Object?>{
    'version': 1,
    'exportedAt': (exportedAt ?? DateTime.now()).toUtc().toIso8601String(),
  };

  if (dataset == PersonalCloudDataset.records) {
    final baseSessions = _rows(base, 'sessions');
    final localSessions = _rows(local, 'sessions');
    final remoteSessions = _rows(remote, 'sessions');
    final baseLogs = _rows(base, 'logs');
    final localLogs = _rows(local, 'logs');
    final remoteLogs = _rows(remote, 'logs');
    final mergedSessions = _mergeTable(
      dataset: dataset,
      entityType: 'session',
      idField: 'session_id',
      baseRows: baseSessions,
      localRows: localSessions,
      remoteRows: remoteSessions,
      conflicts: conflicts,
      resolutions: resolutions,
      groupedFields: const {
        'lifecycle': {'status', 'closed_at', 'deleted_at'},
      },
      immutableFields: const {'created_at'},
    );
    final mergedLogs = _mergeTable(
      dataset: dataset,
      entityType: 'log',
      idField: 'sync_id',
      baseRows: baseLogs,
      localRows: localLogs,
      remoteRows: remoteLogs,
      conflicts: conflicts,
      resolutions: resolutions,
      immutableFields: const {'created_at', 'source_device_id'},
    );

    _resolveParentSessionConflicts(
      baseSessions: baseSessions,
      localSessions: localSessions,
      remoteSessions: remoteSessions,
      baseLogs: baseLogs,
      localLogs: localLogs,
      remoteLogs: remoteLogs,
      mergedSessions: mergedSessions,
      mergedLogs: mergedLogs,
      conflicts: conflicts,
      resolutions: resolutions,
    );
    output['sessions'] = mergedSessions;
    output['logs'] = mergedLogs;
  } else {
    output['items'] = _mergeTable(
      dataset: dataset,
      entityType: 'dictionaryItem',
      idField: '_identity',
      baseRows: _dictionaryRows(base),
      localRows: _dictionaryRows(local),
      remoteRows: _dictionaryRows(remote),
      conflicts: conflicts,
      resolutions: resolutions,
      groupedFields: const {
        'state': {'origin', 'state'},
      },
    ).map((row) {
      final copy = Map<String, Object?>.from(row)..remove('_identity');
      return copy;
    }).toList(growable: false);
  }
  return PersonalCloudMergeResult(snapshot: output, conflicts: conflicts);
}

List<Map<String, Object?>> _rows(Map<String, Object?> snapshot, String key) {
  final value = snapshot[key];
  if (snapshot['version'] != 1 || value is! List) {
    throw FormatException('PERSONAL_CLOUD_INVALID_$key');
  }
  return value.map((row) {
    if (row is! Map) throw FormatException('PERSONAL_CLOUD_INVALID_$key');
    return Map<String, Object?>.from(row);
  }).toList(growable: false);
}

List<Map<String, Object?>> _dictionaryRows(Map<String, Object?> snapshot) =>
    _rows(snapshot, 'items').map((row) {
      final copy = Map<String, Object?>.from(row);
      copy['_identity'] = '${row['dictType']}\u0000${row['raw']}';
      return copy;
    }).toList(growable: false);

void _resolveParentSessionConflicts({
  required List<Map<String, Object?>> baseSessions,
  required List<Map<String, Object?>> localSessions,
  required List<Map<String, Object?>> remoteSessions,
  required List<Map<String, Object?>> baseLogs,
  required List<Map<String, Object?>> localLogs,
  required List<Map<String, Object?>> remoteLogs,
  required List<Map<String, Object?>> mergedSessions,
  required List<Map<String, Object?>> mergedLogs,
  required List<PersonalCloudMergeConflict> conflicts,
  required Map<String, PersonalCloudConflictChoice> resolutions,
}) {
  Map<String, Map<String, Object?>> sessionsById(
    List<Map<String, Object?>> rows,
  ) =>
      {
        for (final row in rows) row['session_id']?.toString() ?? '': row,
      };
  Map<String, List<Map<String, Object?>>> logsBySession(
    List<Map<String, Object?>> rows,
  ) {
    final result = <String, List<Map<String, Object?>>>{};
    for (final row in rows) {
      result
          .putIfAbsent(row['session_id']?.toString() ?? '', () => [])
          .add(row);
    }
    return result;
  }

  final baseParents = sessionsById(baseSessions);
  final localParents = sessionsById(localSessions);
  final remoteParents = sessionsById(remoteSessions);
  final baseChildren = logsBySession(baseLogs);
  final localChildren = logsBySession(localLogs);
  final remoteChildren = logsBySession(remoteLogs);
  final sessionIds = <String>{
    ...baseParents.keys,
    ...localParents.keys,
    ...remoteParents.keys,
  }.toList()
    ..sort();

  for (final sessionId in sessionIds) {
    final baseParent = baseParents[sessionId];
    final localParent = localParents[sessionId];
    final remoteParent = remoteParents[sessionId];
    if (!_isVisibleSession(baseParent)) continue;

    final localDeleted = !_isVisibleSession(localParent);
    final remoteDeleted = !_isVisibleSession(remoteParent);
    final localLogsForSession = localChildren[sessionId] ?? const [];
    final remoteLogsForSession = remoteChildren[sessionId] ?? const [];
    final baseLogsForSession = baseChildren[sessionId] ?? const [];
    final conflictExists = (localDeleted &&
            !remoteDeleted &&
            _containsActiveLogChange(
              baseLogsForSession,
              remoteLogsForSession,
            )) ||
        (remoteDeleted &&
            !localDeleted &&
            _containsActiveLogChange(
              baseLogsForSession,
              localLogsForSession,
            ));
    if (!conflictExists) continue;

    final conflict = _conflict(
      dataset: PersonalCloudDataset.records,
      entityType: 'session',
      entityId: sessionId,
      sessionId: sessionId,
      kind: 'parentDeleted',
      fieldGroup: 'logs',
      baseValue: {
        'session': baseParent,
        'logs': baseLogsForSession,
      },
      localValue: {
        'session': localParent,
        'logs': localLogsForSession,
      },
      remoteValue: {
        'session': remoteParent,
        'logs': remoteLogsForSession,
      },
    );
    final choice = resolutions[conflict.conflictId];
    if (choice == null) {
      conflicts.add(conflict);
      continue;
    }

    _replaceSessionProjection(
      sessionId: sessionId,
      selectedSession: choice == PersonalCloudConflictChoice.local
          ? localParent
          : remoteParent,
      selectedLogs: choice == PersonalCloudConflictChoice.local
          ? localLogsForSession
          : remoteLogsForSession,
      mergedSessions: mergedSessions,
      mergedLogs: mergedLogs,
    );
  }

  // A valid personal snapshot never contains a log without a session row.
  // This final guard also keeps contradictory per-conflict choices from
  // producing a payload that the server and Rust importer must reject.
  final installedSessionIds = mergedSessions
      .map((row) => row['session_id']?.toString())
      .whereType<String>()
      .toSet();
  mergedLogs.removeWhere(
    (row) => !installedSessionIds.contains(row['session_id']?.toString()),
  );
}

bool _isVisibleSession(Map<String, Object?>? session) =>
    session != null && session['deleted_at'] == null;

bool _containsActiveLogChange(
  List<Map<String, Object?>> baseRows,
  List<Map<String, Object?>> changedRows,
) {
  final base = {
    for (final row in baseRows) row['sync_id']?.toString() ?? '': row,
  };
  for (final row in changedRows) {
    if (row['deleted_at'] != null) continue;
    final id = row['sync_id']?.toString() ?? '';
    if (!_deepEqual(row, base[id])) return true;
  }
  return false;
}

void _replaceSessionProjection({
  required String sessionId,
  required Map<String, Object?>? selectedSession,
  required List<Map<String, Object?>> selectedLogs,
  required List<Map<String, Object?>> mergedSessions,
  required List<Map<String, Object?>> mergedLogs,
}) {
  mergedSessions.removeWhere(
    (row) => row['session_id']?.toString() == sessionId,
  );
  mergedLogs.removeWhere(
    (row) => row['session_id']?.toString() == sessionId,
  );
  if (selectedSession == null) return;
  mergedSessions.add(Map<String, Object?>.from(selectedSession));
  mergedLogs.addAll(selectedLogs.map(Map<String, Object?>.from));
}

List<Map<String, Object?>> _mergeTable({
  required PersonalCloudDataset dataset,
  required String entityType,
  required String idField,
  required List<Map<String, Object?>> baseRows,
  required List<Map<String, Object?>> localRows,
  required List<Map<String, Object?>> remoteRows,
  required List<PersonalCloudMergeConflict> conflicts,
  required Map<String, PersonalCloudConflictChoice> resolutions,
  Map<String, Set<String>> groupedFields = const {},
  Set<String> immutableFields = const {},
}) {
  Map<String, Map<String, Object?>> index(List<Map<String, Object?>> rows) => {
        for (final row in rows) row[idField]?.toString() ?? '': row,
      };
  final base = index(baseRows);
  final local = index(localRows);
  final remote = index(remoteRows);
  final ids = <String>{...base.keys, ...local.keys, ...remote.keys}.toList()
    ..sort();
  final result = <Map<String, Object?>>[];

  for (final id in ids) {
    final baseRow = base[id];
    final localRow = local[id];
    final remoteRow = remote[id];
    final sessionId =
        (localRow ?? remoteRow ?? baseRow)?['session_id']?.toString();

    if (baseRow == null) {
      if (localRow == null ||
          remoteRow == null ||
          _deepEqual(localRow, remoteRow)) {
        final row = localRow ?? remoteRow;
        if (row != null) result.add(Map<String, Object?>.from(row));
        continue;
      }
      final conflict = _conflict(
        dataset: dataset,
        entityType: entityType,
        entityId: id,
        sessionId: sessionId,
        kind: 'concurrentCreate',
        baseValue: null,
        localValue: localRow,
        remoteValue: remoteRow,
      );
      final choice = resolutions[conflict.conflictId];
      if (choice == null) conflicts.add(conflict);
      result.add(Map<String, Object?>.from(
        choice == PersonalCloudConflictChoice.remote ? remoteRow : localRow,
      ));
      continue;
    }

    if (localRow == null || remoteRow == null) {
      final survivor = localRow ?? remoteRow;
      if (survivor == null || _deepEqual(survivor, baseRow)) continue;
      final conflict = _conflict(
        dataset: dataset,
        entityType: entityType,
        entityId: id,
        sessionId: sessionId,
        kind: 'deleteVsEdit',
        baseValue: baseRow,
        localValue: localRow,
        remoteValue: remoteRow,
      );
      final choice = resolutions[conflict.conflictId];
      if (choice == null) conflicts.add(conflict);
      final selected =
          choice == PersonalCloudConflictChoice.remote ? remoteRow : localRow;
      if (selected != null) result.add(Map<String, Object?>.from(selected));
      continue;
    }

    if (_deleteVsEdit(baseRow, localRow, remoteRow)) {
      final conflict = _conflict(
        dataset: dataset,
        entityType: entityType,
        entityId: id,
        sessionId: sessionId,
        kind: 'deleteVsEdit',
        fieldGroup: 'deletion',
        baseValue: baseRow,
        localValue: localRow,
        remoteValue: remoteRow,
      );
      final choice = resolutions[conflict.conflictId];
      if (choice == null) conflicts.add(conflict);
      result.add(Map<String, Object?>.from(
        choice == PersonalCloudConflictChoice.remote ? remoteRow : localRow,
      ));
      continue;
    }

    final merged = Map<String, Object?>.from(baseRow);
    final consumed = <String>{idField, 'updated_at'};
    for (final entry in groupedFields.entries) {
      consumed.addAll(entry.value);
      final baseValue = {
        for (final field in entry.value) field: baseRow[field]
      };
      final localValue = {
        for (final field in entry.value) field: localRow[field]
      };
      final remoteValue = {
        for (final field in entry.value) field: remoteRow[field]
      };
      final value = _mergeValue(
        dataset: dataset,
        entityType: entityType,
        entityId: id,
        sessionId: sessionId,
        fieldGroup: entry.key,
        baseValue: baseValue,
        localValue: localValue,
        remoteValue: remoteValue,
        conflicts: conflicts,
        resolutions: resolutions,
      );
      for (final field in entry.value) {
        merged[field] = (value as Map<String, Object?>)[field];
      }
    }
    final fields = <String>{
      ...baseRow.keys,
      ...localRow.keys,
      ...remoteRow.keys
    }..removeAll(consumed);
    for (final field in fields) {
      merged[field] = _mergeValue(
        dataset: dataset,
        entityType: entityType,
        entityId: id,
        sessionId: sessionId,
        fieldGroup:
            immutableFields.contains(field) ? 'immutable:$field' : field,
        baseValue: baseRow[field],
        localValue: localRow[field],
        remoteValue: remoteRow[field],
        conflicts: conflicts,
        resolutions: resolutions,
      );
    }
    if (baseRow.containsKey('updated_at')) {
      merged['updated_at'] = _latestTimestamp(
        [
          baseRow['updated_at'],
          localRow['updated_at'],
          remoteRow['updated_at']
        ],
      );
    }
    result.add(merged);
  }
  return result;
}

Object? _mergeValue({
  required PersonalCloudDataset dataset,
  required String entityType,
  required String entityId,
  required String? sessionId,
  required String fieldGroup,
  required Object? baseValue,
  required Object? localValue,
  required Object? remoteValue,
  required List<PersonalCloudMergeConflict> conflicts,
  required Map<String, PersonalCloudConflictChoice> resolutions,
}) {
  if (_deepEqual(localValue, remoteValue)) return localValue;
  if (_deepEqual(localValue, baseValue)) return remoteValue;
  if (_deepEqual(remoteValue, baseValue)) return localValue;
  final conflict = _conflict(
    dataset: dataset,
    entityType: entityType,
    entityId: entityId,
    sessionId: sessionId,
    kind: 'concurrentEdit',
    fieldGroup: fieldGroup,
    baseValue: baseValue,
    localValue: localValue,
    remoteValue: remoteValue,
  );
  final choice = resolutions[conflict.conflictId];
  if (choice == null) conflicts.add(conflict);
  return choice == PersonalCloudConflictChoice.remote
      ? remoteValue
      : localValue;
}

bool _deleteVsEdit(
  Map<String, Object?> base,
  Map<String, Object?> local,
  Map<String, Object?> remote,
) {
  bool deleted(Map<String, Object?> row) =>
      row['deleted_at'] != null || row['state'] == 'deleted';
  final baseDeleted = deleted(base);
  final localDeleted = deleted(local);
  final remoteDeleted = deleted(remote);
  if (baseDeleted || localDeleted == remoteDeleted) return false;
  final edited = localDeleted ? remote : local;
  final ignored = {'deleted_at', 'state', 'updated_at'};
  return edited.keys.any(
    (field) =>
        !ignored.contains(field) && !_deepEqual(edited[field], base[field]),
  );
}

PersonalCloudMergeConflict _conflict({
  required PersonalCloudDataset dataset,
  required String entityType,
  required String entityId,
  required String kind,
  String? sessionId,
  String? fieldGroup,
  Object? baseValue,
  Object? localValue,
  Object? remoteValue,
}) {
  final suffix = fieldGroup ?? kind;
  return PersonalCloudMergeConflict(
    dataset: dataset,
    conflictId: '${dataset.name}:$entityType:$entityId:$suffix',
    entityType: entityType,
    entityId: entityId,
    sessionId: sessionId,
    kind: kind,
    fieldGroup: fieldGroup,
    basePresent: baseValue != null,
    localPresent: localValue != null,
    remotePresent: remoteValue != null,
    baseValue: baseValue,
    localValue: localValue,
    remoteValue: remoteValue,
  );
}

Object? _latestTimestamp(List<Object?> values) {
  String? selected;
  DateTime? latest;
  for (final value in values.whereType<String>()) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null && (latest == null || parsed.isAfter(latest))) {
      latest = parsed;
      selected = value;
    }
  }
  return selected ?? values.whereType<String>().firstOrNull;
}

bool _deepEqual(Object? left, Object? right) {
  if (identical(left, right) || left == right) return true;
  if (left is Map && right is Map) {
    if (left.length != right.length) return false;
    for (final key in left.keys) {
      if (!right.containsKey(key) || !_deepEqual(left[key], right[key])) {
        return false;
      }
    }
    return true;
  }
  if (left is List && right is List) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index += 1) {
      if (!_deepEqual(left[index], right[index])) return false;
    }
    return true;
  }
  return false;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

String canonicalPersonalCloudSnapshot(Map<String, Object?> snapshot) {
  Object? canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return {for (final key in keys) key: canonical(value[key])};
    }
    if (value is List) return value.map(canonical).toList(growable: false);
    return value;
  }

  return jsonEncode(canonical(snapshot));
}
