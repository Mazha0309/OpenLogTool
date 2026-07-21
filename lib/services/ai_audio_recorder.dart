import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:openlogtool/services/ai_recognition/models.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// A small boundary around the platform recorder so the workbench can be
/// tested without opening a real microphone.
abstract interface class AiAudioRecorder {
  bool get supportsLiveChunks;

  Future<bool> requestPermission();

  Future<void> start();

  Future<AudioSegment?> takeLiveChunk();

  Future<AudioSegment?> stop();

  Future<void> cancel();

  Future<void> dispose();
}

enum _RecordingMode { pcmStream, wavFile, aacFile }

/// Prefers an in-memory PCM stream, then falls back to WAV or AAC file capture
/// when a platform plugin does not expose streaming for that encoder.
final class DeviceAiAudioRecorder implements AiAudioRecorder {
  DeviceAiAudioRecorder({AudioRecorder? recorder})
      : _recorder = recorder ?? AudioRecorder();

  static const int sampleRateHz = 16000;
  static const int channelCount = 1;
  static const int bitsPerSample = 16;

  final AudioRecorder _recorder;
  StreamSubscription<Uint8List>? _subscription;
  BytesBuilder? _pcmBytes;
  Completer<void>? _streamFinished;
  Object? _streamError;
  DateTime? _startedAt;
  DateTime? _liveChunkStartedAt;
  _RecordingMode? _mode;
  String? _filePath;
  bool _disposed = false;

  @override
  bool get supportsLiveChunks => _mode == _RecordingMode.pcmStream;

  @override
  Future<bool> requestPermission() {
    _ensureUsable();
    return _recorder.hasPermission();
  }

  @override
  Future<void> start() async {
    _ensureUsable();
    if (_mode != null) {
      throw StateError('AI_AUDIO_ALREADY_RECORDING');
    }
    // Some platform implementations (notably record_linux) expose a raw PCM
    // stream even though isEncoderSupported(pcm16bits) reports false because
    // that method describes file encoders. Try the stream directly first.
    try {
      await _startPcmStream();
      return;
    } catch (_) {
      try {
        await _recorder.cancel();
      } catch (_) {}
      _clearSession();
    }
    if (await _recorder.isEncoderSupported(AudioEncoder.wav)) {
      await _startFile(AudioEncoder.wav, _RecordingMode.wavFile, 'wav');
      return;
    }
    if (await _recorder.isEncoderSupported(AudioEncoder.aacLc)) {
      await _startFile(AudioEncoder.aacLc, _RecordingMode.aacFile, 'm4a');
      return;
    }
    throw StateError('AI_AUDIO_ENCODER_UNSUPPORTED');
  }

  Future<void> _startPcmStream() async {
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRateHz,
        numChannels: channelCount,
        autoGain: true,
        noiseSuppress: true,
      ),
    );
    _pcmBytes = BytesBuilder(copy: false);
    _streamFinished = Completer<void>();
    _streamError = null;
    _startedAt = DateTime.now();
    _liveChunkStartedAt = _startedAt;
    _mode = _RecordingMode.pcmStream;
    _subscription = stream.listen(
      _pcmBytes!.add,
      onError: (Object error, StackTrace stackTrace) {
        _streamError = error;
        if (!(_streamFinished?.isCompleted ?? true)) {
          _streamFinished!.complete();
        }
      },
      onDone: () {
        if (!(_streamFinished?.isCompleted ?? true)) {
          _streamFinished!.complete();
        }
      },
      cancelOnError: false,
    );
  }

  @override
  Future<AudioSegment?> takeLiveChunk() async {
    _ensureUsable();
    if (_mode != _RecordingMode.pcmStream) return null;
    final buffer = _pcmBytes;
    if (buffer == null) throw StateError('AI_AUDIO_STREAM_STATE_INVALID');
    const minimumChunkBytes = sampleRateHz * channelCount * 2;
    if (buffer.length < minimumChunkBytes) return null;
    final startedAt = _liveChunkStartedAt;
    final pcm = buffer.takeBytes();
    _liveChunkStartedAt = DateTime.now();
    return _pcmSegment(pcm, startedAt: startedAt);
  }

  Future<void> _startFile(
    AudioEncoder encoder,
    _RecordingMode mode,
    String extension,
  ) async {
    final directory = await getTemporaryDirectory();
    final path = p.join(
      directory.path,
      'openlogtool-ai-${DateTime.now().microsecondsSinceEpoch}.$extension',
    );
    await _recorder.start(
      RecordConfig(
        encoder: encoder,
        sampleRate: sampleRateHz,
        numChannels: channelCount,
        autoGain: true,
        noiseSuppress: true,
      ),
      path: path,
    );
    _filePath = path;
    _startedAt = DateTime.now();
    _mode = mode;
  }

  @override
  Future<AudioSegment?> stop() async {
    _ensureUsable();
    final mode = _mode;
    final startedAt = _startedAt;
    if (mode == null) {
      throw StateError('AI_AUDIO_NOT_RECORDING');
    }

    if (mode != _RecordingMode.pcmStream) {
      return _stopFile(mode, startedAt);
    }

    final subscription = _subscription;
    final buffer = _pcmBytes;
    final finished = _streamFinished;
    if (subscription == null || buffer == null || finished == null) {
      throw StateError('AI_AUDIO_STREAM_STATE_INVALID');
    }

    try {
      await _recorder.stop();
      await finished.future;
      final error = _streamError;
      if (error != null) throw error;
      final pcm = buffer.takeBytes();
      if (pcm.isEmpty) return null;
      return _pcmSegment(
        pcm,
        startedAt: _liveChunkStartedAt ?? startedAt,
      );
    } finally {
      await subscription.cancel();
      _clearSession();
    }
  }

  AudioSegment _pcmSegment(Uint8List pcm, {required DateTime? startedAt}) {
    final wav = Pcm16WavEncoder.encode(
      pcm,
      sampleRateHz: sampleRateHz,
      channelCount: channelCount,
    );
    return AudioSegment(
      bytes: wav,
      mimeType: 'audio/wav',
      fileName: 'openlogtool-${DateTime.now().millisecondsSinceEpoch}.wav',
      duration: startedAt == null ? null : DateTime.now().difference(startedAt),
      sampleRateHz: sampleRateHz,
      channelCount: channelCount,
    );
  }

  Future<AudioSegment> _stopFile(
    _RecordingMode mode,
    DateTime? startedAt,
  ) async {
    final configuredPath = _filePath;
    String? outputPath;
    try {
      outputPath = await _recorder.stop() ?? configuredPath;
      if (outputPath == null) throw StateError('AI_AUDIO_FILE_MISSING');
      final bytes = await File(outputPath).readAsBytes();
      if (bytes.isEmpty) throw StateError('AI_AUDIO_EMPTY');
      final wav = mode == _RecordingMode.wavFile;
      return AudioSegment(
        bytes: bytes,
        mimeType: wav ? 'audio/wav' : 'audio/mp4',
        fileName: p.basename(outputPath),
        duration:
            startedAt == null ? null : DateTime.now().difference(startedAt),
        sampleRateHz: sampleRateHz,
        channelCount: channelCount,
      );
    } finally {
      await _deleteTemporaryFile(outputPath ?? configuredPath);
      _clearSession();
    }
  }

  @override
  Future<void> cancel() async {
    if (_disposed) return;
    final mode = _mode;
    if (mode == null) return;
    final subscription = _subscription;
    final filePath = _filePath;
    try {
      await _recorder.cancel();
    } finally {
      await subscription?.cancel();
      await _deleteTemporaryFile(filePath);
      _clearSession();
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await cancel();
    _disposed = true;
    await _recorder.dispose();
  }

  void _clearSession() {
    _subscription = null;
    _pcmBytes = null;
    _streamFinished = null;
    _streamError = null;
    _startedAt = null;
    _liveChunkStartedAt = null;
    _mode = null;
    _filePath = null;
  }

  Future<void> _deleteTemporaryFile(String? path) async {
    if (path == null) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // A best-effort cleanup must not mask the recording result or failure.
    }
  }

  void _ensureUsable() {
    if (_disposed) throw StateError('AI_AUDIO_RECORDER_DISPOSED');
  }
}

/// Encodes raw little-endian signed PCM16 samples into a standard WAV file.
/// Kept independent from the plugin so the generated upload can be verified.
abstract final class Pcm16WavEncoder {
  static Uint8List encode(
    Uint8List pcm, {
    required int sampleRateHz,
    required int channelCount,
  }) {
    if (pcm.isEmpty || pcm.length.isOdd) {
      throw ArgumentError.value(pcm.length, 'pcm', 'must contain PCM16 frames');
    }
    if (sampleRateHz <= 0 || channelCount <= 0) {
      throw ArgumentError('sample rate and channel count must be positive');
    }
    const headerLength = 44;
    const bitsPerSample = 16;
    const bytesPerSample = bitsPerSample ~/ 8;
    final byteRate = sampleRateHz * channelCount * bytesPerSample;
    final blockAlign = channelCount * bytesPerSample;
    final wav = Uint8List(headerLength + pcm.length);
    final header = ByteData.sublistView(wav);

    void ascii(int offset, String value) {
      for (var index = 0; index < value.length; index += 1) {
        wav[offset + index] = value.codeUnitAt(index);
      }
    }

    ascii(0, 'RIFF');
    header.setUint32(4, 36 + pcm.length, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, channelCount, Endian.little);
    header.setUint32(24, sampleRateHz, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    ascii(36, 'data');
    header.setUint32(40, pcm.length, Endian.little);
    wav.setRange(headerLength, wav.length, pcm);
    return wav;
  }
}
