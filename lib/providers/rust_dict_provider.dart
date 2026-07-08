import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:openlogtool/src/bridge/rust_api.dart';
import 'package:openlogtool/src/bridge/models/dict_item.dart';

class RustDictProvider extends ChangeNotifier {
  List<DictItem> _deviceDict = [];
  List<DictItem> _antennaDict = [];
  List<DictItem> _callsignDict = [];
  List<DictItem> _qthDict = [];
  bool _loading = false;
  String? _error;

  List<DictItem> get deviceDict => _deviceDict;
  List<DictItem> get antennaDict => _antennaDict;
  List<DictItem> get callsignDict => _callsignDict;
  List<DictItem> get qthDict => _qthDict;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> loadAll() async {
    _loading = true;
    notifyListeners();
    try {
      _deviceDict = await RustApi.searchDict(dictType: 'device', query: '', limit: 200);
      _antennaDict = await RustApi.searchDict(dictType: 'antenna', query: '', limit: 200);
      _callsignDict = await RustApi.searchDict(dictType: 'callsign', query: '', limit: 200);
      _qthDict = await RustApi.searchDict(dictType: 'qth', query: '', limit: 200);
      _error = null;
    } catch (e) {
      _error = e.toString();
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> seedFromAssets() async {
    try {
      final deviceJson = await rootBundle.loadString('assets/dictionaries/device.json');
      final deviceList = List<String>.from(jsonDecode(deviceJson));
      await RustApi.seedDict(dictType: 'device', items: deviceList);

      final antennaJson = await rootBundle.loadString('assets/dictionaries/antenna.json');
      final antennaList = List<String>.from(jsonDecode(antennaJson));
      await RustApi.seedDict(dictType: 'antenna', items: antennaList);

      final qthJson = await rootBundle.loadString('assets/dictionaries/qth.json');
      final qthList = List<String>.from(jsonDecode(qthJson));
      await RustApi.seedDict(dictType: 'qth', items: qthList);

      await loadAll();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> addDictItem(String dictType, String raw) async {
    try {
      await RustApi.addDictItem(dictType: dictType, raw: raw);
      await loadAll();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<List<DictItem>> search(String dictType, String query) async {
    return RustApi.searchDict(dictType: dictType, query: query);
  }
}
