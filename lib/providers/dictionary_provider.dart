import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    final prefs = await SharedPreferences.getInstance();
    
    _deviceDict = prefs.getStringList('deviceDict') ?? [];
    _antennaDict = prefs.getStringList('antennaDict') ?? [];
    _callsignDict = prefs.getStringList('callsignDict') ?? [];
    _qthDict = prefs.getStringList('qthDict') ?? [];
    
    notifyListeners();
  }

  Future<void> _saveDictionary(String key, List<String> dict) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(key, dict);
  }

  Future<void> addDevice(String device) async {
    if (device.isNotEmpty && !_deviceDict.contains(device)) {
      _deviceDict.add(device);
      _deviceDict.sort();
      await _saveDictionary('deviceDict', _deviceDict);
      notifyListeners();
    }
  }

  Future<void> addAntenna(String antenna) async {
    if (antenna.isNotEmpty && !_antennaDict.contains(antenna)) {
      _antennaDict.add(antenna);
      _antennaDict.sort();
      await _saveDictionary('antennaDict', _antennaDict);
      notifyListeners();
    }
  }

  Future<void> addCallsign(String callsign) async {
    if (callsign.isNotEmpty && !_callsignDict.contains(callsign)) {
      _callsignDict.add(callsign);
      _callsignDict.sort();
      await _saveDictionary('callsignDict', _callsignDict);
      notifyListeners();
    }
  }

  Future<void> addQth(String qth) async {
    if (qth.isNotEmpty && !_qthDict.contains(qth)) {
      _qthDict.add(qth);
      _qthDict.sort();
      await _saveDictionary('qthDict', _qthDict);
      notifyListeners();
    }
  }

  Future<void> importDevices(List<String> devices) async {
    final currentSet = Set<String>.from(_deviceDict);
    currentSet.addAll(devices);
    _deviceDict = currentSet.toList()..sort();
    await _saveDictionary('deviceDict', _deviceDict);
    notifyListeners();
  }

  Future<void> importAntennas(List<String> antennas) async {
    final currentSet = Set<String>.from(_antennaDict);
    currentSet.addAll(antennas);
    _antennaDict = currentSet.toList()..sort();
    await _saveDictionary('antennaDict', _antennaDict);
    notifyListeners();
  }

  Future<void> importCallsigns(List<String> callsigns) async {
    final currentSet = Set<String>.from(_callsignDict);
    currentSet.addAll(callsigns);
    _callsignDict = currentSet.toList()..sort();
    await _saveDictionary('callsignDict', _callsignDict);
    notifyListeners();
  }

  Future<void> importQths(List<String> qths) async {
    final currentSet = Set<String>.from(_qthDict);
    currentSet.addAll(qths);
    _qthDict = currentSet.toList()..sort();
    await _saveDictionary('qthDict', _qthDict);
    notifyListeners();
  }

  Future<void> clearDeviceDict() async {
    _deviceDict.clear();
    await _saveDictionary('deviceDict', _deviceDict);
    notifyListeners();
  }

  Future<void> clearAntennaDict() async {
    _antennaDict.clear();
    await _saveDictionary('antennaDict', _antennaDict);
    notifyListeners();
  }

  Future<void> clearCallsignDict() async {
    _callsignDict.clear();
    await _saveDictionary('callsignDict', _callsignDict);
    notifyListeners();
  }

  Future<void> clearQthDict() async {
    _qthDict.clear();
    await _saveDictionary('qthDict', _qthDict);
    notifyListeners();
  }
}