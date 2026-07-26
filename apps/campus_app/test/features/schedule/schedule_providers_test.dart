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

  group('Custom Course Semester Scoping (R1)', () {
    test(
      'Test 1: Adding custom course when selectedScheduleSemesterProvider is null stores it scoped strictly to resolved semester key (e.g. 2026-2027-1)',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        // Set explicit semester start date to 2026-09-01 (Semester 2026-2027-1)
        await container
            .read(semesterStartProvider.notifier)
            .set(DateTime(2026, 9, 1));

        // Confirm selectedScheduleSemesterProvider is null (default mode)
        final selectedSemester = await container.read(
          selectedScheduleSemesterProvider.future,
        );
        expect(selectedSemester, isNull);

        // Create test course
        const testCourse = Course(
          name: 'Advanced Mathematics',
          teacher: 'Prof. Zhang',
          timeStr: 'Mon 1-2',
          classroom: 'A101',
          dayOfWeek: 1,
          timeSlot: 1,
          endTimeSlot: 2,
          weekList: [1, 2, 3, 4],
          isCustom: true,
        );

        // Add course via customCoursesProvider(null)
        await container
            .read(customCoursesProvider(null).notifier)
            .addCourse(testCourse);

        // Read custom courses for null argument
        final coursesForNull = await container.read(
          customCoursesProvider(null).future,
        );
        expect(coursesForNull, hasLength(1));
        expect(coursesForNull.first.name, 'Advanced Mathematics');

        // Check underlying SharedPreferences storage key
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.containsKey('user_default_schedule_custom_courses_2026-2027-1'),
          isTrue,
        );
        expect(
          prefs.containsKey('schedule_custom_courses_default'),
          isFalse,
        );
      },
    );

    test(
      'Test 2: Switching selectedScheduleSemesterProvider to 2026-2027-2 displays only courses for 2026-2027-2 (hiding 2026-2027-1 course)',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        // Set semester start date to 2026-09-01 (2026-2027-1)
        await container
            .read(semesterStartProvider.notifier)
            .set(DateTime(2026, 9, 1));

        // Add a course to 2026-2027-1 under default mode (null)
        const course1 = Course(
          name: 'Linear Algebra (Sem 1)',
          teacher: 'Prof. Li',
          timeStr: 'Tue 3-4',
          classroom: 'B202',
          dayOfWeek: 2,
          timeSlot: 3,
          endTimeSlot: 4,
          weekList: [1, 2, 3, 4],
          isCustom: true,
        );
        await container
            .read(customCoursesProvider(null).notifier)
            .addCourse(course1);

        // Verify course exists in default mode
        final initialCourses = await container.read(
          customCoursesProvider(null).future,
        );
        expect(initialCourses, hasLength(1));
        expect(initialCourses.first.name, 'Linear Algebra (Sem 1)');

        // Now switch selectedScheduleSemesterProvider to 2026-2027-2
        await container
            .read(selectedScheduleSemesterProvider.notifier)
            .set('2026-2027-2');

        // Verify customCoursesProvider(null) now resolves to 2026-2027-2 and returns empty
        final sem2Courses = await container.read(
          customCoursesProvider(null).future,
        );
        expect(sem2Courses, isEmpty);

        // Add a custom course for 2026-2027-2
        const course2 = Course(
          name: 'Physics Experiments (Sem 2)',
          teacher: 'Prof. Wang',
          timeStr: 'Wed 5-6',
          classroom: 'C303',
          dayOfWeek: 3,
          timeSlot: 5,
          endTimeSlot: 6,
          weekList: [1, 2, 3, 4],
          isCustom: true,
        );
        await container
            .read(customCoursesProvider(null).notifier)
            .addCourse(course2);

        final updatedSem2Courses = await container.read(
          customCoursesProvider(null).future,
        );
        expect(updatedSem2Courses, hasLength(1));
        expect(updatedSem2Courses.first.name, 'Physics Experiments (Sem 2)');

        // Switch back selectedScheduleSemesterProvider to 2026-2027-1
        await container
            .read(selectedScheduleSemesterProvider.notifier)
            .set('2026-2027-1');

        final switchedBackCourses = await container.read(
          customCoursesProvider(null).future,
        );
        expect(switchedBackCourses, hasLength(1));
        expect(switchedBackCourses.first.name, 'Linear Algebra (Sem 1)');
      },
    );

    test(
      'Test 3: Modifying semester start date re-binds current schedule without leaking custom courses across semesters',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        // Start with semester start date = 2026-09-01 (Semester 2026-2027-1)
        await container
            .read(semesterStartProvider.notifier)
            .set(DateTime(2026, 9, 1));

        const courseSem1 = Course(
          name: 'English Reading',
          teacher: 'Prof. Smith',
          timeStr: 'Thu 1-2',
          classroom: 'D404',
          dayOfWeek: 4,
          timeSlot: 1,
          endTimeSlot: 2,
          weekList: [1, 2, 3, 4],
          isCustom: true,
        );
        await container
            .read(customCoursesProvider(null).notifier)
            .addCourse(courseSem1);

        expect(
          await container.read(customCoursesProvider(null).future),
          hasLength(1),
        );

        // Modify semester start date to 2027-02-22 (Semester 2026-2027-2)
        await container
            .read(semesterStartProvider.notifier)
            .set(DateTime(2027, 2, 22));

        // Read customCoursesProvider(null) again - should be empty as it re-bound to 2026-2027-2
        final sem2Courses = await container.read(
          customCoursesProvider(null).future,
        );
        expect(sem2Courses, isEmpty);

        // Modify back to 2026-09-01 (Semester 2026-2027-1)
        await container
            .read(semesterStartProvider.notifier)
            .set(DateTime(2026, 9, 1));

        final restoredCourses = await container.read(
          customCoursesProvider(null).future,
        );
        expect(restoredCourses, hasLength(1));
        expect(restoredCourses.first.name, 'English Reading');
      },
    );

    test(
      'calculateSemester resolves correct academic semester strings from dates',
      () {
        expect(calculateSemester(DateTime(2026, 8, 1)), '2026-2027-1');
        expect(calculateSemester(DateTime(2026, 9, 1)), '2026-2027-1');
        expect(calculateSemester(DateTime(2026, 12, 31)), '2026-2027-1');
        expect(calculateSemester(DateTime(2027, 1, 15)), '2026-2027-1');
        expect(calculateSemester(DateTime(2027, 2, 1)), '2026-2027-2');
        expect(calculateSemester(DateTime(2027, 3, 15)), '2026-2027-2');
        expect(calculateSemester(DateTime(2027, 7, 31)), '2026-2027-2');
      },
    );

    test(
      'Stress Test 1: Leap year boundaries (Feb 29 2024 / 2028) & date adjustments within same semester',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        // Leap year 2024: Feb 29, 2024 is in semester 2023-2024-2
        expect(calculateSemester(DateTime(2024, 2, 28)), '2023-2024-2');
        expect(calculateSemester(DateTime(2024, 2, 29)), '2023-2024-2');
        expect(calculateSemester(DateTime(2024, 3, 1)), '2023-2024-2');
        expect(calculateSemester(DateTime(2028, 2, 29)), '2027-2028-2');

        // Set start date to Feb 28, 2024 (2023-2024-2)
        await container
            .read(semesterStartProvider.notifier)
            .set(DateTime(2024, 2, 28));

        const leapCourse = Course(
          name: 'Leap Year Seminar',
          teacher: 'Dr. Leap',
          timeStr: 'Fri 7-8',
          classroom: 'L101',
          dayOfWeek: 5,
          timeSlot: 7,
          endTimeSlot: 8,
          weekList: [1, 2],
          isCustom: true,
        );
        await container
            .read(customCoursesProvider(null).notifier)
            .addCourse(leapCourse);

        // Shift start date to Feb 29, 2024 (still 2023-2024-2)
        await container
            .read(semesterStartProvider.notifier)
            .set(DateTime(2024, 2, 29));

        // Course should still be retained because semester key 2023-2024-2 hasn't changed
        final coursesOnLeapDay = await container.read(
          customCoursesProvider(null).future,
        );
        expect(coursesOnLeapDay, hasLength(1));
        expect(coursesOnLeapDay.first.name, 'Leap Year Seminar');
      },
    );

    test(
      'Stress Test 2: December / January boundary conditions across New Year',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        // Dec 31, 2026 and Jan 1, 2027 both resolve to 2026-2027-1
        expect(calculateSemester(DateTime(2026, 12, 31)), '2026-2027-1');
        expect(calculateSemester(DateTime(2027, 1, 1)), '2026-2027-1');
        expect(calculateSemester(DateTime(2027, 1, 31)), '2026-2027-1');
        expect(calculateSemester(DateTime(2027, 2, 1)), '2026-2027-2');

        // Set start date to Dec 31, 2026
        await container
            .read(semesterStartProvider.notifier)
            .set(DateTime(2026, 12, 31));

        const decCourse = Course(
          name: 'New Year Workshop',
          teacher: 'Prof. Winter',
          timeStr: 'Mon 1-2',
          classroom: 'W001',
          dayOfWeek: 1,
          timeSlot: 1,
          endTimeSlot: 2,
          weekList: [1],
          isCustom: true,
        );
        await container
            .read(customCoursesProvider(null).notifier)
            .addCourse(decCourse);

        // Move start date to Jan 15, 2027 (same semester 2026-2027-1)
        await container
            .read(semesterStartProvider.notifier)
            .set(DateTime(2027, 1, 15));

        var coursesInJan = await container.read(
          customCoursesProvider(null).future,
        );
        expect(coursesInJan, hasLength(1));
        expect(coursesInJan.first.name, 'New Year Workshop');

        // Move start date to Feb 1, 2027 (crosses boundary into 2026-2027-2)
        await container
            .read(semesterStartProvider.notifier)
            .set(DateTime(2027, 2, 1));

        var coursesInFeb = await container.read(
          customCoursesProvider(null).future,
        );
        expect(coursesInFeb, isEmpty);
      },
    );

    test(
      'Stress Test 3: Multi-semester rapid switching sequence across 5 semesters with zero leakage',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        // 1. Semester 2024-2025-1
        await container
            .read(selectedScheduleSemesterProvider.notifier)
            .set('2024-2025-1');
        await container.read(customCoursesProvider(null).notifier).addCourse(
              const Course(
                name: 'Course 2024-2025-1',
                teacher: 'T1',
                timeStr: 'Mon 1-2',
                classroom: 'C1',
                dayOfWeek: 1,
                timeSlot: 1,
                endTimeSlot: 2,
                weekList: [1],
                isCustom: true,
              ),
            );

        // 2. Semester 2024-2025-2
        await container
            .read(selectedScheduleSemesterProvider.notifier)
            .set('2024-2025-2');
        await container.read(customCoursesProvider(null).notifier).addCourse(
              const Course(
                name: 'Course 2024-2025-2',
                teacher: 'T2',
                timeStr: 'Tue 1-2',
                classroom: 'C2',
                dayOfWeek: 2,
                timeSlot: 1,
                endTimeSlot: 2,
                weekList: [1],
                isCustom: true,
              ),
            );

        // 3. Semester 2025-2026-1
        await container
            .read(selectedScheduleSemesterProvider.notifier)
            .set('2025-2026-1');
        await container.read(customCoursesProvider(null).notifier).addCourse(
              const Course(
                name: 'Course 2025-2026-1',
                teacher: 'T3',
                timeStr: 'Wed 1-2',
                classroom: 'C3',
                dayOfWeek: 3,
                timeSlot: 1,
                endTimeSlot: 2,
                weekList: [1],
                isCustom: true,
              ),
            );

        // 4. Semester 2025-2026-2
        await container
            .read(selectedScheduleSemesterProvider.notifier)
            .set('2025-2026-2');
        await container.read(customCoursesProvider(null).notifier).addCourse(
              const Course(
                name: 'Course 2025-2026-2',
                teacher: 'T4',
                timeStr: 'Thu 1-2',
                classroom: 'C4',
                dayOfWeek: 4,
                timeSlot: 1,
                endTimeSlot: 2,
                weekList: [1],
                isCustom: true,
              ),
            );

        // 5. Semester 2026-2027-1
        await container
            .read(selectedScheduleSemesterProvider.notifier)
            .set('2026-2027-1');
        await container.read(customCoursesProvider(null).notifier).addCourse(
              const Course(
                name: 'Course 2026-2027-1',
                teacher: 'T5',
                timeStr: 'Fri 1-2',
                classroom: 'C5',
                dayOfWeek: 5,
                timeSlot: 1,
                endTimeSlot: 2,
                weekList: [1],
                isCustom: true,
              ),
            );

        // Verify each semester in rapid succession
        final semesters = [
          ('2024-2025-1', 'Course 2024-2025-1'),
          ('2024-2025-2', 'Course 2024-2025-2'),
          ('2025-2026-1', 'Course 2025-2026-1'),
          ('2025-2026-2', 'Course 2025-2026-2'),
          ('2026-2027-1', 'Course 2026-2027-1'),
        ];

        for (final (semKey, expectedName) in semesters) {
          await container
              .read(selectedScheduleSemesterProvider.notifier)
              .set(semKey);
          final courses = await container.read(
            customCoursesProvider(null).future,
          );
          expect(courses, hasLength(1));
          expect(courses.first.name, expectedName);
        }

        // Test deletion in one semester (2025-2026-1) doesn't affect others
        await container
            .read(selectedScheduleSemesterProvider.notifier)
            .set('2025-2026-1');
        final courseToRemove =
            (await container.read(customCoursesProvider(null).future)).first;
        await container
            .read(customCoursesProvider(null).notifier)
            .removeCourse(courseToRemove);

        expect(
          await container.read(customCoursesProvider(null).future),
          isEmpty,
        );

        // Check 2024-2025-1 still has its course
        await container
            .read(selectedScheduleSemesterProvider.notifier)
            .set('2024-2025-1');
        expect(
          await container.read(customCoursesProvider(null).future),
          hasLength(1),
        );
      },
    );

    test(
      'Stress Test 4: Total weeks provider scoping per semester',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        // Set total weeks for 2026-2027-1 to 16
        await container
            .read(selectedScheduleSemesterProvider.notifier)
            .set('2026-2027-1');
        await container
            .read(semesterTotalWeeksProvider(null).notifier)
            .setWeeks(16);

        expect(
          await container.read(semesterTotalWeeksProvider(null).future),
          16,
        );

        // Switch to 2026-2027-2 and set total weeks to 18
        await container
            .read(selectedScheduleSemesterProvider.notifier)
            .set('2026-2027-2');
        await container
            .read(semesterTotalWeeksProvider(null).notifier)
            .setWeeks(18);

        expect(
          await container.read(semesterTotalWeeksProvider(null).future),
          18,
        );

        // Switch back to 2026-2027-1 and verify total weeks is still 16
        await container
            .read(selectedScheduleSemesterProvider.notifier)
            .set('2026-2027-1');
        expect(
          await container.read(semesterTotalWeeksProvider(null).future),
          16,
        );
      },
    );
  });
}
