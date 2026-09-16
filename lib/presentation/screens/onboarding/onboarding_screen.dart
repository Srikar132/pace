import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pace/presentation/providers/auth_provider.dart';
import 'package:pace/presentation/providers/onboarding_provider.dart';
import 'package:pace/presentation/screens/onboarding/welcome_back_screen.dart';
import 'package:pace/presentation/screens/onboarding/distraction_question_screen.dart';
import 'package:pace/presentation/screens/onboarding/study_time_screen.dart';
import 'package:pace/presentation/screens/onboarding/procrastination_screen.dart';

class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onboardingState = ref.watch(onboardingProvider);
    final currentUser = ref.watch(currentUserProvider).value;

    // Check if user is returning (has some data)
    final isReturningUser = currentUser?.hasCompletedOnboarding == false &&
        (currentUser?.procrastinationLevel != null ||
            currentUser?.distractions?.isNotEmpty == true);

    final screens = [
      if (isReturningUser) const WelcomeBackScreen(),
      const DistractionQuestionScreen(),
      const StudyTimeScreen(),
      const ProcrastinationScreen(),
    ];

    return Scaffold(
      body: Stack(
        children: [
          // Gradient background
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF0A2A1E),
                    Color(0xFF0F0F0F),
                  ],
                ),
              ),
            ),
          ),

          // Progress bar
          SafeArea(
            child: Column(
              children: [
                LinearProgressIndicator(
                  value: (onboardingState.currentPage + 1) / screens.length,
                  backgroundColor: Colors.white.withOpacity(0.1),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).colorScheme.primary,
                  ),
                  minHeight: 4,
                ),
                Expanded(
                  child: IndexedStack(
                    index: onboardingState.currentPage,
                    children: screens,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
