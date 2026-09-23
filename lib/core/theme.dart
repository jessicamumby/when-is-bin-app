import 'package:flutter/material.dart';

/// Design system tokens from whenisbins.com (styles-new.css).
///
/// Palette:
///   ink   #323131  (text, header, dark surfaces)
///   paper #f7f3f3  (page background)
///   teal  #0f7d75  (primary action, accents)
///   aqua  #7cc7d5  (soft accent, brand mark)
///   coral #f58757  (secondary accent)
///   link  #325b92  (links)
///   focus #e9ae21  (focus ring)
///   error #b10e1e  (errors)
class AppColors {
  AppColors._();

  static const ink = Color(0xFF323131);
  static const paper = Color(0xFFF7F3F3);
  static const white = Color(0xFFFFFFFF);
  static const aqua = Color(0xFF7CC7D5);
  static const coral = Color(0xFFF58757);
  static const teal = Color(0xFF0F7D75);
  static const link = Color(0xFF325B92);
  static const focus = Color(0xFFE9AE21);
  static const muted = Color(0xFF5A5555);
  static const border = Color(0xFFBDAEA4);
  static const borderSoft = Color(0xFFD8CFC9);
  static const error = Color(0xFFB10E1E);
  static const softAqua = Color(0xFFE8F3F4);
  static const softCoral = Color(0xFFFBEEE8);
  static const softGreen = Color(0xFFE8F1EC);
  static const softPink = Color(0xFFF8ECEF);
}

/// The whenisbins design system as a Flutter [ThemeData].
class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.teal,
        primary: AppColors.teal,
        surface: AppColors.paper,
        error: AppColors.error,
      ),
      scaffoldBackgroundColor: AppColors.paper,
      fontFamily: 'LexendDeca',
    );

    return base.copyWith(
      textTheme: base.textTheme
          .apply(
            bodyColor: AppColors.ink,
            displayColor: AppColors.ink,
          )
          .copyWith(
            headlineLarge: const TextStyle(
              fontSize: 40,
              height: 1.05,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: AppColors.ink,
            ),
            headlineMedium: const TextStyle(
              fontSize: 28,
              height: 1.15,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
            titleLarge: const TextStyle(
              fontSize: 24,
              height: 1.25,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
            bodyLarge: const TextStyle(
              fontSize: 19,
              height: 1.5,
              color: AppColors.ink,
            ),
            bodyMedium: const TextStyle(
              fontSize: 16,
              height: 1.5,
              color: AppColors.ink,
            ),
            labelLarge: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: AppColors.white,
            ),
          ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.ink,
        foregroundColor: AppColors.paper,
        elevation: 0,
        centerTitle: false,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.teal,
          foregroundColor: AppColors.white,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: const RoundedRectangleBorder(),
          textStyle: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          side: const BorderSide(color: AppColors.ink, width: 2),
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: const RoundedRectangleBorder(),
          textStyle: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: AppColors.ink, width: 2),
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: AppColors.ink, width: 2),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: AppColors.ink, width: 2),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: AppColors.error, width: 3),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: AppColors.error, width: 3),
        ),
        labelStyle: const TextStyle(
          color: AppColors.ink,
          fontWeight: FontWeight.w700,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.borderSoft,
        thickness: 1,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.teal,
      ),
    );
  }
}
