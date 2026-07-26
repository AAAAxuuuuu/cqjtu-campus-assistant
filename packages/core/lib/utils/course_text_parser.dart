/// 课程文本识别与自动提取工具。
///
/// 用于从用户复制粘贴的课程描述文本或群通知中，提取课程名称、教室、教师、星期、节次范围和周次范围。
library;

class CourseTextParsedResult {
  const CourseTextParsedResult({
    this.name,
    this.classroom,
    this.teacher,
    this.weekday,
    this.startSlot,
    this.endSlot,
    this.startWeek,
    this.endWeek,
  });

  final String? name;
  final String? classroom;
  final String? teacher;
  final int? weekday;
  final int? startSlot;
  final int? endSlot;
  final int? startWeek;
  final int? endWeek;

  bool get hasAnyField =>
      (name != null && name!.isNotEmpty) ||
      (classroom != null && classroom!.isNotEmpty) ||
      (teacher != null && teacher!.isNotEmpty) ||
      weekday != null ||
      startSlot != null ||
      endSlot != null ||
      startWeek != null ||
      endWeek != null;
}

class CourseTextParser {
  CourseTextParser._();

  static const _weekdayMap = <String, int>{
    '一': 1,
    '1': 1,
    '二': 2,
    '2': 2,
    '三': 3,
    '3': 3,
    '四': 4,
    '4': 4,
    '五': 5,
    '5': 5,
    '六': 6,
    '6': 6,
    '日': 7,
    '七': 7,
    '天': 7,
    '7': 7,
  };

  /// 从给定的文本 [rawInput] 中解析课程要素。
  static CourseTextParsedResult parse(String rawInput) {
    final text = rawInput.trim();
    if (text.isEmpty) return const CourseTextParsedResult();

    String? name;
    String? classroom;
    String? teacher;
    int? weekday;
    int? startSlot;
    int? endSlot;
    int? startWeek;
    int? endWeek;

    // 1. 显式标签解析 (如 课程名称：高等数学)
    final nameLabelMatch = RegExp(
      r'(?:课程名称|课程名|科目)[：:\s]+([^\n,，;；]+)',
    ).firstMatch(text);
    if (nameLabelMatch != null) {
      name = nameLabelMatch.group(1)?.trim();
    }

    final classroomLabelMatch = RegExp(
      r'(?:上课地点|教室|地点|考场|实验室)[：:\s]+([^\n,，;；]+)',
    ).firstMatch(text);
    if (classroomLabelMatch != null) {
      classroom = classroomLabelMatch.group(1)?.trim();
    }

    final teacherLabelMatch = RegExp(
      r'(?:任课教师|授课教师|教师|老师|讲师|教授)[：:\s]+([^\n,，;；]+)',
    ).firstMatch(text);
    if (teacherLabelMatch != null) {
      teacher = teacherLabelMatch.group(1)?.trim();
    }

    // 2. 星期解析 (如 周一、星期三、礼拜五)
    final weekdayMatch = RegExp(
      r'(?:星期|周|禮拜|礼拜)\s*([一二三四五六日七天1-7])',
    ).firstMatch(text);
    if (weekdayMatch != null) {
      final char = weekdayMatch.group(1);
      if (char != null) {
        weekday = _weekdayMap[char];
      }
    }

    // 3. 节次解析 (如 1-2节、3-4节、第5节)
    final slotMatch = RegExp(
      r'(?:第\s*)?(\d{1,2})\s*(?:[-~～—–到至]\s*(\d{1,2}))?\s*节',
    ).firstMatch(text);
    if (slotMatch != null) {
      final startStr = slotMatch.group(1);
      final endStr = slotMatch.group(2);
      if (startStr != null) {
        startSlot = int.tryParse(startStr);
        endSlot = endStr != null ? int.tryParse(endStr) : startSlot;
      }
    }

    // 4. 周次解析 (如 1-16周、第5周)
    final weekMatch = RegExp(
      r'(?:第\s*)?(\d{1,2})\s*(?:[-~～—–到至]\s*(\d{1,2}))?\s*周',
    ).firstMatch(text);
    if (weekMatch != null) {
      final startStr = weekMatch.group(1);
      final endStr = weekMatch.group(2);
      if (startStr != null) {
        startWeek = int.tryParse(startStr);
        endWeek = endStr != null ? int.tryParse(endStr) : startWeek;
      }
    }

    // 5. 如果名称、教室或教师未通过显式标签识别，则清理已匹配的模式后从未标注词汇中提取
    var remaining = text;
    if (nameLabelMatch != null) {
      remaining = remaining.replaceFirst(nameLabelMatch.group(0)!, ' ');
    }
    if (classroomLabelMatch != null) {
      remaining = remaining.replaceFirst(classroomLabelMatch.group(0)!, ' ');
    }
    if (teacherLabelMatch != null) {
      remaining = remaining.replaceFirst(teacherLabelMatch.group(0)!, ' ');
    }
    if (weekdayMatch != null) {
      remaining = remaining.replaceFirst(weekdayMatch.group(0)!, ' ');
    }
    if (slotMatch != null) {
      remaining = remaining.replaceFirst(slotMatch.group(0)!, ' ');
    }
    if (weekMatch != null) {
      remaining = remaining.replaceFirst(weekMatch.group(0)!, ' ');
    }

    // 清理括号、引导词等
    remaining = remaining
        .replaceAll(RegExp(r'[\[\]\(\)（）【】:：]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final tokens =
        remaining
            .split(' ')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();

    for (final token in tokens) {
      // 教室识别模式：形如 A101、科学楼301、第一教学楼201、3-201
      if (classroom == null &&
          (RegExp(r'[A-Za-z0-9\u4e00-\u9fa5]*(?:楼|室|堂|馆|中心)\d*').hasMatch(token) ||
              RegExp(r'^[A-Za-z]\d{3,4}$').hasMatch(token) ||
              RegExp(r'^\d{1,2}-\d{3,4}$').hasMatch(token))) {
        classroom = token;
        continue;
      }

      // 教师识别模式：2-4 个汉字，且不是通用词汇
      if (teacher == null &&
          RegExp(r'^[\u4e00-\u9fa5]{2,4}$').hasMatch(token) &&
          !token.contains('课程') &&
          !token.contains('地点') &&
          !token.contains('时间') &&
          !token.contains('周次') &&
          !token.contains('单周') &&
          !token.contains('双周') &&
          !token.contains('教学')) {
        // 如果名称尚未设置，优先把第一个未识别文本当作课程名称
        if (name == null) {
          name = token;
        } else {
          teacher = token;
        }
        continue;
      }

      // 课程名称识别：未分配且长度合适的文本
      if (name == null && token.length >= 2) {
        name = token;
      }
    }

    return CourseTextParsedResult(
      name: name,
      classroom: classroom,
      teacher: teacher,
      weekday: weekday,
      startSlot: startSlot,
      endSlot: endSlot,
      startWeek: startWeek,
      endWeek: endWeek,
    );
  }
}
