import 'package:campus_app/widgets/glass_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression guard for the GlassAppBar scroll material.
///
/// `GlassAppBar` used to wrap its toolbar in a `NotificationListener<
/// ScrollNotification>`. Every page passes it to `Scaffold(appBar:)`, which
/// makes it a *sibling* of `body` — the body's scroll notifications bubble up
/// through Scaffold and never traverse the appBar's own subtree. So `_scrolled`
/// stayed false forever: blur sigma pinned at 0 and the background pinned at
/// transparent, on all 15 pages that use it.
/// Opacity of the glass material layer.
///
/// The blur filter is now constant (a composed refraction + blur, matching
/// GlassSurface); what animates with scroll is the material's opacity. So the
/// "is the glass active" question is answered here, not by reading sigma.
double _materialOpacity(WidgetTester tester) {
  final opacity = tester.widget<AnimatedOpacity>(
    find.descendant(
      of: find.byType(GlassAppBar),
      matching: find.byType(AnimatedOpacity),
    ),
  );
  return opacity.opacity;
}

Widget _harness({ScrollController? controller}) {
  return MaterialApp(
    home: Scaffold(
      appBar: const GlassAppBar(title: Text('课表')),
      body: ListView.builder(
        controller: controller,
        itemCount: 60,
        itemBuilder: (_, index) =>
            SizedBox(height: 60, child: Text('row $index')),
      ),
    ),
  );
}

void main() {
  group('GlassAppBar scroll material', () {
    testWidgets('is inert at rest', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      expect(_materialOpacity(tester), 0.0);
    });

    testWidgets('activates when the Scaffold body scrolls', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();

      expect(
        _materialOpacity(tester),
        1.0,
        reason: 'the glass material must engage once content scrolls under it',
      );
    });

    testWidgets('deactivates when scrolled back to the top', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_harness(controller: controller));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(_materialOpacity(tester), 1.0);

      controller.jumpTo(0);
      await tester.pumpAndSettle();

      expect(
        _materialOpacity(tester),
        0.0,
        reason: 'returning to offset 0 must clear the material again',
      );
    });

    testWidgets('never blurs the toolbar content itself', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();

      // BackdropFilter blurs everything already painted beneath it, so the
      // AppBar must sit OUTSIDE the filter's subtree. When it was inside, the
      // page title, the action icons and the status-bar area were all blurred
      // along with the scrolling content — titles rendered visibly smeared.
      expect(
        find.descendant(
          of: find.byType(BackdropFilter),
          matching: find.byType(AppBar),
        ),
        findsNothing,
        reason: 'the toolbar must not be a descendant of the BackdropFilter',
      );
      expect(
        find.descendant(
          of: find.byType(BackdropFilter),
          matching: find.text('课表'),
        ),
        findsNothing,
        reason: 'the title must never be inside the blur subtree',
      );
      // ...while the material itself is genuinely active.
      expect(_materialOpacity(tester), 1.0);
    });

    testWidgets('ignores horizontal scrollables such as the timetable grid', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: const GlassAppBar(title: Text('课表')),
            body: ListView(
              scrollDirection: Axis.horizontal,
              children: List.generate(
                40,
                (index) => SizedBox(width: 80, child: Text('day $index')),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView), const Offset(-400, 0));
      await tester.pumpAndSettle();

      expect(
        _materialOpacity(tester),
        0.0,
        reason: 'horizontal panning must not light up the toolbar',
      );
    });
  });
}
