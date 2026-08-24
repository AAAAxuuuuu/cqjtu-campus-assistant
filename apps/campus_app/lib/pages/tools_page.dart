import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core/models/grade.dart';
import '../features/study_progress/study_progress_providers.dart';
import '../theme/app_theme.dart';
import '../utils/campus_error_message.dart';
import '../utils/providers.dart';
import '../widgets/app_card.dart';
import '../widgets/app_entrance.dart';
import '../widgets/background_refresh_banner.dart';
import '../widgets/error_view.dart';
import '../widgets/glass_surface.dart';
import '../widgets/grade_item.dart';
import '../widgets/app_list_tile.dart';
import '../widgets/spinning_refresh_button.dart';
import 'academic_status_page.dart';
import 'campus_service_webview_page.dart';
import 'electricity_page.dart';
import 'leave_apply_page.dart';
import 'study_progress_page.dart';
part 'tools/grades_section.dart';
part 'tools/exams_section.dart';

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
      appBar: GlassAppBar(title: const Text('服务'), centerTitle: false),
      body: ListView(
        padding: AppInsets.withNavBarClearanceOf(
          context,
          const EdgeInsets.fromLTRB(16, 8, 16, 24),
        ),
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
                    MaterialPageRoute(
                      builder: (_) => const StudyProgressPage(),
                    ),
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
            border: Border.all(color: AppColors.outline.withValues(alpha: 0.7)),
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
                          Text(
                            '学业情况',
                            style: AppType.sectionTitle.copyWith(
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _academicCardSubtitle(summary, hasData),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.caption.copyWith(
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
                        Divider(
                          height: 1,
                          color: AppColors.outline.withValues(alpha: 0.6),
                        ),
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
                  // 环形图中心的学分数：metric 的字重与紧行高，字号按环径收小。
                  style: AppType.metric.copyWith(
                    fontSize: 24,
                    letterSpacing: -0.5,
                    color: AppColors.textPrimary,
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
            style: AppType.body.copyWith(
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
            style: AppType.body.copyWith(
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
                style: AppType.body.copyWith(
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
            style: AppType.sectionTitle.copyWith(color: AppColors.textPrimary),
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
