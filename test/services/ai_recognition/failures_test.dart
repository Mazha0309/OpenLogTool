import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openlogtool/services/ai_recognition/ai_recognition.dart';
import 'package:openlogtool/services/ai_recognition/http_transport.dart';

void main() {
  test('maps non-2xx responses to a stable HTTP failure', () async {
    final provider = _provider(
      MockClient((_) async => http.Response('temporarily unavailable', 503)),
    );
    addTearDown(provider.close);

    await expectLater(
      provider.transcribe(_audio()),
      throwsA(
        isA<AiRecognitionException>()
            .having(
              (error) => error.kind,
              'kind',
              AiRecognitionErrorKind.httpStatus,
            )
            .having((error) => error.statusCode, 'statusCode', 503)
            .having(
              (error) => error.responseBody,
              'responseBody',
              'temporarily unavailable',
            ),
      ),
    );
  });

  test('maps malformed success JSON to an invalid response', () async {
    final provider = _provider(
      MockClient((_) async => http.Response('{bad-json', 200)),
    );
    addTearDown(provider.close);

    await expectLater(
      provider.transcribe(_audio()),
      throwsA(
        isA<AiRecognitionException>().having(
          (error) => error.kind,
          'kind',
          AiRecognitionErrorKind.invalidResponse,
        ),
      ),
    );
  });

  test('times out an unfinished request', () async {
    final provider = _provider(
      MockClient((_) => Completer<http.Response>().future),
      timeout: const Duration(milliseconds: 5),
    );
    addTearDown(provider.close);

    await expectLater(
      provider.transcribe(_audio()),
      throwsA(
        isA<AiRecognitionException>().having(
          (error) => error.kind,
          'kind',
          AiRecognitionErrorKind.timeout,
        ),
      ),
    );
  });

  test('cancels an unfinished request with the per-call token', () async {
    final requested = Completer<void>();
    final provider = _provider(
      MockClient((_) {
        requested.complete();
        return Completer<http.Response>().future;
      }),
    );
    addTearDown(provider.close);
    final token = AiCancellationToken();

    final future = provider.transcribe(
      _audio(),
      options: AiRequestOptions(cancellationToken: token),
    );
    await requested.future;
    token.cancel();

    await expectLater(
      future,
      throwsA(
        isA<AiRecognitionException>().having(
          (error) => error.kind,
          'kind',
          AiRecognitionErrorKind.cancelled,
        ),
      ),
    );
  });

  test('close aborts work and prevents subsequent requests', () async {
    final requested = Completer<void>();
    final provider = _provider(
      MockClient((_) {
        requested.complete();
        return Completer<http.Response>().future;
      }),
    );

    final pending = provider.transcribe(_audio());
    await requested.future;
    provider.close();

    await expectLater(
      pending,
      throwsA(
        isA<AiRecognitionException>().having(
          (error) => error.kind,
          'kind',
          AiRecognitionErrorKind.closed,
        ),
      ),
    );
    await expectLater(
      provider.transcribe(_audio()),
      throwsA(
        isA<AiRecognitionException>().having(
          (error) => error.kind,
          'kind',
          AiRecognitionErrorKind.closed,
        ),
      ),
    );
  });

  test('requires runtime credentials when configured for authentication',
      () async {
    var requested = false;
    final profile = _profile(
      credentialTransport: const AiCredentialTransport.bearer(),
    );
    final provider = ProtocolAsrProvider(
      profile: profile,
      httpClient: MockClient((_) async {
        requested = true;
        return http.Response('{}', 200);
      }),
    );
    addTearDown(provider.close);

    await expectLater(
      provider.transcribe(_audio()),
      throwsA(
        isA<AiRecognitionException>().having(
          (error) => error.kind,
          'kind',
          AiRecognitionErrorKind.missingCredentials,
        ),
      ),
    );
    expect(requested, isFalse);
  });

  test('does not let a configured path redirect credentials to another origin',
      () async {
    var requested = false;
    final profile = AiProviderProfile(
      id: 'redirect-profile',
      name: 'Redirect test',
      kind: AiProviderKind.speechRecognition,
      protocol: AiProtocol.jsonHttp,
      baseUrl: Uri.parse('https://trusted.example/asr'),
      model: 'configured-model',
      requestOptions: const {
        'path': 'https://attacker.example/collect',
        'requestTemplate': {'audio': '{{audio.base64}}'},
      },
    );
    final provider = ProtocolAsrProvider(
      profile: profile,
      httpClient: MockClient((_) async {
        requested = true;
        return http.Response('{}', 200);
      }),
    );
    addTearDown(provider.close);

    await expectLater(
      provider.transcribe(
        _audio(),
        options: AiRequestOptions(
          credentials: AiCredentials(apiKey: 'must-stay-on-trusted-origin'),
        ),
      ),
      throwsA(
        isA<AiRecognitionException>().having(
          (error) => error.kind,
          'kind',
          AiRecognitionErrorKind.invalidConfiguration,
        ),
      ),
    );
    expect(requested, isFalse);
  });

  test('does not allow credentials embedded in a configured request path',
      () async {
    final provider = ProtocolAsrProvider(
      profile: AiProviderProfile(
        id: 'query-secret-profile',
        name: 'Query secret test',
        kind: AiProviderKind.speechRecognition,
        protocol: AiProtocol.jsonHttp,
        baseUrl: Uri.parse('https://trusted.example/asr'),
        model: 'configured-model',
        requestOptions: const {
          'path': '/v1/transcribe?api_key=leaked',
          'requestTemplate': {'audio': '{{audio.base64}}'},
        },
        credentialTransport: const AiCredentialTransport.bearer(),
      ),
      httpClient: MockClient(
        (_) async => http.Response(jsonEncode({'text': 'unused'}), 200),
      ),
    );
    addTearDown(provider.close);

    await expectLater(
      provider.transcribe(
        _audio(),
        options: AiRequestOptions(
          credentials: AiCredentials(apiKey: 'runtime-key'),
        ),
      ),
      throwsA(
        isA<AiRecognitionException>().having(
          (error) => error.kind,
          'kind',
          AiRecognitionErrorKind.invalidConfiguration,
        ),
      ),
    );
  });

  test('never forwards provider credentials through an HTTP redirect',
      () async {
    late bool followsRedirects;
    final provider = ProtocolAsrProvider(
      profile: _profile(
        credentialTransport: const AiCredentialTransport.bearer(),
      ),
      httpClient: MockClient((request) async {
        followsRedirects = request.followRedirects;
        expect(request.headers['authorization'], 'Bearer runtime-key');
        return http.Response(
          'redirecting',
          302,
          headers: const {'location': 'https://attacker.example/collect'},
        );
      }),
    );
    addTearDown(provider.close);

    await expectLater(
      provider.transcribe(
        _audio(),
        options: AiRequestOptions(
          credentials: AiCredentials(apiKey: 'runtime-key'),
        ),
      ),
      throwsA(
        isA<AiRecognitionException>()
            .having(
              (error) => error.kind,
              'kind',
              AiRecognitionErrorKind.httpStatus,
            )
            .having((error) => error.statusCode, 'statusCode', 302),
      ),
    );
    expect(followsRedirects, isFalse);
  });

  test('rejects a provider response before buffering unbounded bytes',
      () async {
    final provider = _provider(
      MockClient(
        (_) async => http.Response.bytes(
          List<int>.filled(AiHttpTransport.maxResponseBytes + 1, 0),
          200,
        ),
      ),
    );
    addTearDown(provider.close);

    await expectLater(
      provider.transcribe(_audio()),
      throwsA(
        isA<AiRecognitionException>().having(
          (error) => error.kind,
          'kind',
          AiRecognitionErrorKind.invalidResponse,
        ),
      ),
    );
  });

  test('cancels an oversized declared response stream', () async {
    final streamCancelled = Completer<void>();
    late StreamController<List<int>> responseController;
    final provider = _provider(
      _StreamingClient((request) async {
        responseController = StreamController<List<int>>(
          onCancel: streamCancelled.complete,
        );
        return http.StreamedResponse(
          responseController.stream,
          200,
          contentLength: AiHttpTransport.maxResponseBytes + 1,
          request: request,
        );
      }),
    );
    addTearDown(provider.close);
    addTearDown(() => responseController.close());

    await expectLater(
      provider.transcribe(_audio()),
      throwsA(
        isA<AiRecognitionException>().having(
          (error) => error.kind,
          'kind',
          AiRecognitionErrorKind.invalidResponse,
        ),
      ),
    );
    await streamCancelled.future.timeout(const Duration(seconds: 1));
  });
}

ProtocolAsrProvider _provider(
  http.Client client, {
  Duration timeout = const Duration(seconds: 1),
}) =>
    ProtocolAsrProvider(
      profile: _profile(),
      httpClient: client,
      timeout: timeout,
    );

AiProviderProfile _profile({
  AiCredentialTransport credentialTransport =
      const AiCredentialTransport.none(),
}) =>
    AiProviderProfile(
      id: 'failure-profile',
      name: 'Failure test',
      kind: AiProviderKind.speechRecognition,
      protocol: AiProtocol.jsonHttp,
      baseUrl: Uri.parse('https://example.test/asr'),
      model: 'configured-model',
      requestOptions: const {
        'requestTemplate': {
          'model': '{{model}}',
          'audio': '{{audio.base64}}',
        },
        'responsePath': 'text',
      },
      credentialTransport: credentialTransport,
    );

AudioSegment _audio() => AudioSegment(
      bytes: utf8.encode('audio'),
      mimeType: 'audio/wav',
      fileName: 'sample.wav',
    );

final class _StreamingClient extends http.BaseClient {
  _StreamingClient(this._handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
      _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _handler(request);
}
