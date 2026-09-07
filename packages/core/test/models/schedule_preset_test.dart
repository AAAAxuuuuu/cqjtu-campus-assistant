import 'package:core/models/course.dart';
import 'package:core/models/schedule_calendar_rules.dart';
import 'package:test/test.dart';

void main() {
  final preset = SchedulePresetCatalog.nationalDay2026;
  final semesterStart = DateTime(2026, 9, 7);
  const totalWeeks = 20;

  final rules = ScheduleCalendarRules(enabledPresets: [preset]);

  /// 某一天是否真的上课（含调休挪来的课）。
  bool hasClassOn(DateTime date, {required int dayOfWeekOfCourse}) {
    final course = Course(
      name: '测试课',
      teacher: '',
      timeStr: '',
      classroom: '',
      dayOfWeek: dayOfWeekOfCourse,
      timeSlot: 1,
      endTimeSlot: 2,
      weekList: List.generate(totalWeeks, (i) => i + 1),
    );
    final key = scheduleDateKey(date);
    return rules.resolveOccurrences(
      courses: [course],
      semesterStart: semesterStart,
      totalWeeks: totalWeeks,
    ).any((o) => scheduleDateKey(o.scheduledDate) == key);
  }

  group('通知逐条核对：调休四组', () {
    // 9月20日（周日）上班，补上10月6日（周二）的课程
    // 9月26日（周六）上班，补上9月29日（周二）的课程
    // 9月27日（周日）上班，补上9月30日（周三）的课程
    // 10月10日（周六）上班，补上10月7日（周三）的课程
    final expected = {
      '2026-09-20': '2026-10-06',
      '2026-09-26': '2026-09-29',
      '2026-09-27': '2026-09-30',
      '2026-10-10': '2026-10-07',
    };

    test('四组调休的源/目标日期与通知一致', () {
      final actual = {
        for (final a in preset.adjustments) a.targetKey: a.sourceKey,
      };
      expect(actual, expected);
    });

    test('补课日星期与通知一致（周日/周六/周日/周六）', () {
      expect(DateTime(2026, 9, 20).weekday, DateTime.sunday);
      expect(DateTime(2026, 9, 26).weekday, DateTime.saturday);
      expect(DateTime(2026, 9, 27).weekday, DateTime.sunday);
      expect(DateTime(2026, 10, 10).weekday, DateTime.saturday);
    });

    test('被调休的原课日星期与通知一致（周二/周二/周三/周三）', () {
      expect(DateTime(2026, 10, 6).weekday, DateTime.tuesday);
      expect(DateTime(2026, 9, 29).weekday, DateTime.tuesday);
      expect(DateTime(2026, 9, 30).weekday, DateTime.wednesday);
      expect(DateTime(2026, 10, 7).weekday, DateTime.wednesday);
    });

    test('周二的课挪到 9/20 与 9/26 上，10/6 与 9/29 当天不上课', () {
      expect(hasClassOn(DateTime(2026, 9, 20), dayOfWeekOfCourse: 2), isTrue);
      expect(hasClassOn(DateTime(2026, 9, 26), dayOfWeekOfCourse: 2), isTrue);
      expect(hasClassOn(DateTime(2026, 10, 6), dayOfWeekOfCourse: 2), isFalse);
      expect(hasClassOn(DateTime(2026, 9, 29), dayOfWeekOfCourse: 2), isFalse);
    });

    test('周三的课挪到 9/27 与 10/10 上，9/30 与 10/7 当天不上课', () {
      expect(hasClassOn(DateTime(2026, 9, 27), dayOfWeekOfCourse: 3), isTrue);
      expect(hasClassOn(DateTime(2026, 10, 10), dayOfWeekOfCourse: 3), isTrue);
      expect(hasClassOn(DateTime(2026, 9, 30), dayOfWeekOfCourse: 3), isFalse);
      expect(hasClassOn(DateTime(2026, 10, 7), dayOfWeekOfCourse: 3), isFalse);
    });
  });

  group('通知逐条核对：停课', () {
    test('10/1 - 10/5 停课', () {
      for (var day = 1; day <= 5; day++) {
        expect(
          rules.isNoClassDate(DateTime(2026, 10, day)),
          isTrue,
          reason: '10/$day 应停课',
        );
      }
    });

    test('原排在补课日（周末）的课停掉，由任课教师自行补', () {
      // 9/20 是周日：周日原本的课停掉，那天只上调休挪来的周二课程。
      expect(hasClassOn(DateTime(2026, 9, 20), dayOfWeekOfCourse: 7), isFalse);
      // 10/10 是周六：周六原有的课同理停掉。
      expect(hasClassOn(DateTime(2026, 10, 10), dayOfWeekOfCourse: 6), isFalse);
    });

    test('假期外的正常日期不受影响', () {
      expect(rules.isNoClassDate(DateTime(2026, 9, 28)), isFalse);
      expect(rules.isNoClassDate(DateTime(2026, 10, 8)), isFalse);
      expect(hasClassOn(DateTime(2026, 10, 14), dayOfWeekOfCourse: 3), isTrue);
    });

    test('9/26、9/27 是中秋法定假期，但通知要求上班，补课仍须落地', () {
      // 内置法定名单含 9/25-9/27（中秋）。调休优先于节假日，
      // 所以这两天的补课不会被假期名单吃掉。
      expect(rules.isMakeupWorkday(DateTime(2026, 9, 26)), isTrue);
      expect(rules.isMakeupWorkday(DateTime(2026, 9, 27)), isTrue);
      expect(hasClassOn(DateTime(2026, 9, 26), dayOfWeekOfCourse: 2), isTrue);
      expect(hasClassOn(DateTime(2026, 9, 27), dayOfWeekOfCourse: 3), isTrue);
    });
  });

  group('调休优先于法定节假日', () {
    const anyWeekdayCourse = Course(
      name: '测试课',
      teacher: '',
      timeStr: '',
      classroom: '',
      dayOfWeek: 4, // 周四
      timeSlot: 1,
      endTimeSlot: 2,
      weekList: [1, 2, 3, 4, 5, 6, 7, 8],
    );

    test('源日期同时是节假日时，判为已调休而非假期停课', () {
      // 10/6 既在法定名单里，也是预设调休的来源。
      final occurrences = rules.resolveOccurrences(
        courses: const [
          Course(
            name: '周二课',
            teacher: '',
            timeStr: '',
            classroom: '',
            dayOfWeek: 2,
            timeSlot: 1,
            endTimeSlot: 2,
            weekList: [1, 2, 3, 4, 5, 6, 7, 8],
          ),
        ],
        semesterStart: semesterStart,
        totalWeeks: totalWeeks,
        includeCancelled: true,
      );

      final source = occurrences.firstWhere(
        (o) => scheduleDateKey(o.scheduledDate) == '2026-10-06',
      );
      expect(source.displayStatus, CourseDisplayStatus.movedOut);
      expect(
        source.displayStatus,
        isNot(CourseDisplayStatus.holidayCancelled),
        reason: '调休应接管该日期，而不是报假期停课',
      );
    });

    test('补课目标日落在法定节假日上时，补课照常落地', () {
      // 10/1 是国庆当天。手动把周四的课调到 10/1，调休应压过假期。
      final overriding = ScheduleCalendarRules(
        adjustments: [
          ScheduleDateAdjustment(
            sourceDate: DateTime(2026, 10, 8),
            targetDate: DateTime(2026, 10, 1),
          ),
        ],
      );

      final landed = overriding.resolveOccurrences(
        courses: const [anyWeekdayCourse],
        semesterStart: semesterStart,
        totalWeeks: totalWeeks,
      ).where((o) => scheduleDateKey(o.scheduledDate) == '2026-10-01');

      expect(landed, isNotEmpty, reason: '调休目标不应被节假日名单挡回');
      expect(landed.single.isScheduled, isTrue);
      // 该日期本身仍属节假日，只是调休把课放了进来。
      expect(overriding.isNoClassDate(DateTime(2026, 10, 1)), isTrue);
      expect(overriding.isMakeupWorkday(DateTime(2026, 10, 1)), isTrue);
    });

    test('isAdjustedAway 与 isNoClassDate 语义分离', () {
      expect(rules.isAdjustedAway(DateTime(2026, 10, 6)), isTrue);
      expect(rules.isAdjustedAway(DateTime(2026, 10, 1)), isFalse);
      expect(rules.isNoClassDate(DateTime(2026, 10, 1)), isTrue);
    });
  });

  group('明细数据分组', () {
    test('停课与补课日分开存放，明细不把补课日列为停课', () {
      expect(preset.noClassDates, [
        '2026-10-01',
        '2026-10-02',
        '2026-10-03',
        '2026-10-04',
        '2026-10-05',
      ]);
      expect(preset.makeupOriginalCancelledDates, [
        '2026-09-20',
        '2026-09-26',
        '2026-09-27',
        '2026-10-10',
      ]);
    });

    test('补课日仍会停掉原有课程（合并进 allNoClassDates）', () {
      expect(preset.allNoClassDates.length, 9);
      for (final date in preset.makeupOriginalCancelledDates) {
        expect(preset.allNoClassDates, contains(date));
      }
      expect(rules.isNoClassDate(DateTime(2026, 9, 20)), isTrue);
    });
  });

  group('渲染状态', () {
    test('10/6 显示为已调休（灰），9/20 显示为正常上课（亮）', () {
      const tuesday = Course(
        name: '创业基础',
        teacher: '',
        timeStr: '1-16(周)[08-09节]',
        classroom: '20510',
        dayOfWeek: 2,
        timeSlot: 8,
        endTimeSlot: 9,
        weekList: [1, 2, 3, 4, 5, 6, 7, 8],
      );

      final occurrences = rules.resolveOccurrences(
        courses: [tuesday],
        semesterStart: semesterStart,
        totalWeeks: totalWeeks,
        includeCancelled: true,
      );

      final source = occurrences.firstWhere(
        (o) => scheduleDateKey(o.scheduledDate) == '2026-10-06',
      );
      expect(source.displayStatus, CourseDisplayStatus.movedOut);
      expect(source.asDisplayCourse().isDisplayActive, isFalse);

      final target = occurrences.firstWhere(
        (o) => scheduleDateKey(o.scheduledDate) == '2026-09-20',
      );
      expect(target.isScheduled, isTrue);
      final cell = target.asDisplayCourse();
      expect(cell.isDisplayActive, isTrue);
      expect(cell.dayOfWeek, DateTime.sunday);
      expect(cell.timeSlot, 8);
      expect(cell.endTimeSlot, 9);
    });
  });

  group('学期结束自动销毁', () {
    test('学期内不过期', () {
      expect(preset.isExpiredAt(DateTime(2026, 9, 7)), isFalse);
      expect(preset.isExpiredAt(DateTime(2026, 10, 7)), isFalse);
      expect(preset.isExpiredAt(DateTime(2027, 1, 31)), isFalse);
    });

    test('学期结束后过期', () {
      expect(preset.isExpiredAt(DateTime(2027, 2, 1)), isTrue);
      expect(preset.isExpiredAt(DateTime(2027, 9, 1)), isTrue);
    });

    test('fromJson 在学期内保留预设', () {
      final restored = ScheduleCalendarRules.fromJson(
        rules.toJson(),
        now: DateTime(2026, 10, 1),
      );
      expect(restored.isPresetEnabled(preset.id), isTrue);
    });

    test('fromJson 在学期结束后丢弃预设，预设专属规则随之还原', () {
      final restored = ScheduleCalendarRules.fromJson(
        rules.toJson(),
        now: DateTime(2027, 2, 1),
      );
      expect(restored.enabledPresets, isEmpty);

      // 9/20 与 10/10 只由预设停课，法定名单里没有，预设失效后恢复为普通日期。
      for (final date in [DateTime(2026, 9, 20), DateTime(2026, 10, 10)]) {
        expect(
          restored.isNoClassDate(date),
          isFalse,
          reason: '$date 的停课应随预设一起移除',
        );
      }

      // 预设的调休也不再生效。
      expect(restored.effectiveAdjustments, isEmpty);

      // 10/6、9/26 等本就是法定节假日，与预设无关，不应被“还原”。
      expect(restored.isNoClassDate(DateTime(2026, 10, 6)), isTrue);
      expect(restored.isNoClassDate(DateTime(2026, 9, 26)), isTrue);
    });

    test('未知 id 直接丢弃', () {
      final restored = ScheduleCalendarRules.fromJson({
        'enabledPresets': ['no_such_preset'],
      });
      expect(restored.enabledPresets, isEmpty);
    });
  });

  group('预设与手动规则互不干扰', () {
    test('关闭预设后手动停课与调休完整保留', () {
      final manual = ScheduleCalendarRules(
        additionalNoClassDates: const ['2026-11-11'],
        adjustments: [
          ScheduleDateAdjustment(
            sourceDate: DateTime(2026, 11, 3),
            targetDate: DateTime(2026, 11, 8),
          ),
        ],
        enabledPresets: [preset],
      );

      final withoutPreset = manual.copyWith(enabledPresets: const []);
      expect(withoutPreset.additionalNoClassDates, ['2026-11-11']);
      expect(withoutPreset.adjustments.single.sourceKey, '2026-11-03');
      // 预设的日期随开关一起消失。
      expect(withoutPreset.isNoClassDate(DateTime(2026, 9, 20)), isFalse);
      // 手动的日期不受影响。
      expect(withoutPreset.isNoClassDate(DateTime(2026, 11, 11)), isTrue);
    });

    test('同一天冲突时手动调休覆盖预设', () {
      final overridden = ScheduleCalendarRules(
        adjustments: [
          ScheduleDateAdjustment(
            sourceDate: DateTime(2026, 10, 6),
            targetDate: DateTime(2026, 12, 12),
          ),
        ],
        enabledPresets: [preset],
      );

      expect(
        overridden.effectiveAdjustments['2026-10-06']!.targetKey,
        '2026-12-12',
      );
    });

    test('toJson 只写预设 id，不展开日期', () {
      final json = rules.toJson();
      expect(json['enabledPresets'], [preset.id]);
      expect(json['additionalNoClassDates'], isEmpty);
      expect(json['adjustments'], isEmpty);
    });
  });
}
