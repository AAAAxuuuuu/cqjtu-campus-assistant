import 'dart:convert';

import 'package:campus_app/features/auth/auth_providers.dart';
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

  group('Challenger 2 M3 Stress Tests - Requirement R3', () {
    // ------------------------------------------------------------------------
    // SECTION 1: Overlapping Username Account Isolation Stress Test
    // ------------------------------------------------------------------------
    group('1. Overlapping Username & Key Isolation Stress Tests', () {
      test(
        'Overlapping username prefix: Clearing User A ("user") must NOT delete User B ("user_extra") preferences',
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
          expect(prefs.containsKey('user_user_dorm_campus'), isFalse);

          // User B ("user_extra") data MUST NOT be deleted
          final userBIntact =
              prefs.containsKey('user_user_extra_schedule_sunday_first') &&
              prefs.containsKey('user_user_extra_dorm_campus') &&
              prefs.containsKey('resource_cache_v1:schedule:$userBB64:default');

          expect(
            userBIntact,
            isTrue,
            reason:
                'User B ("user_extra") data was corrupted/deleted when clearing User A ("user")',
          );
        },
      );

      test(
        'Overlapping username suffix: Clearing User A ("test") must NOT delete User B ("my_test") preferences',
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

          // User B data ending with _test
          expect(
            prefs.containsKey('pref_for_my_test'),
            isTrue,
            reason:
                'User B ("my_test") key ending with "_test" was incorrectly deleted',
          );
        },
      );
    });

    // ------------------------------------------------------------------------
    // SECTION 2: Session Cookie Clearing vs Secure Credential Preservation
    // ------------------------------------------------------------------------
    group('2. Session Artifact Clearing vs Credential Preservation', () {
      test(
        'Clearing account cache removes session cookies & tokens from FlutterSecureStorage while keeping CredentialService login credentials intact',
        () async {
          final sessionService = SessionService();
          final credService = CredentialService();

          const username = 'student2026';
          const password = 'secure_password_999';

          // 1. Save credentials in CredentialService
          await credService.save(username, password);

          // 2. Save web login session artifacts in SessionService
          await sessionService.saveWebLoginArtifacts(
            username,
            ticket: 'ticket_abc123',
            casCookies: 'CAS_JSESSIONID=xyz789',
            jwgCookies: 'JWG_COOKIE=12345',
            ecardCookies: 'ECARD_COOKIE=67890',
            zoveToken: 'zove_bearer_token_val',
          );

          // Verify session items & credentials exist before clear
          expect(await sessionService.loadTicket(username), 'ticket_abc123');
          expect(
            await sessionService.loadCasCookies(username),
            'CAS_JSESSIONID=xyz789',
          );
          expect(
            await sessionService.loadJwgCookies(username),
            'JWG_COOKIE=12345',
          );
          expect(
            await sessionService.loadEcardCookies(username),
            'ECARD_COOKIE=67890',
          );
          expect(
            await sessionService.loadZoveToken(username),
            'zove_bearer_token_val',
          );

          final credsBefore = await credService.load();
          expect(credsBefore?.username, username);
          expect(credsBefore?.password, password);

          // 3. Perform cache clear
          final cacheService = AccountCacheService(
            sessionService: sessionService,
          );
          await cacheService.clearAccountCache(username);

          // 4. Assert session artifacts are completely wiped out
          expect(await sessionService.loadTicket(username), isNull);
          expect(await sessionService.loadCasCookies(username), isNull);
          expect(await sessionService.loadJwgCookies(username), isNull);
          expect(await sessionService.loadEcardCookies(username), isNull);
          expect(await sessionService.loadZoveToken(username), isNull);

          // 5. Assert credentials in CredentialService remain untouched
          final credsAfter = await credService.load();
          expect(credsAfter, isNotNull);
          expect(credsAfter?.username, username);
          expect(credsAfter?.password, password);
        },
      );
    });

    // ------------------------------------------------------------------------
    // SECTION 3: Riverpod Provider Invalidation Behavior
    // ------------------------------------------------------------------------
    group('3. Riverpod Provider Invalidation Verification', () {
      test(
        'clearCurrentAccountCache invalidates all dependent feature providers and causes ref.watch to reload clean state',
        () async {
          final container = ProviderContainer();
          addTearDown(container.dispose);

          // Set active credentials
          container.read(credentialsProvider.notifier).set('userA', 'pass123');

          // Seed SharedPreferences for dormRoom
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('user_userA_dorm_campus', '科学城校区');
          await prefs.setString('user_userA_dorm_garden', 'deYuan');
          await prefs.setString('user_userA_dorm_number', '5');
          await prefs.setString('user_userA_dorm_roomid', '0502');

          // Read dorm room initially
          final initialDorm = await container.read(dormRoomProvider.future);
          expect(initialDorm?.displayName, '德园5舍 502室');

          // Execute clearCurrentAccountCache
          await clearCurrentAccountCache(container, 'userA');

          // Read dorm room post clear -> should be null as cache was removed and provider re-fetched
          final clearedDorm = await container.read(dormRoomProvider.future);
          expect(clearedDorm, isNull);
        },
      );
    });
  });
}
