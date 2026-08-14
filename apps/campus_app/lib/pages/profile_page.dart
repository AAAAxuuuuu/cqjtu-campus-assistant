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

part 'profile/profile_cards.dart';
part 'profile/profile_background.dart';

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
          AppEntrance(child: _buildUserInfoCard(creds?.username ?? '未登录')),
          const SizedBox(height: 20),
          AppEntrance(index: 1, child: const _ElectricityCardWidget()),
          const SizedBox(height: 20),
          AppEntrance(
            index: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [_sectionLabel('宿舍设置'), const _DormSettingsCard()],
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
              children: [_sectionLabel('数据与缓存'), const _CacheSettingsCard()],
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
              children: [_sectionLabel('版本更新'), const _AppUpdateCard()],
            ),
          ),
          const SizedBox(height: 30),
          AppEntrance(index: 7, child: _buildLogoutButton(context, ref)),
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
                    child: Icon(
                      Icons.person,
                      size: 38,
                      color: AppColors.primary,
                    ),
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
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 3,
                            ),
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
                                Icon(
                                  Icons.school,
                                  size: 13,
                                  color: Colors.white,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  '重庆交通大学',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w500,
                                  ),
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
        label: const Text(
          '退出登录',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: BorderSide(
            color: AppColors.primary.withValues(alpha: 0.5),
            width: 1.5,
          ),
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
                  child: const Text(
                    '取消',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
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
                                        ? AppColors.danger.withValues(
                                            alpha: 0.85,
                                          )
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
