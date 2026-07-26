import 'dart:convert';

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

  group('Requirement R2: Account ID Based Preferences & Data Isolation', () {
    test('userScopedKey formats keys correctly with fallback to default', () {
      expect(
        userScopedKey('userA', 'schedule_sunday_first'),
        'user_userA_schedule_sunday_first',
      );
      expect(
        userScopedKey('20230001', 'dorm_campus'),
        'user_20230001_dorm_campus',
      );
      expect(
        userScopedKey('', 'schedule_sunday_first'),
        'user_default_schedule_sunday_first',
      );
      expect(
        userScopedKey('  ', 'dorm_roomid'),
        'user_default_dorm_roomid',
      );
    });

    test(
      'Multi-account isolation: userA preferences & custom courses are isolated from userB and restored cleanly upon switch',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        // 1. Log in as userA
        container.read(credentialsProvider.notifier).set('userA', 'passA');

        // Set userA preferences
        await container
            .read(scheduleSundayFirstProvider.notifier)
            .setSundayFirst(true);
        await container
            .read(semesterTotalWeeksProvider(null).notifier)
            .setWeeks(22);

        const dormA = DormRoom(
          campusName: '科学城校区',
          garden: DormGarden.deYuan,
          buildingNumber: 8,
          roomNumber: '0305',
        );
        await container.read(dormRoomProvider.notifier).set(dormA);

        const courseA = Course(
          name: 'Data Structures (User A)',
          teacher: 'Prof. Alice',
          timeStr: 'Mon 1-2',
          classroom: 'A101',
          dayOfWeek: 1,
          timeSlot: 1,
          endTimeSlot: 2,
          weekList: [1, 2, 3, 4],
          isCustom: true,
        );
        await container
            .read(customCoursesProvider(null).notifier)
            .addCourse(courseA);

        // Assert userA settings
        expect(
          await container.read(scheduleSundayFirstProvider.future),
          isTrue,
        );
        expect(
          await container.read(semesterTotalWeeksProvider(null).future),
          22,
        );

        final userADorm = await container.read(dormRoomProvider.future);
        expect(userADorm, isNotNull);
        expect(userADorm!.buildingFullName, '德园8舍');
        expect(userADorm.roomNumber, '0305');

        final userACourses =
            await container.read(customCoursesProvider(null).future);
        expect(userACourses, hasLength(1));
        expect(userACourses.first.name, 'Data Structures (User A)');

        // 2. Switch credentialsProvider to userB
        container.read(credentialsProvider.notifier).set('userB', 'passB');

        // Assert userB receives clean default preferences and empty custom courses list
        expect(
          await container.read(scheduleSundayFirstProvider.future),
          isFalse,
        );
        expect(
          await container.read(semesterTotalWeeksProvider(null).future),
          20,
        );
        expect(await container.read(dormRoomProvider.future), isNull);
        expect(
          await container.read(customCoursesProvider(null).future),
          isEmpty,
        );

        // Set distinct userB preferences
        await container
            .read(semesterTotalWeeksProvider(null).notifier)
            .setWeeks(16);
        const dormB = DormRoom(
          campusName: '科学城校区',
          garden: DormGarden.liYuan,
          buildingNumber: 6,
          roomNumber: '0202',
        );
        await container.read(dormRoomProvider.notifier).set(dormB);
        const courseB = Course(
          name: 'Operating Systems (User B)',
          teacher: 'Prof. Bob',
          timeStr: 'Tue 3-4',
          classroom: 'B202',
          dayOfWeek: 2,
          timeSlot: 3,
          endTimeSlot: 4,
          weekList: [1, 2],
          isCustom: true,
        );
        await container
            .read(customCoursesProvider(null).notifier)
            .addCourse(courseB);

        expect(
          await container.read(semesterTotalWeeksProvider(null).future),
          16,
        );
        final userBDorm = await container.read(dormRoomProvider.future);
        expect(userBDorm!.buildingFullName, '礼园6舍');
        final userBCourses =
            await container.read(customCoursesProvider(null).future);
        expect(userBCourses, hasLength(1));
        expect(userBCourses.first.name, 'Operating Systems (User B)');

        // 3. Switch back to userA
        container.read(credentialsProvider.notifier).set('userA', 'passA');

        // Assert userA preferences and custom courses are restored cleanly
        expect(
          await container.read(scheduleSundayFirstProvider.future),
          isTrue,
        );
        expect(
          await container.read(semesterTotalWeeksProvider(null).future),
          22,
        );

        final restoredUserADorm =
            await container.read(dormRoomProvider.future);
        expect(restoredUserADorm, isNotNull);
        expect(restoredUserADorm!.buildingFullName, '德园8舍');
        expect(restoredUserADorm.roomNumber, '0305');

        final restoredUserACourses =
            await container.read(customCoursesProvider(null).future);
        expect(restoredUserACourses, hasLength(1));
        expect(restoredUserACourses.first.name, 'Data Structures (User A)');
      },
    );

    test(
      'Backward compatibility: falls back to legacy un-prefixed keys when scoped keys are absent',
      () async {
        // Seed SharedPreferences with legacy un-prefixed keys
        SharedPreferences.setMockInitialValues({
          'schedule_sunday_first': true,
          'schedule_total_weeks_2026-2027-1': 18,
          'dorm_campus': '科学城校区',
          'dorm_garden': 'deYuan',
          'dorm_number': '5',
          'dorm_roomid': '0101',
          'schedule_custom_courses_2026-2027-1': jsonEncode([
            const Course(
              name: 'Legacy Course',
              teacher: 'Prof. Legacy',
              timeStr: 'Wed 1-2',
              classroom: 'L100',
              dayOfWeek: 3,
              timeSlot: 1,
              endTimeSlot: 2,
              weekList: [1],
              isCustom: true,
            ).toJson(),
          ]),
        });

        final container = ProviderContainer();
        addTearDown(container.dispose);

        // Set explicit semester start so semesterKey resolves to 2026-2027-1
        await container
            .read(semesterStartProvider.notifier)
            .set(DateTime(2026, 9, 1));

        // Log in as userC (has no scoped keys yet)
        container.read(credentialsProvider.notifier).set('userC', 'passC');

        // Providers should load legacy values
        expect(
          await container.read(scheduleSundayFirstProvider.future),
          isTrue,
        );
        expect(
          await container.read(semesterTotalWeeksProvider('2026-2027-1').future),
          18,
        );
        final dorm = await container.read(dormRoomProvider.future);
        expect(dorm, isNotNull);
        expect(dorm!.buildingFullName, '德园5舍');
        final courses = await container.read(
          customCoursesProvider('2026-2027-1').future,
        );
        expect(courses, hasLength(1));
        expect(courses.first.name, 'Legacy Course');
      },
    );

    test(
      'Unauthenticated / guest mode uses fallback user_default_* key scope',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        // Ensure credentialsProvider is null
        container.read(credentialsProvider.notifier).clear();

        await container
            .read(scheduleSundayFirstProvider.notifier)
            .setSundayFirst(true);
        expect(
          await container.read(scheduleSundayFirstProvider.future),
          isTrue,
        );

        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.containsKey('user_default_schedule_sunday_first'),
          isTrue,
        );
      },
    );
  });
}
