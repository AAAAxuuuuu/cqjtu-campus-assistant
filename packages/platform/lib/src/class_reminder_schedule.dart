import 'package:core/models/course.dart';
import 'package:core/models/schedule_calendar_rules.dart';

class ClassReminder {
  const ClassReminder({
    required this.id,
    required this.courseName,
    required this.classroom,
    required this.teacher,
    required this.timeText,
    required this.week,
    required this.weekday,
    required this.remindAt,
    required this.classStartAt,
    this.isExam = false,
    this.seatNumber = '',
  });

  final int id;
  final String courseName;
  final String classroom;
  final String teacher;
  final String timeText;
  final int week;
  final int weekday;
  final DateTime remindAt;
  final DateTime classStartAt;
  final bool isExam;
  final String seatNumber;

  Map<String, Object?> toPlatformMap() => {
        'id': id,
        'courseName': courseName,
        'classroom': classroom,
        'teacher': teacher,
        'timeText': timeText,
        'week': week,
        'weekday': weekday,
        'remindAtMillis': remindAt.millisecondsSinceEpoch,
        'classStartAtMillis': classStartAt.millisecondsSinceEpoch,
        'isExam': isExam,
        'seatNumber': seatNumber,
      };
}

const Map<int, String> classSlotStartTimes = {
  1: '08:20',
  2: '09:05',
  3: '10:00',
  4: '10:45',
  5: '11:30',
  6: '14:00',
  7: '14:45',
  8: '15:40',
  9: '16:25',
  10: '17:10',
  11: '19:00',
  12: '19:45',
  13: '20:30',
};

List<ClassReminder> buildClassReminders({
  required List<Course> courses,
  required DateTime semesterStart,
  required DateTime now,
  required int reminderMinutes,
  int totalWeeks = 20,
  ScheduleCalendarRules calendarRules = ScheduleCalendarRules.empty,
  bool includeActiveReminders = false,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final reminders = <ClassReminder>[];
  final idCollisions = <int, int>{};

  for (final occurrence in calendarRules.resolveOccurrences(
    courses: courses,
    semesterStart: semesterStart,
    totalWeeks: totalWeeks,
  )) {
    final course = occurrence.course;
    final classDate = occurrence.scheduledDate;
    final daysFromToday = classDate.difference(today).inDays;
    if (daysFromToday < 0 || daysFromToday > 7) continue;

    final timeText = _startTimeTextForCourse(course);
    if (timeText == null) continue;

    final timeParts = timeText.split(':');
    final classStartAt = DateTime(
      classDate.year,
      classDate.month,
      classDate.day,
      int.parse(timeParts[0]),
      int.parse(timeParts[1]),
    );
    final remindAt = classStartAt.subtract(Duration(minutes: reminderMinutes));

    final isPendingReminder = remindAt.isAfter(now);
    final isActiveReminder =
        includeActiveReminders && classStartAt.isAfter(now);
    if (!isPendingReminder && !isActiveReminder) continue;

    final idBase = _classReminderIdBase(
      date: classDate,
      timeSlot: course.timeSlot,
    );
    final collisionIndex = idCollisions.update(
      idBase,
      (value) => value + 1,
      ifAbsent: () => 0,
    );

    reminders.add(
      ClassReminder(
        id: idBase + collisionIndex,
        courseName: course.name,
        classroom: course.classroom,
        teacher: course.teacher,
        timeText: timeText,
        week: calendarRules.weekOf(classDate, semesterStart),
        weekday: classDate.weekday,
        remindAt: remindAt,
        classStartAt: classStartAt,
        isExam: course.isExam,
        seatNumber: course.seatNumber,
      ),
    );
  }

  return reminders;
}

int _classReminderIdBase({required DateTime date, required int timeSlot}) =>
    date.year * 1000000 + date.month * 10000 + date.day * 100 + timeSlot;

String? _startTimeTextForCourse(Course course) {
  final exactStartMinutes = course.exactStartMinutes;
  if (exactStartMinutes != null) return _timeTextFromMinutes(exactStartMinutes);

  if (course.isExam) {
    final match = RegExp(
      r'(\d{1,2}):(\d{2})',
    ).firstMatch(course.timeStr.replaceAll('：', ':'));
    if (match != null) {
      final hour = match.group(1)!.padLeft(2, '0');
      return '$hour:${match.group(2)!}';
    }
  }
  return classSlotStartTimes[course.timeSlot];
}

String _timeTextFromMinutes(int minutes) {
  final clamped = minutes.clamp(0, 23 * 60 + 59);
  final hour = clamped ~/ 60;
  final minute = clamped % 60;
  return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}
