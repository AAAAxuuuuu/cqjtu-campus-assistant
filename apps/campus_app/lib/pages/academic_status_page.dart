import 'dart:async';

import 'package:core/models/grade.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/study_progress/study_progress_providers.dart';
import '../theme/app_theme.dart';
import '../utils/providers.dart';
import '../widgets/app_card.dart';
import '../widgets/background_refresh_banner.dart';
import '../widgets/glass_surface.dart';
import '../widgets/spinning_refresh_button.dart';

class AcademicStatusPage extends ConsumerStatefulWidget {
  const AcademicStatusPage({super.key});

  @override
  ConsumerState<AcademicStatusPage> createState() => _AcademicStatusPageState();
}

class _AcademicStatusPageState extends ConsumerState<AcademicStatusPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshAll();
    });
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      ref.read(gradesProvider('').notifier).refresh(forceRefresh: true),
      ref.read(studyProgressProvider.notifier).refresh(forceRefresh: true),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final gradesState = ref.watch(gradesProvider(''));
    final studyState = ref.watch(studyProgressProvider);
    final summary = ref.watch(studyCreditProgressSummaryProvider);

    return Scaffold(
      appBar: GlassAppBar(
        title: const Text('学业情况'),
        actions: [
          SpinningRefreshButton(tooltip: '刷新学业数据', onPressed: _refreshAll),
        ],
      ),
      body:
          gradesState.hasError &&
              !gradesState.hasData &&
              studyState.hasError &&
              !studyState.hasData
          ? _AcademicError(
              message: gradesState.error.toString(),
              onRetry: () => unawaited(_refreshAll()),
            )
          : _AcademicStatusContent(
              gradesSummary: gradesState.data.summary,
              creditSummary: summary,
              grades: gradesState.data.grades,
              showRefreshBanner:
                  gradesState.shouldOfferManualRefresh ||
                  studyState.shouldOfferManualRefresh,
              onRefresh: _refreshAll,
            ),
    );
  }
}

class _AcademicStatusContent extends StatelessWidget {
  const _AcademicStatusContent({
    required this.gradesSummary,
    required this.creditSummary,
    required this.grades,
    required this.showRefreshBanner,
    required this.onRefresh,
  });

  final Map<String, String> gradesSummary;
  final StudyCreditProgressSummary creditSummary;
  final List<Grade> grades;
  final bool showRefreshBanner;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final stats = AcademicStats.fromGrades(grades);

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (showRefreshBanner)
            BackgroundRefreshBanner(onRefresh: () => unawaited(onRefresh())),
          _OverviewCard(summary: gradesSummary, stats: stats),
          const SizedBox(height: 12),
          _CreditCard(summary: creditSummary, stats: stats),
          if (grades.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 64),
              child: Center(
                child: Text(
                  '暂无学业数据',
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({required this.summary, required this.stats});

  final Map<String, String> summary;
  final AcademicStats stats;

  static String _resolveValue(String? raw, String? fallback) {
    final trimmed = raw?.trim();
    if (trimmed != null && trimmed.isNotEmpty && trimmed != '-') {
      return trimmed;
    }
    return fallback ?? '-';
  }

  @override
  Widget build(BuildContext context) {
    final gpaVal = _resolveValue(
      summary['gpa'],
      stats.calculatedGpa?.toStringAsFixed(2),
    );
    final avgVal = _resolveValue(
      summary['avgScore'],
      stats.weightedAverage?.toStringAsFixed(1),
    );

    // AppCard 自带圆角裁切与品牌色阴影，所以这里 padding 交给内层 Container
    // 承担（左侧强调色条需要贴到卡片边缘，不能被 padding 推开）。
    return AppCard(
      padding: EdgeInsets.zero,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: const BoxDecoration(
          border: Border(left: BorderSide(color: AppColors.primary, width: 4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('学业概览', style: AppType.sectionTitle),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 2,
              childAspectRatio: 2.7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              children: [
                _MetricTile(label: 'GPA', value: gpaVal),
                _MetricTile(label: '均分', value: avgVal),
                _MetricTile(
                  label: '班级排名',
                  value: _resolveValue(summary['classRank'], null),
                ),
                _MetricTile(
                  label: '专业排名',
                  value: _resolveValue(summary['majorRank'], null),
                ),
              ],
            ),
            if (stats.weightedAverage != null) ...[
              const SizedBox(height: 12),
              Text(
                '按当前可读取成绩估算加权均分 ${stats.weightedAverage!.toStringAsFixed(1)}',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CreditCard extends StatelessWidget {
  const _CreditCard({required this.summary, required this.stats});

  final StudyCreditProgressSummary summary;
  final AcademicStats stats;

  @override
  Widget build(BuildContext context) {
    double earnedCreditsFor(StudyCreditCategory category) => summary.buckets
        .where((bucket) => bucket.category == category)
        .fold<double>(0, (total, bucket) => total + bucket.earnedCredits);

    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('学分进度', style: AppType.sectionTitle),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: 2,
            childAspectRatio: 2.8,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            children: [
              _MetricTile(
                label: '总学分',
                value: _formatNumber(summary.requiredCredits),
              ),
              _MetricTile(
                label: '已修必修',
                value: _formatNumber(
                  earnedCreditsFor(StudyCreditCategory.compulsory),
                ),
              ),
              _MetricTile(
                label: '已修选修',
                value: _formatNumber(
                  earnedCreditsFor(StudyCreditCategory.elective),
                ),
              ),
              _MetricTile(
                label: '已修校选',
                value: _formatNumber(
                  earnedCreditsFor(StudyCreditCategory.schoolElective),
                ),
              ),
            ],
          ),
          if (stats.failedCourses > 0) ...[
            const SizedBox(height: 12),
            Text(
              '成绩单中有 ${stats.failedCourses} 门课程待关注',
              style: TextStyle(color: AppColors.danger, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _AcademicError extends StatelessWidget {
  const _AcademicError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.danger, size: 36),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

class AcademicStats {
  const AcademicStats({
    required this.totalCourses,
    required this.failedCourses,
    required this.passedCredits,
    this.weightedAverage,
    this.calculatedGpa,
  });

  final int totalCourses;
  final int failedCourses;
  final double passedCredits;
  final double? weightedAverage;
  final double? calculatedGpa;

  static double? parseScore(String text) {
    final cleaned = text.trim();
    final val = double.tryParse(cleaned);
    if (val != null) return val;
    if (cleaned.contains('优')) return 90.0;
    if (cleaned.contains('良')) return 80.0;
    if (cleaned.contains('中')) return 75.0;
    if (cleaned.contains('不及格') ||
        cleaned.contains('不合格') ||
        cleaned == '未通过' ||
        cleaned.toUpperCase() == 'FAIL' ||
        cleaned.toUpperCase() == 'F') {
      return 50.0;
    }
    if (cleaned.contains('及格') ||
        cleaned.contains('合格') ||
        cleaned == '通过' ||
        cleaned.toUpperCase() == 'PASS' ||
        cleaned.toUpperCase() == 'P') {
      return 60.0;
    }
    return null;
  }

  factory AcademicStats.fromGrades(List<Grade> grades) {
    var passedCredits = 0.0;
    var failedCourses = 0;
    var weightedScore = 0.0;
    var weightedScoreCredits = 0.0;
    var weightedGp = 0.0;
    var weightedGpCredits = 0.0;

    for (final grade in grades) {
      final score = parseScore(grade.score);
      final credit = double.tryParse(grade.credits.trim()) ?? 0.0;
      final rawGp = double.tryParse(grade.gradePoint.trim());
      final gp =
          rawGp ??
          (score != null ? ((score >= 60) ? (score - 50) / 10.0 : 0.0) : null);

      if (score != null) {
        if (score >= 60) {
          passedCredits += credit;
        } else {
          failedCourses += 1;
        }
      } else if (gp != null && gp > 0) {
        passedCredits += credit;
      }

      if (credit > 0) {
        if (score != null) {
          weightedScore += score * credit;
          weightedScoreCredits += credit;
        }
        if (gp != null) {
          weightedGp += gp * credit;
          weightedGpCredits += credit;
        }
      }
    }

    return AcademicStats(
      totalCourses: grades.length,
      failedCourses: failedCourses,
      passedCredits: passedCredits,
      weightedAverage: weightedScoreCredits == 0
          ? null
          : weightedScore / weightedScoreCredits,
      calculatedGpa: weightedGpCredits == 0
          ? null
          : weightedGp / weightedGpCredits,
    );
  }
}

String _formatNumber(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(1);
}
