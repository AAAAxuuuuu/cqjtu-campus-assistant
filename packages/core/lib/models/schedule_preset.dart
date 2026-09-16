import 'schedule_calendar_rules.dart';

/// 学校发布的整段假期安排（停课日 + 调休），按学期打包成一个开关。
///
/// 预设只在本地记一个 [id]，具体日期始终来自这份代码内的定义，因此：
/// * 不会污染用户手动添加的停课日期与调休安排，关掉开关即完全还原；
/// * 学期结束后由 [isExpiredAt] 判定失效，读取时自动清除。
class SchedulePreset {
  const SchedulePreset({
    required this.id,
    required this.name,
    required this.description,
    required this.semesterKey,
    required this.activeUntil,
    this.noClassDates = const [],
    this.makeupOriginalCancelledDates = const [],
    this.adjustments = const [],
  });

  final String id;
  final String name;

  /// 开关副标题，说明这份预设做了什么。
  final String description;

  /// 归属学期（如 `2026-2027-1`），仅用于展示与排查。
  final String semesterKey;

  /// 学期结束日。晚于这一天即视为过期，规则自动销毁。
  final DateTime activeUntil;

  /// 整天停课、且不安排统一补课的日期（如国庆假期本身）。
  final List<String> noClassDates;

  /// 补课日中“原本排的课”停掉的日期。
  ///
  /// 这些日期同时也是某条调休的目标日：当天要上班，但上的是挪来的课，原本按
  /// 星期排的课由任课教师另行安排。与 [noClassDates] 分开是因为语义不同——
  /// 那天并非无课，明细里也不该当作停课日展示。
  final List<String> makeupOriginalCancelledDates;

  /// 调休：把 sourceDate 当天的课挪到 targetDate 上。
  final List<ScheduleDateAdjustment> adjustments;

  /// 供日历规则合并的全部停课日期。
  List<String> get allNoClassDates => [
        ...noClassDates,
        ...makeupOriginalCancelledDates,
      ];

  bool isExpiredAt(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final deadline = DateTime(
      activeUntil.year,
      activeUntil.month,
      activeUntil.day,
    );
    return today.isAfter(deadline);
  }
}

/// 内置预设目录。
abstract final class SchedulePresetCatalog {
  /// 重庆交通大学 2026 年国庆放假调休安排（最新调整）。
  ///
  /// 教务通知：
  /// 9月20日（星期日）、10月10日（星期六）、10月17日（周六）、10月24日（周六）、10月31日（周六）正常上班上课。
  /// 调课安排：
  /// 9月20日（周日）补上10月6日（周二）课程（新生军训不补课）；
  /// 10月10日（周六）补上10月7日（周三）课程；
  /// 10月17日（周六）补上9月28日（周一）课程；
  /// 10月24日（周六）补上9月29日（周二）课程；
  /// 10月31日（周六）补上9月30日（周三）课程。
  /// 原安排在10月10日、17日、24日、31日以及9月20日的课程，由任课教师按教学进度自行补上。
  static final nationalDay2026 = SchedulePreset(
    id: 'cqjtu_national_day_2026',
    name: '2026 国庆放假调休',
    description: '按学校通知停课并调休，学期结束后自动移除',
    semesterKey: '2026-2027-1',
    // 2026-2027 第 1 学期：calculateSemester 在 2027-02 起归入第 2 学期，
    // 因此以 2027-01-31 作为本学期最后一天。
    activeUntil: DateTime(2027, 1, 31),
    // 国庆停课与补休停课，无统一补课。10/3、10/4 为周末，列出仅为与通知一致。
    noClassDates: [
      '2026-10-01',
      '2026-10-02',
      '2026-10-03',
      '2026-10-04',
      '2026-10-05',
    ],
    // 这五天要上班上课，上的是调休挪来的课；原本排在这几天的课由任课教师自行补。
    makeupOriginalCancelledDates: [
      '2026-09-20',
      '2026-10-10',
      '2026-10-17',
      '2026-10-24',
      '2026-10-31',
    ],
    adjustments: [
      ScheduleDateAdjustment(
        sourceDate: DateTime(2026, 10, 6),
        targetDate: DateTime(2026, 9, 20),
      ),
      ScheduleDateAdjustment(
        sourceDate: DateTime(2026, 10, 7),
        targetDate: DateTime(2026, 10, 10),
      ),
      ScheduleDateAdjustment(
        sourceDate: DateTime(2026, 9, 28),
        targetDate: DateTime(2026, 10, 17),
      ),
      ScheduleDateAdjustment(
        sourceDate: DateTime(2026, 9, 29),
        targetDate: DateTime(2026, 10, 24),
      ),
      ScheduleDateAdjustment(
        sourceDate: DateTime(2026, 9, 30),
        targetDate: DateTime(2026, 10, 31),
      ),
    ],
  );

  static final List<SchedulePreset> all = [nationalDay2026];

  static SchedulePreset? byId(String id) {
    for (final preset in all) {
      if (preset.id == id) return preset;
    }
    return null;
  }

  /// 解析已保存的预设 ID，丢弃未知项与已过期项。
  static List<SchedulePreset> resolve(
    Iterable<String> ids, {
    required DateTime now,
  }) {
    final resolved = <SchedulePreset>[];
    for (final id in ids.toSet()) {
      final preset = byId(id);
      if (preset == null || preset.isExpiredAt(now)) continue;
      resolved.add(preset);
    }
    resolved.sort((a, b) => a.id.compareTo(b.id));
    return resolved;
  }
}
