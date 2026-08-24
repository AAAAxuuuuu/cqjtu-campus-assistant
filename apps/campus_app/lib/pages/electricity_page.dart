import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:data/data.dart';
import '../theme/app_theme.dart';
import '../utils/campus_error_message.dart';
import '../utils/providers.dart';
import 'package:campus_platform/services/notification_service.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/app_entrance.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/background_refresh_banner.dart';
import '../widgets/error_view.dart';
import '../widgets/glass_surface.dart';
import '../widgets/spinning_refresh_button.dart';

class ElectricityPage extends ConsumerWidget {
  const ElectricityPage({super.key});

  static Future<void> open(BuildContext context, WidgetRef ref) async {
    try {
      final dorm = await ref.read(dormRoomProvider.future);
      if (!context.mounted) return;

      if (dorm == null) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            icon: const Icon(Icons.home_outlined),
            title: const Text('请先选择宿舍'),
            content: const Text('电费查询和充值需要宿舍信息。请前往“我的”页面的“宿舍设置”完成选择。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('知道了'),
              ),
            ],
          ),
        );
        return;
      }

      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const ElectricityPage()));
    } catch (_) {
      if (!context.mounted) return;
      AppSnackBar.error(context, '宿舍信息读取失败，请稍后重试');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balanceAsync = ref.watch(electricityProvider);
    final isUpdating = balanceAsync.isRefreshing && balanceAsync.hasValue;

    return Scaffold(
      appBar: GlassAppBar(
        title: const Text('电费监控'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: '预警设置',
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const _ThresholdDialog(),
            ),
          ),
          SpinningRefreshButton(
            tooltip: '刷新电量',
            onPressed: () async {
              AppSnackBar.status(context, '正在获取最新电量...');

              try {
                await ref
                    .read(electricityProvider.notifier)
                    .refresh(forceRefresh: true, throwOnError: true);

                if (context.mounted) {
                  AppSnackBar.success(context, '电量已更新');
                }
              } catch (e) {
                if (context.mounted) {
                  AppSnackBar.error(context, '刷新失败，请检查网络');
                }
                rethrow;
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (balanceAsync.shouldOfferManualRefresh)
            BackgroundRefreshBanner(
              onRefresh: () => ref
                  .read(electricityProvider.notifier)
                  .refresh(forceRefresh: true),
            ),
          AppEntrance(
            child: balanceAsync.when(
              skipLoadingOnRefresh: true,
              skipLoadingOnReload: true,
              loading: () => const _BalanceSkeleton(),
              error: (e, _) => ErrorView(
                message: formatCampusError(e),
                onRetry: () => ref
                    .read(electricityProvider.notifier)
                    .refresh(forceRefresh: true),
              ),
              data: (balance) =>
                  _BalanceCard(balance: balance, isUpdating: isUpdating),
            ),
          ),
          const SizedBox(height: 16),
          AppEntrance(index: 1, child: const _RechargeCard()),
        ],
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  final String balance;
  final bool isUpdating;
  const _BalanceCard({required this.balance, required this.isUpdating});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        gradient: AppColors.warmGradient,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -15,
            top: -15,
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
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Icon(Icons.bolt, size: 40, color: Colors.white),
                ),
                const SizedBox(height: 12),
                Text(
                  '当前剩余电量',
                  style: AppType.body.copyWith(
                    color: Colors.white70,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  balance,
                  style: AppType.metric.copyWith(color: Colors.white),
                ),
                if (isUpdating)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: Colors.white70,
                          ),
                        ),
                        SizedBox(width: 6),
                        Text(
                          '静默更新中...',
                          style: AppType.label.copyWith(
                            color: Colors.white70,
                            fontWeight: FontWeight.w400,
                          ),
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
}

class _BalanceSkeleton extends StatelessWidget {
  const _BalanceSkeleton();

  @override
  // 高度对齐加载完成后的 _BalanceCard，避免数据到达时布局跳动。
  Widget build(BuildContext context) => const AppCard(
    padding: EdgeInsets.zero,
    child: SizedBox(
      height: 200,
      child: Center(child: CircularProgressIndicator()),
    ),
  );
}

class _RechargeCard extends ConsumerStatefulWidget {
  const _RechargeCard();

  @override
  ConsumerState<_RechargeCard> createState() => _RechargeCardState();
}

class _RechargeCardState extends ConsumerState<_RechargeCard> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  static const _quickAmounts = [10.0, 20.0, 50.0, 100.0];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _recharge() async {
    final amount = double.tryParse(_ctrl.text.trim());
    if (amount == null || amount < 0.01 || amount > 200) {
      AppSnackBar.warning(context, '请输入正确的金额（0.01 ~ 200 元）');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('确认充值'),
        content: Text('即将为寝室充值电费 ¥${amount.toStringAsFixed(2)}，确认扣款吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _loading = true);
    try {
      final creds = ref.read(credentialsProvider);
      if (creds == null) throw Exception('未登录');

      // 👈 【核心修复】：获取当前选中的寝室参数
      final dorm = ref.read(dormRoomProvider).valueOrNull;

      // 👈 【核心修复】：把寝室参数传给充值接口
      final msg = await ref
          .read(campusGatewayProvider)
          .rechargeElec(
            creds.username,
            amount,
            password: creds.password,
            dormParams: dorm?.toQueryParams(),
          );

      if (mounted) {
        AppSnackBar.success(context, msg);
        ref.read(electricityProvider.notifier).refresh(forceRefresh: true);
      }
    } on ApiException catch (e) {
      if (mounted) {
        AppSnackBar.error(context, e.message);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.electric_bolt, color: AppColors.warning),
              SizedBox(width: 8),
              Text('电费充值（校园卡扣款）', style: AppType.sectionTitle),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: _quickAmounts
                .map(
                  (a) => ActionChip(
                    label: Text('¥${a.toInt()}'),
                    onPressed: () => _ctrl.text = a.toStringAsFixed(0),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: '充值金额（元）',
              prefixText: '¥ ',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          // AppButton 自带 loading 态与按压反馈，不必手写 spinner。
          AppButton(
            label: '立即充值',
            icon: Icons.payment,
            isLoading: _loading,
            width: double.infinity,
            onPressed: _recharge,
          ),
        ],
      ),
    );
  }
}

class _ThresholdDialog extends StatefulWidget {
  const _ThresholdDialog();

  @override
  State<_ThresholdDialog> createState() => _ThresholdDialogState();
}

class _ThresholdDialogState extends State<_ThresholdDialog> {
  double _elecValue = NotificationService.defaultElecThreshold;
  double _cardValue = NotificationService.defaultCardThreshold;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    Future.wait([
      NotificationService.getElecThreshold(),
      NotificationService.getCardThreshold(),
    ]).then((values) {
      if (mounted) {
        setState(() {
          _elecValue = values[0];
          _cardValue = values[1];
          _loaded = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('余额预警设置'),
      content: _loaded
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 电费阈值
                Row(
                  children: [
                    const Icon(
                      Icons.electric_bolt,
                      size: 16,
                      color: AppColors.warning,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '电费预警',
                      style: AppType.rowTitle.copyWith(fontSize: 14),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _elecValue == 0
                      ? '预警已关闭'
                      : '低于 ${_elecValue.toStringAsFixed(0)} 块时发送提醒',
                  style: AppType.subtitle.copyWith(color: AppColors.textMuted),
                ),
                Slider(
                  value: _elecValue,
                  min: 0,
                  max: 50,
                  divisions: 50,
                  label: _elecValue == 0 ? '已关闭' : '${_elecValue.toInt()} ',
                  onChanged: (v) => setState(() => _elecValue = v),
                ),
                const SizedBox(height: 8),
                // 校园卡阈值
                const Row(
                  children: [
                    Icon(Icons.credit_card, size: 16, color: AppColors.info),
                    SizedBox(width: 6),
                    Text(
                      '校园卡预警',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _cardValue == 0
                      ? '预警已关闭'
                      : '低于 ¥${_cardValue.toStringAsFixed(0)} 时发送提醒',
                  style: AppType.subtitle.copyWith(color: AppColors.textMuted),
                ),
                Slider(
                  value: _cardValue,
                  min: 0,
                  max: 100,
                  divisions: 20,
                  label: _cardValue == 0 ? '已关闭' : '¥${_cardValue.toInt()}',
                  onChanged: (v) => setState(() => _cardValue = v),
                ),
                const SizedBox(height: 4),
                const Text(
                  '后台每 15 分钟自动检查一次，低于阈值时推送通知\n（同一类型 6 小时内最多提醒一次）',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                ),
              ],
            )
          : const SizedBox(
              height: 60,
              child: Center(child: CircularProgressIndicator()),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () async {
            await Future.wait([
              NotificationService.setElecThreshold(_elecValue),
              NotificationService.setCardThreshold(_cardValue),
            ]);
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
