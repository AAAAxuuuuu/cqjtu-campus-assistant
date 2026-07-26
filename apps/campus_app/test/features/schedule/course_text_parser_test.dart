import 'package:flutter_test/flutter_test.dart';
import 'package:campus_app/features/schedule/utils/course_text_parser.dart';

void main() {
  group('CourseTextParser', () {
    test('single-line format parsing', () {
      const rawText = '高等数学 周一 1-2节 1-16周 A101 张三老师';
      final parsed = CourseTextParser.parse(rawText);

      expect(parsed.name, equals('高等数学'));
      expect(parsed.weekday, equals(1));
      expect(parsed.startSlot, equals(1));
      expect(parsed.endSlot, equals(2));
      expect(parsed.startWeek, equals(1));
      expect(parsed.endWeek, equals(16));
      expect(parsed.classroom, equals('A101'));
      expect(parsed.teacher, equals('张三'));
      expect(parsed.hasAnyField, isTrue);
    });

    test('multi-line format parsing with explicit tags', () {
      const rawText = '''
课程：大学物理
时间：周三 3-4节
周次：1-16周
地点：B202
教师：李四
''';
      final parsed = CourseTextParser.parse(rawText);

      expect(parsed.name, equals('大学物理'));
      expect(parsed.weekday, equals(3));
      expect(parsed.startSlot, equals(3));
      expect(parsed.endSlot, equals(4));
      expect(parsed.startWeek, equals(1));
      expect(parsed.endWeek, equals(16));
      expect(parsed.classroom, equals('B202'));
      expect(parsed.teacher, equals('李四'));
      expect(parsed.hasAnyField, isTrue);
    });

    test('isolated patterns - weekday and slots', () {
      const rawText = '周一 3-4节';
      final parsed = CourseTextParser.parse(rawText);

      expect(parsed.name, isNull);
      expect(parsed.weekday, equals(1));
      expect(parsed.startSlot, equals(3));
      expect(parsed.endSlot, equals(4));
      expect(parsed.startWeek, isNull);
      expect(parsed.endWeek, isNull);
      expect(parsed.classroom, isNull);
      expect(parsed.teacher, isNull);
      expect(parsed.hasAnyField, isTrue);
    });

    test('isolated patterns - week range', () {
      const rawText = '1-16周';
      final parsed = CourseTextParser.parse(rawText);

      expect(parsed.name, isNull);
      expect(parsed.startWeek, equals(1));
      expect(parsed.endWeek, equals(16));
      expect(parsed.weekday, isNull);
      expect(parsed.startSlot, isNull);
      expect(parsed.classroom, isNull);
      expect(parsed.teacher, isNull);
      expect(parsed.hasAnyField, isTrue);
    });

    test('isolated patterns - classroom', () {
      const rawText = '301教室';
      final parsed = CourseTextParser.parse(rawText);

      expect(parsed.classroom, equals('301教室'));
      expect(parsed.name, isNull);
      expect(parsed.teacher, isNull);
      expect(parsed.weekday, isNull);
      expect(parsed.hasAnyField, isTrue);
    });

    test('isolated patterns - teacher with title suffix', () {
      const rawText = '王五老师';
      final parsed = CourseTextParser.parse(rawText);

      expect(parsed.teacher, equals('王五'));
      expect(parsed.name, isNull);
      expect(parsed.classroom, isNull);
      expect(parsed.weekday, isNull);
      expect(parsed.hasAnyField, isTrue);
    });

    test('weekday formats (星期二, 周5, 礼拜日)', () {
      final parsedTue = CourseTextParser.parse('星期二 1-2节');
      expect(parsedTue.weekday, equals(2));

      final parsedFri = CourseTextParser.parse('周5 7-8节');
      expect(parsedFri.weekday, equals(5));

      final parsedSun = CourseTextParser.parse('礼拜日 1-2节');
      expect(parsedSun.weekday, equals(7));

      final parsedSun2 = CourseTextParser.parse('周天 3-4节');
      expect(parsedSun2.weekday, equals(7));
    });

    test('time slot variants (第3-4节, 1~2节, 3,4节)', () {
      final p1 = CourseTextParser.parse('第3-4节');
      expect(p1.startSlot, equals(3));
      expect(p1.endSlot, equals(4));

      final p2 = CourseTextParser.parse('1~2节');
      expect(p2.startSlot, equals(1));
      expect(p2.endSlot, equals(2));

      final p3 = CourseTextParser.parse('3,4节');
      expect(p3.startSlot, equals(3));
      expect(p3.endSlot, equals(4));
    });

    test('week range variants (第1-16周, 3-15周(单), 16周)', () {
      final p1 = CourseTextParser.parse('第1-16周');
      expect(p1.startWeek, equals(1));
      expect(p1.endWeek, equals(16));

      final p2 = CourseTextParser.parse('3-15周(单)');
      expect(p2.startWeek, equals(3));
      expect(p2.endWeek, equals(15));

      final p3 = CourseTextParser.parse('16周');
      expect(p3.startWeek, equals(16));
      expect(p3.endWeek, equals(16));
    });

    test('classroom building patterns (教学楼B202, 实验室504)', () {
      final p1 = CourseTextParser.parse('教学楼B202');
      expect(p1.classroom, equals('教学楼B202'));

      final p2 = CourseTextParser.parse('实验室504');
      expect(p2.classroom, equals('实验室504'));
    });

    test('partial parsing fallback and empty text', () {
      final emptyResult = CourseTextParser.parse('');
      expect(emptyResult.hasAnyField, isFalse);

      final whitespaceResult = CourseTextParser.parse('   \n\t  ');
      expect(whitespaceResult.hasAnyField, isFalse);

      final invalidSymbols = CourseTextParser.parse(',,, ;;;');
      expect(invalidSymbols.hasAnyField, isFalse);
    });

    test('unstructured line with untagged teacher and course name', () {
      const text = '线性代数 周二 5-6节 1-16周 教学楼A102 李四教授';
      final parsed = CourseTextParser.parse(text);

      expect(parsed.name, equals('线性代数'));
      expect(parsed.weekday, equals(2));
      expect(parsed.startSlot, equals(5));
      expect(parsed.endSlot, equals(6));
      expect(parsed.startWeek, equals(1));
      expect(parsed.endWeek, equals(16));
      expect(parsed.classroom, equals('教学楼A102'));
      expect(parsed.teacher, equals('李四'));
    });
  });
}
