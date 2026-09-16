import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import '../config/voice_api_config.dart';

class RealtimeService {
  WebSocketChannel? _channel;
  final _transcriptController = StreamController<String>.broadcast();
  final _responseController = StreamController<String>.broadcast();
  final _audioResponseController = StreamController<Uint8List>.broadcast();
  final _stateController = StreamController<String>.broadcast();

  bool _isConnected = false;
  bool _reconnecting = false;
  String _accumulatedResponse = '';

  Stream<String> get transcriptStream => _transcriptController.stream;
  Stream<String> get responseStream => _responseController.stream;
  Stream<Uint8List> get audioResponseStream => _audioResponseController.stream;
  Stream<String> get stateStream => _stateController.stream;
  bool get isConnected => _isConnected;

  Future<bool> connect() async {
    if (_isConnected) return true;

    try {
      print('🔄 Connecting to Realtime API...');

      // Build WebSocket URI with authentication and model
      final uri = Uri.parse(
        '${VoiceApiConfig.realtimeWsUrl}?model=${VoiceApiConfig.model}',
      );

      // Connect to WebSocket with Authorization header using IOWebSocketChannel
      final socket =
          await WebSocket.connect(
            uri.toString(),
            headers: {
              'Authorization': 'Bearer ${VoiceApiConfig.apiKey}',
              'OpenAI-Beta': 'realtime=v1',
            },
          ).timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw TimeoutException(
                'Connection timeout - please check your internet',
              );
            },
          );

      _channel = IOWebSocketChannel(socket);

      // Wait a moment for connection to establish
      await Future.delayed(const Duration(milliseconds: 500));

      // Send session configuration
      _channel!.sink.add(
        jsonEncode({
          'type': 'session.update',
          'session': {
            'modalities': ['text', 'audio'],
            'instructions':
                'You are Lumo, a helpful AI voice assistant integrated into a focus and study app called PACE. Be concise, encouraging, and supportive. Help users with their study goals and productivity. Keep responses brief and clear.',
            'voice': VoiceApiConfig.ttsVoice,
            'input_audio_format': 'pcm16',
            'output_audio_format': 'pcm16',
            'input_audio_transcription': {'model': 'whisper-1'},
            'turn_detection': {
              'type': 'server_vad',
              'threshold': 0.5,
              'prefix_padding_ms': 300,
              'silence_duration_ms': 600,
              'create_response': true,
            },
          },
        }),
      );

      // Listen to WebSocket messages
      _channel!.stream.listen(
        _handleMessage,
        onError: (error) {
          print('❌ WebSocket error: $error');
          _isConnected = false;
        },
        onDone: () {
          print('🔌 WebSocket disconnected');
          _isConnected = false;
        },
      );

      _isConnected = true;
      _stateController.add('connected');
      print('✅ Realtime API connected');
      return true;
    } catch (e) {
      print('❌ Failed to connect: $e');
      return false;
    }
  }

  void _handleMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String);
      final type = data['type'] as String;

      switch (type) {
        case 'session.created':
          print('🟢 Session created');
          break;

        case 'input_audio_buffer.speech_started':
          _stateController.add('speech_started');
          print('🎤 Speech detected');
          break;

        case 'input_audio_buffer.speech_stopped':
          _stateController.add('speech_stopped');
          print('🔇 Speech stopped');
          break;

        case 'conversation.item.input_audio_transcription.completed':
          final transcript = data['transcript'] as String;
          _transcriptController.add(transcript);
          print('📝 Transcript: $transcript');
          break;

        case 'response.created':
          _accumulatedResponse = '';
          _stateController.add('response_started');
          break;

        case 'response.output_item.added':
          print('💬 Response item added');
          break;

        case 'response.content_part.added':
          print('📄 Content part added');
          break;

        case 'response.audio_transcript.delta':
          final delta = data['delta'] as String;
          _accumulatedResponse += delta;
          _responseController.add(_accumulatedResponse);
          break;

        case 'response.audio.delta':
          final audioBase64 = data['delta'] as String;
          if (audioBase64.isNotEmpty) {
            try {
              final audioBytes = base64Decode(audioBase64);
              if (audioBytes.isNotEmpty) {
                _audioResponseController.add(audioBytes);
                print('🎵 Audio chunk received: ${audioBytes.length} bytes');
              }
            } catch (e) {
              print('❌ Error decoding audio: $e');
            }
          }
          break;

        case 'response.audio.done':
          print('🔊 Audio response complete');
          _stateController.add('response_complete');
          break;

        case 'response.done':
          print('✅ Response done');
          break;

        case 'error':
          final error = data['error'];
          print('❌ API Error: $error');
          _stateController.add('error');
          break;
      }
    } catch (e) {
      print('❌ Error handling message: $e');
    }
  }

  void sendAudio(Uint8List audioChunk) {
    if (!_isConnected || _channel == null) {
      // Only print once to avoid spam
      if (!_reconnecting) {
        print('⚠️ Cannot send audio - not connected, attempting reconnect...');
        _attemptReconnect();
      }
      return;
    }

    try {
      final base64Audio = base64Encode(audioChunk);
      _channel!.sink.add(
        jsonEncode({'type': 'input_audio_buffer.append', 'audio': base64Audio}),
      );
      // Log occasionally to avoid spam
      if (audioChunk.isNotEmpty) {
        print('📤 Sent audio chunk: ${audioChunk.length} bytes');
      }
    } catch (e) {
      print('❌ Error sending audio: $e');
      _isConnected = false;
    }
  }

  Future<void> _attemptReconnect() async {
    if (_reconnecting) return;
    _reconnecting = true;

    print('🔄 Attempting to reconnect...');
    final success = await connect();

    if (success) {
      print('✅ Reconnected successfully');
    } else {
      print('❌ Reconnect failed');
    }

    _reconnecting = false;
  }

  void commitAudio() {
    if (!_isConnected || _channel == null) {
      print('⚠️ Cannot commit audio - not connected');
      return;
    }

    print('📨 Committing audio buffer...');
    _channel!.sink.add(jsonEncode({'type': 'input_audio_buffer.commit'}));

    // Explicitly trigger response creation
    print('📨 Requesting response...');
    _channel!.sink.add(jsonEncode({'type': 'response.create'}));
  }

  void cancelResponse() {
    if (!_isConnected || _channel == null) return;

    _channel!.sink.add(jsonEncode({'type': 'response.cancel'}));

    _accumulatedResponse = '';
    print('⏹️ Response cancelled');
  }

  Future<void> disconnect() async {
    if (!_isConnected) return;

    await _channel?.sink.close();
    _isConnected = false;
    _stateController.add('disconnected');
    print('🔌 Disconnected from Realtime API');
  }

  Future<void> dispose() async {
    await disconnect();
    await _transcriptController.close();
    await _responseController.close();
    await _audioResponseController.close();
    await _stateController.close();
  }
}
