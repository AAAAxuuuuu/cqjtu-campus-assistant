import 'package:campus_app/main.dart' as app_main;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('awaitFirstFrame completes only after a frame is painted', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());

    var completed = false;
    app_main.awaitFirstFrame().then((_) => completed = true);

    expect(completed, isFalse, reason: 'no frame scheduled yet');

    // Schedule a real frame with dirty content so post-frame callbacks run.
    await tester.pumpWidget(const ColoredBox(color: Color(0xFF112233)));
    await tester.pump();

    expect(completed, isTrue);
  });
}
