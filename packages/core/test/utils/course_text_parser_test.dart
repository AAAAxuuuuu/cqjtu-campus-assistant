import 'package:core/utils/course_text_parser.dart';
import 'package:test/test.dart';

void main() {
  group('CourseTextParser Tests', () {
    test('parses single line schedule text without labels', () {
      const input = '高等数学 周一 1-2节 1-16周 A101 张三';
      final result = CourseTextParser.parse(input);

      expect(result.name, equals('高等数学'));
      expect(result.weekday, equals(1));
      expect(result.startSlot, equals(1));
      expect(result.endSlot, equals(2));
      expect(result.startWeek, equals(1));
      expect(result.endWeek, equals(16));
      expect(result.classroom, equals('A101'));
      expect(result.teacher, equals('张三'));
    });

    test('parses labelled multi-line notification text', () {
      const input = '''
课程名称：数据结构
上课时间：周三 3-4节 (1-12周)
上课地点：第一教学楼201
任课教师：李四
''';
      final result = CourseTextParser.parse(input);

      expect(result.name, equals('数据结构'));
      expect(result.weekday, equals(3));
      expect(result.startSlot, equals(3));
      expect(result.endSlot, equals(4));
      expect(result.startWeek, equals(1));
      expect(result.endWeek, equals(12));
      expect(result.classroom, equals('第一教学楼201'));
      expect(result.teacher, equals('李四'));
    });

    test('parses partial text gracefully', () {
      const input = '大学物理 5-6节';
      final result = CourseTextParser.parse(input);

      expect(result.name, equals('大学物理'));
      expect(result.startSlot, equals(5));
      expect(result.endSlot, equals(6));
      expect(result.hasAnyField, isTrue);
    });

    test('returns empty result for empty string', () {
      final result = CourseTextParser.parse('   ');
      expect(result.hasAnyField, isFalse);
    });
  });
}
