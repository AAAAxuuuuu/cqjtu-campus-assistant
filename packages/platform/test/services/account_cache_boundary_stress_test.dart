import 'dart:convert';

import 'package:campus_platform/services/account_cache_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group(
      'Challenger 1 - AccountCacheService Boundary Isolation & Clearing Stress Tests',
      () {
    test(
        'Prefix Boundary Isolation: user vs user_1 when user_1 has preference keys only (no resource_cache_v1)',
        () async {
      final userAB64 = base64Url.encode(utf8.encode('user'));

      SharedPreferences.setMockInitialValues({
        // Account 'user' cache and preferences
        'resource_cache_v1:schedule:$userAB64:default': '{"courses":["Math"]}',
        'user_user_schedule_sunday_first': true,
        'user_user_dorm_campus': '科学城校区',

        // Account 'user_1' preferences (NO resource_cache_v1 key)
        'user_user_1_schedule_sunday_first': true,
        'user_user_1_dorm_campus': '南岸校区',
      });

      final service = AccountCacheService();
      final prefs = await SharedPreferences.getInstance();

      // Clear account cache for 'user'
      await service.clearAccountCache('user', accountId: 'user', prefs: prefs);

      // Verify 'user' keys are removed
      expect(prefs.containsKey('resource_cache_v1:schedule:$userAB64:default'),
          isFalse,
          reason: "'user' resource cache must be cleared");
      expect(prefs.containsKey('user_user_schedule_sunday_first'), isFalse,
          reason: "'user' sunday_first pref must be cleared");
      expect(prefs.containsKey('user_user_dorm_campus'), isFalse,
          reason: "'user' dorm pref must be cleared");

      // Verify 'user_1' preference keys remain INTACT (Boundary Isolation)
      expect(prefs.containsKey('user_user_1_schedule_sunday_first'), isTrue,
          reason:
              "'user_1' sunday_first pref MUST NOT be deleted when clearing 'user'");
      expect(prefs.containsKey('user_user_1_dorm_campus'), isTrue,
          reason:
              "'user_1' dorm pref MUST NOT be deleted when clearing 'user'");
    });

    test(
        'Prefix Boundary Isolation: user vs user_1 when both have resource_cache_v1 keys',
        () async {
      final userAB64 = base64Url.encode(utf8.encode('user'));
      final user1B64 = base64Url.encode(utf8.encode('user_1'));

      SharedPreferences.setMockInitialValues({
        'resource_cache_v1:schedule:$userAB64:default': '{"courses":["Math"]}',
        'user_user_schedule_sunday_first': true,
        'resource_cache_v1:schedule:$user1B64:default':
            '{"courses":["English"]}',
        'user_user_1_schedule_sunday_first': false,
      });

      final service = AccountCacheService();
      final prefs = await SharedPreferences.getInstance();

      await service.clearAccountCache('user', accountId: 'user', prefs: prefs);

      expect(prefs.containsKey('resource_cache_v1:schedule:$userAB64:default'),
          isFalse);
      expect(prefs.containsKey('user_user_schedule_sunday_first'), isFalse);

      expect(prefs.containsKey('resource_cache_v1:schedule:$user1B64:default'),
          isTrue);
      expect(prefs.containsKey('user_user_1_schedule_sunday_first'), isTrue);
    });

    test(
        'Prefix Boundary Isolation: test vs test_user when test_user has preference keys only',
        () async {
      SharedPreferences.setMockInitialValues({
        'user_test_schedule_sunday_first': true,
        'user_test_user_schedule_sunday_first': true,
      });

      final service = AccountCacheService();
      final prefs = await SharedPreferences.getInstance();

      await service.clearAccountCache('test', accountId: 'test', prefs: prefs);

      expect(prefs.containsKey('user_test_schedule_sunday_first'), isFalse);
      expect(prefs.containsKey('user_test_user_schedule_sunday_first'), isTrue,
          reason: "'test_user' pref MUST NOT be deleted when clearing 'test'");
    });

    test('Prefix Boundary Isolation: abc vs abcd', () async {
      SharedPreferences.setMockInitialValues({
        'user_abc_schedule_sunday_first': true,
        'user_abcd_schedule_sunday_first': true,
      });

      final service = AccountCacheService();
      final prefs = await SharedPreferences.getInstance();

      await service.clearAccountCache('abc', accountId: 'abc', prefs: prefs);

      expect(prefs.containsKey('user_abc_schedule_sunday_first'), isFalse);
      expect(prefs.containsKey('user_abcd_schedule_sunday_first'), isTrue);
    });

    test(
        'Exact Account Key Isolation: exact account key user_user_1 remains intact after clearAccountCache(user)',
        () async {
      SharedPreferences.setMockInitialValues({
        'user_user': 'state_for_user',
        'user_user_1': 'state_for_user_1',
      });

      final service = AccountCacheService();
      final prefs = await SharedPreferences.getInstance();

      await service.clearAccountCache('user', accountId: 'user', prefs: prefs);

      expect(prefs.containsKey('user_user'), isFalse,
          reason: "'user_user' must be cleared when clearing 'user'");
      expect(prefs.containsKey('user_user_1'), isTrue,
          reason:
              "Exact account key 'user_user_1' MUST remain intact after clearing 'user'");
    });

    test(
        'Exact Account Key Isolation: exact account key user_test_user remains intact after clearAccountCache(test)',
        () async {
      SharedPreferences.setMockInitialValues({
        'user_test': 'state_for_test',
        'user_test_user': 'state_for_test_user',
      });

      final service = AccountCacheService();
      final prefs = await SharedPreferences.getInstance();

      await service.clearAccountCache('test', accountId: 'test', prefs: prefs);

      expect(prefs.containsKey('user_test'), isFalse,
          reason: "'user_test' must be cleared when clearing 'test'");
      expect(prefs.containsKey('user_test_user'), isTrue,
          reason:
              "Exact account key 'user_test_user' MUST remain intact after clearing 'test'");
    });

    test(
        'One-click Account Cache Clearing: Single and Multiple Account Sessions',
        () async {
      final userAB64 = base64Url.encode(utf8.encode('userA'));
      final userBB64 = base64Url.encode(utf8.encode('userB'));
      final userCB64 = base64Url.encode(utf8.encode('userC'));

      SharedPreferences.setMockInitialValues({
        'resource_cache_v1:schedule:$userAB64:default': 'dataA',
        'user_userA_pref': 'valA',
        'resource_cache_v1:schedule:$userBB64:default': 'dataB',
        'user_userB_pref': 'valB',
        'resource_cache_v1:schedule:$userCB64:default': 'dataC',
        'user_userC_pref': 'valC',
        'global_theme': 'light',
      });

      final service = AccountCacheService();
      final prefs = await SharedPreferences.getInstance();

      // Clear userA
      await service.clearAccountCache('userA', prefs: prefs);
      expect(prefs.containsKey('resource_cache_v1:schedule:$userAB64:default'),
          isFalse);
      expect(prefs.containsKey('user_userA_pref'), isFalse);
      expect(prefs.containsKey('user_userB_pref'), isTrue);
      expect(prefs.containsKey('user_userC_pref'), isTrue);

      // Clear userB
      await service.clearAccountCache('userB', prefs: prefs);
      expect(prefs.containsKey('user_userB_pref'), isFalse);
      expect(prefs.containsKey('user_userC_pref'), isTrue);
      expect(prefs.containsKey('global_theme'), isTrue);
    });
  });
}
