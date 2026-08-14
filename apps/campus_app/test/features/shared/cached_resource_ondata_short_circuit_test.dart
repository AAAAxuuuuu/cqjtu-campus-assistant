import 'package:campus_app/features/auth/auth_providers.dart';
import 'package:campus_app/features/campus_card/campus_card_providers.dart';
import 'package:campus_app/features/electricity/electricity_providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const widgetChannel = MethodChannel('campus_app/schedule_widget');
  late List<MethodCall> widgetCalls;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    widgetCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(widgetChannel, (call) async {
          widgetCalls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(widgetChannel, null);
  });

  List<String?> pushedElectricity() => widgetCalls
      .where((call) => call.method == 'updateWidgetBalances')
      .map((call) => (call.arguments as Map)['electricityBalance'] as String?)
      .toList();

  List<String?> pushedCardBalance() => widgetCalls
      .where((call) => call.method == 'updateWidgetBalances')
      .map((call) => (call.arguments as Map)['campusCardBalance'] as String?)
      .toList();

  group('onData side-effect short circuit', () {
    test(
      'electricity pushes only on change after the first lifetime push',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        container.read(credentialsProvider.notifier).set('u', 'p');
        final notifier = container.read(electricityProvider.notifier);

        // First onData per notifier lifetime pushes even when unchanged
        // (covers re-login after widgets were cleared).
        await notifier.onData('999', changed: false);
        expect(pushedElectricity(), ['999']);

        // Identical data again: redundant, skipped.
        await notifier.onData('999', changed: false);
        expect(pushedElectricity(), ['999']);

        // Actual change: pushed.
        await notifier.onData('998', changed: true);
        expect(pushedElectricity(), ['999', '998']);

        // Unchanged again: skipped.
        await notifier.onData('998', changed: false);
        expect(pushedElectricity(), ['999', '998']);
      },
    );

    test(
      'campus card pushes only on change after the first lifetime push',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        container.read(credentialsProvider.notifier).set('u', 'p');
        final notifier = container.read(campusCardBalanceProvider.notifier);

        await notifier.onData('66.80', changed: false);
        expect(pushedCardBalance(), ['66.80']);

        await notifier.onData('66.80', changed: false);
        expect(pushedCardBalance(), ['66.80']);

        await notifier.onData('65.00', changed: true);
        expect(pushedCardBalance(), ['66.80', '65.00']);

        await notifier.onData('65.00', changed: false);
        expect(pushedCardBalance(), ['66.80', '65.00']);
      },
    );

    test('second notifier lifetime pushes again even when unchanged '
        '(widget may have been cleared between lifetimes)', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(credentialsProvider.notifier).set('u', 'p');
      final notifier = container.read(campusCardBalanceProvider.notifier);

      await notifier.onData('10.00', changed: false);
      expect(pushedCardBalance(), ['10.00']);

      await notifier.onData('10.00', changed: false);
      expect(pushedCardBalance(), ['10.00']);

      // A fresh notifier instance models the re-login / account-switch
      // rebuild: its first push must happen again.
      final container2 = ProviderContainer();
      addTearDown(container2.dispose);
      container2.read(credentialsProvider.notifier).set('u', 'p');
      final notifier2 = container2.read(campusCardBalanceProvider.notifier);

      await notifier2.onData('10.00', changed: false);
      expect(pushedCardBalance(), ['10.00', '10.00']);
    });
  });
}
