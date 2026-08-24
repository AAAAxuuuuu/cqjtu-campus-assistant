import 'package:campus_app/theme/app_theme.dart';
import 'package:campus_app/widgets/responsive_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The main shell uses `extendBody: true` so page content scrolls *under* the
/// translucent navigation bar — without it there is nothing behind the glass to
/// refract and the translucency is pointless.
///
/// The cost is that every tab-level scrollable must reserve the bar's height
/// itself, otherwise its last item sits permanently under the bar. That
/// regressed every tab at once, so the clearance is now a token
/// ([AppInsets.navBarClearance]) applied through
/// [AppInsets.withNavBarClearance], and these tests pin the contract.
void main() {
  group('AppInsets.withNavBarClearance', () {
    test('adds the bar height to the bottom edge only', () {
      const base = EdgeInsets.fromLTRB(16, 8, 16, 24);
      final padded = AppInsets.withNavBarClearance(base);

      expect(padded.left, base.left);
      expect(padded.right, base.right);
      expect(padded.top, base.top);
      expect(padded.bottom, base.bottom + AppInsets.navBarClearance);
    });

    test('works from zero padding', () {
      final padded = AppInsets.withNavBarClearance(EdgeInsets.zero);
      expect(padded.bottom, AppInsets.navBarClearance);
    });

    test('clearance covers the floating capsule plus its gap', () {
      // The bar is a floating capsule: barHeight + bottomGap, plus breathing
      // room. Any less and the last row sits under it.
      expect(
        AppInsets.navBarClearance,
        greaterThanOrEqualTo(
          FloatingGlassNavBar.barHeight + FloatingGlassNavBar.bottomGap,
        ),
      );
    });
  });

  group('AppInsets.navBarClearanceOf', () {
    testWidgets('adds the system safe area on top of the capsule', (
      tester,
    ) async {
      const safeBottom = 34.0; // gesture-bar phones
      late double clearance;

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            viewPadding: EdgeInsets.only(bottom: safeBottom),
          ),
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                clearance = AppInsets.navBarClearanceOf(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(
        clearance,
        AppInsets.navBarClearance + safeBottom,
        reason:
            'the capsule floats above the safe area, so content must clear '
            'both — a fixed constant is short on gesture-bar phones',
      );
    });
  });

  testWidgets('reserved space actually keeps the last item clear', (
    tester,
  ) async {
    // 60 rows of 60px in a 800px viewport: the list must scroll well past the
    // bar, and the final row must come to rest above it.
    const barHeight = AppInsets.navBarClearance;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          extendBody: true,
          bottomNavigationBar: const SizedBox(
            height: barHeight,
            child: ColoredBox(color: Color(0x22000000)),
          ),
          body: ListView(
            padding: AppInsets.withNavBarClearance(EdgeInsets.zero),
            children: [
              for (var i = 0; i < 60; i++)
                SizedBox(height: 60, child: Text('row $i')),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Scroll to the very end.
    await tester.fling(find.byType(ListView), const Offset(0, -6000), 4000);
    await tester.pumpAndSettle();

    final viewportBottom = tester.getSize(find.byType(MaterialApp)).height;
    final lastRowBottom = tester.getBottomLeft(find.text('row 59')).dy;

    expect(
      lastRowBottom,
      lessThanOrEqualTo(viewportBottom - barHeight + 1),
      reason: 'the final row must rest above the navigation bar, not under it',
    );
  });
}
