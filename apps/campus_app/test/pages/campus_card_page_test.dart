import 'package:campus_app/pages/campus_card_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('recharge action opens the secondary recharge page', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: CampusCardPage())),
    );
    await tester.pump();

    expect(find.widgetWithText(FilledButton, '充值'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '充值'));
    await tester.pumpAndSettle();

    expect(find.text('校园卡充值（支付宝）'), findsOneWidget);
    expect(find.text('跳转支付宝充值'), findsOneWidget);
  });
}
