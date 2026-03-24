import 'package:flutter/material.dart';
import 'package:openlogtool/database/database_helper.dart';
import 'package:openlogtool/models/dictionary_item.dart';

class DictionaryProvider with ChangeNotifier {
  List<DictionaryItem> _deviceDict = [];
  List<DictionaryItem> _antennaDict = [];
  List<DictionaryItem> _callsignDict = [];
  List<DictionaryItem> _qthDict = [];

  List<DictionaryItem> get deviceDict => _deviceDict;
  List<DictionaryItem> get antennaDict => _antennaDict;
  List<DictionaryItem> get callsignDict => _callsignDict;
  List<DictionaryItem> get qthDict => _qthDict;

  DictionaryProvider() {
    _loadDictionaries();
  }

  Future<void> _loadDictionaries() async {
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

    notifyListeners();
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
    if (device.isNotEmpty && !_deviceDict.any((d) => d.raw == device)) {
      final db = DatabaseHelper();
      await db.insertDictionaryItem('device_dictionary', {
        'raw': device,
        'pinyin': '',
        'abbreviation': '',
      });
      _deviceDict.add(DictionaryItem(raw: device, pinyin: '', abbreviation: ''));
      _deviceDict.sort((a, b) => a.raw.compareTo(b.raw));
      notifyListeners();
    }
  }

  Future<void> addAntenna(String antenna) async {
    if (antenna.isNotEmpty && !_antennaDict.any((a) => a.raw == antenna)) {
      final db = DatabaseHelper();
      await db.insertDictionaryItem('antenna_dictionary', {
        'raw': antenna,
        'pinyin': '',
        'abbreviation': '',
      });
      _antennaDict.add(DictionaryItem(raw: antenna, pinyin: '', abbreviation: ''));
      _antennaDict.sort((a, b) => a.raw.compareTo(b.raw));
      notifyListeners();
    }
  }

  Future<void> addCallsign(String callsign) async {
    if (callsign.isNotEmpty && !_callsignDict.any((c) => c.raw == callsign)) {
      final db = DatabaseHelper();
      await db.insertDictionaryItem('callsign_dictionary', {
        'raw': callsign,
        'pinyin': '',
        'abbreviation': '',
      });
      _callsignDict.add(DictionaryItem(raw: callsign, pinyin: '', abbreviation: ''));
      _callsignDict.sort((a, b) => a.raw.compareTo(b.raw));
      notifyListeners();
    }
  }

  Future<void> addQth(String qth) async {
    if (qth.isNotEmpty && !_qthDict.any((q) => q.raw == qth)) {
      final db = DatabaseHelper();
      await db.insertDictionaryItem('qth_dictionary', {
        'raw': qth,
        'pinyin': '',
        'abbreviation': '',
      });
      _qthDict.add(DictionaryItem(raw: qth, pinyin: '', abbreviation: ''));
      _qthDict.sort((a, b) => a.raw.compareTo(b.raw));
      notifyListeners();
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
        _deviceDict.add(DictionaryItem(raw: device, pinyin: '', abbreviation: ''));
      }
    }
    _deviceDict.sort((a, b) => a.raw.compareTo(b.raw));
    notifyListeners();
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
        _antennaDict.add(DictionaryItem(raw: antenna, pinyin: '', abbreviation: ''));
      }
    }
    _antennaDict.sort((a, b) => a.raw.compareTo(b.raw));
    notifyListeners();
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
        _callsignDict.add(DictionaryItem(raw: callsign, pinyin: '', abbreviation: ''));
      }
    }
    _callsignDict.sort((a, b) => a.raw.compareTo(b.raw));
    notifyListeners();
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
        _qthDict.add(DictionaryItem(raw: qth, pinyin: '', abbreviation: ''));
      }
    }
    _qthDict.sort((a, b) => a.raw.compareTo(b.raw));
    notifyListeners();
  }

  Future<void> clearDeviceDict() async {
    final db = DatabaseHelper();
    await db.clearDictionary('device_dictionary');
    _deviceDict.clear();
    notifyListeners();
  }

  Future<void> clearAntennaDict() async {
    final db = DatabaseHelper();
    await db.clearDictionary('antenna_dictionary');
    _antennaDict.clear();
    notifyListeners();
  }

  Future<void> clearCallsignDict() async {
    final db = DatabaseHelper();
    await db.clearDictionary('callsign_dictionary');
    _callsignDict.clear();
    notifyListeners();
  }

  Future<void> clearQthDict() async {
    final db = DatabaseHelper();
    await db.clearDictionary('qth_dictionary');
    _qthDict.clear();
    notifyListeners();
  }

  Future<void> resetDictionaries() async {
    final db = DatabaseHelper();
    await db.resetDictionaries();
    await _loadDictionaries();
  }

  Future<void> resetAllData() async {
    final db = DatabaseHelper();
    await db.resetAllData();
    await _loadDictionaries();
  }
}