import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:when_is_bin_app/core/theme.dart';

/// WCAG 2.x relative luminance, so a token pair can be asserted rather than
/// eyeballed on a screenshot.
double _luminance(Color color) {
  double channel(double value) => value <= 0.03928
      ? value / 12.92
      : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

double _contrast(Color a, Color b) {
  final first = _luminance(a);
  final second = _luminance(b);
  return (math.max(first, second) + 0.05) / (math.min(first, second) + 0.05);
}

void main() {
  final light = AppTheme.light;
  final dark = AppTheme.dark;

  group('AppTheme.dark', () {
    test('is a dark theme built from the dark tokens', () {
      expect(dark.brightness, Brightness.dark);
      expect(dark.colorScheme.brightness, Brightness.dark);
      expect(dark.scaffoldBackgroundColor, AppColors.canvasDark);
      expect(dark.appBarTheme.backgroundColor, AppColors.surfaceDark);
      expect(dark.appBarTheme.foregroundColor, AppColors.inkLight);
      expect(dark.textTheme.bodyMedium?.color, AppColors.inkLight);
      expect(dark.textTheme.headlineLarge?.color, AppColors.inkLight);
      expect(dark.textTheme.labelLarge?.color, AppColors.white);
    });

    test('mirrors the light design system', () {
      expect(
        dark.textTheme.headlineLarge?.fontSize,
        light.textTheme.headlineLarge?.fontSize,
      );
      expect(
        dark.textTheme.titleLarge?.fontSize,
        light.textTheme.titleLarge?.fontSize,
      );
      expect(
        dark.textTheme.bodyMedium?.fontSize,
        light.textTheme.bodyMedium?.fontSize,
      );
      expect(
        dark.textTheme.bodyMedium?.height,
        light.textTheme.bodyMedium?.height,
      );
      expect(
        dark.textTheme.bodyMedium?.fontFamily,
        light.textTheme.bodyMedium?.fontFamily,
      );
    });

    test('uses tokens that differ from the light ones', () {
      expect(AppColors.canvasDark, isNot(AppColors.paper));
      expect(AppColors.inkLight, isNot(AppColors.ink));
      expect(AppColors.mutedDark, isNot(AppColors.muted));
      expect(AppColors.tealDark, isNot(AppColors.teal));
      expect(
        dark.scaffoldBackgroundColor,
        isNot(light.scaffoldBackgroundColor),
      );
      expect(
        dark.textTheme.bodyMedium?.color,
        isNot(light.textTheme.bodyMedium?.color),
      );
    });
  });

  group('WCAG contrast', () {
    void expectAtLeast(double min, Color fg, Color bg, String label) {
      final ratio = _contrast(fg, bg);
      expect(
        ratio,
        greaterThanOrEqualTo(min),
        reason: '$label is ${ratio.toStringAsFixed(2)}:1, needs $min:1',
      );
    }

    group('light', () {
      test('body and secondary text on the page and on cards', () {
        expectAtLeast(4.5, AppColors.ink, AppColors.paper, 'ink on paper');
        expectAtLeast(4.5, AppColors.ink, AppColors.white, 'ink on white');
        expectAtLeast(4.5, AppColors.ink, AppColors.softAqua, 'ink on card');
        // Secondary text is 16px body, so it needs the full 4.5 — and clears
        // 7 comfortably, not barely.
        expectAtLeast(7, AppColors.muted, AppColors.paper, 'muted on paper');
        expectAtLeast(7, AppColors.muted, AppColors.white, 'muted on white');
        expectAtLeast(7, AppColors.muted, AppColors.softAqua, 'muted on card');
      });

      test('text on the teal action colour', () {
        expectAtLeast(4.5, AppColors.white, AppColors.teal, 'white on teal');
        expectAtLeast(4.5, AppColors.teal, AppColors.paper, 'teal on paper');
        expectAtLeast(4.5, AppColors.teal, AppColors.white, 'teal on white');
        expectAtLeast(4.5, AppColors.teal, AppColors.softAqua, 'teal on card');
      });

      test('error and link text', () {
        expectAtLeast(4.5, AppColors.error, AppColors.paper, 'error on paper');
        expectAtLeast(4.5, AppColors.error, AppColors.white, 'error on white');
        expectAtLeast(4.5, AppColors.link, AppColors.paper, 'link on paper');
      });

      test('fills and borders stand off the canvas', () {
        expectAtLeast(3, AppColors.ink, AppColors.paper, 'ink border');
        expectAtLeast(3, AppColors.teal, AppColors.paper, 'teal button');
        expectAtLeast(3, AppColors.teal, AppColors.softAqua, 'teal card border');
      });
    });

    group('dark', () {
      test('body and secondary text on the canvas and on cards', () {
        expectAtLeast(
          4.5,
          AppColors.inkLight,
          AppColors.canvasDark,
          'inkLight on canvas',
        );
        expectAtLeast(
          4.5,
          AppColors.inkLight,
          AppColors.surfaceDark,
          'inkLight on surface',
        );
        expectAtLeast(
          4.5,
          AppColors.inkLight,
          AppColors.softCardDark,
          'inkLight on card',
        );
        expectAtLeast(
          4.5,
          AppColors.mutedDark,
          AppColors.canvasDark,
          'mutedDark on canvas',
        );
        expectAtLeast(
          4.5,
          AppColors.mutedDark,
          AppColors.softCardDark,
          'mutedDark on card',
        );
      });

      test('accent and error text on the dark surfaces', () {
        expectAtLeast(
          4.5,
          AppColors.tealDark,
          AppColors.canvasDark,
          'tealDark on canvas',
        );
        expectAtLeast(
          4.5,
          AppColors.tealDark,
          AppColors.softCardDark,
          'tealDark on card',
        );
        expectAtLeast(
          4.5,
          AppColors.errorDark,
          AppColors.canvasDark,
          'errorDark on canvas',
        );
        expectAtLeast(
          4.5,
          AppColors.inkLight,
          AppColors.softCoralDark,
          'inkLight on the provisional panel',
        );
        expectAtLeast(4.5, AppColors.white, AppColors.teal, 'white on teal');
      });

      test('fills and borders stand off the dark canvas', () {
        expectAtLeast(
          3,
          AppColors.teal,
          AppColors.canvasDark,
          'teal button on canvas',
        );
        expectAtLeast(
          3,
          AppColors.tealDark,
          AppColors.canvasDark,
          'teal accent on canvas',
        );
        expectAtLeast(
          3,
          AppColors.tealDark,
          AppColors.softCardDark,
          'teal accent on card',
        );
        expectAtLeast(
          3,
          AppColors.inkLight,
          AppColors.canvasDark,
          'outlined button stroke',
        );
      });
    });
  });
}
