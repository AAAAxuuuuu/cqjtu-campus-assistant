import 'package:campus_app/features/auth/auth_providers.dart';
import 'package:campus_app/features/grades/grades_providers.dart';
import 'package:campus_app/features/study_progress/study_progress_providers.dart';
import 'package:campus_app/pages/academic_status_page.dart';
import 'package:campus_app/providers/runtime_mode.dart';
import 'package:core/models/course.dart';
import 'package:core/models/exam.dart';
import 'package:core/models/grade.dart';
import 'package:core/models/study_progress.dart';
import 'package:data/data.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeCampusGateway implements CampusGateway {
  final Map<String, ({Map<String, String> summary, List<Grade> grades})>
  gradesUserStore = {};
  final Map<String, StudyProgressData> studyProgressUserStore = {};

  @override
  Future<({Map<String, String> summary, List<Grade> grades})> getGrades(
    String username,
    String password, {
    String semester = '',
    bool forceRefresh = false,
  }) async {
    return gradesUserStore[username] ??
        (summary: <String, String>{}, grades: <Grade>[]);
  }

  @override
  Future<StudyProgressData> getStudyProgress(
    String username,
    String password, {
    bool forceRefresh = false,
  }) async {
    return studyProgressUserStore[username] ??
        const StudyProgressData(
          groups: [],
          currentSemester: '2025-2026-1',
          currentSemesterCourses: [],
        );
  }

  @override
  Future<GradeDetail> getGradeDetail(
    String username,
    String password, {
    required Grade grade,
    bool forceRefresh = false,
  }) async => const GradeDetail(items: [], totalScore: '');

  @override
  Future<({List<Course> courses, String remark})> getSchedule(
    String username,
    String password, {
    String? semester,
    bool forceRefresh = false,
  }) async => (courses: <Course>[], remark: '');

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
  }) async => '';

  @override
  Future<String> getPayCodeToken(String username, {String? password}) async =>
      '';

  @override
  Future<String> getCampusCardAlipayUrl(
    String username,
    double amount, {
    String? password,
  }) async => '';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Academic Card Dynamic Data Adaptation & Fallbacks (R1)', () {
    test(
      'Test 1: Standard numeric grades - computes passedCredits, failedCourses, weightedAverage, and calculatedGpa',
      () {
        const grades = [
          Grade(
            semester: '2025-2026-1',
            courseCode: 'CS101',
            courseName: 'Data Structures',
            score: '85',
            credits: '4.0',
            gradePoint: '3.5',
            courseAttribute: 'Compulsory',
            courseNature: 'Major',
          ),
          Grade(
            semester: '2025-2026-1',
            courseCode: 'CS102',
            courseName: 'Algorithms',
            score: '90',
            credits: '3.0',
            gradePoint: '4.0',
            courseAttribute: 'Compulsory',
            courseNature: 'Major',
          ),
          Grade(
            semester: '2025-2026-1',
            courseCode: 'CS103',
            courseName: 'Compiler Design',
            score: '50',
            credits: '2.0',
            gradePoint: '0.0',
            courseAttribute: 'Compulsory',
            courseNature: 'Major',
          ),
        ];

        final stats = AcademicStats.fromGrades(grades);

        expect(stats.totalCourses, 3);
        expect(stats.failedCourses, 1);
        expect(stats.passedCredits, 7.0);
        // (85*4 + 90*3 + 50*2) / 9 = (340 + 270 + 100) / 9 = 710 / 9 = 78.888...
        expect(stats.weightedAverage, closeTo(78.89, 0.01));
        // (3.5*4 + 4.0*3 + 0.0*2) / 9 = (14 + 12 + 0) / 9 = 26 / 9 = 2.888...
        expect(stats.calculatedGpa, closeTo(2.89, 0.01));
      },
    );

    test(
      'Test 2: Chinese text grades (优秀, 良好, 及格, 不及格, 不合格, PASS, FAIL) - parses scores correctly',
      () {
        const grades = [
          Grade(
            semester: '2025-2026-1',
            courseCode: 'ART101',
            courseName: 'Music Appreciation',
            score: '优秀',
            credits: '2.0',
            gradePoint: '4.0',
            courseAttribute: 'Elective',
            courseNature: 'General',
          ),
          Grade(
            semester: '2025-2026-1',
            courseCode: 'PE101',
            courseName: 'Physical Education',
            score: '及格',
            credits: '1.0',
            gradePoint: '1.0',
            courseAttribute: 'Compulsory',
            courseNature: 'General',
          ),
          Grade(
            semester: '2025-2026-1',
            courseCode: 'LAB101',
            courseName: 'Safety Exam',
            score: '不及格',
            credits: '1.0',
            gradePoint: '0.0',
            courseAttribute: 'Compulsory',
            courseNature: 'General',
          ),
        ];

        final stats = AcademicStats.fromGrades(grades);

        expect(stats.totalCourses, 3);
        expect(stats.passedCredits, 3.0);
        expect(stats.failedCourses, 1);
        // Scores parsed: 优秀->90.0, 及格->60.0, 不及格->50.0
        // Weighted average: (90*2 + 60*1 + 50*1) / 4 = (180 + 60 + 50) / 4 = 290 / 4 = 72.5
        expect(stats.weightedAverage, closeTo(72.5, 0.01));
      },
    );

    test(
      'Test 3: Fallback gradePoint calculation when gradePoint is missing',
      () {
        const grades = [
          Grade(
            semester: '2025-2026-1',
            courseCode: 'MATH101',
            courseName: 'Calculus I',
            score: '80',
            credits: '4.0',
            gradePoint: '-', // Missing gradePoint
            courseAttribute: 'Compulsory',
            courseNature: 'Foundation',
          ),
        ];

        final stats = AcademicStats.fromGrades(grades);

        expect(stats.totalCourses, 1);
        expect(stats.passedCredits, 4.0);
        expect(stats.failedCourses, 0);
        expect(stats.weightedAverage, 80.0);
        // Fallback gradePoint for 80 = (80 - 50) / 10 = 3.0
        expect(stats.calculatedGpa, closeTo(3.0, 0.01));
      },
    );

    test('Test 4: Empty grade list - handles zero credits safely', () {
      final stats = AcademicStats.fromGrades(const []);

      expect(stats.totalCourses, 0);
      expect(stats.failedCourses, 0);
      expect(stats.passedCredits, 0.0);
      expect(stats.weightedAverage, isNull);
      expect(stats.calculatedGpa, isNull);
    });
  });

  group('Account Dynamic Rendering & Credential-Switching Cache Invalidation', () {
    test(
      'Test 5: Switching credentials from Student A to Student B invalidates cache and renders Student B academic data dynamically',
      () async {
        final fakeGateway = FakeCampusGateway();

        // Setup Student A data
        fakeGateway.gradesUserStore['student_a'] = (
          summary: {
            'gpa': '3.80',
            'avgScore': '88.5',
            'classRank': '1',
            'majorRank': '5',
          },
          grades: [
            const Grade(
              semester: '2025-2026-1',
              courseCode: 'CS101',
              courseName: 'Student A Course',
              score: '95',
              credits: '3.0',
              gradePoint: '4.5',
              courseAttribute: 'Compulsory',
              courseNature: 'Major',
            ),
          ],
        );

        // Setup Student B data
        fakeGateway.gradesUserStore['student_b'] = (
          summary: {
            'gpa': '2.50',
            'avgScore': '75.0',
            'classRank': '15',
            'majorRank': '40',
          },
          grades: [
            const Grade(
              semester: '2025-2026-1',
              courseCode: 'EE101',
              courseName: 'Student B Course',
              score: '75',
              credits: '4.0',
              gradePoint: '2.5',
              courseAttribute: 'Compulsory',
              courseNature: 'Major',
            ),
          ],
        );

        final container = ProviderContainer(
          overrides: [campusGatewayProvider.overrideWithValue(fakeGateway)],
        );
        addTearDown(container.dispose);

        // 1. Log in as Student A
        container.read(credentialsProvider.notifier).set('student_a', 'pass_a');
        await container
            .read(gradesProvider('').notifier)
            .refresh(forceRefresh: true);

        final gradesResourceA = container.read(gradesProvider(''));
        expect(gradesResourceA.data.summary['gpa'], '3.80');
        expect(gradesResourceA.data.summary['avgScore'], '88.5');
        expect(gradesResourceA.data.grades, hasLength(1));
        expect(
          gradesResourceA.data.grades.first.courseName,
          'Student A Course',
        );

        // 2. Switch account to Student B
        container.read(credentialsProvider.notifier).set('student_b', 'pass_b');
        await container
            .read(gradesProvider('').notifier)
            .refresh(forceRefresh: true);

        final gradesResourceB = container.read(gradesProvider(''));
        expect(gradesResourceB.data.summary['gpa'], '2.50');
        expect(gradesResourceB.data.summary['avgScore'], '75.0');
        expect(gradesResourceB.data.grades, hasLength(1));
        expect(
          gradesResourceB.data.grades.first.courseName,
          'Student B Course',
        );

        // 3. Switch back to Student A - verifies cache key scope and dynamic reload
        container.read(credentialsProvider.notifier).set('student_a', 'pass_a');
        await container
            .read(gradesProvider('').notifier)
            .refresh(forceRefresh: true);

        final restoredGradesA = container.read(gradesProvider(''));
        expect(restoredGradesA.data.summary['gpa'], '3.80');
        expect(
          restoredGradesA.data.grades.first.courseName,
          'Student A Course',
        );
      },
    );

    test(
      'Test 6: Study progress provider updates dynamically on account switch',
      () async {
        final fakeGateway = FakeCampusGateway();

        fakeGateway.studyProgressUserStore['student_a'] =
            const StudyProgressData(
              groups: [
                StudyProgressGroup(
                  id: '1',
                  title: '必修课',
                  requiredCredits: '4.0',
                  courses: [
                    StudyProgressCourse(
                      code: 'CS101',
                      name: 'Prog 1',
                      credits: '4.0',
                      attribute: '必修',
                      status: '已修读',
                      score: '90',
                      semester: '2025-2026-1',
                    ),
                  ],
                ),
              ],
              currentSemester: '2025-2026-1',
              currentSemesterCourses: [],
            );

        fakeGateway.studyProgressUserStore['student_b'] =
            const StudyProgressData(
              groups: [
                StudyProgressGroup(
                  id: '2',
                  title: '选修课',
                  requiredCredits: '2.0',
                  courses: [
                    StudyProgressCourse(
                      code: 'EE101',
                      name: 'Circuit 1',
                      credits: '2.0',
                      attribute: '选修',
                      status: '已修读',
                      score: '55',
                      semester: '2025-2026-1',
                    ),
                  ],
                ),
              ],
              currentSemester: '2025-2026-1',
              currentSemesterCourses: [],
            );

        final container = ProviderContainer(
          overrides: [campusGatewayProvider.overrideWithValue(fakeGateway)],
        );
        addTearDown(container.dispose);

        // Login as Student A
        container.read(credentialsProvider.notifier).set('student_a', 'pass_a');
        await container
            .read(studyProgressProvider.notifier)
            .refresh(forceRefresh: true);

        final summaryA = container.read(studyCreditProgressSummaryProvider);
        expect(summaryA.earnedCredits, 4.0);

        // Switch to Student B
        container.read(credentialsProvider.notifier).set('student_b', 'pass_b');
        await container
            .read(studyProgressProvider.notifier)
            .refresh(forceRefresh: true);

        final summaryB = container.read(studyCreditProgressSummaryProvider);
        expect(summaryB.earnedCredits, 0.0);
      },
    );

    test(
      'uses learning progress for core credits and grades for school-elective credits',
      () async {
        final fakeGateway = FakeCampusGateway();
        fakeGateway.gradesUserStore['student'] = (
          summary: <String, String>{},
          grades: const [
            Grade(
              semester: '2025-2026-1',
              courseCode: 'SCHOOL-GRADE-1',
              courseName: '成绩查询中的校选课',
              score: '75',
              credits: '2.5',
              gradePoint: '3.0',
              courseAttribute: '校选',
              courseNature: '通识教育课程',
            ),
            Grade(
              semester: '2025-2026-1',
              courseCode: 'NOT-SCHOOL-1',
              courseName: '不应计入校选的选修课',
              score: '90',
              credits: '9',
              gradePoint: '4.0',
              courseAttribute: '选修',
              courseNature: '通识教育课程',
            ),
          ],
        );
        fakeGateway.studyProgressUserStore['student'] = const StudyProgressData(
          groups: [
            StudyProgressGroup(
              id: 'compulsory',
              title: '必修课程',
              creditCategory: '必修',
              requiredCredits: '12',
              courses: [
                StudyProgressCourse(
                  code: 'MATH-AII',
                  name: '高等数学AII',
                  credits: '5（计划内）',
                  attribute: '必修',
                  status: '已修读',
                  score: '34',
                  semester: '2024-2025-1',
                ),
                StudyProgressCourse(
                  code: 'MATH-AII',
                  name: '高等数学AII',
                  credits: '5（计划内）',
                  attribute: '必修',
                  status: '已修读',
                  score: '54',
                  semester: '2025-2026-1',
                ),
                StudyProgressCourse(
                  code: 'RETAKE-1',
                  name: '重修后通过的课程',
                  credits: '3',
                  attribute: '必修',
                  status: '已修读',
                  score: '45',
                  semester: '2024-2025-1',
                ),
                StudyProgressCourse(
                  code: 'RETAKE-1',
                  name: '重修后通过的课程',
                  credits: '3',
                  attribute: '必修',
                  status: '已修读',
                  score: '78',
                  semester: '2025-2026-1',
                ),
                StudyProgressCourse(
                  code: 'COMP-1',
                  name: '已及格必修',
                  credits: '4',
                  attribute: '必修',
                  status: '已修读',
                  score: '及格',
                  semester: '2025-2026-1',
                ),
              ],
            ),
            StudyProgressGroup(
              id: 'elective',
              title: '选修课程',
              creditCategory: '选修',
              requiredCredits: '9',
              courses: [
                StudyProgressCourse(
                  code: 'LIMIT-1',
                  name: '限选课',
                  credits: '2',
                  attribute: '限选',
                  status: '已修读',
                  score: '60',
                  semester: '2025-2026-1',
                ),
                StudyProgressCourse(
                  code: 'ANY-1',
                  name: '任选课',
                  credits: '1',
                  attribute: '任选',
                  status: '已修读',
                  score: '合格',
                  semester: '2025-2026-1',
                ),
                StudyProgressCourse(
                  code: 'ELECT-1',
                  name: '选修课',
                  credits: '2',
                  attribute: '选修',
                  status: '已修读',
                  score: 'PASS',
                  semester: '2025-2026-1',
                ),
                StudyProgressCourse(
                  code: 'UNREAD-1',
                  name: '尚未修读的课程',
                  credits: '3',
                  attribute: '选修',
                  status: '未修读',
                  score: '90',
                  semester: '2025-2026-1',
                ),
              ],
            ),
            StudyProgressGroup(
              id: 'school-elective',
              title: '校选课程',
              creditCategory: '校选',
              requiredCredits: '3',
              courses: [
                StudyProgressCourse(
                  code: 'SCHOOL-1',
                  name: '校选课',
                  credits: '3',
                  attribute: '校选',
                  status: '已修读',
                  score: '75',
                  semester: '2025-2026-1',
                ),
              ],
            ),
          ],
          currentSemester: '2025-2026-1',
          currentSemesterCourses: [],
        );

        final container = ProviderContainer(
          overrides: [campusGatewayProvider.overrideWithValue(fakeGateway)],
        );
        addTearDown(container.dispose);

        container.read(credentialsProvider.notifier).set('student', 'pass');
        await container
            .read(studyProgressProvider.notifier)
            .refresh(forceRefresh: true);

        final summary = container.read(studyCreditProgressSummaryProvider);
        expect(
          summary.buckets
              .singleWhere(
                (bucket) => bucket.category == StudyCreditCategory.compulsory,
              )
              .earnedCredits,
          7,
        );
        expect(
          summary.buckets
              .singleWhere(
                (bucket) => bucket.category == StudyCreditCategory.elective,
              )
              .earnedCredits,
          5,
        );
        expect(
          summary.buckets
              .singleWhere(
                (bucket) =>
                    bucket.category == StudyCreditCategory.schoolElective,
              )
              .earnedCredits,
          2.5,
        );
      },
    );
  });

  group('Study-plan required-credit ledger', () {
    test(
      'prefers the academic-home requirement ledger when it is available',
      () {
        final data = StudyProgressViewData(
          sections: const [
            StudyProgressSectionView(
              id: 'plan-compulsory',
              title: '培养计划必修',
              creditCategory: '必修',
              requiredCredits: '157.5',
              earnedCredits: '',
              remainingCredits: '',
              completionRate: '',
              courses: [],
            ),
            StudyProgressSectionView(
              id: 'plan-elective',
              title: '培养计划选修',
              creditCategory: '选修',
              requiredCredits: '15.5',
              earnedCredits: '',
              remainingCredits: '',
              completionRate: '',
              courses: [],
            ),
          ],
          completedCount: 0,
          inProgressCount: 0,
          pendingCount: 0,
          currentSemester: '2025-2026-2',
          completedCreditsFromProgress: const {
            'compulsory': 77,
            'elective': 7,
            'schoolElective': 2,
          },
          requiredCreditsByCategory: const {
            'compulsory': 157.5,
            'elective': 15.5,
            'schoolElective': 3,
          },
        );

        final summary = StudyCreditProgressSummary.fromData(data);

        expect(summary.requiredCredits, 176);
        expect(
          summary.buckets
              .singleWhere(
                (bucket) =>
                    bucket.category == StudyCreditCategory.schoolElective,
              )
              .requiredCredits,
          3,
        );
        expect(
          summary.buckets
              .singleWhere(
                (bucket) =>
                    bucket.category == StudyCreditCategory.schoolElective,
              )
              .earnedCredits,
          2,
        );
      },
    );

    test(
      'falls back to plan totals when the academic-home ledger is unavailable',
      () {
        final data = StudyProgressViewData(
          sections: [
            StudyProgressSectionView(
              id: 'compulsory',
              title: '必修课程',
              creditCategory: '必修',
              requiredCredits: '100',
              earnedCredits: '77',
              remainingCredits: '23',
              completionRate: '77%',
              courses: [
                const StudyProgressCourseView(
                  code: 'A',
                  name: '明细不应覆盖汇总',
                  credits: '84.5',
                  attribute: '必修',
                  status: StudyCourseStatus.completed,
                  statusLabel: '已修读',
                  scoreLabel: '90',
                ),
              ],
            ),
            StudyProgressSectionView(
              id: 'school',
              title: '公共选修',
              creditCategory: '公共选修',
              requiredCredits: '3',
              earnedCredits: '3',
              remainingCredits: '0',
              completionRate: '100%',
              courses: const [],
            ),
            StudyProgressSectionView(
              id: 'elective',
              title: '专业选修',
              creditCategory: '选修',
              requiredCredits: '73',
              earnedCredits: '0',
              remainingCredits: '73',
              completionRate: '0%',
              courses: const [],
            ),
          ],
          completedCount: 1,
          inProgressCount: 0,
          pendingCount: 0,
          currentSemester: '2025-2026-1',
          completedCreditsFromProgress: const {
            'compulsory': 4,
            'elective': 6,
            'schoolElective': 2,
          },
        );

        final summary = StudyCreditProgressSummary.fromData(data);

        expect(summary.requiredCredits, 176);
        expect(
          summary.buckets
              .singleWhere(
                (bucket) => bucket.category == StudyCreditCategory.compulsory,
              )
              .earnedCredits,
          4,
        );
        expect(
          summary.buckets
              .singleWhere(
                (bucket) =>
                    bucket.category == StudyCreditCategory.schoolElective,
              )
              .earnedCredits,
          2,
        );
      },
    );
  });
}
