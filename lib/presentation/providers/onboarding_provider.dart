import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pace/presentation/providers/auth_provider.dart';
// import 'package:pace/data/local/hive_service.dart'; // Removed - Firebase-only
import 'package:pace/data/repositories/user_repository.dart';

// Onboarding state
class OnboardingState {
  final int currentPage;
  final String? procrastinationLevel;
  final List<String> distractions;
  final String? preferredStudyTime;

  OnboardingState({
    this.currentPage = 0,
    this.procrastinationLevel,
    this.distractions = const [],
    this.preferredStudyTime,
  });

  OnboardingState copyWith({
    int? currentPage,
    String? procrastinationLevel,
    List<String>? distractions,
    String? preferredStudyTime,
  }) {
    return OnboardingState(
      currentPage: currentPage ?? this.currentPage,
      procrastinationLevel: procrastinationLevel ?? this.procrastinationLevel,
      distractions: distractions ?? this.distractions,
      preferredStudyTime: preferredStudyTime ?? this.preferredStudyTime,
    );
  }
}

// Onboarding notifier
class OnboardingNotifier extends Notifier<OnboardingState> {
  late UserRepository _userRepository;

  @override
  OnboardingState build() {
    _userRepository = ref.read(userRepositoryProvider);
    return OnboardingState();
  }

  // Move to next page
  void nextPage() {
    state = state.copyWith(currentPage: state.currentPage + 1);
  }

  // Move to previous page
  void previousPage() {
    if (state.currentPage > 0) {
      state = state.copyWith(currentPage: state.currentPage - 1);
    }
  }

  // Set procrastination level
  void setProcrastinationLevel(String level) {
    state = state.copyWith(procrastinationLevel: level);
  }

  // Toggle distraction
  void toggleDistraction(String distraction) {
    final distractions = List<String>.from(state.distractions);

    if (distractions.contains(distraction)) {
      distractions.remove(distraction);
    } else {
      distractions.add(distraction);
    }

    state = state.copyWith(distractions: distractions);
  }

  // Set preferred study time
  void setPreferredStudyTime(String time) {
    state = state.copyWith(preferredStudyTime: time);
  }

  // Complete onboarding
  Future<void> completeOnboarding(String userId) async {
    try {
      // Update Firestore
      await _userRepository.updateOnboardingAnswers(
        uid: userId,
        procrastinationLevel: state.procrastinationLevel,
        distractions: state.distractions,
        preferredStudyTime: state.preferredStudyTime,
      );

      await _userRepository.updateOnboardingStatus(userId, true);

      // Note: Removed HiveService.markOnboardingComplete() - Firebase handles all persistence
    } catch (e) {
      debugPrint('Error completing onboarding: $e');
      rethrow;
    }
  }
}

// Onboarding provider
final onboardingProvider =
    NotifierProvider<OnboardingNotifier, OnboardingState>(() {
      return OnboardingNotifier();
    });
