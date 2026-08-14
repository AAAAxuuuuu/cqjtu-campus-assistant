part of '../profile_page.dart';

// ══════════════════════════════════════════════════════════════
// ══════════════════════════════════════════════════════════════
class _AppUpdateCard extends StatefulWidget {
  const _AppUpdateCard();

  @override
  State<_AppUpdateCard> createState() => _AppUpdateCardState();
}

class _AppUpdateCardState extends State<_AppUpdateCard> {
  String _versionLabel = '读取中...';
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _loadVersionLabel();
  }

  Future<void> _loadVersionLabel() async {
    try {
      final label = await AppUpdateCoordinator.currentVersionLabel();
      if (!mounted) return;
      setState(() => _versionLabel = label);
    } catch (_) {
      if (!mounted) return;
      setState(() => _versionLabel = '读取失败');
    }
  }

  Future<void> _checkUpdate() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      await AppUpdateCoordinator.checkAndPrompt(context, manual: true);
    } finally {
      if (mounted) {
        setState(() => _checking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.brandedCardDecoration(),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.info.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: const Icon(Icons.system_update_alt, color: AppColors.info),
        ),
        title: const Text(
          '检查更新',
          style: TextStyle(fontSize: 15, color: AppColors.textPrimary),
        ),
        subtitle: Text(
          '当前版本：$_versionLabel\n发现新版本后可直接打开下载链接',
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textMuted,
            height: 1.45,
          ),
        ),
        trailing: _checking
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : FilledButton.tonal(
                onPressed: _checkUpdate,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('检查', style: TextStyle(fontSize: 13)),
              ),
        onTap: _checkUpdate,
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 后台设置卡片
// ══════════════════════════════════════════════════════════════
class _BackgroundSettingsCard extends ConsumerStatefulWidget {
  const _BackgroundSettingsCard();

  @override
  ConsumerState<_BackgroundSettingsCard> createState() =>
      _BackgroundSettingsCardState();
}

class _BackgroundSettingsCardState
    extends ConsumerState<_BackgroundSettingsCard>
    with WidgetsBindingObserver {
  bool? _isIgnoring;
  bool? _autostartAppOps;
  bool _autostartOpened = false;
  bool _lockBackgroundDone = false;
  bool _backgroundSettingsExpanded = false;
  bool? _courseReminderEnabled;
  int? _courseReminderMinutes;
  int? _reminderCoverageUntilMs;

  static const _autostartOpenedKey = 'autostart_page_opened';
  static const _lockBackgroundDoneKey = 'lock_background_done';

  static const List<int> _reminderMinuteOptions = [
    15,
    20,
    25,
    30,
    35,
    40,
    45,
    50,
    55,
    60,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshStatus();
    _loadLocalFlags();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshStatus();
      _loadLocalFlags();
    }
  }

  Future<void> _refreshStatus() async {
    final accountId = ref.read(credentialsProvider)?.username;
    final ignoring =
        await BatteryOptimizationService.isIgnoringBatteryOptimizations();
    final autostart = await BatteryOptimizationService.checkMiuiAutostart();
    final courseReminder = await NotificationService.getCourseReminderEnabled(
      accountId: accountId,
    );
    final courseReminderMinutes =
        await NotificationService.getCourseReminderMinutes(
          accountId: accountId,
        );
    final coverageUntil = await NotificationService.reminderCoverageUntilMs();
    if (mounted) {
      setState(() {
        _isIgnoring = ignoring;
        _autostartAppOps = autostart;
        _courseReminderEnabled = courseReminder;
        _courseReminderMinutes = courseReminderMinutes;
        _reminderCoverageUntilMs = coverageUntil;
      });
    }
  }

  Future<void> _loadLocalFlags() async {
    final prefs = await SharedPreferences.getInstance();
    final autostartOpened = prefs.getBool(_autostartOpenedKey) ?? false;
    final lockBackgroundDone = prefs.getBool(_lockBackgroundDoneKey) ?? false;
    if (mounted) {
      if (_autostartOpened == autostartOpened &&
          _lockBackgroundDone == lockBackgroundDone) {
        return;
      }
      setState(() {
        _autostartOpened = autostartOpened;
        _lockBackgroundDone = lockBackgroundDone;
      });
    }
  }

  Future<void> _markAutostartOpened() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autostartOpenedKey, true);
    if (mounted) {
      setState(() => _autostartOpened = true);
    }
  }

  Future<void> _markLockBackgroundDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_lockBackgroundDoneKey, true);
    if (mounted) {
      setState(() => _lockBackgroundDone = true);
    }
  }

  bool get _autostartDone => _autostartAppOps == true || _autostartOpened;
  bool get _backgroundSetupCompleted =>
      _isIgnoring == true && _autostartDone && _lockBackgroundDone;
  bool get _showCompactBackgroundCard =>
      _backgroundSetupCompleted && !_backgroundSettingsExpanded;

  String get _autostartSubtitle {
    if (_autostartAppOps == true) return '✅ 已开启，App 可开机自启';
    if (_autostartOpened) return '✅ 已操作，请确认页面内已开启';
    return '允许 App 开机自启，确保后台轮询不中断';
  }

  Future<bool> _rescheduleCourseReminders({String? successMessage}) async {
    final accountId = ref.read(credentialsProvider)?.username;
    final semesterStart = ref.read(activeSemesterStartProvider).valueOrNull;
    final selectedSemester = ref
        .read(selectedScheduleSemesterProvider)
        .valueOrNull;
    final totalWeeks =
        ref.read(semesterTotalWeeksProvider(selectedSemester)).valueOrNull ??
        defaultSemesterTotalWeeks;

    if (semesterStart == null) {
      debugPrint('[Profile] 开启失败：尚未设置开学日期');
      if (mounted) {
        AppSnackBar.warning(context, '请先在课程表页面设置开学日期');
      }
      return false;
    }

    try {
      final scheduleResult =
          (await ref
                  .read(scheduleProvider(selectedSemester).notifier)
                  .refresh(forceRefresh: true, throwOnError: true))
              .data;
      final calendarRules = await ref.read(
        scheduleCalendarRulesProvider.future,
      );
      await NotificationService.scheduleClassReminders(
        scheduleResult.courses,
        semesterStart,
        totalWeeks: totalWeeks,
        calendarRules: calendarRules,
        accountId: accountId,
      );
      await ScheduleWidgetService.updateScheduleWidgets(
        courses: scheduleResult.courses,
        semesterStart: semesterStart,
        selectedSemester: selectedSemester,
        remark: scheduleResult.remark,
        totalWeeks: totalWeeks,
        calendarRules: calendarRules,
      );

      if (successMessage != null && mounted) {
        AppSnackBar.success(context, successMessage);
      }
      return true;
    } catch (e) {
      debugPrint('[Profile] 调度失败（拉取课表出错）：$e');
      if (mounted) {
        AppSnackBar.error(context, '课表获取失败，请稍后重试');
      }
      return false;
    }
  }

  String? _coverageText() {
    final until = _reminderCoverageUntilMs;
    if (until == null || until <= 0) return null;
    final date = DateTime.fromMillisecondsSinceEpoch(until);
    return ' · 提醒已排到 ${date.month}月${date.day}日';
  }

  Future<void> _onReminderMinutesSelected(int minutes) async {
    if (_courseReminderMinutes == minutes) return;

    await NotificationService.setCourseReminderMinutes(
      minutes,
      accountId: ref.read(credentialsProvider)?.username,
    );
    if (mounted) {
      setState(() => _courseReminderMinutes = minutes);
    }

    if (_courseReminderEnabled == true) {
      final ok = await _rescheduleCourseReminders();
      if (ok && mounted) {
        AppSnackBar.success(context, '课前提醒已改为提前 $minutes 分钟');
      }
    } else if (mounted) {
      AppSnackBar.status(context, '已保存为提前 $minutes 分钟，开启课前提醒后生效');
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentReminderMinutes =
        _courseReminderMinutes ??
        NotificationService.defaultCourseReminderMinutes;

    return Container(
      decoration: AppTheme.brandedCardDecoration(),
      child: Column(
        children: [
          _SettingTile(
            icon: Icons.notifications_active_outlined,
            iconColor: _courseReminderEnabled == true
                ? AppColors.warning
                : AppColors.textMuted,
            title: '课程表课前通知',
            subtitleWidget:
                _courseReminderEnabled == null || _courseReminderMinutes == null
                ? const Text(
                    '加载中...',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  )
                : Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        _courseReminderEnabled == true
                            ? '✅ 已开启，课前 $currentReminderMinutes 分钟提醒${_coverageText() ?? ''}'
                            : '预警已关闭（默认提前 $currentReminderMinutes 分钟）',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                      PopupMenuButton<int>(
                        initialValue: currentReminderMinutes,
                        tooltip: '设置提醒提前时间',
                        onSelected: _onReminderMinutesSelected,
                        itemBuilder: (context) => _reminderMinuteOptions
                            .map(
                              (m) => PopupMenuItem<int>(
                                value: m,
                                child: Text('提前 $m 分钟'),
                              ),
                            )
                            .toList(),
                        child: const Text(
                          '修改',
                          style: TextStyle(
                            color: AppColors.info,
                            fontSize: 12,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
            trailing: _courseReminderEnabled == null
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Switch(
                    value: _courseReminderEnabled!,
                    activeThumbColor: AppColors.warning,
                    onChanged: (val) async {
                      await NotificationService.setCourseReminderEnabled(
                        val,
                        accountId: ref.read(credentialsProvider)?.username,
                      );
                      setState(() => _courseReminderEnabled = val);

                      if (!val) {
                        await NotificationService.cancelAllClassReminders();
                        debugPrint('[Profile] 课前通知已关闭，所有调度已清空');
                        if (!context.mounted) return;
                        AppSnackBar.status(context, '课前提醒已关闭');
                      } else {
                        final minutes =
                            _courseReminderMinutes ??
                            NotificationService.defaultCourseReminderMinutes;
                        await _rescheduleCourseReminders(
                          successMessage: '课前提醒已开启（提前 $minutes 分钟）',
                        );
                      }
                    },
                  ),
          ),
          const Divider(height: 1, indent: 56, color: AppColors.outline),
          if (_showCompactBackgroundCard)
            _buildCompactBackgroundCard()
          else ...[
            if (_backgroundSetupCompleted)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 2,
                ),
                leading: const Icon(
                  Icons.verified_outlined,
                  color: AppColors.success,
                ),
                title: const Text(
                  '后台保活设置已完成',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  '电池优化、自启动、锁后台均已完成',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
                trailing: TextButton(
                  onPressed: () =>
                      setState(() => _backgroundSettingsExpanded = false),
                  child: const Text('收起'),
                ),
              ),
            if (_backgroundSetupCompleted)
              const Divider(height: 1, indent: 56, color: AppColors.outline),
            _SettingTile(
              icon: Icons.battery_saver_outlined,
              iconColor: _isIgnoring == true
                  ? AppColors.success
                  : AppColors.warning,
              title: '关闭电池优化',
              subtitle: _isIgnoring == null
                  ? '检测中...'
                  : _isIgnoring!
                  ? '✅ 已设置，后台任务可正常运行'
                  : '⚠️ 未设置，后台通知可能无法推送',
              trailing: _isIgnoring == true
                  ? const Icon(
                      Icons.check_circle,
                      color: AppColors.success,
                      size: 20,
                    )
                  : FilledButton.tonal(
                      onPressed: () async {
                        await BatteryOptimizationService.requestIgnoreBatteryOptimizations();
                        await Future.delayed(const Duration(seconds: 1));
                        _refreshStatus();
                      },
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('去设置', style: TextStyle(fontSize: 13)),
                    ),
            ),
            const Divider(height: 1, indent: 56, color: AppColors.outline),
            _SettingTile(
              icon: Icons.autorenew_outlined,
              iconColor: _autostartDone ? AppColors.info : AppColors.textMuted,
              title: '开启自启动',
              subtitle: _autostartSubtitle,
              trailing: _autostartDone
                  ? Icon(
                      _autostartAppOps == true
                          ? Icons.check_circle
                          : Icons.check_circle_outline,
                      color: _autostartAppOps == true
                          ? AppColors.success
                          : AppColors.warning,
                      size: 20,
                    )
                  : OutlinedButton(
                      onPressed: () async {
                        await _markAutostartOpened();
                        await BatteryOptimizationService.openMiuiAutostart();
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('去设置', style: TextStyle(fontSize: 13)),
                    ),
            ),
            const Divider(height: 1, indent: 56, color: AppColors.outline),
            _SettingTile(
              icon: Icons.lock_outline,
              iconColor: _lockBackgroundDone
                  ? AppColors.success
                  : AppColors.secondary,
              title: '锁定后台',
              subtitle: _lockBackgroundDone
                  ? '✅ 已完成，后台任务更稳定'
                  : '在最近任务界面长按本应用 → 锁定，防止被清理',
              trailing: Icon(
                _lockBackgroundDone ? Icons.check_circle : Icons.info_outline,
                color: _lockBackgroundDone
                    ? AppColors.success
                    : AppColors.textMuted,
                size: 20,
              ),
              onTap: () => _showLockGuideDialog(context),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompactBackgroundCard() {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: const Icon(Icons.verified_outlined, color: AppColors.success),
      ),
      title: const Text(
        '后台保活设置已完成',
        style: TextStyle(fontSize: 15, color: AppColors.textPrimary),
      ),
      subtitle: const Text(
        '电池优化、自启动、锁后台均已完成',
        style: TextStyle(fontSize: 12, color: AppColors.textMuted),
      ),
      trailing: TextButton(
        onPressed: () => setState(() => _backgroundSettingsExpanded = true),
        child: const Text('展开'),
      ),
      onTap: () => setState(() => _backgroundSettingsExpanded = true),
    );
  }

  Future<void> _showLockGuideDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.lock_outline, color: AppColors.secondary),
            SizedBox(width: 8),
            Text('如何锁定后台'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('系统会定期清理后台任务。\n锁定步骤：'),
            SizedBox(height: 12),
            _GuideStep(step: '1', text: '点击底部"方块"按钮，打开最近任务'),
            SizedBox(height: 8),
            _GuideStep(step: '2', text: '找到「校园助手」卡片'),
            SizedBox(height: 8),
            _GuideStep(step: '3', text: '下拉卡片，点击锁形图标 🔒'),
            SizedBox(height: 8),
            _GuideStep(step: '4', text: '卡片右上角出现锁图标即成功'),
            SizedBox(height: 12),
            Text(
              '锁定后 App 不会被"清理全部"按钮关闭，后台余额监控将持续运行。',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('我已锁定'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _markLockBackgroundDone();
    if (!context.mounted) return;
    AppSnackBar.success(context, '已标记为完成锁定后台');
  }
}

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Widget? subtitleWidget;
  final Widget trailing;
  final VoidCallback? onTap;

  const _SettingTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.subtitleWidget,
    required this.trailing,
    this.onTap,
  }) : assert(subtitle != null || subtitleWidget != null);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor),
      ),
      title: Text(
        title,
        style: const TextStyle(fontSize: 15, color: AppColors.textPrimary),
      ),
      subtitle:
          subtitleWidget ??
          Text(
            subtitle!,
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
      trailing: trailing,
      onTap: onTap,
    );
  }
}

class _GuideStep extends StatelessWidget {
  final String step;
  final String text;
  const _GuideStep({required this.step, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.secondary.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Text(
            step,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppColors.secondary,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
      ],
    );
  }
}
