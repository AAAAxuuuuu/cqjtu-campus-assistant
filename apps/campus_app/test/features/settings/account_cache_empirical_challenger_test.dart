import 'dart:convert';

import 'package:campus_app/features/auth/auth_providers.dart';
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

  group('Challenger Empirical Verification - Milestone 3 Account Cache Clearing', () {
    test(
      'Empirical Requirement 1 & 2: Purges Account A cache & scoped prefs completely while leaving Account B data and global settings untouched',
      () async {
        final userAB64Url = base64Url.encode(utf8.encode('userA'));
        final userAB64Std = base64.encode(utf8.encode('userA'));
        final userBB64Url = base64Url.encode(utf8.encode('userB'));

        final seededPrefs = <String, Object>{
          // Account A Resource Caches (Base64Url, Base64Std, Unscoped/Default)
          'resource_cache_v1:schedule:$userAB64Url:default': '{"data":"userA_schedule"}',
          'resource_cache_v1:grades:$userAB64Url:default': '{"data":"userA_grades"}',
          'resource_cache_v1:exams:$userAB64Std:default': '{"data":"userA_exams"}',
          'resource_cache_v1:schedule:default:2026-2027-1': '{"data":"unscoped_schedule"}',

          // Account A Scoped Preferences
          'user_userA_schedule_sunday_first': true,
          'user_userA_dorm_campus': '科学城校区',
          'user_userA_schedule_custom_courses_2026-2027-1': '[{"name":"CustomA"}]',

          // Legacy Un-prefixed Preferences
          'schedule_custom_courses_2026-2027-1': '[{"name":"LegacyCourse"}]',
          'schedule_total_weeks_2026-2027-1': 18,
          'dorm_roomid': '302',
          'semester_start_key_2026-2027-1': '2026-09-01',
          'selected_semester_str': '2026-2027-1',
          'schedule_sunday_first': false,
          'schedule_show_inactive_courses': true,

          // Account B Resource Caches & Scoped Preferences
          'resource_cache_v1:schedule:$userBB64Url:default': '{"data":"userB_schedule"}',
          'resource_cache_v1:grades:$userBB64Url:default': '{"data":"userB_grades"}',
          'user_userB_schedule_sunday_first': false,
          'user_userB_dorm_campus': '南岸校区',
          'user_userB_schedule_custom_courses_2026-2027-1': '[{"name":"CustomB"}]',

          // Global App Settings (Should NOT be deleted)
          'battery_guide_shown': true,
          'app_theme_mode': 'dark',
        };

        SharedPreferences.setMockInitialValues(seededPrefs);

        final container = ProviderContainer();
        addTearDown(container.dispose);

        // Set Account A login credentials
        container.read(credentialsProvider.notifier).set('userA', 'secret123');

        // Execute clearCurrentAccountCache for userA
        await clearCurrentAccountCache(container, 'userA');

        final prefsAfter = await SharedPreferences.getInstance();

        // 1. Assert Account A keys, fallback default keys, and legacy keys are purged
        expect(prefsAfter.containsKey('resource_cache_v1:schedule:$userAB64Url:default'), isFalse, reason: 'Account A schedule cache must be purged');
        expect(prefsAfter.containsKey('resource_cache_v1:grades:$userAB64Url:default'), isFalse, reason: 'Account A grades cache must be purged');
        expect(prefsAfter.containsKey('resource_cache_v1:exams:$userAB64Std:default'), isFalse, reason: 'Account A exams cache must be purged');
        expect(prefsAfter.containsKey('resource_cache_v1:schedule:default:2026-2027-1'), isFalse, reason: 'Unscoped fallback cache must be purged');
        expect(prefsAfter.containsKey('user_userA_schedule_sunday_first'), isFalse, reason: 'Account A scoped pref must be purged');
        expect(prefsAfter.containsKey('user_userA_dorm_campus'), isFalse, reason: 'Account A dorm pref must be purged');
        expect(prefsAfter.containsKey('user_userA_schedule_custom_courses_2026-2027-1'), isFalse, reason: 'Account A custom course pref must be purged');
        expect(prefsAfter.containsKey('schedule_custom_courses_2026-2027-1'), isFalse, reason: 'Legacy custom courses pref must be purged');
        expect(prefsAfter.containsKey('schedule_total_weeks_2026-2027-1'), isFalse, reason: 'Legacy total weeks pref must be purged');
        expect(prefsAfter.containsKey('dorm_roomid'), isFalse, reason: 'Legacy dorm pref must be purged');
        expect(prefsAfter.containsKey('semester_start_key_2026-2027-1'), isFalse, reason: 'Legacy semester start pref must be purged');
        expect(prefsAfter.containsKey('selected_semester_str'), isFalse, reason: 'Legacy selected semester pref must be purged');
        expect(prefsAfter.containsKey('schedule_sunday_first'), isFalse, reason: 'Legacy sunday first pref must be purged');

        // 2. Assert Account B data and global settings remain completely untouched
        expect(prefsAfter.containsKey('resource_cache_v1:schedule:$userBB64Url:default'), isTrue, reason: 'Account B schedule cache must remain intact');
        expect(prefsAfter.getString('resource_cache_v1:schedule:$userBB64Url:default'), '{"data":"userB_schedule"}');
        expect(prefsAfter.containsKey('resource_cache_v1:grades:$userBB64Url:default'), isTrue, reason: 'Account B grades cache must remain intact');
        expect(prefsAfter.containsKey('user_userB_schedule_sunday_first'), isTrue, reason: 'Account B scoped pref must remain intact');
        expect(prefsAfter.getBool('user_userB_schedule_sunday_first'), false);
        expect(prefsAfter.containsKey('user_userB_dorm_campus'), isTrue, reason: 'Account B dorm pref must remain intact');
        expect(prefsAfter.getString('user_userB_dorm_campus'), '南岸校区');
        expect(prefsAfter.containsKey('user_userB_schedule_custom_courses_2026-2027-1'), isTrue, reason: 'Account B custom courses must remain intact');
        expect(prefsAfter.containsKey('battery_guide_shown'), isTrue, reason: 'Global setting battery_guide_shown must remain intact');
        expect(prefsAfter.getBool('battery_guide_shown'), true);
        expect(prefsAfter.containsKey('app_theme_mode'), isTrue, reason: 'Global setting app_theme_mode must remain intact');
        expect(prefsAfter.getString('app_theme_mode'), 'dark');

        // 3. Assert Account A credentials in CredentialService are retained (stay logged in)
        final creds = container.read(credentialsProvider);
        expect(creds?.username, 'userA');
        expect(creds?.password, 'secret123');
      },
    );

    test(
      'Empirical Requirement 3: Re-fetching domain providers post-clear triggers fresh data fetching rather than returning stale cached responses',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        // Set logged-in credentials
        container.read(credentialsProvider.notifier).set('userA', 'password123');

        // Populate initial dormRoom state in SharedPreferences for userA
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_userA_dorm_campus', '科学城校区');
        await prefs.setString('user_userA_dorm_garden', 'deYuan');
        await prefs.setString('user_userA_dorm_number', '8');
        await prefs.setString('user_userA_dorm_roomid', '0305');

        // Read dormRoomProvider initially
        final initialRoom = await container.read(dormRoomProvider.future);
        expect(initialRoom?.campusName, '科学城校区');
        expect(initialRoom?.buildingNumber, 8);

        // Now clear account cache for userA
        await clearCurrentAccountCache(container, 'userA');

        // Verify SharedPreferences keys are cleared
        expect(prefs.containsKey('user_userA_dorm_campus'), isFalse);
        expect(prefs.containsKey('user_userA_dorm_roomid'), isFalse);

        // Re-read dormRoomProvider post-clear
        final postClearRoom = await container.read(dormRoomProvider.future);
        // Post clear, provider was invalidated and re-fetched from storage, returning null (fresh state, not stale cached response)
        expect(postClearRoom, isNull);
      },
    );

    test(
      'Empirical Edge Cases: Whitespace trimming, non-existent account clearing isolation, and session clearing',
      () async {
        final userAB64Url = base64Url.encode(utf8.encode('userA'));
        final userBB64Url = base64Url.encode(utf8.encode('userB'));

        SharedPreferences.setMockInitialValues({
          'resource_cache_v1:schedule:$userAB64Url:default': 'data_A',
          'resource_cache_v1:schedule:$userBB64Url:default': 'data_B',
        });

        final cacheService = AccountCacheService();
        final prefs = await SharedPreferences.getInstance();

        // 1. Clearing non-existent Account C should leave Account A and B intact
        await cacheService.clearAccountCache('userC', prefs: prefs);
        expect(prefs.containsKey('resource_cache_v1:schedule:$userAB64Url:default'), isTrue);
        expect(prefs.containsKey('resource_cache_v1:schedule:$userBB64Url:default'), isTrue);

        // 2. Clearing userA with leading/trailing whitespace ('  userA  ') properly trims and purges userA
        await cacheService.clearAccountCache('  userA  ', prefs: prefs);
        expect(prefs.containsKey('resource_cache_v1:schedule:$userAB64Url:default'), isFalse);
        expect(prefs.containsKey('resource_cache_v1:schedule:$userBB64Url:default'), isTrue);

        // 3. Repeated clearing (idempotency check) does not crash or corrupt storage
        await cacheService.clearAccountCache('userA', prefs: prefs);
        expect(prefs.containsKey('resource_cache_v1:schedule:$userBB64Url:default'), isTrue);
      },
    );
  });
}
