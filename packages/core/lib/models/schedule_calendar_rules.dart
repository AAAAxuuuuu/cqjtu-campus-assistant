import 'course.dart';
import 'schedule_preset.dart';

export 'schedule_preset.dart';

/// Moves every course that would occur on [sourceDate] to [targetDate].
class ScheduleDateAdjustment {
  const ScheduleDateAdjustment({
    required this.sourceDate,
    required this.targetDate,
  });

  final DateTime sourceDate;
  final DateTime targetDate;

  String get sourceKey => scheduleDateKey(sourceDate);
  String get targetKey => scheduleDateKey(targetDate);

  Map<String, String> toJson() => {
        'sourceDate': sourceKey,
        'targetDate': targetKey,
      };

  static ScheduleDateAdjustment? fromJson(Object? value) {
    if (value is! Map) return null;
    final source = DateTime.tryParse(value['sourceDate']?.toString() ?? '');
    final target = DateTime.tryParse(value['targetDate']?.toString() ?? '');
    if (source == null || target == null) return null;
    if (scheduleDateKey(source) == scheduleDateKey(target)) return null;
    return ScheduleDateAdjustment(sourceDate: source, targetDate: target);
  }
}

/// A course occurrence after holiday exclusions and user-defined adjustments.
///
/// [displayStatus] 描述这条 occurrence 在课表上该怎么画：
/// * [CourseDisplayStatus.active] — 当天实际上课（含调休补上来的课）
/// * [CourseDisplayStatus.holidayCancelled] — 当天原排课，但被假期挡掉
/// * [CourseDisplayStatus.movedOut] — 当天原排课，但被调休挪走
///
/// 课表渲染会把非 active 的格子画成灰色占位；提醒、小组件、ICS 导出只消费
/// [isScheduled] 为 true 的条目，所以假期/调休源日期不会变成真正的上课。
class ScheduleCourseOccurrence {
  const ScheduleCourseOccurrence({
    required this.course,
    required this.originalDate,
    required this.scheduledDate,
    this.displayStatus = CourseDisplayStatus.active,
  });

  final Course course;
  final DateTime originalDate;
  final DateTime scheduledDate;
  final CourseDisplayStatus displayStatus;

  bool get isAdjusted =>
      scheduleDateKey(originalDate) != scheduleDateKey(scheduledDate);

  /// 当天真正有课，需要点亮、发提醒、进小组件。
  bool get isScheduled => displayStatus == CourseDisplayStatus.active;

  Course asCourseForWeek(int week) => course.copyWith(
        dayOfWeek: scheduledDate.weekday,
        weekList: [week],
        displayStatus: displayStatus,
      );

  /// 课表格子用：保留原始 weekList（详情弹窗的「共 N 周」），只改 weekday 和状态。
  Course asDisplayCourse() => course.copyWith(
        dayOfWeek: scheduledDate.weekday,
        displayStatus: displayStatus,
      );
}

/// Date rules shared by timetable display, reminders and exported calendars.
class ScheduleCalendarRules {
  const ScheduleCalendarRules({
    this.skipOfficialHolidays = true,
    this.additionalNoClassDates = const [],
    this.adjustments = const [],
    this.enabledPresets = const [],
  });

  final bool skipOfficialHolidays;
  final List<String> additionalNoClassDates;
  final List<ScheduleDateAdjustment> adjustments;

  /// 已启用的内置预设（如学校国庆调休）。
  ///
  /// 预设与手动规则分开存放，关闭开关即可完整还原手动设置；持久化时只写 id，
  /// 过期预设在读取时被丢弃，因此学期结束后规则自动销毁。
  final List<SchedulePreset> enabledPresets;

  static const empty = ScheduleCalendarRules();

  bool isPresetEnabled(String presetId) =>
      enabledPresets.any((preset) => preset.id == presetId);

  /// 预设与手动设置合并后的停课日期。
  Set<String> get effectiveNoClassDates => {
        ...additionalNoClassDates,
        for (final preset in enabledPresets) ...preset.allNoClassDates,
      };

  /// 预设与手动设置合并后的调休安排，手动设置优先。
  Map<String, ScheduleDateAdjustment> get effectiveAdjustments {
    final merged = <String, ScheduleDateAdjustment>{};
    for (final preset in enabledPresets) {
      for (final adjustment in preset.adjustments) {
        merged[adjustment.sourceKey] = adjustment;
      }
    }
    // 手动调休后写入，覆盖预设中的同一天。
    for (final adjustment in adjustments) {
      merged[adjustment.sourceKey] = adjustment;
    }
    return merged;
  }

  static const _officialHolidayDates = <String>{
    '2026-01-01',
    '2026-01-02',
    '2026-01-03',
    '2026-02-15',
    '2026-02-16',
    '2026-02-17',
    '2026-02-18',
    '2026-02-19',
    '2026-02-20',
    '2026-02-21',
    '2026-02-22',
    '2026-02-23',
    '2026-04-04',
    '2026-04-05',
    '2026-04-06',
    '2026-05-01',
    '2026-05-02',
    '2026-05-03',
    '2026-05-04',
    '2026-05-05',
    '2026-06-19',
    '2026-06-20',
    '2026-06-21',
    '2026-09-25',
    '2026-09-26',
    '2026-09-27',
    '2026-10-01',
    '2026-10-02',
    '2026-10-03',
    '2026-10-04',
    '2026-10-05',
    '2026-10-06',
    '2026-10-07',
  };

  bool get hasAdditionalNoClassDates => additionalNoClassDates.isNotEmpty;
  bool get hasAdjustments => adjustments.isNotEmpty;

  /// 该日期是否为调休补课日（有课被挪到这天上）。
  ///
  /// 补课日优先级高于法定节假日：像 9/26、9/27 本属中秋法定假期，但学校通知
  /// 要求上班补课，此时补课照常进行。
  bool isMakeupWorkday(DateTime date) {
    final key = scheduleDateKey(date);
    return effectiveAdjustments.values.any(
      (adjustment) => adjustment.targetKey == key,
    );
  }

  /// 该日期**原本排的课**是否停掉。
  ///
  /// 注意这与「当天有没有课」不是一个问题：补课日（如 9/20）两者同时成立——
  /// 原本排在周日的课停掉，同时上调休挪来的周二课程。判断某天实际是否有课
  /// 请用 [resolveOccurrences]。
  ///
  /// 调休优先于节假日：若该日期是某条调休的来源，则由调休接管（课程被挪走
  /// 而非停课），[resolveOccurrences] 会先走调休分支。
  bool isNoClassDate(DateTime date) {
    final key = scheduleDateKey(date);
    return effectiveNoClassDates.contains(key) ||
        (skipOfficialHolidays && _officialHolidayDates.contains(key));
  }

  /// 该日期的课是否被调休挪走。用于把调休和停课区分开。
  bool isAdjustedAway(DateTime date) =>
      effectiveAdjustments.containsKey(scheduleDateKey(date));

  /// 展开课程为具体日期。
  ///
  /// [includeCancelled] 为 true 时，被假期挡掉或被调休挪走的原日期也会作为
  /// 非 active 的 occurrence 返回，供课表画灰色占位；默认 false，保证提醒、
  /// 小组件、日历导出只拿到真正要上的课。
  List<ScheduleCourseOccurrence> resolveOccurrences({
    required List<Course> courses,
    required DateTime semesterStart,
    required int totalWeeks,
    bool includeCancelled = false,
  }) {
    final semesterMonday = _semesterMonday(semesterStart);
    final adjustmentsBySource = effectiveAdjustments;
    final occurrences = <ScheduleCourseOccurrence>[];

    for (final course in courses) {
      final weeks = course.weekList.toSet().toList()..sort();
      for (final week in weeks) {
        if (week < 1 || week > totalWeeks) continue;

        final originalDate = semesterMonday.add(
          Duration(days: (week - 1) * 7 + course.dayOfWeek - 1),
        );
        final adjustment = adjustmentsBySource[scheduleDateKey(originalDate)];

        // 调休优先于节假日：先判调休，原日期即便同时在停课名单里也算“挪走”
        // 而不是“停课”，且目标日期无条件落地（不会被节假日名单挡回去）。
        if (adjustment != null) {
          if (includeCancelled) {
            occurrences.add(
              ScheduleCourseOccurrence(
                course: course,
                originalDate: originalDate,
                scheduledDate: originalDate,
                displayStatus: CourseDisplayStatus.movedOut,
              ),
            );
          }
          occurrences.add(
            ScheduleCourseOccurrence(
              course: course,
              originalDate: originalDate,
              scheduledDate: adjustment.targetDate,
            ),
          );
          continue;
        }

        // 假期停课：本周排了课但当天放假，保留占位而不是整格消失。
        if (isNoClassDate(originalDate)) {
          if (includeCancelled) {
            occurrences.add(
              ScheduleCourseOccurrence(
                course: course,
                originalDate: originalDate,
                scheduledDate: originalDate,
                displayStatus: CourseDisplayStatus.holidayCancelled,
              ),
            );
          }
          continue;
        }

        occurrences.add(
          ScheduleCourseOccurrence(
            course: course,
            originalDate: originalDate,
            scheduledDate: originalDate,
          ),
        );
      }
    }

    occurrences.sort((a, b) {
      final date = a.scheduledDate.compareTo(b.scheduledDate);
      if (date != 0) return date;
      final slot = a.course.timeSlot.compareTo(b.course.timeSlot);
      if (slot != 0) return slot;
      // 同格先画占位再画点亮的课，保证 active 覆盖在上层。
      return (a.isScheduled ? 1 : 0).compareTo(b.isScheduled ? 1 : 0);
    });
    return occurrences;
  }

  int weekOf(
    DateTime date,
    DateTime semesterStart, {
    bool sundayFirst = false,
  }) {
    final start = _semesterWeekStart(semesterStart, sundayFirst: sundayFirst);
    final days = _dateOnly(date).difference(start).inDays;
    return (days / 7).floor() + 1;
  }

  ScheduleCalendarRules copyWith({
    bool? skipOfficialHolidays,
    List<String>? additionalNoClassDates,
    List<ScheduleDateAdjustment>? adjustments,
    List<SchedulePreset>? enabledPresets,
  }) =>
      ScheduleCalendarRules(
        skipOfficialHolidays: skipOfficialHolidays ?? this.skipOfficialHolidays,
        additionalNoClassDates:
            additionalNoClassDates ?? this.additionalNoClassDates,
        adjustments: adjustments ?? this.adjustments,
        enabledPresets: enabledPresets ?? this.enabledPresets,
      );

  Map<String, Object> toJson() => {
        'skipOfficialHolidays': skipOfficialHolidays,
        'additionalNoClassDates': additionalNoClassDates,
        'adjustments':
            adjustments.map((adjustment) => adjustment.toJson()).toList(),
        // 只存 id：日期定义始终来自代码，过期后读取时自动丢弃。
        'enabledPresets': enabledPresets.map((preset) => preset.id).toList(),
      };

  /// [now] 用于剔除已过期的预设，默认取当前时间。
  static ScheduleCalendarRules fromJson(Object? value, {DateTime? now}) {
    if (value is! Map) return empty;
    final noClassDates = (value['additionalNoClassDates'] as List? ?? const [])
        .map((date) => date.toString())
        .where((date) => DateTime.tryParse(date) != null)
        .toSet()
        .toList()
      ..sort();
    final adjustments = (value['adjustments'] as List? ?? const [])
        .map(ScheduleDateAdjustment.fromJson)
        .whereType<ScheduleDateAdjustment>()
        .fold(<String, ScheduleDateAdjustment>{}, (result, adjustment) {
          result[adjustment.sourceKey] = adjustment;
          return result;
        })
        .values
        .toList()
      ..sort((a, b) => a.sourceKey.compareTo(b.sourceKey));

    final presetIds = (value['enabledPresets'] as List? ?? const [])
        .map((id) => id.toString())
        .where((id) => id.isNotEmpty);

    return ScheduleCalendarRules(
      skipOfficialHolidays: value['skipOfficialHolidays'] != false,
      additionalNoClassDates: noClassDates,
      adjustments: adjustments,
      enabledPresets: SchedulePresetCatalog.resolve(
        presetIds,
        now: now ?? DateTime.now(),
      ),
    );
  }
}

String scheduleDateKey(DateTime date) {
  final day = _dateOnly(date);
  return '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

DateTime _semesterWeekStart(DateTime semesterStart,
    {bool sundayFirst = false}) {
  final start = _dateOnly(semesterStart);
  final offset =
      sundayFirst ? start.weekday % 7 : start.weekday - DateTime.monday;
  return start.subtract(Duration(days: offset));
}

DateTime _semesterMonday(DateTime semesterStart) {
  final start = _dateOnly(semesterStart);
  return start.subtract(Duration(days: start.weekday - DateTime.monday));
}
