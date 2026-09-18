import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pace/core/constants/audios.dart';
import 'package:pace/presentation/providers/audio_providers.dart';
import 'package:pace/services/audio_service.dart';

class AudioBottomSheet extends ConsumerStatefulWidget {
  const AudioBottomSheet({super.key});

  @override
  ConsumerState<AudioBottomSheet> createState() => _AudioBottomSheetState();
}

class _AudioBottomSheetState extends ConsumerState<AudioBottomSheet> {
  Audio? selectedAudio;
  Timer? _stateCheckTimer;

  @override
  void initState() {
    super.initState();
    _stateCheckTimer = Timer.periodic(const Duration(milliseconds: 500), (
      timer,
    ) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _stateCheckTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      height: screenHeight * 0.88,
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F0F),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        children: [
          _buildDragHandle(),
          _buildHeader(theme),
          Expanded(child: _buildAudioGrid(theme)),
        ],
      ),
    );
  }

  Widget _buildDragHandle() {
    return Container(
      margin: const EdgeInsets.only(top: 16, bottom: 8),
      width: 48,
      height: 5,
      decoration: BoxDecoration(
        color: const Color(0xFF3A3A3A),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF82D65D).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF82D65D).withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  Icons.music_note_rounded,
                  color: Color(0xFF82D65D),
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Focus Sounds',
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 26,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Enhance your concentration',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF8A8A8A),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAudioGrid(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                'SELECT YOUR SOUND',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: const Color(0xFF82D65D),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 0.82,
                ),
                itemCount: AudioConstants.audioList.length,
                itemBuilder: (context, index) {
                  final audio = AudioConstants.audioList[index];
                  final isSelected =
                      selectedAudio?.songAssetUrl == audio.songAssetUrl;
                  final audioService = ref.read(audioServiceProvider);
                  return _buildAudioCard(
                    audio,
                    isSelected,
                    theme,
                    audioService,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioCard(
    Audio audio,
    bool isSelected,
    ThemeData theme,
    AudioService audioService,
  ) {
    final isMusic = audio.songAssetUrl.endsWith('.mp3');
    final audioType = isMusic ? AudioType.song : AudioType.sound;
    final isCurrentlyPlaying = audioService.isPlaying(audioType) && isSelected;

    return GestureDetector(
      onTap: () => _handleAudioTap(
        audio,
        isSelected,
        isCurrentlyPlaying,
        audioType,
        isMusic,
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF82D65D)
                : const Color(0xFF3A3A3A),
            width: isSelected ? 2.5 : 1.5,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF82D65D).withValues(alpha: 0.25),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Full background image
              Image.asset(
                audio.image,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFF82D65D).withValues(alpha: 0.3),
                          const Color(0xFF5CAF3C).withValues(alpha: 0.2),
                        ],
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        isMusic
                            ? Icons.music_note_rounded
                            : Icons.volume_up_rounded,
                        color: const Color(0xFF82D65D).withValues(alpha: 0.6),
                        size: 48,
                      ),
                    ),
                  );
                },
              ),

              // Dark gradient overlay
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.3),
                      Colors.black.withValues(alpha: 0.75),
                    ],
                  ),
                ),
              ),

              // Selected state overlay
              if (isSelected)
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF82D65D).withValues(alpha: 0.15),
                        const Color(0xFF82D65D).withValues(alpha: 0.05),
                      ],
                    ),
                  ),
                ),

              // Content overlay
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top section - Type badge
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(
                                      0xFF82D65D,
                                    ).withValues(alpha: 0.6)
                                  : Colors.white.withValues(alpha: 0.2),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isMusic
                                    ? Icons.album_rounded
                                    : Icons.graphic_eq_rounded,
                                size: 12,
                                color: isSelected
                                    ? const Color(0xFF82D65D)
                                    : Colors.white,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isMusic ? 'MUSIC' : 'SOUND',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 10,
                                  letterSpacing: 0.5,
                                  color: isSelected
                                      ? const Color(0xFF82D65D)
                                      : Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // Bottom section - Play button and name
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Play/Pause button
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF82D65D)
                                : Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color:
                                    (isSelected
                                            ? const Color(0xFF82D65D)
                                            : Colors.white)
                                        .withValues(alpha: 0.5),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Icon(
                            (isSelected && isCurrentlyPlaying)
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: const Color(0xFF1A1A1A),
                            size: 30,
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Audio Name
                        Text(
                          audio.name,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: Colors.white,
                            letterSpacing: -0.3,
                            shadows: [
                              Shadow(
                                color: Colors.black.withValues(alpha: 0.5),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleAudioTap(
    Audio audio,
    bool isSelected,
    bool isCurrentlyPlaying,
    AudioType audioType,
    bool isMusic,
  ) async {
    if (isSelected && isCurrentlyPlaying) {
      await AudioServiceMethods.pause(ref, audioType);
      _showSnackBar('Paused ${audio.name}', Icons.pause_circle_rounded);
    } else if (isSelected && !isCurrentlyPlaying) {
      await AudioServiceMethods.resume(ref, audioType);
      _showSnackBar('Resumed ${audio.name}', Icons.play_circle_rounded);
    } else {
      setState(() {
        selectedAudio = audio;
      });

      await AudioServiceMethods.stopAll(ref);
      await AudioServiceMethods.playAsset(
        ref,
        assetPath: audio.songAssetUrl,
        type: audioType,
        trackName: audio.name,
        loop: isMusic,
      );

      _showSnackBar('Playing ${audio.name}', Icons.music_note_rounded);
    }
  }

  void _showSnackBar(String message, IconData icon) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: const Color(0xFF82D65D), size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF2A2A2A),
        duration: const Duration(milliseconds: 1500),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 100, left: 20, right: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF3A3A3A), width: 1),
        ),
      ),
    );
  }
}
