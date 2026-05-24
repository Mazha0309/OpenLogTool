import 'package:flutter/material.dart';

class SnackbarLogEntry {
  final String message;
  final String type;
  final String source;
  final DateTime createdAt;

  const SnackbarLogEntry({
    required this.message,
    required this.type,
    required this.source,
    required this.createdAt,
  });
}

class SnackbarLogProvider with ChangeNotifier {
  final List<SnackbarLogEntry> _entries = <SnackbarLogEntry>[];
  List<SnackbarLogEntry>? _reversedCache;

  List<SnackbarLogEntry> get entries =>
      _reversedCache ??= List<SnackbarLogEntry>.unmodifiable(_entries.reversed);

  void add({
    required String message,
    required String type,
    required String source,
  }) {
    _entries.add(
      SnackbarLogEntry(
        message: message,
        type: type,
        source: source,
        createdAt: DateTime.now(),
      ),
    );
    _reversedCache = null;
    notifyListeners();
  }

  void clear() {
    _entries.clear();
    _reversedCache = null;
    notifyListeners();
  }
}
