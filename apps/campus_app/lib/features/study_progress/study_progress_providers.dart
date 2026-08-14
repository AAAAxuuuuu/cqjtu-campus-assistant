import 'package:core/models/grade.dart';
import 'package:core/models/study_progress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/runtime_mode.dart';
import '../auth/auth_providers.dart';
import '../shared/cached_resource.dart';

enum StudyCourseStatus { completed, inProgress, pending }

enum StudyCreditCategory { compulsory, elective, schoolElective }

class StudyProgressCourseView {
  const StudyProgressCourseView({
    required this.code,
    required this.name,
    required this.credits,
    required this.attribute,
    required this.status,
    required this.statusLabel,
    required this.scoreLabel,
    this.semester = '',
    this.grade,
  });

  final String code;
  final String name;
  final String credits;
  final String attribute;
  final StudyCourseStatus status;
  final String statusLabel;
  final String scoreLabel;
  final String semester;
  final Grade? grade;

  factory StudyProgressCourseView.fromJson(Map<String, dynamic> json) =>
      StudyProgressCourseView(
        code: json['code'] as String? ?? '',
        name: json['name'] as String? ?? '',
        credits: json['credits'] as String? ?? '',
        attribute: json['attribute'] as String? ?? '',
        status: StudyCourseStatus.values.firstWhere(
          (value) => value.name == json['status'],
          orElse: () => StudyCourseStatus.pending,
        ),
        statusLabel: json['statusLabel'] as String? ?? '',
        scoreLabel: json['scoreLabel'] as String? ?? '',
        semester: json['semester'] as String? ?? '',
        grade: json['grade'] is Map
            ? Grade.fromJson(Map<String, dynamic>.from(json['grade'] as Map))
            : null,
      );

  Map<String, dynamic> toJson() => {
    'code': code,
    'name': name,
    'credits': credits,
    'attribute': attribute,
    'status': status.name,
    'statusLabel': statusLabel,
    'scoreLabel': scoreLabel,
    'semester': semester,
    'grade': grade?.toJson(),
  };
}

class StudyProgressSectionView {
  const StudyProgressSectionView({
    required this.id,
    required this.title,
    required this.creditCategory,
    required this.requiredCredits,
    required this.earnedCredits,
    required this.remainingCredits,
    required this.completionRate,
    required this.courses,
  });

  final String id;
  final String title;
  final String creditCategory;
  final String requiredCredits;
  final String earnedCredits;
  final String remainingCredits;
  final String completionRate;
  final List<StudyProgressCourseView> courses;

  factory StudyProgressSectionView.fromJson(
    Map<String, dynamic> json,
  ) => StudyProgressSectionView(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    creditCategory: json['creditCategory'] as String? ?? '',
    requiredCredits: json['requiredCredits'] as String? ?? '',
    earnedCredits: json['earnedCredits'] as String? ?? '',
    remainingCredits: json['remainingCredits'] as String? ?? '',
    completionRate: json['completionRate'] as String? ?? '',
    courses: (json['courses'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) =>
              StudyProgressCourseView.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'creditCategory': creditCategory,
    'requiredCredits': requiredCredits,
    'earnedCredits': earnedCredits,
    'remainingCredits': remainingCredits,
    'completionRate': completionRate,
    'courses': courses.map((course) => course.toJson()).toList(),
  };
}

class StudyProgressViewData {
  const StudyProgressViewData({
    required this.sections,
    required this.completedCount,
    required this.inProgressCount,
    required this.pendingCount,
    required this.currentSemester,
    this.completedCreditsFromProgress = const {},
    this.requiredCreditsByCategory = const {},
  });

  final List<StudyProgressSectionView> sections;
  final int completedCount;
  final int inProgressCount;
  final int pendingCount;
  final String currentSemester;
  final Map<String, double> completedCreditsFromProgress;
  final Map<String, double> requiredCreditsByCategory;

  factory StudyProgressViewData.fromJson(Map<String, dynamic> json) =>
      StudyProgressViewData(
        sections: (json['sections'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (item) => StudyProgressSectionView.fromJson(
                Map<String, dynamic>.from(item),
              ),
            )
            .toList(),
        completedCount: json['completedCount'] as int? ?? 0,
        inProgressCount: json['inProgressCount'] as int? ?? 0,
        pendingCount: json['pendingCount'] as int? ?? 0,
        currentSemester: json['currentSemester'] as String? ?? '',
        completedCreditsFromProgress:
            (json['completedCreditsFromProgress'] as Map? ?? const {}).map(
              (key, value) =>
                  MapEntry(key.toString(), _parseCredit(value.toString())),
            ),
        requiredCreditsByCategory:
            (json['requiredCreditsByCategory'] as Map? ?? const {}).map(
              (key, value) =>
                  MapEntry(key.toString(), _parseCredit(value.toString())),
            ),
      );

  Map<String, dynamic> toJson() => {
    'sections': sections.map((section) => section.toJson()).toList(),
    'completedCount': completedCount,
    'inProgressCount': inProgressCount,
    'pendingCount': pendingCount,
    'currentSemester': currentSemester,
    'completedCreditsFromProgress': completedCreditsFromProgress,
    'requiredCreditsByCategory': requiredCreditsByCategory,
  };
}

class StudyCreditBucketView {
  const StudyCreditBucketView({
    required this.category,
    required this.label,
    required this.requiredCredits,
    required this.earnedCredits,
  });

  final StudyCreditCategory category;
  final String label;
  final double requiredCredits;
  final double earnedCredits;
}

class StudyCreditProgressSummary {
  const StudyCreditProgressSummary({
    required this.buckets,
    required this.completedCount,
    required this.inProgressCount,
    required this.pendingCount,
    required this.currentSemester,
  });

  final List<StudyCreditBucketView> buckets;
  final int completedCount;
  final int inProgressCount;
  final int pendingCount;
  final String currentSemester;

  double get requiredCredits =>
      buckets.fold<double>(0, (sum, bucket) => sum + bucket.requiredCredits);

  double get earnedCredits =>
      buckets.fold<double>(0, (sum, bucket) => sum + bucket.earnedCredits);

  bool get hasCreditData => requiredCredits > 0 || earnedCredits > 0;

  factory StudyCreditProgressSummary.fromData(StudyProgressViewData data) {
    final totals = {
      StudyCreditCategory.compulsory: _MutableCreditBucket(label: '必修'),
      StudyCreditCategory.elective: _MutableCreditBucket(label: '选修'),
      StudyCreditCategory.schoolElective: _MutableCreditBucket(label: '校选'),
    };

    for (final section in data.sections) {
      if (_isSummarySection(section)) continue;

      final sectionCategory = _creditCategoryForSection(section);
      totals[sectionCategory]!.requiredCredits += _parseCredit(
        section.requiredCredits,
      );
    }

    for (final category in StudyCreditCategory.values) {
      final officialRequired = data.requiredCreditsByCategory[category.name];
      if (officialRequired != null) {
        totals[category]!.requiredCredits = officialRequired;
      }
    }

    for (final category in StudyCreditCategory.values) {
      totals[category]!.earnedCredits =
          data.completedCreditsFromProgress[category.name] ?? 0;
    }

    return StudyCreditProgressSummary(
      buckets: [
        for (final category in StudyCreditCategory.values)
          StudyCreditBucketView(
            category: category,
            label: totals[category]!.label,
            requiredCredits: totals[category]!.requiredCredits,
            earnedCredits: totals[category]!.earnedCredits,
          ),
      ],
      completedCount: data.completedCount,
      inProgressCount: data.inProgressCount,
      pendingCount: data.pendingCount,
      currentSemester: data.currentSemester,
    );
  }
}

class _MutableCreditBucket {
  _MutableCreditBucket({required this.label});

  final String label;
  double requiredCredits = 0;
  double earnedCredits = 0;
}

final studyProgressProvider =
    NotifierProvider<
      StudyProgressNotifier,
      CachedResource<StudyProgressViewData>
    >(StudyProgressNotifier.new);

final studyCreditProgressSummaryProvider = Provider<StudyCreditProgressSummary>(
  (ref) {
    final progress = ref.watch(studyProgressProvider);
    return StudyCreditProgressSummary.fromData(progress.data);
  },
);

class StudyProgressNotifier
    extends SimpleCachedResourceNotifier<StudyProgressViewData> {
  @override
  StudyProgressViewData get emptyData => const StudyProgressViewData(
    sections: [],
    completedCount: 0,
    inProgressCount: 0,
    pendingCount: 0,
    currentSemester: '',
  );

  @override
  String get cacheNamespace => 'study_progress';

  @override
  Duration get cacheFreshness => const Duration(hours: 6);

  @override
  Object? encode(StudyProgressViewData data) => data.toJson();

  @override
  StudyProgressViewData decode(Object? json) {
    if (json is! Map) return emptyData;
    return StudyProgressViewData.fromJson(Map<String, dynamic>.from(json));
  }

  @override
  Future<StudyProgressViewData> fetch(
    ({String username, String password}) credentials, {
    required bool forceRefresh,
  }) async {
    ensureCredentialPassword(credentials);
    final gateway = ref.read(campusGatewayProvider);
    final progress = await gateway.getStudyProgress(
      credentials.username,
      credentials.password,
      forceRefresh: forceRefresh,
    );
    final grades = await gateway.getGrades(
      credentials.username,
      credentials.password,
      forceRefresh: forceRefresh,
    );
    return _buildStudyProgressView(progress, grades.grades);
  }
}

StudyProgressViewData _buildStudyProgressView(
  StudyProgressData progress,
  List<Grade> grades,
) {
  final currentKeys = progress.currentSemesterCourses
      .map(_courseKeyFromExecutionPlan)
      .toSet();
  final gradesByCode = <String, List<Grade>>{};
  final gradesByName = <String, List<Grade>>{};

  for (final grade in grades) {
    final codeKey = _normalizeCode(grade.courseCode);
    if (codeKey.isNotEmpty) {
      gradesByCode.putIfAbsent(codeKey, () => []).add(grade);
    }
    final nameKey = _normalizeName(grade.courseName);
    if (nameKey.isNotEmpty) {
      gradesByName.putIfAbsent(nameKey, () => []).add(grade);
    }
  }

  var completedCount = 0;
  var inProgressCount = 0;
  var pendingCount = 0;

  final sections = progress.groups.map((group) {
    final courses = group.courses.map((course) {
      final matchedGrade = _matchGrade(course, gradesByCode, gradesByName);
      final sourceStatus = _statusFromSource(course.status);
      final derivedStatus =
          sourceStatus ??
          (_hasCompletedGrade(matchedGrade)
              ? StudyCourseStatus.completed
              : currentKeys.contains(_courseKey(course.code, course.name))
              ? StudyCourseStatus.inProgress
              : StudyCourseStatus.pending);

      switch (derivedStatus) {
        case StudyCourseStatus.completed:
          completedCount++;
          break;
        case StudyCourseStatus.inProgress:
          inProgressCount++;
          break;
        case StudyCourseStatus.pending:
          pendingCount++;
          break;
      }

      final scoreLabel = _scoreLabel(course, matchedGrade, derivedStatus);
      final attribute = [
        course.attribute.trim(),
        course.nature.trim(),
      ].where((item) => item.isNotEmpty).join(' / ');

      return StudyProgressCourseView(
        code: course.code,
        name: course.name,
        credits: course.credits,
        attribute: attribute.isEmpty ? '未标注' : attribute,
        status: derivedStatus,
        statusLabel: _statusLabel(derivedStatus),
        scoreLabel: scoreLabel,
        semester: course.semester,
        grade: matchedGrade,
      );
    }).toList();

    return StudyProgressSectionView(
      id: group.id.isEmpty ? group.title : group.id,
      title: group.title,
      creditCategory: group.creditCategory,
      requiredCredits: group.requiredCredits,
      earnedCredits: group.earnedCredits,
      remainingCredits: group.remainingCredits,
      completionRate: group.completionRate,
      courses: courses,
    );
  }).toList();

  final completedCreditsFromProgress = _completedCreditsFromProgress(progress);
  completedCreditsFromProgress[StudyCreditCategory.schoolElective.name] =
      _completedSchoolElectiveCreditsFromGrades(grades);

  return StudyProgressViewData(
    sections: sections,
    completedCount: completedCount,
    inProgressCount: inProgressCount,
    pendingCount: pendingCount,
    currentSemester: progress.currentSemester,
    completedCreditsFromProgress: completedCreditsFromProgress,
    requiredCreditsByCategory: progress.requiredCreditsByCategory,
  );
}

double _completedSchoolElectiveCreditsFromGrades(List<Grade> grades) => grades
    .where((grade) => grade.courseAttribute.trim() == '校选')
    .fold<double>(0, (total, grade) => total + _parseCredit(grade.credits));

Map<String, double> _completedCreditsFromProgress(StudyProgressData progress) {
  final totals = <String, double>{
    for (final category in StudyCreditCategory.values) category.name: 0,
  };
  final coursesByKey = <String, List<StudyProgressCourse>>{};

  for (final group in progress.groups) {
    for (final course in group.courses) {
      if (_creditCategoryForProgressCourse(course) == null) continue;
      coursesByKey
          .putIfAbsent(_courseKey(course.code, course.name), () => [])
          .add(course);
    }
  }

  for (final courses in coursesByKey.values) {
    final passedCourses = courses
        .where(_isPassedStudyProgressCourse)
        .toList(growable: false);
    if (passedCourses.isEmpty) continue;

    final passedCourse = passedCourses.firstWhere(
      (course) => _parseCredit(course.credits) > 0,
      orElse: () => passedCourses.first,
    );
    final category = _creditCategoryForProgressCourse(passedCourse);
    final credits = _parseCredit(passedCourse.credits);
    if (category != null && credits > 0) {
      totals[category.name] = totals[category.name]! + credits;
    }
  }

  return totals;
}

StudyCreditCategory? _creditCategoryForProgressCourse(
  StudyProgressCourse course,
) {
  switch (course.attribute.trim()) {
    case '必修':
      return StudyCreditCategory.compulsory;
    case '限选':
    case '任选':
    case '选修':
      return StudyCreditCategory.elective;
    case '校选':
      return StudyCreditCategory.schoolElective;
    default:
      return null;
  }
}

bool _isPassedStudyProgressCourse(StudyProgressCourse course) =>
    course.status.trim() == '已修读' && _isPassingScore(course.score);

bool _isPassingScore(String value) {
  final normalized = value.trim();
  final numericScore = double.tryParse(normalized);
  if (numericScore != null) return numericScore >= 60;

  switch (normalized.toUpperCase()) {
    case '及格':
    case '合格':
    case '通过':
    case 'PASS':
    case 'P':
    case '优':
    case '良':
    case '中':
      return true;
    case '不及格':
    case '不合格':
    case 'FAIL':
    case 'F':
    default:
      return false;
  }
}

Grade? _matchGrade(
  StudyProgressCourse course,
  Map<String, List<Grade>> gradesByCode,
  Map<String, List<Grade>> gradesByName,
) {
  final codeKey = _normalizeCode(course.code);
  final nameKey = _normalizeName(course.name);
  final semester = course.semester.trim();

  List<Grade> candidates = codeKey.isNotEmpty
      ? (gradesByCode[codeKey] ?? const [])
      : (gradesByName[nameKey] ?? const []);
  if (candidates.isEmpty && nameKey.isNotEmpty) {
    candidates = gradesByName[nameKey] ?? const [];
  }
  if (candidates.isEmpty) return null;

  if (semester.isNotEmpty) {
    for (final grade in candidates) {
      if (grade.semester.trim() == semester) return grade;
    }
  }

  for (final grade in candidates) {
    if (_hasMeaningfulScore(grade.score)) return grade;
  }
  return candidates.first;
}

String _scoreLabel(
  StudyProgressCourse course,
  Grade? grade,
  StudyCourseStatus status,
) {
  final sourceScore = course.score.trim();
  if (_hasMeaningfulScore(sourceScore)) return sourceScore;
  if (grade != null && _hasMeaningfulScore(grade.score)) {
    return grade.score.trim();
  }

  switch (status) {
    case StudyCourseStatus.completed:
      return grade?.score.trim().isNotEmpty == true
          ? grade!.score.trim()
          : '--';
    case StudyCourseStatus.inProgress:
      return '待出';
    case StudyCourseStatus.pending:
      return '--';
  }
}

StudyCourseStatus? _statusFromSource(String source) {
  final value = source.trim();
  if (value.isEmpty) return null;
  if (value.contains('已')) return StudyCourseStatus.completed;
  if (value.contains('修读中')) return StudyCourseStatus.inProgress;
  if (value.contains('未')) return StudyCourseStatus.pending;
  return null;
}

bool _hasCompletedGrade(Grade? grade) =>
    grade != null && _hasMeaningfulScore(grade.score);

bool _hasMeaningfulScore(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty || normalized == '-' || normalized == '--') {
    return false;
  }
  final score = double.tryParse(normalized);
  if (score != null) return score > 0;
  return normalized != '0';
}

String _statusLabel(StudyCourseStatus status) {
  switch (status) {
    case StudyCourseStatus.completed:
      return '已修读';
    case StudyCourseStatus.inProgress:
      return '修读中';
    case StudyCourseStatus.pending:
      return '未修读';
  }
}

String _courseKey(String code, String name) {
  final normalizedCode = _normalizeCode(code);
  if (normalizedCode.isNotEmpty) return 'code:$normalizedCode';
  return 'name:${_normalizeName(name)}';
}

String _courseKeyFromExecutionPlan(ExecutionPlanCourse course) =>
    _courseKey(course.code, course.name);

String _normalizeCode(String value) => value.trim().toUpperCase();

String _normalizeName(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), '');

StudyCreditCategory _creditCategoryForSection(
  StudyProgressSectionView section,
) {
  final directCategory = section.creditCategory.trim();
  if (directCategory.isNotEmpty) {
    if (_containsAny(directCategory, _schoolElectiveKeywords)) {
      return StudyCreditCategory.schoolElective;
    }
    if (directCategory.contains('必修')) return StudyCreditCategory.compulsory;
    if (_containsAny(directCategory, const ['选修', '限选', '任选'])) {
      return StudyCreditCategory.elective;
    }
  }

  final text = [
    section.id,
    section.title,
    ...section.courses.map((course) => course.attribute),
  ].join(' ');

  if (_containsAny(text, _schoolElectiveKeywords)) {
    return StudyCreditCategory.schoolElective;
  }
  if (text.contains('必修')) return StudyCreditCategory.compulsory;
  if (text.contains('选修')) return StudyCreditCategory.elective;

  return StudyCreditCategory.elective;
}

bool _containsAny(String value, List<String> needles) =>
    needles.any((needle) => value.contains(needle));

double _parseCredit(String value) {
  final match = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(value.trim());
  if (match == null) return 0;
  return double.tryParse(match.group(0)!) ?? 0;
}

bool _isSummarySection(StudyProgressSectionView section) {
  final title = section.title.trim();
  final id = section.id.trim();
  return title.contains('小计') ||
      title.contains('合计') ||
      title.contains('总计') ||
      title.contains('汇总') ||
      id.contains('小计') ||
      id.contains('合计') ||
      id.contains('总计');
}

const _schoolElectiveKeywords = [
  '校选',
  '校级选修',
  '公共选修',
  '通识选修',
  '全校选修',
  '全校性选修',
  '公选',
  '跨专业',
];
