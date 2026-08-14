part of '../schedule_page.dart';

Future<void> _showAddCustomCourseSheet(
  BuildContext context,
  WidgetRef ref,
  String? selectedSemester,
  int totalWeeks,
) async {
  final nameController = TextEditingController();
  final classroomController = TextEditingController();
  final teacherController = TextEditingController();
  final autoTextController = TextEditingController();
  final formKey = GlobalKey<FormState>();
  final safeTotalWeeks = totalWeeks
      .clamp(minSemesterTotalWeeks, maxSemesterTotalWeeks)
      .toInt();
  final selectedWeek = ref.read(selectedWeekProvider);
  final initialWeek = selectedWeek >= 1 && selectedWeek <= safeTotalWeeks
      ? selectedWeek
      : 1;

  var weekday = DateTime.monday;
  var startSlot = 1;
  var endSlot = 2;
  var startWeek = initialWeek;
  var endWeek = initialWeek;
  var recognizedEntries = const <ParsedCourseData>[];

  try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            void applyParsedData(
              ParsedCourseData parsed, {
              int recognizedCount = 1,
            }) {
              var count = 0;
              if (parsed.name != null && parsed.name!.isNotEmpty) {
                nameController.text = parsed.name!;
                count++;
              }
              if (parsed.classroom != null && parsed.classroom!.isNotEmpty) {
                classroomController.text = parsed.classroom!;
                count++;
              }
              if (parsed.teacher != null && parsed.teacher!.isNotEmpty) {
                teacherController.text = parsed.teacher!;
                count++;
              }
              if (parsed.weekday != null &&
                  parsed.weekday! >= 1 &&
                  parsed.weekday! <= 7) {
                weekday = parsed.weekday!;
                count++;
              }
              if (parsed.startSlot != null &&
                  parsed.startSlot! >= 1 &&
                  parsed.startSlot! <= 13) {
                startSlot = parsed.startSlot!;
                count++;
              }
              if (parsed.endSlot != null &&
                  parsed.endSlot! >= 1 &&
                  parsed.endSlot! <= 13) {
                endSlot = parsed.endSlot! < startSlot
                    ? startSlot
                    : parsed.endSlot!;
                count++;
              }
              if (parsed.startWeek != null &&
                  parsed.startWeek! >= 1 &&
                  parsed.startWeek! <= safeTotalWeeks) {
                startWeek = parsed.startWeek!;
                count++;
              }
              if (parsed.endWeek != null &&
                  parsed.endWeek! >= 1 &&
                  parsed.endWeek! <= safeTotalWeeks) {
                endWeek = parsed.endWeek! < startWeek
                    ? startWeek
                    : parsed.endWeek!;
                count++;
              }

              setSheetState(() {});

              if (!sheetContext.mounted) return;
              if (count > 0) {
                AppSnackBar.success(
                  sheetContext,
                  recognizedCount > 1
                      ? '已识别 $recognizedCount 条上课安排，当前展示第 1 条'
                      : '已自动识别填充 $count 项信息',
                );
              } else {
                AppSnackBar.warning(sheetContext, '未识别到有效课程信息');
              }
            }

            void applyParsedEntries(List<ParsedCourseData> entries) {
              recognizedEntries = entries;
              if (entries.isEmpty) {
                if (!sheetContext.mounted) return;
                AppSnackBar.warning(sheetContext, '未识别到有效课程信息');
                return;
              }
              applyParsedData(entries.first, recognizedCount: entries.length);
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                18,
                20,
                MediaQuery.of(sheetContext).viewInsets.bottom + 20,
              ),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.edit_calendar_outlined,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              '新增自定义课程',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Row(
                                  children: [
                                    Icon(
                                      Icons.auto_awesome,
                                      size: 18,
                                      color: AppColors.primary,
                                    ),
                                    SizedBox(width: 6),
                                    Text(
                                      '粘贴并识别课程',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ],
                                ),
                                TextButton.icon(
                                  onPressed: () async {
                                    final data = await Clipboard.getData(
                                      Clipboard.kTextPlain,
                                    );
                                    final text = data?.text;
                                    if (text != null &&
                                        text.trim().isNotEmpty) {
                                      autoTextController.text = text;
                                      final parsed = CourseTextParser.parseAll(
                                        text,
                                      );
                                      applyParsedEntries(parsed);
                                    } else {
                                      if (!sheetContext.mounted) return;
                                      AppSnackBar.warning(
                                        sheetContext,
                                        '剪贴板为空',
                                      );
                                    }
                                  },
                                  icon: const Icon(
                                    Icons.content_paste,
                                    size: 16,
                                  ),
                                  label: const Text('粘贴剪贴板'),
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: autoTextController,
                                    maxLines: 2,
                                    minLines: 1,
                                    decoration: const InputDecoration(
                                      hintText:
                                          '如：高等数学 周一 1-2节 1-16周 A101 张三老师',
                                      hintStyle: TextStyle(fontSize: 12),
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 8,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                FilledButton.tonal(
                                  onPressed: () {
                                    final text = autoTextController.text;
                                    if (text.trim().isNotEmpty) {
                                      final parsed = CourseTextParser.parseAll(
                                        text,
                                      );
                                      applyParsedEntries(parsed);
                                    }
                                  },
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 12,
                                    ),
                                  ),
                                  child: const Text('识别'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (recognizedEntries.length > 1) ...[
                        const SizedBox(height: 10),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.playlist_add_check_outlined,
                              size: 18,
                              color: AppColors.textPrimary,
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                '识别到 ${recognizedEntries.length} 条上课安排，保存时会一次性创建全部课程。',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textPrimary,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: '课程名称',
                          prefixIcon: Icon(Icons.menu_book_outlined),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? '请输入课程名称'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: classroomController,
                        decoration: const InputDecoration(
                          labelText: '教室',
                          prefixIcon: Icon(Icons.room_outlined),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? '请输入教室'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: teacherController,
                        decoration: const InputDecoration(
                          labelText: '教师（可选）',
                          prefixIcon: Icon(Icons.person_outline),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              initialValue: weekday,
                              decoration: const InputDecoration(
                                labelText: '星期',
                                border: OutlineInputBorder(),
                              ),
                              items: List.generate(7, (index) {
                                final value = index + 1;
                                return DropdownMenuItem(
                                  value: value,
                                  child: Text(_weekdayName(value)),
                                );
                              }),
                              onChanged: (value) {
                                if (value == null) return;
                                setSheetState(() => weekday = value);
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              initialValue: startSlot,
                              decoration: const InputDecoration(
                                labelText: '开始节',
                                border: OutlineInputBorder(),
                              ),
                              items: _slotMenuItems(),
                              onChanged: (value) {
                                if (value == null) return;
                                setSheetState(() {
                                  startSlot = value;
                                  if (endSlot < startSlot) endSlot = startSlot;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              initialValue: endSlot,
                              decoration: const InputDecoration(
                                labelText: '结束节',
                                border: OutlineInputBorder(),
                              ),
                              items: _slotMenuItems(),
                              onChanged: (value) {
                                if (value == null) return;
                                setSheetState(() {
                                  endSlot = value < startSlot
                                      ? startSlot
                                      : value;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              initialValue: startWeek,
                              decoration: const InputDecoration(
                                labelText: '开始周',
                                border: OutlineInputBorder(),
                              ),
                              items: _weekMenuItems(safeTotalWeeks),
                              onChanged: (value) {
                                if (value == null) return;
                                setSheetState(() {
                                  startWeek = value;
                                  if (endWeek < startWeek) endWeek = startWeek;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              initialValue: endWeek,
                              decoration: const InputDecoration(
                                labelText: '结束周',
                                border: OutlineInputBorder(),
                              ),
                              items: _weekMenuItems(safeTotalWeeks),
                              onChanged: (value) {
                                if (value == null) return;
                                setSheetState(() {
                                  endWeek = value < startWeek
                                      ? startWeek
                                      : value;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: FilledButton.icon(
                          icon: const Icon(Icons.check),
                          label: Text(
                            recognizedEntries.length > 1
                                ? '保存 ${recognizedEntries.length} 条课程'
                                : '保存课程',
                          ),
                          onPressed: () async {
                            if (!formKey.currentState!.validate()) return;
                            final entries = recognizedEntries.length > 1
                                ? recognizedEntries
                                : const <ParsedCourseData>[];
                            final courses = entries.isEmpty
                                ? [
                                    _buildCustomCourse(
                                      name: nameController.text.trim(),
                                      classroom: classroomController.text
                                          .trim(),
                                      teacher: teacherController.text.trim(),
                                      weekday: weekday,
                                      startSlot: startSlot,
                                      endSlot: endSlot,
                                      startWeek: startWeek,
                                      endWeek: endWeek,
                                    ),
                                  ]
                                : entries
                                      .map(
                                        (parsed) => _buildCustomCourse(
                                          name:
                                              parsed.name?.trim().isNotEmpty ==
                                                  true
                                              ? parsed.name!.trim()
                                              : nameController.text.trim(),
                                          classroom:
                                              parsed.classroom
                                                      ?.trim()
                                                      .isNotEmpty ==
                                                  true
                                              ? parsed.classroom!.trim()
                                              : classroomController.text.trim(),
                                          teacher:
                                              parsed.teacher
                                                      ?.trim()
                                                      .isNotEmpty ==
                                                  true
                                              ? parsed.teacher!.trim()
                                              : teacherController.text.trim(),
                                          weekday: parsed.weekday ?? weekday,
                                          startSlot:
                                              parsed.startSlot ?? startSlot,
                                          endSlot: parsed.endSlot ?? endSlot,
                                          startWeek:
                                              (parsed.startWeek ?? startWeek)
                                                  .clamp(1, safeTotalWeeks)
                                                  .toInt(),
                                          endWeek: (parsed.endWeek ?? endWeek)
                                              .clamp(1, safeTotalWeeks)
                                              .toInt(),
                                        ),
                                      )
                                      .toList();
                            final notifier = ref.read(
                              customCoursesProvider(selectedSemester).notifier,
                            );
                            for (final course in courses) {
                              await notifier.addCourse(course);
                            }
                            if (!sheetContext.mounted) return;
                            Navigator.pop(sheetContext);
                            if (!context.mounted) return;
                            AppSnackBar.success(
                              context,
                              courses.length == 1
                                  ? '已新增「${courses.first.name}」'
                                  : '已新增 ${courses.length} 条自定义课程',
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  } finally {
    nameController.dispose();
    classroomController.dispose();
    teacherController.dispose();
    autoTextController.dispose();
  }
}

List<DropdownMenuItem<int>> _slotMenuItems() {
  return List.generate(_kTotalSlots, (index) {
    final slot = index + 1;
    return DropdownMenuItem(value: slot, child: Text(_slotLabel(slot)));
  });
}

List<DropdownMenuItem<int>> _weekMenuItems(int totalWeeks) {
  return List.generate(totalWeeks, (index) {
    final week = index + 1;
    return DropdownMenuItem(value: week, child: Text('第 $week 周'));
  });
}

String _weekdayName(int weekday) {
  return switch (weekday) {
    DateTime.monday => '周一',
    DateTime.tuesday => '周二',
    DateTime.wednesday => '周三',
    DateTime.thursday => '周四',
    DateTime.friday => '周五',
    DateTime.saturday => '周六',
    _ => '周日',
  };
}

String _slotLabel(int slot) {
  final times = _kSlotTimes[slot];
  if (times == null) return '第 $slot 节';
  return '$slot (${times.$1})';
}

String _customCourseTimeText(
  int weekday,
  int startSlot,
  int endSlot,
  int startWeek,
  int endWeek,
) {
  final weekText = startWeek == endWeek
      ? '第 $startWeek 周'
      : '第 $startWeek-$endWeek 周';
  final slotText = startSlot == endSlot
      ? '第 $startSlot 节'
      : '第 $startSlot-$endSlot 节';
  return '$weekText · ${_weekdayName(weekday)} · $slotText';
}

Course _buildCustomCourse({
  required String name,
  required String classroom,
  required String teacher,
  required int weekday,
  required int startSlot,
  required int endSlot,
  required int startWeek,
  required int endWeek,
}) {
  final safeWeekday = weekday.clamp(DateTime.monday, DateTime.sunday).toInt();
  final safeStartSlot = startSlot.clamp(1, _kTotalSlots).toInt();
  final safeEndSlot = endSlot.clamp(safeStartSlot, _kTotalSlots).toInt();
  final safeStartWeek = startWeek < 1 ? 1 : startWeek;
  final safeEndWeek = endWeek < safeStartWeek ? safeStartWeek : endWeek;
  return Course(
    name: name,
    teacher: teacher,
    timeStr: _customCourseTimeText(
      safeWeekday,
      safeStartSlot,
      safeEndSlot,
      safeStartWeek,
      safeEndWeek,
    ),
    classroom: classroom,
    dayOfWeek: safeWeekday,
    timeSlot: safeStartSlot,
    endTimeSlot: safeEndSlot,
    weekList: [
      for (var week = safeStartWeek; week <= safeEndWeek; week++) week,
    ],
    isCustom: true,
  );
}
