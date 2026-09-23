import 'package:flutter/material.dart';

/// Design system tokens from whenisbins.com (styles-new.css), plus the dark
/// palette that mirrors them.
///
/// Light palette:
///   ink   #323131  (text, header, dark surfaces)
///   paper #f7f3f3  (page background)
///   teal  #0e766e  (primary action, accents)
///   aqua  #7cc7d5  (soft accent, brand mark)
///   coral #f58757  (secondary accent)
///   link  #325b92  (links)
///   focus #e9ae21  (focus ring)
///   error #b10e1e  (errors)
///
/// Every text-on-fill pair below is asserted against WCAG AA in
/// `test/core/theme_test.dart` — including 7:1 for the secondary text, which
/// carries 16px body copy. When a token moves, that test is what says whether
/// it is still readable.
class AppColors {
  AppColors._();

  // ---------------------------------------------------------------- light --

  static const ink = Color(0xFF323131);
  static const paper = Color(0xFFF7F3F3);
  static const white = Color(0xFFFFFFFF);
  static const aqua = Color(0xFF7CC7D5);
  static const coral = Color(0xFFF58757);

  /// The site's own teal (#0f7d75) darkened just far enough to clear AA:
  /// teal text on a card (a `TextButton`, say) was 4.41:1 at the original
  /// value, and is 4.84:1 here. White on teal improves with it, 4.99 → 5.48.
  static const teal = Color(0xFF0E766E);
  static const link = Color(0xFF325B92);
  static const focus = Color(0xFFE9AE21);

  /// Secondary text. #5A5555 sat at 6.66:1 on paper, which is thin for 16px
  /// body copy; this clears 7:1 with headroom (7.91:1 on paper, 8.71:1 on
  /// white).
  static const muted = Color(0xFF4F4A4A);

  static const border = Color(0xFFBDAEA4);
  static const borderSoft = Color(0xFFD8CFC9);
  static const error = Color(0xFFB10E1E);
  static const softAqua = Color(0xFFE8F3F4);
  static const softCoral = Color(0xFFFBEEE8);
  static const softGreen = Color(0xFFE8F1EC);
  static const softPink = Color(0xFFF8ECEF);

  // ----------------------------------------------------------------- dark --

  /// The page background (the dark twin of [paper]).
  static const canvasDark = Color(0xFF14181A);

  /// Raised surfaces: the app bar, inputs.
  static const surfaceDark = Color(0xFF1B2022);

  /// Inset cards (the dark twin of [softAqua]).
  static const softCardDark = Color(0xFF1F2426);

  /// A provisional/warning panel (the dark twin of [softCoral]).
  static const softCoralDark = Color(0xFF3B2A24);

  /// Body and display text on dark. 14.72:1 on the canvas, 12.92:1 on a card.
  static const inkLight = Color(0xFFEDE8E7);

  /// Secondary text on dark. 7.93:1 on the canvas, 6.96:1 on a card.
  static const mutedDark = Color(0xFFB3ABA9);

  /// The accent once [teal] is too dark to read on a dark canvas: 7.48:1
  /// there, 6.57:1 on a card. [teal] itself stays the action *fill*.
  static const tealDark = Color(0xFF4FB8AD);

  /// Errors on dark: #B10E1E is only 2.51:1 against the dark canvas.
  static const errorDark = Color(0xFFFF9C9C);

  static const borderDark = Color(0xFF3A4143);

  // ------------------------------------------------- per-brightness tokens --

  // The component themes cover most of the design system. These are for the
  // handful of elements screens style by hand, so dark mode does not depend on
  // every screen re-deciding what "muted" means.

  /// Text (body, headings, icons) on the page.
  static Color inkFor(Brightness brightness) =>
      brightness == Brightness.dark ? inkLight : ink;

  /// Secondary text on the page.
  static Color mutedFor(Brightness brightness) =>
      brightness == Brightness.dark ? mutedDark : muted;

  /// The accent where it is read as text or as a border, not as a fill.
  static Color accentFor(Brightness brightness) =>
      brightness == Brightness.dark ? tealDark : teal;

  /// The fill of an inset card.
  static Color softCardFor(Brightness brightness) =>
      brightness == Brightness.dark ? softCardDark : softAqua;

  /// The fill of a provisional/warning panel.
  static Color softWarnFor(Brightness brightness) =>
      brightness == Brightness.dark ? softCoralDark : softCoral;

  /// Error text and error icons.
  static Color errorFor(Brightness brightness) =>
      brightness == Brightness.dark ? errorDark : error;

  /// Hairlines and dividers.
  static Color hairlineFor(Brightness brightness) =>
      brightness == Brightness.dark ? borderDark : borderSoft;
}

/// The whenisbins design system as Flutter [ThemeData].
///
/// [light] and [dark] are built from the same component themes with different
/// tokens, so the two can never drift apart structurally.
class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(
        brightness: Brightness.light,
        canvas: AppColors.paper,
        inputFill: AppColors.white,
        ink: AppColors.ink,
        accent: AppColors.teal,
        buttonFill: AppColors.teal,
        onButtonFill: AppColors.white,
        stroke: AppColors.ink,
        error: AppColors.error,
        divider: AppColors.borderSoft,
      );

  static ThemeData get dark => _build(
        brightness: Brightness.dark,
        canvas: AppColors.canvasDark,
        inputFill: AppColors.surfaceDark,
        ink: AppColors.inkLight,
        accent: AppColors.tealDark,
        // The action fill keeps the brand teal in both themes: white on it is
        // 5.48:1, and it stands 3.26:1 off the dark canvas.
        buttonFill: AppColors.teal,
        onButtonFill: AppColors.white,
        stroke: AppColors.inkLight,
        error: AppColors.errorDark,
        divider: AppColors.borderDark,
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color canvas,
    required Color inputFill,
    required Color ink,
    required Color accent,
    required Color buttonFill,
    required Color onButtonFill,
    required Color stroke,
    required Color error,
    required Color divider,
  }) {
    final isDark = brightness == Brightness.dark;
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.teal,
        brightness: brightness,
        primary: accent,
        surface: canvas,
        error: error,
      ),
      scaffoldBackgroundColor: canvas,
      fontFamily: 'LexendDeca',
    );

    return base.copyWith(
      textTheme: base.textTheme
          .apply(
            bodyColor: ink,
            displayColor: ink,
          )
          .copyWith(
            headlineLarge: TextStyle(
              fontSize: 40,
              height: 1.05,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: ink,
            ),
            headlineMedium: TextStyle(
              fontSize: 28,
              height: 1.15,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
            titleLarge: TextStyle(
              fontSize: 24,
              height: 1.25,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
            bodyLarge: TextStyle(
              fontSize: 19,
              height: 1.5,
              color: ink,
            ),
            bodyMedium: TextStyle(
              fontSize: 16,
              height: 1.5,
              color: ink,
            ),
            labelLarge: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: onButtonFill,
            ),
          ),
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.ink,
        foregroundColor: isDark ? AppColors.inkLight : AppColors.paper,
        elevation: 0,
        centerTitle: false,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: buttonFill,
          foregroundColor: onButtonFill,
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
          foregroundColor: ink,
          side: BorderSide(color: stroke, width: 2),
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
        fillColor: inputFill,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: stroke, width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: stroke, width: 2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: stroke, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: error, width: 3),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: error, width: 3),
        ),
        labelStyle: TextStyle(
          color: ink,
          fontWeight: FontWeight.w700,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: divider,
        thickness: 1,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
      ),
    );
  }
}
