part of '../schedule_page.dart';

const int _kTotalSlots = 13;

/// 每小节高度（px）
const double _kSlotH = 64.0;

/// 每列（每天）宽度
const double _kDayW = 76.0;

/// 时间列宽度
const double _kTimeW = 52.0;

/// 备注行高度
const double _kRemarkH = 52.0;

/// 每小节的时间区间（重庆交通大学作息时间表）
const Map<int, (String, String)> _kSlotTimes = {
  1: ('08:20', '09:00'),
  2: ('09:05', '09:45'),
  3: ('10:00', '10:40'),
  4: ('10:45', '11:25'),
  5: ('11:30', '12:10'),
  6: ('14:00', '14:40'),
  7: ('14:45', '15:25'),
  8: ('15:40', '16:20'),
  9: ('16:25', '17:05'),
  10: ('17:10', '17:50'),
  11: ('19:00', '19:40'),
  12: ('19:45', '20:25'),
  13: ('20:30', '21:10'),
};

const int _kTimetableStartMinutes = 8 * 60 + 20;
const int _kTimetableEndMinutes = 21 * 60 + 10;
const double _kCourseInset = 2.0;

// ── 日期工具 ─────────────────────────────────────────────────
DateTime _startOfWeek(DateTime date, {required bool sundayFirst}) {
  final dayOnly = DateTime(date.year, date.month, date.day);
  final offset = sundayFirst ? date.weekday % 7 : date.weekday - 1;
  return dayOnly.subtract(Duration(days: offset));
}

DateTime _startOfSemesterWeek(
  DateTime semesterStart, {
  required bool sundayFirst,
}) {
  return _startOfWeek(semesterStart, sundayFirst: sundayFirst);
}

DateTime _weekStartOf(
  DateTime semesterStart,
  int week, {
  required bool sundayFirst,
}) {
  return _startOfSemesterWeek(
    semesterStart,
    sundayFirst: sundayFirst,
  ).add(Duration(days: (week - 1) * 7));
}

List<int> _orderedWeekdays({required bool sundayFirst}) {
  return sundayFirst
      ? const [DateTime.sunday, 1, 2, 3, 4, 5, 6]
      : const [1, 2, 3, 4, 5, 6, DateTime.sunday];
}

List<String> _weekdayLabels({required bool sundayFirst}) {
  return sundayFirst
      ? const ['日', '一', '二', '三', '四', '五', '六']
      : const ['一', '二', '三', '四', '五', '六', '日'];
}

int _calcCurrentWeek(
  DateTime s, {
  bool sundayFirst = false,
  int totalWeeks = defaultSemesterTotalWeeks,
}) {
  final now = DateTime.now();
  final semesterMonday = _startOfSemesterWeek(s, sundayFirst: sundayFirst);

  if (now.isBefore(semesterMonday)) return 0;

  final diff = now.difference(semesterMonday).inDays;
  final week = diff ~/ 7 + 1;

  if (week > totalWeeks) return totalWeeks + 1;

  return week;
}

// ── 学期自动推算工具 ─────────────────────────────────────────────
String _calculateSemester(DateTime date) {
  int year = date.year;
  int month = date.month;
  if (month >= 8) {
    return '$year-${year + 1}-1';
  } else if (month == 1) {
    return '${year - 1}-$year-1';
  } else {
    return '${year - 1}-$year-2';
  }
}

String _semesterLabel(String s) {
  final parts = s.split('-');
  if (parts.length != 3) return s;
  return '${parts[0].substring(2)}-${parts[1].substring(2)} 第${parts[2]}学期';
}

String _courseColorKey(Course course) {
  final normalized = course.name.trim().replaceAll(RegExp(r'\s+'), ' ');
  return normalized.isEmpty ? '未命名课程' : normalized;
}

Map<String, Color> _buildCourseColorMap(List<Course> courses) {
  final names = courses.map(_courseColorKey).toSet().toList()..sort();
  final used = <int>{};
  final result = <String, Color>{};

  for (final name in names) {
    final seed = _stableCourseHash(name);
    for (var attempt = 0; attempt < 720; attempt++) {
      final color = _pastelCourseColor(seed, attempt);
      final value = color.toARGB32();
      if (!used.add(value)) continue;
      result[name] = color;
      break;
    }
  }

  return result;
}

Color _pastelCourseColor(int seed, int attempt) {
  final mixed = (seed + attempt * 0x9E3779B9) & 0xFFFFFFFF;
  final hue = ((mixed % 3600) / 10.0 + attempt * 17.0) % 360.0;
  final saturation = 0.30 + ((mixed >> 8) % 9) / 100.0;
  final lightness = 0.82 + ((mixed >> 16) % 6) / 100.0;
  return HSLColor.fromAHSL(1, hue, saturation, lightness).toColor();
}

class _ScheduleGridPalette {
  final bool usesDirectImage;
  final Color header;
  final Color surface;
  final Color timeColumn;
  final Color morning;
  final Color afternoon;
  final Color evening;
  final Color divider;
  final Color timeText;

  const _ScheduleGridPalette({
    required this.usesDirectImage,
    required this.header,
    required this.surface,
    required this.timeColumn,
    required this.morning,
    required this.afternoon,
    required this.evening,
    required this.divider,
    required this.timeText,
  });

  factory _ScheduleGridPalette.forBackground(bool hasCustomImage) {
    if (hasCustomImage) {
      // 课程格保持全透明让图片透出来，但**文字所在的区域必须有衬底**：
      // 时间列和星期表头此前是 Colors.transparent，深紫文字直接压在用户
      // 的背景图上，遇到浅色或高频细节的图就完全看不清。
      // 分隔线同理，AppColors.outline 是为白底调的浅色，压在图上会消失。
      return _ScheduleGridPalette(
        usesDirectImage: true,
        header: Colors.white.withValues(alpha: 0.82),
        surface: Colors.transparent,
        timeColumn: Colors.white.withValues(alpha: 0.78),
        morning: Colors.transparent,
        afternoon: Colors.transparent,
        evening: Colors.transparent,
        divider: AppColors.textPrimary.withValues(alpha: 0.18),
        timeText: AppColors.textPrimary,
      );
    }
    return _ScheduleGridPalette(
      usesDirectImage: false,
      header: AppColors.surface,
      surface: AppColors.surfaceCard,
      timeColumn: AppColors.surfaceCard,
      morning: AppColors.surfaceCard,
      afternoon: AppColors.primary.withValues(alpha: 0.04),
      evening: AppColors.secondary.withValues(alpha: 0.06),
      divider: AppColors.outline,
      timeText: AppColors.textPrimary,
    );
  }
}

int _stableCourseHash(String value) {
  var hash = 0x811C9DC5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}
