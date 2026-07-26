import 'dart:convert';

import 'package:campus_app/features/auth/auth_providers.dart';
import 'package:campus_app/features/schedule/schedule_providers.dart';
import 'package:campus_app/features/settings/settings_providers.dart';
import 'package:campus_platform/services/account_cache_service.dart';
import 'package:campus_platform/services/credential_service.dart';
import 'package:campus_platform/services/session_service.dart';
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

  group('Challenger 1 Stress & Empirical Challenge Suite for Milestone 3 (R3)', () {
    test(
      'Challenge 1 (FAIL): Overlapping username prefix causes User A ("user") clear to delete User B ("user_extra") preferences',
      () async {
        final userAB64 = base64Url.encode(utf8.encode('user'));
        final userBB64 = base64Url.encode(utf8.encode('user_extra'));

        SharedPreferences.setMockInitialValues({
          // User A ("user") data
          'resource_cache_v1:schedule:$userAB64:default': 'data_A',
          'user_user_schedule_sunday_first': true,
          'user_user_dorm_campus': '科学城校区',

          // User B ("user_extra") data
          'resource_cache_v1:schedule:$userBB64:default': 'data_B',
          'user_user_extra_schedule_sunday_first': false,
          'user_user_extra_dorm_campus': '南岸校区',
        });

        final container = ProviderContainer();
        addTearDown(container.dispose);

        // Clear cache for User A ("user")
        await clearCurrentAccountCache(container, 'user');

        final prefs = await SharedPreferences.getInstance();

        // User A data should be deleted
        expect(
          prefs.containsKey('resource_cache_v1:schedule:$userAB64:default'),
          isFalse,
        );
        expect(prefs.containsKey('user_user_schedule_sunday_first'), isFalse);

        // User B ("user_extra") data should be intact
        final userBIntact =
            prefs.containsKey('user_user_extra_schedule_sunday_first') &&
            prefs.containsKey('user_user_extra_dorm_campus') &&
            prefs.containsKey('resource_cache_v1:schedule:$userBB64:default');

        expect(
          userBIntact,
          isTrue,
          reason:
              'BUG CONFIRMED: Clearing User A ("user") deletes User B ("user_extra") data due to prefix matching on "user_user_"',
        );
      },
    );

    test(
      'Challenge 2 (FAIL): Overlapping username suffix causes User A ("test") clear to delete User B ("my_test") preferences',
      () async {
        final userAB64 = base64Url.encode(utf8.encode('test'));
        final userBB64 = base64Url.encode(utf8.encode('my_test'));

        SharedPreferences.setMockInitialValues({
          'resource_cache_v1:schedule:$userAB64:default': 'data_A',
          'user_test_pref': 'valA',

          'resource_cache_v1:schedule:$userBB64:default': 'data_B',
          'pref_for_my_test': 'valB',
        });

        final container = ProviderContainer();
        addTearDown(container.dispose);

        await clearCurrentAccountCache(container, 'test');

        final prefs = await SharedPreferences.getInstance();

        expect(
          prefs.containsKey('resource_cache_v1:schedule:$userAB64:default'),
          isFalse,
        );
        expect(prefs.containsKey('user_test_pref'), isFalse);

        expect(
          prefs.containsKey('pref_for_my_test'),
          isTrue,
          reason:
              'BUG CONFIRMED: Clearing User A ("test") deletes User B ("my_test") key "pref_for_my_test" due to suffix matching on "_test"',
        );
      },
    );

    test(
      'Challenge 3 (PASS): Session cookies & tokens cleared while login credentials in CredentialService preserved',
      () async {
        final sessionService = SessionService();
        final credService = CredentialService();

        const username = 'student2026';
        const password = 'secure_password_999';

        await credService.save(username, password);
        await sessionService.saveWebLoginArtifacts(
          username,
          ticket: 'ticket_abc123',
          casCookies: 'CAS_JSESSIONID=xyz789',
          jwgCookies: 'JWG_COOKIE=12345',
          ecardCookies: 'ECARD_COOKIE=67890',
          zoveToken: 'zove_bearer_token_val',
        );

        expect(await sessionService.loadTicket(username), 'ticket_abc123');
        expect(
          await sessionService.loadCasCookies(username),
          'CAS_JSESSIONID=xyz789',
        );

        final cacheService = AccountCacheService(
          sessionService: sessionService,
        );
        await cacheService.clearAccountCache(username);

        // Session tokens removed
        expect(await sessionService.loadTicket(username), isNull);
        expect(await sessionService.loadCasCookies(username), isNull);
        expect(await sessionService.loadJwgCookies(username), isNull);
        expect(await sessionService.loadEcardCookies(username), isNull);
        expect(await sessionService.loadZoveToken(username), isNull);

        // Credentials preserved
        final credsAfter = await credService.load();
        expect(credsAfter, isNotNull);
        expect(credsAfter?.username, username);
        expect(credsAfter?.password, password);
      },
    );

    test(
      'Challenge 4 (FAIL): Riverpod invalidation misses scheduleShowInactiveCoursesProvider',
      () async {
        final prefsMap = <String, Object>{
          'user_userA_schedule_show_inactive_courses': false,
        };
        SharedPreferences.setMockInitialValues(prefsMap);

        final container = ProviderContainer();
        addTearDown(container.dispose);

        container.read(credentialsProvider.notifier).set('userA', 'passA');

        // Initial read -> false
        final initialShowInactive = await container.read(
          scheduleShowInactiveCoursesProvider.future,
        );
        expect(initialShowInactive, isFalse);

        // Execute clearCurrentAccountCache
        await clearCurrentAccountCache(container, 'userA');

        // Re-read -> after clear, should reset to default (true)
        final resetShowInactive = await container.read(
          scheduleShowInactiveCoursesProvider.future,
        );
        expect(
          resetShowInactive,
          isTrue,
          reason:
              'BUG CONFIRMED: scheduleShowInactiveCoursesProvider is missing ref.invalidate in clearCurrentAccountCache',
        );
      },
    );
  });
}
