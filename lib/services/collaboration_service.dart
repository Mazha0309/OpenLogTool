import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

class CollaborationService {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  String? _serverWsUrl;
  String? _token;
  String? _currentSessionId;
  String? _deviceId;

  Function(Map<String, dynamic>)? onLogUpserted;
  Function(Map<String, dynamic>)? onLogDeleted;

  void connect({
    required String serverUrl,
    required String token,
    required String sessionId,
    required String deviceId,
  }) {
    disconnect();
    _token = token;
    _currentSessionId = sessionId;
    _deviceId = deviceId;
    _serverWsUrl = serverUrl
        .replaceAll(RegExp(r'^http'), 'ws')
        .replaceAll(RegExp(r'/\$'), '');
    _connectWs();
  }

  void _connectWs() {
    try {
      final uri = Uri.parse('$_serverWsUrl/ws?sessionId=$_currentSessionId&deviceId=$_deviceId');
      _channel = WebSocketChannel.connect(uri);
      _subscription = _channel!.stream.listen(
        (data) {
          try {
            final msg = json.decode(data as String);
            _handleMessage(msg);
          } catch (_) {}
        },
        onError: (_) => _scheduleReconnect(),
        onDone: () => _scheduleReconnect(),
      );
    } catch (_) {}
  }

  void _handleMessage(Map<String, dynamic> msg) {
    final type = msg['type'];
    final sourceDeviceId = msg['source_device_id'];
    if (sourceDeviceId == _deviceId) return; // ignore own messages

    if (type == 'log.upserted' && onLogUpserted != null) {
      onLogUpserted!(msg['log'] ?? {});
    } else if (type == 'log.deleted' && onLogDeleted != null) {
      onLogDeleted!(msg);
    }
  }

  void _scheduleReconnect() {
    _subscription?.cancel();
    _channel?.sink.close();
    Future.delayed(const Duration(seconds: 3), () {
      if (_currentSessionId != null) _connectWs();
    });
  }

  Future<void> pushLogUpsert(String sessionId, Map<String, dynamic> log, String deviceId) async {
    try {
      final uri = Uri.parse('$_serverWsUrl/api/v1/logs/sessions/$sessionId/logs/upsert');
      await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
        body: json.encode({'deviceId': deviceId, 'log': log}),
      );
    } catch (_) {}
  }

  Future<void> pushLogDelete(String sessionId, String syncId, String deviceId) async {
    try {
      final uri = Uri.parse('$_serverWsUrl/api/v1/logs/sessions/$sessionId/logs/$syncId');
      await http.delete(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
        body: json.encode({'deviceId': deviceId, 'deleted_at': DateTime.now().toUtc().toIso8601String()}),
      );
    } catch (_) {}
  }

  void disconnect() {
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    _subscription = null;
    _currentSessionId = null;
  }
}
