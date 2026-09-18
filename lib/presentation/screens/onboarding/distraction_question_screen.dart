import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pace/presentation/providers/onboarding_provider.dart';

class DistractionQuestionScreen extends ConsumerWidget {
  const DistractionQuestionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final onboardingState = ref.watch(onboardingProvider);
    final onboardingNotifier = ref.read(onboardingProvider.notifier);

    final distractions = [
      {
        'id': 'reels',
        'text': 'I keep scrolling reels & shorts',
        'icon': Icons.video_library_outlined,
      },
      {
        'id': 'notifications',
        'text': 'I get distracted by notifications',
        'icon': Icons.notifications_outlined,
      },
      {
        'id': 'texting',
        'text': 'I keep texting on my phone',
        'icon': Icons.message_outlined,
      },
      {
        'id': 'games',
        'text': 'I play a lot of games',
        'icon': Icons.sports_esports_outlined,
      },
    ];

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),

          // Mascot + Question
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.3),
                    width: 2,
                  ),
                ),
                child: ClipOval(
                  child: Image.asset(
                    'assets/images/mascot.png',
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: theme.colorScheme.primary.withValues(alpha: 0.2),
                        child: Icon(
                          Icons.person,
                          size: 30,
                          color: theme.colorScheme.primary,
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    "What's your biggest distraction when you're trying to focus?",
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 32),

          // Distraction options
          ...distractions.map((distraction) {
            final isSelected =
                onboardingState.distractions.contains(distraction['id']) ==
                true;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: _DistractionOption(
                title: distraction['text'] as String,
                icon: distraction['icon'] as IconData,
                isSelected: isSelected,
                onTap: () {
                  onboardingNotifier.toggleDistraction(
                    distraction['id'] as String,
                  );
                },
              ),
            );
          }),

          const SizedBox(height: 16),

          // Info text
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Can be edited inside the app later',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          // Continue button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onboardingState.distractions.isNotEmpty == true
                  ? () {
                      onboardingNotifier.nextPage();
                    }
                  : null,
              child: const Text('Continue'),
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _DistractionOption extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _DistractionOption({
    required this.title,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.15)
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 32,
              color: isSelected ? theme.colorScheme.primary : Colors.white70,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            Icon(
              isSelected ? Icons.check_circle : Icons.radio_button_off,
              color: isSelected ? theme.colorScheme.primary : Colors.white30,
            ),
          ],
        ),
      ),
    );
  }
}
