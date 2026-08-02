import 'dart:async';

import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:data/data.dart';
import '../theme/app_theme.dart';
import '../utils/providers.dart';
import '../widgets/app_entrance.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/background_refresh_banner.dart';
import '../widgets/glass_surface.dart';
import '../widgets/spinning_refresh_button.dart';

class CampusCardPage extends ConsumerStatefulWidget {
  const CampusCardPage({super.key, this.scrollToQr = false});

  final bool scrollToQr;

  @override
  ConsumerState<CampusCardPage> createState() => _CampusCardPageState();
}

class _CampusCardPageState extends ConsumerState<CampusCardPage> {
  final _controller = ScrollController();
  int _handledQrScrollSignal = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.scrollToQr) {
        _scrollToQr();
      }
      _autoRefreshCardData();
    });
  }

  void _autoRefreshCardData() => unawaited(
    refreshCampusCardOnEntry(
      ref.read(campusCardBalanceProvider.notifier),
      ref.read(payCodeProvider.notifier),
    ),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(mainTabIndexProvider, (previous, next) {
      if (next == 1 && previous != 1) {
        _autoRefreshCardData();
      }
    });

    final qrScrollSignal = ref.watch(campusCardQrScrollSignalProvider);
    final balanceState = ref.watch(campusCardBalanceProvider);
    if (qrScrollSignal > _handledQrScrollSignal) {
      _handledQrScrollSignal = qrScrollSignal;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToQr();
        _autoRefreshCardData();
      });
    }

    return Scaffold(
      appBar: GlassAppBar(title: const Text('校园卡')),
      body: ListView(
        controller: _controller,
        padding: const EdgeInsets.all(16),
        children: [
          if (balanceState.shouldOfferManualRefresh)
            BackgroundRefreshBanner(
              onRefresh: () => ref
                  .read(campusCardBalanceProvider.notifier)
                  .refresh(forceRefresh: true),
            ),
          AppEntrance(child: const _BalanceCard()),
          const SizedBox(height: 16),
          AppEntrance(index: 1, child: const _QrCard()),
        ],
      ),
    );
  }

  void _scrollToQr() {
    if (!_controller.hasClients) return;
    _controller.animateTo(
      170,
      duration: AppMotion.standard,
      curve: AppMotion.easeOutStrong,
    );
  }
}

// ── 校园卡余额 ───────────────────────────────────────────────
class _BalanceCard extends ConsumerWidget {
  const _BalanceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balanceAsync = ref.watch(campusCardBalanceProvider);
    final isUpdating = balanceAsync.isRefreshing && balanceAsync.hasValue;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        gradient: AppColors.primaryGradient,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -20,
            top: -20,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.credit_card,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      '校园卡余额',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    SpinningRefreshButton(
                      color: Colors.white,
                      size: 22,
                      tooltip: '刷新余额',
                      onPressed: () async {
                        AppSnackBar.status(context, '正在刷新余额...');
                        try {
                          await ref
                              .read(campusCardBalanceProvider.notifier)
                              .refresh(forceRefresh: true, throwOnError: true);
                          if (context.mounted) {
                            AppSnackBar.success(context, '余额已更新');
                          }
                        } catch (e) {
                          if (context.mounted) {
                            AppSnackBar.error(context, '刷新失败：$e');
                          }
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: balanceAsync.isLoading
                          ? const SizedBox(
                              height: 42,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            )
                          : balanceAsync.hasError && !balanceAsync.hasData
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '获取失败',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  balanceAsync.error.toString(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white60,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            )
                          : Text(
                              balanceAsync.hasData ? balanceAsync.data : '--',
                              style: AppType.metric.copyWith(
                                color: Colors.white,
                              ),
                            ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const CampusCardRechargePage(),
                        ),
                      ),
                      icon: const Icon(Icons.add_card_outlined, size: 18),
                      label: const Text('充值'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.primary,
                        elevation: 4,
                        shadowColor: Colors.black.withValues(alpha: 0.15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
                if (isUpdating)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
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
                          style: TextStyle(color: Colors.white70, fontSize: 11),
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

// ── 消费二维码 ───────────────────────────────────────────────
class _QrCard extends ConsumerWidget {
  const _QrCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokenAsync = ref.watch(payCodeProvider);
    final isUpdating = tokenAsync.isRefreshing && tokenAsync.hasToken;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.outline.withValues(alpha: 0.8)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.tint.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: const Icon(
                  Icons.qr_code_2,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                '消费二维码',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              if (isUpdating)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.secondary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          tokenAsync.when(
            skipLoadingOnRefresh: true,
            skipLoadingOnReload: true,
            loading: () => const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Column(
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 48,
                  color: AppColors.danger,
                ),
                const SizedBox(height: 8),
                Text(
                  e.toString(),
                  style: const TextStyle(color: AppColors.danger, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => ref
                      .read(payCodeProvider.notifier)
                      .refresh(forceRefresh: true, throwOnError: false),
                  child: const Text('重新获取'),
                ),
              ],
            ),
            data: (token) {
              if (token.isEmpty) {
                return SizedBox(
                  height: 220,
                  child: Center(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.qr_code_2),
                      label: const Text('获取消费二维码'),
                      onPressed: () => ref
                          .read(payCodeProvider.notifier)
                          .refresh(forceRefresh: true, throwOnError: false),
                    ),
                  ),
                );
              }

              return Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.outline),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: QrImageView(
                      data: token,
                      size: 200,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.security, size: 14, color: AppColors.accent),
                        SizedBox(width: 6),
                        Text(
                          '二维码仅用于当次消费，请勿截图保存',
                          style: TextStyle(
                            color: AppColors.accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('刷新二维码'),
                    onPressed: tokenAsync.isRefreshing
                        ? null
                        : () => ref
                              .read(payCodeProvider.notifier)
                              .refresh(forceRefresh: true, throwOnError: false),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class CampusCardRechargePage extends StatelessWidget {
  const CampusCardRechargePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('校园卡充值')),
      body: const SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: _RechargeCard(),
        ),
      ),
    );
  }
}

// ── 支付宝充值 ───────────────────────────────────────────────
class _RechargeCard extends ConsumerStatefulWidget {
  const _RechargeCard();

  @override
  ConsumerState<_RechargeCard> createState() => _RechargeCardState();
}

class _RechargeCardState extends ConsumerState<_RechargeCard>
    with WidgetsBindingObserver {
  final _ctrl = TextEditingController();
  bool _loading = false;
  bool _waitingForReturn = false;
  static const _quickAmounts = [20.0, 50.0, 100.0, 200.0];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _waitingForReturn && mounted) {
      _waitingForReturn = false;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('确认支付结果'),
          content: const Text('是否已完成支付宝付款？'),
          actions: [
            TextButton(
              onPressed: () async {
                // 1. 先关闭弹窗
                Navigator.pop(context);

                // 静默刷新余额。
                try {
                  await ref
                      .read(campusCardBalanceProvider.notifier)
                      .refresh(forceRefresh: true, throwOnError: true);

                  if (mounted) {
                    AppSnackBar.success(context, '余额已更新');
                  }
                } catch (e) {
                  if (mounted) {
                    AppSnackBar.error(context, '刷新余额失败，请稍后手动点击刷新图标');
                  }
                }
              },
              child: const Text('已完成付款'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('还未付款'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _pay() async {
    final amount = double.tryParse(_ctrl.text.trim());
    if (amount == null || amount < 0.01 || amount > 500) {
      AppSnackBar.warning(context, '请输入正确的金额');
      return;
    }

    setState(() => _loading = true);
    try {
      final creds = ref.read(credentialsProvider);
      if (creds == null) throw Exception('未登录');
      final responseData = await ref
          .read(campusGatewayProvider)
          .getCampusCardAlipayUrl(
            creds.username,
            amount,
            password: creds.password,
          );

      if (responseData.startsWith('alipays://') ||
          responseData.startsWith('alipay://')) {
        _waitingForReturn = true;
        await launchUrl(
          Uri.parse(responseData),
          mode: LaunchMode.externalApplication,
        );
      } else {
        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => _AlipayBridgePage(
                htmlData: responseData,
                onRealUrlReady: (realUrl) async {
                  _waitingForReturn = true;
                  await launchUrl(
                    Uri.parse(realUrl),
                    mode: LaunchMode.externalApplication,
                  );
                },
              ),
            ),
          );
        }
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.account_balance_wallet_outlined,
                  color: AppColors.success,
                ),
                SizedBox(width: 8),
                Text(
                  '校园卡充值（支付宝）',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
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
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: '充值金额（元）',
                prefixText: '¥ ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.open_in_new, size: 18),
                label: _loading
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('跳转支付宝充值'),
                onPressed: _loading ? null : _pay,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 隐形中转页：提交表单、拦截真实 URL、打开浏览器后自动关闭 ──────
class _AlipayBridgePage extends StatefulWidget {
  final String htmlData;
  final Future<void> Function(String realUrl) onRealUrlReady;

  const _AlipayBridgePage({
    required this.htmlData,
    required this.onRealUrlReady,
  });

  @override
  State<_AlipayBridgePage> createState() => _AlipayBridgePageState();
}

class _AlipayBridgePageState extends State<_AlipayBridgePage> {
  late final WebViewController controller;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) async {
            final url = request.url;

            if (url.startsWith('alipay') || url.startsWith('intent://')) {
              if (!_handled) {
                _handled = true;
                await widget.onRealUrlReady(url);
                if (mounted) Navigator.pop(context);
              }
              return NavigationDecision.prevent;
            }

            if (!url.contains('mapi.alipay.com') &&
                url.startsWith('https://') &&
                !_handled) {
              _handled = true;
              await widget.onRealUrlReady(url);
              if (mounted) Navigator.pop(context);
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadHtmlString(widget.htmlData, baseUrl: 'https://ecard.cqjtu.edu.cn');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('正在跳转支付宝...')),
      body: Stack(
        children: [
          // WebView 必须在 widget 树中才能真正加载 HTML 并触发导航拦截
          Offstage(
            offstage: true,
            child: WebViewWidget(controller: controller),
          ),
          const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('正在准备支付，请稍候...'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
