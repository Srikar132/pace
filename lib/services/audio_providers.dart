import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pace/services/audio_service.dart';

/// Provider for the audio service singleton
final audioServiceProvider = Provider<AudioService>((ref) {
  final service = AudioService();
  // Initialize the service when first accessed
  service.initialize();
  return service;
});

/// Convenience methods for audio operations
class AudioServiceMethods {
  static AudioService getService(WidgetRef ref) {
    return ref.read(audioServiceProvider);
  }

  /// Play notification sound
  static Future<void> playNotification(WidgetRef ref, [String? customPath]) async {
    final service = getService(ref);
    await service.playNotificationSound(customPath);
  }

  /// Play success sound
  static Future<void> playSuccess(WidgetRef ref) async {
    final service = getService(ref);
    await service.playSuccessSound();
  }

  /// Play error sound
  static Future<void> playError(WidgetRef ref) async {
    final service = getService(ref);
    await service.playErrorSound();
  }

  /// Play focus start sound
  static Future<void> playFocusStart(WidgetRef ref) async {
    final service = getService(ref);
    await service.playFocusStartSound();
  }

  /// Play focus end sound
  static Future<void> playFocusEnd(WidgetRef ref) async {
    final service = getService(ref);
    await service.playFocusEndSound();
  }

  /// Play asset sound
  static Future<bool> playAsset(
    WidgetRef ref, {
    required String assetPath,
    required AudioType type,
    String? trackId,
    String? trackName,
    bool loop = false,
    double? volume,
  }) async {
    final service = getService(ref);
    return await service.playAsset(
      assetPath: assetPath,
      type: type,
      trackId: trackId,
      trackName: trackName,
      loop: loop,
      volume: volume,
    );
  }

  /// Play file
  static Future<bool> playFile(
    WidgetRef ref, {
    required String filePath,
    required AudioType type,
    String? trackId,
    String? trackName,
    bool loop = false,
    double? volume,
  }) async {
    final service = getService(ref);
    return await service.playFile(
      filePath: filePath,
      type: type,
      trackId: trackId,
      trackName: trackName,
      loop: loop,
      volume: volume,
    );
  }

  /// Play URL
  static Future<bool> playUrl(
    WidgetRef ref, {
    required String url,
    required AudioType type,
    String? trackId,
    String? trackName,
    bool loop = false,
    double? volume,
  }) async {
    final service = getService(ref);
    return await service.playUrl(
      url: url,
      type: type,
      trackId: trackId,
      trackName: trackName,
      loop: loop,
      volume: volume,
    );
  }

  /// Control playback
  static Future<void> pause(WidgetRef ref, AudioType type) async {
    final service = getService(ref);
    await service.pause(type);
  }

  static Future<void> resume(WidgetRef ref, AudioType type) async {
    final service = getService(ref);
    await service.resume(type);
  }

  static Future<void> stop(WidgetRef ref, AudioType type) async {
    final service = getService(ref);
    await service.stop(type);
  }

  static Future<void> stopAll(WidgetRef ref) async {
    final service = getService(ref);
    await service.stopAll();
  }

  /// Volume and speed controls
  static Future<void> setVolume(WidgetRef ref, AudioType type, double volume) async {
    final service = getService(ref);
    await service.setVolume(type, volume);
  }

  static Future<void> setPlaybackSpeed(WidgetRef ref, double speed) async {
    final service = getService(ref);
    await service.setPlaybackSpeed(speed);
  }

  static Future<void> toggleMute(WidgetRef ref) async {
    final service = getService(ref);
    await service.toggleMute();
  }

  /// Seek
  static Future<void> seek(WidgetRef ref, AudioType type, Duration position) async {
    final service = getService(ref);
    await service.seek(type, position);
  }
}
