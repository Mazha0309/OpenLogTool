import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openlogtool/services/ai_recognition/ai_recognition.dart';

void main() {
  group('OpenAI audio transcriptions protocol', () {
    test('sends configured model and audio as multipart data', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(
          request.url,
          Uri.parse('https://speech.example.test/v1/audio/transcriptions'),
        );
        expect(request.headers['authorization'], 'Bearer runtime-key');
        expect(request.headers['x-tenant'], 'club-1');
        final contentType = request.headers['content-type'];
        expect(contentType, startsWith('multipart/form-data; boundary='));
        final body = utf8.decode(request.bodyBytes);
        expect(body, contains('name="model"\r\n\r\nchosen-asr-model'));
        expect(body, contains('name="language"\r\n\r\nzh'));
        expect(body, contains('name="prompt"\r\n\r\nBG5CRL'));
        expect(body, contains('name="file"; filename="radio.wav"'));
        expect(body, contains('Content-Type: audio/wav'));
        expect(body, contains('audio-bytes'));
        return _jsonResponse({'text': 'BG5CRL 59'});
      });
      final provider = ProtocolAsrProvider(
        profile: _asrProfile(
          protocol: AiProtocol.openAiAudioTranscriptions,
          baseUrl: 'https://speech.example.test/v1',
          model: 'chosen-asr-model',
          headers: const {'X-Tenant': 'club-1'},
        ),
        httpClient: client,
      );
      addTearDown(provider.close);

      final result = await provider.transcribe(
        _audio(),
        languageHint: 'zh',
        prompt: 'BG5CRL',
        options: AiRequestOptions(
          credentials: AiCredentials(apiKey: 'runtime-key'),
        ),
      );

      expect(result.text, 'BG5CRL 59');
      expect(result.metadata['model'], 'chosen-asr-model');
    });

    test('resolves a credential reference at request time', () async {
      final profile = _asrProfile(
        protocol: AiProtocol.openAiAudioTranscriptions,
        credentialId: 'asr-key-ref',
      );
      final client = MockClient((request) async {
        expect(request.headers['authorization'], 'Bearer resolved-key');
        return _jsonResponse({'text': 'resolved'});
      });
      final provider = ProtocolAsrProvider(
        profile: profile,
        httpClient: client,
      );
      addTearDown(provider.close);

      final result = await provider.transcribe(
        _audio(),
        options: AiRequestOptions(
          credentialResolver: (request) {
            expect(request.providerId, 'asr-profile');
            expect(request.credentialId, 'asr-key-ref');
            return AiCredentials(apiKey: 'resolved-key');
          },
        ),
      );

      expect(result.text, 'resolved');
    });
  });

  group('OpenAI chat input_audio protocol', () {
    test('encodes input_audio using the configured model', () async {
      final client = MockClient((request) async {
        expect(
          request.url,
          Uri.parse('https://chat.example.test/v1/chat/completions'),
        );
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['model'], 'audio-chat-model');
        final messages = body['messages'] as List<dynamic>;
        final user = messages.single as Map<String, dynamic>;
        final content = user['content'] as List<dynamic>;
        expect(content.first, {'type': 'text', 'text': 'radio context'});
        expect(content.last, {
          'type': 'input_audio',
          'input_audio': {
            'data': base64Encode(utf8.encode('audio-bytes')),
            'format': 'wav',
          },
        });
        return _jsonResponse({
          'choices': [
            {
              'message': {
                'content': [
                  {'type': 'text', 'text': 'CQ '},
                  {'type': 'text', 'text': 'TEST'},
                ],
              },
            },
          ],
        });
      });
      final provider = ProtocolAsrProvider(
        profile: _asrProfile(
          protocol: AiProtocol.openAiChatCompletionsAudio,
          baseUrl: 'https://chat.example.test',
          model: 'audio-chat-model',
        ),
        httpClient: client,
      );
      addTearDown(provider.close);

      final result = await provider.transcribe(
        _audio(),
        prompt: 'radio context',
        options: AiRequestOptions(
          credentials: AiCredentials(apiKey: 'key'),
        ),
      );

      expect(result.text, 'CQ TEST');
    });

    test('supports data URL audio and an omitted format field', () async {
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final messages = body['messages'] as List<dynamic>;
        final user = messages.single as Map<String, dynamic>;
        final content = user['content'] as List<dynamic>;
        final audioPart = content.single as Map<String, dynamic>;
        expect(audioPart['input_audio'], {
          'data': 'data:audio/wav;base64,'
              '${base64Encode(utf8.encode('audio-bytes'))}',
        });
        return _jsonResponse({
          'choices': [
            {
              'message': {'content': 'data url accepted'},
            },
          ],
        });
      });
      final provider = ProtocolAsrProvider(
        profile: _asrProfile(
          protocol: AiProtocol.openAiChatCompletionsAudio,
          requestOptions: const {
            'audioDataEncoding': 'dataUrl',
            'includeAudioFormat': false,
            'includePrompt': false,
            'responsePath': 'choices[0].message.content',
          },
        ),
        httpClient: client,
      );
      addTearDown(provider.close);

      final result = await provider.transcribe(
        _audio(),
        prompt: 'this prompt must not be included',
        options: AiRequestOptions(
          credentials: AiCredentials(apiKey: 'key'),
        ),
      );

      expect(result.text, 'data url accepted');
    });
  });

  group('generic JSON HTTP protocol', () {
    test('renders an ASR request template and configured response path',
        () async {
      final client = MockClient((request) async {
        expect(request.method, 'PUT');
        expect(
          request.url,
          Uri.parse('https://gateway.example.test/api/asr'),
        );
        expect(request.headers['x-provider-key'], 'Token runtime-json-key');
        expect(request.headers['x-station'], 'B1');
        expect(jsonDecode(request.body), {
          'selected_model': 'vendor-model-from-config',
          'payload': {
            'content': base64Encode(utf8.encode('audio-bytes')),
            'mime': 'audio/wav',
          },
          'hint': 'en',
        });
        return _jsonResponse({
          'result': {'transcript': 'K1ABC five nine'},
        });
      });
      final profile = _asrProfile(
        protocol: AiProtocol.jsonHttp,
        baseUrl: 'https://gateway.example.test/api',
        model: 'vendor-model-from-config',
        headers: const {'X-Station': 'B1'},
        requestOptions: const {
          'path': 'asr',
          'method': 'PUT',
          'requestTemplate': {
            'selected_model': '{{model}}',
            'payload': {
              'content': '{{audio.base64}}',
              'mime': '{{audio.mimeType}}',
            },
            'hint': '{{language}}',
          },
          'responsePath': 'result.transcript',
        },
        credentialTransport: AiCredentialTransport.header(
          name: 'X-Provider-Key',
          prefix: 'Token ',
        ),
      );
      final provider = ProtocolAsrProvider(
        profile: profile,
        httpClient: client,
      );
      addTearDown(provider.close);

      final result = await provider.transcribe(
        _audio(),
        languageHint: 'en',
        options: AiRequestOptions(
          credentials: AiCredentials(apiKey: 'runtime-json-key'),
        ),
      );

      expect(result.text, 'K1ABC five nine');
    });

    test('extracts model-neutral candidate field maps', () async {
      final client = MockClient((request) async {
        expect(jsonDecode(request.body), {
          'model': 'extractor-selected-by-user',
          'heard': 'BG5CRL 59 Zhejiang',
          'rules': 'Return candidate fields',
        });
        return _jsonResponse({
          'data': {
            'candidates': [
              {'callsign': 'BG5CRL', 'rst': '59', 'qth': 'Zhejiang'},
              {'callsign': 'BG5CRL', 'rst': '59'},
            ],
          },
        });
      });
      final profile = AiProviderProfile(
        id: 'extract-profile',
        name: 'Configurable extractor',
        kind: AiProviderKind.fieldExtraction,
        protocol: AiProtocol.jsonHttp,
        baseUrl: Uri.parse('https://extract.example.test'),
        model: 'extractor-selected-by-user',
        requestOptions: const {
          'requestTemplate': {
            'model': '{{model}}',
            'heard': '{{transcription.text}}',
            'rules': '{{instructions}}',
          },
          'responsePath': 'data.candidates',
        },
        credentialTransport: const AiCredentialTransport.none(),
      );
      final provider = ProtocolFieldExtractionProvider(
        profile: profile,
        httpClient: client,
      );
      addTearDown(provider.close);

      final candidates = await provider.extract(
        Transcription(text: 'BG5CRL 59 Zhejiang'),
        instructions: 'Return candidate fields',
      );

      expect(candidates, hasLength(2));
      expect(candidates.first.fields['callsign'], 'BG5CRL');
      expect(candidates.first.fields['qth'], 'Zhejiang');
      expect(candidates.first.sourceText, 'BG5CRL 59 Zhejiang');
    });
  });
}

AiProviderProfile _asrProfile({
  required AiProtocol protocol,
  String baseUrl = 'https://speech.example.test',
  String model = 'configured-model',
  Map<String, String> headers = const {},
  AiJsonObject requestOptions = const {},
  String? credentialId,
  AiCredentialTransport credentialTransport =
      const AiCredentialTransport.bearer(),
}) =>
    AiProviderProfile(
      id: 'asr-profile',
      name: 'ASR profile',
      kind: AiProviderKind.speechRecognition,
      protocol: protocol,
      baseUrl: Uri.parse(baseUrl),
      model: model,
      headers: headers,
      requestOptions: requestOptions,
      capabilities: const AiProviderCapabilities(
        supportsAudioTranscription: true,
        supportsLanguageHint: true,
        supportsPrompt: true,
        supportedAudioMimeTypes: {'audio/wav'},
      ),
      credentialId: credentialId,
      credentialTransport: credentialTransport,
    );

AudioSegment _audio() => AudioSegment(
      bytes: utf8.encode('audio-bytes'),
      mimeType: 'audio/wav',
      fileName: 'radio.wav',
    );

http.Response _jsonResponse(Object? body, [int statusCode = 200]) =>
    http.Response(
      jsonEncode(body),
      statusCode,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
