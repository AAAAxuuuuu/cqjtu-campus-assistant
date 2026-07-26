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

  group('Milestone 2 Gate: Multi-Account Isolation & Switch Harness', () {
    test(
      'Full sequence userA -> userB -> userC -> userA with modifications to week start, total weeks, dorm selection, custom courses',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        // Define distinct data models for userA, userB, userC
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

        const dormC = DormRoom(
          campusName: '科学城校区',
          garden: DormGarden.deYuan,
          buildingNumber: 1,
          roomNumber: '0101',
        );

        const courseA = Course(
          name: 'Advanced Algorithms (User A)',
          teacher: 'Dr. Alice',
          timeStr: 'Mon 1-2',
          classroom: 'A101',
          dayOfWeek: 1,
          timeSlot: 1,
          endTimeSlot: 2,
          weekList: [1, 2, 3, 4, 5],
          isCustom: true,
        );

        const courseB = Course(
          name: 'Compiler Engineering (User B)',
          teacher: 'Prof. Bob',
          timeStr: 'Tue 3-4',
          classroom: 'B202',
          dayOfWeek: 2,
          timeSlot: 3,
          endTimeSlot: 4,
          weekList: [1, 3, 5, 7],
          isCustom: true,
        );

        const courseC = Course(
          name: 'Computer Vision (User C)',
          teacher: 'Dr. Charlie',
          timeStr: 'Wed 5-6',
          classroom: 'C303',
          dayOfWeek: 3,
          timeSlot: 5,
          endTimeSlot: 6,
          weekList: [2, 4, 6, 8],
          isCustom: true,
        );

        // ==========================================
        // STEP 1: Log in as userA and modify preferences
        // ==========================================
        container.read(credentialsProvider.notifier).set('userA', 'passA');
        expect(container.read(credentialsProvider)?.username, equals('userA'));

        await container
            .read(scheduleSundayFirstProvider.notifier)
            .setSundayFirst(true);
        await container
            .read(semesterTotalWeeksProvider(null).notifier)
            .setWeeks(24);
        await container.read(dormRoomProvider.notifier).set(dormA);
        await container
            .read(customCoursesProvider(null).notifier)
            .addCourse(courseA);

        // Verify userA state immediately
        expect(
          await container.read(scheduleSundayFirstProvider.future),
          isTrue,
        );
        expect(
          await container.read(semesterTotalWeeksProvider(null).future),
          equals(24),
        );
        final userADormRead = await container.read(dormRoomProvider.future);
        expect(userADormRead?.buildingFullName, equals(dormA.buildingFullName));
        expect(userADormRead?.roomNumber, equals(dormA.roomNumber));
        expect(userADormRead?.garden, equals(dormA.garden));
        final userACoursesRead = await container.read(
          customCoursesProvider(null).future,
        );
        expect(userACoursesRead, hasLength(1));
        expect(
          userACoursesRead.first.name,
          equals('Advanced Algorithms (User A)'),
        );

        // ==========================================
        // STEP 2: Switch to userB (Verify no bleed, set userB values)
        // ==========================================
        container.read(credentialsProvider.notifier).set('userB', 'passB');
        expect(container.read(credentialsProvider)?.username, equals('userB'));

        // Verify userB clean defaults (zero bleed from userA)
        expect(
          await container.read(scheduleSundayFirstProvider.future),
          isFalse, // default
        );
        expect(
          await container.read(semesterTotalWeeksProvider(null).future),
          equals(20), // default
        );
        expect(await container.read(dormRoomProvider.future), isNull);
        expect(
          await container.read(customCoursesProvider(null).future),
          isEmpty,
        );

        // Modify userB preferences
        await container
            .read(scheduleSundayFirstProvider.notifier)
            .setSundayFirst(false); // explicit false
        await container
            .read(semesterTotalWeeksProvider(null).notifier)
            .setWeeks(16);
        await container.read(dormRoomProvider.notifier).set(dormB);
        await container
            .read(customCoursesProvider(null).notifier)
            .addCourse(courseB);

        // Verify userB state
        expect(
          await container.read(scheduleSundayFirstProvider.future),
          isFalse,
        );
        expect(
          await container.read(semesterTotalWeeksProvider(null).future),
          equals(16),
        );
        final userBDormRead = await container.read(dormRoomProvider.future);
        expect(userBDormRead?.buildingFullName, equals(dormB.buildingFullName));
        expect(userBDormRead?.roomNumber, equals(dormB.roomNumber));
        expect(userBDormRead?.garden, equals(dormB.garden));
        final userBCoursesRead = await container.read(
          customCoursesProvider(null).future,
        );
        expect(userBCoursesRead, hasLength(1));
        expect(
          userBCoursesRead.first.name,
          equals('Compiler Engineering (User B)'),
        );

        // ==========================================
        // STEP 3: Switch to userC (Verify no bleed, set userC values)
        // ==========================================
        container.read(credentialsProvider.notifier).set('userC', 'passC');
        expect(container.read(credentialsProvider)?.username, equals('userC'));

        // Verify userC clean defaults (zero bleed from userA or userB)
        expect(
          await container.read(scheduleSundayFirstProvider.future),
          isFalse, // default
        );
        expect(
          await container.read(semesterTotalWeeksProvider(null).future),
          equals(20), // default
        );
        expect(await container.read(dormRoomProvider.future), isNull);
        expect(
          await container.read(customCoursesProvider(null).future),
          isEmpty,
        );

        // Modify userC preferences
        await container
            .read(scheduleSundayFirstProvider.notifier)
            .setSundayFirst(true);
        await container
            .read(semesterTotalWeeksProvider(null).notifier)
            .setWeeks(28);
        await container.read(dormRoomProvider.notifier).set(dormC);
        await container
            .read(customCoursesProvider(null).notifier)
            .addCourse(courseC);

        // Verify userC state
        expect(
          await container.read(scheduleSundayFirstProvider.future),
          isTrue,
        );
        expect(
          await container.read(semesterTotalWeeksProvider(null).future),
          equals(28),
        );
        final userCDormRead = await container.read(dormRoomProvider.future);
        expect(userCDormRead?.buildingFullName, equals(dormC.buildingFullName));
        expect(userCDormRead?.roomNumber, equals(dormC.roomNumber));
        expect(userCDormRead?.garden, equals(dormC.garden));
        final userCCoursesRead = await container.read(
          customCoursesProvider(null).future,
        );
        expect(userCCoursesRead, hasLength(1));
        expect(userCCoursesRead.first.name, equals('Computer Vision (User C)'));

        // ==========================================
        // STEP 4: Switch back to userA and assert preferences intact
        // ==========================================
        container.read(credentialsProvider.notifier).set('userA', 'passA');
        expect(container.read(credentialsProvider)?.username, equals('userA'));

        expect(
          await container.read(scheduleSundayFirstProvider.future),
          isTrue,
        );
        expect(
          await container.read(semesterTotalWeeksProvider(null).future),
          equals(24),
        );
        final restoredUserADorm = await container.read(dormRoomProvider.future);
        expect(restoredUserADorm, isNotNull);
        expect(
          restoredUserADorm?.buildingFullName,
          equals(dormA.buildingFullName),
        );
        expect(restoredUserADorm?.roomNumber, equals(dormA.roomNumber));
        expect(restoredUserADorm?.garden, equals(dormA.garden));
        final restoredUserACourses = await container.read(
          customCoursesProvider(null).future,
        );
        expect(restoredUserACourses, hasLength(1));
        expect(
          restoredUserACourses.first.name,
          equals('Advanced Algorithms (User A)'),
        );
      },
    );

    test(
      'Rapid looping account switches (userA -> userB -> userC -> userA x 10 cycles)',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        // Pre-populate SharedPreferences for userA, userB, userC
        container.read(credentialsProvider.notifier).set('userA', 'passA');
        await container
            .read(scheduleSundayFirstProvider.notifier)
            .setSundayFirst(true);
        await container
            .read(semesterTotalWeeksProvider(null).notifier)
            .setWeeks(22);

        container.read(credentialsProvider.notifier).set('userB', 'passB');
        await container
            .read(scheduleSundayFirstProvider.notifier)
            .setSundayFirst(false);
        await container
            .read(semesterTotalWeeksProvider(null).notifier)
            .setWeeks(18);

        container.read(credentialsProvider.notifier).set('userC', 'passC');
        await container
            .read(scheduleSundayFirstProvider.notifier)
            .setSundayFirst(true);
        await container
            .read(semesterTotalWeeksProvider(null).notifier)
            .setWeeks(26);

        // Perform 10 rapid switch cycles
        for (var i = 0; i < 10; i++) {
          container.read(credentialsProvider.notifier).set('userA', 'passA');
          expect(
            await container.read(scheduleSundayFirstProvider.future),
            isTrue,
          );
          expect(
            await container.read(semesterTotalWeeksProvider(null).future),
            22,
          );

          container.read(credentialsProvider.notifier).set('userB', 'passB');
          expect(
            await container.read(scheduleSundayFirstProvider.future),
            isFalse,
          );
          expect(
            await container.read(semesterTotalWeeksProvider(null).future),
            18,
          );

          container.read(credentialsProvider.notifier).set('userC', 'passC');
          expect(
            await container.read(scheduleSundayFirstProvider.future),
            isTrue,
          );
          expect(
            await container.read(semesterTotalWeeksProvider(null).future),
            26,
          );
        }
      },
    );
  });
}
