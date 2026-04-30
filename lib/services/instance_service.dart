import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

class InstanceService {
  static const _key = 'client_instance_id';
  static String? _cached;

  static Future<String> getInstanceId() async {
    if (_cached != null) return _cached!;

    final prefs = await SharedPreferences.getInstance();
    _cached = prefs.getString(_key);

    if (_cached == null || _cached!.isEmpty) {
      _cached = _generateId();
      await prefs.setString(_key, _cached!);
    }

    return _cached!;
  }

  static String _generateId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    _cached = null;
  }
}
