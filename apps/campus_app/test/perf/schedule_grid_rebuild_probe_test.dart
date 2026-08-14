import 'package:campus_app/features/auth/auth_providers.dart';
import 'package:campus_app/features/schedule/schedule_providers.dart'
    show selectedWeekProvider;
import 'package:campus_app/pages/schedule_page.dart';
import 'package:campus_app/providers/runtime_mode.dart';
import 'package:campus_app/utils/semester_service.dart';
import 'package:core/models/course.dart';
import 'package:core/models/exam.dart';
import 'package:core/models/grade.dart';
import 'package:core/models/study_progress.dart';
import 'package:data/data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Structural rebuild-scope probe for the schedule grid.
///
/// Deterministic, host-runnable evidence for the RepaintBoundary decision:
/// counts which widget types rebuild when the displayed week changes. If the
/// time column and weekday header rebuild together with every course cell,
/// that is the scope evidence required before adding RepaintBoundary.
/// Always passes; prints [PERF] statistics.
class _FakeGateway implements CampusGateway {
  @override
  Future<({List<Course> courses, String remark})> getSchedule(
    String username,
    String password, {
    String? semester,
    bool forceRefresh = false,
  }) async {
    final courses = <Course>[];
    final names = ['高等数学', '大学英语', '线性代数', '数据结构', '计算机网络', '操作系统'];
    var week = 1;
    for (var slot = 1; slot <= 13; slot += 2) {
      for (var day = 1; day <= 5; day++) {
        courses.add(
          Course(
            name: names[(day + slot) % names.length],
            teacher: '教师$day',
            timeStr: '',
            classroom: 'A${100 + day}',
            dayOfWeek: day,
            timeSlot: slot,
            endTimeSlot: slot + 1,
            weekList: [week],
          ),
        );
        week = week % 20 + 1;
      }
    }
    return (courses: courses, remark: 'perf-probe');
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
  }) async => '12.30';

  @override
  Future<String> getCampusCardBalance(
    String username,
    String password, {
    bool forceRefresh = false,
  }) async => '66.80';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('week switch rebuild scope is measured and reported', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        campusGatewayProvider.overrideWithValue(_FakeGateway()),
        semesterServiceProvider.overrideWithValue(
          SemesterService(
            initialCache: SemesterCacheSnapshot(
              defaultStart: DateTime(2026, 2, 23), // a Monday
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

    expect(find.byType(SchedulePage), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);

    final rebuilds = <String>[];
    void onRebuild(Element element, bool builtOnce) {
      if (builtOnce) return; // skip initial builds
      rebuilds.add(element.widget.runtimeType.toString());
    }

    debugOnRebuildDirtyWidget = onRebuild;
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    // Park on a mid-semester week so neither direction clamps.
    container.read(selectedWeekProvider.notifier).setWeek(10);
    await tester.pumpAndSettle();
    final warmWeek = container.read(selectedWeekProvider);
    rebuilds.clear();

    // One representative week switch.
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    final switchedWeek = container.read(selectedWeekProvider);
    expect(switchedWeek, warmWeek + 1, reason: 'tap must advance the week');

    final counts = <String, int>{};
    for (final type in rebuilds) {
      counts[type] = (counts[type] ?? 0) + 1;
    }
    final top = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final summary = top.take(12).map((e) => '${e.key}=${e.value}').join(', ');
    debugPrint(
      '[PERF] week-switch rebuilds total=${rebuilds.length} types=${counts.length} | $summary',
    );

    expect(rebuilds, isNotEmpty, reason: 'a week switch must rebuild widgets');
  });
}
