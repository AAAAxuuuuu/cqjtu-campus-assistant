import 'package:campus_app/features/auth/auth_providers.dart';
import 'package:campus_app/features/schedule/schedule_providers.dart';
import 'package:core/models/course.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Empirical Challenge Task 1: Rapid Multi-Semester Switches (5+ Semesters)', () {
    test('Sequential CRUD and rapid switching across 10 semesters with zero data leakage', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(credentialsProvider.notifier).set('user_empirical', 'pass');

      final semesters = List.generate(10, (i) => '${2020 + i}-${2021 + i}-${(i % 2) + 1}');

      // Phase 1: Populate each semester with unique custom courses and total weeks
      for (int i = 0; i < semesters.length; i++) {
        final sem = semesters[i];
        await container.read(selectedScheduleSemesterProvider.notifier).set(sem);

        // Add 2 courses per semester
        final c1 = Course(
          name: 'Course A ($sem)',
          teacher: 'Teacher A',
          timeStr: 'Mon 1-2',
          classroom: 'Room A',
          dayOfWeek: 1,
          timeSlot: 1,
          endTimeSlot: 2,
          weekList: [1, 2],
          isCustom: true,
        );
        final c2 = Course(
          name: 'Course B ($sem)',
          teacher: 'Teacher B',
          timeStr: 'Tue 3-4',
          classroom: 'Room B',
          dayOfWeek: 2,
          timeSlot: 3,
          endTimeSlot: 4,
          weekList: [3, 4],
          isCustom: true,
        );

        await container.read(customCoursesProvider(null).notifier).addCourse(c1);
        await container.read(customCoursesProvider(null).notifier).addCourse(c2);

        // Set unique weeks count (between 12 and 30)
        final weeks = 12 + i;
        await container.read(semesterTotalWeeksProvider(null).notifier).setWeeks(weeks);
      }

      // Phase 2: Rapid random-access switching (50 switches) and strict verification
      for (int step = 0; step < 50; step++) {
        final index = (step * 7) % semesters.length;
        final sem = semesters[index];

        await container.read(selectedScheduleSemesterProvider.notifier).set(sem);

        final currentCourses = await container.read(customCoursesProvider(null).future);
        final currentWeeks = await container.read(semesterTotalWeeksProvider(null).future);

        expect(currentCourses, hasLength(2), reason: 'Semester $sem must have exactly 2 courses after rapid switch step $step');
        expect(currentCourses[0].name, 'Course A ($sem)');
        expect(currentCourses[1].name, 'Course B ($sem)');
        expect(currentWeeks, 12 + index, reason: 'Semester $sem must retain its set weeks count (${12 + index}) after rapid switch');
      }

      // Phase 3: SharedPreferences raw key inspection
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();

      // Ensure no fallback or corrupted keys exist
      for (final key in allKeys) {
        expect(key.contains('schedule_custom_courses_default'), isFalse, reason: 'Key $key contains old "default" fallback');
        expect(key.contains('schedule_total_weeks_default'), isFalse, reason: 'Key $key contains old "default" fallback');
        expect(key.contains('null'), isFalse, reason: 'Key $key contains "null" string fallback');
        expect(key.endsWith('_'), isFalse, reason: 'Key $key ends with empty prefix suffix');
      }
    });

    test('Rapid concurrent switching without awaiting notifier set completion', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final semesters = ['2023-2024-1', '2023-2024-2', '2024-2025-1', '2024-2025-2', '2025-2026-1'];

      // Fire 5 rapid set calls back to back
      final futures = semesters.map((s) => container.read(selectedScheduleSemesterProvider.notifier).set(s));
      await Future.wait(futures);

      // Final state should be the last setting ('2025-2026-1')
      final finalSem = await container.read(selectedScheduleSemesterProvider.future);
      expect(finalSem, '2025-2026-1');

      final key = await resolveSemesterKey(container.read(Provider((ref) => ref)), null);
      expect(key, '2025-2026-1');
    });
  });

  group('Empirical Challenge Task 2: Semester Start Date Modifications & Boundaries', () {
    test('Leap Years: Feb 28 vs Feb 29 (2024, 2028, 2000, 2096, 2100)', () {
      // 2024 (Leap year)
      expect(calculateSemester(DateTime(2024, 2, 28)), '2023-2024-2');
      expect(calculateSemester(DateTime(2024, 2, 29)), '2023-2024-2');
      expect(calculateSemester(DateTime(2024, 3, 1)), '2023-2024-2');

      // 2028 (Leap year)
      expect(calculateSemester(DateTime(2028, 2, 28)), '2027-2028-2');
      expect(calculateSemester(DateTime(2028, 2, 29)), '2027-2028-2');
      expect(calculateSemester(DateTime(2028, 3, 1)), '2027-2028-2');

      // 2000 (Leap century year)
      expect(calculateSemester(DateTime(2000, 2, 29)), '1999-2000-2');

      // 2100 (Non-leap century year)
      expect(calculateSemester(DateTime(2100, 2, 28)), '2099-2100-2');
      expect(calculateSemester(DateTime(2100, 3, 1)), '2099-2100-2');
    });

    test('Month and Year-End Boundaries: July 31/Aug 1, Dec 31/Jan 1, Jan 31/Feb 1', () {
      // July 31 -> Spring (month 7), Aug 1 -> Fall (month 8)
      expect(calculateSemester(DateTime(2026, 7, 31, 23, 59, 59)), '2025-2026-2');
      expect(calculateSemester(DateTime(2026, 8, 1, 0, 0, 0)), '2026-2027-1');

      // Dec 31 -> Fall (month 12), Jan 1 -> Fall (month 1 of previous academic year)
      expect(calculateSemester(DateTime(2026, 12, 31, 23, 59, 59)), '2026-2027-1');
      expect(calculateSemester(DateTime(2027, 1, 1, 0, 0, 0)), '2026-2027-1');

      // Jan 31 -> Fall (month 1), Feb 1 -> Spring (month 2)
      expect(calculateSemester(DateTime(2027, 1, 31, 23, 59, 59)), '2026-2027-1');
      expect(calculateSemester(DateTime(2027, 2, 1, 0, 0, 0)), '2026-2027-2');
    });

    test('Dynamic semesterStartProvider modification toggles custom course views across boundaries', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Start date set to 2026-07-31 -> 2025-2026-2
      await container.read(semesterStartProvider.notifier).set(DateTime(2026, 7, 31));

      const courseSpring = Course(
        name: 'Spring Course 2026',
        teacher: 'Teacher S',
        timeStr: 'Mon 1-2',
        classroom: 'S1',
        dayOfWeek: 1,
        timeSlot: 1,
        endTimeSlot: 2,
        weekList: [1],
        isCustom: true,
      );
      await container.read(customCoursesProvider(null).notifier).addCourse(courseSpring);

      var courses = await container.read(customCoursesProvider(null).future);
      expect(courses, hasLength(1));
      expect(courses.first.name, 'Spring Course 2026');

      // Change start date across month boundary to 2026-08-01 -> 2026-2027-1
      await container.read(semesterStartProvider.notifier).set(DateTime(2026, 8, 1));

      courses = await container.read(customCoursesProvider(null).future);
      expect(courses, isEmpty, reason: 'Aug 1 is Fall semester 2026-2027-1, Spring courses should not be visible');

      // Add a Fall course
      const courseFall = Course(
        name: 'Fall Course 2026',
        teacher: 'Teacher F',
        timeStr: 'Mon 1-2',
        classroom: 'F1',
        dayOfWeek: 1,
        timeSlot: 1,
        endTimeSlot: 2,
        weekList: [1],
        isCustom: true,
      );
      await container.read(customCoursesProvider(null).notifier).addCourse(courseFall);

      // Move start date to Dec 31, 2026 (still Fall 2026-2027-1)
      await container.read(semesterStartProvider.notifier).set(DateTime(2026, 12, 31));

      courses = await container.read(customCoursesProvider(null).future);
      expect(courses, hasLength(1));
      expect(courses.first.name, 'Fall Course 2026');

      // Move start date to Jan 31, 2027 (still Fall 2026-2027-1)
      await container.read(semesterStartProvider.notifier).set(DateTime(2027, 1, 31));

      courses = await container.read(customCoursesProvider(null).future);
      expect(courses, hasLength(1));
      expect(courses.first.name, 'Fall Course 2026');

      // Move start date to Feb 1, 2027 (Spring 2026-2027-2)
      await container.read(semesterStartProvider.notifier).set(DateTime(2027, 2, 1));

      courses = await container.read(customCoursesProvider(null).future);
      expect(courses, isEmpty);

      // Move back to July 31, 2026 (Spring 2025-2026-2)
      await container.read(semesterStartProvider.notifier).set(DateTime(2026, 7, 31));

      courses = await container.read(customCoursesProvider(null).future);
      expect(courses, hasLength(1));
      expect(courses.first.name, 'Spring Course 2026');
    });

    test('Interaction between selectedScheduleSemesterProvider and activeSemesterStartProvider', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Default start date set to 2026-09-01
      await container.read(semesterStartProvider.notifier).set(DateTime(2026, 9, 1));
      await container.read(selectedScheduleSemesterProvider.future);

      // activeSemesterStartProvider should be 2026-09-01 when selected is null
      final activeDefault = container.read(activeSemesterStartProvider).valueOrNull;
      expect(activeDefault, DateTime(2026, 9, 1));

      // Select explicit semester '2027-2028-1'
      await container.read(selectedScheduleSemesterProvider.notifier).set('2027-2028-1');

      // Set start date specifically for '2027-2028-1'
      await container.read(semesterStartForKeyProvider('2027-2028-1').notifier).set(DateTime(2027, 9, 6));

      final activeForSelected = container.read(activeSemesterStartProvider).valueOrNull;
      expect(activeForSelected, DateTime(2027, 9, 6));

      // Changing default semesterStartProvider now should NOT change activeSemesterStartProvider while selected is set
      await container.read(semesterStartProvider.notifier).set(DateTime(2026, 10, 1));

      final activeUnchanged = container.read(activeSemesterStartProvider).valueOrNull;
      expect(activeUnchanged, DateTime(2027, 9, 6));
    });
  });

  group('Empirical Challenge Task 3: Custom Courses CRUD, Semester Weeks & Stale Key Fallbacks', () {
    test('Adding and removing custom courses across explicit family arguments vs null', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Selected semester is null, start date is 2026-09-01 -> 2026-2027-1
      await container.read(semesterStartProvider.notifier).set(DateTime(2026, 9, 1));

      const course1 = Course(
        name: 'Math',
        teacher: 'T1',
        timeStr: 'Mon 1-2',
        classroom: 'R1',
        dayOfWeek: 1,
        timeSlot: 1,
        endTimeSlot: 2,
        weekList: [1],
        isCustom: true,
      );
      const course2 = Course(
        name: 'Physics',
        teacher: 'T2',
        timeStr: 'Tue 1-2',
        classroom: 'R2',
        dayOfWeek: 2,
        timeSlot: 1,
        endTimeSlot: 2,
        weekList: [1],
        isCustom: true,
      );

      // Add courses to null arg
      await container.read(customCoursesProvider(null).notifier).addCourse(course1);
      await container.read(customCoursesProvider(null).notifier).addCourse(course2);

      var list = await container.read(customCoursesProvider(null).future);
      expect(list, hasLength(2));

      // Remove course1 using null arg
      await container.read(customCoursesProvider(null).notifier).removeCourse(course1);

      list = await container.read(customCoursesProvider(null).future);
      expect(list, hasLength(1));
      expect(list.first.name, 'Physics');

      // Add course to explicit family key '2026-2027-2'
      await container.read(customCoursesProvider('2026-2027-2').notifier).addCourse(course1);

      final listExplicit = await container.read(customCoursesProvider('2026-2027-2').future);
      expect(listExplicit, hasLength(1));
      expect(listExplicit.first.name, 'Math');

      // Null arg (pointing to 2026-2027-1) must still contain only Physics
      final listNullStillSem1 = await container.read(customCoursesProvider(null).future);
      expect(listNullStillSem1, hasLength(1));
      expect(listNullStillSem1.first.name, 'Physics');

      // Clear courses for null arg (2026-2027-1)
      await container.read(customCoursesProvider(null).notifier).clearCourses();
      expect(await container.read(customCoursesProvider(null).future), isEmpty);

      // 2026-2027-2 must remain untouched
      expect(await container.read(customCoursesProvider('2026-2027-2').future), hasLength(1));
    });

    test('Semester total weeks bounds enforcement (min 12, max 30, default 20)', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(selectedScheduleSemesterProvider.notifier).set('2026-2027-1');

      // Initial value default 20
      expect(await container.read(semesterTotalWeeksProvider('2026-2027-1').future), 20);

      // Test lower bound clamp: setting 0 -> 12
      await container.read(semesterTotalWeeksProvider('2026-2027-1').notifier).setWeeks(0);
      expect(await container.read(semesterTotalWeeksProvider('2026-2027-1').future), 12);

      // Test upper bound clamp: setting 99 -> 30
      await container.read(semesterTotalWeeksProvider('2026-2027-1').notifier).setWeeks(99);
      expect(await container.read(semesterTotalWeeksProvider('2026-2027-1').future), 30);

      // Test normal value: setting 18 -> 18
      await container.read(semesterTotalWeeksProvider('2026-2027-1').notifier).setWeeks(18);
      expect(await container.read(semesterTotalWeeksProvider('2026-2027-1').future), 18);
    });

    test('Absence of stale key fallbacks in SharedPreferences', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Set explicit date to 2026-09-01
      await container.read(semesterStartProvider.notifier).set(DateTime(2026, 9, 1));
      await container.read(semesterTotalWeeksProvider(null).notifier).setWeeks(16);
      await container.read(customCoursesProvider(null).notifier).addCourse(
        const Course(
          name: 'Sanity Course',
          teacher: 'T',
          timeStr: 'Mon 1-2',
          classroom: 'C',
          dayOfWeek: 1,
          timeSlot: 1,
          endTimeSlot: 2,
          weekList: [1],
          isCustom: true,
        ),
      );

      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();

      // Check exact keys written
      expect(keys.contains('user_default_schedule_total_weeks_2026-2027-1'), isTrue);
      expect(keys.contains('user_default_schedule_custom_courses_2026-2027-1'), isTrue);

      // Reject any invalid or stale keys
      expect(keys.contains('schedule_custom_courses_default'), isFalse);
      expect(keys.contains('schedule_total_weeks_default'), isFalse);
      expect(keys.contains('schedule_custom_courses_null'), isFalse);
      expect(keys.contains('schedule_total_weeks_null'), isFalse);
    });
  });
}
