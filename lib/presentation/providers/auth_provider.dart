// Clean Firebase-only authentication provider
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pace/data/models/user_model.dart';
import 'package:pace/data/repositories/auth_repository.dart';
import 'package:pace/data/repositories/user_repository.dart';
import 'package:pace/presentation/providers/permission_provider.dart';

// Auth State for loading management
class AuthState {
  final bool isSigningIn;
  final bool isSigningOut;
  final String? error;

  const AuthState({
    this.isSigningIn = false,
    this.isSigningOut = false,
    this.error,
  });

  AuthState copyWith({
    bool? isSigningIn,
    bool? isSigningOut,
    String? error,
    bool clearError = false,
  }) {
    return AuthState(
      isSigningIn: isSigningIn ?? this.isSigningIn,
      isSigningOut: isSigningOut ?? this.isSigningOut,
      error: clearError ? null : error ?? this.error,
    );
  }

  // Helper getters
  bool get hasError => error != null;
  bool get isProcessing => isSigningIn || isSigningOut;
}

// Repository Providers
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(),
);
final userRepositoryProvider = Provider<UserRepository>(
  (ref) => UserRepository(),
);

// Firebase Auth State (Single Source of Truth)
final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
});

// User Data Stream (Firebase handles all caching automatically)
final currentUserProvider = StreamProvider<UserModel?>((ref) {
  final authState = ref.watch(authStateProvider);

  return authState.when(
    data: (firebaseUser) {
      if (firebaseUser == null) {
        return Stream.value(null);
      }

      return ref.watch(userRepositoryProvider).streamUserData(firebaseUser.uid);
    },
    loading: () => Stream.value(null),
    error: (error, stack) => Stream.value(null),
  );
});

class AuthNotifier extends Notifier<AuthState> {
  late AuthRepository _authRepository;
  late UserRepository _userRepository;

  @override
  AuthState build() {
    _authRepository = ref.read(authRepositoryProvider);
    _userRepository = ref.read(userRepositoryProvider);
    return const AuthState();
  }

  // Sign in with Google (Firebase handles all persistence)
  Future<void> signInWithGoogle() async {
    try {
      state = state.copyWith(isSigningIn: true, clearError: true);

      // Firebase handles all the persistence automatically
      final user = await _authRepository.signInWithGoogle();

      state = state.copyWith(isSigningIn: false);

      if (user == null) {
        state = state.copyWith(error: 'Sign-in was cancelled');
      }
    } catch (e) {
      state = state.copyWith(
        isSigningIn: false,
        error: 'Failed to sign in: ${e.toString()}',
      );
    }
  }

  // Sign out (Firebase handles clearing cached data)
  Future<void> signOut() async {
    try {
      state = state.copyWith(isSigningOut: true, clearError: true);

      // Firebase handles clearing all cached data
      await _authRepository.signOut();

      state = state.copyWith(isSigningOut: false);
    } catch (e) {
      state = state.copyWith(
        isSigningOut: false,
        error: 'Failed to sign out: ${e.toString()}',
      );
    }
  }

  // Complete onboarding (Firebase streams will update automatically)
  Future<void> completeOnboarding({
    required String userId,
    required String procrastinationLevel,
    required List<String> distractions,
    required String preferredStudyTime,
  }) async {
    try {
      // Update Firestore - Firebase will handle caching
      await _userRepository.updateOnboardingAnswers(
        uid: userId,
        procrastinationLevel: procrastinationLevel,
        distractions: distractions,
        preferredStudyTime: preferredStudyTime,
      );

      await _userRepository.updateOnboardingStatus(userId, true);

      // No need to manually update local cache - Firebase streams will update automatically
    } catch (e) {
      state = state.copyWith(
        error: 'Failed to complete onboarding: ${e.toString()}',
      );
      rethrow;
    }
  }

  // Update permissions (Firebase streams automatically update UI)
  Future<void> updatePermissionStatus(String userId, bool granted) async {
    try {
      await _userRepository.updatePermissionStatus(userId, granted);
      // Firebase streams automatically update UI
    } catch (e) {
      state = state.copyWith(
        error: 'Failed to update permissions: ${e.toString()}',
      );
      rethrow;
    }
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

// Auth Notifier Provider
final authNotifierProvider = NotifierProvider<AuthNotifier, AuthState>(() {
  return AuthNotifier();
});

// Derived Providers for UI
final isAuthenticatedProvider = Provider<bool>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.when(
    data: (user) => user != null,
    loading: () => false,
    error: (_, _) => false,
  );
});

final authLoadingProvider = Provider<bool>((ref) {
  final authState = ref.watch(authNotifierProvider);
  final streamState = ref.watch(authStateProvider);

  return authState.isProcessing || streamState.isLoading;
});

final authErrorProvider = Provider<String?>((ref) {
  return ref.watch(authNotifierProvider.select((state) => state.error));
});

// Navigation Helper Providers
final shouldShowOnboardingProvider = Provider<bool>((ref) {
  final user = ref.watch(currentUserProvider).value;
  final isAuthenticated = ref.watch(isAuthenticatedProvider);

  return isAuthenticated && user != null && !user.hasCompletedOnboarding;
});

final shouldShowPermissionsProvider = Provider<bool>((ref) {
  final user = ref.watch(currentUserProvider).value;
  final isAuthenticated = ref.watch(isAuthenticatedProvider);
  final permissionState = ref.watch(permissionProvider);

  // Check real-time permissions from provider, not database
  return isAuthenticated &&
      user != null &&
      user.hasCompletedOnboarding &&
      !permissionState.allGranted;
});

final shouldShowHomeProvider = Provider<bool>((ref) {
  final user = ref.watch(currentUserProvider).value;
  final isAuthenticated = ref.watch(isAuthenticatedProvider);
  final permissionState = ref.watch(permissionProvider);

  // Check real-time permissions from provider, not database
  return isAuthenticated &&
      user != null &&
      user.hasCompletedOnboarding &&
      permissionState.allGranted;
});
