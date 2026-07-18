import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';
import 'package:openlogtool/models/dictionary_item.dart';
import 'package:openlogtool/models/log_entry.dart';
import 'package:openlogtool/models/session.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;
  static Future<Database>? _databaseInitFuture;

  static const String _databaseName = 'openlogtool.db';
  static const String _logsTable = 'logs';
  static const String _historyTable = 'history';
  static const String _sessionsTable = 'sessions';
  static const List<String> _dictionaryTables = <String>[
    'device_dictionary',
    'antenna_dictionary',
    'qth_dictionary',
    'callsign_dictionary',
  ];

  /// Whitelist of tables that may receive ALTER TABLE / CREATE INDEX
  /// statements via helper methods. DDL cannot be parameterized, so we
  /// gate the names here instead of allowing arbitrary interpolation.
  static const Set<String> _allowedDdlTables = <String>{
    _logsTable,
    _historyTable,
    _sessionsTable,
    'device_dictionary',
    'antenna_dictionary',
    'qth_dictionary',
    'callsign_dictionary',
  };

  static final RegExp _identifierRegExp = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

  static void _assertSafeIdentifier(String value, String kind) {
    if (!_identifierRegExp.hasMatch(value)) {
      throw ArgumentError('Invalid $kind: $value');
    }
  }

  static void _assertKnownTable(String tableName) {
    if (!_allowedDdlTables.contains(tableName)) {
      throw ArgumentError('Unknown table for DDL: $tableName');
    }
  }

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  Future<Database> get database {
    if (_database != null) {
      return Future.value(_database!);
    }
    // Single-flight: concurrent get-calls share the same init future.
    return _databaseInitFuture ??= _initDatabase().then((db) {
      _database = db;
      _databaseInitFuture = null;
      return db;
    });
  }

  Future<Database> _initDatabase() async {
    String dbPath;
    if (kIsWeb) {
      dbPath = _databaseName;
    } else {
      final documentsDirectory = await getApplicationDocumentsDirectory();
      dbPath = p.join(documentsDirectory.path, _databaseName);
    }

    return openDatabase(
      dbPath,
      version: 1,
      onCreate: _onCreate,
      onOpen: _onOpen,
    );
  }

  Future<void> _onOpen(Database db) async {
    await _ensureDictionaryTablesExist(db);
    await _ensureHistoryTableExists(db);
    await _ensureLogsTableExists(db);
    await _ensureSessionsTableExists(db);
    await _migrateSyncSchema(db);
    await _migrateHistoryToSessions(db);

    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM device_dictionary'),
    );
    if (count == null || count == 0) {
      await _loadInitialDictionaries(db);
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await _createLogsTable(db);
    await _createDictionaryTable(db, 'device_dictionary');
    await _createDictionaryTable(db, 'antenna_dictionary');
    await _createDictionaryTable(db, 'qth_dictionary');
    await _createDictionaryTable(db, 'callsign_dictionary');
    await _createHistoryTable(db);
    await _createSessionsTable(db);
    await _loadInitialDictionaries(db);
  }

  Future<void> _ensureLogsTableExists(Database db) async {
    await _createLogsTable(db, ifNotExists: true);
  }

  Future<void> _ensureDictionaryTablesExist(Database db) async {
    for (final tableName in _dictionaryTables) {
      await _createDictionaryTable(db, tableName, ifNotExists: true);
    }
  }

  Future<void> _ensureHistoryTableExists(Database db) async {
    await _createHistoryTable(db, ifNotExists: true);
  }

  Future<void> _ensureSessionsTableExists(Database db) async {
    await _createSessionsTable(db, ifNotExists: true);
  }

  Future<void> _createLogsTable(Database db, {bool ifNotExists = false}) async {
    await db.execute('''
      CREATE TABLE ${ifNotExists ? 'IF NOT EXISTS ' : ''}$_logsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sync_id TEXT UNIQUE,
        time TEXT NOT NULL,
        controller TEXT NOT NULL,
        callsign TEXT NOT NULL,
        report TEXT,
        qth TEXT,
        device TEXT,
        power TEXT,
        antenna TEXT,
        height TEXT,
        created_at TEXT,
        updated_at TEXT,
        deleted_at TEXT,
        source_device_id TEXT
      )
    ''');
    if (!ifNotExists) {
      await _ensureUniqueIndex(db, 'idx_logs_sync_id', _logsTable, 'sync_id');
    }
  }

  Future<void> _createDictionaryTable(
    Database db,
    String tableName, {
    bool ifNotExists = false,
  }) async {
    await db.execute('''
      CREATE TABLE ${ifNotExists ? 'IF NOT EXISTS ' : ''}$tableName (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        raw TEXT NOT NULL UNIQUE,
        pinyin TEXT,
        abbreviation TEXT,
        sync_id TEXT UNIQUE,
        type TEXT,
        created_at TEXT,
        updated_at TEXT,
        deleted_at TEXT,
        source_device_id TEXT
      )
    ''');
    if (!ifNotExists) {
      await _ensureUniqueIndex(
          db, 'idx_${tableName}_sync_id', tableName, 'sync_id');
    }
  }

  Future<void> _createHistoryTable(Database db,
      {bool ifNotExists = false}) async {
    await db.execute('''
      CREATE TABLE ${ifNotExists ? 'IF NOT EXISTS ' : ''}$_historyTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sync_id TEXT UNIQUE,
        name TEXT NOT NULL,
        logs_data TEXT NOT NULL,
        log_count INTEGER NOT NULL,
        created_at TEXT,
        updated_at TEXT,
        deleted_at TEXT,
        source_device_id TEXT
      )
    ''');
    if (!ifNotExists) {
      await _ensureUniqueIndex(
          db, 'idx_history_sync_id', _historyTable, 'sync_id');
    }
  }

  Future<void> _createSessionsTable(Database db,
      {bool ifNotExists = false}) async {
    await db.execute('''
      CREATE TABLE ${ifNotExists ? 'IF NOT EXISTS ' : ''}$_sessionsTable (
        session_id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'active',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        closed_at TEXT,
        deleted_at TEXT,
        source_device_id TEXT
      )
    ''');
    if (!ifNotExists) {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sessions_status ON $_sessionsTable(status)',
      );
    }
  }

  Future<void> _migrateSyncSchema(Database db) async {
    await _migrateLogsTable(db);
    for (final tableName in _dictionaryTables) {
      await _migrateDictionaryTable(db, tableName);
    }
    await _migrateHistoryTable(db);
  }

  Future<void> _migrateLogsTable(Database db) async {
    await _ensureColumn(db, _logsTable, 'sync_id', 'TEXT');
    await _ensureColumn(db, _logsTable, 'created_at', 'TEXT');
    await _ensureColumn(db, _logsTable, 'updated_at', 'TEXT');
    await _ensureColumn(db, _logsTable, 'deleted_at', 'TEXT');
    await _ensureColumn(db, _logsTable, 'source_device_id', 'TEXT');
    await _ensureColumn(db, _logsTable, 'session_id', 'TEXT');
    await _repairDuplicateSyncIds(db, _logsTable, 'log');
    await _ensureUniqueIndex(db, 'idx_logs_sync_id', _logsTable, 'sync_id');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_logs_session_id ON $_logsTable(session_id)',
    );

    final rows = await db.query(
      _logsTable,
      columns: <String>['id', 'time', 'sync_id', 'created_at', 'updated_at'],
    );
    final batch = db.batch();
    for (final row in rows) {
      final logId = row['id'];
      if (logId == null) {
        continue;
      }
      final fallbackTime = _stringOrNull(row['time']);
      final createdAt =
          _stringOrNull(row['created_at']) ?? _legacyTimestamp(fallbackTime);
      final updates = <String, Object?>{};

      if (_isBlank(row['sync_id'])) {
        updates['sync_id'] = _generateSyncId('log');
      }
      if (_isBlank(row['created_at'])) {
        updates['created_at'] = createdAt;
      }
      if (_isBlank(row['updated_at'])) {
        updates['updated_at'] = _stringOrNull(row['updated_at']) ?? createdAt;
      }

      if (updates.isNotEmpty) {
        batch.update(_logsTable, updates,
            where: 'id = ?', whereArgs: <Object?>[logId]);
      }
    }
    await batch.commit(noResult: true);
  }

  Future<void> _migrateDictionaryTable(Database db, String tableName) async {
    await _ensureColumn(db, tableName, 'sync_id', 'TEXT');
    await _ensureColumn(db, tableName, 'type', 'TEXT');
    await _ensureColumn(db, tableName, 'created_at', 'TEXT');
    await _ensureColumn(db, tableName, 'updated_at', 'TEXT');
    await _ensureColumn(db, tableName, 'deleted_at', 'TEXT');
    await _ensureColumn(db, tableName, 'source_device_id', 'TEXT');
    await _repairDuplicateSyncIds(
        db, tableName, _dictionaryTypeForTable(tableName));
    await _ensureUniqueIndex(
        db, 'idx_${tableName}_sync_id', tableName, 'sync_id');

    final dictionaryType = _dictionaryTypeForTable(tableName);
    final rows = await db.query(
      tableName,
      columns: <String>['id', 'sync_id', 'type', 'created_at', 'updated_at'],
    );
    final batch = db.batch();
    for (final row in rows) {
      final localId = row['id'];
      if (localId == null) {
        continue;
      }
      final createdAt = _stringOrNull(row['created_at']) ?? _now();
      final updates = <String, Object?>{};

      if (_isBlank(row['sync_id'])) {
        updates['sync_id'] = _generateSyncId(dictionaryType);
      }
      if (_isBlank(row['type'])) {
        updates['type'] = dictionaryType;
      }
      if (_isBlank(row['created_at'])) {
        updates['created_at'] = createdAt;
      }
      if (_isBlank(row['updated_at'])) {
        updates['updated_at'] = _stringOrNull(row['updated_at']) ?? createdAt;
      }

      if (updates.isNotEmpty) {
        batch.update(tableName, updates,
            where: 'id = ?', whereArgs: <Object?>[localId]);
      }
    }
    await batch.commit(noResult: true);
  }

  Future<void> _migrateHistoryTable(Database db) async {
    await _ensureColumn(db, _historyTable, 'sync_id', 'TEXT');
    await _ensureColumn(db, _historyTable, 'created_at', 'TEXT');
    await _ensureColumn(db, _historyTable, 'updated_at', 'TEXT');
    await _ensureColumn(db, _historyTable, 'deleted_at', 'TEXT');
    await _ensureColumn(db, _historyTable, 'source_device_id', 'TEXT');
    await _repairDuplicateSyncIds(db, _historyTable, 'history');
    await _ensureUniqueIndex(
        db, 'idx_history_sync_id', _historyTable, 'sync_id');

    final rows = await db.query(
      _historyTable,
      columns: <String>['id', 'sync_id', 'created_at', 'updated_at'],
    );
    final batch = db.batch();
    for (final row in rows) {
      final localId = row['id'];
      if (localId == null) {
        continue;
      }
      final createdAt = _stringOrNull(row['created_at']) ?? _now();
      final updates = <String, Object?>{};

      if (_isBlank(row['sync_id'])) {
        updates['sync_id'] = _generateSyncId('history');
      }
      if (_isBlank(row['created_at'])) {
        updates['created_at'] = createdAt;
      }
      if (_isBlank(row['updated_at'])) {
        updates['updated_at'] = _stringOrNull(row['updated_at']) ?? createdAt;
      }

      if (updates.isNotEmpty) {
        batch.update(_historyTable, updates,
            where: 'id = ?', whereArgs: <Object?>[localId]);
      }
    }
    await batch.commit(noResult: true);
  }

  Future<void> _migrateHistoryToSessions(Database db) async {
    final count = Sqflite.firstIntValue(
      await db.rawQuery("SELECT COUNT(*) FROM $_sessionsTable"),
    );
    if (count != null && count > 0) return;

    final histories = await db.query(_historyTable);

    for (final h in histories) {
      final syncId = h['sync_id']?.toString();
      if (syncId == null) continue;

      final sessionId = Session.migrationSessionId(syncId);
      final name = h['name']?.toString() ?? '未命名记录';

      await db.insert(_sessionsTable, {
        'session_id': sessionId,
        'title': name,
        'status': 'closed',
        'created_at':
            h['created_at'] ?? DateTime.now().toUtc().toIso8601String(),
        'updated_at': h['updated_at'] ??
            h['created_at'] ??
            DateTime.now().toUtc().toIso8601String(),
        'closed_at':
            h['created_at'] ?? DateTime.now().toUtc().toIso8601String(),
      });
    }
  }

  Future<void> _ensureColumn(
    Database db,
    String tableName,
    String columnName,
    String definition,
  ) async {
    _assertKnownTable(tableName);
    _assertSafeIdentifier(columnName, 'column name');
    final columns = await _getExistingColumns(db, tableName);
    if (columns.contains(columnName)) {
      return;
    }
    await db
        .execute('ALTER TABLE $tableName ADD COLUMN $columnName $definition');
  }

  Future<Set<String>> _getExistingColumns(Database db, String tableName) async {
    _assertKnownTable(tableName);
    final result = await db.rawQuery('PRAGMA table_info($tableName)');
    return result.map((row) => row['name'].toString()).toSet();
  }

  Future<void> _ensureUniqueIndex(
    Database db,
    String indexName,
    String tableName,
    String columnName,
  ) async {
    _assertKnownTable(tableName);
    _assertSafeIdentifier(indexName, 'index name');
    _assertSafeIdentifier(columnName, 'column name');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS $indexName ON $tableName($columnName)',
    );
  }

  Future<void> _repairDuplicateSyncIds(
      Database db, String tableName, String prefix) async {
    final duplicates = await db.rawQuery(
      '''
      SELECT sync_id
      FROM $tableName
      WHERE sync_id IS NOT NULL AND TRIM(sync_id) != ''
      GROUP BY sync_id
      HAVING COUNT(*) > 1
      ''',
    );

    for (final duplicate in duplicates) {
      final syncId = duplicate['sync_id']?.toString();
      if (syncId == null || syncId.trim().isEmpty) {
        continue;
      }

      final rows = await db.query(
        tableName,
        columns: <String>['id'],
        where: 'sync_id = ?',
        whereArgs: <Object?>[syncId],
        orderBy: 'id ASC',
      );

      if (rows.length <= 1) {
        continue;
      }

      final batch = db.batch();
      for (final row in rows.skip(1)) {
        final localId = row['id'];
        if (localId == null) {
          continue;
        }
        batch.update(
          tableName,
          <String, Object?>{'sync_id': _generateSyncId(prefix)},
          where: 'id = ?',
          whereArgs: <Object?>[localId],
        );
      }
      await batch.commit(noResult: true);
    }
  }

  Future<void> _loadInitialDictionaries(Database db) async {
    await _loadDictionaryFromAsset(
        db, 'assets/dictionaries/antenna.json', 'antenna_dictionary');
    await _loadDictionaryFromAsset(
        db, 'assets/dictionaries/device.json', 'device_dictionary');
    await _loadDictionaryFromAsset(
        db, 'assets/dictionaries/qth.json', 'qth_dictionary');
  }

  Future<void> loadInitialDictionaries() async {
    final db = await database;
    await _loadInitialDictionaries(db);
  }

  Future<void> _loadDictionaryFromAsset(
      Database db, String assetPath, String tableName) async {
    try {
      final String jsonString = await rootBundle.loadString(assetPath);
      final List<dynamic> jsonList = json.decode(jsonString) as List<dynamic>;

      final batch = db.batch();
      for (final item in jsonList) {
        final row = _buildDictionaryRow(
          tableName,
          Map<String, dynamic>.from(item as Map),
        );
        batch.insert(
          tableName,
          row,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      await batch.commit(noResult: true);
    } catch (_) {
      // Asset file doesn't exist or can't be loaded, skip.
    }
  }

  Map<String, dynamic> _buildLogRow(LogEntry log) {
    final createdAt = _legacyTimestamp(log.createdAt);
    final updatedAt =
        _legacyTimestamp(log.updatedAt.isNotEmpty ? log.updatedAt : createdAt);
    return <String, dynamic>{
      'sync_id': log.id,
      'time': log.time,
      'controller': log.controller,
      'callsign': log.callsign,
      'report': log.report,
      'qth': log.qth,
      'device': log.device,
      'power': log.power,
      'antenna': log.antenna,
      'height': log.height,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'deleted_at': log.deletedAt,
      'source_device_id': _stringOrNull(log.sourceDeviceId),
      'session_id': log.sessionId,
    };
  }

  Map<String, dynamic> _buildDictionaryRow(
      String tableName, Map<String, dynamic> item) {
    final createdAt = _legacyTimestamp(
        _stringOrNull(item['created_at'] ?? item['createdAt']));
    final updatedAt = _legacyTimestamp(
        _stringOrNull(item['updated_at'] ?? item['updatedAt']) ?? createdAt);
    final row = <String, dynamic>{
      'raw': item['raw']?.toString() ?? '',
      'pinyin': item['pinyin']?.toString() ?? '',
      'abbreviation': item['abbreviation']?.toString() ?? '',
      'sync_id': _stringOrNull(item['sync_id'] ?? item['syncId']) ??
          _generateSyncId(_dictionaryTypeForTable(tableName)),
      'type': _stringOrNull(item['type']) ?? _dictionaryTypeForTable(tableName),
      'created_at': createdAt,
      'updated_at': updatedAt,
      'deleted_at': _stringOrNull(item['deleted_at'] ?? item['deletedAt']),
      'source_device_id':
          _stringOrNull(item['source_device_id'] ?? item['sourceDeviceId']),
    };

    final localId = item['id'];
    if (localId is int) {
      row['id'] = localId;
    }
    return row;
  }

  String _dictionaryTypeForTable(String tableName) {
    switch (tableName) {
      case 'device_dictionary':
        return 'device';
      case 'antenna_dictionary':
        return 'antenna';
      case 'qth_dictionary':
        return 'qth';
      case 'callsign_dictionary':
        return 'callsign';
      default:
        return tableName;
    }
  }

  String _generateSyncId(String prefix) {
    final random = Random.secure();
    final suffix = List<String>.generate(
      4,
      (_) => random.nextInt(1 << 16).toRadixString(16).padLeft(4, '0'),
    ).join();
    return '$prefix-${DateTime.now().toUtc().microsecondsSinceEpoch}-$suffix';
  }

  String _now() => DateTime.now().toUtc().toIso8601String();

  DateTime? _parseTimestamp(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return DateTime.tryParse(normalized)?.toUtc();
  }

  String _legacyTimestamp(String? value) {
    final normalized = value?.trim();
    if (normalized != null && normalized.isNotEmpty) {
      final parsed = DateTime.tryParse(normalized);
      if (parsed != null) {
        return parsed.toUtc().toIso8601String();
      }
    }
    return _now();
  }

  String? _stringOrNull(dynamic value) {
    if (value == null) {
      return null;
    }
    final normalized = value.toString().trim();
    return normalized.isEmpty ? null : normalized;
  }

  bool _isBlank(dynamic value) => _stringOrNull(value) == null;

  int? _intOrNull(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  bool _shouldApplyDeletedAt(
      dynamic existingDeletedAt, String incomingDeletedAt) {
    final existing = _parseTimestamp(_stringOrNull(existingDeletedAt));
    final incoming = _parseTimestamp(incomingDeletedAt);
    if (incoming == null) {
      return false;
    }
    if (existing == null) {
      return true;
    }
    return incoming.isAfter(existing);
  }

  DateTime? _latestVersionTimestamp({dynamic updatedAt, dynamic deletedAt}) {
    final updated = _parseTimestamp(_stringOrNull(updatedAt));
    final deleted = _parseTimestamp(_stringOrNull(deletedAt));
    if (updated == null) {
      return deleted;
    }
    if (deleted == null) {
      return updated;
    }
    return updated.isAfter(deleted) ? updated : deleted;
  }

  void _assertDictionaryTable(String tableName) {
    if (!_dictionaryTables.contains(tableName)) {
      throw ArgumentError('Unsupported dictionary table: $tableName');
    }
  }

  Map<String, dynamic> _buildHistoryRow(Map<String, dynamic> item) {
    final createdAtInput =
        _stringOrNull(item['created_at'] ?? item['createdAt']);
    final createdAt = _legacyTimestamp(createdAtInput);
    final updatedAt = _legacyTimestamp(
      _stringOrNull(item['updated_at'] ?? item['updatedAt']) ?? createdAt,
    );
    return <String, dynamic>{
      'sync_id': _stringOrNull(item['sync_id'] ?? item['syncId']) ??
          _generateSyncId('history'),
      'name': item['name']?.toString() ?? '',
      'logs_data':
          item['logs_data']?.toString() ?? item['logsData']?.toString() ?? '[]',
      'log_count': _intOrNull(item['log_count'] ?? item['logCount']) ?? 0,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'deleted_at': _stringOrNull(item['deleted_at'] ?? item['deletedAt']),
      'source_device_id':
          _stringOrNull(item['source_device_id'] ?? item['sourceDeviceId']),
    };
  }

  Future<void> _upsertSyncRow({
    required String tableName,
    required String syncId,
    required Map<String, dynamic> incomingRow,
  }) async {
    final db = await database;
    final existingRows = await db.query(
      tableName,
      columns: <String>['id', 'updated_at', 'deleted_at'],
      where: 'sync_id = ?',
      whereArgs: <Object?>[syncId],
      limit: 1,
    );

    if (existingRows.isEmpty) {
      await db.insert(tableName, incomingRow);
      return;
    }

    final existingVersion = _latestVersionTimestamp(
      updatedAt: existingRows.first['updated_at'],
      deletedAt: existingRows.first['deleted_at'],
    );
    final incomingVersion = _latestVersionTimestamp(
      updatedAt: incomingRow['updated_at'],
      deletedAt: incomingRow['deleted_at'],
    );

    if (incomingVersion != null &&
        (existingVersion == null || incomingVersion.isAfter(existingVersion))) {
      await db.update(
        tableName,
        incomingRow,
        where: 'sync_id = ?',
        whereArgs: <Object?>[syncId],
      );
    }
  }

  Future<void> _softDeleteBySyncId(
      String tableName, String syncId, String deletedAt) async {
    final db = await database;
    final normalizedDeletedAt = _legacyTimestamp(deletedAt);
    final existingRows = await db.query(
      tableName,
      columns: <String>['deleted_at'],
      where: 'sync_id = ?',
      whereArgs: <Object?>[syncId],
      limit: 1,
    );

    if (existingRows.isEmpty ||
        !_shouldApplyDeletedAt(
            existingRows.first['deleted_at'], normalizedDeletedAt)) {
      return;
    }

    await db.update(
      tableName,
      <String, dynamic>{'deleted_at': normalizedDeletedAt},
      where: 'sync_id = ?',
      whereArgs: <Object?>[syncId],
    );
  }

  // Log operations
  Future<int> insertLog(LogEntry log) async {
    final db = await database;
    final row = _buildLogRow(log);
    final existingRows = await db.query(
      _logsTable,
      columns: <String>['id', 'created_at'],
      where: 'sync_id = ?',
      whereArgs: <Object?>[row['sync_id']],
      limit: 1,
    );

    if (existingRows.isEmpty) {
      return db.insert(_logsTable, row);
    }

    final localId = existingRows.first['id'] as int;
    await db.update(
      _logsTable,
      <String, dynamic>{
        ...row,
        'created_at': _stringOrNull(existingRows.first['created_at']) ??
            row['created_at'],
        'deleted_at': null,
      },
      where: 'id = ?',
      whereArgs: <Object?>[localId],
    );
    return localId;
  }

  Future<LogEntry?> getLogByLocalId(int id) async {
    final db = await database;
    final rows = await db.query(
      _logsTable,
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return LogEntry.fromMap(rows.first);
  }

  Future<List<LogEntry>> getAllLogs() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(_logsTable);
    return List<LogEntry>.generate(
        maps.length, (int i) => LogEntry.fromMap(maps[i]));
  }

  Future<List<LogEntry>> getVisibleLogs([String? sessionId]) async {
    final db = await database;
    final maps = sessionId != null
        // Show logs explicitly tagged with this session AND orphan logs
        // (session_id IS NULL) so legacy / unbound rows are still reachable
        // from the active session view instead of vanishing.
        ? await db.query(
            _logsTable,
            where:
                'deleted_at IS NULL AND (session_id = ? OR session_id IS NULL)',
            whereArgs: [sessionId],
            orderBy: 'id ASC',
          )
        : await db.query(
            _logsTable,
            where: 'deleted_at IS NULL',
            orderBy: 'id ASC',
          );
    return List<LogEntry>.generate(
        maps.length, (int i) => LogEntry.fromMap(maps[i]));
  }

  Future<int> updateLog(int id, LogEntry log) async {
    final db = await database;
    String? preservedSyncId;
    String? preservedCreatedAt;
    final existingRows = await db.query(
      _logsTable,
      columns: <String>['sync_id', 'created_at'],
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (existingRows.isNotEmpty) {
      preservedSyncId = _stringOrNull(existingRows.first['sync_id']);
      preservedCreatedAt = _stringOrNull(existingRows.first['created_at']);
    }
    final updateRow = _buildLogRow(log);
    return db.update(
      _logsTable,
      <String, dynamic>{
        ...updateRow,
        'sync_id': log.hasExplicitSyncId ? log.id : (preservedSyncId ?? log.id),
        'created_at': preservedCreatedAt ?? updateRow['created_at'],
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<int> deleteLog(int id) async {
    final db = await database;
    final deletedAt = _now();
    return db.update(
      _logsTable,
      <String, dynamic>{'deleted_at': deletedAt},
      where: 'id = ? AND (deleted_at IS NULL OR deleted_at < ?)',
      whereArgs: <Object?>[id, deletedAt],
    );
  }

  Future<void> deleteAllLogs() async {
    final db = await database;
    await db.update(
      _logsTable,
      <String, dynamic>{'deleted_at': _now()},
      where: 'deleted_at IS NULL',
    );
  }

  Future<List<Map<String, dynamic>>> getLogsChangedSince(String since) async {
    final db = await database;
    return db.query(
      _logsTable,
      where: 'updated_at > ? OR deleted_at > ?',
      whereArgs: <Object?>[since, since],
      orderBy: 'updated_at ASC, deleted_at ASC',
    );
  }

  Future<void> upsertLogFromSync(Map<String, dynamic> data) async {
    final log = LogEntry.fromJson(data);
    final row = _buildLogRow(log);
    final syncId =
        _stringOrNull(data['id'] ?? data['sync_id'] ?? row['sync_id']);
    if (syncId == null) {
      return;
    }

    await _upsertSyncRow(
      tableName: _logsTable,
      syncId: syncId,
      incomingRow: <String, dynamic>{...row, 'sync_id': syncId},
    );
  }

  Future<void> softDeleteLog(String syncId, String deletedAt) async {
    await _softDeleteBySyncId(_logsTable, syncId, deletedAt);
  }

  Future<void> importLogs(List<LogEntry> logs) async {
    final db = await database;
    final batch = db.batch();
    for (final log in logs) {
      batch.insert(_logsTable, _buildLogRow(log));
    }
    await batch.commit(noResult: true);
  }

  // Dictionary operations
  Future<List<Map<String, dynamic>>> getDictionary(String tableName) async {
    _assertDictionaryTable(tableName);
    final db = await database;
    return db.query(tableName, orderBy: 'raw ASC');
  }

  Future<List<String>> getDictionaryRaw(String tableName) async {
    _assertDictionaryTable(tableName);
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      tableName,
      where: 'deleted_at IS NULL',
      orderBy: 'raw ASC',
    );
    final result = <String>[];
    for (final m in maps) {
      final raw = _stringOrNull(m['raw']);
      if (raw != null) result.add(raw);
    }
    return result;
  }

  Future<List<DictionaryItem>> getDictionaryItems(String tableName) async {
    _assertDictionaryTable(tableName);
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      tableName,
      where: 'deleted_at IS NULL',
      orderBy: 'raw ASC',
    );
    return maps
        .map(
          (Map<String, dynamic> m) => DictionaryItem.fromMap(<String, dynamic>{
            ...m,
            'type': m['type'] ?? _dictionaryTypeForTable(tableName),
          }),
        )
        .toList();
  }

  Future<DictionaryItem?> getDictionaryItemByRaw(
      String tableName, String raw) async {
    _assertDictionaryTable(tableName);
    final db = await database;
    final rows = await db.query(
      tableName,
      where: 'raw = ? AND deleted_at IS NULL',
      whereArgs: <Object?>[raw],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return DictionaryItem.fromMap(<String, dynamic>{
      ...rows.first,
      'type': rows.first['type'] ?? _dictionaryTypeForTable(tableName),
    });
  }

  Future<int> insertDictionaryItem(
      String tableName, Map<String, dynamic> item) async {
    _assertDictionaryTable(tableName);
    final db = await database;
    final row = _buildDictionaryRow(tableName, item);
    final existingRows = await db.query(
      tableName,
      columns: <String>['id', 'sync_id', 'created_at'],
      where: 'raw = ?',
      whereArgs: <Object?>[row['raw']],
      limit: 1,
    );

    if (existingRows.isEmpty) {
      return db.insert(
        tableName,
        row,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    final localId = existingRows.first['id'] as int;
    await db.update(
      tableName,
      <String, dynamic>{
        ...row,
        'sync_id':
            _stringOrNull(existingRows.first['sync_id']) ?? row['sync_id'],
        'created_at': _stringOrNull(existingRows.first['created_at']) ??
            row['created_at'],
        'updated_at': _now(),
        'deleted_at': null,
      },
      where: 'id = ?',
      whereArgs: <Object?>[localId],
    );
    return localId;
  }

  Future<void> importDictionaryItems(
      String tableName, List<Map<String, dynamic>> items) async {
    final db = await database;
    final batch = db.batch();
    for (final item in items) {
      batch.insert(
        tableName,
        _buildDictionaryRow(tableName, item),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<int> deleteDictionaryItem(String tableName, int id) async {
    _assertDictionaryTable(tableName);
    final db = await database;
    final now = _now();
    return db.update(
      tableName,
      <String, dynamic>{'deleted_at': now, 'updated_at': now},
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> clearDictionary(String tableName) async {
    _assertDictionaryTable(tableName);
    final db = await database;
    final now = _now();
    await db.update(
      tableName,
      <String, dynamic>{'deleted_at': now, 'updated_at': now},
      where: 'deleted_at IS NULL',
    );
  }

  Future<List<Map<String, dynamic>>> getDictionaryChangedSince(
      String tableName, String since) async {
    _assertDictionaryTable(tableName);
    final db = await database;
    return db.query(
      tableName,
      where: 'updated_at > ? OR deleted_at > ?',
      whereArgs: <Object?>[since, since],
      orderBy: 'updated_at ASC, deleted_at ASC',
    );
  }

  Future<void> upsertDictionaryItemFromSync(
      String tableName, Map<String, dynamic> item) async {
    _assertDictionaryTable(tableName);
    final row = _buildDictionaryRow(tableName, item);
    final syncId =
        _stringOrNull(item['sync_id'] ?? item['syncId'] ?? row['sync_id']);
    if (syncId == null) {
      return;
    }

    await _upsertSyncRow(
      tableName: tableName,
      syncId: syncId,
      incomingRow: <String, dynamic>{...row, 'sync_id': syncId},
    );
  }

  Future<void> softDeleteDictionaryItem(
      String tableName, String syncId, String deletedAt) async {
    _assertDictionaryTable(tableName);
    await _softDeleteBySyncId(tableName, syncId, deletedAt);
  }

  Future<void> resetDictionaries() async {
    await clearDictionary('antenna_dictionary');
    await clearDictionary('device_dictionary');
    await clearDictionary('qth_dictionary');
    await clearDictionary('callsign_dictionary');
    final db = await database;
    await _loadInitialDictionaries(db);
  }

  Future<void> resetAllData() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final dbPath = p.join(documentsDirectory.path, _databaseName);
    try {
      await deleteDatabase(dbPath);
    } catch (_) {}
  }

  // History operations
  Future<int> insertHistory(String name, List<LogEntry> logs) async {
    final db = await database;
    final logsData = json.encode(logs.map((LogEntry l) => l.toJson()).toList());
    final createdAt = _now();
    return db.insert(_historyTable, <String, dynamic>{
      'sync_id': _generateSyncId('history'),
      'name': name,
      'logs_data': logsData,
      'log_count': logs.length,
      'created_at': createdAt,
      'updated_at': createdAt,
      'deleted_at': null,
    });
  }

  Future<List<Map<String, dynamic>>> getAllHistory() async {
    final db = await database;
    return db.query(
      _historyTable,
      where: 'deleted_at IS NULL',
      orderBy: 'created_at DESC',
    );
  }

  Future<List<LogEntry>> getHistoryLogs(int id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _historyTable,
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: <Object?>[id],
    );
    if (maps.isEmpty) {
      return <LogEntry>[];
    }
    final logsData =
        json.decode(maps.first['logs_data'] as String) as List<dynamic>;
    return logsData
        .map((dynamic l) =>
            LogEntry.fromJson(Map<String, dynamic>.from(l as Map)))
        .toList();
  }

  Future<int> deleteHistory(int id) async {
    final db = await database;
    final deletedAt = _now();
    return db.update(
      _historyTable,
      <String, dynamic>{'deleted_at': deletedAt},
      where: 'id = ? AND (deleted_at IS NULL OR deleted_at < ?)',
      whereArgs: <Object?>[id, deletedAt],
    );
  }

  Future<void> clearAllHistory() async {
    final db = await database;
    await db.update(
      _historyTable,
      <String, dynamic>{'deleted_at': _now()},
      where: 'deleted_at IS NULL',
    );
  }

  Future<List<Map<String, dynamic>>> getHistoryChangedSince(
      String since) async {
    final db = await database;
    return db.query(
      _historyTable,
      where: 'updated_at > ? OR deleted_at > ?',
      whereArgs: <Object?>[since, since],
      orderBy: 'updated_at ASC, deleted_at ASC',
    );
  }

  Future<void> upsertHistoryFromSync(Map<String, dynamic> item) async {
    final row = _buildHistoryRow(item);
    final syncId =
        _stringOrNull(item['sync_id'] ?? item['syncId'] ?? row['sync_id']);
    if (syncId == null) {
      return;
    }

    await _upsertSyncRow(
      tableName: _historyTable,
      syncId: syncId,
      incomingRow: <String, dynamic>{...row, 'sync_id': syncId},
    );
  }

  Future<void> softDeleteHistory(String syncId, String deletedAt) async {
    await _softDeleteBySyncId(_historyTable, syncId, deletedAt);
  }

  // Session operations
  Future<List<Map<String, dynamic>>> getActiveSession() async {
    final db = await database;
    return db.query(
      _sessionsTable,
      where: 'status = ? AND deleted_at IS NULL',
      whereArgs: ['active'],
      limit: 1,
    );
  }

  /// Returns the session row for [sessionId] if it exists and is not
  /// soft-deleted. Used to validate persisted "current session" pointers
  /// against the actual DB state.
  Future<Session?> getSessionById(String sessionId) async {
    final db = await database;
    final rows = await db.query(
      _sessionsTable,
      where: 'session_id = ? AND deleted_at IS NULL',
      whereArgs: [sessionId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Session.fromMap(rows.first);
  }

  Future<List<Map<String, dynamic>>> getClosedSessions() async {
    final db = await database;
    return db.query(
      _sessionsTable,
      where: "status IN ('closed', 'archived') AND deleted_at IS NULL",
      orderBy: 'created_at DESC',
    );
  }

  /// Count of visible (non-deleted) logs attached to [sessionId]. Used by
  /// the history panel to show a per-session record count.
  Future<int> getLogCountForSession(String sessionId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) FROM $_logsTable WHERE session_id = ? AND deleted_at IS NULL',
      [sessionId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Permanently remove a session and all its associated logs. No soft-delete
  /// precondition — works on any session.
  Future<int> hardDeleteSession(String sessionId) async {
    final db = await database;
    return db.transaction<int>((txn) async {
      await txn.delete(
        _logsTable,
        where: 'session_id = ?',
        whereArgs: [sessionId],
      );
      return txn.delete(
        _sessionsTable,
        where: 'session_id = ?',
        whereArgs: [sessionId],
      );
    });
  }

  /// Permanently delete a single log row. No soft-delete precondition.
  Future<int> hardDeleteLog(String syncId) async {
    final db = await database;
    return db.delete(_logsTable, where: 'sync_id = ?', whereArgs: [syncId]);
  }

  /// Permanently delete a dictionary item. No soft-delete precondition.
  Future<int> hardDeleteDictionaryItem(String tableName, String syncId) async {
    _assertDictionaryTable(tableName);
    final db = await database;
    return db.delete(tableName, where: 'sync_id = ?', whereArgs: [syncId]);
  }

  Future<int> purgeDeletedRecords() async {
    final db = await database;
    var count = 0;
    count += await db.delete(_logsTable, where: 'deleted_at IS NOT NULL');
    count += await db.delete(_sessionsTable, where: 'deleted_at IS NOT NULL');
    count += await db.delete(_historyTable, where: 'deleted_at IS NOT NULL');
    for (final table in _dictionaryTables) {
      count += await db.delete(table, where: 'deleted_at IS NOT NULL');
    }
    return count;
  }

  Future<void> insertSession(Session session) async {
    final db = await database;
    await db.insert(_sessionsTable, session.toMap());
  }

  Future<void> closeSession(String sessionId) async {
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      _sessionsTable,
      {
        'status': 'closed',
        'closed_at': now,
        'updated_at': now,
      },
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<List<Map<String, dynamic>>> getSessionsChangedSince(
      String since) async {
    final db = await database;
    final count = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM $_sessionsTable'),
        ) ??
        0;
    debugPrint('[DB] sessions table has $count rows, querying since=$since');
    final result = await db.query(
      _sessionsTable,
      where: 'updated_at > ? OR deleted_at > ?',
      whereArgs: [since, since],
    );
    debugPrint('[DB] getSessionsChangedSince returned ${result.length} rows');
    return result;
  }

  /// Sessions table uses `session_id` as its primary key, not `sync_id`, so
  /// it cannot share the generic `_upsertSyncRow` / `_softDeleteBySyncId`
  /// helpers that query by `sync_id`. These are dedicated implementations.
  Future<void> upsertSessionFromSync(Map<String, dynamic> data) async {
    final sessionId = data['session_id']?.toString();
    if (sessionId == null) return;

    final db = await database;
    final existingRows = await db.query(
      _sessionsTable,
      columns: ['session_id', 'updated_at', 'deleted_at'],
      where: 'session_id = ?',
      whereArgs: [sessionId],
      limit: 1,
    );

    if (existingRows.isEmpty) {
      await db.insert(_sessionsTable, data,
          conflictAlgorithm: ConflictAlgorithm.replace);
      return;
    }

    final existingVersion = _latestVersionTimestamp(
      updatedAt: existingRows.first['updated_at'],
      deletedAt: existingRows.first['deleted_at'],
    );
    final incomingVersion = _latestVersionTimestamp(
      updatedAt: data['updated_at'],
      deletedAt: data['deleted_at'],
    );

    if (incomingVersion != null &&
        (existingVersion == null || incomingVersion.isAfter(existingVersion))) {
      await db.update(
        _sessionsTable,
        data,
        where: 'session_id = ?',
        whereArgs: [sessionId],
      );
    }
  }

  Future<void> softDeleteSession(String sessionId, String deletedAt) async {
    final db = await database;
    final normalizedDeletedAt = _legacyTimestamp(deletedAt);
    final existingRows = await db.query(
      _sessionsTable,
      columns: ['session_id', 'deleted_at'],
      where: 'session_id = ?',
      whereArgs: [sessionId],
      limit: 1,
    );

    if (existingRows.isEmpty) return;
    if (!_shouldApplyDeletedAt(
        existingRows.first['deleted_at'], normalizedDeletedAt)) {
      return;
    }

    await db.update(
      _sessionsTable,
      <String, dynamic>{'deleted_at': normalizedDeletedAt},
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<String> exportDatabase() async {
    final db = await database;

    final logs = await db.query(_logsTable);
    final deviceDict = await db.query('device_dictionary');
    final antennaDict = await db.query('antenna_dictionary');
    final qthDict = await db.query('qth_dictionary');
    final callsignDict = await db.query('callsign_dictionary');
    final history = await db.query(_historyTable);
    final sessions = await db.query(_sessionsTable);

    final exportData = <String, dynamic>{
      'version': 2,
      'exportedAt': _now(),
      'logs': logs,
      'device_dictionary': deviceDict,
      'antenna_dictionary': antennaDict,
      'qth_dictionary': qthDict,
      'callsign_dictionary': callsignDict,
      'history': history,
      'sessions': sessions,
    };

    return json.encode(exportData);
  }

  Future<void> importDatabase(String jsonData) async {
    final data = json.decode(jsonData) as Map<String, dynamic>;

    final version = data['version'];
    if (version != 1 && version != 2) {
      throw Exception('不支持的数据库版本');
    }

    final db = await database;
    final importedLogs = _sanitizeImportedRows(
      (data['logs'] as List<dynamic>?) ?? <dynamic>[],
      'log',
    );
    final importedDeviceDictionary = _sanitizeImportedRows(
      (data['device_dictionary'] as List<dynamic>?) ?? <dynamic>[],
      'device',
    );
    final importedAntennaDictionary = _sanitizeImportedRows(
      (data['antenna_dictionary'] as List<dynamic>?) ?? <dynamic>[],
      'antenna',
    );
    final importedQthDictionary = _sanitizeImportedRows(
      (data['qth_dictionary'] as List<dynamic>?) ?? <dynamic>[],
      'qth',
    );
    final importedCallsignDictionary = _sanitizeImportedRows(
      (data['callsign_dictionary'] as List<dynamic>?) ?? <dynamic>[],
      'callsign',
    );
    final importedHistory = _sanitizeImportedRows(
      (data['history'] as List<dynamic>?) ?? <dynamic>[],
      'history',
    );
    // v2 backups may contain the retired `callsign_qth_history` cache. It was
    // derived from logs, so accepting but ignoring it preserves recovery from
    // old backups without reviving the removed table.
    final importedSessions = ((data['sessions'] as List<dynamic>?) ?? const [])
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .where((m) => _stringOrNull(m['session_id']) != null)
        .toList();

    await db.transaction((Transaction txn) async {
      await txn.delete(_logsTable);
      await txn.delete('device_dictionary');
      await txn.delete('antenna_dictionary');
      await txn.delete('qth_dictionary');
      await txn.delete('callsign_dictionary');
      await txn.delete(_historyTable);
      await txn.delete(_sessionsTable);

      // Use a Batch to avoid awaiting once per row inside the transaction,
      // which serialized every insert and held the write-lock for the
      // duration of the loop on large imports.
      final batch = txn.batch();
      for (final log in importedLogs) {
        batch.insert(_logsTable, log);
      }
      for (final item in importedDeviceDictionary) {
        batch.insert('device_dictionary', item);
      }
      for (final item in importedAntennaDictionary) {
        batch.insert('antenna_dictionary', item);
      }
      for (final item in importedQthDictionary) {
        batch.insert('qth_dictionary', item);
      }
      for (final item in importedCallsignDictionary) {
        batch.insert('callsign_dictionary', item);
      }
      for (final item in importedHistory) {
        batch.insert(_historyTable, item);
      }
      for (final item in importedSessions) {
        batch.insert(_sessionsTable, item,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });

    await _migrateSyncSchema(db);
    if (importedSessions.isEmpty) {
      // v1 export had no sessions. Reconstruct from history so logs that
      // were tagged via _migrateHistoryToSessions still resolve.
      await _migrateHistoryToSessions(db);
    }
  }

  List<Map<String, dynamic>> _sanitizeImportedRows(
      List<dynamic> rows, String prefix) {
    final seenSyncIds = <String>{};
    return rows.map((dynamic row) {
      final normalized = Map<String, dynamic>.from(row as Map);
      final existingSyncId =
          _stringOrNull(normalized['sync_id'] ?? normalized['syncId']);
      if (existingSyncId == null || seenSyncIds.contains(existingSyncId)) {
        final generated = _generateSyncId(prefix);
        normalized['sync_id'] = generated;
      } else {
        normalized['sync_id'] = existingSyncId;
      }
      seenSyncIds.add(normalized['sync_id'] as String);
      return normalized;
    }).toList();
  }

  Future<Map<String, dynamic>> getDatabaseStats() async {
    final db = await database;

    final logsCount = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM $_logsTable')) ??
        0;
    final deviceCount = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM device_dictionary')) ??
        0;
    final antennaCount = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM antenna_dictionary')) ??
        0;
    final qthCount = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM qth_dictionary')) ??
        0;
    final callsignCount = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM callsign_dictionary')) ??
        0;
    final historyCount = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM $_historyTable')) ??
        0;

    return <String, dynamic>{
      'logs': logsCount,
      'device_dictionary': deviceCount,
      'antenna_dictionary': antennaCount,
      'qth_dictionary': qthCount,
      'callsign_dictionary': callsignCount,
      'history': historyCount,
    };
  }

  Future<LogEntry?> getLatestLogByCallsign(String callsign) async {
    if (callsign.isEmpty) return null;
    final db = await database;
    final rows = await db.query(
      _logsTable,
      where: 'callsign = ? AND deleted_at IS NULL',
      whereArgs: [callsign.toUpperCase()],
      orderBy: 'id DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return LogEntry.fromMap(rows.first);
  }

  Future<List<LogEntry>> getLogsByCallsign(String callsign,
      {int limit = 5}) async {
    if (callsign.isEmpty) return [];
    final db = await database;
    final rows = await db.query(
      _logsTable,
      where: 'callsign = ? AND deleted_at IS NULL',
      whereArgs: [callsign.toUpperCase()],
      orderBy: 'id DESC',
      limit: limit,
    );
    return rows.map((m) => LogEntry.fromMap(m)).toList();
  }
}
