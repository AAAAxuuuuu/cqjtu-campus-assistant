import 'course.dart';

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
class ScheduleCourseOccurrence {
  const ScheduleCourseOccurrence({
    required this.course,
    required this.originalDate,
    required this.scheduledDate,
  });

  final Course course;
  final DateTime originalDate;
  final DateTime scheduledDate;

  bool get isAdjusted =>
      scheduleDateKey(originalDate) != scheduleDateKey(scheduledDate);

  Course asCourseForWeek(int week) =>
      course.copyWith(dayOfWeek: scheduledDate.weekday, weekList: [week]);
}

/// Date rules shared by timetable display, reminders and exported calendars.
class ScheduleCalendarRules {
  const ScheduleCalendarRules({
    this.skipOfficialHolidays = true,
    this.additionalNoClassDates = const [],
    this.adjustments = const [],
  });

  final bool skipOfficialHolidays;
  final List<String> additionalNoClassDates;
  final List<ScheduleDateAdjustment> adjustments;

  static const empty = ScheduleCalendarRules();

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

  bool isNoClassDate(DateTime date) {
    final key = scheduleDateKey(date);
    return additionalNoClassDates.contains(key) ||
        (skipOfficialHolidays && _officialHolidayDates.contains(key));
  }

  List<ScheduleCourseOccurrence> resolveOccurrences({
    required List<Course> courses,
    required DateTime semesterStart,
    required int totalWeeks,
  }) {
    final semesterMonday = _semesterMonday(semesterStart);
    final adjustmentsBySource = {
      for (final adjustment in adjustments) adjustment.sourceKey: adjustment,
    };
    final occurrences = <ScheduleCourseOccurrence>[];

    for (final course in courses) {
      final weeks = course.weekList.toSet().toList()..sort();
      for (final week in weeks) {
        if (week < 1 || week > totalWeeks) continue;

        final originalDate = semesterMonday.add(
          Duration(days: (week - 1) * 7 + course.dayOfWeek - 1),
        );
        final adjustment = adjustmentsBySource[scheduleDateKey(originalDate)];
        if (adjustment == null && isNoClassDate(originalDate)) continue;

        occurrences.add(
          ScheduleCourseOccurrence(
            course: course,
            originalDate: originalDate,
            scheduledDate: adjustment?.targetDate ?? originalDate,
          ),
        );
      }
    }

    occurrences.sort((a, b) {
      final date = a.scheduledDate.compareTo(b.scheduledDate);
      if (date != 0) return date;
      return a.course.timeSlot.compareTo(b.course.timeSlot);
    });
    return occurrences;
  }

  int weekOf(DateTime date, DateTime semesterStart) {
    final days = _dateOnly(
      date,
    ).difference(_semesterMonday(semesterStart)).inDays;
    return days ~/ 7 + 1;
  }

  ScheduleCalendarRules copyWith({
    bool? skipOfficialHolidays,
    List<String>? additionalNoClassDates,
    List<ScheduleDateAdjustment>? adjustments,
  }) =>
      ScheduleCalendarRules(
        skipOfficialHolidays: skipOfficialHolidays ?? this.skipOfficialHolidays,
        additionalNoClassDates:
            additionalNoClassDates ?? this.additionalNoClassDates,
        adjustments: adjustments ?? this.adjustments,
      );

  Map<String, Object> toJson() => {
        'skipOfficialHolidays': skipOfficialHolidays,
        'additionalNoClassDates': additionalNoClassDates,
        'adjustments':
            adjustments.map((adjustment) => adjustment.toJson()).toList(),
      };

  static ScheduleCalendarRules fromJson(Object? value) {
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

    return ScheduleCalendarRules(
      skipOfficialHolidays: value['skipOfficialHolidays'] != false,
      additionalNoClassDates: noClassDates,
      adjustments: adjustments,
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

DateTime _semesterMonday(DateTime semesterStart) {
  final start = _dateOnly(semesterStart);
  return start.subtract(Duration(days: start.weekday - DateTime.monday));
}
