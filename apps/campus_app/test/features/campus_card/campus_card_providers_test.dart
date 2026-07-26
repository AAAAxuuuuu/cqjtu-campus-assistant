import 'package:campus_app/features/auth/auth_providers.dart';
import 'package:campus_app/features/campus_card/campus_card_providers.dart';
import 'package:campus_app/providers/runtime_mode.dart';
import 'package:core/models/course.dart';
import 'package:core/models/exam.dart';
import 'package:core/models/grade.dart';
import 'package:core/models/study_progress.dart';
import 'package:data/data.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TrackingCampusGateway implements CampusGateway {
  final List<bool> balanceForceRefreshValues = [];
  int payCodeCalls = 0;

  @override
  Future<String> getCampusCardBalance(
    String username,
    String password, {
    bool forceRefresh = false,
  }) async {
    balanceForceRefreshValues.add(forceRefresh);
    return '66.80';
  }

  @override
  Future<String> getPayCodeToken(String username, {String? password}) async {
    payCodeCalls++;
    return 'pay-code-token';
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
  Future<String> rechargeElec(
    String username,
    double amount, {
    String? password,
    Map<String, String>? dormParams,
  }) async => '';

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

  test(
    'entering the campus-card page force-refreshes balance and pay code',
    () async {
      final gateway = TrackingCampusGateway();
      final container = ProviderContainer(
        overrides: [campusGatewayProvider.overrideWithValue(gateway)],
      );
      addTearDown(container.dispose);
      container.read(credentialsProvider.notifier).set('student', 'password');

      await refreshCampusCardOnEntry(
        container.read(campusCardBalanceProvider.notifier),
        container.read(payCodeProvider.notifier),
      );

      expect(gateway.balanceForceRefreshValues, contains(true));
      expect(container.read(campusCardBalanceProvider).data, '66.80');
      expect(container.read(payCodeProvider).token, 'pay-code-token');
      expect(gateway.payCodeCalls, greaterThanOrEqualTo(1));
    },
  );
}
