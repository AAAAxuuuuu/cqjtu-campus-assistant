import 'dart:convert';

import 'package:campus_app/features/auth/auth_providers.dart';
import 'package:campus_app/features/schedule/schedule_providers.dart';
import 'package:campus_app/features/settings/settings_providers.dart';
import 'package:campus_platform/services/account_cache_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  group('AccountCacheService & clearCurrentAccountCache (R3 & R4)', () {
    test(
      'clearCurrentAccountCache deletes userA cache & preferences while preserving userB data and userA credentials',
      () async {
        final userAB64 = base64Url.encode(utf8.encode('userA'));
        final userBB64 = base64Url.encode(utf8.encode('userB'));

        final initialValues = <String, Object>{
          // User A resource cache
          'resource_cache_v1:schedule:$userAB64:default': 'data_A_schedule',
          'resource_cache_v1:grades:$userAB64:default': 'data_A_grades',
          // Fallback resource cache (unscoped/default key written during cache write)
          'resource_cache_v1:schedule:default:2026-2027-1':
              'data_default_schedule',
          // User A scoped preferences
          'user_userA_schedule_sunday_first': true,
          'user_userA_schedule_show_inactive_courses': false,
          'user_userA_dorm_campus': '科学城校区',
          'user_userA_schedule_custom_courses_2026-2027-1':
              '[{"name":"CourseA"}]',

          // Legacy preferences
          'schedule_custom_courses_2026-2027-1': '[{"name":"Legacy"}]',
          'schedule_total_weeks_2026-2027-1': 20,
          'dorm_roomid': '101',
          'semester_start_key_2026-2027-1': '2026-09-01',
          'selected_semester_str': '2026-2027-1',
          'schedule_sunday_first': true,

          // User B resource cache
          'resource_cache_v1:schedule:$userBB64:default': 'data_B_schedule',
          'resource_cache_v1:grades:$userBB64:default': 'data_B_grades',
          // User B scoped preferences
          'user_userB_schedule_sunday_first': false,
          'user_userB_dorm_campus': '南岸校区',
          'user_userB_schedule_custom_courses_2026-2027-1':
              '[{"name":"CourseB"}]',

          // Global app setting
          'battery_guide_shown': true,
        };

        SharedPreferences.setMockInitialValues(initialValues);

        final container = ProviderContainer();
        addTearDown(container.dispose);

        // 1. Log in userA
        container
            .read(credentialsProvider.notifier)
            .set('userA', 'password123');
        final showInactiveBefore = await container.read(
          scheduleShowInactiveCoursesProvider.future,
        );
        expect(showInactiveBefore, isFalse);

        // Verify initial state
        final prefsBefore = await SharedPreferences.getInstance();
        expect(
          prefsBefore.containsKey(
            'resource_cache_v1:schedule:$userAB64:default',
          ),
          isTrue,
        );
        expect(
          prefsBefore.containsKey(
            'resource_cache_v1:schedule:$userBB64:default',
          ),
          isTrue,
        );
        expect(
          prefsBefore.containsKey(
            'resource_cache_v1:schedule:default:2026-2027-1',
          ),
          isTrue,
        );
        expect(
          prefsBefore.containsKey('user_userA_schedule_sunday_first'),
          isTrue,
        );
        expect(
          prefsBefore.containsKey('user_userB_schedule_sunday_first'),
          isTrue,
        );

        // 2. Execute clearCurrentAccountCache for userA
        await clearCurrentAccountCache(container, 'userA');

        final prefsAfter = await SharedPreferences.getInstance();

        // 3. Assert userA keys, fallback keys, and legacy keys are deleted
        expect(
          prefsAfter.containsKey(
            'resource_cache_v1:schedule:$userAB64:default',
          ),
          isFalse,
        );
        expect(
          prefsAfter.containsKey('resource_cache_v1:grades:$userAB64:default'),
          isFalse,
        );
        expect(
          prefsAfter.containsKey(
            'resource_cache_v1:schedule:default:2026-2027-1',
          ),
          isFalse,
        );
        expect(
          prefsAfter.containsKey('user_userA_schedule_sunday_first'),
          isFalse,
        );
        expect(
          prefsAfter.containsKey('user_userA_schedule_show_inactive_courses'),
          isFalse,
        );
        expect(prefsAfter.containsKey('user_userA_dorm_campus'), isFalse);
        expect(
          prefsAfter.containsKey(
            'user_userA_schedule_custom_courses_2026-2027-1',
          ),
          isFalse,
        );

        expect(
          prefsAfter.containsKey('schedule_custom_courses_2026-2027-1'),
          isFalse,
        );
        expect(
          prefsAfter.containsKey('schedule_total_weeks_2026-2027-1'),
          isFalse,
        );
        expect(prefsAfter.containsKey('dorm_roomid'), isFalse);
        expect(
          prefsAfter.containsKey('semester_start_key_2026-2027-1'),
          isFalse,
        );
        expect(prefsAfter.containsKey('selected_semester_str'), isFalse);
        expect(prefsAfter.containsKey('schedule_sunday_first'), isFalse);

        // 4. Assert userB keys and global settings remain intact
        expect(
          prefsAfter.containsKey(
            'resource_cache_v1:schedule:$userBB64:default',
          ),
          isTrue,
        );
        expect(
          prefsAfter.containsKey('resource_cache_v1:grades:$userBB64:default'),
          isTrue,
        );
        expect(
          prefsAfter.containsKey('user_userB_schedule_sunday_first'),
          isTrue,
        );
        expect(prefsAfter.containsKey('user_userB_dorm_campus'), isTrue);
        expect(
          prefsAfter.containsKey(
            'user_userB_schedule_custom_courses_2026-2027-1',
          ),
          isTrue,
        );
        expect(prefsAfter.containsKey('battery_guide_shown'), isTrue);

        // 5. Assert userA credentials remain intact so user stays logged in
        final creds = container.read(credentialsProvider);
        expect(creds?.username, 'userA');
        expect(creds?.password, 'password123');

        // 6. Assert scheduleShowInactiveCoursesProvider is invalidated and reloads default true
        final showInactiveAfter = await container.read(
          scheduleShowInactiveCoursesProvider.future,
        );
        expect(showInactiveAfter, isTrue);
      },
    );

    test(
      'AccountCacheService.clearAccountCache cleanly handles single-user isolation and clearCurrentAccountCache alias',
      () async {
        final userAB64 = base64Url.encode(utf8.encode('userA'));

        SharedPreferences.setMockInitialValues({
          'resource_cache_v1:schedule:$userAB64:default': 'data',
          'user_userA_test': 'test',
        });

        final cacheService = AccountCacheService();
        final prefs = await SharedPreferences.getInstance();

        await cacheService.clearCurrentAccountCache('userA', prefs: prefs);

        expect(
          prefs.containsKey('resource_cache_v1:schedule:$userAB64:default'),
          isFalse,
        );
        expect(prefs.containsKey('user_userA_test'), isFalse);
      },
    );

    test('clearAccountCache ignores empty or whitespace usernames', () async {
      final userAB64 = base64Url.encode(utf8.encode('userA'));

      SharedPreferences.setMockInitialValues({
        'resource_cache_v1:schedule:$userAB64:default': 'data',
        'user_userA_test': 'test',
      });

      final cacheService = AccountCacheService();
      final prefs = await SharedPreferences.getInstance();

      await cacheService.clearAccountCache('', prefs: prefs);
      await cacheService.clearAccountCache('   ', prefs: prefs);

      expect(
        prefs.containsKey('resource_cache_v1:schedule:$userAB64:default'),
        isTrue,
      );
      expect(prefs.containsKey('user_userA_test'), isTrue);
    });
  });
}
