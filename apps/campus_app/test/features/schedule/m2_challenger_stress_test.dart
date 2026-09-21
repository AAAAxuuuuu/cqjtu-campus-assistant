import 'package:campus_app/features/auth/auth_providers.dart';
import 'package:campus_app/features/schedule/schedule_providers.dart';
import 'package:campus_app/providers/runtime_mode.dart';
import 'package:core/models/course.dart';
import 'package:core/models/exam.dart';
import 'package:core/models/grade.dart';
import 'package:core/models/study_progress.dart';
import 'package:core/utils/resource_cache_key.dart';
import 'package:data/data.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _StressFakeGateway implements CampusGateway {
  final Map<String, List<Course>> semesterCourses = {};
  final Map<String, String> semesterRemarks = {};
  final List<String?> scheduleCallSemesters = [];
  final List<String?> examCallSemesters = [];
  int scheduleCallCount = 0;
  int examCallCount = 0;

  @override
  Future<({List<Course> courses, String remark})> getSchedule(
    String username,
    String password, {
    String? semester,
    bool forceRefresh = false,
  }) async {
    scheduleCallCount++;
    scheduleCallSemesters.add(semester);
    final courses = semesterCourses[semester] ?? const [];
    final remark = semesterRemarks[semester] ?? '';
    return (courses: courses, remark: remark);
  }

  @override
  Future<List<Exam>> getExams(
    String username,
    String password, {
    String? semester,
    bool forceRefresh = false,
  }) async {
    examCallCount++;
    examCallSemesters.add(semester);
    return const [];
  }

  @override
  Future<({Map<String, String> summary, List<Grade> grades})> getGrades(
    String username,
    String password, {
    String semester = '',
    bool forceRefresh = false,
  }) async => (summary: <String, String>{}, grades: <Grade>[]);

  @override
  Future<GradeDetail> getGradeDetail(
    String username,
    String password, {
    required Grade grade,
    bool forceRefresh = false,
  }) async => const GradeDetail(items: [], totalScore: '');

  @override
  Future<StudyProgressData> getStudyProgress(
    String username,
    String password, {
    bool forceRefresh = false,
  }) async => const StudyProgressData(
    groups: [],
    currentSemester: '',
    currentSemesterCourses: [],
  );

  @override
  Future<String> getElecBalance(
    String username,
    String password, {
    bool forceRefresh = false,
    Map<String, String>? dormParams,
  }) async => '100.00';

  @override
  Future<String> getCampusCardBalance(
    String username,
    String password, {
    bool forceRefresh = false,
  }) async => '50.00';

  @override
  Future<String> rechargeElec(
    String username,
    double amount, {
    String? password,
    Map<String, String>? dormParams,
  }) async => 'ok';

  @override
  Future<String> getPayCodeToken(String username, {String? password}) async =>
      'token';

  @override
  Future<String> getCampusCardAlipayUrl(
    String username,
    double amount, {
    String? password,
  }) async => 'https://example.com/alipay';
}

const _courseA = Course(
  name: '算法设计与分析',
  teacher: '赵老师',
  timeStr: '周一 1-2节',
  classroom: 'C301',
  dayOfWeek: 1,
  timeSlot: 1,
  endTimeSlot: 2,
  weekList: [1, 2, 3, 4],
);

const _courseB = Course(
  name: '软件工程导论',
  teacher: '钱老师',
  timeStr: '周三 5-6节',
  classroom: 'D402',
  dayOfWeek: 3,
  timeSlot: 5,
  endTimeSlot: 6,
  weekList: [1, 2, 3, 4],
);

const _customCourse1 = Course(
  name: '考研英语自习',
  teacher: '自学',
  timeStr: '周六 1-2节',
  classroom: '图书馆自习室',
  dayOfWeek: 6,
  timeSlot: 1,
  endTimeSlot: 2,
  weekList: [1, 2, 3, 4, 5, 6, 7, 8],
  isCustom: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Milestone 2 Challenger Stress Harness: Cache Guard', () {
    test(
      '1.1 Remote empty courses against populated local cache: throws SchoolSystemChangedFailure and preserves memory/disk cache',
      () async {
        final gateway = _StressFakeGateway();
        final container = ProviderContainer(
          overrides: [campusGatewayProvider.overrideWithValue(gateway)],
        );
        addTearDown(container.dispose);

        const username = 'student_guard_test';
        container.read(credentialsProvider.notifier).set(username, 'pass123');
        await container
            .read(semesterStartProvider.notifier)
            .set(DateTime(2026, 9, 1));

        // Initial populate: 2 courses
        gateway.semesterCourses['2026-2027-1'] = [_courseA, _courseB];
        gateway.semesterRemarks['2026-2027-1'] = '正常课表';

        await container
            .read(scheduleProvider(null).notifier)
            .refresh(forceRefresh: true);

        final initial = container.read(scheduleProvider(null));
        expect(initial.hasData, isTrue);
        expect(initial.data.courses, hasLength(2));

        final cacheKey = resourceCacheKey(
          'schedule',
          username: username,
          scope: '2026-2027-1',
        );
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.containsKey(cacheKey), isTrue);
        final diskCacheBefore = prefs.getString(cacheKey)!;
        expect(diskCacheBefore, contains('算法设计与分析'));
        expect(diskCacheBefore, contains('软件工程导论'));

        // Remote now fails or returns empty courses
        gateway.semesterCourses['2026-2027-1'] = const [];
        gateway.semesterRemarks['2026-2027-1'] = '';
        gateway.examCallCount = 0; // reset to check if exam fetch is skipped

        await container
            .read(scheduleProvider(null).notifier)
            .refresh(forceRefresh: true);

        final afterGuard = container.read(scheduleProvider(null));

        // 1. SWR State retains data
        expect(afterGuard.hasData, isTrue);
        expect(afterGuard.data.courses, hasLength(2));
        expect(afterGuard.data.courses[0].name, '算法设计与分析');
        expect(afterGuard.data.courses[1].name, '软件工程导论');

        // 2. Specific typed failure thrown
        expect(afterGuard.error, isA<SchoolSystemChangedFailure>());
        expect(
          (afterGuard.error as SchoolSystemChangedFailure).message,
          '远端课表返回空数据，已拦截以保护既有本地缓存',
        );

        // 3. Disk cache untouched
        final diskCacheAfter = prefs.getString(cacheKey)!;
        expect(diskCacheAfter, equals(diskCacheBefore));

        // 4. Exam courses fetch was aborted early by the guard
        expect(gateway.examCallCount, 0);
      },
    );

    test(
      '1.2 Initial cold start with no local cache: accepts empty courses without failure or crash',
      () async {
        final gateway = _StressFakeGateway();
        final container = ProviderContainer(
          overrides: [campusGatewayProvider.overrideWithValue(gateway)],
        );
        addTearDown(container.dispose);

        const username = 'student_cold_start';
        container.read(credentialsProvider.notifier).set(username, 'pass123');
        await container
            .read(semesterStartProvider.notifier)
            .set(DateTime(2026, 9, 1));

        // Cold start with empty remote schedule
        gateway.semesterCourses['2026-2027-1'] = const [];
        gateway.semesterRemarks['2026-2027-1'] = '本学期无课程记录';

        await container
            .read(scheduleProvider(null).notifier)
            .refresh(forceRefresh: true);

        final state = container.read(scheduleProvider(null));
        expect(state.hasData, isTrue);
        expect(state.data.courses, isEmpty);
        expect(state.data.remark, '本学期无课程记录');
        expect(state.error, isNull);

        // Disk cache is safely written with empty courses
        final cacheKey = resourceCacheKey(
          'schedule',
          username: username,
          scope: '2026-2027-1',
        );
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.containsKey(cacheKey), isTrue);
        expect(prefs.getString(cacheKey), contains('"courses":[]'));
      },
    );

    test(
      '1.3 Custom courses preservation: both hybrid (school+custom) and custom-only are shielded from remote wipe',
      () async {
        final gateway = _StressFakeGateway();
        final container = ProviderContainer(
          overrides: [campusGatewayProvider.overrideWithValue(gateway)],
        );
        addTearDown(container.dispose);

        const username = 'student_custom_guard';
        container.read(credentialsProvider.notifier).set(username, 'pass123');
        await container
            .read(semesterStartProvider.notifier)
            .set(DateTime(2026, 9, 1));

        // Add custom course for active semester
        await container
            .read(customCoursesProvider('2026-2027-1').notifier)
            .addCourse(_customCourse1);

        // Populate with 1 school course + 1 custom course
        gateway.semesterCourses['2026-2027-1'] = [_courseA];
        await container
            .read(scheduleProvider(null).notifier)
            .refresh(forceRefresh: true);

        final stateInitial = container.read(scheduleProvider(null));
        expect(stateInitial.hasData, isTrue);
        expect(stateInitial.data.courses, hasLength(2));
        expect(
          stateInitial.data.courses.any(
            (c) => c.name == '考研英语自习' && c.isCustom,
          ),
          isTrue,
        );
        expect(
          stateInitial.data.courses.any((c) => c.name == '算法设计与分析'),
          isTrue,
        );

        // Now remote drops to empty
        gateway.semesterCourses['2026-2027-1'] = const [];
        await container
            .read(scheduleProvider(null).notifier)
            .refresh(forceRefresh: true);

        final stateGuarded = container.read(scheduleProvider(null));
        expect(stateGuarded.hasData, isTrue);
        expect(stateGuarded.error, isA<SchoolSystemChangedFailure>());
        // Both custom course and school course are preserved
        expect(stateGuarded.data.courses, hasLength(2));
        expect(
          stateGuarded.data.courses.any((c) => c.name == '考研英语自习'),
          isTrue,
        );
        expect(
          stateGuarded.data.courses.any((c) => c.name == '算法设计与分析'),
          isTrue,
        );

        // Disk cache retains both
        final cacheKey = resourceCacheKey(
          'schedule',
          username: username,
          scope: '2026-2027-1',
        );
        final prefs = await SharedPreferences.getInstance();
        final rawCache = prefs.getString(cacheKey)!;
        expect(rawCache, contains('考研英语自习'));
        expect(rawCache, contains('算法设计与分析'));
      },
    );
  });

  group(
    'Milestone 2 Challenger Stress Harness: Semester Scope Alignment & Switching',
    () {
      test(
        '2.1 Scope key resolution: null, empty, whitespace and explicit match exact same scope key',
        () async {
          final container = ProviderContainer();
          addTearDown(container.dispose);

          await container
              .read(semesterStartProvider.notifier)
              .set(DateTime(2026, 9, 1));

          final notifierNull = container.read(scheduleProvider(null).notifier);
          final notifierExplicit = container.read(
            scheduleProvider('2026-2027-1').notifier,
          );
          final notifierWhitespace = container.read(
            scheduleProvider('   ').notifier,
          );

          expect(notifierNull.cacheScopeForArg(null), '2026-2027-1');
          expect(
            notifierExplicit.cacheScopeForArg('2026-2027-1'),
            '2026-2027-1',
          );
          expect(notifierWhitespace.cacheScopeForArg('   '), '2026-2027-1');
          expect(
            notifierExplicit.cacheScopeForArg('  2026-2027-1  '),
            '2026-2027-1',
          );

          // Verify SharedPreferences keys are bitwise identical
          const user = 'test_user';
          final keyNull = resourceCacheKey(
            'schedule',
            username: user,
            scope: notifierNull.cacheScopeForArg(null),
          );
          final keyExplicit = resourceCacheKey(
            'schedule',
            username: user,
            scope: notifierExplicit.cacheScopeForArg('2026-2027-1'),
          );
          expect(keyNull, equals(keyExplicit));
          expect(
            keyNull,
            resourceCacheKey('schedule', username: user, scope: '2026-2027-1'),
          );
          expect(
            keyNull,
            'resource_cache_v1:c2NoZWR1bGU=:dGVzdF91c2Vy:MjAyNi0yMDI3LTE=',
          );
        },
      );

      test(
        '2.2 SWR read/write symmetry between scheduleProvider(null) and scheduleProvider(explicit)',
        () async {
          final gateway = _StressFakeGateway();
          final container = ProviderContainer(
            overrides: [campusGatewayProvider.overrideWithValue(gateway)],
          );
          addTearDown(container.dispose);

          const username = 'student_symmetry';
          container.read(credentialsProvider.notifier).set(username, 'pass123');
          await container
              .read(semesterStartProvider.notifier)
              .set(DateTime(2026, 9, 1));

          gateway.semesterCourses['2026-2027-1'] = [_courseA];

          // 1. Fetch via scheduleProvider('2026-2027-1')
          await container
              .read(scheduleProvider('2026-2027-1').notifier)
              .refresh(forceRefresh: true);

          // 2. Create second container sharing same SharedPreferences to simulate fresh app launch
          final container2 = ProviderContainer(
            overrides: [campusGatewayProvider.overrideWithValue(gateway)],
          );
          addTearDown(container2.dispose);

          container2
              .read(credentialsProvider.notifier)
              .set(username, 'pass123');
          await container2
              .read(semesterStartProvider.notifier)
              .set(DateTime(2026, 9, 1));

          // Read via scheduleProvider(null) from disk cache before network
          final cachedState = await container2
              .read(scheduleProvider(null).notifier)
              .restoreCachedThenRefresh();

          expect(
            cachedState.hasData,
            isTrue,
            reason:
                'scheduleProvider(null) must immediately hit cache written by scheduleProvider(explicit)',
          );
          expect(cachedState.data.courses, hasLength(1));
          expect(cachedState.data.courses.first.name, '算法设计与分析');
        },
      );

      test(
        '2.3 Rapid switching between semesters: no cross-contamination or cache overwrites',
        () async {
          final gateway = _StressFakeGateway();
          final container = ProviderContainer(
            overrides: [campusGatewayProvider.overrideWithValue(gateway)],
          );
          addTearDown(container.dispose);

          const username = 'student_switcher';
          container.read(credentialsProvider.notifier).set(username, 'pass123');
          await container
              .read(semesterStartProvider.notifier)
              .set(DateTime(2026, 9, 1));

          gateway.semesterCourses['2025-2026-2'] = [_courseA];
          gateway.semesterCourses['2026-2027-1'] = [_courseB];

          // Rapidly switch between the two semesters
          for (int i = 0; i < 6; i++) {
            final sem = (i % 2 == 0) ? '2025-2026-2' : '2026-2027-1';
            await container
                .read(selectedScheduleSemesterProvider.notifier)
                .set(sem);
            await container
                .read(scheduleProvider(sem).notifier)
                .refresh(forceRefresh: true);

            final state = container.read(scheduleProvider(sem));
            expect(state.hasData, isTrue);
            if (sem == '2025-2026-2') {
              expect(state.data.courses.first.name, '算法设计与分析');
            } else {
              expect(state.data.courses.first.name, '软件工程导论');
            }
          }

          // Verify disk cache has two distinct, unpolluted keys
          final prefs = await SharedPreferences.getInstance();
          final keyA = resourceCacheKey(
            'schedule',
            username: username,
            scope: '2025-2026-2',
          );
          final keyB = resourceCacheKey(
            'schedule',
            username: username,
            scope: '2026-2027-1',
          );

          expect(prefs.containsKey(keyA), isTrue);
          expect(prefs.containsKey(keyB), isTrue);

          final cacheA = prefs.getString(keyA)!;
          final cacheB = prefs.getString(keyB)!;

          expect(cacheA, contains('算法设计与分析'));
          expect(cacheA, isNot(contains('软件工程导论')));

          expect(cacheB, contains('软件工程导论'));
          expect(cacheB, isNot(contains('算法设计与分析')));
        },
      );

      test(
        '2.4 Gateway parameters: getSchedule and _loadExamCourses always receive resolved non-null semester',
        () async {
          final gateway = _StressFakeGateway();
          final container = ProviderContainer(
            overrides: [campusGatewayProvider.overrideWithValue(gateway)],
          );
          addTearDown(container.dispose);

          container
              .read(credentialsProvider.notifier)
              .set('student_args', 'pass123');
          await container
              .read(semesterStartProvider.notifier)
              .set(DateTime(2026, 9, 1));

          gateway.semesterCourses['2026-2027-1'] = [_courseA];

          // Fetch with null resourceArg
          await container
              .read(scheduleProvider(null).notifier)
              .refresh(forceRefresh: true);

          expect(gateway.scheduleCallSemesters.last, '2026-2027-1');
          expect(gateway.examCallSemesters.last, '2026-2027-1');
          expect(gateway.scheduleCallSemesters.contains(null), isFalse);
          expect(gateway.examCallSemesters.contains(null), isFalse);
        },
      );
    },
  );
}
