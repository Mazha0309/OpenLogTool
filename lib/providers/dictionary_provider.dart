import 'package:flutter/material.dart';
import 'package:openlogtool/database/database_helper.dart';

class DictionaryProvider with ChangeNotifier {
  List<String> _deviceDict = [];
  List<String> _antennaDict = [];
  List<String> _callsignDict = [];
  List<String> _qthDict = [];

  List<String> get deviceDict => _deviceDict;
  List<String> get antennaDict => _antennaDict;
  List<String> get callsignDict => _callsignDict;
  List<String> get qthDict => _qthDict;

  DictionaryProvider() {
    _loadDictionaries();
  }

  Future<void> _loadDictionaries() async {
    final db = DatabaseHelper();
    _deviceDict = await db.getDictionaryRaw('device_dictionary');
    _antennaDict = await db.getDictionaryRaw('antenna_dictionary');
    _callsignDict = await db.getDictionaryRaw('callsign_dictionary');
    _qthDict = await db.getDictionaryRaw('qth_dictionary');

    if (_deviceDict.isEmpty && _antennaDict.isEmpty && _qthDict.isEmpty) {
      await db.loadInitialDictionaries();
      _deviceDict = await db.getDictionaryRaw('device_dictionary');
      _antennaDict = await db.getDictionaryRaw('antenna_dictionary');
      _qthDict = await db.getDictionaryRaw('qth_dictionary');
    }

    notifyListeners();
  }

  Future<void> addDevice(String device) async {
    if (device.isNotEmpty && !_deviceDict.contains(device)) {
      final db = DatabaseHelper();
      await db.insertDictionaryItem('device_dictionary', {'raw': device});
      _deviceDict.add(device);
      _deviceDict.sort();
      notifyListeners();
    }
  }

  Future<void> addAntenna(String antenna) async {
    if (antenna.isNotEmpty && !_antennaDict.contains(antenna)) {
      final db = DatabaseHelper();
      await db.insertDictionaryItem('antenna_dictionary', {'raw': antenna});
      _antennaDict.add(antenna);
      _antennaDict.sort();
      notifyListeners();
    }
  }

  Future<void> addCallsign(String callsign) async {
    if (callsign.isNotEmpty && !_callsignDict.contains(callsign)) {
      final db = DatabaseHelper();
      await db.insertDictionaryItem('callsign_dictionary', {'raw': callsign});
      _callsignDict.add(callsign);
      _callsignDict.sort();
      notifyListeners();
    }
  }

  Future<void> addQth(String qth) async {
    if (qth.isNotEmpty && !_qthDict.contains(qth)) {
      final db = DatabaseHelper();
      await db.insertDictionaryItem('qth_dictionary', {'raw': qth});
      _qthDict.add(qth);
      _qthDict.sort();
      notifyListeners();
    }
  }

  Future<void> importDevices(List<String> devices) async {
    final db = DatabaseHelper();
    final items = devices.map((d) => {'raw': d}).toList();
    await db.importDictionaryItems('device_dictionary', items);
    final currentSet = Set<String>.from(_deviceDict);
    currentSet.addAll(devices);
    _deviceDict = currentSet.toList()..sort();
    notifyListeners();
  }

  Future<void> importAntennas(List<String> antennas) async {
    final db = DatabaseHelper();
    final items = antennas.map((a) => {'raw': a}).toList();
    await db.importDictionaryItems('antenna_dictionary', items);
    final currentSet = Set<String>.from(_antennaDict);
    currentSet.addAll(antennas);
    _antennaDict = currentSet.toList()..sort();
    notifyListeners();
  }

  Future<void> importCallsigns(List<String> callsigns) async {
    final db = DatabaseHelper();
    final items = callsigns.map((c) => {'raw': c}).toList();
    await db.importDictionaryItems('callsign_dictionary', items);
    final currentSet = Set<String>.from(_callsignDict);
    currentSet.addAll(callsigns);
    _callsignDict = currentSet.toList()..sort();
    notifyListeners();
  }

  Future<void> importQths(List<String> qths) async {
    final db = DatabaseHelper();
    final items = qths.map((q) => {'raw': q}).toList();
    await db.importDictionaryItems('qth_dictionary', items);
    final currentSet = Set<String>.from(_qthDict);
    currentSet.addAll(qths);
    _qthDict = currentSet.toList()..sort();
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