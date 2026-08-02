import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/study_progress/study_progress_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/background_refresh_banner.dart';
import '../widgets/glass_surface.dart';
import '../widgets/spinning_refresh_button.dart';
import 'tools_page.dart' show GradeDetailPage;

class StudyProgressPage extends ConsumerStatefulWidget {
  const StudyProgressPage({super.key});

  @override
  ConsumerState<StudyProgressPage> createState() => _StudyProgressPageState();
}

class _StudyProgressPageState extends ConsumerState<StudyProgressPage> {
  String _query = '';
  StudyCourseStatus? _statusFilter;

  @override
  Widget build(BuildContext context) {
    final resource = ref.watch(studyProgressProvider);
    final notifier = ref.read(studyProgressProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: GlassAppBar(
        title: const Text('培养计划'),
        actions: [
          SpinningRefreshButton(
            tooltip: '刷新',
            onPressed: () => notifier.refresh(forceRefresh: true),
          ),
        ],
      ),
      body: Builder(
        builder: (context) {
          if (!resource.hasData && resource.isRefreshing) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!resource.hasData && resource.hasError) {
            return _ErrorState(
              message: resource.error.toString(),
              onRetry: () => notifier.refresh(forceRefresh: true),
            );
          }

          final data = resource.data;
          final sections = _filterSections(data);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              if (resource.shouldOfferManualRefresh)
                BackgroundRefreshBanner(
                  onRefresh: () => notifier.refresh(forceRefresh: true),
                ),
              _SummaryPanel(
                currentSemester: data.currentSemester,
                completedCount: data.completedCount,
                inProgressCount: data.inProgressCount,
                pendingCount: data.pendingCount,
              ),
              const SizedBox(height: 16),
              _FilterBar(
                query: _query,
                statusFilter: _statusFilter,
                onQueryChanged: (value) => setState(() => _query = value),
                onStatusChanged: (value) =>
                    setState(() => _statusFilter = value),
              ),
              const SizedBox(height: 18),
              if (sections.isEmpty)
                const _EmptyState()
              else
                for (final section in sections) ...[
                  _SectionBlock(
                    section: section,
                    onOpenGrade: _openGradeDetail,
                  ),
                  const SizedBox(height: 14),
                ],
            ],
          );
        },
      ),
    );
  }

  List<StudyProgressSectionView> _filterSections(StudyProgressViewData data) {
    final query = _query.trim().replaceAll(RegExp(r'\s+'), '').toLowerCase();
    return data.sections
        .map((section) {
          final courses = section.courses.where((course) {
            final matchesQuery =
                query.isEmpty ||
                course.name
                    .replaceAll(RegExp(r'\s+'), '')
                    .toLowerCase()
                    .contains(query) ||
                course.attribute
                    .replaceAll(RegExp(r'\s+'), '')
                    .toLowerCase()
                    .contains(query);
            final matchesStatus =
                _statusFilter == null || course.status == _statusFilter;
            return matchesQuery && matchesStatus;
          }).toList();

          return StudyProgressSectionView(
            id: section.id,
            title: section.title,
            creditCategory: section.creditCategory,
            requiredCredits: section.requiredCredits,
            earnedCredits: section.earnedCredits,
            remainingCredits: section.remainingCredits,
            completionRate: section.completionRate,
            courses: courses,
          );
        })
        .where((section) => section.courses.isNotEmpty)
        .toList();
  }

  void _openGradeDetail(StudyProgressCourseView course) {
    final grade = course.grade;
    if (grade == null || !grade.hasDetail) return;

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GradeDetailPage(grade: grade)),
    );
  }
}

class _SummaryPanel extends StatelessWidget {
  const _SummaryPanel({
    required this.currentSemester,
    required this.completedCount,
    required this.inProgressCount,
    required this.pendingCount,
  });

  final String currentSemester;
  final int completedCount;
  final int inProgressCount;
  final int pendingCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.outline.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '课程分类总览',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            currentSemester.isEmpty ? '当前学期未识别' : '当前学期 $currentSemester',
            style: const TextStyle(color: AppColors.textMuted),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _MetricChip(
                  label: '已修读',
                  value: completedCount.toString(),
                  foreground: AppColors.success,
                  background: AppColors.success.withValues(alpha: 0.12),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricChip(
                  label: '修读中',
                  value: inProgressCount.toString(),
                  foreground: AppColors.info,
                  background: AppColors.info.withValues(alpha: 0.12),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricChip(
                  label: '未修读',
                  value: pendingCount.toString(),
                  foreground: AppColors.danger,
                  background: AppColors.danger.withValues(alpha: 0.12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.label,
    required this.value,
    required this.foreground,
    required this.background,
  });

  final String label;
  final String value;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: foreground,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.query,
    required this.statusFilter,
    required this.onQueryChanged,
    required this.onStatusChanged,
  });

  final String query;
  final StudyCourseStatus? statusFilter;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<StudyCourseStatus?> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          initialValue: query,
          onChanged: onQueryChanged,
          decoration: InputDecoration(
            hintText: '搜索课程名称或属性',
            prefixIcon: const Icon(Icons.search),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _FilterChip(
              label: '全部',
              selected: statusFilter == null,
              onTap: () => onStatusChanged(null),
            ),
            _FilterChip(
              label: '已修读',
              selected: statusFilter == StudyCourseStatus.completed,
              onTap: () => onStatusChanged(StudyCourseStatus.completed),
            ),
            _FilterChip(
              label: '修读中',
              selected: statusFilter == StudyCourseStatus.inProgress,
              onTap: () => onStatusChanged(StudyCourseStatus.inProgress),
            ),
            _FilterChip(
              label: '未修读',
              selected: statusFilter == StudyCourseStatus.pending,
              onTap: () => onStatusChanged(StudyCourseStatus.pending),
            ),
          ],
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.quick,
        curve: AppMotion.easeOutStrong,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.outline,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.textBody,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _SectionBlock extends StatelessWidget {
  const _SectionBlock({required this.section, required this.onOpenGrade});

  final StudyProgressSectionView section;
  final ValueChanged<StudyProgressCourseView> onOpenGrade;

  @override
  Widget build(BuildContext context) {
    final progressText = [
      if (section.earnedCredits.isNotEmpty) '已获 ${section.earnedCredits}',
      if (section.requiredCredits.isNotEmpty) '要求 ${section.requiredCredits}',
      if (section.completionRate.isNotEmpty) section.completionRate,
    ].join('  ');

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.outline.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            decoration: BoxDecoration(
              color: AppColors.tint.withValues(alpha: 0.25),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppRadius.lg),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  section.title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (progressText.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    progressText,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          for (var i = 0; i < section.courses.length; i++) ...[
            _CourseRow(
              course: section.courses[i],
              onOpenGrade: () => onOpenGrade(section.courses[i]),
            ),
            if (i != section.courses.length - 1)
              Divider(height: 1, color: AppColors.outline.withValues(alpha: 0.6)),
          ],
        ],
      ),
    );
  }
}

class _CourseRow extends StatelessWidget {
  const _CourseRow({required this.course, required this.onOpenGrade});

  final StudyProgressCourseView course;
  final VoidCallback onOpenGrade;

  @override
  Widget build(BuildContext context) {
    final scoreInteractive = course.grade?.hasDetail == true;
    return InkWell(
      onTap: () => _showCourseSheet(context, course),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    course.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textBody,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _SmallTag(label: '${course.credits} 学分'),
                      _SmallTag(label: course.attribute),
                      _StatusTag(
                        status: course.status,
                        label: course.statusLabel,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            InkWell(
              onTap: scoreInteractive ? onOpenGrade : null,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: scoreInteractive
                      ? AppColors.secondary.withValues(alpha: 0.12)
                      : AppColors.outline.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      course.scoreLabel,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: scoreInteractive
                            ? AppColors.secondary
                            : AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      scoreInteractive ? '查看明细' : '暂无明细',
                      style: TextStyle(
                        fontSize: 11,
                        color: scoreInteractive
                            ? AppColors.secondary.withValues(alpha: 0.8)
                            : AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallTag extends StatelessWidget {
  const _SmallTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.outline.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.textMuted,
        ),
      ),
    );
  }
}

class _StatusTag extends StatelessWidget {
  const _StatusTag({required this.status, required this.label});

  final StudyCourseStatus status;
  final String label;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (status) {
      StudyCourseStatus.completed => (
        AppColors.success.withValues(alpha: 0.12),
        AppColors.success,
      ),
      StudyCourseStatus.inProgress => (
        AppColors.info.withValues(alpha: 0.12),
        AppColors.info,
      ),
      StudyCourseStatus.pending => (
        AppColors.danger.withValues(alpha: 0.12),
        AppColors.danger,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 36),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.outline.withValues(alpha: 0.7)),
      ),
      child: const Center(
        child: Text(
          '当前筛选下没有可展示的课程',
          style: TextStyle(color: AppColors.textMuted),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

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
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

void _showCourseSheet(BuildContext context, StudyProgressCourseView course) {
  showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            course.name,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          _SheetRow(label: '学分', value: course.credits),
          _SheetRow(label: '属性', value: course.attribute),
          _SheetRow(label: '修读情况', value: course.statusLabel),
          _SheetRow(label: '成绩', value: course.scoreLabel),
          if (course.code.trim().isNotEmpty)
            _SheetRow(label: '课程编号', value: course.code),
          if (course.semester.trim().isNotEmpty)
            _SheetRow(label: '修读学期', value: course.semester),
        ],
      ),
    ),
  );
}

class _SheetRow extends StatelessWidget {
  const _SheetRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.textMuted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
