import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:openlogtool/models/dictionary_item.dart';
import 'package:openlogtool/models/log_entry.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  static const String _databaseName = 'openlogtool.db';
  static const String _logsTable = 'logs';
  static const String _historyTable = 'history';
  static const String _callsignQthHistoryTable = 'callsign_qth_history';
  static const List<String> _dictionaryTables = <String>[
    'device_dictionary',
    'antenna_dictionary',
    'qth_dictionary',
    'callsign_dictionary',
  ];

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = '${documentsDirectory.path}${Platform.pathSeparator}$_databaseName';

    return openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
      onOpen: _onOpen,
    );
  }

  Future<void> _onOpen(Database db) async {
    await _ensureDictionaryTablesExist(db);
    await _ensureHistoryTableExists(db);
    await _ensureLogsTableExists(db);
    await _ensureCallsignQthHistoryTableExists(db);
    await _migrateSyncSchema(db);

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
    await _createCallsignQthHistoryTable(db);
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

  Future<void> _ensureCallsignQthHistoryTableExists(Database db) async {
    await _createCallsignQthHistoryTable(db, ifNotExists: true);
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
    await _ensureUniqueIndex(db, 'idx_logs_sync_id', _logsTable, 'sync_id');
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
        deleted_at TEXT
      )
    ''');
    await _ensureUniqueIndex(db, 'idx_${tableName}_sync_id', tableName, 'sync_id');
  }

  Future<void> _createHistoryTable(Database db, {bool ifNotExists = false}) async {
    await db.execute('''
      CREATE TABLE ${ifNotExists ? 'IF NOT EXISTS ' : ''}$_historyTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sync_id TEXT UNIQUE,
        name TEXT NOT NULL,
        logs_data TEXT NOT NULL,
        log_count INTEGER NOT NULL,
        created_at TEXT,
        updated_at TEXT,
        deleted_at TEXT
      )
    ''');
    await _ensureUniqueIndex(db, 'idx_history_sync_id', _historyTable, 'sync_id');
  }

  Future<void> _createCallsignQthHistoryTable(
    Database db, {
    bool ifNotExists = false,
  }) async {
    await db.execute('''
      CREATE TABLE ${ifNotExists ? 'IF NOT EXISTS ' : ''}$_callsignQthHistoryTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sync_id TEXT UNIQUE,
        callsign TEXT NOT NULL,
        qth TEXT NOT NULL,
        recorded_at TEXT NOT NULL,
        created_at TEXT,
        updated_at TEXT,
        deleted_at TEXT
      )
    ''');
    await _ensureUniqueIndex(
      db,
      'idx_callsign_qth_history_sync_id',
      _callsignQthHistoryTable,
      'sync_id',
    );
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_callsign_qth_callsign
      ON $_callsignQthHistoryTable(callsign)
    ''');
  }

  Future<void> _migrateSyncSchema(Database db) async {
    await _migrateLogsTable(db);
    for (final tableName in _dictionaryTables) {
      await _migrateDictionaryTable(db, tableName);
    }
    await _migrateHistoryTable(db);
    await _migrateCallsignQthHistoryTable(db);
  }

  Future<void> _migrateLogsTable(Database db) async {
    await _ensureColumn(db, _logsTable, 'sync_id', 'TEXT');
    await _ensureColumn(db, _logsTable, 'created_at', 'TEXT');
    await _ensureColumn(db, _logsTable, 'updated_at', 'TEXT');
    await _ensureColumn(db, _logsTable, 'deleted_at', 'TEXT');
    await _ensureColumn(db, _logsTable, 'source_device_id', 'TEXT');
    await _ensureUniqueIndex(db, 'idx_logs_sync_id', _logsTable, 'sync_id');

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
      final createdAt = _stringOrNull(row['created_at']) ?? _legacyTimestamp(fallbackTime);
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
        batch.update(_logsTable, updates, where: 'id = ?', whereArgs: <Object?>[logId]);
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
    await _ensureUniqueIndex(db, 'idx_${tableName}_sync_id', tableName, 'sync_id');

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
        batch.update(tableName, updates, where: 'id = ?', whereArgs: <Object?>[localId]);
      }
    }
    await batch.commit(noResult: true);
  }

  Future<void> _migrateHistoryTable(Database db) async {
    await _ensureColumn(db, _historyTable, 'sync_id', 'TEXT');
    await _ensureColumn(db, _historyTable, 'created_at', 'TEXT');
    await _ensureColumn(db, _historyTable, 'updated_at', 'TEXT');
    await _ensureColumn(db, _historyTable, 'deleted_at', 'TEXT');
    await _ensureUniqueIndex(db, 'idx_history_sync_id', _historyTable, 'sync_id');

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
        batch.update(_historyTable, updates, where: 'id = ?', whereArgs: <Object?>[localId]);
      }
    }
    await batch.commit(noResult: true);
  }

  Future<void> _migrateCallsignQthHistoryTable(Database db) async {
    await _ensureColumn(db, _callsignQthHistoryTable, 'sync_id', 'TEXT');
    await _ensureColumn(db, _callsignQthHistoryTable, 'created_at', 'TEXT');
    await _ensureColumn(db, _callsignQthHistoryTable, 'updated_at', 'TEXT');
    await _ensureColumn(db, _callsignQthHistoryTable, 'deleted_at', 'TEXT');
    await _ensureUniqueIndex(
      db,
      'idx_callsign_qth_history_sync_id',
      _callsignQthHistoryTable,
      'sync_id',
    );

    final rows = await db.query(
      _callsignQthHistoryTable,
      columns: <String>['id', 'recorded_at', 'sync_id', 'created_at', 'updated_at'],
    );
    final batch = db.batch();
    for (final row in rows) {
      final localId = row['id'];
      if (localId == null) {
        continue;
      }
      final recordedAt = _stringOrNull(row['recorded_at']);
      final createdAt = _stringOrNull(row['created_at']) ?? _legacyTimestamp(recordedAt);
      final updates = <String, Object?>{};

      if (_isBlank(row['sync_id'])) {
        updates['sync_id'] = _generateSyncId('callsign-qth');
      }
      if (_isBlank(row['created_at'])) {
        updates['created_at'] = createdAt;
      }
      if (_isBlank(row['updated_at'])) {
        updates['updated_at'] = _stringOrNull(row['updated_at']) ?? createdAt;
      }

      if (updates.isNotEmpty) {
        batch.update(
          _callsignQthHistoryTable,
          updates,
          where: 'id = ?',
          whereArgs: <Object?>[localId],
        );
      }
    }
    await batch.commit(noResult: true);
  }

  Future<void> _ensureColumn(
    Database db,
    String tableName,
    String columnName,
    String definition,
  ) async {
    final columns = await _getExistingColumns(db, tableName);
    if (columns.contains(columnName)) {
      return;
    }
    await db.execute('ALTER TABLE $tableName ADD COLUMN $columnName $definition');
  }

  Future<Set<String>> _getExistingColumns(Database db, String tableName) async {
    final result = await db.rawQuery('PRAGMA table_info($tableName)');
    return result.map((row) => row['name'].toString()).toSet();
  }

  Future<void> _ensureUniqueIndex(
    Database db,
    String indexName,
    String tableName,
    String columnName,
  ) async {
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS $indexName ON $tableName($columnName)',
    );
  }

  Future<void> _loadInitialDictionaries(Database db) async {
    await _loadDictionaryFromAsset(db, 'assets/dictionaries/antenna.json', 'antenna_dictionary');
    await _loadDictionaryFromAsset(db, 'assets/dictionaries/device.json', 'device_dictionary');
    await _loadDictionaryFromAsset(db, 'assets/dictionaries/qth.json', 'qth_dictionary');
  }

  Future<void> loadInitialDictionaries() async {
    final db = await database;
    await _loadInitialDictionaries(db);
  }

  Future<void> _loadDictionaryFromAsset(Database db, String assetPath, String tableName) async {
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
    final updatedAt = _legacyTimestamp(log.updatedAt.isNotEmpty ? log.updatedAt : createdAt);
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
    };
  }

  Map<String, dynamic> _buildDictionaryRow(String tableName, Map<String, dynamic> item) {
    final now = _now();
    final createdAt = _stringOrNull(item['created_at'] ?? item['createdAt']) ?? now;
    final updatedAt = _stringOrNull(item['updated_at'] ?? item['updatedAt']) ?? createdAt;
    final row = <String, dynamic>{
      'raw': item['raw']?.toString() ?? '',
      'pinyin': item['pinyin']?.toString() ?? '',
      'abbreviation': item['abbreviation']?.toString() ?? '',
      'sync_id': _stringOrNull(item['sync_id'] ?? item['syncId']) ?? _generateSyncId(_dictionaryTypeForTable(tableName)),
      'type': _stringOrNull(item['type']) ?? _dictionaryTypeForTable(tableName),
      'created_at': createdAt,
      'updated_at': updatedAt,
      'deleted_at': _stringOrNull(item['deleted_at'] ?? item['deletedAt']),
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

  String _now() => DateTime.now().toIso8601String();

  String _legacyTimestamp(String? value) {
    final normalized = value?.trim();
    if (normalized != null && normalized.isNotEmpty && DateTime.tryParse(normalized) != null) {
      return normalized;
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

  // Log operations
  Future<int> insertLog(LogEntry log) async {
    final db = await database;
    return db.insert(_logsTable, _buildLogRow(log));
  }

  Future<List<LogEntry>> getAllLogs() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(_logsTable);
    return List<LogEntry>.generate(maps.length, (int i) => LogEntry.fromMap(maps[i]));
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
    return db.delete(
      _logsTable,
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> deleteAllLogs() async {
    final db = await database;
    await db.delete(_logsTable);
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
    final db = await database;
    return db.query(tableName, orderBy: 'raw ASC');
  }

  Future<List<String>> getDictionaryRaw(String tableName) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(tableName, orderBy: 'raw ASC');
    return maps.map((Map<String, dynamic> m) => m['raw'] as String).toList();
  }

  Future<List<DictionaryItem>> getDictionaryItems(String tableName) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(tableName, orderBy: 'raw ASC');
    return maps
        .map(
          (Map<String, dynamic> m) => DictionaryItem.fromMap(<String, dynamic>{
            ...m,
            'type': m['type'] ?? _dictionaryTypeForTable(tableName),
          }),
        )
        .toList();
  }

  Future<int> insertDictionaryItem(String tableName, Map<String, dynamic> item) async {
    final db = await database;
    return db.insert(
      tableName,
      _buildDictionaryRow(tableName, item),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> importDictionaryItems(String tableName, List<Map<String, dynamic>> items) async {
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
    final db = await database;
    return db.delete(
      tableName,
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> clearDictionary(String tableName) async {
    final db = await database;
    await db.delete(tableName);
  }

  Future<void> resetDictionaries() async {
    final db = await database;
    await db.delete('antenna_dictionary');
    await db.delete('device_dictionary');
    await db.delete('qth_dictionary');
    await _loadInitialDictionaries(db);
  }

  Future<void> resetAllData() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = '${documentsDirectory.path}${Platform.pathSeparator}$_databaseName';
    final dbFile = File(path);
    if (await dbFile.exists()) {
      await dbFile.delete();
    }
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
    return db.query(_historyTable, orderBy: 'created_at DESC');
  }

  Future<List<LogEntry>> getHistoryLogs(int id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _historyTable,
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    if (maps.isEmpty) {
      return <LogEntry>[];
    }
    final logsData = json.decode(maps.first['logs_data'] as String) as List<dynamic>;
    return logsData
        .map((dynamic l) => LogEntry.fromJson(Map<String, dynamic>.from(l as Map)))
        .toList();
  }

  Future<int> deleteHistory(int id) async {
    final db = await database;
    return db.delete(
      _historyTable,
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> clearAllHistory() async {
    final db = await database;
    await db.delete(_historyTable);
  }

  Future<String> exportDatabase() async {
    final db = await database;

    final logs = await db.query(_logsTable);
    final deviceDict = await db.query('device_dictionary');
    final antennaDict = await db.query('antenna_dictionary');
    final qthDict = await db.query('qth_dictionary');
    final callsignDict = await db.query('callsign_dictionary');
    final history = await db.query(_historyTable);
    final callsignQthHistory = await db.query(_callsignQthHistoryTable);

    final exportData = <String, dynamic>{
      'version': 1,
      'exportedAt': _now(),
      'logs': logs,
      'device_dictionary': deviceDict,
      'antenna_dictionary': antennaDict,
      'qth_dictionary': qthDict,
      'callsign_dictionary': callsignDict,
      'history': history,
      'callsign_qth_history': callsignQthHistory,
    };

    return json.encode(exportData);
  }

  Future<void> importDatabase(String jsonData) async {
    final data = json.decode(jsonData) as Map<String, dynamic>;

    if (data['version'] != 1) {
      throw Exception('不支持的数据库版本');
    }

    final db = await database;

    await db.transaction((Transaction txn) async {
      await txn.delete(_logsTable);
      await txn.delete('device_dictionary');
      await txn.delete('antenna_dictionary');
      await txn.delete('qth_dictionary');
      await txn.delete('callsign_dictionary');
      await txn.delete(_historyTable);
      await txn.delete(_callsignQthHistoryTable);

      if (data['logs'] != null) {
        for (final log in data['logs'] as List<dynamic>) {
          await txn.insert(_logsTable, Map<String, dynamic>.from(log as Map));
        }
      }

      if (data['device_dictionary'] != null) {
        for (final item in data['device_dictionary'] as List<dynamic>) {
          await txn.insert('device_dictionary', Map<String, dynamic>.from(item as Map));
        }
      }

      if (data['antenna_dictionary'] != null) {
        for (final item in data['antenna_dictionary'] as List<dynamic>) {
          await txn.insert('antenna_dictionary', Map<String, dynamic>.from(item as Map));
        }
      }

      if (data['qth_dictionary'] != null) {
        for (final item in data['qth_dictionary'] as List<dynamic>) {
          await txn.insert('qth_dictionary', Map<String, dynamic>.from(item as Map));
        }
      }

      if (data['callsign_dictionary'] != null) {
        for (final item in data['callsign_dictionary'] as List<dynamic>) {
          await txn.insert('callsign_dictionary', Map<String, dynamic>.from(item as Map));
        }
      }

      if (data['history'] != null) {
        for (final item in data['history'] as List<dynamic>) {
          await txn.insert(_historyTable, Map<String, dynamic>.from(item as Map));
        }
      }

      if (data['callsign_qth_history'] != null) {
        for (final item in data['callsign_qth_history'] as List<dynamic>) {
          await txn.insert(_callsignQthHistoryTable, Map<String, dynamic>.from(item as Map));
        }
      }
    });

    await _migrateSyncSchema(db);
  }

  Future<Map<String, dynamic>> getDatabaseStats() async {
    final db = await database;

    final logsCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $_logsTable')) ?? 0;
    final deviceCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM device_dictionary')) ?? 0;
    final antennaCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM antenna_dictionary')) ?? 0;
    final qthCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM qth_dictionary')) ?? 0;
    final callsignCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM callsign_dictionary')) ?? 0;
    final historyCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $_historyTable')) ?? 0;
    final callsignQthHistoryCount =
        Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $_callsignQthHistoryTable')) ?? 0;

    return <String, dynamic>{
      'logs': logsCount,
      'device_dictionary': deviceCount,
      'antenna_dictionary': antennaCount,
      'qth_dictionary': qthCount,
      'callsign_dictionary': callsignCount,
      'history': historyCount,
      'callsign_qth_history': callsignQthHistoryCount,
    };
  }

  Future<void> addCallsignQthRecord(String callsign, String qth) async {
    if (callsign.isEmpty || qth.isEmpty) {
      return;
    }
    final db = await database;
    final recordedAt = _now();
    await db.insert(_callsignQthHistoryTable, <String, dynamic>{
      'sync_id': _generateSyncId('callsign-qth'),
      'callsign': callsign.toUpperCase(),
      'qth': qth,
      'recorded_at': recordedAt,
      'created_at': recordedAt,
      'updated_at': recordedAt,
      'deleted_at': null,
    });
  }

  Future<List<Map<String, dynamic>>> getCallsignQthHistory(String callsign, {int limit = 3}) async {
    if (callsign.isEmpty) {
      return <Map<String, dynamic>>[];
    }
    final db = await database;
    return db.query(
      _callsignQthHistoryTable,
      where: 'callsign = ?',
      whereArgs: <Object?>[callsign.toUpperCase()],
      orderBy: 'recorded_at DESC',
      limit: limit,
    );
  }

  Future<List<Map<String, dynamic>>> getAllCallsignQthHistory() async {
    final db = await database;
    return db.query(
      _callsignQthHistoryTable,
      orderBy: 'recorded_at DESC',
    );
  }

  Future<String?> getLastRecordedTime(String callsign, String qth) async {
    if (callsign.isEmpty || qth.isEmpty) {
      return null;
    }
    final db = await database;
    final results = await db.query(
      _callsignQthHistoryTable,
      where: 'callsign = ? AND qth = ?',
      whereArgs: <Object?>[callsign.toUpperCase(), qth],
      orderBy: 'recorded_at DESC',
      limit: 1,
    );
    if (results.isEmpty) {
      return null;
    }
    return results.first['recorded_at'] as String;
  }

  Future<void> clearCallsignQthHistory() async {
    final db = await database;
    await db.delete(_callsignQthHistoryTable);
  }
}
