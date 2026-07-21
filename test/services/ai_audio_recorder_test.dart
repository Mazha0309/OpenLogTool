import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/services/ai_audio_recorder.dart';

void main() {
  test('wraps little-endian PCM16 in a valid mono 16 kHz WAV header', () {
    final wav = Pcm16WavEncoder.encode(
      Uint8List.fromList(const [0, 0, 255, 127]),
      sampleRateHz: 16000,
      channelCount: 1,
    );
    final header = ByteData.sublistView(wav);

    expect(ascii.decode(wav.sublist(0, 4)), 'RIFF');
    expect(header.getUint32(4, Endian.little), 40);
    expect(ascii.decode(wav.sublist(8, 12)), 'WAVE');
    expect(header.getUint16(20, Endian.little), 1);
    expect(header.getUint16(22, Endian.little), 1);
    expect(header.getUint32(24, Endian.little), 16000);
    expect(header.getUint16(34, Endian.little), 16);
    expect(ascii.decode(wav.sublist(36, 40)), 'data');
    expect(header.getUint32(40, Endian.little), 4);
    expect(wav.sublist(44), const [0, 0, 255, 127]);
  });

  test('rejects partial PCM16 samples', () {
    expect(
      () => Pcm16WavEncoder.encode(
        Uint8List.fromList(const [1]),
        sampleRateHz: 16000,
        channelCount: 1,
      ),
      throwsArgumentError,
    );
  });
}
