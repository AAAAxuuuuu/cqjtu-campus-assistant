import 'dart:convert';

import 'package:campus_app/features/auth/auth_providers.dart';
import 'package:campus_app/features/schedule/schedule_providers.dart';
import 'package:campus_app/pages/schedule_page.dart';
import 'package:campus_app/providers/runtime_mode.dart';
import 'package:campus_app/utils/semester_service.dart';
import 'package:core/models/course.dart';
import 'package:core/models/exam.dart';
import 'package:core/models/grade.dart';
import 'package:core/models/study_progress.dart';
import 'package:core/utils/resource_cache_key.dart';
import 'package:data/data.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeScheduleGateway implements CampusGateway {
  _FakeScheduleGateway(this.courses, {this.failSchedule = false});

  final List<Course> courses;
  final bool failSchedule;

  @override
  Future<({List<Course> courses, String remark})> getSchedule(
    String username,
    String password, {
    String? semester,
    bool forceRefresh = false,
  }) async {
    if (failSchedule) throw Exception('network offline');
    return (courses: courses, remark: '');
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
  Future<List<Exam>> getExams(
    String username,
    String password, {
    String? semester,
    bool forceRefresh = false,
  }) async => const [];

  @override
  Future<String> getElecBalance(
    String username,
    String password, {
    bool forceRefresh = false,
    Map<String, String>? dormParams,
  }) async => '0.00';

  @override
  Future<String> getCampusCardBalance(
    String username,
    String password, {
    bool forceRefresh = false,
  }) async => '0.00';

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

const _mondaySlot67 = Course(
  name: '高等数学',
  teacher: '张老师',
  timeStr: '1-16(周)[06-07节]',
  classroom: '20101',
  dayOfWeek: 1,
  timeSlot: 6,
  endTimeSlot: 7,
  weekList: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16],
);

const _mondaySlot89 = Course(
  name: '数据结构',
  teacher: '李老师',
  timeStr: '1-16(周)[08-09节]',
  classroom: '20202',
  dayOfWeek: 1,
  timeSlot: 8,
  endTimeSlot: 9,
  weekList: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16],
);

const _week17FourSlot = Course(
  name: '工程实训',
  teacher: '王老师',
  timeStr: '17(周)[06-07-08-09节]',
  classroom: '601005一机房A区',
  dayOfWeek: 1,
  timeSlot: 6,
  endTimeSlot: 9,
  weekList: [17],
);

const _crossRowFourSlotHtml = '''
<html><body>
<table id="timetable">
<tr><th></th><th>一</th><th>二</th><th>三</th><th>四</th><th>五</th><th>六</th><th>日</th></tr>
<tr><td></td><td></td><td></td><td></td><td></td><td></td><td></td></tr>
<tr><td></td><td></td><td></td><td></td><td></td><td></td><td></td></tr>
<tr>
  <td><div class="kbcontent">
    <font>高等数学</font><br>
    <font title="教师">张老师</font><br>
    <font title="周次(节次)">1-16(周)[06-07节]</font><br>
    <font title="教室">20101</font><br>
    ---------------------<br>
    <font>工程实训</font><br>
    <font title="教师">王老师</font><br>
    <font title="周次(节次)">17(周)[06-07-08-09节]</font><br>
    <font title="教室">601005一机房A区</font>
  </div></td>
  <td></td><td></td><td></td><td></td><td></td><td></td>
</tr>
<tr>
  <td><div class="kbcontent">
    <font>数据结构</font><br>
    <font title="教师">李老师</font><br>
    <font title="周次(节次)">1-16(周)[08-09节]</font><br>
    <font title="教室">20202</font><br>
    ---------------------<br>
    <font>工程实训</font><br>
    <font title="教师">王老师</font><br>
    <font title="周次(节次)">17(周)[06-07-08-09节]</font><br>
    <font title="教室">601005一机房A区</font>
  </div></td>
  <td></td><td></td><td></td><td></td><td></td><td></td>
</tr>
</table>
</body></html>
''';

int _renderStackChildCount(RenderStack stack) {
  var count = 0;
  var child = stack.firstChild;
  while (child != null) {
    count++;
    child = stack.childAfter(child);
  }
  return count;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'parsed cross-row week-17 4-slot course switches cleanly to week 17 and back without covering earlier weeks',
    (tester) async {
      final parsed = ScheduleParser.parse(_crossRowFourSlotHtml);
      expect(parsed.courses, hasLength(3));

      final gateway = _FakeScheduleGateway(parsed.courses);
      final container = ProviderContainer(
        overrides: [
          campusGatewayProvider.overrideWithValue(gateway),
          semesterServiceProvider.overrideWithValue(
            SemesterService(
              initialCache: SemesterCacheSnapshot(
                defaultStart: DateTime(2026, 3, 2),
              ),
              initialAccountId: 'u',
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(credentialsProvider.notifier).set('u', 'p');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SchedulePage()),
        ),
      );
      await tester.pumpAndSettle();

      // Week 16: Monday 6-7 and 8-9 active; week 17 course hidden.
      container.read(selectedWeekProvider.notifier).setWeek(16);
      await tester.pumpAndSettle();
      expect(find.text('高等数学'), findsOneWidget);
      expect(find.text('数据结构'), findsOneWidget);
      expect(find.text('工程实训'), findsNothing);

      final mondayStack = tester.renderObject<RenderStack>(
        find
            .ancestor(of: find.text('高等数学'), matching: find.byType(Stack))
            .first,
      );
      final week16ChildCountBefore = _renderStackChildCount(mondayStack);

      // Navigate to week 17: only the 4-slot course is active on Monday 6-9.
      container.read(selectedWeekProvider.notifier).setWeek(17);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('工程实训'), findsOneWidget);
      expect(find.text('高等数学'), findsNothing);
      expect(find.text('数据结构'), findsNothing);

      // Navigate back to weeks 16, 15, and 1: the 4-slot course must vanish
      // completely without leaving an orphaned RenderBox covering slots 6-9.
      for (final week in [16, 15, 1]) {
        container.read(selectedWeekProvider.notifier).setWeek(week);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.text('工程实训'),
          findsNothing,
          reason: 'Week $week must not show week 17 four-slot course',
        );
        expect(find.text('高等数学'), findsOneWidget);
        expect(find.text('数据结构'), findsOneWidget);
        expect(
          _renderStackChildCount(mondayStack),
          week16ChildCountBefore,
          reason:
              'Monday RenderStack must not leak child render objects on week $week',
        );
      }

      // Week 18 (all 3 inactive): summary cell must count 3 courses, not 4.
      container.read(selectedWeekProvider.notifier).setWeek(18);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('本周无课 · 3 门'), findsOneWidget);
    },
  );

  testWidgets(
    'un-deduplicated gateway response with duplicated 4-slot course never throws or leaks overlay',
    (tester) async {
      final gateway = _FakeScheduleGateway([
        _mondaySlot67,
        _mondaySlot89,
        _week17FourSlot,
        Course.fromJson(_week17FourSlot.toJson()),
      ]);
      final container = ProviderContainer(
        overrides: [
          campusGatewayProvider.overrideWithValue(gateway),
          semesterServiceProvider.overrideWithValue(
            SemesterService(
              initialCache: SemesterCacheSnapshot(
                defaultStart: DateTime(2026, 3, 2),
              ),
              initialAccountId: 'u',
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(credentialsProvider.notifier).set('u', 'p');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SchedulePage()),
        ),
      );
      await tester.pumpAndSettle();

      container.read(selectedWeekProvider.notifier).setWeek(16);
      await tester.pumpAndSettle();
      final mondayStack = tester.renderObject<RenderStack>(
        find
            .ancestor(of: find.text('高等数学'), matching: find.byType(Stack))
            .first,
      );
      final week16ChildCountBefore = _renderStackChildCount(mondayStack);

      container.read(selectedWeekProvider.notifier).setWeek(17);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('工程实训'), findsOneWidget);

      for (final week in [16, 15, 1]) {
        container.read(selectedWeekProvider.notifier).setWeek(week);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('工程实训'), findsNothing);
        expect(find.text('高等数学'), findsOneWidget);
        expect(find.text('数据结构'), findsOneWidget);
        expect(_renderStackChildCount(mondayStack), week16ChildCountBefore);
      }
    },
  );

  testWidgets(
    'duplicate custom courses at the same slot never cause duplicate Stack keys across week switches',
    (tester) async {
      final customA = _week17FourSlot.copyWith(isCustom: true);
      final customB = _week17FourSlot.copyWith(isCustom: true);
      final gateway = _FakeScheduleGateway([_mondaySlot67, _mondaySlot89]);
      final container = ProviderContainer(
        overrides: [
          campusGatewayProvider.overrideWithValue(gateway),
          semesterServiceProvider.overrideWithValue(
            SemesterService(
              initialCache: SemesterCacheSnapshot(
                defaultStart: DateTime(2026, 3, 2),
              ),
              initialAccountId: 'u',
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(credentialsProvider.notifier).set('u', 'p');

      await container
          .read(customCoursesProvider(null).notifier)
          .addCourse(customA);
      await container
          .read(customCoursesProvider(null).notifier)
          .addCourse(customB);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SchedulePage()),
        ),
      );
      await tester.pumpAndSettle();

      container.read(selectedWeekProvider.notifier).setWeek(16);
      await tester.pumpAndSettle();
      final mondayStack = tester.renderObject<RenderStack>(
        find
            .ancestor(of: find.text('高等数学'), matching: find.byType(Stack))
            .first,
      );
      final expectedCount = _renderStackChildCount(mondayStack);

      container.read(selectedWeekProvider.notifier).setWeek(17);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('工程实训'), findsNWidgets(2));

      container.read(selectedWeekProvider.notifier).setWeek(16);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('工程实训'), findsNothing);
      expect(find.text('高等数学'), findsOneWidget);
      expect(find.text('数据结构'), findsOneWidget);
      expect(_renderStackChildCount(mondayStack), expectedCount);
    },
  );

  test(
    'ScheduleNotifier.decode deduplicates legacy cached school courses without requiring force refresh',
    () async {
      final cacheKey = resourceCacheKey(
        'schedule',
        username: 'u',
        scope: '2025-2026-2',
      );
      SharedPreferences.setMockInitialValues({
        cacheKey: jsonEncode({
          'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
          'data': {
            'courses': [
              _mondaySlot67.toJson(),
              _mondaySlot89.toJson(),
              _week17FourSlot.toJson(),
              _week17FourSlot.toJson(),
            ],
            'remark': 'cached-remark',
          },
        }),
      });

      final gateway = _FakeScheduleGateway(const [], failSchedule: true);
      final container = ProviderContainer(
        overrides: [
          campusGatewayProvider.overrideWithValue(gateway),
          semesterServiceProvider.overrideWithValue(
            SemesterService(
              initialCache: SemesterCacheSnapshot(
                defaultStart: DateTime(2026, 3, 2),
              ),
              initialAccountId: 'u',
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(credentialsProvider.notifier).set('u', 'p');

      await container
          .read(scheduleProvider(null).notifier)
          .restoreCachedThenRefresh(forceRefresh: false);

      final cachedCourses = container.read(scheduleProvider(null)).data.courses;
      expect(cachedCourses.where((c) => c.name == '工程实训'), hasLength(1));
      expect(cachedCourses, hasLength(3));
    },
  );
}
