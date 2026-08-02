import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core/models/grade.dart';
import '../features/study_progress/study_progress_providers.dart';
import '../theme/app_theme.dart';
import '../utils/providers.dart';
import '../widgets/app_entrance.dart';
import '../widgets/background_refresh_banner.dart';
import '../widgets/glass_surface.dart';
import '../widgets/grade_item.dart';
import '../widgets/app_list_tile.dart';
import '../widgets/spinning_refresh_button.dart';
import 'academic_status_page.dart';
import 'campus_service_webview_page.dart';
import 'electricity_page.dart';
import 'leave_apply_page.dart';
import 'study_progress_page.dart';

// ── 学期选项生成 ──────────────────────────────────────────────
/// 生成学期列表：向后1个学期 + 当前学期 + 向前8个学年（共18个选项）
/// 顺序：最新学期在前
List<String> _buildSemesterOptions() {
  final now = DateTime.now();
  // 8 月及以后算上半学年（第 1 学期），否则算下半（第 2 学期）
  int currentYear = now.month >= 8 ? now.year : now.year - 1;
  int currentTerm = now.month >= 8 ? 1 : 2;

  // 计算起始点：向后推 1 个学期
  int startYear = currentYear;
  int startTerm = currentTerm + 1;
  if (startTerm > 2) {
    startTerm = 1;
    startYear++;
  }

  final options = <String>[];
  int y = startYear;
  int t = startTerm;

  // 1(向后) + 1(当前) + 16(向前8年) = 18 个选项
  for (int i = 0; i < 18; i++) {
    options.add('$y-${y + 1}-$t');
    // 往下循环时往前推一个学期
    if (t == 2) {
      t = 1;
    } else {
      t = 2;
      y--;
    }
  }
  return options;
}

// ── 学期选择底部弹窗 ─────────────────────────────────────────
Future<String?> showSemesterPicker(
  BuildContext context, {
  required String current, // 当前选中值，空字符串表示"全部"
}) async {
  final options = _buildSemesterOptions();

  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true, // [新增] 允许弹窗高度随内容伸展
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      // [新增] 限制最大高度为屏幕的 70%，体验更好
      final maxHeight = MediaQuery.of(ctx).size.height * 0.7;

      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min, // 核心：让外部 Column 紧贴内容
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Text(
                      '选择学期',
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    // 查全部入口
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, ''),
                      child: const Text('查全部'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // [新增] 用 Flexible + SingleChildScrollView 包裹列表，完美解决越界和滑动
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: options.map((s) {
                      final isSelected = s == current;
                      // 解析显示更友好的名称
                      final parts = s.split('-');
                      final label = parts.length == 3
                          ? '${parts[0]}-${parts[1]} 学年  第 ${parts[2]} 学期'
                          : s;
                      return ListTile(
                        title: Text(label),
                        trailing: isSelected
                            ? Icon(
                                Icons.check,
                                color: Theme.of(ctx).colorScheme.primary,
                              )
                            : null,
                        selected: isSelected,
                        selectedColor: Theme.of(ctx).colorScheme.primary,
                        onTap: () => Navigator.pop(ctx, s),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}

class ToolsPage extends ConsumerWidget {
  const ToolsPage({super.key});

  static const _emailUrl = 'https://i.cqjtu.edu.cn/email/#/index';
  static const _evaluationUrl = 'https://jwzlapp.cqjtu.edu.cn/#/login';
  static const _busReservationUrl = 'https://wxfw.cqjtu.edu.cn/bus/h5/#/';
  static const _ecardServiceUrl =
      'https://ids.cqjtu.edu.cn/authserver/login?service=https%3A%2F%2Fecard.cqjtu.edu.cn%2Fepay%2Fj_spring_cas_security_check';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studyProgress = ref.watch(studyProgressProvider);
    final studySummary = ref.watch(studyCreditProgressSummaryProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: GlassAppBar(
        title: const Text('服务'),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          AppEntrance(
            index: 0,
            child: _AcademicProgressServiceCard(
              summary: studySummary,
              hasData: studyProgress.hasData,
              isLoading: studyProgress.isLoading,
              hasError: studyProgress.hasError && !studyProgress.hasData,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AcademicStatusPage()),
              ),
              onRefresh: () => ref
                  .read(studyProgressProvider.notifier)
                  .refresh(forceRefresh: true),
            ),
          ),
          const SizedBox(height: 18),
          AppEntrance(
            index: 1,
            child: _ServiceSection(
              title: '教务',
              children: [
                _ServiceTile(
                  icon: Icons.grade_outlined,
                  color: AppColors.primary,
                  title: '成绩查询',
                  subtitle: '成绩列表与明细',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const GradesPage()),
                  ),
                ),
                _ServiceTile(
                  icon: Icons.event_note_outlined,
                  color: AppColors.secondary,
                  title: '考试安排',
                  subtitle: '考试时间、考场与座位',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ExamsPage()),
                  ),
                ),
                _ServiceTile(
                  icon: Icons.schema_outlined,
                  color: AppColors.accent,
                  title: '培养计划',
                  subtitle: '执行计划与培养方案',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const StudyProgressPage()),
                  ),
                ),
                _ServiceTile(
                  icon: Icons.rate_review_outlined,
                  color: AppColors.primary.withValues(alpha: 0.8),
                  title: '课程评价',
                  subtitle: '进入评教系统',
                  onTap: () => _openWebService(
                    context,
                    title: '课程评价',
                    url: _evaluationUrl,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          AppEntrance(
            index: 2,
            child: _ServiceSection(
              title: '校园',
              children: [
                _ServiceTile(
                  icon: Icons.bolt_outlined,
                  color: AppColors.accent,
                  title: '宿舍电费',
                  subtitle: '余额查询与充值',
                  onTap: () => ElectricityPage.open(context, ref),
                ),
                _ServiceTile(
                  icon: Icons.directions_bus_outlined,
                  color: AppColors.secondary,
                  title: '校车预约',
                  subtitle: '校车班次查询与预约',
                  onTap: () => _openWebService(
                    context,
                    title: '校车预约',
                    url: _busReservationUrl,
                  ),
                ),
                _ServiceTile(
                  icon: Icons.credit_card_outlined,
                  color: AppColors.primary,
                  title: '一卡通服务',
                  subtitle: '进入一卡通系统办理校园卡服务',
                  onTap: () => _openWebService(
                    context,
                    title: '一卡通服务',
                    url: _ecardServiceUrl,
                  ),
                ),
                _ServiceTile(
                  icon: Icons.assignment_return_outlined,
                  color: AppColors.success,
                  title: '请假申请',
                  subtitle: '出入校与请假记录',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LeaveApplyPage()),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          AppEntrance(
            index: 3,
            child: _ServiceSection(
              title: '在线系统',
              children: [
                _ServiceTile(
                  icon: Icons.alternate_email,
                  color: AppColors.secondary,
                  title: '邮箱服务',
                  subtitle: '学校邮箱与别名',
                  onTap: () =>
                      _openWebService(context, title: '邮箱服务', url: _emailUrl),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openWebService(
    BuildContext context, {
    required String title,
    required String url,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CampusServiceWebViewPage(title: title, initialUrl: url),
      ),
    );
  }
}

class _AcademicProgressServiceCard extends StatelessWidget {
  const _AcademicProgressServiceCard({
    required this.summary,
    required this.hasData,
    required this.isLoading,
    required this.hasError,
    required this.onTap,
    required this.onRefresh,
  });

  final StudyCreditProgressSummary summary;
  final bool hasData;
  final bool isLoading;
  final bool hasError;
  final VoidCallback onTap;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: AppColors.outline.withValues(alpha: 0.7),
            ),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 14, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '学业情况',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _academicCardSubtitle(summary, hasData),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isLoading)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else if (hasError || !hasData)
                      IconButton(
                        tooltip: hasError ? '重新获取学业情况' : '同步培养计划数据',
                        icon: const Icon(Icons.refresh, size: 19),
                        visualDensity: VisualDensity.compact,
                        onPressed: onRefresh,
                      )
                    else
                      Icon(
                        Icons.chevron_right,
                        color: AppColors.textMuted.withValues(alpha: 0.5),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final topContent = constraints.maxWidth < 320
                        ? Column(
                            children: [
                              _RequiredCreditRing(
                                summary: summary,
                                hasData: hasData,
                              ),
                              const SizedBox(height: 16),
                              _RequiredCreditLegend(
                                summary: summary,
                                hasData: hasData,
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              _RequiredCreditRing(
                                summary: summary,
                                hasData: hasData,
                              ),
                              const SizedBox(width: 18),
                              Expanded(
                                child: _RequiredCreditLegend(
                                  summary: summary,
                                  hasData: hasData,
                                ),
                              ),
                            ],
                          );

                    return Column(
                      children: [
                        topContent,
                        const SizedBox(height: 18),
                        Divider(height: 1, color: AppColors.outline.withValues(alpha: 0.6)),
                        const SizedBox(height: 14),
                        _EarnedCreditProgressGrid(
                          summary: summary,
                          hasData: hasData,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RequiredCreditRing extends StatelessWidget {
  const _RequiredCreditRing({required this.summary, required this.hasData});

  final StudyCreditProgressSummary summary;
  final bool hasData;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 116,
      height: 116,
      child: CustomPaint(
        painter: _CreditRingPainter(summary.buckets),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  hasData ? _formatCredit(summary.requiredCredits) : '--',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    height: 1,
                    color: AppColors.textPrimary,
                    fontSize: 24,
                  ),
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                '应修学分',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RequiredCreditLegend extends StatelessWidget {
  const _RequiredCreditLegend({required this.summary, required this.hasData});

  final StudyCreditProgressSummary summary;
  final bool hasData;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < summary.buckets.length; i++) ...[
          _RequiredCreditLegendRow(
            bucket: summary.buckets[i],
            totalRequired: summary.requiredCredits,
            hasData: hasData,
          ),
          if (i != summary.buckets.length - 1)
            const Divider(height: 18, color: AppColors.outline),
        ],
      ],
    );
  }
}

class _RequiredCreditLegendRow extends StatelessWidget {
  const _RequiredCreditLegendRow({
    required this.bucket,
    required this.totalRequired,
    required this.hasData,
  });

  final StudyCreditBucketView bucket;
  final double totalRequired;
  final bool hasData;

  @override
  Widget build(BuildContext context) {
    final percent = !hasData || bucket.requiredCredits <= 0
        ? 0
        : (bucket.earnedCredits / bucket.requiredCredits * 100).round().clamp(
            0,
            100,
          );
    final color = _creditCategoryColor(bucket.category);

    return Row(
      children: [
        Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '应修${bucket.label}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        SizedBox(
          width: 42,
          child: Text(
            hasData ? '$percent%' : '--',
            textAlign: TextAlign.end,
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ),
        Container(
          width: 1,
          height: 16,
          margin: const EdgeInsets.symmetric(horizontal: 10),
          color: AppColors.outline,
        ),
        SizedBox(
          width: 46,
          child: Text(
            hasData ? '${_formatCredit(bucket.requiredCredits)}分' : '--',
            textAlign: TextAlign.end,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _EarnedCreditProgressGrid extends StatelessWidget {
  const _EarnedCreditProgressGrid({
    required this.summary,
    required this.hasData,
  });

  final StudyCreditProgressSummary summary;
  final bool hasData;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useTwoColumns = constraints.maxWidth >= 520;
        final tileWidth = useTwoColumns
            ? (constraints.maxWidth - 28) / 2
            : constraints.maxWidth;

        return Wrap(
          spacing: 28,
          runSpacing: 12,
          children: [
            for (final bucket in summary.buckets)
              SizedBox(
                width: tileWidth,
                child: _EarnedCreditProgressTile(
                  bucket: bucket,
                  hasData: hasData,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _EarnedCreditProgressTile extends StatelessWidget {
  const _EarnedCreditProgressTile({
    required this.bucket,
    required this.hasData,
  });

  final StudyCreditBucketView bucket;
  final bool hasData;

  @override
  Widget build(BuildContext context) {
    final progress = !hasData || bucket.requiredCredits <= 0
        ? 0.0
        : (bucket.earnedCredits / bucket.requiredCredits).clamp(0.0, 1.0);
    final color = _creditCategoryColor(bucket.category);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '已修${bucket.label}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Text(
              hasData ? '${_formatCredit(bucket.earnedCredits)}分' : '--',
              style: const TextStyle(color: AppColors.textPrimary),
            ),
          ],
        ),
        const SizedBox(height: 9),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 7,
            color: color,
            backgroundColor: AppColors.tintSoft,
          ),
        ),
      ],
    );
  }
}

class _CreditRingPainter extends CustomPainter {
  const _CreditRingPainter(this.buckets);

  final List<StudyCreditBucketView> buckets;

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.shortestSide * 0.22;
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(strokeWidth / 2);
    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt
      ..color = AppColors.tintSoft;

    canvas.drawArc(arcRect, -math.pi / 2, math.pi * 2, false, basePaint);

    final total = buckets.fold<double>(
      0,
      (sum, bucket) => sum + bucket.requiredCredits,
    );
    if (total <= 0) return;

    var start = -math.pi / 2;
    const gap = 0.035;
    for (final bucket in buckets) {
      if (bucket.requiredCredits <= 0) continue;
      final sweep = math.pi * 2 * bucket.requiredCredits / total;
      final visibleSweep = (sweep - gap).clamp(0.0, sweep);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt
        ..color = _creditCategoryColor(bucket.category);
      canvas.drawArc(arcRect, start, visibleSweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _CreditRingPainter oldDelegate) =>
      oldDelegate.buckets != buckets;
}

String _formatCredit(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(1);
}

String _academicCardSubtitle(StudyCreditProgressSummary summary, bool hasData) {
  if (!hasData) return '等待培养计划数据同步';
  if (summary.currentSemester.trim().isEmpty) return '已联动培养计划';
  return '已联动培养计划 · ${summary.currentSemester}';
}

Color _creditCategoryColor(StudyCreditCategory category) {
  switch (category) {
    case StudyCreditCategory.compulsory:
      return AppColors.primary;
    case StudyCreditCategory.elective:
      return AppColors.secondary;
    case StudyCreditCategory.schoolElective:
      return AppColors.accent;
  }
}

class _ServiceSection extends StatelessWidget {
  const _ServiceSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                children[i],
                if (i != children.length - 1)
                  const Divider(
                    height: 1,
                    indent: 56,
                    color: AppColors.outline,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ServiceTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ServiceTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppListTile(
      icon: icon,
      iconColor: color,
      title: title,
      subtitle: subtitle,
      onTap: onTap,
    );
  }
}

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
                  child: Text('暂无成绩数据', style: TextStyle(color: AppColors.textMuted)),
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
      Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
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
        skipError: true,
        skipLoadingOnRefresh: true,
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString())),
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
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        exam.courseName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
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
