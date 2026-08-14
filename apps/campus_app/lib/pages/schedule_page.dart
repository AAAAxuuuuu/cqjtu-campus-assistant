import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:core/models/course.dart';
import 'package:core/models/schedule_calendar_rules.dart';
import 'package:core/utils/schedule_time_utils.dart';
import 'package:campus_platform/services/notification_service.dart';
import 'package:campus_platform/services/schedule_widget_service.dart';
import '../features/schedule/schedule_export_service.dart';
import 'package:core/utils/course_text_parser.dart';
import '../theme/app_theme.dart';
import '../utils/campus_error_message.dart';
import '../utils/providers.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/background_refresh_banner.dart';
import '../widgets/course_cell.dart';
import '../widgets/error_view.dart';
import '../widgets/glass_surface.dart';
import 'webview_login_page.dart';

part 'schedule/schedule_utils.dart';
part 'schedule/schedule_sheets.dart';
part 'schedule/schedule_add_course.dart';
part 'schedule/schedule_grid.dart';
part 'schedule/schedule_week_navigator.dart';

class SchedulePage extends ConsumerWidget {
  const SchedulePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedSemesterAsync = ref.watch(selectedScheduleSemesterProvider);
    final selectedSemester = selectedSemesterAsync.valueOrNull;
    final semesterAsync = ref.watch(activeSemesterStartProvider);
    final sundayFirst =
        ref.watch(scheduleSundayFirstProvider).valueOrNull ?? false;
    final totalWeeks =
        ref.watch(semesterTotalWeeksProvider(selectedSemester)).valueOrNull ??
        defaultSemesterTotalWeeks;
    final density =
        ref.watch(scheduleDensityProvider).valueOrNull ??
        ScheduleDensity.standard;
    final backgroundImagePath = ref
        .watch(scheduleBackgroundImageProvider)
        .valueOrNull;

    ref.listen<AsyncValue<DateTime?>>(activeSemesterStartProvider, (_, next) {
      final start = next.valueOrNull;
      if (start != null) {
        ref
            .read(selectedWeekProvider.notifier)
            .setWeek(
              _calcCurrentWeek(
                start,
                sundayFirst: sundayFirst,
                totalWeeks: totalWeeks,
              ),
            );
      }
    });

    final semesterStart = semesterAsync.valueOrNull;
    if (semesterStart == null) {
      return const _NoSemesterPage();
    }

    return _ScheduleBody(
      semesterStart: semesterStart,
      selectedSemester: selectedSemester,
      sundayFirst: sundayFirst,
      totalWeeks: totalWeeks,
      density: density,
      backgroundImagePath: backgroundImagePath,
    );
  }
}

// ── 未设置开学日期引导页 ─────────────────────────────────────
class _NoSemesterPage extends ConsumerWidget {
  const _NoSemesterPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: GlassAppBar(
        centerTitle: false,
        title: const Text(
          '课程表',
          style: TextStyle(color: AppColors.textPrimary),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.calendar_today_outlined,
                size: 64,
                color: AppColors.textMuted.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 20),
              const Text(
                '尚未设置开学日期',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '设置开学日期后，将自动识别学期并获取课表。',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, height: 1.5),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                icon: const Icon(Icons.edit_calendar_outlined),
                label: const Text('选择开学日期'),
                onPressed: () => _pickSemesterStart(context, ref),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 课程表主体 ────────────────────────────────────────────────
class _ScheduleBody extends ConsumerWidget {
  final DateTime semesterStart;
  final String? selectedSemester;
  final bool sundayFirst;
  final int totalWeeks;
  final ScheduleDensity density;
  final String? backgroundImagePath;

  const _ScheduleBody({
    required this.semesterStart,
    this.selectedSemester,
    required this.sundayFirst,
    required this.totalWeeks,
    required this.density,
    required this.backgroundImagePath,
  });

  // ── 统一的刷新逻辑（包含验证码拦截和 WebView 处理）──────────────────
  Future<void> _doRefresh(BuildContext context, WidgetRef ref) async {
    final creds = ref.read(credentialsProvider);
    if (creds == null) return;

    try {
      AppSnackBar.status(context, '正在同步最新课表...');

      // 强制后端发起请求
      final result =
          (await ref
                  .read(scheduleProvider(selectedSemester).notifier)
                  .refresh(forceRefresh: true, throwOnError: true))
              .data;

      // 刷新本地状态
      debugPrint('[刷新] 课表已更新，重新调度课程通知...');
      final calendarRules = await ref.read(
        scheduleCalendarRulesProvider.future,
      );
      await NotificationService.scheduleClassReminders(
        result.courses,
        semesterStart,
        totalWeeks: totalWeeks,
        calendarRules: calendarRules,
        accountId: creds.username,
      );
      await ScheduleWidgetService.updateScheduleWidgets(
        courses: result.courses,
        semesterStart: semesterStart,
        selectedSemester: selectedSemester,
        remark: result.remark,
        totalWeeks: totalWeeks,
        calendarRules: calendarRules,
      );

      if (context.mounted) {
        AppSnackBar.success(context, '课表已更新');
      }
    } catch (e) {
      final errorStr = e.toString();
      // 如果报错内容提示需要验证码，唤起 WebView
      if (errorStr.contains('449') ||
          errorStr.contains('验证码') ||
          errorStr.contains('HTML') ||
          errorStr.contains('CAS')) {
        if (context.mounted) {
          final result = await Navigator.of(context).push<Map<String, dynamic>>(
            MaterialPageRoute(
              builder: (_) => WebViewLoginPage(
                username: creds.username,
                password: creds.password,
              ),
            ),
          );

          // WebView 登录成功，拿到了 Cookies
          if (result != null && context.mounted) {
            try {
              await ref
                  .read(webLoginBinderProvider)
                  .bind(username: creds.username, result: result);
            } catch (injectErr) {
              if (context.mounted) {
                AppSnackBar.error(context, '会话恢复失败: $injectErr');
              }
            }
          }
        }
      } else {
        // 普通的网络错误直接提示
        if (context.mounted) {
          AppSnackBar.error(context, '刷新失败：${formatCampusError(e)}');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheduleAsync = ref.watch(scheduleProvider(selectedSemester));
    final showInactiveCourses =
        ref.watch(scheduleShowInactiveCoursesProvider).valueOrNull ?? true;
    final calendarRules =
        ref.watch(scheduleCalendarRulesProvider).valueOrNull ??
        ScheduleCalendarRules.empty;
    final selectedWeek = ref.watch(selectedWeekProvider);
    final currentWeek = _calcCurrentWeek(
      semesterStart,
      sundayFirst: sundayFirst,
      totalWeeks: totalWeeks,
    );
    final scheduleData = scheduleAsync.valueOrNull;

    final semLabel = selectedSemester != null
        ? _semesterLabel(selectedSemester!)
        : '设置学期开学日期';

    return Scaffold(
      appBar: GlassAppBar(
        centerTitle: false,
        title: const Text(
          '课程表',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.edit_calendar, size: 16),
            label: Text(
              semLabel,
              style: TextStyle(
                fontSize: 12,
                color: selectedSemester != null
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => _pickSemesterStart(context, ref),
          ),
          if (selectedWeek != currentWeek)
            TextButton(
              onPressed: () =>
                  ref.read(selectedWeekProvider.notifier).setWeek(currentWeek),
              child: const Text('回本周'),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            // ✅ 将右上角的刷新也指向通用的 _doRefresh
            onPressed: () => _doRefresh(context, ref),
          ),
          IconButton(
            tooltip: '更多课程表功能',
            icon: const Icon(Icons.more_horiz),
            onPressed: scheduleData == null
                ? null
                : () => _showScheduleMoreSheet(
                    context,
                    ref,
                    courses: scheduleData.courses,
                    semesterStart: semesterStart,
                    sundayFirst: sundayFirst,
                    totalWeeks: totalWeeks,
                    semesterLabel: semLabel,
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('新增课程'),
        onPressed: () => _showAddCustomCourseSheet(
          context,
          ref,
          selectedSemester,
          totalWeeks,
        ),
      ),
      body: scheduleAsync.when(
        skipError: true,
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) {
          String errMsg = e.toString();
          // ✅ 错误提示美化：去掉乱码，转换为直观提示
          if (errMsg.contains('449') ||
              errMsg.contains('验证码') ||
              errMsg.contains('HTML') ||
              errMsg.contains('CAS')) {
            errMsg = '系统会话已过期或需要安全验证\n请点击下方重试按钮进行验证';
          } else {
            errMsg = errMsg.replaceAll('Exception: ', '');
          }

          return ErrorView(
            message: errMsg,
            // ✅ 将屏幕中间的重试按钮也指向 _doRefresh
            onRetry: () => _doRefresh(context, ref),
          );
        },
        data: (result) => Column(
          children: [
            if (scheduleAsync.shouldOfferManualRefresh)
              BackgroundRefreshBanner(
                onRefresh: () => _doRefresh(context, ref),
              ),
            _WeekNavigator(
              semesterStart: semesterStart,
              selectedWeek: selectedWeek,
              currentWeek: currentWeek,
              sundayFirst: sundayFirst,
              totalWeeks: totalWeeks,
            ),
            Expanded(
              child: _TimetableGrid(
                courses: _coursesForDisplayedWeek(
                  courses: result.courses,
                  semesterStart: semesterStart,
                  selectedWeek: selectedWeek,
                  totalWeeks: totalWeeks,
                  calendarRules: calendarRules,
                  includeInactiveCourses: showInactiveCourses,
                ),
                remark: result.remark,
                semesterStart: semesterStart,
                selectedWeek: selectedWeek,
                sundayFirst: sundayFirst,
                totalWeeks: totalWeeks,
                selectedSemester: selectedSemester,
                showInactiveCourses: showInactiveCourses,
                density: density,
                backgroundImagePath: backgroundImagePath,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 以下其余部分保持不变 (选期逻辑、导航栏、表格绘制等) ─────────────────────────────────────────
