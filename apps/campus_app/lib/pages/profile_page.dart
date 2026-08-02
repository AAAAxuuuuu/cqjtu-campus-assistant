import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../utils/providers.dart';
import '../widgets/app_entrance.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/glass_surface.dart';
import 'package:campus_platform/services/credential_service.dart';
import 'package:campus_platform/services/notification_service.dart';
import 'package:campus_platform/services/battery_optimization_service.dart';
import 'package:campus_platform/services/schedule_widget_service.dart';
import 'package:core/models/dorm_room.dart';
import '../services/app_update_coordinator.dart';
import '../services/webview_session_scope.dart';
import 'login_page.dart';
import 'electricity_page.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  void _logout(BuildContext context, WidgetRef ref) async {
    await WebViewSessionScope.clearOnLogout();

    ref.invalidate(sessionManagerProvider);
    ref.invalidate(campusGatewayProvider);
    await ref.read(credentialServiceProvider).clear();
    ref.read(credentialsProvider.notifier).clear();
    ref.read(payCodeProvider.notifier).clear();
    resetAccountBoundProviders(ref);

    await NotificationService.cancelAllClassReminders();
    await ScheduleWidgetService.clearScheduleWidgets();
    debugPrint('[Profile] 账号已退出，所有状态与本地通知调度已清空');

    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final creds = ref.watch(credentialsProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: GlassAppBar(
        title: const Text('我的', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        children: [
          AppEntrance(
            child: _buildUserInfoCard(creds?.username ?? '未登录'),
          ),
          const SizedBox(height: 20),
          AppEntrance(
            index: 1,
            child: const _ElectricityCardWidget(),
          ),
          const SizedBox(height: 20),
          AppEntrance(
            index: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionLabel('宿舍设置'),
                const _DormSettingsCard(),
              ],
            ),
          ),
          const SizedBox(height: 20),
          AppEntrance(
            index: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionLabel('课表偏好'),
                const _SchedulePreferenceCard(),
              ],
            ),
          ),
          const SizedBox(height: 20),
          AppEntrance(
            index: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionLabel('数据与缓存'),
                const _CacheSettingsCard(),
              ],
            ),
          ),
          const SizedBox(height: 20),
          AppEntrance(
            index: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionLabel('通知与后台'),
                const _BackgroundSettingsCard(),
              ],
            ),
          ),
          const SizedBox(height: 20),
          AppEntrance(
            index: 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionLabel('版本更新'),
                const _AppUpdateCard(),
              ],
            ),
          ),
          const SizedBox(height: 30),
          AppEntrance(
            index: 7,
            child: _buildLogoutButton(context, ref),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary,
      ),
    ),
  );

  Widget _buildUserInfoCard(String username) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.hero),
        gradient: AppColors.primaryGradient,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -15,
            bottom: -20,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                  child: const CircleAvatar(
                    radius: 32,
                    backgroundColor: Colors.white,
                    child: Icon(Icons.person, size: 38, color: AppColors.primary),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        username,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.3),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.school, size: 13, color: Colors.white),
                                SizedBox(width: 4),
                                Text(
                                  '重庆交通大学',
                                  style: TextStyle(fontSize: 11.5, color: Colors.white, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoutButton(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton.icon(
        icon: const Icon(Icons.logout, size: 18),
        label: const Text('退出登录', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: BorderSide(color: AppColors.primary.withValues(alpha: 0.5), width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          backgroundColor: Colors.white,
        ),
        onPressed: () {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Row(
                children: [
                  Icon(Icons.logout, color: AppColors.primary),
                  SizedBox(width: 8),
                  Text('退出登录'),
                ],
              ),
              content: const Text('确定要退出当前账号吗？'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消', style: TextStyle(color: AppColors.textMuted)),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _logout(context, ref);
                  },
                  child: const Text('确定退出'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SchedulePreferenceCard extends ConsumerWidget {
  const _SchedulePreferenceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sundayFirstAsync = ref.watch(scheduleSundayFirstProvider);
    final sundayFirst = sundayFirstAsync.valueOrNull ?? false;
    final showInactiveAsync = ref.watch(scheduleShowInactiveCoursesProvider);
    final showInactive = showInactiveAsync.valueOrNull ?? true;
    final selectedSemester = ref
        .watch(selectedScheduleSemesterProvider)
        .valueOrNull;
    final totalWeeksAsync = ref.watch(
      semesterTotalWeeksProvider(selectedSemester),
    );
    final totalWeeks = totalWeeksAsync.valueOrNull ?? defaultSemesterTotalWeeks;

    return Container(
      decoration: AppTheme.brandedCardDecoration(),
      child: Column(
        children: [
          _SettingTile(
            icon: Icons.calendar_view_week_outlined,
            iconColor: sundayFirst ? AppColors.success : AppColors.textMuted,
            title: '周日作为每周起始日',
            subtitle: sundayFirst
                ? '课表按周日到周六展示，并按周日起算当前周'
                : '课表按周一到周日展示，并按周一起算当前周',
            trailing: sundayFirstAsync.isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Switch(
                    value: sundayFirst,
                    activeThumbColor: AppColors.success,
                    onChanged: (value) async {
                      await ref
                          .read(scheduleSundayFirstProvider.notifier)
                          .setSundayFirst(value);
                      if (!context.mounted) return;
                      AppSnackBar.success(
                        context,
                        value ? '已切换为周日起始' : '已切换为周一起始',
                      );
                    },
                  ),
          ),
          const Divider(height: 1, indent: 56, color: AppColors.outline),
          _SettingTile(
            icon: Icons.layers_outlined,
            iconColor: showInactive ? AppColors.secondary : AppColors.textMuted,
            title: '显示本周无课课程',
            subtitle: showInactive ? '课表中显示本周无课但与当前周相关的课程提示' : '课表只显示当周实际有课的课程',
            trailing: showInactiveAsync.isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Switch(
                    value: showInactive,
                    activeThumbColor: AppColors.secondary,
                    onChanged: (value) async {
                      await ref
                          .read(scheduleShowInactiveCoursesProvider.notifier)
                          .setShowInactiveCourses(value);
                      if (!context.mounted) return;
                      AppSnackBar.success(
                        context,
                        value ? '已显示本周无课课程' : '已隐藏本周无课课程',
                      );
                    },
                  ),
          ),
          const Divider(height: 1, indent: 56, color: AppColors.outline),
          _SettingTile(
            icon: Icons.view_week_outlined,
            iconColor: AppColors.info,
            title: '学期周数',
            subtitle: '当前学期按 $totalWeeks 周计算课表、小组件和课前提醒',
            trailing: totalWeeksAsync.isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : PopupMenuButton<int>(
                    initialValue: totalWeeks,
                    tooltip: '设置学期周数',
                    onSelected: (value) async {
                      await ref
                          .read(
                            semesterTotalWeeksProvider(
                              selectedSemester,
                            ).notifier,
                          )
                          .setWeeks(value);
                      if (!context.mounted) return;
                      AppSnackBar.success(context, '学期周数已改为 $value 周');
                    },
                    itemBuilder: (context) => [
                      for (
                        var week = minSemesterTotalWeeks;
                        week <= maxSemesterTotalWeeks;
                        week++
                      )
                        PopupMenuItem(value: week, child: Text('$week 周')),
                    ],
                    child: Text(
                      '$totalWeeks 周',
                      style: const TextStyle(
                        color: AppColors.info,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _CacheSettingsCard extends ConsumerWidget {
  const _CacheSettingsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final creds = ref.watch(credentialsProvider);
    final username = creds?.username ?? '';

    return Container(
      decoration: AppTheme.brandedCardDecoration(),
      child: _SettingTile(
        icon: Icons.cleaning_services_outlined,
        iconColor: AppColors.warning,
        title: '清空缓存',
        subtitle: '清理当前账号的学业、课表与本地配置缓存',
        trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
        onTap: () {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text('确认清空缓存'),
              content: const Text('确定要清空当前账号的本地缓存与设置吗？'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消', style: TextStyle(color: AppColors.textMuted)),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await clearCurrentAccountCache(ref, username);
                    if (!context.mounted) return;
                    AppSnackBar.success(context, '当前账号缓存已成功清空');
                  },
                  child: const Text(
                    '确认清空',
                    style: TextStyle(color: AppColors.warning),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 宿舍设置卡片
// ══════════════════════════════════════════════════════════════
class _DormSettingsCard extends ConsumerWidget {
  const _DormSettingsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dormAsync = ref.watch(dormRoomProvider);

    return Container(
      decoration: AppTheme.brandedCardDecoration(),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: const Icon(Icons.home_outlined, color: AppColors.warning),
        ),
        title: const Text(
          '我的宿舍',
          style: TextStyle(fontSize: 15, color: AppColors.textPrimary),
        ),
        subtitle: dormAsync.when(
          loading: () => const Text(
            '加载中...',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          error: (_, _) => const Text(
            '加载失败',
            style: TextStyle(fontSize: 12, color: AppColors.danger),
          ),
          data: (dorm) => Text(
            dorm == null ? '未设置，请先选择后使用电费服务' : dorm.displayName,
            style: TextStyle(
              fontSize: 12,
              color: dorm == null ? AppColors.warning : AppColors.textMuted,
            ),
          ),
        ),
        trailing: FilledButton.tonal(
          onPressed: () => _showDormPicker(context, ref),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('选择', style: TextStyle(fontSize: 13)),
        ),
        onTap: () => _showDormPicker(context, ref),
      ),
    );
  }

  void _showDormPicker(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DormPickerSheet(
        currentDorm: ref.read(dormRoomProvider).valueOrNull,
        onSaved: (room) async {
          await ref.read(dormRoomProvider.notifier).set(room);
          if (context.mounted) {
            AppSnackBar.success(
              context,
              '已保存：${room.displayName}，电费数据正在刷新',
            );
          }
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 宿舍选择底部弹窗（双滚轮 + 房间号输入）
// ══════════════════════════════════════════════════════════════
class _DormPickerSheet extends StatefulWidget {
  final DormRoom? currentDorm;
  final Future<void> Function(DormRoom) onSaved;

  const _DormPickerSheet({required this.currentDorm, required this.onSaved});

  @override
  State<_DormPickerSheet> createState() => _DormPickerSheetState();
}

class _DormPickerSheetState extends State<_DormPickerSheet> {
  late FixedExtentScrollController _gardenCtrl;
  late FixedExtentScrollController _numberCtrl;
  late FixedExtentScrollController _southDistrictCtrl;
  late FixedExtentScrollController _southBuildingCtrl;
  final _roomCtrl = TextEditingController();

  // 当前滚轮选中值（随滚动实时更新，用于预览）
  late DormGarden _selectedGarden;
  late int _selectedNumber;
  late SouthDormDistrict _selectedSouthDistrict;
  late SouthDormBuilding _selectedSouthBuilding;
  var _isSouthCampus = false;

  bool _saving = false;
  String? _roomError;

  static const _gardens = DormGarden.values;

  @override
  void initState() {
    super.initState();
    final dorm = widget.currentDorm;
    _isSouthCampus = dorm?.isSouthCampus ?? false;
    _selectedGarden = dorm != null && !dorm.isSouthCampus
        ? dorm.garden
        : DormGarden.deYuan;
    _selectedNumber = dorm != null && !dorm.isSouthCampus
        ? dorm.buildingNumber
        : 1;
    _selectedSouthDistrict = dorm?.southDistrict ?? southDormDistricts.first;
    _selectedSouthBuilding =
        dorm?.southBuilding ?? _selectedSouthDistrict.buildings.first;

    _gardenCtrl = FixedExtentScrollController(
      initialItem: _gardens.indexOf(_selectedGarden),
    );
    _numberCtrl = FixedExtentScrollController(
      initialItem: _selectedNumber - kDormNumberMin,
    );
    _southDistrictCtrl = FixedExtentScrollController(
      initialItem: southDormDistricts.indexOf(_selectedSouthDistrict),
    );
    _southBuildingCtrl = FixedExtentScrollController(
      initialItem: _selectedSouthDistrict.buildings.indexOf(
        _selectedSouthBuilding,
      ),
    );

    if (dorm != null) {
      // 还原房间号，去掉前导零
      _roomCtrl.text = dorm.roomNumber.replaceFirst(RegExp(r'^0+'), '');
    }
  }

  @override
  void dispose() {
    _gardenCtrl.dispose();
    _numberCtrl.dispose();
    _southDistrictCtrl.dispose();
    _southBuildingCtrl.dispose();
    _roomCtrl.dispose();
    super.dispose();
  }

  /// 将输入的房间号格式化为 4 位补零字符串
  String? _formatRoom(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    // 支持用户直接输入 "0305" 或 "305"
    if (!RegExp(r'^\d{1,4}$').hasMatch(t)) return null;
    final n = int.tryParse(t);
    if (n == null || n < 1) return null;
    return t.padLeft(4, '0');
  }

  void _selectSouthDistrict(int index) {
    final district = southDormDistricts[index];
    if (district == _selectedSouthDistrict) return;
    setState(() {
      _selectedSouthDistrict = district;
      _selectedSouthBuilding = district.buildings.first;
    });
    _southBuildingCtrl.jumpToItem(0);
  }

  Future<void> _save() async {
    final roomId = _formatRoom(_roomCtrl.text);
    if (roomId == null) {
      setState(() => _roomError = '请输入正确的房间号（如 305）');
      return;
    }
    setState(() {
      _roomError = null;
      _saving = true;
    });

    final room = _isSouthCampus
        ? DormRoom.southCampus(
            district: _selectedSouthDistrict,
            building: _selectedSouthBuilding,
            roomNumber: roomId,
          )
        : DormRoom(
            campusName: '科学城校区',
            garden: _selectedGarden,
            buildingNumber: _selectedNumber,
            roomNumber: roomId,
          );
    await widget.onSaved(room);
    if (mounted) {
      setState(() => _saving = false);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── 拖拽指示条 ──────────────────────────────────
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),

            // ── 标题 ────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.home_outlined,
                      color: AppColors.accent,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '选择我的宿舍',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '支持科学城校区与南岸校区学生宿舍',
                          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),

            // ── 当前选中预览（仅显示楼栋名，不暴露内部 ID）──────
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.home_outlined,
                    size: 16,
                    color: AppColors.accent.withValues(alpha: 0.9),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isSouthCampus
                          ? '已选：${_selectedSouthBuilding.label}'
                          : '已选：${_selectedGarden.label}$_selectedNumber舍',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.accent.withValues(alpha: 0.95),
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('科学城校区')),
                      ButtonSegment(value: true, label: Text('南岸校区')),
                    ],
                    selected: {_isSouthCampus},
                    onSelectionChanged: (selection) {
                      setState(() => _isSouthCampus = selection.first);
                    },
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 200,
                    child: Row(
                      children: _isSouthCampus
                          ? [
                              Expanded(
                                child: _DormPickerWheel(
                                  controller: _southDistrictCtrl,
                                  labels: [
                                    for (final district in southDormDistricts)
                                      district.label,
                                  ],
                                  selectedIndex: southDormDistricts.indexOf(
                                    _selectedSouthDistrict,
                                  ),
                                  onSelected: _selectSouthDistrict,
                                ),
                              ),
                              Expanded(
                                child: _DormPickerWheel(
                                  controller: _southBuildingCtrl,
                                  labels: [
                                    for (final building
                                        in _selectedSouthDistrict.buildings)
                                      building.label,
                                  ],
                                  selectedIndex: _selectedSouthDistrict
                                      .buildings
                                      .indexOf(_selectedSouthBuilding),
                                  onSelected: (index) {
                                    setState(
                                      () => _selectedSouthBuilding =
                                          _selectedSouthDistrict
                                              .buildings[index],
                                    );
                                  },
                                ),
                              ),
                            ]
                          : [
                              Expanded(
                                child: _DormPickerWheel(
                                  controller: _gardenCtrl,
                                  labels: [
                                    for (final garden in _gardens) garden.label,
                                  ],
                                  selectedIndex: _gardens.indexOf(
                                    _selectedGarden,
                                  ),
                                  onSelected: (index) {
                                    setState(
                                      () => _selectedGarden = _gardens[index],
                                    );
                                  },
                                ),
                              ),
                              Expanded(
                                child: _DormPickerWheel(
                                  controller: _numberCtrl,
                                  labels: [
                                    for (
                                      var number = kDormNumberMin;
                                      number <= kDormNumberMax;
                                      number++
                                    )
                                      '$number舍',
                                  ],
                                  selectedIndex:
                                      _selectedNumber - kDormNumberMin,
                                  onSelected: (index) {
                                    setState(
                                      () => _selectedNumber =
                                          kDormNumberMin + index,
                                    );
                                  },
                                ),
                              ),
                            ],
                    ),
                  ),
                ],
              ),
            ),

            // ── 房间号输入 ───────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '房间号',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _roomCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    onChanged: (_) {
                      if (_roomError != null) setState(() => _roomError = null);
                    },
                    decoration: InputDecoration(
                      hintText: '如住 305 房，输入 305',
                      errorText: _roomError,
                      prefixIcon: const Icon(Icons.door_back_door_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      counterText: '',
                    ),
                  ),
                ],
              ),
            ),

            // ── 保存按钮 ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_rounded, size: 20),
                  label: Text(_saving ? '保存中...' : '保存宿舍设置'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent.withValues(alpha: 0.85),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                  ),
                  onPressed: _saving ? null : _save,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DormPickerWheel extends StatelessWidget {
  const _DormPickerWheel({
    required this.controller,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
  });

  final FixedExtentScrollController controller;
  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Center(
          child: Container(
            height: 44,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
          ),
        ),
        ListWheelScrollView.useDelegate(
          controller: controller,
          itemExtent: 44,
          physics: const FixedExtentScrollPhysics(),
          diameterRatio: 1.8,
          perspective: 0.004,
          onSelectedItemChanged: onSelected,
          childDelegate: ListWheelChildBuilderDelegate(
            childCount: labels.length,
            builder: (context, index) {
              final selected = index == selectedIndex;
              return Center(
                child: Text(
                  labels[index],
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: selected ? 20 : 16,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    color: selected
                        ? AppColors.accent.withValues(alpha: 0.95)
                        : AppColors.textMuted,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

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
    if (mounted) {
      setState(() {
        _isIgnoring = ignoring;
        _autostartAppOps = autostart;
        _courseReminderEnabled = courseReminder;
        _courseReminderMinutes = courseReminderMinutes;
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
                            ? '✅ 已开启，课前 $currentReminderMinutes 分钟提醒'
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
              const Divider(height: 1, indent: 56, color: AppColors.outline),            _SettingTile(
              icon: Icons.battery_saver_outlined,
              iconColor: _isIgnoring == true ? AppColors.success : AppColors.warning,
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
                color: _lockBackgroundDone ? AppColors.success : AppColors.textMuted,
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

// ══════════════════════════════════════════════════════════════
// 电费卡片
// ══════════════════════════════════════════════════════════════
class _ElectricityCardWidget extends ConsumerWidget {
  const _ElectricityCardWidget();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balanceAsync = ref.watch(electricityProvider);

    return GestureDetector(
      onTap: () => ElectricityPage.open(context, ref),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            colors: [AppColors.textPrimary, AppColors.textSecondary],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.textPrimary.withValues(alpha: 0.4),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.bolt,
                        color: AppColors.accent,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Consumer(
                      builder: (context, ref, _) {
                        final dorm = ref.watch(dormRoomProvider).valueOrNull;
                        return Text(
                          dorm == null ? '宿舍电费' : dorm.displayName,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const Text(
                  '点击去充值',
                  style: TextStyle(color: Colors.white38, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 24),
            balanceAsync.when(
              skipError: true,
              skipLoadingOnRefresh: true,
              skipLoadingOnReload: true,
              loading: () => const SizedBox(
                height: 80,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: CircularProgressIndicator(color: Colors.white54),
                ),
              ),
              error: (e, _) => SizedBox(
                height: 80,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: e is NoDormSetException
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '未设置宿舍',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              '请在下方「宿舍设置」中选择你的宿舍',
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        )
                      : const Text(
                          '获取失败',
                          style: TextStyle(
                            color: AppColors.danger,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              data: (balanceStr) {
                final isNegative = balanceStr.contains('-');
                final absNumStr = balanceStr.replaceAll(RegExp(r'[^0-9.]'), '');
                final balValue =
                    (double.tryParse(absNumStr) ?? 0.0) * (isNegative ? -1 : 1);

                return FutureBuilder<double>(
                  future: NotificationService.getElecThreshold(),
                  initialData: NotificationService.defaultElecThreshold,
                  builder: (context, snapshot) {
                    final threshold =
                        snapshot.data ??
                        NotificationService.defaultElecThreshold;
                    final isLowBalance = threshold > 0 && balValue < threshold;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6.0),
                              child: Text(
                                isNegative ? '-¥' : '¥',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              absNumStr.isEmpty ? '0.00' : absNumStr,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 48,
                                fontWeight: FontWeight.w900,
                                height: 1.0,
                                fontFamily: 'Roboto',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: isLowBalance
                                        ? AppColors.danger
                                        : AppColors.success,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color:
                                            (isLowBalance
                                                    ? AppColors.danger
                                                    : AppColors.success)
                                                .withValues(alpha: 0.6),
                                        blurRadius: 6,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  threshold == 0
                                      ? '余额预警已关闭'
                                      : (isLowBalance
                                            ? '余额偏低，建议充值'
                                            : '余额充足，安心用电'),
                                  style: TextStyle(
                                    color: isLowBalance
                                        ? AppColors.danger.withValues(alpha: 0.85)
                                        : Colors.white70,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Row(
                                children: [
                                  Text(
                                    '详情',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(width: 2),
                                  Icon(
                                    Icons.chevron_right,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
