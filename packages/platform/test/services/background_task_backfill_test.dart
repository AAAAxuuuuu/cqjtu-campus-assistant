import 'dart:convert';

import 'package:campus_platform/services/background_task.dart';
import 'package:core/utils/resource_cache_key.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('backfills balances into the foreground cache format', () async {
    await backfillBalanceCaches(
      prefs: await SharedPreferences.getInstance(),
      username: 'u123',
      elecBalance: '12.30',
      cardBalance: '66.80',
      dormParams: {'buildid': 'B1', 'roomid': '101'},
    );

    final prefs = await SharedPreferences.getInstance();

    final elecKey = resourceCacheKey(
      'electricity_balance',
      username: 'u123',
      scope: 'B1:101',
    );
    final elecRaw = jsonDecode(prefs.getString(elecKey)!);
    expect((elecRaw as Map)['data'], '12.30');
    expect(elecRaw['updatedAtMs'], isA<int>());

    final cardKey = resourceCacheKey(
      'campus_card_balance',
      username: 'u123',
      scope: null,
    );
    final cardRaw = jsonDecode(prefs.getString(cardKey)!);
    expect((cardRaw as Map)['data'], '66.80');

    expect(prefs.getInt('bg_elec_checked_at_ms'), isNotNull);
    expect(prefs.getInt('bg_card_checked_at_ms'), isNotNull);
  });

  test('skips absent balances and missing dorm parameters', () async {
    await backfillBalanceCaches(
      prefs: await SharedPreferences.getInstance(),
      username: 'u123',
      elecBalance: null,
      cardBalance: null,
      dormParams: null,
    );

    final prefs = await SharedPreferences.getInstance();
    expect(
        prefs.getKeys().where((k) => k.contains('resource_cache_v1')), isEmpty);
    expect(prefs.getInt('bg_elec_checked_at_ms'), isNull);
    expect(prefs.getInt('bg_card_checked_at_ms'), isNull);
  });

  test('electricity cache requires dorm params', () async {
    await backfillBalanceCaches(
      prefs: await SharedPreferences.getInstance(),
      username: 'u123',
      elecBalance: '12.30',
      cardBalance: '66.80',
      dormParams: null,
    );

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getKeys().where((k) => k.contains('electricity_balance')),
      isEmpty,
    );
    final cardKey = resourceCacheKey(
      'campus_card_balance',
      username: 'u123',
      scope: null,
    );
    expect(prefs.getString(cardKey), isNotNull);
  });
}
