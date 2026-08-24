import 'package:campus_app/widgets/responsive_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tab switches animate in with a direction-aware slide + fade.
///
/// The constraint is that the animation must NOT be built on
/// `AnimatedSwitcher`: tab pages have to stay mounted inside the `IndexedStack`
/// so scroll offsets and provider subscriptions survive. An earlier version of
/// this shell used AnimatedSwitcher and lost scroll position in 服务/我的 on
/// every switch, and re-fired CampusCardPage's initState refresh each time.
/// So these tests check the transition plays *and* that keep-alive still holds.
void main() {
  const destinations = [
    NavigationDestination(icon: Icon(Icons.calendar_today), label: '课表'),
    NavigationDestination(icon: Icon(Icons.credit_card), label: '校园卡'),
    NavigationDestination(icon: Icon(Icons.apps), label: '服务'),
    NavigationDestination(icon: Icon(Icons.person), label: '我的'),
  ];

  const railDestinations = [
    NavigationRailDestination(
      icon: Icon(Icons.calendar_today),
      label: Text('课表'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.credit_card),
      label: Text('校园卡'),
    ),
    NavigationRailDestination(icon: Icon(Icons.apps), label: Text('服务')),
    NavigationRailDestination(icon: Icon(Icons.person), label: Text('我的')),
  ];

  /// Reads the horizontal offset applied to the visible tab.
  double? slideOffsetOf(WidgetTester tester) {
    final transforms = tester.widgetList<Transform>(find.byType(Transform));
    for (final transform in transforms) {
      final dx = transform.transform.getTranslation().x;
      if (dx != 0) return dx;
    }
    return 0;
  }

  double? opacityOf(WidgetTester tester) {
    final opacities = tester.widgetList<Opacity>(find.byType(Opacity));
    for (final widget in opacities) {
      if (widget.opacity < 1.0) return widget.opacity;
    }
    return 1.0;
  }

  Widget harness({
    required int index,
    required ValueChanged<int> onTab,
    bool disableAnimations = false,
  }) {
    return MediaQuery(
      data: MediaQueryData(
        size: const Size(400, 800),
        disableAnimations: disableAnimations,
      ),
      child: MaterialApp(
        home: ResponsiveScaffold(
          currentIndex: index,
          onTabSelected: onTab,
          pages: const [
            Center(child: Text('page-0')),
            Center(child: Text('page-1')),
            Center(child: Text('page-2')),
            Center(child: Text('page-3')),
          ],
          destinations: destinations,
          railDestinations: railDestinations,
        ),
      ),
    );
  }

  testWidgets('slides in from the right when moving forward', (tester) async {
    var index = 0;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => harness(
          index: index,
          onTab: (next) => setState(() => index = next),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 我的 (3) -> forward from 课表 (0).
    await tester.tap(find.text('我的'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));

    expect(
      slideOffsetOf(tester),
      greaterThan(0),
      reason: 'moving to a higher index should enter from the right',
    );
  });

  testWidgets('slides in from the left when moving backward', (tester) async {
    var index = 3;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => harness(
          index: index,
          onTab: (next) => setState(() => index = next),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 校园卡 (1) <- backward from 我的 (3).
    await tester.tap(find.text('校园卡'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));

    expect(
      slideOffsetOf(tester),
      lessThan(0),
      reason: 'moving to a lower index should enter from the left',
    );
  });

  testWidgets('settles to no offset and full opacity', (tester) async {
    var index = 0;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => harness(
          index: index,
          onTab: (next) => setState(() => index = next),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('服务'));
    await tester.pumpAndSettle();

    expect(slideOffsetOf(tester), 0);
    expect(opacityOf(tester), 1.0);
  });

  testWidgets('fades in rather than flashing from fully transparent', (
    tester,
  ) async {
    var index = 0;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => harness(
          index: index,
          onTab: (next) => setState(() => index = next),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('校园卡'));
    await tester.pump();

    final opacity = opacityOf(tester)!;
    expect(
      opacity,
      greaterThan(0.3),
      reason: 'starting from 0 opacity reads as a flash, not a move-in',
    );
    expect(opacity, lessThan(1.0));
  });

  testWidgets('respects the reduce-motion setting', (tester) async {
    var index = 0;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => harness(
          index: index,
          onTab: (next) => setState(() => index = next),
          disableAnimations: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('我的'));
    await tester.pump();

    expect(
      slideOffsetOf(tester),
      0,
      reason: 'no movement when the system asks for reduced motion',
    );
  });

  testWidgets('keeps every tab mounted while animating', (tester) async {
    var index = 0;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => harness(
          index: index,
          onTab: (next) => setState(() => index = next),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('我的'));
    await tester.pump(const Duration(milliseconds: 40));

    // All four pages exist in the tree (IndexedStack + maintainState), even
    // mid-animation — this is what preserves scroll position.
    for (var i = 0; i < 4; i++) {
      expect(
        find.text('page-$i', skipOffstage: false),
        findsOneWidget,
        reason: 'page-$i must stay mounted across switches',
      );
    }
  });
}
