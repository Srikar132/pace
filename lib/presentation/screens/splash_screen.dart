import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pace/presentation/providers/auth_provider.dart';
import 'package:pace/presentation/providers/focus_session_provider.dart';
import 'package:pace/presentation/providers/permission_provider.dart';
import 'package:pace/presentation/screens/entry_screen.dart';
import 'package:pace/presentation/screens/home_screen.dart';
import 'package:pace/presentation/screens/onboarding/onboarding_screen.dart';
import 'package:pace/presentation/screens/permission_screen.dart';
import 'package:pace/presentation/screens/active_focus_screen.dart';
import 'package:pace/services/native_service.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  bool _hasCheckedSession = false;
  bool _hasCheckedPermissions = false;

  @override
  void initState() {
    super.initState();
    _checkActiveSession();
  }

  Future<void> _checkActiveSession() async {
    // Wait a brief moment to ensure providers are ready
    await Future.delayed(const Duration(milliseconds: 100));

    try {
      final status = await NativeService.getCurrentSessionStatus();

      if (status != null && status['isActive'] == true && mounted) {
        // Sync the session state to Flutter
        await ref
            .read(focusSessionProvider.notifier)
            .refreshSessionFromNative();

        setState(() {
          _hasCheckedSession = true;
        });
      } else {
        setState(() {
          _hasCheckedSession = true;
        });
      }
    } catch (e) {
      debugPrint('Error checking active session: $e');
      setState(() {
        _hasCheckedSession = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch authentication status and user data
    final isAuthenticated = ref.watch(isAuthenticatedProvider);
    final currentUser = ref.watch(currentUserProvider);
    final isLoading = ref.watch(authLoadingProvider);
    final authError = ref.watch(authErrorProvider);
    final focusSession = ref.watch(focusSessionProvider);

    // Show loading screen while determining state
    if (isLoading || currentUser.isLoading || !_hasCheckedSession) {
      return const _LoadingScreen();
    }

    // Handle authentication error
    if (authError != null) {
      return _ErrorScreen(
        error: authError,
        onRetry: () {
          ref.read(authNotifierProvider.notifier).clearError();
        },
      );
    }

    // Not authenticated - show entry screen
    if (!isAuthenticated) {
      return const EntryScreen();
    }

    // Authenticated - route based on user completion status
    return currentUser.when(
      data: (user) {
        if (user == null) {
          return const EntryScreen();
        }

        // Check onboarding status
        if (!user.hasCompletedOnboarding) {
          return const OnboardingScreen();
        }

        // Check permissions in real-time from provider, not database
        // This ensures we always check actual permission status
        final permissionState = ref.watch(permissionProvider);

        // Trigger permission check once per splash screen visit, not on
        // every rebuild (this widget also rebuilds on every focus-session
        // timer tick, since it stays mounted as the app's root widget).
        if (!_hasCheckedPermissions) {
          _hasCheckedPermissions = true;
          Future.microtask(() {
            ref.read(permissionProvider.notifier).checkPermissions();
          });
        }

        // If ANY permission is not granted, show permission screen
        // User must grant ALL permissions before proceeding
        if (!permissionState.allGranted) {
          return const PermissionScreen();
        }

        // If there's an active focus session, show the active focus screen
        if (focusSession.isActive) {
          return ActiveFocusScreen(
            sessionId: focusSession.sessionId ?? '',
            plannedDuration: focusSession.plannedDuration ?? 0,
            sessionType: focusSession.sessionType ?? 'focus',
          );
        }

        // Everything completed - show home
        return const HomeScreen();
      },
      loading: () => const _LoadingScreen(),
      error: (error, _) => _ErrorScreen(
        error: error.toString(),
        onRetry: () => ref.read(authNotifierProvider.notifier).clearError(),
      ),
    );
  }
}

class _ErrorScreen extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _ErrorScreen({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A4D3E), Color(0xFF82D65D)],
          ),
        ),
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Error Icon
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.error_outline,
                  size: 50,
                  color: Colors.white,
                ),
              ),

              const SizedBox(height: 24),

              // Error Title
              const Text(
                'Something went wrong',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 16),

              // Error Message
              Text(
                error,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 32),

              // Retry Button
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF1A4D3E),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingScreen extends StatefulWidget {
  const _LoadingScreen();

  @override
  State<_LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<_LoadingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(
      begin: 0.85,
      end: 1.05,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(20)),
            child: Icon(
              Icons.hourglass_full,
              size: 50,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}
