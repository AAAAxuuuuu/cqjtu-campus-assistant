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

class _RecordingFakeGateway implements CampusGateway {
  String? lastScheduleSemester;
  String? lastExamSemester;
  int scheduleCallCount = 0;
  int examCallCount = 0;
  List<Course> coursesToReturn = const [];
  String remarkToReturn = '';
  List<Exam> examsToReturn = const [];

  @override
  Future<({List<Course> courses, String remark})> getSchedule(
    String username,
    String password, {
    String? semester,
    bool forceRefresh = false,
  }) async {
    scheduleCallCount++;
    lastScheduleSemester = semester;
    return (courses: coursesToReturn, remark: remarkToReturn);
  }

  @override
  Future<List<Exam>> getExams(
    String username,
    String password, {
    String? semester,
    bool forceRefresh = false,
  }) async {
    examCallCount++;
    lastExamSemester = semester;
    return examsToReturn;
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

const _sampleCourse1 = Course(
  name: '高等数学',
  teacher: '张老师',
  timeStr: '周一 1-2节',
  classroom: 'A101',
  dayOfWeek: 1,
  timeSlot: 1,
  endTimeSlot: 2,
  weekList: [1, 2, 3, 4],
);

const _sampleCourse2 = Course(
  name: '大学物理',
  teacher: '李老师',
  timeStr: '周二 3-4节',
  classroom: 'B202',
  dayOfWeek: 2,
  timeSlot: 3,
  endTimeSlot: 4,
  weekList: [1, 2, 3, 4],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('R4: Semester Scope Alignment and Parameter Passing', () {
    test(
      'resolveSemesterKeySync resolves null, whitespace, and empty string to active semester',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        // Set explicit semester start date to 2026-09-01 => 2026-2027-1
        await container
            .read(semesterStartProvider.notifier)
            .set(DateTime(2026, 9, 1));

        expect(
          container.read(Provider((ref) => resolveSemesterKeySync(ref, null))),
          '2026-2027-1',
        );
        expect(
          container.read(Provider((ref) => resolveSemesterKeySync(ref, ''))),
          '2026-2027-1',
        );
        expect(
          container.read(
            Provider((ref) => resolveSemesterKeySync(ref, '   \t  ')),
          ),
          '2026-2027-1',
        );
      },
    );

    test('resolveSemesterKeySync trims and preserves explicit semester', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(
          Provider((ref) => resolveSemesterKeySync(ref, '2025-2026-2')),
        ),
        '2025-2026-2',
      );
      expect(
        container.read(
          Provider((ref) => resolveSemesterKeySync(ref, '  2025-2026-2  ')),
        ),
        '2025-2026-2',
      );
    });

    test(
      'resolveSemesterKeySync prioritizes selectedScheduleSemesterProvider over semesterStartProvider',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        // Set semester start date to 2026-09-01 => 2026-2027-1
        await container
            .read(semesterStartProvider.notifier)
            .set(DateTime(2026, 9, 1));

        // Switch selectedScheduleSemesterProvider to 2027-2028-1
        await container
            .read(selectedScheduleSemesterProvider.notifier)
            .set('2027-2028-1');

        expect(
          container.read(Provider((ref) => resolveSemesterKeySync(ref, null))),
          '2027-2028-1',
        );
      },
    );

    test(
      'cacheScopeForArg(null) and cacheScopeForArg(activeSemester) produce the identical scope string',
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

        final scopeNull = notifierNull.cacheScopeForArg(null);
        final scopeExplicit = notifierExplicit.cacheScopeForArg('2026-2027-1');

        expect(scopeNull, '2026-2027-1');
        expect(scopeExplicit, '2026-2027-1');
        expect(scopeNull, equals(scopeExplicit));
      },
    );

    test(
      'ScheduleNotifier passes resolved semesterKey to gateway.getSchedule and _loadExamCourses',
      () async {
        final fakeGateway = _RecordingFakeGateway();
        final container = ProviderContainer(
          overrides: [campusGatewayProvider.overrideWithValue(fakeGateway)],
        );
        addTearDown(container.dispose);

        // Set credentials & active semester start
        container
            .read(credentialsProvider.notifier)
            .set('student123', 'pass123');
        await container
            .read(semesterStartProvider.notifier)
            .set(DateTime(2026, 9, 1));

        fakeGateway.coursesToReturn = [_sampleCourse1];

        // Request schedule with resourceArg == null
        await container
            .read(scheduleProvider(null).notifier)
            .refresh(forceRefresh: true);

        // Verify gateway.getSchedule and getExams received '2026-2027-1' instead of null
        expect(fakeGateway.scheduleCallCount, greaterThanOrEqualTo(1));
        expect(fakeGateway.lastScheduleSemester, '2026-2027-1');
        expect(fakeGateway.examCallCount, greaterThanOrEqualTo(1));
        expect(fakeGateway.lastExamSemester, '2026-2027-1');
      },
    );
  });

  group('R1: Defensive Cache Guard against Empty Remote Courses', () {
    test(
      'Throws SchoolSystemChangedFailure and protects cached courses when remote returns empty list',
      () async {
        final fakeGateway = _RecordingFakeGateway();
        final container = ProviderContainer(
          overrides: [campusGatewayProvider.overrideWithValue(fakeGateway)],
        );
        addTearDown(container.dispose);

        container
            .read(credentialsProvider.notifier)
            .set('student123', 'pass123');
        await container
            .read(semesterStartProvider.notifier)
            .set(DateTime(2026, 9, 1));

        // 1. Initial successful fetch populates cache with 2 courses
        fakeGateway.coursesToReturn = [_sampleCourse1, _sampleCourse2];
        fakeGateway.remarkToReturn = '第1周课表';
        await container
            .read(scheduleProvider(null).notifier)
            .refresh(forceRefresh: true);

        final stateWithCourses = container.read(scheduleProvider(null));
        expect(stateWithCourses.hasData, isTrue);
        expect(stateWithCourses.data.courses, hasLength(2));
        expect(stateWithCourses.data.remark, '第1周课表');
        expect(stateWithCourses.error, isNull);

        // Confirm disk cache is written under resolved scope key
        final expectedCacheKey = resourceCacheKey(
          'schedule',
          username: 'student123',
          scope: '2026-2027-1',
        );
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.containsKey(expectedCacheKey), isTrue);
        final rawCacheBefore = prefs.getString(expectedCacheKey)!;
        expect(rawCacheBefore, contains('高等数学'));
        expect(rawCacheBefore, contains('大学物理'));

        // 2. Remote now anomalously returns empty courses (e.g. server glitch or unexpected DOM)
        fakeGateway.coursesToReturn = const [];
        fakeGateway.remarkToReturn = '';

        // Trigger refresh (force refresh)
        await container
            .read(scheduleProvider(null).notifier)
            .refresh(forceRefresh: true);

        // Verify SWR state protection:
        final guardedState = container.read(scheduleProvider(null));
        expect(
          guardedState.hasData,
          isTrue,
          reason: 'hasData must remain true under SWR',
        );
        expect(
          guardedState.data.courses,
          hasLength(2),
          reason: 'Cached courses must not be wiped',
        );
        expect(guardedState.data.courses[0].name, '高等数学');
        expect(guardedState.data.courses[1].name, '大学物理');
        expect(guardedState.error, isA<SchoolSystemChangedFailure>());
        expect(
          (guardedState.error as SchoolSystemChangedFailure).message,
          '远端课表返回空数据，已拦截以保护既有本地缓存',
        );

        // Verify underlying disk cache in SharedPreferences was NOT overwritten with empty courses
        final rawCacheAfter = prefs.getString(expectedCacheKey)!;
        expect(rawCacheAfter, contains('高等数学'));
        expect(rawCacheAfter, contains('大学物理'));
      },
    );

    test(
      'Allows empty courses on cold start when no cached courses exist',
      () async {
        final fakeGateway = _RecordingFakeGateway();
        final container = ProviderContainer(
          overrides: [campusGatewayProvider.overrideWithValue(fakeGateway)],
        );
        addTearDown(container.dispose);

        container
            .read(credentialsProvider.notifier)
            .set('new_student', 'pass123');
        await container
            .read(semesterStartProvider.notifier)
            .set(DateTime(2026, 9, 1));

        // Remote returns empty courses on cold start (e.g. new student with no registered courses)
        fakeGateway.coursesToReturn = const [];
        fakeGateway.remarkToReturn = '暂无课程';

        await container
            .read(scheduleProvider(null).notifier)
            .refresh(forceRefresh: true);

        final state = container.read(scheduleProvider(null));
        expect(state.hasData, isTrue);
        expect(state.data.courses, isEmpty);
        expect(state.data.remark, '暂无课程');
        expect(state.error, isNull);
      },
    );

    test(
      'Allows cache overwrite when remote returns a valid non-empty course list',
      () async {
        final fakeGateway = _RecordingFakeGateway();
        final container = ProviderContainer(
          overrides: [campusGatewayProvider.overrideWithValue(fakeGateway)],
        );
        addTearDown(container.dispose);

        container
            .read(credentialsProvider.notifier)
            .set('student123', 'pass123');
        await container
            .read(semesterStartProvider.notifier)
            .set(DateTime(2026, 9, 1));

        // Initial 1 course
        fakeGateway.coursesToReturn = [_sampleCourse1];
        await container
            .read(scheduleProvider(null).notifier)
            .refresh(forceRefresh: true);
        expect(
          container.read(scheduleProvider(null)).data.courses,
          hasLength(1),
        );

        // Remote now updates with 2 courses
        fakeGateway.coursesToReturn = [_sampleCourse1, _sampleCourse2];
        await container
            .read(scheduleProvider(null).notifier)
            .refresh(forceRefresh: true);

        final state = container.read(scheduleProvider(null));
        expect(state.hasData, isTrue);
        expect(state.data.courses, hasLength(2));
        expect(state.error, isNull);
      },
    );
  });
}
