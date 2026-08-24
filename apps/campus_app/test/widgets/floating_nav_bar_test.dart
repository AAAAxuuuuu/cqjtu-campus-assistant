import 'package:campus_app/widgets/responsive_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The navigation bar used to live in `Scaffold.bottomNavigationBar`, which
/// forces full width and pins it to the screen edge — a solid rectangle across
/// the bottom. It is now a floating capsule positioned in a Stack, so it has
/// side margins, a bottom gap, and a fully rounded shape.
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

  Rect capsuleRect(WidgetTester tester) {
    // The capsule body is the fixed-height SizedBox inside the bar.
    return tester.getRect(
      find
          .descendant(
            of: find.byType(FloatingGlassNavBar),
            matching: find.byWidgetPredicate(
              (w) => w is SizedBox && w.height == FloatingGlassNavBar.barHeight,
            ),
          )
          .first,
    );
  }

  Widget harness({Size size = const Size(400, 800)}) {
    return MediaQuery(
      data: MediaQueryData(size: size),
      child: MaterialApp(
        home: ResponsiveScaffold(
          currentIndex: 0,
          onTabSelected: (_) {},
          pages: const [
            ColoredBox(color: Colors.red),
            ColoredBox(color: Colors.green),
            ColoredBox(color: Colors.blue),
            ColoredBox(color: Colors.yellow),
          ],
          destinations: destinations,
          railDestinations: railDestinations,
        ),
      ),
    );
  }

  testWidgets('floats with side margins instead of spanning full width', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    final bar = find.byType(FloatingGlassNavBar);
    expect(bar, findsOneWidget);

    // The capsule is the NavigationBar inside it; measure that, not the
    // padding wrapper.
    final navRect = capsuleRect(tester);
    final screenWidth = tester.getSize(find.byType(MaterialApp)).width;

    expect(
      navRect.left,
      greaterThanOrEqualTo(FloatingGlassNavBar.sideMargin - 0.5),
      reason: 'the capsule must not touch the left screen edge',
    );
    expect(
      screenWidth - navRect.right,
      greaterThanOrEqualTo(FloatingGlassNavBar.sideMargin - 0.5),
      reason: 'the capsule must not touch the right screen edge',
    );
    expect(
      navRect.width,
      lessThan(screenWidth),
      reason: 'a full-width bar is the old rectangular look',
    );
  });

  testWidgets('leaves a gap below the capsule', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    final navRect = capsuleRect(tester);
    final screenHeight = tester.getSize(find.byType(MaterialApp)).height;

    expect(
      screenHeight - navRect.bottom,
      greaterThanOrEqualTo(FloatingGlassNavBar.bottomGap - 0.5),
      reason: 'the capsule must sit above the screen edge, not on it',
    );
  });

  testWidgets('is fully rounded', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    // A pill radius is half the height; anything less reads as a rounded
    // rectangle rather than a capsule.
    final decorated = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(FloatingGlassNavBar),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    final decoration = decorated.decoration as BoxDecoration;
    final radius = decoration.borderRadius as BorderRadius;

    expect(radius.topLeft.x, FloatingGlassNavBar.barHeight / 2);
  });

  testWidgets(
    'content sits behind the capsule so glass has something to show',
    (tester) async {
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(
        scaffold.extendBody,
        isTrue,
        reason:
            'without extendBody there is nothing behind the glass to refract',
      );
      expect(
        scaffold.bottomNavigationBar,
        isNull,
        reason:
            'the bottomNavigationBar slot would force the old full-width bar',
      );
    },
  );

  testWidgets('wide screens use the rail and no capsule', (tester) async {
    await tester.pumpWidget(harness(size: const Size(900, 700)));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(FloatingGlassNavBar), findsNothing);
  });

  testWidgets('every destination is tappable', (tester) async {
    // Forcing NavigationBar to a height smaller than its intrinsic one pushed
    // the icons outside the capsule's layout bounds: they rendered below the
    // glass and stopped receiving hit tests entirely.
    final taps = <int>[];

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(400, 800)),
        child: MaterialApp(
          home: ResponsiveScaffold(
            currentIndex: 0,
            onTabSelected: taps.add,
            pages: const [
              ColoredBox(color: Colors.red),
              ColoredBox(color: Colors.green),
              ColoredBox(color: Colors.blue),
              ColoredBox(color: Colors.yellow),
            ],
            destinations: destinations,
            railDestinations: railDestinations,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final label in ['校园卡', '服务', '我的']) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    expect(taps, [1, 2, 3], reason: 'each destination must dispatch its index');
  });

  testWidgets('labels keep real height on a gesture-bar phone', (tester) async {
    // The failure that shipped: barHeight was 64 while NavigationBar's
    // intrinsic height is 80, so its labels collapsed to zero height and the
    // icons overflowed past the capsule — the bar rendered half-drawn and the
    // hit targets landed outside its bounds.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.7;
    tester.view.viewPadding = const FakeViewPadding(bottom: 92, top: 100);
    tester.view.padding = const FakeViewPadding(bottom: 92, top: 100);
    addTearDown(tester.view.reset);

    final taps = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: ResponsiveScaffold(
          currentIndex: 0,
          onTabSelected: taps.add,
          pages: const [
            ColoredBox(color: Colors.red),
            ColoredBox(color: Colors.green),
            ColoredBox(color: Colors.blue),
            ColoredBox(color: Colors.yellow),
          ],
          destinations: destinations,
          railDestinations: railDestinations,
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final label in ['课表', '校园卡', '服务', '我的']) {
      final rect = tester.getRect(find.text(label));
      expect(
        rect.height,
        greaterThan(4),
        reason:
            '"$label" collapsed to ${rect.height}px — the capsule is '
            'shorter than NavigationBar needs',
      );
    }

    // And the icons must still dispatch.
    await tester.tapAt(tester.getCenter(find.byIcon(Icons.apps)));
    await tester.pumpAndSettle();
    expect(taps, [2]);
  });

  testWidgets('content is vertically centred in the capsule', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    final capsule = capsuleRect(tester);

    for (final label in ['课表', '校园卡', '服务', '我的']) {
      final column = find.ancestor(
        of: find.text(label),
        matching: find.byType(Column),
      );
      final iconRect = tester.getRect(
        find.descendant(of: column, matching: find.byType(Icon)).first,
      );
      final labelRect = tester.getRect(find.text(label));

      // Space above the icon vs below the label must match, or the content
      // reads as sitting too high — which is what shipped.
      final above = iconRect.top - capsule.top;
      final below = capsule.bottom - labelRect.bottom;
      expect(
        (above - below).abs(),
        lessThan(8.0),
        reason:
            '"$label" is off-centre: ${above.toStringAsFixed(1)}px above '
            'vs ${below.toStringAsFixed(1)}px below',
      );
    }
  });

  test('capsule is slim', () {
    // Material's NavigationBar forces 80px; hand-rolling the row was what
    // made a slimmer capsule possible at all.
    expect(FloatingGlassNavBar.barHeight, lessThan(72));
  });

  testWidgets('capsule fully contains the navigation content', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    final capsule = capsuleRect(tester);

    // Icons and labels must sit inside the glass, not spill past its bottom.
    for (final label in ['课表', '校园卡', '服务', '我的']) {
      final labelRect = tester.getRect(find.text(label));
      expect(
        labelRect.bottom,
        lessThanOrEqualTo(capsule.bottom + 0.5),
        reason: '"$label" overflows the capsule bottom edge',
      );
      expect(
        labelRect.top,
        greaterThanOrEqualTo(capsule.top - 0.5),
        reason: '"$label" overflows the capsule top edge',
      );
    }
  });
}
