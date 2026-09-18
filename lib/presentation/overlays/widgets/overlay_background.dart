import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class OverlayBackground extends StatelessWidget {
  final Widget child;
  final Gradient? gradient;
  final Color? backgroundColor;

  const OverlayBackground({
    super.key,
    required this.child,
    this.gradient,
    this. backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: gradient ?? const LinearGradient(
          colors: [AppColors.background, AppColors.surface],
          begin: Alignment. topCenter,
          end: Alignment. bottomCenter,
        ),
        color: backgroundColor,
      ),
      child: child,
    );
  }
}