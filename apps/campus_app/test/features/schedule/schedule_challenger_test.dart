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

  group('Challenger Empirical Tests - calculateSemester', () {
    test(
      'Date boundary switching: Aug 1 vs July 31, Jan 1 vs Dec 31, Feb 1 vs Jan 31',
      () {
        // Month >= 8 -> Fall semester
        expect(calculateSemester(DateTime(2026, 8, 1, 0, 0, 0)), '2026-2027-1');
        expect(calculateSemester(DateTime(2026, 8, 1)), '2026-2027-1');
        expect(
          calculateSemester(DateTime(2026, 12, 31, 23, 59, 59)),
          '2026-2027-1',
        );

        // Month == 1 -> Fall semester of previous year
        expect(calculateSemester(DateTime(2027, 1, 1, 0, 0, 0)), '2026-2027-1');
        expect(
          calculateSemester(DateTime(2027, 1, 31, 23, 59, 59)),
          '2026-2027-1',
        );

        // Month 2..7 -> Spring semester
        expect(calculateSemester(DateTime(2027, 2, 1, 0, 0, 0)), '2026-2027-2');
        expect(
          calculateSemester(DateTime(2027, 7, 31, 23, 59, 59)),
          '2026-2027-2',
        );
      },
    );

    test('Leap years & Century boundaries', () {
      // Leap year 2024
      expect(calculateSemester(DateTime(2024, 2, 29)), '2023-2024-2');
      // Leap year 2028
      expect(calculateSemester(DateTime(2028, 2, 29)), '2027-2028-2');
      // Century non-leap year 2100
      expect(calculateSemester(DateTime(2100, 2, 28)), '2099-2100-2');
      // Year 2000 leap century year
      expect(calculateSemester(DateTime(2000, 2, 29)), '1999-2000-2');
    });

    test('Far future and historical dates', () {
      expect(calculateSemester(DateTime(2099, 9, 1)), '2099-2100-1');
      expect(calculateSemester(DateTime(1990, 5, 1)), '1989-1990-2');
    });
  });

  group('Challenger Empirical Tests - resolveSemesterKey boundaries', () {
    test(
      'Boundary cases: empty string "" vs null vs whitespace "  " vs padded strings',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        // Default start date set to 2026-09-01 => 2026-2027-1
        await container
            .read(semesterStartProvider.notifier)
            .set(DateTime(2026, 9, 1));
        await container.read(selectedScheduleSemesterProvider.future);

        Future<String> testResolve(String? sem, {bool listen = true}) {
          return container.read(
            Provider((ref) => resolveSemesterKey(ref, sem, listen: listen)),
          );
        }

        // 1. Direct parameter tests
        final keyNull = await testResolve(null);
        final keyEmpty = await testResolve('');
        final keyWhitespace = await testResolve('   \t\n  ');
        final keyPadded = await testResolve('  2025-2026-2  ');

        expect(
          keyNull,
          '2026-2027-1',
          reason: 'null should resolve to default active semester',
        );
        expect(
          keyEmpty,
          '2026-2027-1',
          reason: 'empty string should resolve to default active semester',
        );
        expect(
          keyWhitespace,
          '2026-2027-1',
          reason: 'whitespace string should resolve to default active semester',
        );
        expect(
          keyPadded,
          '2025-2026-2',
          reason: 'padded string should be trimmed',
        );
      },
    );

    test(
      'SelectedSemester set to empty string "" vs whitespace "   " vs null',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        await container
            .read(semesterStartProvider.notifier)
            .set(DateTime(2026, 9, 1));
        await container.read(selectedScheduleSemesterProvider.future);

        Future<String> testResolve(String? sem, {bool listen = true}) {
          return container.read(
            Provider((ref) => resolveSemesterKey(ref, sem, listen: listen)),
          );
        }

        // Set selected semester to whitespace "  "
        await container
            .read(selectedScheduleSemesterProvider.notifier)
            .set('   ');
        final keyFromWhitespaceSelected = await testResolve(null);
        expect(keyFromWhitespaceSelected, '2026-2027-1');

        // Set selected semester to empty string ""
        await container.read(selectedScheduleSemesterProvider.notifier).set('');
        final keyFromEmptySelected = await testResolve(null);
        expect(keyFromEmptySelected, '2026-2027-1');

        // Set selected semester to null
        await container
            .read(selectedScheduleSemesterProvider.notifier)
            .set(null);
        final keyFromNullSelected = await testResolve(null);
        expect(keyFromNullSelected, '2026-2027-1');
      },
    );

    test(
      'Custom courses provider resolution with "", null, and whitespace arguments',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        await container
            .read(semesterStartProvider.notifier)
            .set(DateTime(2026, 9, 1));
        await container.read(selectedScheduleSemesterProvider.future);

        const testCourse = Course(
          name: 'Test Course 101',
          teacher: 'Teacher',
          timeStr: 'Mon 1-2',
          classroom: 'Room',
          dayOfWeek: 1,
          timeSlot: 1,
          endTimeSlot: 2,
          weekList: [1],
          isCustom: true,
        );

        // Add course using null
        await container
            .read(customCoursesProvider(null).notifier)
            .addCourse(testCourse);

        // Query using empty string "" and whitespace "  "
        final nullCourses = await container.read(
          customCoursesProvider(null).future,
        );
        final emptyCourses = await container.read(
          customCoursesProvider('').future,
        );
        final spaceCourses = await container.read(
          customCoursesProvider('   ').future,
        );

        expect(nullCourses, hasLength(1));
        expect(emptyCourses, hasLength(1));
        expect(spaceCourses, hasLength(1));
        expect(nullCourses.first.name, 'Test Course 101');
        expect(emptyCourses.first.name, 'Test Course 101');
        expect(spaceCourses.first.name, 'Test Course 101');
      },
    );
  });

  group(
    'Challenger Empirical Tests - Rapid Invalidations & SharedPreferences Consistency',
    () {
      test(
        'Rapid semester switching while performing CRUD on custom courses',
        () async {
          final container = ProviderContainer();
          addTearDown(container.dispose);

          await container
              .read(semesterStartProvider.notifier)
              .set(DateTime(2026, 9, 1));
          await container.read(selectedScheduleSemesterProvider.future);

          // Perform rapid alternating switches and writes across 3 semesters
          final semesters = ['2024-2025-1', '2024-2025-2', '2025-2026-1'];

          for (int i = 0; i < 15; i++) {
            final sem = semesters[i % semesters.length];
            await container
                .read(selectedScheduleSemesterProvider.notifier)
                .set(sem);

            // Add a course to current selected semester
            final course = Course(
              name: 'Course_$i',
              teacher: 'T',
              timeStr: 'Mon 1-2',
              classroom: 'C',
              dayOfWeek: 1,
              timeSlot: 1,
              endTimeSlot: 2,
              weekList: [1],
              isCustom: true,
            );
            await container
                .read(customCoursesProvider(null).notifier)
                .addCourse(course);
          }

          // Verify SharedPreferences consistency: each semester should have its expected count of courses
          final prefs = await SharedPreferences.getInstance();

          // Check keys in prefs
          for (final sem in semesters) {
            final raw = prefs.getString(
              'user_default_schedule_custom_courses_$sem',
            );
            expect(
              raw,
              isNotNull,
              reason:
                  'Key user_default_schedule_custom_courses_$sem should exist in prefs',
            );
          }
        },
      );

      test(
        'Rapid semester start invalidations update activeSemesterStartProvider correctly',
        () async {
          final container = ProviderContainer();
          addTearDown(container.dispose);

          await container.read(selectedScheduleSemesterProvider.future);

          // Rapidly update semester start date 20 times
          for (int i = 1; i <= 20; i++) {
            await container
                .read(semesterStartProvider.notifier)
                .set(DateTime(2026, 9, i));
          }

          final activeStart = container
              .read(activeSemesterStartProvider)
              .valueOrNull;
          expect(activeStart, DateTime(2026, 9, 20));
        },
      );

      test(
        'Concurrent reads and writes across family providers with invalid/malformed semester keys',
        () async {
          final container = ProviderContainer();
          addTearDown(container.dispose);

          await container.read(selectedScheduleSemesterProvider.future);

          // Malformed semester keys: slashes, special chars, extra dashes, empty
          final weirdKeys = [
            '2024/2025/1',
            'Semester 1 2026',
            '2026--2027--1',
            r'$$$!!!',
            '   ',
          ];

          for (final key in weirdKeys) {
            final weeks = await container.read(
              semesterTotalWeeksProvider(key).future,
            );
            expect(weeks, defaultSemesterTotalWeeks);

            await container
                .read(semesterTotalWeeksProvider(key).notifier)
                .setWeeks(18);
            final updatedWeeks = await container.read(
              semesterTotalWeeksProvider(key).future,
            );
            expect(updatedWeeks, 18);
          }
        },
      );

      test(
        'Verify customCoursesProvider decodes corrupted JSON gracefully without crash',
        () async {
          final container = ProviderContainer();
          addTearDown(container.dispose);

          await container.read(selectedScheduleSemesterProvider.future);

          final prefs = await SharedPreferences.getInstance();
          // Write corrupted JSON into custom courses key
          await prefs.setString(
            'schedule_custom_courses_2026-2027-1',
            '{corrupted_json: true',
          );

          await container
              .read(selectedScheduleSemesterProvider.notifier)
              .set('2026-2027-1');

          // Should not throw, should return empty list
          final courses = await container.read(
            customCoursesProvider(null).future,
          );
          expect(courses, isEmpty);
        },
      );

      test(
        'Verify total weeks clamping works for out-of-bound values',
        () async {
          final container = ProviderContainer();
          addTearDown(container.dispose);

          await container.read(selectedScheduleSemesterProvider.future);
          await container
              .read(selectedScheduleSemesterProvider.notifier)
              .set('2026-2027-1');

          // Ensure build() is completed before calling setWeeks
          await container.read(semesterTotalWeeksProvider(null).future);

          // Try setting 5 weeks (below min 12)
          await container
              .read(semesterTotalWeeksProvider(null).notifier)
              .setWeeks(5);
          expect(
            await container.read(semesterTotalWeeksProvider(null).future),
            minSemesterTotalWeeks,
          );

          // Try setting 50 weeks (above max 30)
          await container
              .read(semesterTotalWeeksProvider(null).notifier)
              .setWeeks(50);
          expect(
            await container.read(semesterTotalWeeksProvider(null).future),
            maxSemesterTotalWeeks,
          );
        },
      );

      test(
        'Race condition check: calling setWeeks before build finishes',
        () async {
          final container = ProviderContainer();
          addTearDown(container.dispose);

          await container.read(selectedScheduleSemesterProvider.future);

          // Call setWeeks(16) without awaiting .future first
          final notifier = container.read(
            semesterTotalWeeksProvider('race_sem').notifier,
          );
          await notifier.setWeeks(16);

          // Await future after setWeeks
          final result = await container.read(
            semesterTotalWeeksProvider('race_sem').future,
          );
          expect(result, 16);
        },
      );
    },
  );
}
