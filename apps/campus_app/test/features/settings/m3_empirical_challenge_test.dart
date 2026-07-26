import 'dart:convert';

import 'package:campus_app/features/auth/auth_providers.dart';
import 'package:campus_app/features/schedule/schedule_providers.dart';
import 'package:campus_app/features/settings/settings_providers.dart';
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

  group('Milestone 3 Empirical Challenge Suite', () {
    test(
      'REQ 1 & 2: Multi-account cache clear for userA clears all userA cache/prefs while userB remains 100% intact',
      () async {
        final userAB64Url = base64Url.encode(utf8.encode('userA'));
        final userBB64Url = base64Url.encode(utf8.encode('userB'));

        final initialValues = <String, Object>{
          // User A resource caches
          'resource_cache_v1:schedule:$userAB64Url:default': jsonEncode({
            'updatedAtMs': 1000,
            'data': {'courses': [{'name': 'Math_A'}], 'remark': 'Remark_A'},
          }),
          'resource_cache_v1:grades:$userAB64Url:default': jsonEncode({
            'updatedAtMs': 1000,
            'data': {'summary': {'GPA': '3.9'}, 'grades': []},
          }),
          'resource_cache_v1:exams:$userAB64Url:default': jsonEncode({
            'updatedAtMs': 1000,
            'data': [{'courseName': 'Math Exam A'}],
          }),
          'resource_cache_v1:electricity:$userAB64Url:default': jsonEncode({
            'updatedAtMs': 1000,
            'data': '100.5',
          }),
          'resource_cache_v1:campus_card_balance:$userAB64Url:default': jsonEncode({
            'updatedAtMs': 1000,
            'data': '50.00',
          }),
          'resource_cache_v1:study_progress:$userAB64Url:default': jsonEncode({
            'updatedAtMs': 1000,
            'data': {'completedCount': 10},
          }),

          // User A scoped preferences
          'user_userA_dorm_campus': '科学城校区',
          'user_userA_dorm_garden': 'deYuan',
          'user_userA_dorm_number': '1',
          'user_userA_dorm_roomid': '0305',
          'user_userA_schedule_sunday_first': true,
          'user_userA_schedule_show_inactive_courses': false,
          'user_userA_schedule_custom_courses_2026-2027-1': '[{"name":"Custom_A"}]',
          'user_userA_schedule_total_weeks_2026-2027-1': 16,

          // User B resource caches
          'resource_cache_v1:schedule:$userBB64Url:default': jsonEncode({
            'updatedAtMs': 2000,
            'data': {'courses': [{'name': 'English_B'}], 'remark': 'Remark_B'},
          }),
          'resource_cache_v1:grades:$userBB64Url:default': jsonEncode({
            'updatedAtMs': 2000,
            'data': {'summary': {'GPA': '3.5'}, 'grades': []},
          }),
          'resource_cache_v1:exams:$userBB64Url:default': jsonEncode({
            'updatedAtMs': 2000,
            'data': [{'courseName': 'English Exam B'}],
          }),
          'resource_cache_v1:electricity:$userBB64Url:default': jsonEncode({
            'updatedAtMs': 2000,
            'data': '200.0',
          }),
          'resource_cache_v1:campus_card_balance:$userBB64Url:default': jsonEncode({
            'updatedAtMs': 2000,
            'data': '150.00',
          }),
          'resource_cache_v1:study_progress:$userBB64Url:default': jsonEncode({
            'updatedAtMs': 2000,
            'data': {'completedCount': 20},
          }),

          // User B scoped preferences
          'user_userB_dorm_campus': '南岸校区',
          'user_userB_dorm_garden': 'liYuan',
          'user_userB_dorm_number': '2',
          'user_userB_dorm_roomid': '0406',
          'user_userB_schedule_sunday_first': false,
          'user_userB_schedule_show_inactive_courses': true,
          'user_userB_schedule_custom_courses_2026-2027-1': '[{"name":"Custom_B"}]',
          'user_userB_schedule_total_weeks_2026-2027-1': 24,

          // Global / system settings
          'credential_signed_in_username_v1': 'userA',
        };

        SharedPreferences.setMockInitialValues(initialValues);

        // Also set up SessionService tokens for userA and userB
        final sessionSvc = SessionService();
        await sessionSvc.saveSessionId('userA', 'session_userA_123');
        await sessionSvc.saveTicket('userA', 'ticket_userA_123');
        await sessionSvc.saveSessionId('userB', 'session_userB_456');
        await sessionSvc.saveTicket('userB', 'ticket_userB_456');

        final container = ProviderContainer();
        addTearDown(container.dispose);

        container.read(credentialsProvider.notifier).set('userA', 'passA');

        // Execute clearCurrentAccountCache for userA
        await clearCurrentAccountCache(container, 'userA');

        final prefs = await SharedPreferences.getInstance();

        // Check userA resource caches deleted
        expect(prefs.containsKey('resource_cache_v1:schedule:$userAB64Url:default'), isFalse);
        expect(prefs.containsKey('resource_cache_v1:grades:$userAB64Url:default'), isFalse);
        expect(prefs.containsKey('resource_cache_v1:exams:$userAB64Url:default'), isFalse);
        expect(prefs.containsKey('resource_cache_v1:electricity:$userAB64Url:default'), isFalse);
        expect(prefs.containsKey('resource_cache_v1:campus_card_balance:$userAB64Url:default'), isFalse);
        expect(prefs.containsKey('resource_cache_v1:study_progress:$userAB64Url:default'), isFalse);

        // Check userA preferences deleted
        expect(prefs.containsKey('user_userA_dorm_campus'), isFalse);
        expect(prefs.containsKey('user_userA_dorm_garden'), isFalse);
        expect(prefs.containsKey('user_userA_dorm_number'), isFalse);
        expect(prefs.containsKey('user_userA_dorm_roomid'), isFalse);
        expect(prefs.containsKey('user_userA_schedule_sunday_first'), isFalse);
        expect(prefs.containsKey('user_userA_schedule_show_inactive_courses'), isFalse);
        expect(prefs.containsKey('user_userA_schedule_custom_courses_2026-2027-1'), isFalse);
        expect(prefs.containsKey('user_userA_schedule_total_weeks_2026-2027-1'), isFalse);

        // Check userA SessionService tokens deleted
        expect(await sessionSvc.loadSessionId('userA'), isNull);
        expect(await sessionSvc.loadTicket('userA'), isNull);

        // Check userB resource caches PRESERVED 100%
        expect(prefs.containsKey('resource_cache_v1:schedule:$userBB64Url:default'), isTrue);
        expect(prefs.containsKey('resource_cache_v1:grades:$userBB64Url:default'), isTrue);
        expect(prefs.containsKey('resource_cache_v1:exams:$userBB64Url:default'), isTrue);
        expect(prefs.containsKey('resource_cache_v1:electricity:$userBB64Url:default'), isTrue);
        expect(prefs.containsKey('resource_cache_v1:campus_card_balance:$userBB64Url:default'), isTrue);
        expect(prefs.containsKey('resource_cache_v1:study_progress:$userBB64Url:default'), isTrue);

        // Check userB preferences PRESERVED 100%
        expect(prefs.getString('user_userB_dorm_campus'), '南岸校区');
        expect(prefs.getString('user_userB_dorm_garden'), 'liYuan');
        expect(prefs.getBool('user_userB_schedule_sunday_first'), false);
        expect(prefs.getBool('user_userB_schedule_show_inactive_courses'), true);
        expect(prefs.getString('user_userB_schedule_custom_courses_2026-2027-1'), '[{"name":"Custom_B"}]');
        expect(prefs.getInt('user_userB_schedule_total_weeks_2026-2027-1'), 24);

        // Check userB SessionService tokens PRESERVED 100%
        expect(await sessionSvc.loadSessionId('userB'), 'session_userB_456');
        expect(await sessionSvc.loadTicket('userB'), 'ticket_userB_456');
      },
    );

    test(
      'REQ 3: Preserves CredentialService credentials so user stays logged in',
      () async {
        final credService = CredentialService();
        await credService.save('userA', 'secretPassword123');

        final container = ProviderContainer();
        addTearDown(container.dispose);

        container.read(credentialsProvider.notifier).set('userA', 'secretPassword123');

        // Clear cache
        await clearCurrentAccountCache(container, 'userA');

        // Verify CredentialService credentials still exist
        final credsFromStorage = await credService.load();
        expect(credsFromStorage, isNotNull);
        expect(credsFromStorage?.username, 'userA');
        expect(credsFromStorage?.password, 'secretPassword123');

        // Verify Riverpod credentialsProvider still holds userA credentials
        final inMemoryCreds = container.read(credentialsProvider);
        expect(inMemoryCreds, isNotNull);
        expect(inMemoryCreds?.username, 'userA');
        expect(inMemoryCreds?.password, 'secretPassword123');
      },
    );

    test(
      'REQ 4 Verification: Validates Riverpod invalidations in clearCurrentAccountCache',
      () async {
        final prefsMap = <String, Object>{
          'user_userA_schedule_sunday_first': true,
          'user_userA_schedule_show_inactive_courses': false,
          'user_userA_dorm_campus': '科学城校区',
          'user_userA_dorm_garden': 'deYuan',
          'user_userA_dorm_number': '1',
          'user_userA_dorm_roomid': '0305',
        };
        SharedPreferences.setMockInitialValues(prefsMap);

        final container = ProviderContainer();
        addTearDown(container.dispose);

        container.read(credentialsProvider.notifier).set('userA', 'passA');

        // Read initial state of providers
        final initialSundayFirst = await container.read(scheduleSundayFirstProvider.future);
        expect(initialSundayFirst, isTrue);

        final initialDorm = await container.read(dormRoomProvider.future);
        expect(initialDorm, isNotNull);
        expect(initialDorm?.roomNumber, '0305');

        final initialShowInactive = await container.read(scheduleShowInactiveCoursesProvider.future);
        expect(initialShowInactive, isFalse);

        // Execute clearCurrentAccountCache
        await clearCurrentAccountCache(container, 'userA');

        // Re-read providers to check if live invalidation updated state in RAM:
        final resetSundayFirst = await container.read(scheduleSundayFirstProvider.future);
        expect(resetSundayFirst, isFalse, reason: 'scheduleSundayFirstProvider reset to default (false)');

        final resetDorm = await container.read(dormRoomProvider.future);
        expect(resetDorm, isNull, reason: 'dormRoomProvider reset to null');

        // Check scheduleShowInactiveCoursesProvider
        final resetShowInactive = await container.read(scheduleShowInactiveCoursesProvider.future);

        // We assert resetShowInactive is true (will fail if not invalidated)
        expect(resetShowInactive, isTrue, reason: 'BUG DETECTED: scheduleShowInactiveCoursesProvider is missing ref.invalidate in clearCurrentAccountCache');
      },
    );
  });
}
