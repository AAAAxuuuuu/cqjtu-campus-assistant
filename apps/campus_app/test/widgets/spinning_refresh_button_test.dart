import 'package:campus_app/widgets/spinning_refresh_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('shows check icon after a successful refresh', (tester) async {
    await tester.pumpWidget(
      _wrap(SpinningRefreshButton(onPressed: () async {})),
    );

    await tester.tap(find.byType(IconButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1300));
    expect(find.byIcon(Icons.refresh), findsOneWidget);
  });

  testWidgets('shows error icon after a failed refresh', (tester) async {
    await tester.pumpWidget(
      _wrap(
        SpinningRefreshButton(
          onPressed: () async {
            throw StateError('refresh failed');
          },
        ),
      ),
    );

    await tester.tap(find.byType(IconButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byIcon(Icons.error_outline), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1300));
    expect(find.byIcon(Icons.refresh), findsOneWidget);
  });

  testWidgets('disabled button does not animate', (tester) async {
    await tester.pumpWidget(
      _wrap(const SpinningRefreshButton(onPressed: null)),
    );
    expect(find.byIcon(Icons.refresh), findsOneWidget);
    await tester.tap(find.byType(IconButton), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byIcon(Icons.refresh), findsOneWidget);
  });
}
