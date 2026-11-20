// packages/core/test/models/course_test.dart

import 'package:test/test.dart';
import 'package:core/models/course.dart';

void main() {
  group('Course.isActiveInWeek', () {
    const course = Course(
      name: '高等数学',
      teacher: '张老师',
      timeStr: '周一 1-2节',
      classroom: 'A101',
      dayOfWeek: 1,
      timeSlot: 1,
      weekList: [1, 2, 3, 5, 7], // 跳跃周
    );

    test('包含在 weekList 中的周返回 true', () {
      expect(course.isActiveInWeek(1), isTrue);
      expect(course.isActiveInWeek(3), isTrue);
      expect(course.isActiveInWeek(7), isTrue);
    });

    test('不在 weekList 中的周返回 false', () {
      expect(course.isActiveInWeek(4), isFalse);
      expect(course.isActiveInWeek(6), isFalse);
      expect(course.isActiveInWeek(8), isFalse);
    });

    test('weekList 为空时任意周均返回 false', () {
      const emptyCourse = Course(
        name: '体育',
        teacher: '李老师',
        timeStr: '',
        classroom: '',
        dayOfWeek: 3,
        timeSlot: 9,
        weekList: [],
      );
      expect(emptyCourse.isActiveInWeek(1), isFalse);
      expect(emptyCourse.isActiveInWeek(99), isFalse);
    });
  });

  group('Course.slotSpan', () {
    test('默认 endTimeSlot == timeSlot 时 slotSpan == 1', () {
      const c = Course(
        name: 'x',
        teacher: '',
        timeStr: '',
        classroom: '',
        dayOfWeek: 1,
        timeSlot: 3,
        weekList: [],
      );
      expect(c.slotSpan, equals(1));
    });

    test('endTimeSlot > timeSlot 时 slotSpan 正确计算', () {
      const c = Course(
        name: 'x',
        teacher: '',
        timeStr: '',
        classroom: '',
        dayOfWeek: 2,
        timeSlot: 1,
        endTimeSlot: 4,
        weekList: [],
      );
      expect(c.slotSpan, equals(4));
    });
  });

  group('Course.fromJson', () {
    test('正常 JSON 全字段解析', () {
      final json = {
        'name': '线性代数',
        'teacher': '王老师',
        'timeStr': '周三 3-4节',
        'classroom': 'B202',
        'dayOfWeek': 3,
        'timeSlot': 3,
        'endTimeSlot': 4,
        'weekList': [1, 2, 4, 6, 8],
      };
      final c = Course.fromJson(json);
      expect(c.name, '线性代数');
      expect(c.teacher, '王老师');
      expect(c.dayOfWeek, 3);
      expect(c.timeSlot, 3);
      expect(c.endTimeSlot, 4);
      expect(c.weekList, [1, 2, 4, 6, 8]);
    });

    test('缺少可选字段时使用默认值', () {
      final c = Course.fromJson({});
      expect(c.name, '');
      expect(c.dayOfWeek, 1);
      expect(c.timeSlot, 1);
      expect(c.weekList, isEmpty);
      expect(c.slotSpan, 1); // endTimeSlot 默认 == timeSlot
    });

    test('weekList 缺失时返回空列表', () {
      final c = Course.fromJson({
        'name': 'test',
        'dayOfWeek': 1,
        'timeSlot': 1,
      });
      expect(c.weekList, isEmpty);
    });
  });
  group('Course exact exam minutes', () {
    test('preserves exact exam minutes in JSON', () {
      const c = Course(
        name: 'Exam',
        teacher: '',
        timeStr: '2026-06-30 14:30-16:30',
        classroom: 'A01128',
        dayOfWeek: 2,
        timeSlot: 6,
        endTimeSlot: 9,
        weekList: [18],
        isExam: true,
        exactStartMinutes: 14 * 60 + 30,
        exactEndMinutes: 16 * 60 + 30,
      );

      final restored = Course.fromJson(c.toJson());

      expect(restored.exactStartMinutes, 14 * 60 + 30);
      expect(restored.exactEndMinutes, 16 * 60 + 30);
    });

    test('recovers exact exam minutes from legacy cached timeStr', () {
      final c = Course.fromJson({
        'name': 'Exam',
        'timeStr': '2026-06-30 14:30-16:30',
        'dayOfWeek': 2,
        'timeSlot': 7,
        'endTimeSlot': 9,
        'weekList': [18],
        'isExam': true,
      });

      expect(c.exactStartMinutes, 14 * 60 + 30);
      expect(c.exactEndMinutes, 16 * 60 + 30);
    });
  });

  group('deduplicateCourses', () {
    const fourSlot = Course(
      name: '工程实训',
      teacher: '王老师',
      timeStr: '17(周)[06-07-08-09节]',
      classroom: '601005一机房A区',
      dayOfWeek: 1,
      timeSlot: 6,
      endTimeSlot: 9,
      weekList: [17],
    );

    test('collapses identical multi-row school courses while preserving order',
        () {
      final duplicate = Course(
        name: ' 工程实训 ',
        teacher: '王老师',
        timeStr: '17(周)[06-07-08-09节]',
        classroom: '601005一机房A区',
        dayOfWeek: 1,
        timeSlot: 6,
        endTimeSlot: 9,
        weekList: const [17, 17],
      );
      const other = Course(
        name: '高等数学',
        teacher: '张老师',
        timeStr: '1-16(周)[06-07节]',
        classroom: '20101',
        dayOfWeek: 1,
        timeSlot: 6,
        endTimeSlot: 7,
        weekList: [1, 2, 3],
      );

      final result = deduplicateCourses([other, fourSlot, duplicate]);
      expect(result, hasLength(2));
      expect(result[0].name, '高等数学');
      expect(result[1].name, '工程实训');
    });

    test(
        'keeps distinct courses that differ by week, slot, day, teacher, or room',
        () {
      final diffWeek = fourSlot.copyWith(weekList: const [18]);
      final diffSlot = fourSlot.copyWith(timeSlot: 1, endTimeSlot: 4);
      final diffDay = fourSlot.copyWith(dayOfWeek: 2);
      final diffTeacher = fourSlot.copyWith(teacher: '李老师');
      final diffRoom = fourSlot.copyWith(classroom: '601006二机房');

      final result = deduplicateCourses([
        fourSlot,
        diffWeek,
        diffSlot,
        diffDay,
        diffTeacher,
        diffRoom,
      ]);
      expect(result, hasLength(6));
    });

    test('preserves duplicate custom courses by default', () {
      final custom1 = fourSlot.copyWith(isCustom: true);
      final custom2 = fourSlot.copyWith(isCustom: true);

      expect(deduplicateCourses([custom1, custom2]), hasLength(2));
      expect(
        deduplicateCourses([custom1, custom2], deduplicateCustom: true),
        hasLength(1),
      );
    });
  });
}
