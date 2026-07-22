import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openlogtool/services/text_assistant.dart';
import 'package:openlogtool/services/text_assistant_tasks.dart';

void main() {
  test('OpenAI preset requests JSON with low-latency reasoning disabled',
      () async {
    late Map<String, Object?> body;
    final client = TextAssistantClient(
      config: TextAssistantConfig(
        provider: TextAssistantProvider.openAi,
        baseUrl: Uri.parse('https://api.openai.com/v1'),
        model: 'gpt-test',
        credentialId: 'key',
      ),
      secretResolver: (_) async => 'secret',
      httpClient: MockClient((request) async {
        expect(request.url.toString(),
            'https://api.openai.com/v1/chat/completions');
        expect(request.headers['authorization'], 'Bearer secret');
        body = Map<String, Object?>.from(jsonDecode(request.body) as Map);
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': '```json\n{"suggestion":"5 W"}\n```'}
              }
            ]
          }),
          200,
        );
      }),
    );

    final result = await client.completeJson(
      systemPrompt: 'system',
      userPrompt: 'user',
      maxOutputTokens: 80,
    );

    expect(result, {'suggestion': '5 W'});
    expect(body['reasoning_effort'], 'none');
    expect(body['temperature'], 0);
    expect(body['response_format'], {'type': 'json_object'});
    expect(body.containsKey('thinking'), isFalse);
    client.close();
  });

  test('compatible preset retries once without unsupported optional fields',
      () async {
    final requests = <Map<String, Object?>>[];
    final client = TextAssistantClient(
      config: TextAssistantConfig(
        provider: TextAssistantProvider.openAiCompatible,
        baseUrl: Uri.parse('https://llm.example/v1'),
        model: 'fast-model',
        credentialId: 'key',
      ),
      secretResolver: (_) async => 'secret',
      httpClient: MockClient((request) async {
        requests
            .add(Map<String, Object?>.from(jsonDecode(request.body) as Map));
        if (requests.length == 1) return http.Response('unsupported', 400);
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': '{"ok":true}'}
              }
            ]
          }),
          200,
        );
      }),
    );

    expect(
      await client.completeJson(systemPrompt: 'system', userPrompt: 'user'),
      {'ok': true},
    );
    expect(requests, hasLength(2));
    expect(requests.first['enable_thinking'], false);
    expect(requests.first['reasoning_effort'], 'none');
    expect(requests.last.containsKey('enable_thinking'), false);
    expect(requests.last.containsKey('reasoning_effort'), false);
    expect(requests.last.containsKey('response_format'), false);
    client.close();
  });

  test('Anthropic preset uses Messages API and omits extended thinking',
      () async {
    late Map<String, Object?> body;
    final client = TextAssistantClient(
      config: TextAssistantConfig(
        provider: TextAssistantProvider.anthropic,
        baseUrl: Uri.parse('https://api.anthropic.com'),
        model: 'claude-test',
        credentialId: 'key',
      ),
      secretResolver: (_) async => 'anthropic-secret',
      httpClient: MockClient((request) async {
        expect(request.url.toString(), 'https://api.anthropic.com/v1/messages');
        expect(request.headers['x-api-key'], 'anthropic-secret');
        expect(request.headers['anthropic-version'], '2023-06-01');
        body = Map<String, Object?>.from(jsonDecode(request.body) as Map);
        return http.Response(
          jsonEncode({
            'content': [
              {'type': 'text', 'text': '{"suggestion":"FT-991A"}'}
            ]
          }),
          200,
        );
      }),
    );

    expect(
      await client.completeJson(systemPrompt: 'system', userPrompt: 'user'),
      {'suggestion': 'FT-991A'},
    );
    expect(body.containsKey('thinking'), false);
    expect(body['system'], 'system');
    client.close();
  });

  test('dictionary aggregate parser and reviewed operation stay structured',
      () {
    final source = DictionaryAiSource.fromJson(jsonEncode({
      'version': 1,
      'stateToken': 'token',
      'recordCount': 3,
      'dictionaries': {
        'device': [
          {'value': 'FT-991A', 'origin': 'user'}
        ],
        'antenna': [],
        'callsign': [],
        'qth': [],
      },
      'history': {
        'device': [
          {'value': 'FT991A', 'count': 2}
        ],
        'antenna': [],
        'callsign': [],
        'qth': [],
      },
    }));
    const suggestion = DictionaryAiSuggestion(
      category: DictionaryAiCategory.device,
      action: DictionaryAiAction.rename,
      source: 'FT991A',
      target: 'FT-991A',
      reason: 'Normalize model name',
    );

    expect(source.recordCount, 3);
    expect(source.history[DictionaryAiCategory.device]!.single.count, 2);
    expect(suggestion.toApplyJson(), containsPair('source', 'FT991A'));
    expect(suggestion.toApplyJson(), containsPair('target', 'FT-991A'));
    expect(suggestion.toApplyJson()['dictType'], 'device_dictionary');
  });
}
