import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openlogtool/services/text_assistant.dart';
import 'package:openlogtool/services/text_assistant_tasks.dart';

void main() {
  test('OpenAI preset uses Responses API with low-latency JSON output',
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
        expect(request.url.toString(), 'https://api.openai.com/v1/responses');
        expect(request.headers['authorization'], 'Bearer secret');
        body = Map<String, Object?>.from(jsonDecode(request.body) as Map);
        return http.Response(
          jsonEncode({
            'output': [
              {
                'type': 'reasoning',
                'summary': [],
              },
              {
                'type': 'message',
                'content': [
                  {
                    'type': 'output_text',
                    'text': '```json\n{"suggestion":"5 W"}\n```',
                  }
                ]
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
    expect(body['instructions'], 'system');
    expect(body['input'], 'user');
    expect(body['max_output_tokens'], 80);
    expect(body['reasoning'], {'effort': 'none'});
    expect(body['text'], {
      'format': {'type': 'json_object'}
    });
    expect(body.containsKey('messages'), isFalse);
    client.close();
  });

  test('compatible preset uses old Chat Completions protocol', () async {
    late Uri endpoint;
    late Map<String, Object?> body;
    final client = TextAssistantClient(
      config: TextAssistantConfig(
        provider: TextAssistantProvider.openAiCompatible,
        baseUrl: Uri.parse('https://llm.example/v1'),
        model: 'fast-model',
        credentialId: 'key',
      ),
      secretResolver: (_) async => 'secret',
      httpClient: MockClient((request) async {
        endpoint = request.url;
        body = Map<String, Object?>.from(jsonDecode(request.body) as Map);
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
    expect(endpoint.toString(), 'https://llm.example/v1/chat/completions');
    expect(body['messages'], [
      {'role': 'system', 'content': 'system'},
      {'role': 'user', 'content': 'user'},
    ]);
    expect(body['max_tokens'], 512);
    expect(body['response_format'], {'type': 'json_object'});
    expect(body.containsKey('instructions'), isFalse);
    expect(body.containsKey('input'), isFalse);
    expect(body.containsKey('reasoning_effort'), isFalse);
    expect(body.containsKey('enable_thinking'), isFalse);
    client.close();
  });

  test('compatible Chat preset retries without unsupported optional fields',
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
    expect(requests.first['temperature'], 0);
    expect(requests.first['response_format'], {'type': 'json_object'});
    expect(requests.last.containsKey('response_format'), false);
    expect(requests.last.containsKey('temperature'), false);
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
