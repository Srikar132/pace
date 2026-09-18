import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

class AudioPlayerService {
  final _player = AudioPlayer();
  final _playbackController = StreamController<bool>.broadcast();

  final List<int> _audioBuffer = [];
  bool _isPlaying = false;
  File? _currentAudioFile;
  int _fileCounter = 0;

  // Callback when playback finishes
  void Function()? onPlaybackComplete;

  Stream<bool> get playbackStream => _playbackController.stream;
  bool get isPlaying => _isPlaying;

  AudioPlayerService() {
    _player.setPlayerMode(PlayerMode.mediaPlayer);
    _player.setVolume(1.0);

    _player.onPlayerComplete.listen((_) {
      debugPrint('🔊 Playback complete');
      _isPlaying = false;
      _cleanupFile();
      if (!_playbackController.isClosed) {
        _playbackController.add(false);
      }
      // Notify that playback is done
      onPlaybackComplete?.call();
    });
  }

  /// Queue audio chunk - just accumulate, don't play yet
  void queueAudioChunk(Uint8List chunk) {
    _audioBuffer.addAll(chunk);
  }

  /// Called when response is complete - play ALL accumulated audio
  Future<void> flush() async {
    // Wait for remaining audio chunks to arrive (they often come after response_complete)
    await Future.delayed(const Duration(milliseconds: 500));

    if (_audioBuffer.isEmpty) {
      debugPrint('⚠️ No audio to play');
      onPlaybackComplete?.call();
      return;
    }

    // Don't play if buffer is too small (likely incomplete)
    if (_audioBuffer.length < 5000) {
      debugPrint(
        '⚠️ Audio buffer too small: ${_audioBuffer.length} bytes, skipping',
      );
      _audioBuffer.clear();
      onPlaybackComplete?.call();
      return;
    }

    if (_isPlaying) {
      await stop();
    }

    _isPlaying = true;
    if (!_playbackController.isClosed) {
      _playbackController.add(true);
    }

    try {
      final pcmData = Uint8List.fromList(_audioBuffer);
      _audioBuffer.clear();

      debugPrint('🔊 Playing ${pcmData.length} bytes of audio');

      // Amplify audio for better volume
      final amplified = _amplifyAudio(pcmData, 2.0);

      // Create WAV file
      final wavData = _createWavFile(amplified);

      final tempDir = await getTemporaryDirectory();
      _currentAudioFile = File(
        '${tempDir.path}/lumo_audio_${_fileCounter++}.wav',
      );
      await _currentAudioFile!.writeAsBytes(wavData, flush: true);

      await _player.play(DeviceFileSource(_currentAudioFile!.path));
    } catch (e) {
      debugPrint('❌ Play error: $e');
      _isPlaying = false;
      if (!_playbackController.isClosed) {
        _playbackController.add(false);
      }
      onPlaybackComplete?.call();
    }
  }

  Uint8List _amplifyAudio(Uint8List pcmData, double gain) {
    final result = Uint8List(pcmData.length);
    final buffer = ByteData.view(result.buffer);
    final src = ByteData.view(pcmData.buffer);

    for (int i = 0; i < pcmData.length - 1; i += 2) {
      int sample = src.getInt16(i, Endian.little);
      double amplified = (sample * gain).clamp(-32768, 32767);
      buffer.setInt16(i, amplified.toInt(), Endian.little);
    }
    return result;
  }

  Uint8List _createWavFile(Uint8List pcmData) {
    const sampleRate = 24000;
    const numChannels = 1;
    const bitsPerSample = 16;
    final byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
    final blockAlign = numChannels * bitsPerSample ~/ 8;
    final dataSize = pcmData.length;
    final fileSize = 36 + dataSize;

    final header = ByteData(44);
    // RIFF
    header.setUint8(0, 0x52);
    header.setUint8(1, 0x49);
    header.setUint8(2, 0x46);
    header.setUint8(3, 0x46);
    header.setUint32(4, fileSize, Endian.little);
    header.setUint8(8, 0x57);
    header.setUint8(9, 0x41);
    header.setUint8(10, 0x56);
    header.setUint8(11, 0x45);
    // fmt
    header.setUint8(12, 0x66);
    header.setUint8(13, 0x6d);
    header.setUint8(14, 0x74);
    header.setUint8(15, 0x20);
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, numChannels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    // data
    header.setUint8(36, 0x64);
    header.setUint8(37, 0x61);
    header.setUint8(38, 0x74);
    header.setUint8(39, 0x61);
    header.setUint32(40, dataSize, Endian.little);

    final wav = Uint8List(44 + dataSize);
    wav.setRange(0, 44, header.buffer.asUint8List());
    wav.setRange(44, 44 + dataSize, pcmData);
    return wav;
  }

  void _cleanupFile() async {
    try {
      if (_currentAudioFile != null && await _currentAudioFile!.exists()) {
        await _currentAudioFile!.delete();
      }
    } catch (_) {}
  }

  Future<void> stop() async {
    await _player.stop();
    _audioBuffer.clear();
    _isPlaying = false;
    if (!_playbackController.isClosed) {
      _playbackController.add(false);
    }
    _cleanupFile();
  }

  Future<void> dispose() async {
    await stop();
    await _player.dispose();
    await _playbackController.close();
  }
}
