import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import 'overlay_router.dart';

class OverlayApp extends ConsumerWidget {
  const OverlayApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Pace Overlay',
      debugShowCheckedModeBanner: false,
      routerConfig:  OverlayRouter.router,
      theme: AppTheme.darkTheme,
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