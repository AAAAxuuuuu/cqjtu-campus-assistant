import 'dart:math' as math;

import 'package:campus_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Contrast guard for the brand palette.
///
/// The four brand colors all sat between 38–43% saturation with white-background
/// contrast of 3.91 / 3.26 / 2.17 / 1.96 — none of them reached the WCAG AA
/// body-text minimum of 4.5:1, which is why colored small text rendered washed
/// out. The palette now separates *fill* colors (blocks, gradients, button
/// bodies) from *ink* colors (text, small icons), and only the ink series is
/// allowed to carry text.
///
/// WCAG relative luminance, per
/// https://www.w3.org/TR/WCAG21/#dfn-relative-luminance
double _relativeLuminance(Color color) {
  double channel(double component) {
    return component <= 0.03928
        ? component / 12.92
        : math.pow((component + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

double _contrast(Color a, Color b) {
  final la = _relativeLuminance(a);
  final lb = _relativeLuminance(b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  const white = Color(0xFFFFFFFF);

  group('ink colors carry text at AA', () {
    const inks = <String, Color>{
      'primaryInk': AppColors.primaryInk,
      'secondaryInk': AppColors.secondaryInk,
      'accentInk': AppColors.accentInk,
    };

    inks.forEach((name, color) {
      test('$name reaches 4.5:1 on white', () {
        final ratio = _contrast(color, white);
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason:
              '$name is ${ratio.toStringAsFixed(2)}:1 — below WCAG AA for '
              'body text; text and small icons must stay legible',
        );
      });
    });

    test('body text colors also reach AA', () {
      for (final entry in <String, Color>{
        'textPrimary': AppColors.textPrimary,
        'textSecondary': AppColors.textSecondary,
        'textBody': AppColors.textBody,
      }.entries) {
        final ratio = _contrast(entry.value, white);
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: '${entry.key} is ${ratio.toStringAsFixed(2)}:1',
        );
      }
    });
  });

  group('ink colors stay on their fill hue', () {
    void expectSameFamily(String name, Color ink, Color fill) {
      final inkHue = HSLColor.fromColor(ink).hue;
      final fillHue = HSLColor.fromColor(fill).hue;
      final delta = (inkHue - fillHue).abs();
      final circular = math.min(delta, 360 - delta);
      expect(
        circular,
        lessThan(12),
        reason:
            '$name drifted ${circular.toStringAsFixed(1)}° from its fill '
            'color; the ink variant must read as the same brand color',
      );
    }

    test('each ink matches its fill', () {
      expectSameFamily('primaryInk', AppColors.primaryInk, AppColors.primary);
      expectSameFamily(
        'secondaryInk',
        AppColors.secondaryInk,
        AppColors.secondary,
      );
      expectSameFamily('accentInk', AppColors.accentInk, AppColors.accent);
    });

    test('each ink is darker than its fill', () {
      expect(
        _relativeLuminance(AppColors.primaryInk),
        lessThan(_relativeLuminance(AppColors.primary)),
      );
      expect(
        _relativeLuminance(AppColors.secondaryInk),
        lessThan(_relativeLuminance(AppColors.secondary)),
      );
      expect(
        _relativeLuminance(AppColors.accentInk),
        lessThan(_relativeLuminance(AppColors.accent)),
      );
    });
  });

  group('palette keeps a usable hierarchy', () {
    test('primary and secondary stay distinguishable', () {
      final primaryHue = HSLColor.fromColor(AppColors.primary).hue;
      final secondaryHue = HSLColor.fromColor(AppColors.secondary).hue;
      final delta = (primaryHue - secondaryHue).abs();
      final circular = math.min(delta, 360 - delta);
      expect(
        circular,
        greaterThan(60),
        reason: 'the two data-series colors must not be confusable in charts',
      );
    });

    test('tint is decorative only: too close to primary to carry meaning', () {
      // Documents *why* tint must never be used as a semantic color: it is
      // only ~16° from primary, so a chart using both is unreadable.
      final tintHue = HSLColor.fromColor(AppColors.tint).hue;
      final primaryHue = HSLColor.fromColor(AppColors.primary).hue;
      final delta = (tintHue - primaryHue).abs();
      expect(math.min(delta, 360 - delta), lessThan(30));
    });
  });
}
