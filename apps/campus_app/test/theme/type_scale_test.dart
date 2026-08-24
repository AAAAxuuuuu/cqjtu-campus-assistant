import 'package:campus_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// `AppType` was used 3 times against 262 inline `TextStyle(...)` calls, so the
/// five-step scale was effectively unused and font sizes were picked per call
/// site — a measured spread of 9 / 9.5 / 10 / 10.5 / 11 / 11.5 / 12 / 12.5 /
/// 13 / 14 / 14.5 / 15 / 16 / 17 / 18 / 19 / 20 / 22 / 24 / … / 72.
///
/// Consuming the scale exposed the gaps: 12 (56 uses), 13 (23), 11 (16) and 15
/// (12) were the top four, and only 12 had a token. `subtitle`, `label` and
/// `rowTitle` fill those in. These tests keep the ladder coherent so it stays
/// usable — an out-of-order or duplicated step pushes call sites back to
/// inline styles.
void main() {
  const ladder = <String, TextStyle>{
    'label': AppType.label,
    'caption': AppType.caption,
    'subtitle': AppType.subtitle,
    'body': AppType.body,
    'rowTitle': AppType.rowTitle,
    'sectionTitle': AppType.sectionTitle,
    'pageTitle': AppType.pageTitle,
    'metric': AppType.metric,
  };

  group('type scale', () {
    test('every step declares a size, weight and line height', () {
      ladder.forEach((name, style) {
        expect(style.fontSize, isNotNull, reason: '$name has no fontSize');
        expect(style.fontWeight, isNotNull, reason: '$name has no fontWeight');
        expect(style.height, isNotNull, reason: '$name has no height');
      });
    });

    test('sizes increase monotonically along the ladder', () {
      final entries = ladder.entries.toList();
      for (var i = 1; i < entries.length; i++) {
        expect(
          entries[i].value.fontSize,
          greaterThan(entries[i - 1].value.fontSize!),
          reason: '${entries[i].key} must be larger than ${entries[i - 1].key}',
        );
      }
    });

    test('no two steps share a size', () {
      final sizes = ladder.values.map((s) => s.fontSize).toList();
      expect(
        sizes.toSet().length,
        sizes.length,
        reason: 'duplicate steps make the ladder ambiguous to pick from',
      );
    });

    test('covers the four most common sizes in the codebase', () {
      // 12, 13, 11 and 15 were the top four measured inline sizes.
      final sizes = ladder.values.map((s) => s.fontSize).toSet();
      for (final size in [11.0, 12.0, 13.0, 15.0]) {
        expect(
          sizes,
          contains(size),
          reason:
              '${size.toInt()}px is a high-traffic size with no token, so '
              'call sites will keep writing it inline',
        );
      }
    });

    test('large steps use negative tracking, small steps do not', () {
      // Apple-style optical sizing: the bigger the type, the tighter it sets.
      expect(AppType.metric.letterSpacing, lessThan(0));
      expect(AppType.pageTitle.letterSpacing, lessThan(0));
      expect(AppType.sectionTitle.letterSpacing, lessThan(0));
      expect(AppType.caption.letterSpacing, greaterThanOrEqualTo(0));
      expect(AppType.label.letterSpacing, greaterThanOrEqualTo(0));
    });

    test('body copy sets looser than display type', () {
      expect(
        AppType.body.height,
        greaterThan(AppType.pageTitle.height!),
        reason: 'running text needs more leading than a headline',
      );
      expect(AppType.subtitle.height, greaterThan(AppType.metric.height!));
    });
  });
}
