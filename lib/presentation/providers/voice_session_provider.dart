import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../models/voice_state.dart';
import '../../services/audio_stream_service.dart';
import '../../services/realtime_service.dart';
import '../../services/audio_player_service.dart';
import 'package:flutter/foundation.dart';

final voiceSessionProvider =
    NotifierProvider<VoiceSessionNotifier, VoiceSessionStateModel>(() {
      return VoiceSessionNotifier();
    });

class VoiceSessionNotifier extends Notifier<VoiceSessionStateModel> {
  bool _mounted = true;

  @override
  VoiceSessionStateModel build() {
    _mounted = true;
    return VoiceSessionStateModel();
  }

  final _audioService = AudioStreamService();
  final _realtimeService = RealtimeService();
  final _playerService = AudioPlayerService();
  final _uuid = const Uuid();

  bool _continuousMode = true; // Auto-restart listening after response

  // Safe state update
  void _updateState(
    VoiceSessionStateModel Function(VoiceSessionStateModel) update,
  ) {
    if (_mounted) {
      try {
        state = update(state);
      } catch (e) {
        debugPrint('⚠️ State update error: $e');
      }
    }
  }

  StreamSubscription? _audioSubscription;
  StreamSubscription? _audioLevelSubscription;
  StreamSubscription? _transcriptSubscription;
  StreamSubscription? _responseSubscription;
  StreamSubscription? _audioResponseSubscription;
  StreamSubscription? _stateSubscription;
  StreamSubscription? _playbackSubscription;

  Future<bool> initialize() async {
    try {
      debugPrint('🚀 Initializing voice session...');

      // Auto-restart listening when playback finishes (continuous mode)
      _playerService.onPlaybackComplete = () {
        if (_mounted && _continuousMode) {
          debugPrint('🔄 Playback done, auto-restarting listening...');
          // Auto-restart listening for continuous conversation
          _autoRestartListening();
        }
      };

      final connected = await _realtimeService.connect();
      debugPrint('🔌 Connection result: $connected');

      if (!connected) {
        _updateState(
          (s) => s.copyWith(
            state: VoiceSessionState.error,
            error: 'Failed to connect. Check internet connection.',
          ),
        );
        return false;
      }

      // Transcript received
      _transcriptSubscription = _realtimeService.transcriptStream.listen((
        transcript,
      ) {
        debugPrint('📝 Got transcript: $transcript');
        final message = VoiceMessage(
          id: _uuid.v4(),
          role: 'user',
          content: transcript,
          timestamp: DateTime.now(),
        );
        _updateState(
          (s) => s.copyWith(
            messages: [...s.messages, message],
            clearPartialTranscript: true,
          ),
        );
      });

      // Response text stream
      _responseSubscription = _realtimeService.responseStream.listen((
        response,
      ) {
        debugPrint('💬 Got response text: $response');
        _updateState((s) => s.copyWith(partialResponse: response));
      });

      // Audio chunks - just queue them
      _audioResponseSubscription = _realtimeService.audioResponseStream.listen((
        chunk,
      ) {
        debugPrint('🎵 Got audio chunk: ${chunk.length} bytes');
        _playerService.queueAudioChunk(chunk);
      });

      // API state changes
      _stateSubscription = _realtimeService.stateStream.listen((apiState) {
        debugPrint('📡 API state changed: $apiState');
        switch (apiState) {
          case 'speech_started':
            _updateState((s) => s.copyWith(state: VoiceSessionState.listening));
            break;
          case 'speech_stopped':
            // Stop recording while bot is processing/speaking to prevent feedback
            _pauseListening();
            _updateState((s) => s.copyWith(state: VoiceSessionState.thinking));
            break;
          case 'response_started':
            _updateState((s) => s.copyWith(state: VoiceSessionState.speaking));
            break;
          case 'response_complete':
            // Play all collected audio
            _playerService.flush();

            if (state.partialResponse != null &&
                state.partialResponse!.isNotEmpty) {
              final message = VoiceMessage(
                id: _uuid.v4(),
                role: 'assistant',
                content: state.partialResponse!,
                timestamp: DateTime.now(),
              );
              _updateState(
                (s) => s.copyWith(
                  messages: [...s.messages, message],
                  clearPartialResponse: true,
                ),
              );
            }
            break;
          case 'error':
            _updateState(
              (s) => s.copyWith(
                state: VoiceSessionState.error,
                error: 'API error occurred.',
              ),
            );
            break;
        }
      });

      // When playback finishes - DON'T go to idle if continuous mode
      // The auto-restart will handle the state transition
      _playbackSubscription = _playerService.playbackStream.listen((isPlaying) {
        if (!isPlaying && state.state == VoiceSessionState.speaking) {
          if (!_continuousMode) {
            _updateState((s) => s.copyWith(state: VoiceSessionState.idle));
          }
          // In continuous mode, stay in speaking state until auto-restart sets listening
        }
      });

      // Audio level for visualizer
      _audioLevelSubscription = _audioService.audioLevelStream.listen((level) {
        _updateState((s) => s.copyWith(audioLevel: level));
      });

      return true;
    } catch (e) {
      debugPrint('❌ Init error: $e');
      _updateState(
        (s) => s.copyWith(
          state: VoiceSessionState.error,
          error: 'Failed to initialize: $e',
        ),
      );
      return false;
    }
  }

  /// TAP TO START - enables continuous listening mode
  Future<void> startListening() async {
    // Don't start if already active
    if (state.state == VoiceSessionState.listening ||
        state.state == VoiceSessionState.speaking ||
        state.state == VoiceSessionState.thinking) {
      return;
    }

    // Enable continuous mode
    _continuousMode = true;

    // Stop any current playback first
    await _playerService.stop();

    final started = await _audioService.startRecording();
    if (!started) {
      _updateState(
        (s) => s.copyWith(
          state: VoiceSessionState.error,
          error: 'Microphone permission denied.',
        ),
      );
      return;
    }

    // Stream audio to API
    _audioSubscription = _audioService.audioStream.listen((chunk) {
      if (_continuousMode) {
        _realtimeService.sendAudio(chunk);
      }
    });

    _updateState((s) => s.copyWith(state: VoiceSessionState.listening));
    debugPrint('🎤 Started continuous listening mode');
  }

  /// TAP TO STOP SPEAKING (sends audio for processing)
  Future<void> stopListening() async {
    if (state.state != VoiceSessionState.listening) return;

    await _audioSubscription?.cancel();
    await _audioService.stopRecording();
    _realtimeService.commitAudio();

    _updateState((s) => s.copyWith(state: VoiceSessionState.thinking));
    debugPrint('⏹️ Stopped listening, processing...');
  }

  /// Pause listening (stop mic) but keep continuous mode enabled
  void _pauseListening() {
    _audioSubscription?.cancel();
    _audioService.stopRecording();
    debugPrint('⏸️ Paused listening (bot is speaking)');
  }

  /// TAP TO INTERRUPT (stops playback, goes to idle)
  void interrupt() {
    debugPrint('🛑 Stopping voice session...');

    // Stop continuous mode
    _continuousMode = false;

    // Stop recording if active
    _audioSubscription?.cancel();
    _audioService.stopRecording();

    // Stop audio playback
    _playerService.stop();

    // Go to idle
    _updateState(
      (s) =>
          s.copyWith(state: VoiceSessionState.idle, clearPartialResponse: true),
    );
  }

  /// Auto-restart listening after bot finishes speaking
  Future<void> _autoRestartListening() async {
    if (!_continuousMode || !_mounted) return;

    // Small delay before restarting
    await Future.delayed(const Duration(milliseconds: 300));

    if (!_continuousMode || !_mounted) return;

    final started = await _audioService.startRecording();
    if (!started) {
      _updateState((s) => s.copyWith(state: VoiceSessionState.idle));
      return;
    }

    // Stream audio to API
    _audioSubscription = _audioService.audioStream.listen((chunk) {
      if (_continuousMode) {
        _realtimeService.sendAudio(chunk);
      }
    });

    _updateState((s) => s.copyWith(state: VoiceSessionState.listening));
    debugPrint('🎤 Auto-restarted listening');
  }

  /// Stop continuous mode (when leaving screen)
  void stopAll() {
    _continuousMode = false;
    _playerService.stop();
    _audioSubscription?.cancel();
    _audioService.stopRecording();
  }

  void clearMessages() {
    _updateState((s) => s.copyWith(messages: []));
  }

  void disposeResources() {
    _mounted = false;

    _audioSubscription?.cancel();
    _audioLevelSubscription?.cancel();
    _transcriptSubscription?.cancel();
    _responseSubscription?.cancel();
    _audioResponseSubscription?.cancel();
    _stateSubscription?.cancel();
    _playbackSubscription?.cancel();

    _audioService.dispose();
    _realtimeService.dispose();
    _playerService.dispose();
  }
}
