import 'dart:convert';

import 'package:campus_app/features/auth/auth_providers.dart';
import 'package:campus_app/features/schedule/schedule_providers.dart';
import 'package:campus_app/features/settings/settings_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('Milestone 4 Challenger 1 - Campus App Account Cache & Boundary Isolation Tests', () {
    test('Boundary Isolation Defect Test: user vs user_1 preference preservation', () async {
      SharedPreferences.setMockInitialValues({
        'user_user_schedule_sunday_first': true,
        'user_user_1_schedule_sunday_first': true,
        'user_user_1_dorm_campus': '南岸校区',
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Execute clearCurrentAccountCache for 'user'
      await clearCurrentAccountCache(container, 'user');

      final prefs = await SharedPreferences.getInstance();

      // Account 'user' key should be cleared
      expect(prefs.containsKey('user_user_schedule_sunday_first'), isFalse);

      // Account 'user_1' keys MUST NOT be deleted
      expect(prefs.containsKey('user_user_1_schedule_sunday_first'), isTrue,
          reason: 'DEFECT: clearCurrentAccountCache("user") inadvertently deleted user_1 schedule_sunday_first preference');
      expect(prefs.containsKey('user_user_1_dorm_campus'), isTrue,
          reason: 'DEFECT: clearCurrentAccountCache("user") inadvertently deleted user_1 dorm_campus preference');
    });

    test('Boundary Isolation Defect Test: test vs test_user preference preservation', () async {
      SharedPreferences.setMockInitialValues({
        'user_test_schedule_sunday_first': true,
        'user_test_user_schedule_sunday_first': true,
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await clearCurrentAccountCache(container, 'test');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('user_test_schedule_sunday_first'), isFalse);
      expect(prefs.containsKey('user_test_user_schedule_sunday_first'), isTrue,
          reason: 'DEFECT: clearCurrentAccountCache("test") inadvertently deleted test_user preference');
    });

    test('Boundary Isolation Pass Test: abc vs abcd preference preservation', () async {
      SharedPreferences.setMockInitialValues({
        'user_abc_schedule_sunday_first': true,
        'user_abcd_schedule_sunday_first': true,
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await clearCurrentAccountCache(container, 'abc');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('user_abc_schedule_sunday_first'), isFalse);
      expect(prefs.containsKey('user_abcd_schedule_sunday_first'), isTrue);
    });

    test('Exact Account Key Isolation: exact account key user_user_1 remains intact after clearCurrentAccountCache(user)', () async {
      SharedPreferences.setMockInitialValues({
        'user_user': 'state_user',
        'user_user_1': 'state_user_1',
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await clearCurrentAccountCache(container, 'user');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('user_user'), isFalse);
      expect(prefs.containsKey('user_user_1'), isTrue,
          reason: 'Exact account key user_user_1 MUST remain intact after clearCurrentAccountCache("user")');
    });

    test('Exact Account Key Isolation: exact account key user_test_user remains intact after clearCurrentAccountCache(test)', () async {
      SharedPreferences.setMockInitialValues({
        'user_test': 'state_test',
        'user_test_user': 'state_test_user',
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await clearCurrentAccountCache(container, 'test');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('user_test'), isFalse);
      expect(prefs.containsKey('user_test_user'), isTrue,
          reason: 'Exact account key user_test_user MUST remain intact after clearCurrentAccountCache("test")');
    });

    test('One-click account cache clearing for single and multiple account sessions', () async {
      final userAB64 = base64Url.encode(utf8.encode('userA'));
      final userBB64 = base64Url.encode(utf8.encode('userB'));

      SharedPreferences.setMockInitialValues({
        'resource_cache_v1:schedule:$userAB64:default': '{"courses":[]}',
        'user_userA_schedule_sunday_first': true,
        'resource_cache_v1:schedule:$userBB64:default': '{"courses":[]}',
        'user_userB_schedule_sunday_first': true,
        'app_theme_mode': 'dark',
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Clear userA
      await clearCurrentAccountCache(container, 'userA');

      final prefs = await SharedPreferences.getInstance();

      expect(prefs.containsKey('resource_cache_v1:schedule:$userAB64:default'), isFalse);
      expect(prefs.containsKey('user_userA_schedule_sunday_first'), isFalse);

      expect(prefs.containsKey('resource_cache_v1:schedule:$userBB64:default'), isTrue);
      expect(prefs.containsKey('user_userB_schedule_sunday_first'), isTrue);
      expect(prefs.getString('app_theme_mode'), 'dark');
    });

    test('Preference persistence & restoration after cache clear operations', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Login as userA
      container.read(credentialsProvider.notifier).set('userA', 'password123');

      // Set sundayFirst preference to true
      await container.read(scheduleSundayFirstProvider.notifier).setSundayFirst(true);

      final prefs1 = await SharedPreferences.getInstance();
      expect(prefs1.getBool('user_userA_schedule_sunday_first'), isTrue);

      // Clear cache for userA
      await clearCurrentAccountCache(container, 'userA');

      final prefs2 = await SharedPreferences.getInstance();
      expect(prefs2.containsKey('user_userA_schedule_sunday_first'), isFalse);

      // Post-clear: reading provider returns default (false)
      final postClearValue = await container.read(scheduleSundayFirstProvider.future);
      expect(postClearValue, isFalse);

      // Restore/Set new preference after cache clear
      await container.read(scheduleSundayFirstProvider.notifier).setSundayFirst(true);

      final prefs3 = await SharedPreferences.getInstance();
      expect(prefs3.getBool('user_userA_schedule_sunday_first'), isTrue);
      final restoredValue = await container.read(scheduleSundayFirstProvider.future);
      expect(restoredValue, isTrue);
    });
  });
}
