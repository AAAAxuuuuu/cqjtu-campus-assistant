import 'package:campus_app/features/auth/auth_providers.dart';
import 'package:campus_app/features/schedule/schedule_providers.dart';
import 'package:campus_app/features/settings/settings_providers.dart';
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

  group('R2 Account ID Preference & Data Isolation Tests', () {
    test(
      '1. Schedule Sunday First preference is strictly isolated per account ID',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        // Account A login
        container.read(credentialsProvider.notifier).set('account_a', 'pass_a');
        expect(container.read(credentialsProvider)?.username, 'account_a');

        // Set Sunday First = true under Account A
        await container
            .read(scheduleSundayFirstProvider.notifier)
            .setSundayFirst(true);
        final sundayFirstA = await container.read(
          scheduleSundayFirstProvider.future,
        );
        expect(sundayFirstA, isTrue);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool('user_account_a_schedule_sunday_first'), isTrue);

        // Switch to Account B
        container.read(credentialsProvider.notifier).set('account_b', 'pass_b');
        expect(container.read(credentialsProvider)?.username, 'account_b');

        final sundayFirstB = await container.read(
          scheduleSundayFirstProvider.future,
        );
        expect(
          sundayFirstB,
          isFalse,
          reason: 'Account B must not inherit Account A preference',
        );
        expect(prefs.getBool('user_account_b_schedule_sunday_first'), isNull);

        // Set Sunday First = false under Account B
        await container
            .read(scheduleSundayFirstProvider.notifier)
            .setSundayFirst(false);
        expect(prefs.getBool('user_account_b_schedule_sunday_first'), isFalse);

        // Switch back to Account A
        container.read(credentialsProvider.notifier).set('account_a', 'pass_a');
        final restoredSundayFirstA = await container.read(
          scheduleSundayFirstProvider.future,
        );
        expect(
          restoredSundayFirstA,
          isTrue,
          reason: 'Account A preference must be restored intact',
        );
      },
    );

    test(
      '2. Semester Total Weeks is strictly isolated per account ID and semester',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        // Set semester start to 2026-09-01 (Semester 2026-2027-1)
        await container
            .read(semesterStartProvider.notifier)
            .set(DateTime(2026, 9, 1));

        // Account A login
        container.read(credentialsProvider.notifier).set('user_1001', 'pass1');

        // Account A sets 24 weeks
        await container
            .read(semesterTotalWeeksProvider(null).notifier)
            .setWeeks(24);
        final weeksA = await container.read(
          semesterTotalWeeksProvider(null).future,
        );
        expect(weeksA, 24);

        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getInt('user_user_1001_schedule_total_weeks_2026-2027-1'),
          24,
        );

        // Switch to Account B
        container.read(credentialsProvider.notifier).set('user_1002', 'pass2');
        final weeksB = await container.read(
          semesterTotalWeeksProvider(null).future,
        );
        expect(
          weeksB,
          defaultSemesterTotalWeeks,
          reason: 'Account B should get default total weeks',
        );

        // Account B sets 16 weeks
        await container
            .read(semesterTotalWeeksProvider(null).notifier)
            .setWeeks(16);
        expect(
          prefs.getInt('user_user_1002_schedule_total_weeks_2026-2027-1'),
          16,
        );

        // Switch back to Account A
        container.read(credentialsProvider.notifier).set('user_1001', 'pass1');
        final restoredWeeksA = await container.read(
          semesterTotalWeeksProvider(null).future,
        );
        expect(
          restoredWeeksA,
          24,
          reason: 'Account A total weeks must be restored intact',
        );
      },
    );

    test(
      '3. Custom Courses are strictly isolated per account ID without cross-account leakage',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        await container
            .read(semesterStartProvider.notifier)
            .set(DateTime(2026, 9, 1));

        // Account A login
        container.read(credentialsProvider.notifier).set('student_a', 'secret');

        const courseA = Course(
          name: 'Account A Math',
          teacher: 'Teacher A',
          timeStr: 'Mon 1-2',
          classroom: 'Room A',
          dayOfWeek: 1,
          timeSlot: 1,
          endTimeSlot: 2,
          weekList: [1, 2, 3],
          isCustom: true,
        );

        await container
            .read(customCoursesProvider(null).notifier)
            .addCourse(courseA);

        final coursesA = await container.read(
          customCoursesProvider(null).future,
        );
        expect(coursesA, hasLength(1));
        expect(coursesA.first.name, 'Account A Math');

        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.containsKey(
            'user_student_a_schedule_custom_courses_2026-2027-1',
          ),
          isTrue,
        );

        // Switch to Account B
        container.read(credentialsProvider.notifier).set('student_b', 'secret');
        final coursesB = await container.read(
          customCoursesProvider(null).future,
        );
        expect(
          coursesB,
          isEmpty,
          reason: 'Account B must not see Account A custom courses',
        );

        const courseB = Course(
          name: 'Account B Physics',
          teacher: 'Teacher B',
          timeStr: 'Wed 3-4',
          classroom: 'Room B',
          dayOfWeek: 3,
          timeSlot: 3,
          endTimeSlot: 4,
          weekList: [1, 2, 3, 4, 5],
          isCustom: true,
        );
        await container
            .read(customCoursesProvider(null).notifier)
            .addCourse(courseB);

        final updatedCoursesB = await container.read(
          customCoursesProvider(null).future,
        );
        expect(updatedCoursesB, hasLength(1));
        expect(updatedCoursesB.first.name, 'Account B Physics');

        // Switch back to Account A
        container.read(credentialsProvider.notifier).set('student_a', 'secret');
        final restoredCoursesA = await container.read(
          customCoursesProvider(null).future,
        );
        expect(restoredCoursesA, hasLength(1));
        expect(restoredCoursesA.first.name, 'Account A Math');
      },
    );

    test(
      '4. Dorm Room & Campus selection is strictly isolated per account ID',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        // Account A login
        container.read(credentialsProvider.notifier).set('dorm_user_1', 'pass');

        const roomA = DormRoom(
          campusName: '科学城校区',
          garden: DormGarden.deYuan,
          buildingNumber: 8,
          roomNumber: '0302',
        );

        await container.read(dormRoomProvider.notifier).set(roomA);
        final readRoomA = await container.read(dormRoomProvider.future);
        expect(readRoomA, isNotNull);
        expect(readRoomA?.campusName, '科学城校区');
        expect(readRoomA?.garden, DormGarden.deYuan);
        expect(readRoomA?.buildingNumber, 8);
        expect(readRoomA?.roomNumber, '0302');

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('user_dorm_user_1_dorm_campus'), '科学城校区');
        expect(prefs.getString('user_dorm_user_1_dorm_garden'), 'deYuan');
        expect(prefs.getString('user_dorm_user_1_dorm_number'), '8');
        expect(prefs.getString('user_dorm_user_1_dorm_roomid'), '0302');

        // Switch to Account B
        container.read(credentialsProvider.notifier).set('dorm_user_2', 'pass');
        final readRoomB = await container.read(dormRoomProvider.future);
        expect(
          readRoomB,
          isNull,
          reason: 'Account B must not inherit Account A dorm room',
        );

        const roomB = DormRoom(
          campusName: '科学城校区',
          garden: DormGarden.liYuan,
          buildingNumber: 6,
          roomNumber: '0501',
        );
        await container.read(dormRoomProvider.notifier).set(roomB);
        final updatedRoomB = await container.read(dormRoomProvider.future);
        expect(updatedRoomB?.campusName, '科学城校区');
        expect(updatedRoomB?.garden, DormGarden.liYuan);
        expect(updatedRoomB?.buildingNumber, 6);
        expect(updatedRoomB?.roomNumber, '0501');

        // Switch back to Account A
        container.read(credentialsProvider.notifier).set('dorm_user_1', 'pass');
        final restoredRoomA = await container.read(dormRoomProvider.future);
        expect(restoredRoomA?.campusName, '科学城校区');
        expect(restoredRoomA?.garden, DormGarden.deYuan);
        expect(restoredRoomA?.buildingNumber, 8);
        expect(restoredRoomA?.roomNumber, '0302');
      },
    );

    test(
      '5. Unauthenticated / Guest fallback handles data isolation using guest namespace',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        // Unauthenticated state (credentialsProvider is null)
        expect(container.read(credentialsProvider), isNull);

        // Modify preference as guest
        await container
            .read(scheduleSundayFirstProvider.notifier)
            .setSundayFirst(true);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool('user_default_schedule_sunday_first'), isTrue);

        // Log in as user_authenticated
        container
            .read(credentialsProvider.notifier)
            .set('user_authenticated', 'pass');
        final userSundayFirst = await container.read(
          scheduleSundayFirstProvider.future,
        );
        expect(
          userSundayFirst,
          isFalse,
          reason: 'Logged-in user must not pollute/share guest preference',
        );

        // Clear credentials (logout)
        container.read(credentialsProvider.notifier).clear();
        final guestSundayFirst = await container.read(
          scheduleSundayFirstProvider.future,
        );
        expect(
          guestSundayFirst,
          isTrue,
          reason: 'Guest preference restored when logging out',
        );
      },
    );

    test(
      '6. Legacy un-prefixed keys fall back gracefully when account-scoped key is absent',
      () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('schedule_sunday_first', true);
        await prefs.setInt('schedule_total_weeks_2026-2027-1', 18);
        await prefs.setString('dorm_campus', '科学城校区');
        await prefs.setString('dorm_garden', 'deYuan');
        await prefs.setString('dorm_number', '3');
        await prefs.setString('dorm_roomid', '0101');

        final container = ProviderContainer();
        addTearDown(container.dispose);

        await container
            .read(semesterStartProvider.notifier)
            .set(DateTime(2026, 9, 1));

        // Login as legacy_user
        container.read(credentialsProvider.notifier).set('legacy_user', 'pass');

        // Reads should fall back to legacy keys
        final sundayFirst = await container.read(
          scheduleSundayFirstProvider.future,
        );
        expect(sundayFirst, isTrue);

        final totalWeeks = await container.read(
          semesterTotalWeeksProvider(null).future,
        );
        expect(totalWeeks, 18);

        final dorm = await container.read(dormRoomProvider.future);
        expect(dorm?.campusName, '科学城校区');
        expect(dorm?.garden, DormGarden.deYuan);
        expect(dorm?.buildingNumber, 3);
        expect(dorm?.roomNumber, '0101');

        // Updating setting should write to scoped key
        await container
            .read(scheduleSundayFirstProvider.notifier)
            .setSundayFirst(false);
        expect(
          prefs.getBool('user_legacy_user_schedule_sunday_first'),
          isFalse,
        );
      },
    );
  });
}
