import 'dart:convert';

import 'package:campus_platform/services/account_cache_service.dart';
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

  group('AccountCacheService tests', () {
    test(
        'triggering cache clear for Account A removes Account A cache and preferences while Account B remains intact',
        () async {
      final userAB64 = base64Url.encode(utf8.encode('userA'));
      final userBB64 = base64Url.encode(utf8.encode('userB'));

      SharedPreferences.setMockInitialValues({
        // Account A cache and preference keys
        'resource_cache_v1:schedule:$userAB64:default': '{"courses":["Math"]}',
        'resource_cache_v1:grades:$userAB64:default':
            '{"summary":{"GPA":"3.8"}}',
        'user_userA_schedule_sunday_first': true,
        'user_userA_dorm_campus': '科学城校区',

        // Account B cache and preference keys
        'resource_cache_v1:schedule:$userBB64:default':
            '{"courses":["English"]}',
        'resource_cache_v1:grades:$userBB64:default':
            '{"summary":{"GPA":"3.5"}}',
        'user_userB_schedule_sunday_first': false,
        'user_userB_dorm_campus': '南岸校区',

        // Global app setting
        'app_theme_mode': 'dark',
      });

      final service = AccountCacheService();
      final prefs = await SharedPreferences.getInstance();

      // Verify initial state
      expect(prefs.containsKey('resource_cache_v1:schedule:$userAB64:default'),
          isTrue);
      expect(prefs.containsKey('resource_cache_v1:schedule:$userBB64:default'),
          isTrue);
      expect(prefs.containsKey('user_userA_schedule_sunday_first'), isTrue);
      expect(prefs.containsKey('user_userB_schedule_sunday_first'), isTrue);

      // Execute cache clear for Account A
      await service.clearAccountCache('userA',
          accountId: 'userA', prefs: prefs);

      // Verify Account A keys are removed
      expect(prefs.containsKey('resource_cache_v1:schedule:$userAB64:default'),
          isFalse);
      expect(prefs.containsKey('resource_cache_v1:grades:$userAB64:default'),
          isFalse);
      expect(prefs.containsKey('user_userA_schedule_sunday_first'), isFalse);
      expect(prefs.containsKey('user_userA_dorm_campus'), isFalse);

      // Verify Account B keys remain intact
      expect(prefs.containsKey('resource_cache_v1:schedule:$userBB64:default'),
          isTrue);
      expect(prefs.containsKey('resource_cache_v1:grades:$userBB64:default'),
          isTrue);
      expect(prefs.containsKey('user_userB_schedule_sunday_first'), isTrue);
      expect(prefs.containsKey('user_userB_dorm_campus'), isTrue);

      // Verify unrelated global settings remain intact
      expect(prefs.containsKey('app_theme_mode'), isTrue);
    });

    test('Riverpod state invalidation reloads clean state correctly', () async {
      int buildCount = 0;
      final testResourceProvider = StateProvider<String>((ref) {
        buildCount++;
        return 'data_v$buildCount';
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Initial read
      final firstRead = container.read(testResourceProvider);
      expect(firstRead, 'data_v1');
      expect(buildCount, 1);

      final service = AccountCacheService();

      // Clear cache and invalidate test resource provider
      await service.clearAndInvalidate(
        invalidator: (provider) => container.invalidate(provider),
        username: 'userA',
        accountId: 'userA',
        providers: [testResourceProvider],
      );

      // Subsequent read after invalidation should produce re-evaluated state
      final secondRead = container.read(testResourceProvider);
      expect(secondRead, 'data_v2');
      expect(buildCount, 2);
    });
  });
}
