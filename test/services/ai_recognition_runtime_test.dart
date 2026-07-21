import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/services/ai_recognition_runtime.dart';

void main() {
  test('rejects filler-only transcripts before field extraction', () {
    expect(AiRecognitionRuntime.isActionableTranscription('嗯。'), isFalse);
    expect(AiRecognitionRuntime.isActionableTranscription('嗯嗯……'), isFalse);
    expect(AiRecognitionRuntime.isActionableTranscription(' uh! '), isFalse);
    expect(AiRecognitionRuntime.isActionableTranscription('BG5CDL'), isTrue);
  });

  test('extracts only explicitly stated wattage as a power fallback', () {
    expect(
      AiRecognitionRuntime.extractExplicitPower('五个瓦特功率发射'),
      '5 W',
    );
    expect(AiRecognitionRuntime.extractExplicitPower('功率二十五瓦'), '25 W');
    expect(AiRecognitionRuntime.extractExplicitPower('power 10 watts'), '10 W');
    expect(AiRecognitionRuntime.extractExplicitPower('没有提到功率'), isNull);
  });
}
