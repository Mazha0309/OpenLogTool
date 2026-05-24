import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

class CollaborationService {
  static const Duration _timeout = Duration(seconds: 10);

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
        .replaceAll(RegExp(r'/$'), '');
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
          } catch (e) {
            debugPrint('[Collaboration] decode failed: $e');
          }
        },
        onError: (e) {
          debugPrint('[Collaboration] ws error: $e');
          _scheduleReconnect();
        },
        onDone: () => _scheduleReconnect(),
      );
    } catch (e) {
      debugPrint('[Collaboration] connect failed: $e');
    }
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

  Future<bool> pushLogUpsert(
      String sessionId, Map<String, dynamic> log, String deviceId) async {
    if (_serverWsUrl == null) return false;
    try {
      final baseUrl = _serverWsUrl!.replaceAll(RegExp(r'^ws'), 'http');
      final uri = Uri.parse(
          '$baseUrl/api/v1/logs/sessions/$sessionId/logs/upsert');
      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_token',
            },
            body: json.encode({'deviceId': deviceId, 'log': log}),
          )
          .timeout(_timeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return true;
      }
      debugPrint(
          '[Collaboration] pushLogUpsert failed: ${response.statusCode}');
      return false;
    } catch (e) {
      debugPrint('[Collaboration] pushLogUpsert error: $e');
      return false;
    }
  }

  Future<bool> pushLogDelete(
      String sessionId, String syncId, String deviceId) async {
    if (_serverWsUrl == null) return false;
    try {
      final baseUrl = _serverWsUrl!.replaceAll(RegExp(r'^ws'), 'http');
      final uri =
          Uri.parse('$baseUrl/api/v1/logs/sessions/$sessionId/logs/$syncId');
      final response = await http
          .delete(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_token',
            },
            body: json.encode({
              'deviceId': deviceId,
              'deleted_at': DateTime.now().toUtc().toIso8601String(),
            }),
          )
          .timeout(_timeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return true;
      }
      debugPrint(
          '[Collaboration] pushLogDelete failed: ${response.statusCode}');
      return false;
    } catch (e) {
      debugPrint('[Collaboration] pushLogDelete error: $e');
      return false;
    }
  }

  void disconnect() {
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    _subscription = null;
    _currentSessionId = null;
  }
}
