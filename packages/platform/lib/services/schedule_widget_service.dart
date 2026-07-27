import 'package:core/models/course.dart';
import 'package:core/models/schedule_calendar_rules.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ScheduleWidgetService {
  static const _channel = MethodChannel('campus_app/schedule_widget');

  static bool get _usesNativeAndroidWidgets =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> updateScheduleWidgets({
    required List<Course> courses,
    required DateTime semesterStart,
    String? selectedSemester,
    String remark = '',
    int totalWeeks = 20,
    ScheduleCalendarRules calendarRules = ScheduleCalendarRules.empty,
  }) async {
    if (!_usesNativeAndroidWidgets) return;

    try {
      final actualCourses = calendarRules
          .resolveOccurrences(
            courses: courses,
            semesterStart: semesterStart,
            totalWeeks: totalWeeks,
          )
          .map((occurrence) {
            final week = calendarRules.weekOf(
              occurrence.scheduledDate,
              semesterStart,
            );
            return week < 1 || week > totalWeeks
                ? null
                : occurrence.asCourseForWeek(week);
          })
          .whereType<Course>()
          .toList();
      await _channel.invokeMethod<void>('updateScheduleWidgets', {
        'courses': actualCourses.map(_courseToMap).toList(),
        'semesterStartMillis': semesterStart.millisecondsSinceEpoch,
        'selectedSemester': selectedSemester,
        'remark': remark,
        'totalWeeks': totalWeeks,
      });
    } catch (error, stackTrace) {
      debugPrint('[WIDGET] updateScheduleWidgets failed: $error');
      debugPrint('$stackTrace');
    }
  }

  static Future<void> clearScheduleWidgets() async {
    if (!_usesNativeAndroidWidgets) return;

    try {
      await _channel.invokeMethod<void>('clearScheduleWidgets');
    } catch (error) {
      debugPrint('[WIDGET] clearScheduleWidgets failed: $error');
    }
  }

  static Future<void> refreshScheduleWidgets() async {
    if (!_usesNativeAndroidWidgets) return;

    try {
      await _channel.invokeMethod<void>('refreshScheduleWidgets');
    } catch (error) {
      debugPrint('[WIDGET] refreshScheduleWidgets failed: $error');
    }
  }

  static Future<void> updateBalances({
    String? campusCardBalance,
    String? electricityBalance,
  }) async {
    if (!_usesNativeAndroidWidgets) return;
    if (campusCardBalance == null && electricityBalance == null) return;

    try {
      await _channel.invokeMethod<void>('updateWidgetBalances', {
        'campusCardBalance': campusCardBalance,
        'electricityBalance': electricityBalance,
      });
    } catch (error) {
      debugPrint('[WIDGET] updateBalances failed: $error');
    }
  }

  static Map<String, Object?> _courseToMap(Course course) => {
    'name': course.name,
    'teacher': course.teacher,
    'timeStr': course.timeStr,
    'classroom': course.classroom,
    'dayOfWeek': course.dayOfWeek,
    'timeSlot': course.timeSlot,
    'endTimeSlot': course.endTimeSlot,
    'weekList': course.weekList,
    'isExam': course.isExam,
    'isCustom': course.isCustom,
    'seatNumber': course.seatNumber,
    'exactStartMinutes': course.exactStartMinutes,
    'exactEndMinutes': course.exactEndMinutes,
  };
}
