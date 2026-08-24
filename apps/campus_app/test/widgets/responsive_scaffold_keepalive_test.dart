import 'package:campus_app/widgets/responsive_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shell used to swap tabs with `AnimatedSwitcher` over
/// `KeyedSubtree(key: ValueKey(currentIndex))`. That gave each tab a new key on
/// every switch, so Flutter disposed the outgoing element tree and rebuilt the
/// incoming one from scratch: scroll offsets were lost and `initState` side
/// effects (e.g. CampusCardPage's auto-refresh) re-fired on every visit.
class _CountingTab extends StatefulWidget {
  const _CountingTab({required this.label, required this.initCounts});

  final String label;
  final Map<String, int> initCounts;

  @override
  State<_CountingTab> createState() => _CountingTabState();
}

class _CountingTabState extends State<_CountingTab> {
  @override
  void initState() {
    super.initState();
    widget.initCounts.update(
      widget.label,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: 80,
      itemBuilder: (_, index) =>
          SizedBox(height: 50, child: Text('${widget.label}-$index')),
    );
  }
}

void main() {
  Widget harness({
    required int index,
    required ValueChanged<int> onTab,
    required Map<String, int> initCounts,
  }) {
    return MaterialApp(
      home: ResponsiveScaffold(
        currentIndex: index,
        onTabSelected: onTab,
        pages: [
          _CountingTab(label: 'a', initCounts: initCounts),
          _CountingTab(label: 'b', initCounts: initCounts),
        ],
        destinations: const [
          NavigationDestination(icon: Icon(Icons.schedule), label: 'A'),
          NavigationDestination(icon: Icon(Icons.person), label: 'B'),
        ],
        railDestinations: const [
          NavigationRailDestination(
            icon: Icon(Icons.schedule),
            label: Text('A'),
          ),
          NavigationRailDestination(icon: Icon(Icons.person), label: Text('B')),
        ],
      ),
    );
  }

  testWidgets('tab pages are built once, not on every switch', (tester) async {
    final initCounts = <String, int>{};
    var index = 0;

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => harness(
          index: index,
          onTab: (next) => setState(() => index = next),
          initCounts: initCounts,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(initCounts['a'], 1);
    expect(
      initCounts['b'],
      1,
      reason: 'IndexedStack mounts every tab up front',
    );

    // Switch back and forth several times.
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('B'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A'));
      await tester.pumpAndSettle();
    }

    expect(
      initCounts['a'],
      1,
      reason: 'tab A must not be re-created when revisited',
    );
    expect(
      initCounts['b'],
      1,
      reason: 'tab B must not be re-created when revisited',
    );
  });

  testWidgets('scroll offset survives a tab round trip', (tester) async {
    final initCounts = <String, int>{};
    var index = 0;

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => harness(
          index: index,
          onTab: (next) => setState(() => index = next),
          initCounts: initCounts,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final firstTab = find.byType(ListView).first;
    await tester.drag(firstTab, const Offset(0, -600));
    await tester.pumpAndSettle();

    final offsetBefore = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .pixels;
    expect(offsetBefore, greaterThan(0));

    await tester.tap(find.text('B'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A'));
    await tester.pumpAndSettle();

    final offsetAfter = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .pixels;

    expect(
      offsetAfter,
      offsetBefore,
      reason: 'returning to a tab must restore its scroll position',
    );
  });

  testWidgets('only the selected tab is visible', (tester) async {
    final initCounts = <String, int>{};

    await tester.pumpWidget(
      harness(index: 0, onTab: (_) {}, initCounts: initCounts),
    );
    await tester.pumpAndSettle();

    expect(find.text('a-0'), findsOneWidget);
    expect(
      find.text('b-0'),
      findsNothing,
      reason: 'the offstage tab stays mounted but must not paint',
    );
  });
}
