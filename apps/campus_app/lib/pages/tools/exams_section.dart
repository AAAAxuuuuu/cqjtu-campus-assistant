part of '../tools_page.dart';

// ── 考试安排页 (已修改为公开类) ─────────────────────────────────────────────────
class ExamsPage extends ConsumerStatefulWidget {
  const ExamsPage({super.key});

  @override
  ConsumerState<ExamsPage> createState() => _ExamsPageState();
}

class _ExamsPageState extends ConsumerState<ExamsPage> {
  // null = 当前学期（后端默认）
  String? _semester;

  String get _semesterLabel {
    if (_semester == null) return '当前学期';
    final parts = _semester!.split('-');
    return parts.length == 3
        ? '${parts[0]}-${parts[1]}  第${parts[2]}学期'
        : _semester!;
  }

  @override
  Widget build(BuildContext context) {
    final examsAsync = ref.watch(examsProvider(_semester));

    return Scaffold(
      appBar: GlassAppBar(
        title: const Text('考试安排'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.filter_list, size: 18),
            label: Text(_semesterLabel, style: const TextStyle(fontSize: 13)),
            onPressed: () async {
              final result = await showSemesterPicker(
                context,
                current: _semester ?? '',
              );
              if (result != null) {
                setState(() {
                  // 空字符串映射回 null（后端默认当前学期）
                  _semester = result.isEmpty ? null : result;
                });
              }
            },
          ),
        ],
      ),
      body: examsAsync.when(
        skipLoadingOnRefresh: true,
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
          message: formatCampusError(e),
          onRetry: () => ref
              .read(examsProvider(_semester).notifier)
              .refresh(forceRefresh: true),
        ),
        data: (exams) {
          if (exams.isEmpty) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (examsAsync.shouldOfferManualRefresh)
                  BackgroundRefreshBanner(
                    onRefresh: () => ref
                        .read(examsProvider(_semester).notifier)
                        .refresh(forceRefresh: true),
                  ),
                const SizedBox(height: 120),
                const Center(
                  child: Text(
                    '当前学期暂无考试安排',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                ),
              ],
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount:
                exams.length + (examsAsync.shouldOfferManualRefresh ? 1 : 0),
            itemBuilder: (_, i) {
              if (examsAsync.shouldOfferManualRefresh && i == 0) {
                return BackgroundRefreshBanner(
                  onRefresh: () => ref
                      .read(examsProvider(_semester).notifier)
                      .refresh(forceRefresh: true),
                );
              }
              final examIndex =
                  i - (examsAsync.shouldOfferManualRefresh ? 1 : 0);
              final exam = exams[examIndex];
              return AppCard(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(exam.courseName, style: AppType.rowTitle),
                    const Divider(),
                    _ExamRow(Icons.access_time_outlined, exam.examTime),
                    _ExamRow(Icons.room_outlined, exam.examRoom),
                    _ExamRow(
                      Icons.event_seat_outlined,
                      '座位号：${exam.seatNumber}',
                    ),
                    _ExamRow(
                      Icons.confirmation_number_outlined,
                      '准考证：${exam.ticketNumber}',
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _ExamRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _ExamRow(this.icon, this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textMuted),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
      ],
    ),
  );
}
