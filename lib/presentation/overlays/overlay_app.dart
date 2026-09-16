import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'overlay_router.dart';

class OverlayApp extends ConsumerWidget {
  const OverlayApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Pace Overlay',
      debugShowCheckedModeBanner: false,
      routerConfig:  OverlayRouter.router,
      theme:  ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6366F1),
          secondary: Color(0xFF8B5CF6),
          surface:  Color(0xFF0F0F0F),
          background: Color(0xFF0F0F0F), // Use same as surface to avoid flash
        ),
        fontFamily: 'Inter',
      ),
      builder: (context, child) {
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value:  const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness:  Brightness.light,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarIconBrightness:  Brightness.light,
          ),
          child: child ??  const SizedBox.shrink(),
        );
      },
    );
  }
}