import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:campus_platform/services/notification_service.dart';
import 'package:campus_platform/services/schedule_widget_service.dart';
import 'package:core/models/course.dart';
import 'package:core/models/exam.dart';
import 'package:core/models/schedule_calendar_rules.dart';
import 'package:core/utils/exam_time_utils.dart';
import 'package:core/utils/schedule_time_utils.dart';
import 'package:data/data.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/runtime_mode.dart';
import '../../utils/semester_service.dart';
import '../auth/auth_providers.dart';
import '../shared/cached_resource.dart';

typedef ScheduleResult = ({List<Course> courses, String remark});

final scheduleProvider =
    NotifierProvider.family<
      ScheduleNotifier,
      CachedResource<ScheduleResult>,
      String?
    >(ScheduleNotifier.new);

class ScheduleNotifier extends CachedResourceNotifier<ScheduleResult, String?> {
  @override
  ScheduleResult get emptyData => (courses: const [], remark: '');

  @override
  String get cacheNamespace => 'schedule';

  @override
  String? cacheScopeForArg(String? arg) => arg;

  @override
  Object? encode(ScheduleResult data) => {
    'courses': data.courses.map((course) => course.toJson()).toList(),
    'remark': data.remark,
  };

  @override
  ScheduleResult decode(Object? json) {
    if (json is! Map) return emptyData;
    final coursesRaw = json['courses'];
    return (
      courses: coursesRaw is List
          ? coursesRaw
                .whereType<Map>()
                .map((item) => Course.fromJson(Map<String, dynamic>.from(item)))
                .toList()
          : const <Course>[],
      remark: json['remark']?.toString() ?? '',
    );
  }

  @override
  void listenDependencies(String? arg) {
    ref.listen<AsyncValue<List<Course>>>(customCoursesProvider(arg), (_, next) {
      unawaited(refresh());
    });
    ref.listen<AsyncValue<int>>(semesterTotalWeeksProvider(arg), (_, next) {
      unawaited(refresh());
    });
    ref.listen<AsyncValue<DateTime?>>(activeSemesterStartProvider, (_, next) {
      unawaited(refresh());
    });
  }

  @override
  Future<ScheduleResult> fetch(
    ({String username, String password}) credentials, {
    required bool forceRefresh,
  }) async {
    ensureCredentialPassword(credentials);

    final gateway = ref.read(campusGatewayProvider);
    final selectedSemester = await ref.read(
      selectedScheduleSemesterProvider.future,
    );
    final semesterKey = resourceArg ?? selectedSemester;
    final customCourses = await ref.read(
      customCoursesProvider(semesterKey).future,
    );
    final totalWeeks = await ref.read(
      semesterTotalWeeksProvider(semesterKey).future,
    );
    final scheduleResult = await gateway.getSchedule(
      credentials.username,
      credentials.password,
      semester: resourceArg,
      forceRefresh: forceRefresh,
    );

    final semesterStart = await _resolveSemesterStart(ref, semesterKey);
    final examCourses = semesterStart == null
        ? <Course>[]
        : await _loadExamCourses(
            gateway: gateway,
            username: credentials.username,
            password: credentials.password,
            semester: resourceArg,
            semesterStart: semesterStart,
            totalWeeks: totalWeeks,
          );

    return (
      courses: [...scheduleResult.courses, ...customCourses, ...examCourses],
      remark: scheduleResult.remark,
    );
  }

  @override
  Future<void> onData(ScheduleResult data, {required bool changed}) async {
    if (!changed) return;
    final selectedSemester = ref
        .read(selectedScheduleSemesterProvider)
        .valueOrNull;
    final semesterStart = ref.read(activeSemesterStartProvider).valueOrNull;
    if (semesterStart == null) return;
    final totalWeeks =
        ref.read(semesterTotalWeeksProvider(selectedSemester)).valueOrNull ??
        defaultSemesterTotalWeeks;
    final calendarRules = await ref.read(scheduleCalendarRulesProvider.future);

    await NotificationService.scheduleClassReminders(
      data.courses,
      semesterStart,
      totalWeeks: totalWeeks,
      calendarRules: calendarRules,
      accountId: ref.read(credentialsProvider)?.username,
    );
    await ScheduleWidgetService.updateScheduleWidgets(
      courses: data.courses,
      semesterStart: semesterStart,
      selectedSemester: selectedSemester,
      remark: data.remark,
      totalWeeks: totalWeeks,
      calendarRules: calendarRules,
    );
  }
}

Future<DateTime?> _resolveSemesterStart(Ref ref, String? semesterKey) async {
  if (semesterKey != null && semesterKey.isNotEmpty) {
    return ref.watch(semesterStartForKeyProvider(semesterKey).future);
  }
  return ref.watch(semesterStartProvider.future);
}

Future<List<Course>> _loadExamCourses({
  required CampusGateway gateway,
  required String username,
  required String password,
  required String? semester,
  required DateTime semesterStart,
  required int totalWeeks,
}) async {
  try {
    final exams = await gateway.getExams(
      username,
      password,
      semester: semester,
    );
    return examsToCourses(
      exams: exams,
      semesterStart: semesterStart,
      totalWeeks: totalWeeks,
    );
  } catch (error) {
    debugPrint('[Schedule] 考试安排同步到课表失败: $error');
    return const [];
  }
}

/// 将考试列表转换为课表课程。
List<Course> examsToCourses({
  required List<Exam> exams,
  required DateTime semesterStart,
  required int totalWeeks,
}) {
  return exams
      .map((exam) {
        final parsed = parseExamTime(exam.examTime);
        if (parsed == null) return null;

        final week = weekOfDate(semesterStart, parsed.start);
        if (week < 1 || week > totalWeeks) return null;

        final name = exam.courseName.trim().isEmpty
            ? '考试'
            : '考试：${exam.courseName.trim()}';
        final seat = exam.seatNumber.trim() == '-'
            ? ''
            : exam.seatNumber.trim();

        // 计算精确分钟数（从午夜 00:00 开始），用于课表精确布局
        final startMinutes = parsed.start.hour * 60 + parsed.start.minute;
        final endMinutes = parsed.end.hour * 60 + parsed.end.minute;

        return Course(
          name: name,
          teacher: '',
          timeStr: exam.examTime.trim(),
          classroom: exam.examRoom.trim(),
          dayOfWeek: parsed.start.weekday,
          timeSlot: _startSlotForExactTime(parsed.start),
          endTimeSlot: endSlotFor(parsed.end),
          weekList: [week],
          isExam: true,
          seatNumber: seat,
          exactStartMinutes: startMinutes,
          exactEndMinutes: endMinutes,
        );
      })
      .whereType<Course>()
      .toList();
}

int _startSlotForExactTime(DateTime value) {
  final minutes = value.hour * 60 + value.minute;
  for (final entry in slotMinuteRanges.entries) {
    if (minutes <= entry.value.end) return entry.key;
  }
  return slotMinuteRanges.keys.last;
}

// ── Semester / Week / Course Settings ─────────────────────────

class SemesterStartNotifier extends AsyncNotifier<DateTime?> {
  @override
  Future<DateTime?> build() async {
    final accountId = getAccountId(ref, listen: true);
    final service = ref.read(semesterServiceProvider);
    if (service.cacheReadyFor(accountId)) {
      return service.loadSync(accountId: accountId);
    }
    return service.load(accountId: accountId);
  }

  Future<void> set(DateTime date) async {
    final accountId = getAccountId(ref, listen: false);
    await ref.read(semesterServiceProvider).save(date, accountId: accountId);
    state = AsyncData(date);
  }
}

final semesterStartProvider =
    AsyncNotifierProvider<SemesterStartNotifier, DateTime?>(
      SemesterStartNotifier.new,
    );

class SemesterStartForKeyNotifier
    extends FamilyAsyncNotifier<DateTime?, String> {
  @override
  Future<DateTime?> build(String arg) async {
    final accountId = getAccountId(ref, listen: true);
    final service = ref.read(semesterServiceProvider);
    if (service.cacheReadyFor(accountId)) {
      return service.loadForKeySync(arg, accountId: accountId);
    }
    return service.loadForKey(arg, accountId: accountId);
  }

  Future<void> set(DateTime date) async {
    final accountId = getAccountId(ref, listen: false);
    await ref
        .read(semesterServiceProvider)
        .saveForKey(arg, date, accountId: accountId);
    state = AsyncData(date);
  }
}

final semesterStartForKeyProvider =
    AsyncNotifierProvider.family<
      SemesterStartForKeyNotifier,
      DateTime?,
      String
    >(SemesterStartForKeyNotifier.new);

class SelectedSemesterNotifier extends AsyncNotifier<String?> {
  @override
  Future<String?> build() async {
    final accountId = getAccountId(ref, listen: true);
    final service = ref.read(semesterServiceProvider);
    if (service.cacheReadyFor(accountId)) {
      return service.loadSelectedSemesterSync(accountId: accountId);
    }
    return service.loadSelectedSemester(accountId: accountId);
  }

  Future<void> set(String? value) async {
    final accountId = getAccountId(ref, listen: false);
    await ref
        .read(semesterServiceProvider)
        .saveSelectedSemester(value, accountId: accountId);
    state = AsyncData(value);
  }
}

final selectedScheduleSemesterProvider =
    AsyncNotifierProvider<SelectedSemesterNotifier, String?>(
      SelectedSemesterNotifier.new,
    );

final activeSemesterStartProvider = Provider<AsyncValue<DateTime?>>((ref) {
  final selectedAsync = ref.watch(selectedScheduleSemesterProvider);
  if (selectedAsync.isLoading) return const AsyncValue.loading();
  if (selectedAsync.hasError) {
    return AsyncValue.error(selectedAsync.error!, selectedAsync.stackTrace!);
  }

  final selected = selectedAsync.valueOrNull;
  if (selected == null) return ref.watch(semesterStartProvider);
  return ref.watch(semesterStartForKeyProvider(selected));
});

const int defaultSemesterTotalWeeks = 20;
const int minSemesterTotalWeeks = 12;
const int maxSemesterTotalWeeks = 30;

const _semesterTotalWeeksPrefix = 'schedule_total_weeks_';
const _customCoursesPrefix = 'schedule_custom_courses_';

/// 计算 DateTime 对应的学期字符串（如 2026-2027-1）。
String calculateSemester(DateTime date) {
  final year = date.year;
  final month = date.month;
  if (month >= 8) {
    return '$year-${year + 1}-1';
  } else if (month == 1) {
    return '${year - 1}-$year-1';
  } else {
    return '${year - 1}-$year-2';
  }
}

/// 动态解析学期 Key。
/// 当 [semester] 为 null 或空串时，优先使用选中的学期字符串；
/// 若未选择，则使用当前激活学期的 start date 计算学期字符串；
/// 仍未设置 start date 时后备回退到当前时间的学期字符串。
Future<String> resolveSemesterKey(
  Ref ref,
  String? semester, {
  bool listen = true,
}) async {
  final safeSemester = semester?.trim();
  if (safeSemester != null && safeSemester.isNotEmpty) {
    return safeSemester;
  }
  if (listen) {
    final selectedAsync = await ref.watch(
      selectedScheduleSemesterProvider.future,
    );
    final selected = selectedAsync?.trim();
    if (selected != null && selected.isNotEmpty) {
      return selected;
    }
    final startDate = await ref.watch(semesterStartProvider.future);
    if (startDate != null) {
      return calculateSemester(startDate);
    }
  } else {
    final selectedAsync = ref.read(selectedScheduleSemesterProvider);
    final selectedValue =
        selectedAsync.valueOrNull ??
        (selectedAsync.isLoading
            ? await ref.read(selectedScheduleSemesterProvider.future)
            : null);
    final selected = selectedValue?.trim();
    if (selected != null && selected.isNotEmpty) {
      return selected;
    }
    final startDateAsync = ref.read(semesterStartProvider);
    final startDate =
        startDateAsync.valueOrNull ??
        (startDateAsync.isLoading
            ? await ref.read(semesterStartProvider.future)
            : null);
    if (startDate != null) {
      return calculateSemester(startDate);
    }
  }

  final accountId = getAccountId(ref, listen: listen);
  final service = ref.read(semesterServiceProvider);
  if (service.cacheReadyFor(accountId)) {
    final selectedSync = service
        .loadSelectedSemesterSync(accountId: accountId)
        ?.trim();
    if (selectedSync != null && selectedSync.isNotEmpty) {
      return selectedSync;
    }
    final defaultStart = service.loadSync(accountId: accountId);
    if (defaultStart != null) {
      return calculateSemester(defaultStart);
    }
  } else {
    final selectedAsync = await service.loadSelectedSemester(
      accountId: accountId,
    );
    final selected = selectedAsync?.trim();
    if (selected != null && selected.isNotEmpty) {
      return selected;
    }
    final defaultStart = await service.load(accountId: accountId);
    if (defaultStart != null) {
      return calculateSemester(defaultStart);
    }
  }

  return calculateSemester(DateTime.now());
}

/// Helper function to generate account-scoped SharedPreferences keys.
/// Format: `user_${accountId}_$key`. If [accountId] is empty or whitespace, defaults to `'guest'`.
String userScopedKey(String accountId, String key) {
  final safeAccount = accountId.trim().isNotEmpty
      ? accountId.trim()
      : 'default';
  return 'user_${safeAccount}_$key';
}

String _userScopedKey(Ref ref, String key, {bool listen = true}) {
  final accountId = getAccountId(ref, listen: listen);
  return userScopedKey(accountId, key);
}

int _normalizeTotalWeeks(int value) {
  return value.clamp(minSemesterTotalWeeks, maxSemesterTotalWeeks).toInt();
}

class SemesterTotalWeeksNotifier extends FamilyAsyncNotifier<int, String?> {
  @override
  Future<int> build(String? arg) async {
    final semesterKey = await resolveSemesterKey(ref, arg, listen: true);
    final scopedKey = _userScopedKey(
      ref,
      '$_semesterTotalWeeksPrefix$semesterKey',
      listen: true,
    );
    final legacyKey = '$_semesterTotalWeeksPrefix$semesterKey';
    final prefs = await SharedPreferences.getInstance();
    final stored = await _readScopedIntWithMigration(
      prefs,
      scopedKey: scopedKey,
      legacyKey: legacyKey,
      fallback: defaultSemesterTotalWeeks,
    );
    return _normalizeTotalWeeks(stored);
  }

  Future<void> setWeeks(int value) async {
    final safeValue = _normalizeTotalWeeks(value);
    final semesterKey = await resolveSemesterKey(ref, arg, listen: false);
    final scopedKey = _userScopedKey(
      ref,
      '$_semesterTotalWeeksPrefix$semesterKey',
      listen: false,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(scopedKey, safeValue);
    state = AsyncValue.data(safeValue);
  }
}

final semesterTotalWeeksProvider =
    AsyncNotifierProvider.family<SemesterTotalWeeksNotifier, int, String?>(
      SemesterTotalWeeksNotifier.new,
    );

class CustomCoursesNotifier extends FamilyAsyncNotifier<List<Course>, String?> {
  @override
  Future<List<Course>> build(String? arg) async {
    final semesterKey = await resolveSemesterKey(ref, arg, listen: true);
    final scopedKey = _userScopedKey(
      ref,
      '$_customCoursesPrefix$semesterKey',
      listen: true,
    );
    final legacyKey = '$_customCoursesPrefix$semesterKey';
    final prefs = await SharedPreferences.getInstance();

    final raw = await _readScopedStringWithMigration(
      prefs,
      scopedKey: scopedKey,
      legacyKey: legacyKey,
    );
    if (raw == null || raw.isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => Course.fromJson(Map<String, dynamic>.from(item)))
          .map((course) => course.copyWith(isCustom: true))
          .toList();
    } catch (error) {
      debugPrint('[Schedule] 自定义课程读取失败: $error');
      return const [];
    }
  }

  Future<void> addCourse(Course course) async {
    final current = await future;
    final next = [...current, course.copyWith(isCustom: true, isExam: false)];
    await _save(next);
  }

  Future<void> removeCourse(Course course) async {
    final current = await future;
    var removed = false;
    final next = <Course>[];
    for (final item in current) {
      if (!removed &&
          _courseStorageIdentity(item) == _courseStorageIdentity(course)) {
        removed = true;
        continue;
      }
      next.add(item);
    }
    await _save(next);
  }

  Future<void> clearCourses() => _save(const []);

  Future<void> _save(List<Course> courses) async {
    final semesterKey = await resolveSemesterKey(ref, arg, listen: false);
    final scopedKey = _userScopedKey(
      ref,
      '$_customCoursesPrefix$semesterKey',
      listen: false,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      scopedKey,
      jsonEncode(courses.map((course) => course.toJson()).toList()),
    );
    state = AsyncValue.data(courses);
  }

  String _courseStorageIdentity(Course course) {
    return jsonEncode(course.copyWith(isCustom: true, isExam: false).toJson());
  }
}

final customCoursesProvider =
    AsyncNotifierProvider.family<CustomCoursesNotifier, List<Course>, String?>(
      CustomCoursesNotifier.new,
    );

class SelectedWeekNotifier extends Notifier<int> {
  @override
  int build() => 1;

  void setWeek(int week) => state = week;
}

final selectedWeekProvider = NotifierProvider<SelectedWeekNotifier, int>(
  SelectedWeekNotifier.new,
);

const _scheduleSundayFirstKey = 'schedule_sunday_first';
const _scheduleShowInactiveCoursesKey = 'schedule_show_inactive_courses';
const _scheduleDensityKey = 'schedule_density';
const _scheduleBackgroundKey = 'schedule_background';
const _scheduleCalendarRulesKey = 'schedule_calendar_rules';

enum ScheduleDensity { compact, standard, spacious }

Future<bool> _readScopedBoolWithMigration(
  SharedPreferences prefs, {
  required String scopedKey,
  required String legacyKey,
  required bool fallback,
}) async {
  if (prefs.containsKey(scopedKey)) {
    return prefs.getBool(scopedKey) ?? fallback;
  }
  if (!prefs.containsKey(legacyKey)) return fallback;

  final value = prefs.getBool(legacyKey) ?? fallback;
  await prefs.setBool(scopedKey, value);
  await prefs.remove(legacyKey);
  return value;
}

Future<int> _readScopedIntWithMigration(
  SharedPreferences prefs, {
  required String scopedKey,
  required String legacyKey,
  required int fallback,
}) async {
  if (prefs.containsKey(scopedKey)) {
    return prefs.getInt(scopedKey) ?? fallback;
  }
  if (!prefs.containsKey(legacyKey)) return fallback;

  final value = prefs.getInt(legacyKey) ?? fallback;
  await prefs.setInt(scopedKey, value);
  await prefs.remove(legacyKey);
  return value;
}

Future<String?> _readScopedStringWithMigration(
  SharedPreferences prefs, {
  required String scopedKey,
  required String legacyKey,
}) async {
  final scoped = prefs.getString(scopedKey);
  if (scoped != null) return scoped;
  final legacy = prefs.getString(legacyKey);
  if (legacy == null) return null;

  await prefs.setString(scopedKey, legacy);
  await prefs.remove(legacyKey);
  return legacy;
}

class ScheduleSundayFirstNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final key = _userScopedKey(ref, _scheduleSundayFirstKey, listen: true);
    final prefs = await SharedPreferences.getInstance();
    return _readScopedBoolWithMigration(
      prefs,
      scopedKey: key,
      legacyKey: _scheduleSundayFirstKey,
      fallback: false,
    );
  }

  Future<void> setSundayFirst(bool value) async {
    final key = _userScopedKey(ref, _scheduleSundayFirstKey, listen: false);
    state = AsyncValue.data(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }
}

final scheduleSundayFirstProvider =
    AsyncNotifierProvider<ScheduleSundayFirstNotifier, bool>(
      ScheduleSundayFirstNotifier.new,
    );

class ScheduleShowInactiveCoursesNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final key = _userScopedKey(
      ref,
      _scheduleShowInactiveCoursesKey,
      listen: true,
    );
    final prefs = await SharedPreferences.getInstance();
    return _readScopedBoolWithMigration(
      prefs,
      scopedKey: key,
      legacyKey: _scheduleShowInactiveCoursesKey,
      fallback: true,
    );
  }

  Future<void> setShowInactiveCourses(bool value) async {
    final key = _userScopedKey(
      ref,
      _scheduleShowInactiveCoursesKey,
      listen: false,
    );
    state = AsyncValue.data(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }
}

final scheduleShowInactiveCoursesProvider =
    AsyncNotifierProvider<ScheduleShowInactiveCoursesNotifier, bool>(
      ScheduleShowInactiveCoursesNotifier.new,
    );

class ScheduleDensityNotifier extends AsyncNotifier<ScheduleDensity> {
  @override
  Future<ScheduleDensity> build() async {
    final key = _userScopedKey(ref, _scheduleDensityKey, listen: true);
    final prefs = await SharedPreferences.getInstance();
    final stored = await _readScopedStringWithMigration(
      prefs,
      scopedKey: key,
      legacyKey: _scheduleDensityKey,
    );
    return ScheduleDensity.values.firstWhere(
      (value) => value.name == stored,
      orElse: () => ScheduleDensity.standard,
    );
  }

  Future<void> setDensity(ScheduleDensity value) async {
    state = AsyncValue.data(value);
    final key = _userScopedKey(ref, _scheduleDensityKey, listen: false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value.name);
  }
}

final scheduleDensityProvider =
    AsyncNotifierProvider<ScheduleDensityNotifier, ScheduleDensity>(
      ScheduleDensityNotifier.new,
    );

class ScheduleBackgroundImageNotifier extends AsyncNotifier<String?> {
  @override
  Future<String?> build() async {
    final key = _userScopedKey(ref, _scheduleBackgroundKey, listen: true);
    final prefs = await SharedPreferences.getInstance();
    final stored = await _readScopedStringWithMigration(
      prefs,
      scopedKey: key,
      legacyKey: _scheduleBackgroundKey,
    );
    if (stored == null || stored.trim().isEmpty) return null;
    if (await File(stored).exists()) return stored;
    await prefs.remove(key);
    return null;
  }

  Future<void> setImage(String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw StateError('未找到选择的背景图片');
    }

    final directory = Directory(
      '${(await getApplicationDocumentsDirectory()).path}${Platform.pathSeparator}schedule_backgrounds',
    );
    await directory.create(recursive: true);
    final extensionMatch = RegExp(
      r'\.(jpg|jpeg|png|webp)$',
      caseSensitive: false,
    ).firstMatch(sourcePath);
    final extension = extensionMatch?.group(1)?.toLowerCase() ?? 'jpg';
    final destination = File(
      '${directory.path}${Platform.pathSeparator}schedule_${DateTime.now().microsecondsSinceEpoch}.$extension',
    );
    await source.copy(destination.path);

    final key = _userScopedKey(ref, _scheduleBackgroundKey, listen: false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, destination.path);
    state = AsyncValue.data(destination.path);
  }

  Future<void> clearImage() async {
    final key = _userScopedKey(ref, _scheduleBackgroundKey, listen: false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
    state = const AsyncValue.data(null);
  }
}

final scheduleBackgroundImageProvider =
    AsyncNotifierProvider<ScheduleBackgroundImageNotifier, String?>(
      ScheduleBackgroundImageNotifier.new,
    );

class ScheduleCalendarRulesNotifier
    extends AsyncNotifier<ScheduleCalendarRules> {
  @override
  Future<ScheduleCalendarRules> build() async {
    final key = _userScopedKey(ref, _scheduleCalendarRulesKey, listen: true);
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return ScheduleCalendarRules.empty;

    try {
      return ScheduleCalendarRules.fromJson(jsonDecode(raw));
    } catch (error) {
      debugPrint('[Schedule] 课表日期规则读取失败: $error');
      return ScheduleCalendarRules.empty;
    }
  }

  Future<void> setSkipOfficialHolidays(bool value) {
    final current = state.valueOrNull ?? ScheduleCalendarRules.empty;
    return _save(current.copyWith(skipOfficialHolidays: value));
  }

  Future<void> addNoClassDate(DateTime date) {
    final current = state.valueOrNull ?? ScheduleCalendarRules.empty;
    final dates = {
      ...current.additionalNoClassDates,
      scheduleDateKey(date),
    }.toList()..sort();
    return _save(current.copyWith(additionalNoClassDates: dates));
  }

  Future<void> removeNoClassDate(String dateKey) {
    final current = state.valueOrNull ?? ScheduleCalendarRules.empty;
    return _save(
      current.copyWith(
        additionalNoClassDates: current.additionalNoClassDates
            .where((date) => date != dateKey)
            .toList(),
      ),
    );
  }

  Future<void> saveAdjustment(ScheduleDateAdjustment adjustment) {
    final current = state.valueOrNull ?? ScheduleCalendarRules.empty;
    final adjustments = [
      ...current.adjustments.where(
        (item) => item.sourceKey != adjustment.sourceKey,
      ),
      adjustment,
    ]..sort((a, b) => a.sourceKey.compareTo(b.sourceKey));
    return _save(current.copyWith(adjustments: adjustments));
  }

  Future<void> removeAdjustment(String sourceDateKey) {
    final current = state.valueOrNull ?? ScheduleCalendarRules.empty;
    return _save(
      current.copyWith(
        adjustments: current.adjustments
            .where((adjustment) => adjustment.sourceKey != sourceDateKey)
            .toList(),
      ),
    );
  }

  Future<void> _save(ScheduleCalendarRules rules) async {
    final key = _userScopedKey(ref, _scheduleCalendarRulesKey, listen: false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(rules.toJson()));
    state = AsyncData(rules);
    await _rescheduleClassReminders(rules);
  }

  Future<void> _rescheduleClassReminders(ScheduleCalendarRules rules) async {
    final credentials = ref.read(credentialsProvider);
    final semesterStart = ref.read(activeSemesterStartProvider).valueOrNull;
    if (credentials == null || semesterStart == null) return;

    final selectedSemester = ref
        .read(selectedScheduleSemesterProvider)
        .valueOrNull;
    final schedule = ref.read(scheduleProvider(selectedSemester)).valueOrNull;
    if (schedule == null) return;

    final totalWeeks =
        ref.read(semesterTotalWeeksProvider(selectedSemester)).valueOrNull ??
        defaultSemesterTotalWeeks;
    await NotificationService.scheduleClassReminders(
      schedule.courses,
      semesterStart,
      totalWeeks: totalWeeks,
      calendarRules: rules,
      accountId: credentials.username,
    );
    await ScheduleWidgetService.updateScheduleWidgets(
      courses: schedule.courses,
      semesterStart: semesterStart,
      selectedSemester: selectedSemester,
      remark: schedule.remark,
      totalWeeks: totalWeeks,
      calendarRules: rules,
    );
  }
}

final scheduleCalendarRulesProvider =
    AsyncNotifierProvider<ScheduleCalendarRulesNotifier, ScheduleCalendarRules>(
      ScheduleCalendarRulesNotifier.new,
    );
