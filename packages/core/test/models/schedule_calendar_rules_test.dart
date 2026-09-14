import 'package:core/models/course.dart';
import 'package:core/models/schedule_calendar_rules.dart';
import 'package:test/test.dart';

void main() {
  // 26-27 第1学期：第 1 周周一 = 2026-09-07，故第 5 周为 10/05 - 10/11。
  final semesterStart = DateTime(2026, 9, 7);
  const totalWeeks = 20;

  // 周三 6-7 节，timeStr "1-9,11,13,15(周)"，第 5 周在 weekList 内。
  const wednesdayCourse = Course(
    name: '计算机系统基础',
    teacher: '李艳辉',
    timeStr: '1-9,11,13,15(周)[06-07节]',
    classroom: '20606',
    dayOfWeek: 3,
    timeSlot: 6,
    endTimeSlot: 7,
    weekList: [1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 13, 15],
  );

  // 周二 8-9 节，只在双周上课，第 5 周本就没课。
  const tuesdayCourse = Course(
    name: '创业基础',
    teacher: '',
    timeStr: '2,4,6,8(周)[08-09节]',
    classroom: '20510',
    dayOfWeek: 2,
    timeSlot: 8,
    endTimeSlot: 9,
    weekList: [2, 4, 6, 8],
  );

  ScheduleCourseOccurrence? occurrenceOn(
    List<ScheduleCourseOccurrence> all,
    DateTime date,
  ) {
    final key = scheduleDateKey(date);
    final matches = all.where(
      (o) => scheduleDateKey(o.scheduledDate) == key,
    );
    return matches.isEmpty ? null : matches.first;
  }

  group('假期停课', () {
    test('默认不返回被假期挡掉的 occurrence（提醒/小组件路径）', () {
      final occurrences = const ScheduleCalendarRules().resolveOccurrences(
        courses: [wednesdayCourse],
        semesterStart: semesterStart,
        totalWeeks: totalWeeks,
      );

      expect(occurrenceOn(occurrences, DateTime(2026, 10, 7)), isNull);
    });

    test('includeCancelled 时 10/7 返回 holidayCancelled 占位', () {
      final occurrences = const ScheduleCalendarRules().resolveOccurrences(
        courses: [wednesdayCourse],
        semesterStart: semesterStart,
        totalWeeks: totalWeeks,
        includeCancelled: true,
      );

      final holiday = occurrenceOn(occurrences, DateTime(2026, 10, 7));
      expect(holiday, isNotNull);
      expect(holiday!.displayStatus, CourseDisplayStatus.holidayCancelled);
      expect(holiday.isScheduled, isFalse);
      expect(holiday.asDisplayCourse().displayStatusLabel, '假期停课');
    });

    test('非假期周照常点亮', () {
      final occurrences = const ScheduleCalendarRules().resolveOccurrences(
        courses: [wednesdayCourse],
        semesterStart: semesterStart,
        totalWeeks: totalWeeks,
        includeCancelled: true,
      );

      // 第 4 周周三 = 9/30，第 6 周周三 = 10/14，均非节假日。
      for (final date in [DateTime(2026, 9, 30), DateTime(2026, 10, 14)]) {
        final o = occurrenceOn(occurrences, date);
        expect(o, isNotNull, reason: '$date 应有课');
        expect(o!.isScheduled, isTrue);
      }
    });
  });

  group('调休', () {
    // 把 10/6（假期内）的课调到 9/20 上。
    final rules = ScheduleCalendarRules(
      adjustments: [
        ScheduleDateAdjustment(
          sourceDate: DateTime(2026, 10, 6),
          targetDate: DateTime(2026, 9, 20),
        ),
      ],
    );

    // 周二 8-9 节且第 5 周有课，这样 10/6 才会命中调休。
    const tuesdayEveryWeek = Course(
      name: '创业基础',
      teacher: '',
      timeStr: '1-16(周)[08-09节]',
      classroom: '20510',
      dayOfWeek: 2,
      timeSlot: 8,
      endTimeSlot: 9,
      weekList: [1, 2, 3, 4, 5, 6, 7, 8],
    );

    test('调休优先于假期：源日期 10/6 是 movedOut 而非 holidayCancelled', () {
      final occurrences = rules.resolveOccurrences(
        courses: [tuesdayEveryWeek],
        semesterStart: semesterStart,
        totalWeeks: totalWeeks,
        includeCancelled: true,
      );

      final source = occurrenceOn(occurrences, DateTime(2026, 10, 6));
      expect(source, isNotNull);
      expect(source!.displayStatus, CourseDisplayStatus.movedOut);
      expect(source.isScheduled, isFalse);
      expect(source.asDisplayCourse().displayStatusLabel, '已调休');
    });

    test('目标日期 9/20 点亮，且排布与源日期一致', () {
      final occurrences = rules.resolveOccurrences(
        courses: [tuesdayEveryWeek],
        semesterStart: semesterStart,
        totalWeeks: totalWeeks,
        includeCancelled: true,
      );

      final target = occurrenceOn(occurrences, DateTime(2026, 9, 20));
      expect(target, isNotNull);
      expect(target!.isScheduled, isTrue);
      expect(target.isAdjusted, isTrue);

      final cell = target.asDisplayCourse();
      expect(cell.isDisplayActive, isTrue);
      // 9/20 是周日，格子要落到周日那列，节次不变。
      expect(cell.dayOfWeek, DateTime.sunday);
      expect(cell.timeSlot, 8);
      expect(cell.endTimeSlot, 9);
    });

    test('调休后的课仍会发提醒（默认路径保留 target）', () {
      final occurrences = rules.resolveOccurrences(
        courses: [tuesdayEveryWeek],
        semesterStart: semesterStart,
        totalWeeks: totalWeeks,
      );

      expect(occurrenceOn(occurrences, DateTime(2026, 9, 20)), isNotNull);
      expect(occurrenceOn(occurrences, DateTime(2026, 10, 6)), isNull);
    });
  });

  group('asDisplayCourse 保留整学期周数', () {
    test('weekList 不再被改写成单周', () {
      final occurrences = const ScheduleCalendarRules().resolveOccurrences(
        courses: [wednesdayCourse],
        semesterStart: semesterStart,
        totalWeeks: totalWeeks,
      );
      final cell = occurrences.first.asDisplayCourse();

      // 详情弹窗展示「共 N 周」，N 应为 12 而不是 1。
      expect(cell.weekList.length, 12);
    });

    test('asCourseForWeek 仍收窄为单周（小组件/提醒依赖此语义）', () {
      final occurrences = const ScheduleCalendarRules().resolveOccurrences(
        courses: [wednesdayCourse],
        semesterStart: semesterStart,
        totalWeeks: totalWeeks,
      );
      final widgetCourse = occurrences.first.asCourseForWeek(1);

      expect(widgetCourse.weekList, [1]);
      expect(widgetCourse.isActiveInWeek(1), isTrue);
    });
  });

  group('本周无课与假期停课可区分', () {
    test('第 5 周：周二本就无课，周三是假期停课', () {
      const rules = ScheduleCalendarRules();
      final occurrences = rules.resolveOccurrences(
        courses: [wednesdayCourse, tuesdayCourse],
        semesterStart: semesterStart,
        totalWeeks: totalWeeks,
        includeCancelled: true,
      );
      final week5 = occurrences
          .where((o) => rules.weekOf(o.scheduledDate, semesterStart) == 5)
          .toList();

      // 周三有占位；周二完全没有 occurrence（由 UI 补 noClassThisWeek）。
      expect(week5.map((o) => o.scheduledDate.weekday), [DateTime.wednesday]);
      expect(
        week5.single.displayStatus,
        CourseDisplayStatus.holidayCancelled,
      );
    });
  });

  group('weekOf 计算', () {
    test('周一为第一天 vs 周日为第一天', () {
      const rules = ScheduleCalendarRules();
      // 2026-09-07 是周一
      final semStart = DateTime(2026, 9, 7);

      // 周一为第一天：9/7(一) - 9/13(日) 为第 1 周
      expect(
          rules.weekOf(DateTime(2026, 9, 7), semStart, sundayFirst: false), 1);
      expect(
          rules.weekOf(DateTime(2026, 9, 13), semStart, sundayFirst: false), 1);
      // 9/14(一) - 9/20(日) 为第 2 周
      expect(
          rules.weekOf(DateTime(2026, 9, 14), semStart, sundayFirst: false), 2);
      expect(
          rules.weekOf(DateTime(2026, 9, 20), semStart, sundayFirst: false), 2);
      // 9/21(一) - 9/27(日) 为第 3 周
      expect(
          rules.weekOf(DateTime(2026, 9, 21), semStart, sundayFirst: false), 3);
      expect(
          rules.weekOf(DateTime(2026, 9, 27), semStart, sundayFirst: false), 3);

      // 周日为第一天：
      // 第 1 周：9/6(日) - 9/12(六)
      expect(
          rules.weekOf(DateTime(2026, 9, 7), semStart, sundayFirst: true), 1);
      expect(
          rules.weekOf(DateTime(2026, 9, 12), semStart, sundayFirst: true), 1);
      // 第 2 周：9/13(日) - 9/19(六)
      expect(
          rules.weekOf(DateTime(2026, 9, 13), semStart, sundayFirst: true), 2);
      expect(
          rules.weekOf(DateTime(2026, 9, 19), semStart, sundayFirst: true), 2);
      // 第 3 周：9/20(日) - 9/26(六)
      expect(
          rules.weekOf(DateTime(2026, 9, 20), semStart, sundayFirst: true), 3);
      expect(
          rules.weekOf(DateTime(2026, 9, 26), semStart, sundayFirst: true), 3);
      // 第 4 周：9/27(日) - 10/3(六)
      expect(
          rules.weekOf(DateTime(2026, 9, 27), semStart, sundayFirst: true), 4);
      expect(
          rules.weekOf(DateTime(2026, 10, 3), semStart, sundayFirst: true), 4);
    });
  });
}
