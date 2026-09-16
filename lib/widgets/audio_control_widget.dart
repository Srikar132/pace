import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pace/services/audio_service.dart';
import 'package:pace/presentation/providers/audio_providers.dart';

/// A comprehensive audio control widget that demonstrates the audio service capabilities
class AudioControlWidget extends ConsumerStatefulWidget {
  const AudioControlWidget({super.key});

  @override
  ConsumerState<AudioControlWidget> createState() => _AudioControlWidgetState();
}

class _AudioControlWidgetState extends ConsumerState<AudioControlWidget> {
  double _currentSpeed = 1.0;
  double _musicVolume = 0.7;
  double _soundVolume = 1.0;
  double _backgroundVolume = 0.3;
  
  final List<double> _speedValues = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  late AudioService _audioService;

  @override
  void initState() {
    super.initState();
    _audioService = ref.read(audioServiceProvider);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          ],
        ),
      ),
    );
  }

  Widget _buildAudioTypeControls(AudioType type, String label) {
    return AnimatedBuilder(
      animation: _audioService,
      builder: (context, _) {
        final isPlaying = _audioService.isPlaying(type);
        final state = _audioService.getStateByType(type);
        final progress = _audioService.getProgress(type);
        
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      label,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const Spacer(),
                    Text(
                      state.name.toUpperCase(),
                      style: TextStyle(
                        fontSize: 12,
                        color: isPlaying ? Colors.green : Colors.grey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                
                // Progress bar
                LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.grey.shade300,
                  valueColor: AlwaysStoppedAnimation(
                    isPlaying ? Colors.blue : Colors.grey,
                  ),
                ),
                
                const SizedBox(height: 8),
                
                // Control buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      onPressed: isPlaying
                          ? () => AudioServiceMethods.pause(ref, type)
                          : null,
                      icon: const Icon(Icons.pause, size: 20),
                      tooltip: 'Pause',
                    ),
                    IconButton(
                      onPressed: !isPlaying && state == AudioPlayerState.paused
                          ? () => AudioServiceMethods.resume(ref, type)
                          : null,
                      icon: const Icon(Icons.play_arrow, size: 20),
                      tooltip: 'Resume',
                    ),
                    IconButton(
                      onPressed: () => AudioServiceMethods.stop(ref, type),
                      icon: const Icon(Icons.stop, size: 20),
                      tooltip: 'Stop',
                    ),
                    IconButton(
                      onPressed: () => _showFileDialog(type),
                      icon: const Icon(Icons.folder_open, size: 20),
                      tooltip: 'Load File',
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showFileDialog(AudioType type) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Play ${type.name.toUpperCase()}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.audiotrack),
              title: const Text('Play Asset Sound'),
              subtitle: const Text('sounds/lumo-sound.wav'),
              onTap: () {
                AudioServiceMethods.playAsset(
                  ref,
                  assetPath: 'sounds/lumo-sound.wav',
                  type: type,
                  trackName: 'Lumo Sound',
                  loop: type == AudioType.background,
                );
                Navigator.pop(context);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Play from URL'),
              subtitle: const Text('Enter a URL'),
              onTap: () {
                Navigator.pop(context);
                _showUrlDialog(type);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showUrlDialog(AudioType type) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Play from URL'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'https://example.com/audio.mp3',
            labelText: 'Audio URL',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                AudioServiceMethods.playUrl(
                  ref,
                  url: controller.text,
                  type: type,
                  trackName: 'URL Audio',
                  loop: type == AudioType.background,
                );
                Navigator.pop(context);
              }
            },
            child: const Text('Play'),
          ),
        ],
      ),
    );
  }
}
