part of '../schedule_page.dart';

class _TimetableGrid extends ConsumerStatefulWidget {
  final List<Course> courses;
  final String remark;
  final DateTime semesterStart;
  final int selectedWeek;
  final bool sundayFirst;
  final int totalWeeks;
  final String? selectedSemester;
  final bool showInactiveCourses;
  final ScheduleDensity density;
  final String? backgroundImagePath;

  const _TimetableGrid({
    required this.courses,
    required this.remark,
    required this.semesterStart,
    required this.selectedWeek,
    required this.sundayFirst,
    required this.totalWeeks,
    required this.selectedSemester,
    required this.showInactiveCourses,
    required this.density,
    required this.backgroundImagePath,
  });

  @override
  ConsumerState<_TimetableGrid> createState() => _TimetableGridState();
}

class _TimetableGridState extends ConsumerState<_TimetableGrid> {
  final ScrollController _horizontalController = ScrollController();
  double _headerScrollOffset = 0;

  @override
  void initState() {
    super.initState();
    _horizontalController.addListener(_syncHeaderOffset);
  }

  @override
  void dispose() {
    _horizontalController.removeListener(_syncHeaderOffset);
    _horizontalController.dispose();
    super.dispose();
  }

  void _syncHeaderOffset() {
    if (!mounted) return;
    final next = _horizontalController.hasClients
        ? _horizontalController.offset
        : 0.0;
    if (next == _headerScrollOffset) return;
    setState(() => _headerScrollOffset = next);
  }

  Map<int, List<Course>> _buildDayMap() {
    final map = <int, List<Course>>{};
    for (final c in widget.courses) {
      map.putIfAbsent(c.dayOfWeek, () => []).add(c);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final dayMap = _buildDayMap();
    final courseColorMap = _buildCourseColorMap(widget.courses);
    final isVacation =
        widget.selectedWeek == 0 ||
        widget.selectedWeek == widget.totalWeeks + 1;
    final weekStart = isVacation
        ? _startOfWeek(DateTime.now(), sundayFirst: widget.sundayFirst)
        : _weekStartOf(
            widget.semesterStart,
            widget.selectedWeek,
            sundayFirst: widget.sundayFirst,
          );
    final today = DateTime.now();
    final todayDay = DateTime(today.year, today.month, today.day);
    final gridH = _gridHeight;
    final totalWidth = _kTimeW + _kDayW * 7;
    final dayLabels = _weekdayLabels(sundayFirst: widget.sundayFirst);
    final orderedWeekdays = _orderedWeekdays(sundayFirst: widget.sundayFirst);
    final hasCustomBackground = widget.backgroundImagePath != null;
    final palette = _ScheduleGridPalette.forBackground(hasCustomBackground);

    return Stack(
      fit: StackFit.expand,
      children: [
        if (hasCustomBackground)
          Image.file(
            File(widget.backgroundImagePath!),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        Column(
          children: [
            Container(
              height: 44,
              color: palette.header,
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  minWidth: totalWidth,
                  maxWidth: totalWidth,
                  minHeight: 44,
                  maxHeight: 44,
                  child: Transform.translate(
                    offset: Offset(-_headerScrollOffset, 0),
                    child: SizedBox(
                      width: totalWidth,
                      height: 44,
                      child: Row(
                        children: [
                          SizedBox(width: _kTimeW, height: 44),
                          for (int d = 0; d < 7; d++)
                            _buildDayHeader(
                              context,
                              weekStart.add(Duration(days: d)),
                              dayLabels[d],
                              todayDay,
                              isVacation,
                              palette,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Container(height: 1, color: palette.divider),
            Expanded(
              child: SingleChildScrollView(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final contentWidth = constraints.maxWidth > totalWidth
                        ? constraints.maxWidth
                        : totalWidth;

                    return Stack(
                      children: [
                        SingleChildScrollView(
                          controller: _horizontalController,
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: contentWidth,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  height: gridH,
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(width: _kTimeW),
                                      for (int day = 0; day < 7; day++)
                                        _buildDayColumn(
                                          context,
                                          dayMap[orderedWeekdays[day]] ?? [],
                                          weekStart.add(Duration(days: day)),
                                          courseColorMap,
                                          palette,
                                        ),
                                    ],
                                  ),
                                ),
                                if (widget.remark.isNotEmpty)
                                  Container(
                                    width: contentWidth,
                                    constraints: const BoxConstraints(
                                      minHeight: _kRemarkH,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    // accent 8% 在纯白底上刚够看，压在用户自定义
                                    // 背景图上等于没有底——文字和图标直接叠在
                                    // 图案上。有背景图时换成近实色白底。
                                    decoration: BoxDecoration(
                                      color: hasCustomBackground
                                          ? Colors.white.withValues(alpha: 0.92)
                                          : AppColors.accent.withValues(
                                              alpha: 0.08,
                                            ),
                                      border: Border(
                                        top: BorderSide(
                                          color: hasCustomBackground
                                              ? AppColors.accent.withValues(
                                                  alpha: 0.55,
                                                )
                                              : AppColors.accent.withValues(
                                                  alpha: 0.3,
                                                ),
                                          width: 1,
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        SizedBox(
                                          width: _kTimeW - 12,
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.start,
                                            children: [
                                              const SizedBox(height: 2),
                                              Icon(
                                                Icons.sticky_note_2_outlined,
                                                size: 14,
                                                color: AppColors.accent
                                                    .withValues(alpha: 0.9),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '备注',
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  color: AppColors.accent
                                                      .withValues(alpha: 0.9),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Expanded(
                                          child: Text(
                                            widget.remark,
                                            style: AppType.label.copyWith(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w400,
                                              height: 1.6,
                                              color: AppColors.textPrimary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                SizedBox(
                                  width: contentWidth,
                                  // 含安全区：浮动胶囊会抬到安全区之上，
                                  // 固定常量在带手势条的机型上不够。
                                  // 再加 FAB 一段：本页「新增课程」按钮浮在
                                  // 胶囊之上，不额外让出会压住备注行。
                                  height:
                                      AppInsets.navBarClearanceOf(context) +
                                      AppInsets.fabClearance,
                                ),
                              ],
                            ),
                          ),
                        ),
                        IgnorePointer(
                          // The time column content never changes when the
                          // displayed week changes: give it a paint boundary
                          // so week switches only repaint the course grid.
                          child: RepaintBoundary(
                            child: Container(
                              width: _kTimeW,
                              height: gridH,
                              decoration: BoxDecoration(
                                color: palette.timeColumn,
                                border: Border(
                                  right: BorderSide(color: palette.divider),
                                ),
                              ),
                              child: _buildTimeColumn(gridH, palette),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDayHeader(
    BuildContext context,
    DateTime date,
    String dayLabel,
    DateTime todayDay,
    bool isVacation,
    _ScheduleGridPalette palette,
  ) {
    final isToday = date == todayDay && !isVacation;
    final primaryColor = Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: _kDayW,
      height: 44,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '周$dayLabel',
            maxLines: 1,
            overflow: TextOverflow.clip,
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontSize: 12,
              height: 1.1,
              fontWeight: FontWeight.bold,
              color: isToday ? primaryColor : palette.timeText,
            ),
          ),
          const SizedBox(height: 1),
          SizedBox(
            height: 16,
            child: Center(
              child: isToday
                  ? Container(
                      height: 16,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: primaryColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${date.month}/${date.day}',
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        textScaler: TextScaler.noScaling,
                        style: const TextStyle(
                          fontSize: 11,
                          height: 1,
                          color: Colors.white,
                        ),
                      ),
                    )
                  : Text(
                      '${date.month}/${date.day}',
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1,
                        color: palette.timeText.withValues(alpha: 0.8),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  double get _slotHeight => switch (widget.density) {
    ScheduleDensity.compact => 52,
    ScheduleDensity.standard => _kSlotH,
    ScheduleDensity.spacious => 76,
  };

  double get _densityScale => switch (widget.density) {
    ScheduleDensity.compact => 0.88,
    ScheduleDensity.standard => 1,
    ScheduleDensity.spacious => 1.08,
  };

  double get _gridHeight => _slotBottom(_kTotalSlots);

  double _slotTop(int slot) {
    final normalized = slot.clamp(1, _kTotalSlots);
    return (normalized - 1) * _slotHeight;
  }

  double _slotBottom(int slot) => _slotTop(slot) + _slotHeight;

  double _topForSlot(int slot) => _slotTop(slot);

  double _heightForSlot(int slot) => _slotHeight;

  double _topForCourseMinute(int minutes) =>
      _visualOffsetForMinute(minutes) + _kCourseInset;

  double _bottomForCourseMinute(int minutes) =>
      _visualOffsetForMinute(minutes) - _kCourseInset;

  double _visualOffsetForMinute(int minutes) {
    final clamped = minutes.clamp(
      _kTimetableStartMinutes,
      _kTimetableEndMinutes,
    );

    for (var slot = 1; slot <= _kTotalSlots; slot++) {
      final range = slotMinuteRanges[slot]!;
      if (clamped >= range.start && clamped <= range.end) {
        final span = (range.end - range.start).clamp(1, 1440);
        final fraction = (clamped - range.start) / span;
        return _slotTop(slot) + _slotHeight * fraction;
      }

      if (slot == _kTotalSlots) break;

      final nextRange = slotMinuteRanges[slot + 1]!;
      if (clamped > range.end && clamped < nextRange.start) {
        final gap = (nextRange.start - range.end).clamp(1, 1440);
        final fraction = (clamped - range.end) / gap;
        return _slotBottom(slot) +
            (_slotTop(slot + 1) - _slotBottom(slot)) * fraction;
      }
    }

    return clamped <= _kTimetableStartMinutes
        ? _slotTop(1)
        : _slotBottom(_kTotalSlots);
  }

  Widget _buildTimeColumn(double gridH, _ScheduleGridPalette palette) {
    return SizedBox(
      width: _kTimeW,
      height: gridH,
      child: Stack(
        children: [
          ..._sectionBg(palette),
          for (int s = 1; s <= _kTotalSlots; s++)
            Positioned(
              top: _topForSlot(s),
              left: 0,
              right: 0,
              height: _heightForSlot(s),
              child: _SlotCell(slot: s, textColor: palette.timeText),
            ),
          _hDivider(_slotBottom(5), palette.divider),
          _hDivider(_slotBottom(10), palette.divider),
        ],
      ),
    );
  }

  /// 根据精确分钟数（从午夜 00:00 起算）计算在课表网格中的像素 top 位置
  double _exactTopForMinutes(int minutes) {
    for (final entry in slotMinuteRanges.entries) {
      final start = entry.value.start;
      final end = entry.value.end;
      if (minutes >= start && minutes <= end) {
        return _topForCourseMinute(minutes);
      }
    }
    // 超出时间范围，回退到最近邻节次
    return _topForCourseMinute(minutes);
  }

  /// 构建单个课程定位块（支持考试课程的精确时间定位）
  Widget _buildCoursePositioned(
    _CoursePlacement placement,
    BuildContext context,
    Map<String, Color> courseColorMap,
  ) {
    final course = placement.course;
    double top;
    double height;

    if (course.isExam &&
        course.exactStartMinutes != null &&
        course.exactEndMinutes != null) {
      // 考试课程：根据精确分钟数计算位置和高度
      top = _exactTopForMinutes(course.exactStartMinutes!);
      final bottom = _bottomForCourseMinute(course.exactEndMinutes!);
      height = bottom - top;
    } else {
      // 普通课程：按固定节次计算
      top = _topForSlot(placement.startSlot) + _kCourseInset;
      final bottom = _slotBottom(placement.endSlot) - _kCourseInset;
      height = bottom - top;
    }
    height = height.clamp(18.0, double.infinity);

    return Positioned(
      key: ValueKey(placement.key),
      top: top,
      left: placement.left,
      width: placement.width,
      height: height,
      child: placement.isSummary
          ? _InactiveCourseSummaryCell(courses: placement.courses)
          : CourseCell(
              course: course,
              isActive: course.isActiveInWeek(widget.selectedWeek),
              color: courseColorMap[_courseColorKey(course)],
              onDelete: course.isCustom
                  ? () => _deleteCustomCourse(context, course)
                  : null,
              densityScale: _densityScale,
            ),
    );
  }

  Widget _buildDayColumn(
    BuildContext context,
    List<Course> dayCourses,
    DateTime courseDate,
    Map<String, Color> courseColorMap,
    _ScheduleGridPalette palette,
  ) {
    final gridH = _gridHeight;
    final placements = _buildCoursePlacements(dayCourses);
    return Container(
      width: _kDayW,
      height: gridH,
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(right: BorderSide(color: palette.divider)),
      ),
      child: Stack(
        children: [
          ..._sectionBg(palette),
          for (int s = 1; s <= _kTotalSlots; s++)
            _hDivider(
              _slotBottom(s),
              palette.usesDirectImage
                  ? palette.divider
                  : palette.divider.withValues(alpha: 0.6),
            ),
          _hDivider(_slotBottom(5), palette.divider, thickness: 1.0),
          _hDivider(_slotBottom(10), palette.divider, thickness: 1.0),
          for (final placement in placements)
            _buildCoursePositioned(placement, context, courseColorMap),
        ],
      ),
    );
  }

  List<_CoursePlacement> _buildCoursePlacements(List<Course> dayCourses) {
    final activeCourses = dayCourses
        .where((course) => course.isActiveInWeek(widget.selectedWeek))
        .toList();
    final inactiveCourses = widget.showInactiveCourses
        ? (dayCourses
              .where(
                (course) =>
                    !course.isActiveInWeek(widget.selectedWeek) &&
                    !activeCourses.any(
                      (active) => _coursesOverlap(course, active),
                    ),
              )
              .toList()
            ..sort(_compareCoursesForLayout))
        : <Course>[];

    const outerPadding = 2.0;
    final fullWidth = _kDayW - outerPadding * 2;
    final inactivePlacements = <_CoursePlacement>[];
    var index = 0;

    while (index < inactiveCourses.length) {
      final cluster = <Course>[];
      var clusterEndSlot = inactiveCourses[index].endTimeSlot;

      while (index < inactiveCourses.length) {
        final course = inactiveCourses[index];
        if (cluster.isNotEmpty && course.timeSlot > clusterEndSlot) break;
        cluster.add(course);
        if (course.endTimeSlot > clusterEndSlot) {
          clusterEndSlot = course.endTimeSlot;
        }
        index++;
      }

      inactivePlacements.add(
        _CoursePlacement(
          courses: cluster,
          left: outerPadding,
          width: fullWidth,
        ),
      );
    }

    final activePlacements =
        activeCourses
            .toList()
            .map(
              (course) => _CoursePlacement(
                courses: [course],
                left: outerPadding,
                width: fullWidth,
              ),
            )
            .toList()
          ..sort((a, b) => _compareCoursesForLayout(a.course, b.course));

    return [...inactivePlacements, ...activePlacements];
  }

  int _compareCoursesForLayout(Course a, Course b) {
    final rangeA = _courseMinuteRange(a);
    final rangeB = _courseMinuteRange(b);
    final startCompare = rangeA.start.compareTo(rangeB.start);
    if (startCompare != 0) return startCompare;

    final endCompare = rangeA.end.compareTo(rangeB.end);
    if (endCompare != 0) return endCompare;

    final activeCompare = (a.isActiveInWeek(widget.selectedWeek) ? 0 : 1)
        .compareTo(b.isActiveInWeek(widget.selectedWeek) ? 0 : 1);
    if (activeCompare != 0) return activeCompare;

    if (a.isExam != b.isExam) return a.isExam ? 1 : -1;
    return a.name.compareTo(b.name);
  }

  bool _coursesOverlap(Course a, Course b) {
    final rangeA = _courseMinuteRange(a);
    final rangeB = _courseMinuteRange(b);
    return rangeA.start < rangeB.end && rangeB.start < rangeA.end;
  }

  ({int start, int end}) _courseMinuteRange(Course course) {
    if (course.exactStartMinutes != null &&
        course.exactEndMinutes != null &&
        course.exactEndMinutes! > course.exactStartMinutes!) {
      return (start: course.exactStartMinutes!, end: course.exactEndMinutes!);
    }

    return (
      start: slotMinuteRanges[course.timeSlot]!.start,
      end: slotMinuteRanges[course.endTimeSlot]!.end,
    );
  }

  Future<void> _deleteCustomCourse(BuildContext context, Course course) async {
    await ref
        .read(customCoursesProvider(widget.selectedSemester).notifier)
        .removeCourse(course);
    if (!context.mounted) return;
    AppSnackBar.success(context, '已删除「${course.name}」');
  }

  List<Widget> _sectionBg(_ScheduleGridPalette palette) => [
    Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: _slotBottom(5),
      child: Container(color: palette.morning),
    ),
    Positioned(
      top: _topForSlot(6),
      left: 0,
      right: 0,
      height: _slotBottom(10) - _topForSlot(6),
      child: Container(color: palette.afternoon),
    ),
    Positioned(
      top: _topForSlot(11),
      left: 0,
      right: 0,
      height: _slotBottom(13) - _topForSlot(11),
      child: Container(color: palette.evening),
    ),
  ];

  Widget _hDivider(double top, Color color, {double thickness = 0.5}) =>
      Positioned(
        top: top,
        left: 0,
        right: 0,
        child: Container(height: thickness, color: color),
      );
}

class _CoursePlacement {
  final List<Course> courses;
  final double left;
  final double width;

  const _CoursePlacement({
    required this.courses,
    required this.left,
    required this.width,
  });

  Course get course => courses.first;

  bool get isSummary => courses.length > 1;

  int get startSlot => courses
      .map((course) => course.timeSlot)
      .reduce((value, element) => value < element ? value : element);

  int get endSlot => courses
      .map((course) => course.endTimeSlot)
      .reduce((value, element) => value > element ? value : element);

  int get slotSpan => endSlot - startSlot + 1;

  String get key => isSummary
      ? 'inactive_summary_${courses.map((course) => '${course.name}_${course.timeStr}').join('|')}'
      : '${course.name}_${course.timeStr}';
}

class _InactiveCourseSummaryCell extends StatelessWidget {
  final List<Course> courses;

  const _InactiveCourseSummaryCell({required this.courses});

  @override
  Widget build(BuildContext context) {
    final title = courses.length == 1
        ? courses.first.name
        : '本周无课 · ${courses.length} 门';
    final subtitle = courses.length == 1
        ? courses.first.classroom
        : courses.take(2).map((course) => course.name).join('、');

    return GestureDetector(
      onTap: () => _showDetails(context),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.tintSoft,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.outline, width: 0.6),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMuted,
                  height: 1.15,
                ),
              ),
              const Spacer(),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9.5,
                  color: AppColors.textMuted.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetails(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 34),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.layers_outlined, color: AppColors.textMuted),
                SizedBox(width: 10),
                Text(
                  '本周无课的重叠课程',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 14),
            for (final course in courses)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${course.timeSlot}-${course.endTimeSlot}',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            course.name,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (course.classroom.trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                course.classroom,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SlotCell extends StatelessWidget {
  final int slot;
  final Color textColor;
  const _SlotCell({required this.slot, required this.textColor});

  @override
  Widget build(BuildContext context) {
    final times = _kSlotTimes[slot];
    return Container(
      alignment: Alignment.center,
      color: Colors.transparent,
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$slot',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          if (times != null) ...[
            Text(
              times.$1,
              style: TextStyle(
                fontSize: 9,
                color: textColor.withValues(alpha: 0.76),
              ),
            ),
            Text(
              times.$2,
              style: TextStyle(
                fontSize: 9,
                color: textColor.withValues(alpha: 0.76),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
