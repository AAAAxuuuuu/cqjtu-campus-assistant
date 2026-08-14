part of '../profile_page.dart';

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
                  child: const Text(
                    '取消',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
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
            AppSnackBar.success(context, '已保存：${room.displayName}，电费数据正在刷新');
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
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
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
