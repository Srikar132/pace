import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pace/presentation/overlays/screens/blocked_app_overlay.dart';
import 'package:pace/presentation/overlays/screens/blocked_applimit_overlay.dart';
import 'package:pace/presentation/overlays/screens/blocked_shorts_overlay.dart';
import 'package:pace/presentation/overlays/screens/blocked_website_overlay.dart';


class OverlayRouter {
  static final GoRouter router = GoRouter(
    initialLocation: '/blocked-app',
    routes: [
      GoRoute(
        path: '/blocked-app',
        name: 'blocked-app',
        builder: (context, state) => const BlockedAppOverlay(),
      ),
      GoRoute(
        path: '/blocked-shorts',
        name: 'blocked-shorts',
        builder: (context, state) => const BlockedShortsOverlay(),
      ),
      GoRoute(
        path: '/blocked-website',
        name:  'blocked-website',
        builder:  (context, state) => const BlockedWebsiteOverlay(),
      ),
      GoRoute(
        path: '/app-limit',
        name: 'app-limit',
        builder: (context, state) => const AppLimitOverlay(),
      ),
/*      GoRoute(
        path: '/notification-block',
        name:  'notification-block',
        builder: (context, state) => const NotificationBlockOverlay(),
      ),*/
    ],
  );
}