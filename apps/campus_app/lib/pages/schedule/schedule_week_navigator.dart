part of '../schedule_page.dart';

class _WeekNavigator extends ConsumerWidget {
  final DateTime semesterStart;
  final int selectedWeek;
  final int currentWeek;
  final bool sundayFirst;
  final int totalWeeks;

  const _WeekNavigator({
    required this.semesterStart,
    required this.selectedWeek,
    required this.currentWeek,
    required this.sundayFirst,
    required this.totalWeeks,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final semesterDoneWeek = totalWeeks + 1;
    final isVacation = selectedWeek == 0 || selectedWeek == semesterDoneWeek;
    final weekStart = isVacation
        ? _startOfWeek(DateTime.now(), sundayFirst: sundayFirst)
        : _weekStartOf(semesterStart, selectedWeek, sundayFirst: sundayFirst);
    final weekEnd = weekStart.add(const Duration(days: 6));
    final isCur = selectedWeek == currentWeek;

    VoidCallback? onLeft;
    if (selectedWeek > 1 && selectedWeek <= totalWeeks) {
      onLeft = () =>
          ref.read(selectedWeekProvider.notifier).setWeek(selectedWeek - 1);
    } else if (selectedWeek == semesterDoneWeek) {
      onLeft = () =>
          ref.read(selectedWeekProvider.notifier).setWeek(totalWeeks);
    } else if (selectedWeek == 1) {
      onLeft = () => ref.read(selectedWeekProvider.notifier).setWeek(0);
    }

    VoidCallback? onRight;
    if (selectedWeek >= 1 && selectedWeek < totalWeeks) {
      onRight = () =>
          ref.read(selectedWeekProvider.notifier).setWeek(selectedWeek + 1);
    } else if (selectedWeek == 0) {
      onRight = () => ref.read(selectedWeekProvider.notifier).setWeek(1);
    } else if (selectedWeek == totalWeeks) {
      onRight = () =>
          ref.read(selectedWeekProvider.notifier).setWeek(semesterDoneWeek);
    }

    return Container(
      color: Theme.of(
        context,
      ).colorScheme.primaryContainer.withValues(alpha: 0.3),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          IconButton(
            tooltip: '上一周',
            icon: const Icon(Icons.chevron_left),
            padding: EdgeInsets.zero,
            // 48dp is the Material / WCAG 2.5.5 minimum target; these were
            // 36dp, i.e. 25% under, on the app's most-tapped control.
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: onLeft,
          ),
          Expanded(
            // Long-press is the only way to jump to an arbitrary week, and a
            // bare GestureDetector announces nothing to TalkBack — the
            // affordance was undiscoverable for screen-reader users.
            child: Semantics(
              button: true,
              label: '选择周次',
              hint: '长按选择要跳转的周次',
              child: GestureDetector(
                onLongPress: () => _pickWeek(context, ref),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          isVacation ? '放假中' : '第 $selectedWeek 周',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: isCur && !isVacation
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          ),
                        ),
                        if (isCur && !isVacation) ...[
                          const SizedBox(width: 6),
                          const AppBadge.solid(label: '本周'),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${weekStart.month}/${weekStart.day} - '
                      '${weekEnd.month}/${weekEnd.day}',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: '下一周',
            icon: const Icon(Icons.chevron_right),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: onRight,
          ),
        ],
      ),
    );
  }

  void _pickWeek(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SizedBox(
        height: 300,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '选择周次',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  childAspectRatio: 1.6,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: totalWeeks,
                itemBuilder: (_, i) {
                  final w = i + 1;
                  final isCur = w == currentWeek;
                  final isSel = w == selectedWeek;
                  return GestureDetector(
                    onTap: () {
                      ref.read(selectedWeekProvider.notifier).setWeek(w);
                      Navigator.pop(context);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSel
                            ? Theme.of(context).colorScheme.primary
                            : isCur
                            ? Theme.of(context).colorScheme.primaryContainer
                            : AppColors.tintSoft,
                        borderRadius: BorderRadius.circular(8),
                        border: isCur && !isSel
                            ? Border.all(
                                color: Theme.of(context).colorScheme.primary,
                                width: 1.5,
                              )
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '第$w周',
                        style: TextStyle(
                          fontSize: 12,
                          color: isSel ? Colors.white : null,
                          fontWeight: isCur || isSel
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
