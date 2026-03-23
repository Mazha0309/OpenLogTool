import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:openlogtool/models/log_entry.dart';

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
    );
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

    await _loadInitialDictionaries(db);
  }

  Future<void> _loadInitialDictionaries(Database db) async {
    await _loadDictionaryFromAsset(db, 'assets/dictionaries/antenna.json', 'antenna_dictionary');
    await _loadDictionaryFromAsset(db, 'assets/dictionaries/device.json', 'device_dictionary');
    await _loadDictionaryFromAsset(db, 'assets/dictionaries/qth.json', 'qth_dictionary');
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
}