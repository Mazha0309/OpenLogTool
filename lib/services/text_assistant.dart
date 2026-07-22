import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:openlogtool/services/ai_recognition/errors.dart';
import 'package:openlogtool/services/ai_recognition/providers.dart';

enum TextAssistantProvider {
  openAi,
  anthropic,
  openAiCompatible;

  static TextAssistantProvider fromJson(Object? value) {
    if (value is String) {
      for (final provider in values) {
        if (provider.name == value) return provider;
      }
    }
    throw FormatException('Unsupported text assistant provider: $value');
  }
}

final class TextAssistantConfig {
  TextAssistantConfig({
    required this.provider,
    required Uri baseUrl,
    required String model,
    required String credentialId,
  })  : baseUrl = _validatedBaseUrl(baseUrl),
        model = _required(model, 'model'),
        credentialId = _required(credentialId, 'credentialId');

  factory TextAssistantConfig.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Text assistant configuration is invalid');
    }
    final json = Map<String, Object?>.from(value);
    final baseUrl = Uri.tryParse(json['baseUrl']?.toString() ?? '');
    if (baseUrl == null) {
      throw const FormatException('Text assistant Base URL is invalid');
    }
    return TextAssistantConfig(
      provider: TextAssistantProvider.fromJson(json['provider']),
      baseUrl: baseUrl,
      model: json['model']?.toString() ?? '',
      credentialId: json['credentialId']?.toString() ?? '',
    );
  }

  final TextAssistantProvider provider;
  final Uri baseUrl;
  final String model;
  final String credentialId;

  Map<String, Object?> toJson() => <String, Object?>{
        'provider': provider.name,
        'baseUrl': baseUrl.toString(),
        'model': model,
        'credentialId': credentialId,
      };

  String get signature => '${provider.name}|$baseUrl|$model|$credentialId';
}

typedef TextAssistantSecretResolver = Future<String?> Function(
  String credentialId,
);

/// Small JSON-only client shared by field extraction, inline normalization,
/// and dictionary maintenance. Credentials are resolved for each request and
/// never become part of the serializable configuration.
final class TextAssistantClient {
  TextAssistantClient({
    required this.config,
    required TextAssistantSecretResolver secretResolver,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 30),
  })  : _secretResolver = secretResolver,
        _client = httpClient ?? http.Client(),
        _ownsClient = httpClient == null;

  final TextAssistantConfig config;
  final Duration timeout;
  final TextAssistantSecretResolver _secretResolver;
  final http.Client _client;
  final bool _ownsClient;
  bool _closed = false;

  Future<Map<String, Object?>> completeJson({
    required String systemPrompt,
    required String userPrompt,
    AiCancellationToken? cancellationToken,
    int maxOutputTokens = 512,
  }) async {
    if (_closed) throw StateError('TEXT_ASSISTANT_CLOSED');
    cancellationToken?.throwIfCancelled(providerId: 'text-assistant');
    final secret = await _secretResolver(config.credentialId);
    if (secret == null || secret.trim().isEmpty) {
      throw StateError('TEXT_ASSISTANT_API_KEY_REQUIRED');
    }
    cancellationToken?.throwIfCancelled(providerId: 'text-assistant');

    final responseText = switch (config.provider) {
      TextAssistantProvider.anthropic => _completeAnthropic(
          secret: secret,
          systemPrompt: systemPrompt,
          userPrompt: userPrompt,
          maxOutputTokens: maxOutputTokens,
          cancellationToken: cancellationToken,
        ),
      TextAssistantProvider.openAi ||
      TextAssistantProvider.openAiCompatible =>
        _completeOpenAi(
          secret: secret,
          systemPrompt: systemPrompt,
          userPrompt: userPrompt,
          maxOutputTokens: maxOutputTokens,
          cancellationToken: cancellationToken,
        ),
    };
    return _decodeJsonObject(await responseText);
  }

  Future<String> _completeOpenAi({
    required String secret,
    required String systemPrompt,
    required String userPrompt,
    required int maxOutputTokens,
    required AiCancellationToken? cancellationToken,
  }) async {
    final endpoint = _endpoint(config.baseUrl, const ['chat', 'completions']);
    final baseBody = <String, Object?>{
      'model': config.model,
      'messages': <Object?>[
        <String, Object?>{'role': 'system', 'content': systemPrompt},
        <String, Object?>{'role': 'user', 'content': userPrompt},
      ],
      'stream': false,
    };
    final fastBody = <String, Object?>{
      ...baseBody,
      'temperature': 0,
      'max_tokens': maxOutputTokens,
      'response_format': <String, Object?>{'type': 'json_object'},
      'reasoning_effort': 'none',
      if (config.provider == TextAssistantProvider.openAiCompatible)
        'enable_thinking': false,
    };
    var response = await _postJson(
      endpoint,
      headers: <String, String>{'authorization': 'Bearer ${secret.trim()}'},
      body: fastBody,
      cancellationToken: cancellationToken,
      allowHttpError: true,
    );
    // OpenAI-compatible servers differ on optional reasoning/JSON fields. A
    // single conservative retry keeps the simple preset usable without an
    // advanced request-options editor.
    if (response.statusCode == 400 || response.statusCode == 422) {
      response = await _postJson(
        endpoint,
        headers: <String, String>{'authorization': 'Bearer ${secret.trim()}'},
        body: <String, Object?>{
          ...baseBody,
          'max_tokens': maxOutputTokens,
        },
        cancellationToken: cancellationToken,
        allowHttpError: true,
      );
    }
    _requireSuccess(response);
    final decoded = _decodeResponseObject(response);
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      throw StateError('TEXT_ASSISTANT_INVALID_RESPONSE');
    }
    final message = (choices.first as Map)['message'];
    if (message is! Map) throw StateError('TEXT_ASSISTANT_INVALID_RESPONSE');
    final content = message['content'];
    if (content is String && content.trim().isNotEmpty) return content;
    throw StateError('TEXT_ASSISTANT_EMPTY_RESPONSE');
  }

  Future<String> _completeAnthropic({
    required String secret,
    required String systemPrompt,
    required String userPrompt,
    required int maxOutputTokens,
    required AiCancellationToken? cancellationToken,
  }) async {
    final response = await _postJson(
      _endpoint(config.baseUrl, const ['v1', 'messages']),
      headers: <String, String>{
        'x-api-key': secret.trim(),
        'anthropic-version': '2023-06-01',
      },
      body: <String, Object?>{
        'model': config.model,
        'system': systemPrompt,
        'messages': <Object?>[
          <String, Object?>{'role': 'user', 'content': userPrompt},
        ],
        'max_tokens': maxOutputTokens,
        'temperature': 0,
        // Extended thinking is intentionally omitted for low-latency tasks.
      },
      cancellationToken: cancellationToken,
      allowHttpError: true,
    );
    _requireSuccess(response);
    final decoded = _decodeResponseObject(response);
    final content = decoded['content'];
    if (content is! List) throw StateError('TEXT_ASSISTANT_INVALID_RESPONSE');
    final text = content
        .whereType<Map>()
        .where((item) => item['type'] == 'text' && item['text'] is String)
        .map((item) => item['text'] as String)
        .join();
    if (text.trim().isEmpty) throw StateError('TEXT_ASSISTANT_EMPTY_RESPONSE');
    return text;
  }

  Future<http.Response> _postJson(
    Uri uri, {
    required Map<String, String> headers,
    required Map<String, Object?> body,
    required AiCancellationToken? cancellationToken,
    required bool allowHttpError,
  }) async {
    cancellationToken?.throwIfCancelled(providerId: 'text-assistant');
    final operation = _client
        .post(
          uri,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
            'accept': 'application/json',
            ...headers,
          },
          body: jsonEncode(body),
        )
        .timeout(timeout);
    final response = cancellationToken == null
        ? await operation
        : await Future.any<http.Response>(<Future<http.Response>>[
            operation,
            cancellationToken.whenCancelled.then<http.Response>((_) {
              throw const AiRecognitionException(
                kind: AiRecognitionErrorKind.cancelled,
                message: 'The text assistant request was cancelled',
                providerId: 'text-assistant',
              );
            }),
          ]);
    if (!allowHttpError) _requireSuccess(response);
    return response;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    if (_ownsClient) _client.close();
  }
}

Uri _endpoint(Uri base, List<String> suffix) {
  final segments = base.pathSegments.where((item) => item.isNotEmpty).toList();
  if (suffix.first == 'v1' && segments.isNotEmpty && segments.last == 'v1') {
    return base.replace(pathSegments: <String>[...segments, ...suffix.skip(1)]);
  }
  if (suffix.first != 'v1' && segments.isNotEmpty && segments.last == 'v1') {
    return base.replace(pathSegments: <String>[...segments, ...suffix]);
  }
  return base.replace(pathSegments: <String>[...segments, ...suffix]);
}

Map<String, Object?> _decodeResponseObject(http.Response response) {
  final decoded = jsonDecode(utf8.decode(response.bodyBytes));
  if (decoded is! Map) throw StateError('TEXT_ASSISTANT_INVALID_RESPONSE');
  return Map<String, Object?>.from(decoded);
}

Map<String, Object?> _decodeJsonObject(String text) {
  var source = text.trim();
  final fenced =
      RegExp(r'^```(?:json)?\s*([\s\S]*?)\s*```$', caseSensitive: false)
          .firstMatch(source);
  if (fenced != null) source = fenced.group(1)!.trim();
  try {
    final decoded = jsonDecode(source);
    if (decoded is Map) return Map<String, Object?>.from(decoded);
  } catch (_) {
    final start = source.indexOf('{');
    final end = source.lastIndexOf('}');
    if (start >= 0 && end > start) {
      final decoded = jsonDecode(source.substring(start, end + 1));
      if (decoded is Map) return Map<String, Object?>.from(decoded);
    }
  }
  throw StateError('TEXT_ASSISTANT_RESPONSE_NOT_JSON');
}

void _requireSuccess(http.Response response) {
  if (response.statusCode >= 200 && response.statusCode < 300) return;
  final body = utf8.decode(response.bodyBytes, allowMalformed: true);
  throw AiRecognitionException(
    kind: AiRecognitionErrorKind.httpStatus,
    message: 'The text assistant returned HTTP ${response.statusCode}',
    providerId: 'text-assistant',
    statusCode: response.statusCode,
    responseBody: body.length > 1000 ? body.substring(0, 1000) : body,
  );
}

Uri _validatedBaseUrl(Uri value) {
  if (!value.hasScheme ||
      (value.scheme != 'http' && value.scheme != 'https') ||
      value.host.isEmpty ||
      value.userInfo.isNotEmpty ||
      value.fragment.isNotEmpty) {
    throw ArgumentError.value(value, 'baseUrl', 'must be an absolute HTTP URL');
  }
  return value;
}

String _required(String value, String field) {
  final normalized = value.trim();
  if (normalized.isEmpty) throw ArgumentError.value(value, field, 'is empty');
  return normalized;
}
