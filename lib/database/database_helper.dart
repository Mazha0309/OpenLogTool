import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:openlogtool/models/log_entry.dart';
import 'package:openlogtool/models/dictionary_item.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, 'openlogtool.db');

    return await openDatabase(
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
    final count = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM device_dictionary'));
    if (count == null || count == 0) {
      await _loadInitialDictionaries(db);
    }
  }

  Future<void> _ensureLogsTableExists(Database db) async {
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS logs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          time TEXT NOT NULL,
          controller TEXT NOT NULL,
          callsign TEXT NOT NULL,
          report TEXT,
          qth TEXT,
          device TEXT,
          power TEXT,
          antenna TEXT,
          height TEXT
        )
      ''');
    } catch (_) {}
  }

  Future<void> _ensureDictionaryTablesExist(Database db) async {
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS device_dictionary (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          raw TEXT NOT NULL UNIQUE,
          pinyin TEXT,
          abbreviation TEXT
        )
      ''');
    } catch (_) {}

    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS antenna_dictionary (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          raw TEXT NOT NULL UNIQUE,
          pinyin TEXT,
          abbreviation TEXT
        )
      ''');
    } catch (_) {}

    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS qth_dictionary (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          raw TEXT NOT NULL UNIQUE,
          pinyin TEXT,
          abbreviation TEXT
        )
      ''');
    } catch (_) {}

    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS callsign_dictionary (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          raw TEXT NOT NULL UNIQUE,
          pinyin TEXT,
          abbreviation TEXT
        )
      ''');
    } catch (_) {}
  }

  Future<void> _ensureHistoryTableExists(Database db) async {
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS history (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          logs_data TEXT NOT NULL,
          log_count INTEGER NOT NULL,
          created_at TEXT NOT NULL
        )
      ''');
    } catch (_) {}
  }

  Future<void> _ensureCallsignQthHistoryTableExists(Database db) async {
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS callsign_qth_history (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          callsign TEXT NOT NULL,
          qth TEXT NOT NULL,
          recorded_at TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_callsign_qth_callsign ON callsign_qth_history(callsign)
      ''');
    } catch (_) {}
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        time TEXT NOT NULL,
        controller TEXT NOT NULL,
        callsign TEXT NOT NULL,
        report TEXT,
        qth TEXT,
        device TEXT,
        power TEXT,
        antenna TEXT,
        height TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE device_dictionary (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        raw TEXT NOT NULL UNIQUE,
        pinyin TEXT,
        abbreviation TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE antenna_dictionary (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        raw TEXT NOT NULL UNIQUE,
        pinyin TEXT,
        abbreviation TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE qth_dictionary (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        raw TEXT NOT NULL UNIQUE,
        pinyin TEXT,
        abbreviation TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE callsign_dictionary (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        raw TEXT NOT NULL UNIQUE,
        pinyin TEXT,
        abbreviation TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        logs_data TEXT NOT NULL,
        log_count INTEGER NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE callsign_qth_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        callsign TEXT NOT NULL,
        qth TEXT NOT NULL,
        recorded_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_callsign_qth_callsign ON callsign_qth_history(callsign)
    ''');

    await _loadInitialDictionaries(db);
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
      final List<dynamic> jsonList = json.decode(jsonString);

      final batch = db.batch();
      for (final item in jsonList) {
        batch.insert(
          tableName,
          {
            'raw': item['raw'] ?? '',
            'pinyin': item['pinyin'] ?? '',
            'abbreviation': item['abbreviation'] ?? '',
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      await batch.commit(noResult: true);
    } catch (e) {
      // Asset file doesn't exist or can't be loaded, skip
    }
  }

  // Log operations
  Future<int> insertLog(LogEntry log) async {
    final db = await database;
    return await db.insert('logs', log.toMap());
  }

  Future<List<LogEntry>> getAllLogs() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('logs');
    return List.generate(maps.length, (i) => LogEntry.fromMap(maps[i]));
  }

  Future<int> updateLog(int id, LogEntry log) async {
    final db = await database;
    return await db.update(
      'logs',
      log.toMap(),
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteLog(int id) async {
    final db = await database;
    return await db.delete(
      'logs',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteAllLogs() async {
    final db = await database;
    await db.delete('logs');
  }

  Future<void> importLogs(List<LogEntry> logs) async {
    final db = await database;
    final batch = db.batch();
    for (final log in logs) {
      batch.insert('logs', log.toMap());
    }
    await batch.commit(noResult: true);
  }

  // Dictionary operations
  Future<List<Map<String, dynamic>>> getDictionary(String tableName) async {
    final db = await database;
    return await db.query(tableName, orderBy: 'raw ASC');
  }

  Future<List<String>> getDictionaryRaw(String tableName) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(tableName, orderBy: 'raw ASC');
    return maps.map((m) => m['raw'] as String).toList();
  }

  Future<List<DictionaryItem>> getDictionaryItems(String tableName) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(tableName, orderBy: 'raw ASC');
    return maps.map((m) => DictionaryItem.fromMap(m)).toList();
  }

  Future<int> insertDictionaryItem(String tableName, Map<String, dynamic> item) async {
    final db = await database;
    return await db.insert(
      tableName,
      item,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> importDictionaryItems(String tableName, List<Map<String, dynamic>> items) async {
    final db = await database;
    final batch = db.batch();
    for (final item in items) {
      batch.insert(
        tableName,
        item,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<int> deleteDictionaryItem(String tableName, int id) async {
    final db = await database;
    return await db.delete(
      tableName,
      where: 'id = ?',
      whereArgs: [id],
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
    final path = join(documentsDirectory.path, 'openlogtool.db');
    final dbFile = File(path);
    if (await dbFile.exists()) {
      await dbFile.delete();
    }
  }

  // History operations
  Future<int> insertHistory(String name, List<LogEntry> logs) async {
    final db = await database;
    final logsData = json.encode(logs.map((l) => l.toJson()).toList());
    return await db.insert('history', {
      'name': name,
      'logs_data': logsData,
      'log_count': logs.length,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getAllHistory() async {
    final db = await database;
    return await db.query('history', orderBy: 'created_at DESC');
  }

  Future<List<LogEntry>> getHistoryLogs(int id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'history',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return [];
    final logsData = json.decode(maps.first['logs_data'] as String) as List;
    return logsData.map((l) => LogEntry.fromJson(l as Map<String, dynamic>)).toList();
  }

  Future<int> deleteHistory(int id) async {
    final db = await database;
    return await db.delete(
      'history',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> clearAllHistory() async {
    final db = await database;
    await db.delete('history');
  }

  Future<String> exportDatabase() async {
    final db = await database;

    final logs = await db.query('logs');
    final deviceDict = await db.query('device_dictionary');
    final antennaDict = await db.query('antenna_dictionary');
    final qthDict = await db.query('qth_dictionary');
    final callsignDict = await db.query('callsign_dictionary');
    final history = await db.query('history');

    final exportData = {
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'logs': logs,
      'device_dictionary': deviceDict,
      'antenna_dictionary': antennaDict,
      'qth_dictionary': qthDict,
      'callsign_dictionary': callsignDict,
      'history': history,
    };

    return json.encode(exportData);
  }

  Future<void> importDatabase(String jsonData) async {
    final data = json.decode(jsonData) as Map<String, dynamic>;

    if (data['version'] != 1) {
      throw Exception('不支持的数据库版本');
    }

    final db = await database;

    await db.transaction((txn) async {
      await txn.delete('logs');
      await txn.delete('device_dictionary');
      await txn.delete('antenna_dictionary');
      await txn.delete('qth_dictionary');
      await txn.delete('callsign_dictionary');
      await txn.delete('history');

      if (data['logs'] != null) {
        for (final log in data['logs'] as List) {
          await txn.insert('logs', Map<String, dynamic>.from(log));
        }
      }

      if (data['device_dictionary'] != null) {
        for (final item in data['device_dictionary'] as List) {
          await txn.insert('device_dictionary', Map<String, dynamic>.from(item));
        }
      }

      if (data['antenna_dictionary'] != null) {
        for (final item in data['antenna_dictionary'] as List) {
          await txn.insert('antenna_dictionary', Map<String, dynamic>.from(item));
        }
      }

      if (data['qth_dictionary'] != null) {
        for (final item in data['qth_dictionary'] as List) {
          await txn.insert('qth_dictionary', Map<String, dynamic>.from(item));
        }
      }

      if (data['callsign_dictionary'] != null) {
        for (final item in data['callsign_dictionary'] as List) {
          await txn.insert('callsign_dictionary', Map<String, dynamic>.from(item));
        }
      }

      if (data['history'] != null) {
        for (final item in data['history'] as List) {
          await txn.insert('history', Map<String, dynamic>.from(item));
        }
      }
    });
  }

  Future<Map<String, dynamic>> getDatabaseStats() async {
    final db = await database;

    final logsCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM logs')) ?? 0;
    final deviceCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM device_dictionary')) ?? 0;
    final antennaCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM antenna_dictionary')) ?? 0;
    final qthCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM qth_dictionary')) ?? 0;
    final callsignCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM callsign_dictionary')) ?? 0;
    final historyCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM history')) ?? 0;

    return {
      'logs': logsCount,
      'device_dictionary': deviceCount,
      'antenna_dictionary': antennaCount,
      'qth_dictionary': qthCount,
      'callsign_dictionary': callsignCount,
      'history': historyCount,
    };
  }

  Future<void> addCallsignQthRecord(String callsign, String qth) async {
    if (callsign.isEmpty || qth.isEmpty) return;
    final db = await database;
    await db.insert('callsign_qth_history', {
      'callsign': callsign.toUpperCase(),
      'qth': qth,
      'recorded_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getCallsignQthHistory(String callsign, {int limit = 3}) async {
    if (callsign.isEmpty) return [];
    final db = await database;
    final results = await db.query(
      'callsign_qth_history',
      where: 'callsign = ?',
      whereArgs: [callsign.toUpperCase()],
      orderBy: 'recorded_at DESC',
      limit: limit,
    );
    return results;
  }

  Future<String?> getLastRecordedTime(String callsign, String qth) async {
    if (callsign.isEmpty || qth.isEmpty) return null;
    final db = await database;
    final results = await db.query(
      'callsign_qth_history',
      where: 'callsign = ? AND qth = ?',
      whereArgs: [callsign.toUpperCase(), qth],
      orderBy: 'recorded_at DESC',
      limit: 1,
    );
    if (results.isEmpty) return null;
    return results.first['recorded_at'] as String;
  }

  Future<void> clearCallsignQthHistory() async {
    final db = await database;
    await db.delete('callsign_qth_history');
  }
}