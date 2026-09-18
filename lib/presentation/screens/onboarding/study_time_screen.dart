import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pace/presentation/providers/onboarding_provider.dart';

class StudyTimeScreen extends ConsumerWidget {
  const StudyTimeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final onboardingState = ref.watch(onboardingProvider);
    final onboardingNotifier = ref.read(onboardingProvider.notifier);

    final studyTimes = [
      {
        'id': 'early_bird',
        'title': 'Early Bird',
        'time': '5:00 AM - 9:00 AM',
        'icon': '🌅',
      },
      {
        'id': 'morning',
        'title': 'Morning Person',
        'time': '9:00 AM - 12:00 PM',
        'icon': '☀️',
      },
      {
        'id': 'afternoon',
        'title': 'Afternoon Focus',
        'time': '12:00 PM - 5:00 PM',
        'icon': '🌤️',
      },
      {
        'id': 'evening',
        'title': 'Evening Owl',
        'time': '5:00 PM - 9:00 PM',
        'icon': '🌆',
      },
      {
        'id': 'night',
        'title': 'Night Owl',
        'time': '9:00 PM - 1:00 AM',
        'icon': '🌙',
      },
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight:
              MediaQuery.of(context).size.height -
              MediaQuery.of(context).padding.top -
              MediaQuery.of(context).padding.bottom -
              48, // Account for padding
        ),
        child: IntrinsicHeight(
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
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.2,
                            ),
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
                        "What's your preferred study time?",
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // Study time options
              ...studyTimes.map((time) {
                final isSelected =
                    onboardingState.preferredStudyTime == time['id'];

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: _StudyTimeOption(
                    title: time['title'] as String,
                    time: time['time'] as String,
                    emoji: time['icon'] as String,
                    isSelected: isSelected,
                    onTap: () {
                      onboardingNotifier.setPreferredStudyTime(
                        time['id'] as String,
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

              const Expanded(child: SizedBox()),

              // Continue button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onboardingState.preferredStudyTime == null
                      ? null
                      : () {
                          onboardingNotifier.nextPage();
                        },
                  child: const Text('Continue'),
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _StudyTimeOption extends StatelessWidget {
  final String title;
  final String time;
  final String emoji;
  final bool isSelected;
  final VoidCallback onTap;

  const _StudyTimeOption({
    required this.title,
    required this.time,
    required this.emoji,
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
            Text(emoji, style: const TextStyle(fontSize: 32)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    time,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white54,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? theme.colorScheme.primary : Colors.white30,
            ),
          ],
        ),
      ),
    );
  }
}
