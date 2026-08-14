part of '../schedule_page.dart';

Future<void> _showScheduleMoreSheet(
  BuildContext context,
  WidgetRef ref, {
  required List<Course> courses,
  required DateTime semesterStart,
  required bool sundayFirst,
  required int totalWeeks,
  required String semesterLabel,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _ScheduleMoreSheet(
    pageContext: context,
    courses: courses,
    semesterStart: semesterStart,
    sundayFirst: sundayFirst,
    totalWeeks: totalWeeks,
    semesterLabel: semesterLabel,
  ),
);

class _ScheduleMoreSheet extends ConsumerWidget {
  final BuildContext pageContext;
  final List<Course> courses;
  final DateTime semesterStart;
  final bool sundayFirst;
  final int totalWeeks;
  final String semesterLabel;

  const _ScheduleMoreSheet({
    required this.pageContext,
    required this.courses,
    required this.semesterStart,
    required this.sundayFirst,
    required this.totalWeeks,
    required this.semesterLabel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final density =
        ref.watch(scheduleDensityProvider).valueOrNull ??
        ScheduleDensity.standard;
    final backgroundImagePath = ref
        .watch(scheduleBackgroundImageProvider)
        .valueOrNull;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.86,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            const Text(
              '课程表工具',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            _sheetSectionLabel('下载'),
            _SheetActionTile(
              icon: Icons.picture_as_pdf_outlined,
              title: '全学期周课表 PDF',
              subtitle: '按周分页导出第 1-$totalWeeks 周的课程网格',
              onTap: () =>
                  _export(context, ref, _ScheduleExportType.allWeeksPdf),
            ),
            _SheetActionTile(
              icon: Icons.format_list_bulleted_outlined,
              title: '课程清单 PDF',
              subtitle: '按星期和节次整理整个学期课程',
              onTap: () => _export(context, ref, _ScheduleExportType.listPdf),
            ),
            _SheetActionTile(
              icon: Icons.calendar_month_outlined,
              title: '日历 ICS',
              subtitle: '导入系统日历或第三方日历',
              onTap: () => _export(context, ref, _ScheduleExportType.ics),
            ),
            const Divider(height: 32),
            _sheetSectionLabel('显示'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.edit_calendar_outlined),
              title: const Text('学期开学日期'),
              subtitle: Text(semesterLabel),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(context);
                _pickSemesterStart(pageContext, ref);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_repeat_outlined),
              title: const Text('节假日与调休'),
              subtitle: const Text('节假日停课，调休日由你按学校安排手动添加'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                Navigator.pop(context);
                await _showScheduleCalendarRulesSheet(
                  pageContext,
                  semesterStart: semesterStart,
                );
              },
            ),
            const SizedBox(height: 8),
            const Text('课表密度', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SegmentedButton<ScheduleDensity>(
              segments: const [
                ButtonSegment(
                  value: ScheduleDensity.compact,
                  label: Text('紧凑'),
                ),
                ButtonSegment(
                  value: ScheduleDensity.standard,
                  label: Text('标准'),
                ),
                ButtonSegment(
                  value: ScheduleDensity.spacious,
                  label: Text('宽松'),
                ),
              ],
              selected: {density},
              showSelectedIcon: false,
              onSelectionChanged: (selection) => ref
                  .read(scheduleDensityProvider.notifier)
                  .setDensity(selection.first),
            ),
            const SizedBox(height: 18),
            const Text('课表背景', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: _BackgroundThumbnail(path: backgroundImagePath),
              title: const Text('从相册选择'),
              subtitle: Text(
                backgroundImagePath == null ? '未设置自定义背景' : '正在使用自定义背景',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _chooseBackground(context, ref),
            ),
            if (backgroundImagePath != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () async {
                    await ref
                        .read(scheduleBackgroundImageProvider.notifier)
                        .clearImage();
                  },
                  icon: const Icon(Icons.layers_clear_outlined, size: 18),
                  label: const Text('移除背景'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _chooseBackground(BuildContext context, WidgetRef ref) async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2000,
      imageQuality: 90,
    );
    if (image == null) return;

    try {
      await ref
          .read(scheduleBackgroundImageProvider.notifier)
          .setImage(image.path);
      if (context.mounted) {
        AppSnackBar.success(context, '已应用自定义课表背景');
      }
    } catch (error) {
      if (context.mounted) {
        AppSnackBar.error(context, '设置背景失败：$error');
      }
    }
  }

  Future<void> _export(
    BuildContext sheetContext,
    WidgetRef ref,
    _ScheduleExportType type,
  ) async {
    Navigator.pop(sheetContext);
    AppSnackBar.status(pageContext, '正在生成导出文件...');
    try {
      final calendarRules = await ref.read(
        scheduleCalendarRulesProvider.future,
      );
      switch (type) {
        case _ScheduleExportType.allWeeksPdf:
          await ScheduleExportService.shareAllWeeksPdf(
            courses: courses,
            semesterStart: semesterStart,
            totalWeeks: totalWeeks,
            sundayFirst: sundayFirst,
            semesterLabel: semesterLabel,
            calendarRules: calendarRules,
          );
        case _ScheduleExportType.listPdf:
          await ScheduleExportService.shareCourseListPdf(
            courses: courses,
            semesterStart: semesterStart,
            totalWeeks: totalWeeks,
            semesterLabel: semesterLabel,
            calendarRules: calendarRules,
          );
        case _ScheduleExportType.ics:
          await ScheduleExportService.shareIcs(
            courses: courses,
            semesterStart: semesterStart,
            totalWeeks: totalWeeks,
            sundayFirst: sundayFirst,
            semesterLabel: semesterLabel,
            calendarRules: calendarRules,
          );
      }
    } catch (error) {
      if (pageContext.mounted) {
        AppSnackBar.error(pageContext, '导出失败：$error');
      }
    }
  }
}

enum _ScheduleExportType { allWeeksPdf, listPdf, ics }

List<Course> _coursesForDisplayedWeek({
  required List<Course> courses,
  required DateTime semesterStart,
  required int selectedWeek,
  required int totalWeeks,
  required ScheduleCalendarRules calendarRules,
  required bool includeInactiveCourses,
}) {
  if (selectedWeek < 1 || selectedWeek > totalWeeks) return const [];

  final activeOccurrences = calendarRules
      .resolveOccurrences(
        courses: courses,
        semesterStart: semesterStart,
        totalWeeks: totalWeeks,
      )
      .where(
        (occurrence) =>
            calendarRules.weekOf(occurrence.scheduledDate, semesterStart) ==
            selectedWeek,
      )
      .toList();
  final activeCourses = activeOccurrences
      .map((occurrence) => occurrence.asCourseForWeek(selectedWeek))
      .toList();
  if (!includeInactiveCourses) return activeCourses;

  final coursesMovedIntoThisWeek = activeOccurrences
      .map((occurrence) => occurrence.course)
      .toSet();
  final inactiveCourses = courses
      .where(
        (course) =>
            !course.isActiveInWeek(selectedWeek) &&
            !coursesMovedIntoThisWeek.contains(course),
      )
      .map((course) => course.copyWith(weekList: const []))
      .toList();
  return [...inactiveCourses, ...activeCourses];
}

Future<void> _showScheduleCalendarRulesSheet(
  BuildContext context, {
  required DateTime semesterStart,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _ScheduleCalendarRulesSheet(semesterStart: semesterStart),
);

class _ScheduleCalendarRulesSheet extends ConsumerWidget {
  const _ScheduleCalendarRulesSheet({required this.semesterStart});

  final DateTime semesterStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rulesAsync = ref.watch(scheduleCalendarRulesProvider);
    final rules = rulesAsync.valueOrNull ?? ScheduleCalendarRules.empty;
    final isLoading = rulesAsync.isLoading;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.86,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            const Text(
              '节假日与调休',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.beach_access_outlined),
              title: const Text('避开 2026 法定节假日'),
              subtitle: const Text('节假日课程不显示，也不会生成上课提醒'),
              value: rules.skipOfficialHolidays,
              onChanged: isLoading
                  ? null
                  : (value) => ref
                        .read(scheduleCalendarRulesProvider.notifier)
                        .setSkipOfficialHolidays(value),
            ),
            const Divider(height: 32),
            _sheetSectionLabel('额外停课日期'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_busy_outlined),
              title: const Text('添加停课日期'),
              trailing: const Icon(Icons.add),
              enabled: !isLoading,
              onTap: isLoading ? null : () => _addNoClassDate(context, ref),
            ),
            if (rules.additionalNoClassDates.isEmpty)
              const ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('暂无额外停课日期'),
              )
            else
              ...rules.additionalNoClassDates.map(
                (date) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_scheduleDateLabel(date)),
                  trailing: IconButton(
                    tooltip: '移除停课日期',
                    icon: const Icon(Icons.close),
                    onPressed: () => ref
                        .read(scheduleCalendarRulesProvider.notifier)
                        .removeNoClassDate(date),
                  ),
                ),
              ),
            const Divider(height: 32),
            _sheetSectionLabel('手动调休'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.swap_horiz_outlined),
              title: const Text('添加调休安排'),
              subtitle: const Text('选择原上课日期，再选择实际补课日期'),
              trailing: const Icon(Icons.add),
              enabled: !isLoading,
              onTap: isLoading ? null : () => _addAdjustment(context, ref),
            ),
            if (rules.adjustments.isEmpty)
              const ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('暂无手动调休安排'),
              )
            else
              ...rules.adjustments.map(
                (adjustment) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_repeat_outlined),
                  title: Text(
                    '${_scheduleDateLabel(adjustment.sourceKey)} 的课程',
                  ),
                  subtitle: Text(
                    '改至 ${_scheduleDateLabel(adjustment.targetKey)} 上课',
                  ),
                  trailing: IconButton(
                    tooltip: '移除调休安排',
                    icon: const Icon(Icons.close),
                    onPressed: () => ref
                        .read(scheduleCalendarRulesProvider.notifier)
                        .removeAdjustment(adjustment.sourceKey),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _addNoClassDate(BuildContext context, WidgetRef ref) async {
    final date = await _pickScheduleRuleDate(context, semesterStart);
    if (date == null) return;
    await ref.read(scheduleCalendarRulesProvider.notifier).addNoClassDate(date);
  }

  Future<void> _addAdjustment(BuildContext context, WidgetRef ref) async {
    final sourceDate = await _pickScheduleRuleDate(context, semesterStart);
    if (sourceDate == null || !context.mounted) return;
    final targetDate = await _pickScheduleRuleDate(
      context,
      semesterStart,
      initialDate: sourceDate.add(const Duration(days: 1)),
    );
    if (targetDate == null || !context.mounted) return;
    if (scheduleDateKey(sourceDate) == scheduleDateKey(targetDate)) {
      AppSnackBar.warning(context, '原上课日期和补课日期不能相同');
      return;
    }
    await ref
        .read(scheduleCalendarRulesProvider.notifier)
        .saveAdjustment(
          ScheduleDateAdjustment(
            sourceDate: sourceDate,
            targetDate: targetDate,
          ),
        );
  }
}

Future<DateTime?> _pickScheduleRuleDate(
  BuildContext context,
  DateTime semesterStart, {
  DateTime? initialDate,
}) {
  final firstDate = DateTime(semesterStart.year - 1, 1, 1);
  final lastDate = DateTime(semesterStart.year + 2, 12, 31);
  final candidate = initialDate ?? DateTime.now();
  final safeInitialDate = candidate.isBefore(firstDate)
      ? firstDate
      : candidate.isAfter(lastDate)
      ? lastDate
      : candidate;
  return showDatePicker(
    context: context,
    firstDate: firstDate,
    lastDate: lastDate,
    initialDate: safeInitialDate,
  );
}

String _scheduleDateLabel(String value) {
  final date = DateTime.tryParse(value);
  if (date == null) return value;
  return '${date.year}年${date.month}月${date.day}日';
}

class _BackgroundThumbnail extends StatelessWidget {
  final String? path;

  const _BackgroundThumbnail({required this.path});

  @override
  Widget build(BuildContext context) {
    if (path == null) {
      return const SizedBox(
        width: 44,
        height: 44,
        child: Icon(Icons.wallpaper_outlined),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.file(
        File(path!),
        width: 44,
        height: 44,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const SizedBox(
          width: 44,
          height: 44,
          child: Icon(Icons.broken_image_outlined),
        ),
      ),
    );
  }
}

class _SheetActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SheetActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}

Widget _sheetSectionLabel(String value) => Padding(
  padding: const EdgeInsets.only(bottom: 4),
  child: Text(
    value,
    style: const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: AppColors.textMuted,
    ),
  ),
);

Future<void> _pickSemesterStart(BuildContext context, WidgetRef ref) async {
  final now = DateTime.now();
  final initial = ref.read(activeSemesterStartProvider).valueOrNull ?? now;

  final picked = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(now.year - 2),
    lastDate: DateTime(now.year + 2),
    helpText: '选择开学第一天',
  );

  if (picked == null) return;

  final semesterStr = _calculateSemester(picked);
  final forKeyNotifier = ref.read(
    semesterStartForKeyProvider(semesterStr).notifier,
  );
  final semesterStartNotifier = ref.read(semesterStartProvider.notifier);
  final selectedSemesterNotifier = ref.read(
    selectedScheduleSemesterProvider.notifier,
  );
  final selectedWeekNotifier = ref.read(selectedWeekProvider.notifier);
  final sundayFirst =
      ref.read(scheduleSundayFirstProvider).valueOrNull ?? false;

  await forKeyNotifier.set(picked);
  await semesterStartNotifier.set(picked);
  await selectedSemesterNotifier.set(semesterStr);
  selectedWeekNotifier.setWeek(
    _calcCurrentWeek(
      picked,
      sundayFirst: sundayFirst,
      totalWeeks:
          ref.read(semesterTotalWeeksProvider(semesterStr)).valueOrNull ??
          defaultSemesterTotalWeeks,
    ),
  );

  if (context.mounted) {
    AppSnackBar.status(context, '已自动切换为 ${_semesterLabel(semesterStr)}');
  }
}
