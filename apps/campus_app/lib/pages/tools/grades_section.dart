part of '../tools_page.dart';

// ── 成绩页 (已修改为公开类) ────────────────────────────────────────────────────
class GradesPage extends ConsumerStatefulWidget {
  const GradesPage({super.key});

  @override
  ConsumerState<GradesPage> createState() => _GradesPageState();
}

class _GradesPageState extends ConsumerState<GradesPage> {
  String _semester = ''; // 空字符串 = 全部

  String get _semesterLabel {
    if (_semester.isEmpty) return '全部学期';
    final parts = _semester.split('-');
    return parts.length == 3
        ? '${parts[0]}-${parts[1]}  第${parts[2]}学期'
        : _semester;
  }

  @override
  Widget build(BuildContext context) {
    final gradesAsync = ref.watch(gradesProvider(_semester));

    return Scaffold(
      appBar: GlassAppBar(
        title: const Text('成绩查询'),
        actions: [
          // 学期筛选入口：显示当前选中学期
          TextButton.icon(
            icon: const Icon(Icons.filter_list, size: 18),
            label: Text(_semesterLabel, style: const TextStyle(fontSize: 13)),
            onPressed: () async {
              final result = await showSemesterPicker(
                context,
                current: _semester,
              );
              // result == null 说明用户关闭弹窗未选择，保持原值
              if (result != null && result != _semester) {
                setState(() => _semester = result);
              }
            },
          ),
        ],
      ),
      body: gradesAsync.when(
        skipError: true,
        skipLoadingOnRefresh: true,
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(e.toString()),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => ref
                    .read(gradesProvider(_semester).notifier)
                    .refresh(forceRefresh: true),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
        data: (result) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (gradesAsync.shouldOfferManualRefresh)
              BackgroundRefreshBanner(
                onRefresh: () => ref
                    .read(gradesProvider(_semester).notifier)
                    .refresh(forceRefresh: true),
              ),
            if (result.summary.isNotEmpty || result.grades.isNotEmpty)
              _SummaryCard(summary: result.summary, grades: result.grades),
            const SizedBox(height: 12),
            ...result.grades.map(
              (g) => GradeItem(
                grade: g,
                onTap: g.hasDetail
                    ? () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => GradeDetailPage(grade: g),
                        ),
                      )
                    : null,
              ),
            ),
            if (result.grades.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    '暂无成绩数据',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final Map<String, String> summary;
  final List<Grade> grades;
  const _SummaryCard({required this.summary, this.grades = const []});

  static String _resolveValue(String? raw, String? fallback) {
    final trimmed = raw?.trim();
    if (trimmed != null && trimmed.isNotEmpty && trimmed != '-') {
      return trimmed;
    }
    return fallback ?? '-';
  }

  @override
  Widget build(BuildContext context) {
    final stats = grades.isNotEmpty ? AcademicStats.fromGrades(grades) : null;
    final gpaVal = _resolveValue(
      summary['gpa'],
      stats?.calculatedGpa?.toStringAsFixed(2),
    );
    final avgVal = _resolveValue(
      summary['avgScore'],
      stats?.weightedAverage?.toStringAsFixed(1),
    );

    return Card(
      color: AppColors.tint.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '学业汇总',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _Item('GPA', gpaVal),
                _Item('均分', avgVal),
                _Item('班级排名', _resolveValue(summary['classRank'], null)),
                _Item('专业排名', _resolveValue(summary['majorRank'], null)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  final String label;
  final String value;
  const _Item(this.label, this.value);

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: AppColors.primary,
        ),
      ),
      Text(
        label,
        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
      ),
    ],
  );
}

class GradeDetailPage extends ConsumerWidget {
  const GradeDetailPage({super.key, required this.grade});

  final Grade grade;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arg = (grade: grade);
    final detailAsync = ref.watch(gradeDetailProvider(arg));
    final isFetching = detailAsync.isRefreshing && !detailAsync.hasValue;

    return Scaffold(
      appBar: GlassAppBar(
        title: const Text('成绩明细'),
        actions: [
          SpinningRefreshButton(
            tooltip: '刷新明细',
            onPressed: () => ref
                .read(gradeDetailProvider(arg).notifier)
                .refresh(forceRefresh: true),
          ),
        ],
      ),
      body: detailAsync.when(
        skipError: true,
        skipLoadingOnRefresh: true,
        skipLoadingOnReload: true,
        loading: () => _GradeDetailContent(
          grade: grade,
          detail: const GradeDetail(items: [], totalScore: ''),
          isFetching: true,
        ),
        error: (error, _) => _GradeDetailError(
          grade: grade,
          message: error.toString(),
          onRetry: () => ref
              .read(gradeDetailProvider(arg).notifier)
              .refresh(forceRefresh: true),
        ),
        data: (detail) => _GradeDetailContent(
          grade: grade,
          detail: detail,
          isFetching: isFetching,
          banner: detailAsync.shouldOfferManualRefresh
              ? BackgroundRefreshBanner(
                  onRefresh: () => ref
                      .read(gradeDetailProvider(arg).notifier)
                      .refresh(forceRefresh: true),
                )
              : null,
        ),
      ),
    );
  }
}

class _GradeDetailContent extends StatelessWidget {
  const _GradeDetailContent({
    required this.grade,
    required this.detail,
    required this.isFetching,
    this.banner,
  });

  final Grade grade;
  final GradeDetail detail;
  final bool isFetching;
  final Widget? banner;

  @override
  Widget build(BuildContext context) {
    final total = detail.totalScore.trim().isEmpty
        ? grade.score
        : detail.totalScore.trim();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ?banner,
        _GradeHeroCard(grade: grade, totalScore: total),
        const SizedBox(height: 12),
        if (detail.items.isEmpty)
          _DetailEmptyState(isFetching: isFetching)
        else
          _BreakdownCard(items: detail.items),
      ],
    );
  }
}

class _GradeHeroCard extends StatelessWidget {
  const _GradeHeroCard({required this.grade, required this.totalScore});

  final Grade grade;
  final String totalScore;

  Color _scoreColor(BuildContext context) {
    final score = double.tryParse(totalScore);
    if (score == null) return Theme.of(context).colorScheme.primary;
    if (score >= 90) return AppColors.success;
    if (score >= 75) return Theme.of(context).colorScheme.primary;
    if (score >= 60) return AppColors.warning;
    return AppColors.danger;
  }

  @override
  Widget build(BuildContext context) {
    final color = _scoreColor(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: color, width: 4)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    grade.courseName,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${grade.semester}  ${grade.credits} 学分  绩点 ${grade.gradePoint}',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  if (grade.courseAttribute.isNotEmpty ||
                      grade.courseNature.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        [
                          grade.courseAttribute,
                          grade.courseNature,
                        ].where((text) => text.trim().isNotEmpty).join(' · '),
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Column(
              children: [
                Text(
                  totalScore,
                  style: TextStyle(
                    color: color,
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '总成绩',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({required this.items});

  final List<GradeDetailItem> items;

  @override
  Widget build(BuildContext context) {
    final segments = _buildBreakdownSegments(items);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '成绩构成',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            if (segments.isEmpty)
              Text('暂无可展示的成绩构成', style: TextStyle(color: AppColors.textMuted))
            else ...[
              _SegmentedBreakdownBar(segments: segments),
              const SizedBox(height: 14),
              for (var i = 0; i < segments.length; i++) ...[
                _BreakdownRow(segment: segments[i]),
                if (i != segments.length - 1) const Divider(height: 24),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

const _breakdownPalette = <Color>[
  Color(0xFF2563EB),
  Color(0xFF16A34A),
  Color(0xFFF59E0B),
  Color(0xFFE11D48),
  Color(0xFF0891B2),
  Color(0xFF7C3AED),
];

class _BreakdownSegment {
  const _BreakdownSegment({
    required this.item,
    required this.ratio,
    required this.color,
    required this.weightedScore,
  });

  final GradeDetailItem item;
  final double ratio;
  final Color color;
  final double? weightedScore;
}

List<_BreakdownSegment> _buildBreakdownSegments(List<GradeDetailItem> items) {
  final segments = <_BreakdownSegment>[];

  for (final item in items) {
    final ratio = _parsePercent(item.ratio);
    if (ratio == null || ratio <= 0) continue;

    final normalizedRatio = ratio > 1 ? 1.0 : ratio;
    final score = double.tryParse(item.score.trim());
    segments.add(
      _BreakdownSegment(
        item: item,
        ratio: normalizedRatio,
        color: _breakdownPalette[segments.length % _breakdownPalette.length],
        weightedScore: score == null ? null : score * normalizedRatio,
      ),
    );
  }

  return segments;
}

class _SegmentedBreakdownBar extends StatelessWidget {
  const _SegmentedBreakdownBar({required this.segments});

  final List<_BreakdownSegment> segments;

  int _flexFor(double ratio) {
    final flex = (ratio * 1000).round();
    return flex <= 0 ? 1 : flex;
  }

  @override
  Widget build(BuildContext context) {
    final usedRatio = segments.fold<double>(
      0,
      (total, segment) => total + segment.ratio,
    );
    final remainder = usedRatio >= 1 ? 0.0 : 1 - usedRatio;

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 14,
        child: Row(
          children: [
            for (final segment in segments)
              Expanded(
                flex: _flexFor(segment.ratio),
                child: ColoredBox(
                  color: segment.color,
                  child: const SizedBox.expand(),
                ),
              ),
            if (remainder > 0)
              Expanded(
                flex: _flexFor(remainder),
                child: ColoredBox(
                  color: AppColors.tintSoft,
                  child: const SizedBox.expand(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({required this.segment});

  final _BreakdownSegment segment;

  @override
  Widget build(BuildContext context) {
    final item = segment.item;
    final weighted = segment.weightedScore;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: segment.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            Text(
              item.score.isEmpty ? '-' : item.score,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              '占比 ${item.ratio.isEmpty ? '-' : item.ratio}',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            const Spacer(),
            Text(
              weighted == null ? '折算 -' : '折算 ${weighted.toStringAsFixed(1)}',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }
}

class _DetailEmptyState extends StatelessWidget {
  const _DetailEmptyState({required this.isFetching});

  final bool isFetching;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
        child: Column(
          children: [
            Icon(
              isFetching ? Icons.cloud_sync_outlined : Icons.info_outline,
              color: AppColors.textMuted.withValues(alpha: 0.4),
              size: 36,
            ),
            const SizedBox(height: 10),
            Text(
              isFetching ? '正在后台获取成绩明细' : '该课程暂无可展示的明细',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _GradeDetailError extends StatelessWidget {
  const _GradeDetailError({
    required this.grade,
    required this.message,
    required this.onRetry,
  });

  final Grade grade;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _GradeHeroCard(grade: grade, totalScore: grade.score),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                const Icon(Icons.error_outline, color: AppColors.danger),
                const SizedBox(height: 8),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重新获取'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

double? _parsePercent(String value) {
  final normalized = value.trim().replaceAll('%', '');
  final parsed = double.tryParse(normalized);
  if (parsed == null) return null;
  return parsed / 100;
}
