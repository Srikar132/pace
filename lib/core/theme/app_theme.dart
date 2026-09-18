// File: lib/core/theme/app_theme.dart

import 'package:flutter/material.dart';

class AppTheme {
  // Exact reGain app colors
  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: const ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFF82D65D),
      onPrimary: Color(0xFF1A1A1A),
      secondary: Color(0xFF8FD66E), // Lighter green for accents
      onSecondary: Color(0xFF1A1A1A),
      tertiary: Color(0xFF5CAF3C), // Darker green
      onTertiary: Colors.white,
      error: Color(0xFFFF5252),
      onError: Colors.white,
      surface: Color(0xFF1E1E1E), // Card/elevated surface
      onSurface: Color(0xFFFFFFFF), // White text
      surfaceContainerHighest: Color(0xFF2A2A2A), // Slightly elevated
      outline: Color(0xFF3A3A3A), // Border color
      shadow: Color(0xFF000000),
    ),
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.bold,
        color: Colors.white,
        letterSpacing: -0.5,
      ),
      displayMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: Colors.white,
        letterSpacing: -0.5,
      ),
      displaySmall: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
      headlineLarge: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
      headlineMedium: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
      headlineSmall: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
      titleLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: Colors.white,
      ),
      titleSmall: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: Color(0xFFB0B0B0),
      ),
      bodyLarge: TextStyle(fontSize: 16, color: Color(0xFFE0E0E0), height: 1.5),
      bodyMedium: TextStyle(
        fontSize: 14,
        color: Color(0xFFB0B0B0),
        height: 1.5,
      ),
      bodySmall: TextStyle(fontSize: 12, color: Color(0xFF8A8A8A), height: 1.4),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Color(0xFFB0B0B0),
        letterSpacing: 0.3,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Color(0xFF8A8A8A),
        letterSpacing: 0.3,
      ),
      labelSmall: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w500,
        color: Color(0xFF6A6A6A),
        letterSpacing: 0.3,
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF0F0F0F),
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 22,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
      ),
      iconTheme: IconThemeData(color: Colors.white, size: 24),
      actionsIconTheme: IconThemeData(color: Colors.white, size: 24),
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF2A2A2A),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF3A3A3A), width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF3A3A3A), width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF7ED957), width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFFF5252), width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFFF5252), width: 2),
      ),
      labelStyle: const TextStyle(color: Color(0xFF8A8A8A), fontSize: 14),
      hintStyle: const TextStyle(color: Color(0xFF6A6A6A), fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        disabledBackgroundColor: const Color(0xFF3A3A3A),
        disabledForegroundColor: const Color(0xFF6A6A6A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
        elevation: 0,
        shadowColor: Colors.transparent,
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        side: const BorderSide(color: Color(0xFF3A3A3A), width: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF7ED957),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    ),
    cardTheme: CardThemeData(
      color: const Color(0xFF1E1E1E),
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFF2A2A2A), width: 1),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: const Color(0xFF1E1E1E),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: const TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
      contentTextStyle: const TextStyle(
        color: Color(0xFFB0B0B0),
        fontSize: 16,
        height: 1.5,
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Color(0xFF1E1E1E),
      modalBackgroundColor: Color(0xFF1E1E1E),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: const Color(0xFF2A2A2A),
      selectedColor: const Color(0xFF7ED957),
      disabledColor: const Color(0xFF1A1A1A),
      labelStyle: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      secondaryLabelStyle: const TextStyle(
        color: Color(0xFF1A1A1A),
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: BorderSide.none,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const Color(0xFF1A1A1A);
        }
        return const Color(0xFF6A6A6A);
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const Color(0xFF7ED957);
        }
        return const Color(0xFF3A3A3A);
      }),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: Color(0xFF7ED957),
      inactiveTrackColor: Color(0xFF3A3A3A),
      thumbColor: Color(0xFF7ED957),
      overlayColor: Color(0x337ED957),
      valueIndicatorColor: Color(0xFF7ED957),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: Color(0xFF7ED957),
      linearTrackColor: Color(0xFF3A3A3A),
      circularTrackColor: Color(0xFF3A3A3A),
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0xFF2A2A2A),
      thickness: 1,
      space: 1,
    ),
    scaffoldBackgroundColor: const Color(0xFF0F0F0F),
    dividerColor: const Color(0xFF2A2A2A),
    splashColor: const Color(0x1A7ED957),
    highlightColor: const Color(0x0D7ED957),
    iconTheme: const IconThemeData(color: Colors.white, size: 24),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Color(0xFF7ED957),
      foregroundColor: Color(0xFF1A1A1A),
      elevation: 0,
      highlightElevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: const Color(0xFF0F0F0F),
      indicatorColor: const Color(0xFF7ED957).withValues(alpha: 0.15),
      elevation: 0,
      height: 70,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF7ED957),
          );
        }
        return const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: Color(0xFF6A6A6A),
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: Color(0xFF7ED957), size: 26);
        }
        return const IconThemeData(color: Color(0xFF6A6A6A), size: 26);
      }),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: const Color(0xFF2A2A2A),
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      behavior: SnackBarBehavior.floating,
      elevation: 0,
    ),
    listTileTheme: const ListTileThemeData(
      tileColor: Color(0xFF1E1E1E),
      textColor: Colors.white,
      iconColor: Color(0xFF7ED957),
      contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
    badgeTheme: const BadgeThemeData(
      backgroundColor: Color(0xFF7ED957),
      textColor: Color(0xFF1A1A1A),
      textStyle: TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
    ),
  );
}

// Optional: Color constants file
// File: lib/core/theme/app_colors.dart
class AppColors {
  // Brand Colors
  static const primaryGreen = Color(0xFF82D65D); // Main lime green
  static const lightGreen = Color(0xFF8FD66E); // Lighter variant
  static const darkGreen = Color(0xFF5CAF3C); // Darker variant

  // Background Colors
  static const background = Color(0xFF0F0F0F); // Main dark background
  static const surface = Color(0xFF1E1E1E); // Cards and elevated surfaces
  static const surfaceElevated = Color(0xFF2A2A2A); // More elevated

  // Text Colors
  static const textPrimary = Color(0xFFFFFFFF); // White
  static const textSecondary = Color(0xFFE0E0E0); // Light gray
  static const textTertiary = Color(0xFFB0B0B0); // Medium gray
  static const textMuted = Color(0xFF8A8A8A); // Muted gray
  static const textDisabled = Color(0xFF6A6A6A); // Disabled gray

  // Border & Divider
  static const border = Color(0xFF3A3A3A);
  static const divider = Color(0xFF2A2A2A);

  // Status Colors
  static const error = Color(0xFFFF5252);
  static const success = Color(0xFF7ED957);
  static const warning = Color(0xFFFFB84D);
  static const info = Color(0xFF64B5F6);

  // Special
  static const activeIndicator = Color(
    0xFF7ED957,
  ); // Green dot for "focusing now"
  static const buttonWhite = Color(0xFFFFFFFF); // White buttons
  static const proYellow = Color(0xFFFFD700); // PRO badge
}
