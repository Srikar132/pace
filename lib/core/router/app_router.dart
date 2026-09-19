import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pace/presentation/providers/app_bootstrap_provider.dart';
import 'package:pace/presentation/providers/auth_provider.dart';
import 'package:pace/presentation/providers/focus_session_provider.dart';
import 'package:pace/presentation/providers/permission_provider.dart';
import 'package:pace/presentation/screens/active_focus_screen.dart';
import 'package:pace/presentation/screens/home_screen.dart';
import 'package:pace/presentation/screens/manage_blocked_apps_screen.dart';
import 'package:pace/presentation/screens/onboarding/onboarding_screen.dart';
import 'package:pace/presentation/screens/permission_screen.dart';
import 'package:pace/presentation/screens/profile_screen.dart';
import 'package:pace/presentation/screens/save_session_screen.dart';
import 'package:pace/presentation/screens/splash_screen.dart';
import 'package:pace/presentation/screens/welcome_screen.dart';

const splashRoute = '/splash';
const welcomeRoute = '/welcome';
const onboardingRoute = '/onboarding';
const permissionsRoute = '/permissions';
const homeRoute = '/home';
const activeSessionRoute = '/active-session';
const saveSessionRoute = '/save-session';
const manageBlockedAppsRoute = '/manage-blocked-apps';
const profileRoute = '/profile';

/// Bridges Riverpod state changes into go_router's `refreshListenable`, so
/// `redirect` gets re-evaluated whenever any of the gating providers change
/// (auth, onboarding, permissions, active-session), not just on navigation.
class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(Ref ref) {
    ref.listen(isAuthenticatedProvider, (_, _) => notifyListeners());
    ref.listen(currentUserProvider, (_, _) => notifyListeners());
    ref.listen(authStateProvider, (_, _) => notifyListeners());
    ref.listen(authErrorProvider, (_, _) => notifyListeners());
    ref.listen(permissionProvider, (_, _) => notifyListeners());
    ref.listen(
      focusSessionProvider.select((s) => s.isActive),
      (_, _) => notifyListeners(),
    );
    ref.listen(appBootstrapProvider, (_, _) => notifyListeners());
  }
}

final appRouterProvider = Provider<GoRouter>((ref) {
  // _RouterRefreshNotifier's constructor ref.listen()s appBootstrapProvider
  // (and the other gating providers) below, which both starts the future
  // and reacts to it resolving - deliberately not ref.watch() here, which
  // would rebuild this whole provider (recreating the GoRouter instance,
  // losing navigation state) every time any of them change.
  final refreshNotifier = _RouterRefreshNotifier(ref);
  ref.onDispose(refreshNotifier.dispose);

  return GoRouter(
    initialLocation: splashRoute,
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final bootstrap = ref.read(appBootstrapProvider);
      // Deliberately authStateProvider's own isLoading, not the composite
      // authLoadingProvider (which also flips true for an in-progress
      // sign-in/sign-out action, not just "don't know the auth state yet").
      // Gating on that would force a redirect to /splash mid-sign-in,
      // which - unlike the old single-Navigator SplashScreen.build() swap -
      // actually tears down the /welcome *page* under go_router and kills
      // the open sign-in bottom sheet along with it.
      final isAuthResolving = ref.read(authStateProvider).isLoading;
      final currentUser = ref.read(currentUserProvider);
      final authError = ref.read(authErrorProvider);

      // Bootstrap (native session sync + initial permission sweep) and auth
      // are still resolving for the first time - park on /splash until
      // they're not.
      if (bootstrap.isLoading || isAuthResolving || currentUser.isLoading) {
        return loc == splashRoute ? null : splashRoute;
      }

      if (authError != null) {
        return loc == splashRoute ? null : splashRoute;
      }

      final isAuthenticated = ref.read(isAuthenticatedProvider);
      final user = currentUser.value;
      if (!isAuthenticated || user == null) {
        return loc == welcomeRoute ? null : welcomeRoute;
      }

      if (!user.hasCompletedOnboarding) {
        return loc == onboardingRoute ? null : onboardingRoute;
      }

      final permissionState = ref.read(permissionProvider);
      if (!permissionState.allGranted) {
        return loc == permissionsRoute ? null : permissionsRoute;
      }

      // All gates passed. If we're actually sitting on one of the gate
      // screens themselves, move forward - either because a reactive state
      // change (e.g. the last permission got granted while on
      // /permissions) means we no longer belong here, or because this is
      // the initial landing from /splash. Leave every other screen alone
      // so this doesn't fight explicit in-app navigation, e.g.
      // focus_screen.dart pushing /active-session on top of /home.
      const gateLocations = {
        splashRoute,
        welcomeRoute,
        onboardingRoute,
        permissionsRoute,
      };
      if (gateLocations.contains(loc)) {
        final focusSession = ref.read(focusSessionProvider);
        return focusSession.isActive ? activeSessionRoute : homeRoute;
      }

      return null;
    },
    routes: [
      GoRoute(
        path: splashRoute,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: welcomeRoute,
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: onboardingRoute,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: permissionsRoute,
        builder: (context, state) => const PermissionScreen(),
      ),
      GoRoute(path: homeRoute, builder: (context, state) => const HomeScreen()),
      GoRoute(
        path: activeSessionRoute,
        builder: (context, state) => const ActiveFocusScreen(),
      ),
      GoRoute(
        path: saveSessionRoute,
        builder: (context, state) => SaveSessionScreen(
          sessionData: state.extra as Map<String, dynamic>? ?? const {},
        ),
      ),
      GoRoute(
        path: manageBlockedAppsRoute,
        builder: (context, state) => const ManageBlockedAppsScreen(),
      ),
      GoRoute(
        path: profileRoute,
        builder: (context, state) => const ProfileScreen(),
      ),
    ],
  );
});
