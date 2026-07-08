import 'package:flutter/foundation.dart';
import 'package:openlogtool/src/bridge/rust_api.dart';
import 'package:openlogtool/src/bridge/models/session.dart';

class RustSessionProvider extends ChangeNotifier {
  Session? _currentSession;
  List<Session> _sessions = [];
  bool _loading = false;
  String? _error;

  Session? get currentSession => _currentSession;
  List<Session> get sessions => _sessions;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> loadSessions() async {
    _loading = true;
    notifyListeners();
    try {
      _sessions = await RustApi.listSessions();
      _error = null;
    } catch (e) {
      _error = e.toString();
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> createSession(String title) async {
    try {
      final session = await RustApi.createSession(title: title);
      _currentSession = session;
      await loadSessions();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> closeSession(String sessionId) async {
    try {
      await RustApi.closeSession(sessionId: sessionId);
      if (_currentSession?.session_id == sessionId) {
        _currentSession = null;
      }
      await loadSessions();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> joinSession(String shareCode) async {
    try {
      _currentSession = await RustApi.joinSession(shareCode: shareCode);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  void selectSession(Session session) {
    _currentSession = session;
    notifyListeners();
  }
}
