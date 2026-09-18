import 'dart:async';
import 'package:record/record.dart';
import '../config/voice_api_config.dart';
import 'package:flutter/foundation.dart';

class AudioStreamService {
  final _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _audioSubscription;
  final _audioStreamController = StreamController<Uint8List>.broadcast();
  final _audioLevelController = StreamController<double>.broadcast();

  bool _isRecording = false;

  Stream<Uint8List> get audioStream => _audioStreamController.stream;
  Stream<double> get audioLevelStream => _audioLevelController.stream;
  bool get isRecording => _isRecording;

  Future<bool> startRecording() async {
    if (_isRecording) return true;

    try {
      // Check permissions
      if (!await _recorder.hasPermission()) {
        debugPrint('❌ Microphone permission denied');
        return false;
      }

      // Configure recording
      const config = RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: VoiceApiConfig.sampleRate,
        numChannels: VoiceApiConfig.channels,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
      );

      // Start streaming
      final stream = await _recorder.startStream(config);

      _audioSubscription = stream.listen(
        (chunk) {
          if (_isRecording) {
            _audioStreamController.add(chunk);
            _calculateAudioLevel(chunk);
          }
        },
        onError: (error) {
          debugPrint('❌ Audio stream error: $error');
        },
      );

      _isRecording = true;
      debugPrint('🎤 Recording started');
      return true;
    } catch (e) {
      debugPrint('❌ Failed to start recording: $e');
      return false;
    }
  }

  Future<void> stopRecording() async {
    if (!_isRecording) return;

    await _audioSubscription?.cancel();
    await _recorder.stop();
    _isRecording = false;
    _audioLevelController.add(0.0);
    debugPrint('🛑 Recording stopped');
  }

  void _calculateAudioLevel(Uint8List chunk) {
    if (chunk.isEmpty) return;

    // Convert bytes to PCM samples (16-bit)
    double sum = 0;
    for (int i = 0; i < chunk.length - 1; i += 2) {
      int sample = (chunk[i + 1] << 8) | chunk[i];
      if (sample > 32767) sample -= 65536;
      sum += (sample / 32768.0).abs();
    }

    double average = sum / (chunk.length / 2);
    _audioLevelController.add(average);
  }

  Future<void> dispose() async {
    await stopRecording();
    await _audioStreamController.close();
    await _audioLevelController.close();
    await _recorder.dispose();
  }
}
