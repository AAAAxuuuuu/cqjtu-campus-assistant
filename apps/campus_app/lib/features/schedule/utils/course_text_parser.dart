import 'package:flutter/foundation.dart';

/// Holds parsed course attributes extracted from free text or schedule strings.
@immutable
class ParsedCourseData {
  final String? name;
  final String? classroom;
  final String? teacher;
  final int? weekday; // 1 (Monday) .. 7 (Sunday)
  final int? startSlot; // 1 .. 13
  final int? endSlot; // 1 .. 13
  final int? startWeek;
  final int? endWeek;

  const ParsedCourseData({
    this.name,
    this.classroom,
    this.teacher,
    this.weekday,
    this.startSlot,
    this.endSlot,
    this.startWeek,
    this.endWeek,
  });

  bool get hasAnyField =>
      (name != null && name!.isNotEmpty) ||
      (classroom != null && classroom!.isNotEmpty) ||
      (teacher != null && teacher!.isNotEmpty) ||
      weekday != null ||
      startSlot != null ||
      endSlot != null ||
      startWeek != null ||
      endWeek != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ParsedCourseData &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          classroom == other.classroom &&
          teacher == other.teacher &&
          weekday == other.weekday &&
          startSlot == other.startSlot &&
          endSlot == other.endSlot &&
          startWeek == other.startWeek &&
          endWeek == other.endWeek;

  @override
  int get hashCode => Object.hash(
    name,
    classroom,
    teacher,
    weekday,
    startSlot,
    endSlot,
    startWeek,
    endWeek,
  );

  @override
  String toString() {
    return 'ParsedCourseData(name: $name, classroom: $classroom, teacher: $teacher, '
        'weekday: $weekday, startSlot: $startSlot, endSlot: $endSlot, '
        'startWeek: $startWeek, endWeek: $endWeek)';
  }
}

/// Robust regex & key-value parser for extracting custom course details from text.
class CourseTextParser {
  CourseTextParser._();

  /// Parses raw text (single-line or multi-line) into a [ParsedCourseData].
  static ParsedCourseData parse(String rawText) {
    final trimmedText = rawText.trim();
    if (trimmedText.isEmpty) {
      return const ParsedCourseData();
    }

    // Standardize colons and whitespace, tildes, dashes
    final text = trimmedText
        .replaceAll('：', ':')
        .replaceAll('～', '~')
        .replaceAll('—', '-')
        .replaceAll('–', '-');

    String? explicitName;
    String? explicitClassroom;
    String? explicitTeacher;

    // 1. Check explicit key-value tags
    final nameTagMatch = RegExp(
      r'(?:课程|课程名称|课名|科目)[:：]\s*([^\s\n,，;；]+)',
      caseSensitive: false,
    ).firstMatch(text);
    if (nameTagMatch != null) {
      explicitName = nameTagMatch.group(1)?.trim();
    }

    final classroomTagMatch = RegExp(
      r'(?:地点|教室|上课地点|场地|机房|实验室)[:：]\s*([^\s\n,，;；]+)',
      caseSensitive: false,
    ).firstMatch(text);
    if (classroomTagMatch != null) {
      explicitClassroom = classroomTagMatch.group(1)?.trim();
    }

    final teacherTagMatch = RegExp(
      r'(?:教师|老师|主讲|授课教师|讲师)[:：]\s*([^\s\n,，;；]+)',
      caseSensitive: false,
    ).firstMatch(text);
    if (teacherTagMatch != null) {
      explicitTeacher = teacherTagMatch.group(1)?.trim();
    }

    // 2. Weekday extraction
    int? weekday;
    String? matchedWeekdayStr;
    final weekdayMatch = RegExp(
      r'(?:周|星期|礼拜)\s*([一二三四五六日天1-7])',
      caseSensitive: false,
    ).firstMatch(text);

    if (weekdayMatch != null) {
      matchedWeekdayStr = weekdayMatch.group(0);
      final rawDay = weekdayMatch.group(1);
      weekday = _parseWeekdayChar(rawDay);
    }

    // 3. Time slot extraction (startSlot, endSlot: 1..13)
    int? startSlot;
    int? endSlot;
    String? matchedSlotStr;

    // Slot Pattern A: Range with 节 (e.g. 1-2节, 第3-4节, 1~2节)
    final slotRangeMatch = RegExp(
      r'(?:第\s*)?(\d{1,2})\s*(?:-|~|—|–|至|到)\s*(\d{1,2})\s*(?:节|小节)',
      caseSensitive: false,
    ).firstMatch(text);

    // Slot Pattern B: Comma or plus separated with 节 (e.g. 3,4节, 1+2节)
    final slotCommaMatch = RegExp(
      r'(?:第\s*)?(\d{1,2})\s*(?:,|\+|、)\s*(\d{1,2})\s*(?:节|小节)',
      caseSensitive: false,
    ).firstMatch(text);

    // Slot Pattern C: Single slot with 节 (e.g. 第3节, 2节)
    final slotSingleMatch = RegExp(
      r'(?:第\s*)?(\d{1,2})\s*(?:节|小节)',
      caseSensitive: false,
    ).firstMatch(text);

    // Slot Pattern D: Range right after weekday without 节 (e.g. 周一 1-2)
    final slotAfterWeekdayMatch = RegExp(
      r'(?:周|星期|礼拜)[一二三四五六日天1-7]\s*(?:第\s*)?(\d{1,2})\s*(?:-|~|—|–|至|到)\s*(\d{1,2})',
      caseSensitive: false,
    ).firstMatch(text);

    if (slotRangeMatch != null) {
      matchedSlotStr = slotRangeMatch.group(0);
      startSlot = int.tryParse(slotRangeMatch.group(1) ?? '');
      endSlot = int.tryParse(slotRangeMatch.group(2) ?? '');
    } else if (slotCommaMatch != null) {
      matchedSlotStr = slotCommaMatch.group(0);
      startSlot = int.tryParse(slotCommaMatch.group(1) ?? '');
      endSlot = int.tryParse(slotCommaMatch.group(2) ?? '');
    } else if (slotSingleMatch != null) {
      matchedSlotStr = slotSingleMatch.group(0);
      startSlot = int.tryParse(slotSingleMatch.group(1) ?? '');
      endSlot = startSlot;
    } else if (slotAfterWeekdayMatch != null) {
      matchedSlotStr =
          '${slotAfterWeekdayMatch.group(1)}-${slotAfterWeekdayMatch.group(2)}';
      startSlot = int.tryParse(slotAfterWeekdayMatch.group(1) ?? '');
      endSlot = int.tryParse(slotAfterWeekdayMatch.group(2) ?? '');
    }

    if (startSlot != null) {
      startSlot = startSlot.clamp(1, 13);
    }
    if (endSlot != null) {
      endSlot = endSlot.clamp(1, 13);
      if (startSlot != null && endSlot < startSlot) {
        endSlot = startSlot;
      }
    }

    // 4. Week range extraction (startWeek, endWeek)
    int? startWeek;
    int? endWeek;
    String? matchedWeekStr;

    // Week Pattern A: Range with 周 (e.g. 1-16周, 第1-16周, 3-15周(单), 1-16周(双))
    final weekRangeMatch = RegExp(
      r'(?:第\s*)?(\d{1,2})\s*(?:-|~|—|–|至|到)\s*(\d{1,2})\s*(?:[\(（]?[单双]周?[\)）]?)?\s*周',
      caseSensitive: false,
    ).firstMatch(text);

    // Week Pattern B: Tagged week range without 周 suffix (e.g. 周次: 1-16)
    final weekTaggedMatch = RegExp(
      r'(?:周次|周数)[:：]\s*(?:第\s*)?(\d{1,2})\s*(?:-|~|—|–|至|到)\s*(\d{1,2})',
      caseSensitive: false,
    ).firstMatch(text);

    // Week Pattern C: Single week (e.g. 第16周, 8周)
    final weekSingleMatch = RegExp(
      r'(?:第\s*)?(\d{1,2})\s*周',
      caseSensitive: false,
    ).firstMatch(text);

    if (weekRangeMatch != null) {
      matchedWeekStr = weekRangeMatch.group(0);
      startWeek = int.tryParse(weekRangeMatch.group(1) ?? '');
      endWeek = int.tryParse(weekRangeMatch.group(2) ?? '');
    } else if (weekTaggedMatch != null) {
      matchedWeekStr = weekTaggedMatch.group(0);
      startWeek = int.tryParse(weekTaggedMatch.group(1) ?? '');
      endWeek = int.tryParse(weekTaggedMatch.group(2) ?? '');
    } else if (weekSingleMatch != null) {
      matchedWeekStr = weekSingleMatch.group(0);
      startWeek = int.tryParse(weekSingleMatch.group(1) ?? '');
      endWeek = startWeek;
    }

    if (startWeek != null && startWeek < 1) startWeek = 1;
    if (endWeek != null) {
      if (startWeek != null && endWeek < startWeek) {
        endWeek = startWeek;
      }
    }

    // 5. Teacher extraction
    String? teacher = explicitTeacher;
    String? matchedTeacherStr;

    if (teacher == null) {
      // Suffix pattern: e.g. 张三老师, 李四教授, 王五副教授, 赵六讲师
      final teacherSuffixMatch = RegExp(
        r'([\u4e00-\u9fa5]{2,4})(?:老师|教授|副教授|讲师)',
      ).firstMatch(text);
      if (teacherSuffixMatch != null) {
        teacher = teacherSuffixMatch.group(1);
        matchedTeacherStr = teacherSuffixMatch.group(0);
      }
    } else {
      matchedTeacherStr = teacherTagMatch?.group(0);
    }

    // 6. Classroom extraction
    String? classroom = explicitClassroom;
    String? matchedClassroomStr;

    if (classroom == null) {
      // Building + Room patterns: A101, 301教室, 教学楼B202, 实验室504, 基教楼102, 二教201
      final classroomMatch = RegExp(
        r'(?:(?:[A-Za-z0-9\u4e00-\u9fa5]{0,8}(?:教学楼|基教楼|实验楼|科技楼|学院楼|三教|二教|一教|四教|楼|栋|区|馆|实验室))[\s-]*)?[A-Za-z]?\d{3,4}[A-Za-z]?(?:教室|室)?',
      ).firstMatch(text);

      if (classroomMatch != null &&
          classroomMatch.group(0)!.trim().isNotEmpty) {
        final matchStr = classroomMatch.group(0)!.trim();
        // Ignore matches that are purely numbers or collide with slot/week numbers unless classroom-specific
        if (!_isPureNumberOrSlotWeek(matchStr)) {
          classroom = matchStr;
          matchedClassroomStr = matchStr;
        }
      }
    } else {
      matchedClassroomStr = classroomTagMatch?.group(0);
    }

    // 7. Course Name extraction
    String? name = explicitName;

    if (name == null) {
      // Token stripping strategy for un-tagged / space-delimited text
      var cleanText = text;

      // Remove explicit tag labels
      cleanText = cleanText.replaceAll(
        RegExp(
          r'(?:课程|课程名称|课名|科目|地点|教室|上课地点|场地|机房|实验室|教师|老师|主讲|授课教师|讲师|时间|上课时间|周次|周数)[:：]',
        ),
        ' ',
      );

      // Remove recognized component strings
      if (matchedWeekdayStr != null) {
        cleanText = cleanText.replaceAll(matchedWeekdayStr, ' ');
      }
      if (matchedSlotStr != null) {
        cleanText = cleanText.replaceAll(matchedSlotStr, ' ');
      }
      if (matchedWeekStr != null) {
        cleanText = cleanText.replaceAll(matchedWeekStr, ' ');
      }
      if (matchedClassroomStr != null) {
        cleanText = cleanText.replaceAll(matchedClassroomStr, ' ');
      }
      if (matchedTeacherStr != null) {
        cleanText = cleanText.replaceAll(matchedTeacherStr, ' ');
      }

      // Split into non-empty tokens
      final tokens = cleanText
          .split(RegExp(r'[\s,，;；\n\r]+'))
          .where((t) => t.trim().isNotEmpty)
          .toList();

      if (tokens.isNotEmpty) {
        // If teacher was not found via suffix or tag, check if remaining tokens contain an untagged teacher (e.g. "高等数学 ... 王五")
        if (teacher == null && tokens.length >= 2) {
          final lastToken = tokens.last.trim();
          if (RegExp(r'^[\u4e00-\u9fa5]{2,4}$').hasMatch(lastToken)) {
            teacher = lastToken;
            tokens.removeLast();
          }
        }

        if (tokens.isNotEmpty) {
          name = tokens.first.trim();
        }
      }
    }

    return ParsedCourseData(
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

  static int? _parseWeekdayChar(String? char) {
    if (char == null) return null;
    switch (char) {
      case '一':
      case '1':
        return 1;
      case '二':
      case '2':
        return 2;
      case '三':
      case '3':
        return 3;
      case '四':
      case '4':
        return 4;
      case '五':
      case '5':
        return 5;
      case '六':
      case '6':
        return 6;
      case '日':
      case '天':
      case '7':
        return 7;
      default:
        return null;
    }
  }

  static bool _isPureNumberOrSlotWeek(String str) {
    if (RegExp(r'^\d+$').hasMatch(str)) return true;
    if (RegExp(r'^\d+-\d+$').hasMatch(str)) return true;
    return false;
  }
}
