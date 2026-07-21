import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/services/ai_recognition/ai_recognition.dart';
import 'package:openlogtool/services/ai_recognition_runtime.dart';

void main() {
  test('passes one final transcript through the optional extraction stage',
      () async {
    final asr = _FakeAsr();
    final extractor = _FakeExtractor();
    final credentialRequests = <String>[];
    final pipeline = AiRecognitionPipeline(
      asr: asr,
      fieldExtraction: extractor,
      credentialResolver: (request) {
        credentialRequests.add(request.providerId);
        return AiCredentials(apiKey: 'test-key');
      },
    );
    addTearDown(pipeline.close);

    final result = await pipeline.recognize(
      _audio(),
      languageHint: 'zh',
      transcriptionPrompt: 'expected callsigns',
      extractionInstructions: 'return log fields',
    );

    expect(result.transcription.text, 'BG5CRL 信号五九');
    expect(result.candidates.single.fields['callsign'], 'BG5CRL');
    expect(asr.languageHint, 'zh');
    expect(asr.prompt, 'expected callsigns');
    expect(extractor.instructions, 'return log fields');
    // Fakes resolve credentials exactly as real providers do, proving the
    // same resolver can isolate keys by provider ID across both stages.
    expect(credentialRequests, ['asr', 'extractor']);
  });

  test('returns a transcript without inventing candidates when no extractor',
      () async {
    final pipeline = AiRecognitionPipeline(asr: _FakeAsr());
    addTearDown(pipeline.close);

    final result = await pipeline.recognize(_audio());

    expect(result.transcription.text, isNotEmpty);
    expect(result.candidates, isEmpty);
  });

  test('skips field extraction when the transcript gate rejects filler',
      () async {
    final extractor = _FakeExtractor();
    final pipeline = AiRecognitionPipeline(
      asr: _FakeAsr(transcript: '嗯。'),
      fieldExtraction: extractor,
    );
    addTearDown(pipeline.close);

    final result = await pipeline.recognize(
      _audio(),
      shouldExtract: (transcription) =>
          AiRecognitionRuntime.isActionableTranscription(transcription.text),
    );

    expect(result.transcription.text, '嗯。');
    expect(result.candidates, isEmpty);
    expect(extractor.callCount, 0);
  });

  test('does not enter extraction after cancellation', () async {
    final token = AiCancellationToken();
    final extractor = _FakeExtractor();
    final asr = _FakeAsr(onTranscribed: token.cancel);
    final pipeline = AiRecognitionPipeline(
      asr: asr,
      fieldExtraction: extractor,
    );
    addTearDown(pipeline.close);

    await expectLater(
      pipeline.recognize(_audio(), cancellationToken: token),
      throwsA(
        isA<AiRecognitionException>().having(
          (error) => error.kind,
          'kind',
          AiRecognitionErrorKind.cancelled,
        ),
      ),
    );
    expect(extractor.callCount, 0);
  });

  test('close is idempotent and rejects new work', () async {
    final asr = _FakeAsr();
    final extractor = _FakeExtractor();
    final pipeline = AiRecognitionPipeline(
      asr: asr,
      fieldExtraction: extractor,
    );

    pipeline.close();
    pipeline.close();

    expect(asr.closeCount, 1);
    expect(extractor.closeCount, 1);
    await expectLater(
      pipeline.recognize(_audio()),
      throwsA(
        isA<AiRecognitionException>().having(
          (error) => error.kind,
          'kind',
          AiRecognitionErrorKind.closed,
        ),
      ),
    );
  });

  test('does not return candidates when cancellation wins during extraction',
      () async {
    final token = AiCancellationToken();
    final extractionStarted = Completer<void>();
    final releaseExtraction = Completer<void>();
    final pipeline = AiRecognitionPipeline(
      asr: _FakeAsr(),
      fieldExtraction: _FakeExtractor(
        onExtract: () async {
          extractionStarted.complete();
          await releaseExtraction.future;
        },
      ),
    );
    addTearDown(pipeline.close);

    final result = pipeline.recognize(
      _audio(),
      cancellationToken: token,
    );
    await extractionStarted.future;
    token.cancel();
    releaseExtraction.complete();

    await expectLater(
      result,
      throwsA(
        isA<AiRecognitionException>().having(
          (error) => error.kind,
          'kind',
          AiRecognitionErrorKind.cancelled,
        ),
      ),
    );
  });
}

final class _FakeAsr implements AsrProvider {
  _FakeAsr({this.onTranscribed, this.transcript = 'BG5CRL 信号五九'});

  final void Function()? onTranscribed;
  final String transcript;
  String? languageHint;
  String? prompt;
  int closeCount = 0;

  @override
  AiProviderCapabilities get capabilities => profile.capabilities;

  @override
  final AiProviderProfile profile = AiProviderProfile(
    id: 'asr',
    name: 'ASR',
    kind: AiProviderKind.speechRecognition,
    protocol: AiProtocol.jsonHttp,
    baseUrl: Uri.parse('https://asr.example'),
    model: 'asr-model',
    credentialId: 'asr-key',
    requestOptions: const {
      'requestTemplate': {'audio': '{{audio.base64}}'},
    },
  );

  @override
  void close() => closeCount += 1;

  @override
  Future<Transcription> transcribe(
    AudioSegment audio, {
    String? languageHint,
    String? prompt,
    AiRequestOptions options = const AiRequestOptions(),
  }) async {
    this.languageHint = languageHint;
    this.prompt = prompt;
    await options.credentialResolver?.call(
      AiCredentialRequest(
        providerId: profile.id,
        credentialId: profile.credentialId,
      ),
    );
    onTranscribed?.call();
    return Transcription(text: transcript, language: 'zh');
  }
}

final class _FakeExtractor implements FieldExtractionProvider {
  _FakeExtractor({this.onExtract});

  final Future<void> Function()? onExtract;
  String? instructions;
  int callCount = 0;
  int closeCount = 0;

  @override
  AiProviderCapabilities get capabilities => profile.capabilities;

  @override
  final AiProviderProfile profile = AiProviderProfile(
    id: 'extractor',
    name: 'Extractor',
    kind: AiProviderKind.fieldExtraction,
    protocol: AiProtocol.openAiChatCompletions,
    baseUrl: Uri.parse('https://extractor.example/v1'),
    model: 'extractor-model',
    credentialId: 'extractor-key',
  );

  @override
  void close() => closeCount += 1;

  @override
  Future<List<RecognitionCandidate>> extract(
    Transcription transcription, {
    String? instructions,
    AiRequestOptions options = const AiRequestOptions(),
  }) async {
    callCount += 1;
    this.instructions = instructions;
    await onExtract?.call();
    await options.credentialResolver?.call(
      AiCredentialRequest(
        providerId: profile.id,
        credentialId: profile.credentialId,
      ),
    );
    return [
      RecognitionCandidate(
        fields: const {'callsign': 'BG5CRL', 'rstRcvd': '59'},
        sourceText: transcription.text,
      ),
    ];
  }
}

AudioSegment _audio() => AudioSegment(
      bytes: const [1, 2, 3],
      mimeType: 'audio/wav',
      fileName: 'turn.wav',
    );
