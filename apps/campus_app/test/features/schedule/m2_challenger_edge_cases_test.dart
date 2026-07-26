import 'package:campus_app/features/auth/auth_providers.dart';
import 'package:campus_app/features/schedule/schedule_providers.dart';
import 'package:campus_app/features/settings/settings_providers.dart';
import 'package:campus_platform/services/dorm_service.dart';
import 'package:core/models/course.dart';
import 'package:core/models/dorm_room.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('M2 Challenger Edge Case Tests', () {
    test('1. Key generation logic under unusual account IDs (special chars, long strings, whitespace)', () async {
      // Test userScopedKey directly
      expect(
        userScopedKey('user@domain.com', 'test_key'),
        'user_user@domain.com_test_key',
      );

      expect(
        userScopedKey('user/123#\$\$%^&*()', 'test_key'),
        'user_user/123#\$\$%^&*()_test_key',
      );

      expect(
        userScopedKey('  padded_user  ', 'test_key'),
        'user_padded_user_test_key',
        reason: 'Leading and trailing whitespace must be trimmed',
      );

      expect(
        userScopedKey('中文账号_123', 'test_key'),
        'user_中文账号_123_test_key',
      );

      expect(
        userScopedKey('emoji_😀_user', 'test_key'),
        'user_emoji_😀_user_test_key',
      );

      final longAccountId = 'a' * 1000;
      expect(
        userScopedKey(longAccountId, 'test_key'),
        'user_${longAccountId}_test_key',
      );

      expect(
        userScopedKey('', 'test_key'),
        'user_default_test_key',
        reason: 'Empty account ID must fallback to default',
      );

      expect(
        userScopedKey('   ', 'test_key'),
        'user_default_test_key',
        reason: 'Whitespace-only account ID must fallback to default',
      );

      // Test DormService save and load with special characters & long strings
      final dormService = DormService();
      final room1 = DormRoom(
        campusName: '科学城校区',
        garden: DormGarden.deYuan,
        buildingNumber: 12,
        roomNumber: '0405',
      );

      final specialAccountId = 'user#123@xyz!/\\';
      await dormService.save(room1, accountId: specialAccountId);

      final loadedRoom1 = await dormService.load(accountId: specialAccountId);
      expect(loadedRoom1?.campusName, '科学城校区');
      expect(loadedRoom1?.garden, DormGarden.deYuan);
      expect(loadedRoom1?.buildingNumber, 12);
      expect(loadedRoom1?.roomNumber, '0405');

      // Ensure clear removes account-scoped keys
      await dormService.clear(accountId: specialAccountId);
      final clearedRoom = await dormService.load(accountId: specialAccountId);
      expect(clearedRoom, isNull);
    });

    test('2. Persistence across simulated app restart / provider disposal', () async {
      final specialUser = 'user@special#domain:99';
      final longUser = 'x' * 500;

      // --- SESSION 1 ---
      var container1 = ProviderContainer();

      // Login as special user
      container1.read(credentialsProvider.notifier).set(specialUser, 'password123');

      // Set Sunday First
      await container1
          .read(scheduleSundayFirstProvider.notifier)
          .setSundayFirst(true);

      // Set Semester Total Weeks
      await container1
          .read(semesterTotalWeeksProvider('2026-2027-1').notifier)
          .setWeeks(22);

      // Add Custom Course
      final course1 = Course(
        name: 'Special Edge Course',
        teacher: 'Prof. Edge',
        timeStr: 'Wed 1-2',
        classroom: 'Lab 404',
        dayOfWeek: 3,
        timeSlot: 1,
        endTimeSlot: 2,
        weekList: [1, 2, 3],
        isCustom: true,
      );
      await container1
          .read(customCoursesProvider('2026-2027-1').notifier)
          .addCourse(course1);

      // Set Dorm Room
      final specialDorm = DormRoom(
        campusName: '科学城校区',
        garden: DormGarden.deYuan,
        buildingNumber: 5,
        roomNumber: '0201',
      );
      await container1.read(dormRoomProvider.notifier).set(specialDorm);

      // Verify raw SharedPreferences keys in Session 1
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('user_${specialUser}_schedule_sunday_first'), isTrue);
      expect(prefs.getInt('user_${specialUser}_schedule_total_weeks_2026-2027-1'), 22);
      expect(prefs.getString('user_${specialUser}_dorm_campus'), '科学城校区');

      // Simulate App Restart by disposing container1
      container1.dispose();

      // --- SESSION 2 (App Restart) ---
      var container2 = ProviderContainer();
      addTearDown(container2.dispose);

      // Restore credentials for specialUser
      container2.read(credentialsProvider.notifier).set(specialUser, 'password123');

      final restoredSundayFirst =
          await container2.read(scheduleSundayFirstProvider.future);
      expect(restoredSundayFirst, isTrue);

      final restoredTotalWeeks =
          await container2.read(semesterTotalWeeksProvider('2026-2027-1').future);
      expect(restoredTotalWeeks, 22);

      final restoredCourses =
          await container2.read(customCoursesProvider('2026-2027-1').future);
      expect(restoredCourses.length, 1);
      expect(restoredCourses.first.name, 'Special Edge Course');

      final restoredDorm = await container2.read(dormRoomProvider.future);
      expect(restoredDorm?.campusName, '科学城校区');
      expect(restoredDorm?.buildingNumber, 5);

      // In Session 2, switch to extremely long account ID
      container2.read(credentialsProvider.notifier).set(longUser, 'pass_long');

      final longUserSundayFirst =
          await container2.read(scheduleSundayFirstProvider.future);
      expect(longUserSundayFirst, isFalse, reason: 'Long user should get default preference');

      await container2
          .read(scheduleSundayFirstProvider.notifier)
          .setSundayFirst(false);
      expect(prefs.getBool('user_${longUser}_schedule_sunday_first'), isFalse);

      // Switch back to specialUser in container2
      container2.read(credentialsProvider.notifier).set(specialUser, 'password123');
      final recheckedSundayFirst =
          await container2.read(scheduleSundayFirstProvider.future);
      expect(recheckedSundayFirst, isTrue, reason: 'Special user preference must remain intact');
    });
  });
}
