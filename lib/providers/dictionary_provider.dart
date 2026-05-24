import 'dart:async';
import 'package:flutter/material.dart';
import 'package:openlogtool/database/database_helper.dart';
import 'package:openlogtool/models/dictionary_item.dart';

class DictionaryProvider with ChangeNotifier {
  bool _disposed = false;
  List<DictionaryItem> _deviceDict = [];
  List<DictionaryItem> _antennaDict = [];
  List<DictionaryItem> _callsignDict = [];
  List<DictionaryItem> _qthDict = [];
  Future<void> Function()? _onDictionaryChanged;

  List<DictionaryItem> get deviceDict => _deviceDict;
  List<DictionaryItem> get antennaDict => _antennaDict;
  List<DictionaryItem> get callsignDict => _callsignDict;
  List<DictionaryItem> get qthDict => _qthDict;

  void setOnDictionaryChanged(Future<void> Function()? callback) {
    _onDictionaryChanged = callback;
  }

  Future<void> _notifyDictionaryChanged() async {
    if (_onDictionaryChanged != null) {
      unawaited(_onDictionaryChanged!());
    }
  }

  DictionaryProvider() {
    scheduleMicrotask(_loadDictionaries);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  Future<void> _loadDictionaries() async {
    try {
      final db = DatabaseHelper();
      _deviceDict = await db.getDictionaryItems('device_dictionary');
      _antennaDict = await db.getDictionaryItems('antenna_dictionary');
      _callsignDict = await db.getDictionaryItems('callsign_dictionary');
      _qthDict = await db.getDictionaryItems('qth_dictionary');

      if (_deviceDict.isEmpty && _antennaDict.isEmpty && _qthDict.isEmpty) {
        await db.loadInitialDictionaries();
        _deviceDict = await db.getDictionaryItems('device_dictionary');
        _antennaDict = await db.getDictionaryItems('antenna_dictionary');
        _qthDict = await db.getDictionaryItems('qth_dictionary');
      }
    } catch (e, st) {
      debugPrint('[DictionaryProvider] _loadDictionaries failed: $e\n$st');
    }
    _safeNotify();
  }

  List<DictionaryItem> filterDevices(String query) {
    if (query.isEmpty) return _deviceDict;
    return _deviceDict.where((item) => item.matches(query)).toList();
  }

  List<DictionaryItem> filterAntennas(String query) {
    if (query.isEmpty) return _antennaDict;
    return _antennaDict.where((item) => item.matches(query)).toList();
  }

  List<DictionaryItem> filterCallsigns(String query) {
    if (query.isEmpty) return _callsignDict;
    return _callsignDict.where((item) => item.matches(query)).toList();
  }

  List<DictionaryItem> filterQths(String query) {
    if (query.isEmpty) return _qthDict;
    return _qthDict.where((item) => item.matches(query)).toList();
  }

  Future<void> addDevice(String device) async {
    if (device.isEmpty || _deviceDict.any((d) => d.raw == device)) return;
    try {
      final db = DatabaseHelper();
      await db.insertDictionaryItem('device_dictionary', {
        'raw': device,
        'pinyin': '',
        'abbreviation': '',
      });
      final persisted = await db.getDictionaryItemByRaw('device_dictionary', device);
      _deviceDict.add(persisted ?? DictionaryItem(raw: device, pinyin: '', abbreviation: '', type: 'device'));
      _deviceDict.sort((a, b) => a.raw.compareTo(b.raw));
      _safeNotify();
      await _notifyDictionaryChanged();
    } catch (e, st) {
      debugPrint('[DictionaryProvider] addDevice failed: $e\n$st');
      rethrow;
    }
  }

  Future<void> addAntenna(String antenna) async {
    if (antenna.isEmpty || _antennaDict.any((a) => a.raw == antenna)) return;
    try {
      final db = DatabaseHelper();
      await db.insertDictionaryItem('antenna_dictionary', {
        'raw': antenna,
        'pinyin': '',
        'abbreviation': '',
      });
      final persisted = await db.getDictionaryItemByRaw('antenna_dictionary', antenna);
      _antennaDict.add(persisted ?? DictionaryItem(raw: antenna, pinyin: '', abbreviation: '', type: 'antenna'));
      _antennaDict.sort((a, b) => a.raw.compareTo(b.raw));
      _safeNotify();
      await _notifyDictionaryChanged();
    } catch (e, st) {
      debugPrint('[DictionaryProvider] addAntenna failed: $e\n$st');
      rethrow;
    }
  }

  Future<void> addCallsign(String callsign) async {
    if (callsign.isEmpty || _callsignDict.any((c) => c.raw == callsign)) return;
    try {
      final db = DatabaseHelper();
      await db.insertDictionaryItem('callsign_dictionary', {
        'raw': callsign,
        'pinyin': '',
        'abbreviation': '',
      });
      final persisted = await db.getDictionaryItemByRaw('callsign_dictionary', callsign);
      _callsignDict.add(persisted ?? DictionaryItem(raw: callsign, pinyin: '', abbreviation: '', type: 'callsign'));
      _callsignDict.sort((a, b) => a.raw.compareTo(b.raw));
      _safeNotify();
      await _notifyDictionaryChanged();
    } catch (e, st) {
      debugPrint('[DictionaryProvider] addCallsign failed: $e\n$st');
      rethrow;
    }
  }

  Future<void> addQth(String qth) async {
    if (qth.isEmpty || _qthDict.any((q) => q.raw == qth)) return;
    try {
      final db = DatabaseHelper();
      await db.insertDictionaryItem('qth_dictionary', {
        'raw': qth,
        'pinyin': '',
        'abbreviation': '',
      });
      final persisted = await db.getDictionaryItemByRaw('qth_dictionary', qth);
      _qthDict.add(persisted ?? DictionaryItem(raw: qth, pinyin: '', abbreviation: '', type: 'qth'));
      _qthDict.sort((a, b) => a.raw.compareTo(b.raw));
      _safeNotify();
      await _notifyDictionaryChanged();
    } catch (e, st) {
      debugPrint('[DictionaryProvider] addQth failed: $e\n$st');
      rethrow;
    }
  }

  Future<void> importDevices(List<String> devices) async {
    final db = DatabaseHelper();
    for (final device in devices) {
      if (!_deviceDict.any((d) => d.raw == device)) {
        await db.insertDictionaryItem('device_dictionary', {
          'raw': device,
          'pinyin': '',
          'abbreviation': '',
        });
        final persisted = await db.getDictionaryItemByRaw('device_dictionary', device);
        _deviceDict.add(persisted ?? DictionaryItem(raw: device, pinyin: '', abbreviation: '', type: 'device'));
      }
    }
    _deviceDict.sort((a, b) => a.raw.compareTo(b.raw));
    notifyListeners();
    await _notifyDictionaryChanged();
  }

  Future<void> importAntennas(List<String> antennas) async {
    final db = DatabaseHelper();
    for (final antenna in antennas) {
      if (!_antennaDict.any((a) => a.raw == antenna)) {
        await db.insertDictionaryItem('antenna_dictionary', {
          'raw': antenna,
          'pinyin': '',
          'abbreviation': '',
        });
        final persisted = await db.getDictionaryItemByRaw('antenna_dictionary', antenna);
        _antennaDict.add(persisted ?? DictionaryItem(raw: antenna, pinyin: '', abbreviation: '', type: 'antenna'));
      }
    }
    _antennaDict.sort((a, b) => a.raw.compareTo(b.raw));
    notifyListeners();
    await _notifyDictionaryChanged();
  }

  Future<void> importCallsigns(List<String> callsigns) async {
    final db = DatabaseHelper();
    for (final callsign in callsigns) {
      if (!_callsignDict.any((c) => c.raw == callsign)) {
        await db.insertDictionaryItem('callsign_dictionary', {
          'raw': callsign,
          'pinyin': '',
          'abbreviation': '',
        });
        final persisted = await db.getDictionaryItemByRaw('callsign_dictionary', callsign);
        _callsignDict.add(persisted ?? DictionaryItem(raw: callsign, pinyin: '', abbreviation: '', type: 'callsign'));
      }
    }
    _callsignDict.sort((a, b) => a.raw.compareTo(b.raw));
    notifyListeners();
    await _notifyDictionaryChanged();
  }

  Future<void> importQths(List<String> qths) async {
    final db = DatabaseHelper();
    for (final qth in qths) {
      if (!_qthDict.any((q) => q.raw == qth)) {
        await db.insertDictionaryItem('qth_dictionary', {
          'raw': qth,
          'pinyin': '',
          'abbreviation': '',
        });
        final persisted = await db.getDictionaryItemByRaw('qth_dictionary', qth);
        _qthDict.add(persisted ?? DictionaryItem(raw: qth, pinyin: '', abbreviation: '', type: 'qth'));
      }
    }
    _qthDict.sort((a, b) => a.raw.compareTo(b.raw));
    notifyListeners();
    await _notifyDictionaryChanged();
  }

  Future<void> clearDeviceDict() async {
    final db = DatabaseHelper();
    final deletedAt = DateTime.now().toUtc().toIso8601String();
    for (final item in _deviceDict) {
      await db.softDeleteDictionaryItem('device_dictionary', item.syncId, deletedAt);
    }
    _deviceDict.clear();
    notifyListeners();
    await _notifyDictionaryChanged();
  }

  Future<void> clearAntennaDict() async {
    final db = DatabaseHelper();
    final deletedAt = DateTime.now().toUtc().toIso8601String();
    for (final item in _antennaDict) {
      await db.softDeleteDictionaryItem('antenna_dictionary', item.syncId, deletedAt);
    }
    _antennaDict.clear();
    notifyListeners();
    await _notifyDictionaryChanged();
  }

  Future<void> clearCallsignDict() async {
    final db = DatabaseHelper();
    final deletedAt = DateTime.now().toUtc().toIso8601String();
    for (final item in _callsignDict) {
      await db.softDeleteDictionaryItem('callsign_dictionary', item.syncId, deletedAt);
    }
    _callsignDict.clear();
    notifyListeners();
    await _notifyDictionaryChanged();
  }

  Future<void> clearQthDict() async {
    final db = DatabaseHelper();
    final deletedAt = DateTime.now().toUtc().toIso8601String();
    for (final item in _qthDict) {
      await db.softDeleteDictionaryItem('qth_dictionary', item.syncId, deletedAt);
    }
    _qthDict.clear();
    notifyListeners();
    await _notifyDictionaryChanged();
  }

  Future<void> resetDictionaries() async {
    final db = DatabaseHelper();
    await db.resetDictionaries();
    await _loadDictionaries();
    await _notifyDictionaryChanged();
  }

  Future<void> resetAllData() async {
    final db = DatabaseHelper();
    await db.resetAllData();
    await _loadDictionaries();
    await _notifyDictionaryChanged();
  }
}
