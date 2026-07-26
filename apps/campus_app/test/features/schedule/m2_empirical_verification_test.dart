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

  group('Milestone 2 Empirical Verification: Account ID Isolation & Concurrency', () {
    test(
      'Scenario 1: Rapid sequential account switches (Account A -> Account B -> Guest -> Account A)',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        const dormA = DormRoom(
          campusName: '科学城校区',
          garden: DormGarden.deYuan,
          buildingNumber: 8,
          roomNumber: '0305',
        );

        const dormB = DormRoom(
          campusName: '科学城校区',
          garden: DormGarden.liYuan,
          buildingNumber: 6,
          roomNumber: '0202',
        );

        const dormGuest = DormRoom(
          campusName: '科学城校区',
          garden: DormGarden.deYuan,
          buildingNumber: 1,
          roomNumber: '0101',
        );

        const courseA = Course(
          name: 'Account A Course',
          teacher: 'Teacher A',
          timeStr: 'Mon 1-2',
          classroom: 'A101',
          dayOfWeek: 1,
          timeSlot: 1,
          endTimeSlot: 2,
          weekList: [1, 2, 3],
          isCustom: true,
        );

        const courseB = Course(
          name: 'Account B Course',
          teacher: 'Teacher B',
          timeStr: 'Tue 3-4',
          classroom: 'B202',
          dayOfWeek: 2,
          timeSlot: 3,
          endTimeSlot: 4,
          weekList: [4, 5, 6],
          isCustom: true,
        );

        const courseGuest = Course(
          name: 'Guest Course',
          teacher: 'Teacher Guest',
          timeStr: 'Wed 5-6',
          classroom: 'G303',
          dayOfWeek: 3,
          timeSlot: 5,
          endTimeSlot: 6,
          weekList: [7, 8, 9],
          isCustom: true,
        );

        // --- Step 1: Populate preferences for Account A ---
        container.read(credentialsProvider.notifier).set('userA', 'passA');
        await container.read(scheduleSundayFirstProvider.notifier).setSundayFirst(true);
        await container.read(semesterTotalWeeksProvider(null).notifier).setWeeks(24);
        await container.read(dormRoomProvider.notifier).set(dormA);
        await container.read(customCoursesProvider(null).notifier).addCourse(courseA);

        // --- Step 2: Populate preferences for Account B ---
        container.read(credentialsProvider.notifier).set('userB', 'passB');
        await container.read(scheduleSundayFirstProvider.notifier).setSundayFirst(false);
        await container.read(semesterTotalWeeksProvider(null).notifier).setWeeks(16);
        await container.read(dormRoomProvider.notifier).set(dormB);
        await container.read(customCoursesProvider(null).notifier).addCourse(courseB);

        // --- Step 3: Populate preferences for Guest Mode ---
        container.read(credentialsProvider.notifier).clear();
        await container.read(scheduleSundayFirstProvider.notifier).setSundayFirst(true);
        await container.read(semesterTotalWeeksProvider(null).notifier).setWeeks(18);
        await container.read(dormRoomProvider.notifier).set(dormGuest);
        await container.read(customCoursesProvider(null).notifier).addCourse(courseGuest);

        // --- Step 4: Rapid sequential switching loop (20 iterations) ---
        for (int cycle = 0; cycle < 20; cycle++) {
          // Switch to Account A
          container.read(credentialsProvider.notifier).set('userA', 'passA');
          expect(await container.read(scheduleSundayFirstProvider.future), isTrue);
          expect(await container.read(semesterTotalWeeksProvider(null).future), equals(24));
          final readDormA = await container.read(dormRoomProvider.future);
          expect(readDormA?.roomNumber, equals('0305'));
          final readCoursesA = await container.read(customCoursesProvider(null).future);
          expect(readCoursesA, hasLength(1));
          expect(readCoursesA.first.name, equals('Account A Course'));

          // Switch to Account B
          container.read(credentialsProvider.notifier).set('userB', 'passB');
          expect(await container.read(scheduleSundayFirstProvider.future), isFalse);
          expect(await container.read(semesterTotalWeeksProvider(null).future), equals(16));
          final readDormB = await container.read(dormRoomProvider.future);
          expect(readDormB?.roomNumber, equals('0202'));
          final readCoursesB = await container.read(customCoursesProvider(null).future);
          expect(readCoursesB, hasLength(1));
          expect(readCoursesB.first.name, equals('Account B Course'));

          // Switch to Guest
          container.read(credentialsProvider.notifier).clear();
          expect(await container.read(scheduleSundayFirstProvider.future), isTrue);
          expect(await container.read(semesterTotalWeeksProvider(null).future), equals(18));
          final readDormGuest = await container.read(dormRoomProvider.future);
          expect(readDormGuest?.roomNumber, equals('0101'));
          final readCoursesGuest = await container.read(customCoursesProvider(null).future);
          expect(readCoursesGuest, hasLength(1));
          expect(readCoursesGuest.first.name, equals('Guest Course'));
        }
      },
    );

    test(
      'Scenario 2: Concurrent preference updates across accounts in isolated containers',
      () async {
        final containerA = ProviderContainer();
        final containerB = ProviderContainer();
        addTearDown(containerA.dispose);
        addTearDown(containerB.dispose);

        containerA.read(credentialsProvider.notifier).set('accountA', 'passA');
        containerB.read(credentialsProvider.notifier).set('accountB', 'passB');

        const courseA = Course(
          name: 'Concurrent Course A',
          teacher: 'Teacher A',
          timeStr: 'Mon 1-2',
          classroom: 'A101',
          dayOfWeek: 1,
          timeSlot: 1,
          endTimeSlot: 2,
          weekList: [1, 2],
          isCustom: true,
        );

        const courseB = Course(
          name: 'Concurrent Course B',
          teacher: 'Teacher B',
          timeStr: 'Tue 3-4',
          classroom: 'B202',
          dayOfWeek: 2,
          timeSlot: 3,
          endTimeSlot: 4,
          weekList: [3, 4],
          isCustom: true,
        );

        // Execute concurrent asynchronous sets across Account A and Account B
        await Future.wait([
          containerA.read(scheduleSundayFirstProvider.notifier).setSundayFirst(true),
          containerB.read(scheduleSundayFirstProvider.notifier).setSundayFirst(false),
          containerA.read(semesterTotalWeeksProvider('2026-2027-1').notifier).setWeeks(25),
          containerB.read(semesterTotalWeeksProvider('2026-2027-1').notifier).setWeeks(15),
          containerA.read(customCoursesProvider('2026-2027-1').notifier).addCourse(courseA),
          containerB.read(customCoursesProvider('2026-2027-1').notifier).addCourse(courseB),
        ]);

        // Inspect SharedPreferences to ensure non-overlapping key spaces
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool('user_accountA_schedule_sunday_first'), isTrue);
        expect(prefs.getBool('user_accountB_schedule_sunday_first'), isFalse);
        expect(prefs.getInt('user_accountA_schedule_total_weeks_2026-2027-1'), equals(25));
        expect(prefs.getInt('user_accountB_schedule_total_weeks_2026-2027-1'), equals(15));
        expect(prefs.containsKey('user_accountA_schedule_custom_courses_2026-2027-1'), isTrue);
        expect(prefs.containsKey('user_accountB_schedule_custom_courses_2026-2027-1'), isTrue);

        final coursesA = await containerA.read(customCoursesProvider('2026-2027-1').future);
        final coursesB = await containerB.read(customCoursesProvider('2026-2027-1').future);

        expect(coursesA.map((c) => c.name), contains('Concurrent Course A'));
        expect(coursesA.map((c) => c.name), isNot(contains('Concurrent Course B')));
        expect(coursesB.map((c) => c.name), contains('Concurrent Course B'));
        expect(coursesB.map((c) => c.name), isNot(contains('Concurrent Course A')));
      },
    );

    test(
      'Scenario 3: Verification that course data for Account A never leaks into Account B state',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        // Populate 3 custom courses for userA
        container.read(credentialsProvider.notifier).set('userA', 'passA');
        for (int i = 1; i <= 3; i++) {
          await container.read(customCoursesProvider('2026-2027-1').notifier).addCourse(
                Course(
                  name: 'User A Course $i',
                  teacher: 'Teacher A',
                  timeStr: 'Mon $i',
                  classroom: 'A$i',
                  dayOfWeek: 1,
                  timeSlot: i,
                  endTimeSlot: i,
                  weekList: [i],
                  isCustom: true,
                ),
              );
        }

        // Switch to userB (which has no custom courses set)
        container.read(credentialsProvider.notifier).set('userB', 'passB');
        final userBCourses = await container.read(customCoursesProvider('2026-2027-1').future);
        expect(userBCourses, isEmpty, reason: "Account B state must be empty and free of Account A's courses");

        // Clear courses for userA
        container.read(credentialsProvider.notifier).set('userA', 'passA');
        await container.read(customCoursesProvider('2026-2027-1').notifier).clearCourses();
        final userACoursesAfterClear = await container.read(customCoursesProvider('2026-2027-1').future);
        expect(userACoursesAfterClear, isEmpty);
      },
    );
  });
}
