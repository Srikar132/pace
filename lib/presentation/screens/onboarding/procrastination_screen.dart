import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pace/core/router/app_router.dart';
import 'package:pace/presentation/providers/auth_provider.dart';
import 'package:pace/presentation/providers/onboarding_provider.dart';

class ProcrastinationScreen extends ConsumerWidget {
  const ProcrastinationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final onboardingState = ref.watch(onboardingProvider);
    final onboardingNotifier = ref.read(onboardingProvider.notifier);

    final procrastinationLevels = [
      {'id': 'struggle', 'text': 'I struggle to get started'},
      {'id': 'few_bad_days', 'text': 'I have a few bad days'},
      {'id': 'consistent', 'text': "I'm fairly consistent"},
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
                    'How often do you procrastinate before you start focusing?',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 32),

          // Procrastination level options
          ...procrastinationLevels.map((level) {
            final isSelected =
                onboardingState.procrastinationLevel == level['id'];

            return Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: _ProcrastinationOption(
                text: level['text'] as String,
                isSelected: isSelected,
                onTap: () {
                  onboardingNotifier.setProcrastinationLevel(
                    level['id'] as String,
                  );
                },
              ),
            );
          }),

          const Spacer(),

          // Complete onboarding button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onboardingState.procrastinationLevel == null
                  ? null
                  : () async {
                      // Check if user data is available
                      final userAsyncValue = ref.read(currentUserProvider);
                      userAsyncValue.when(
                        data: (user) async {
                          if (user == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text(
                                  'User not found. Please sign in again.',
                                ),
                                backgroundColor: theme.colorScheme.error,
                              ),
                            );
                            return;
                          }

                          try {
                            await onboardingNotifier.completeOnboarding(
                              user.uid,
                            );

                            // Route back through /splash so the router's
                            // redirect logic decides where to land next.
                            if (context.mounted) {
                              context.go(splashRoute);
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Error: ${e.toString()}'),
                                  backgroundColor: theme.colorScheme.error,
                                ),
                              );
                            }
                          }
                        },
                        loading: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Loading user data...'),
                            ),
                          );
                        },
                        error: (error, stack) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error loading user: $error'),
                              backgroundColor: theme.colorScheme.error,
                            ),
                          );
                        },
                      );
                    },
              child: const Text('Continue'),
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _ProcrastinationOption extends StatelessWidget {
  final String text;
  final bool isSelected;
  final VoidCallback onTap;

  const _ProcrastinationOption({
    required this.text,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
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
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
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
