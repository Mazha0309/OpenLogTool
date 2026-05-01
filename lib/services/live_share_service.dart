import 'dart:convert';
import 'package:http/http.dart' as http;

class LiveShareResult {
  final String url;
  final String shareCode;
  final String sessionId;

  LiveShareResult({required this.url, required this.shareCode, required this.sessionId});

  factory LiveShareResult.fromJson(Map<String, dynamic> json) {
    return LiveShareResult(
      url: json['url'] ?? '',
      shareCode: json['shareCode'] ?? '',
      sessionId: json['sessionId'] ?? '',
    );
  }
}

class LiveShareService {
  final String serverUrl;
  final String token;

  LiveShareService({required this.serverUrl, required this.token});

  Future<LiveShareResult?> createShareLink(String sessionId) async {
    try {
      final uri = Uri.parse('${serverUrl.replaceAll(RegExp(r'/\$'), '')}/api/v1/logs/sessions/$sessionId/public-link');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'enabled': true}),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['ok'] == true) return LiveShareResult.fromJson(data);
      }
    } catch (_) {}
    return null;
  }
}
