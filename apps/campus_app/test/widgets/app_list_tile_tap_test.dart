import 'package:campus_app/widgets/app_list_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// AppListTile used to defer its callback:
///
/// ```dart
/// onTap: () {
///   setState(() => _isPressed = true);
///   Future.delayed(AppMotion.press, () {
///     if (mounted) { setState(() => _isPressed = false); widget.onTap!(); }
///   });
/// }
/// ```
///
/// That put 120ms in front of every navigation in the 服务 tab (this widget
/// backs all of its rows), and the `if (mounted)` guard silently swallowed the
/// tap whenever the widget was disposed inside the window — e.g. when the tap
/// itself replaced the surrounding page.
void main() {
  Widget harness(VoidCallback onTap) {
    return MaterialApp(
      home: Scaffold(
        body: AppListTile(
          icon: Icons.school,
          iconColor: Colors.blue,
          title: '成绩查询',
          onTap: onTap,
        ),
      ),
    );
  }

  testWidgets('fires the callback in the same frame as the tap', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(harness(() => taps++));

    await tester.tap(find.byType(AppListTile));
    // Deliberately no pumpAndSettle: a deferred callback would still be
    // sitting in a timer here.
    await tester.pump(Duration.zero);

    expect(taps, 1, reason: 'navigation must not wait for the press animation');
  });

  testWidgets('does not drop the tap when the tile unmounts immediately', (
    tester,
  ) async {
    var taps = 0;
    late StateSetter setOuter;
    var showTile = true;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              setOuter = setState;
              return showTile
                  ? AppListTile(
                      icon: Icons.school,
                      iconColor: Colors.blue,
                      title: '成绩查询',
                      onTap: () {
                        taps++;
                        // Simulate the tap replacing the surrounding content,
                        // which disposes this tile right away.
                        setOuter(() => showTile = false);
                      },
                    )
                  : const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byType(AppListTile));
    await tester.pumpAndSettle();

    expect(taps, 1);
    expect(find.byType(AppListTile), findsNothing);
  });

  testWidgets('still animates the press', (tester) async {
    await tester.pumpWidget(harness(() {}));

    double currentScale() =>
        tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;

    expect(currentScale(), 1.0);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(AppListTile)),
    );
    await tester.pump();
    expect(
      currentScale(),
      lessThan(1.0),
      reason: 'holding the row must still scale it down',
    );

    await gesture.up();
    await tester.pumpAndSettle();
    expect(currentScale(), 1.0);
  });
}
