import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../theme/app_theme.dart';
import '../widgets/glass_surface.dart';
import '../utils/providers.dart';
import '../services/webview_session_scope.dart';

class CampusServiceWebViewPage extends ConsumerStatefulWidget {
  const CampusServiceWebViewPage({
    super.key,
    required this.title,
    required this.initialUrl,
    this.customUserAgent,
    this.onSchemeIntercepted,
  });

  final String title;
  final String initialUrl;
  final String? customUserAgent;
  final ValueChanged<String>? onSchemeIntercepted;

  @override
  ConsumerState<CampusServiceWebViewPage> createState() =>
      _CampusServiceWebViewPageState();
}

class _CampusServiceWebViewPageState
    extends ConsumerState<CampusServiceWebViewPage> {
  late final WebViewController _controller;
  var _loadingProgress = 0;
  var _canGoBack = false;
  var _canGoForward = false;

  /// 连续消费返回手势的次数，页面成功变化时清零。
  ///
  /// SSO 站点（一卡通等）的历史里全是重定向条目：`goBack()` 回到重定向页后
  /// 又被立刻转发回来，`canGoBack` 永远为 true，用户被永久困住。所以限制
  /// 连续消费次数，超过就放行让路由关闭——任何情况下都必须有退路。
  var _consecutiveBackAttempts = 0;
  String? _lastUrlAtBackAttempt;

  static const _maxConsecutiveBackAttempts = 2;

  static const _defaultUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/120.0.0.0 Safari/537.36';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setUserAgent(widget.customUserAgent ?? _defaultUserAgent)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) setState(() => _loadingProgress = progress);
          },
          onPageStarted: (_) => _refreshNavigationState(),
          onPageFinished: (url) async {
            await _refreshNavigationState();
            if (_shouldAutofill(url)) {
              await _autofillKnownCredentials();
            }
          },
          onNavigationRequest: (request) async {
            final uri = Uri.tryParse(request.url);
            if (uri != null &&
                uri.scheme != 'http' &&
                uri.scheme != 'https' &&
                uri.scheme != 'about' &&
                uri.scheme != 'data') {
              debugPrint(
                '[CampusServiceWebView] Intercepted non-http scheme: ${request.url}',
              );
              widget.onSchemeIntercepted?.call(request.url);
              try {
                final launched = await launchUrl(
                  uri,
                  mode: LaunchMode.externalApplication,
                );
                if (!launched && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('无法打开对应应用 (${uri.scheme})，已尝试调用外部应用'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              } catch (e) {
                debugPrint(
                  '[CampusServiceWebView] Failed to launch external scheme: $e',
                );
              }
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      );

    unawaited(_prepareSessionAndLoad());
  }

  Future<void> _prepareSessionAndLoad() async {
    final username = ref.read(credentialsProvider)?.username ?? '';
    try {
      await WebViewSessionScope.resetForAccount(_controller, username);
    } catch (error) {
      debugPrint('[CampusServiceWebView] session reset failed: $error');
    }

    if (!mounted) return;
    await _controller.loadRequest(Uri.parse(widget.initialUrl));
  }

  Future<void> _refreshNavigationState() async {
    final canGoBack = await _controller.canGoBack();
    final canGoForward = await _controller.canGoForward();
    final currentUrl = await _controller.currentUrl();
    if (!mounted) return;
    setState(() {
      _canGoBack = canGoBack;
      _canGoForward = canGoForward;
      // Landing somewhere new means the user is browsing normally, so the
      // back budget must be restored — otherwise ordinary navigation would
      // slowly spend it and the gesture would start closing the page early.
      if (currentUrl != _lastUrlAtBackAttempt) {
        _consecutiveBackAttempts = 0;
        _lastUrlAtBackAttempt = null;
      }
    });
  }

  bool _shouldAutofill(String url) {
    return url.contains('ids.cqjtu.edu.cn/authserver/login') ||
        url.contains('jwgln.cqjtu.edu.cn/sjd') ||
        url.contains('jwzlapp.cqjtu.edu.cn');
  }

  Future<void> _autofillKnownCredentials() async {
    final credentials = ref.read(credentialsProvider);
    if (credentials == null || credentials.password.trim().isEmpty) return;

    final username = jsonEncode(credentials.username);
    final password = jsonEncode(credentials.password);
    await _controller.runJavaScript('''
      setTimeout(function () {
        var p = document.getElementById('password') ||
          document.querySelector('input[type="password"]');
        var u = document.getElementById('username') ||
          document.querySelector('input[name="username"]') ||
          document.querySelector('input[name="userNo"]') ||
          document.querySelector('input[type="text"]');
        if (u && p) {
          u.value = $username;
          p.value = $password;
          u.dispatchEvent(new Event('input', { bubbles: true }));
          p.dispatchEvent(new Event('input', { bubbles: true }));
          u.dispatchEvent(new Event('change', { bubbles: true }));
          p.dispatchEvent(new Event('change', { bubbles: true }));
        }
      }, 300);
    ''');
  }

  Future<void> _openExternal() async {
    final currentUrl = await _controller.currentUrl() ?? widget.initialUrl;
    final uri = Uri.tryParse(currentUrl);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    // The Android back gesture used to pop this whole route even when the
    // embedded site had its own history, so swiping back from a second-level
    // page (校车预约 → 快速预约, 评教 → 具体表单) exited the service entirely
    // instead of going back one page.
    //
    // But simply forwarding every gesture to `goBack()` traps the user: SSO
    // sites (一卡通) fill their history with redirect entries, so going back
    // lands on a redirect that immediately forwards again — `canGoBack` never
    // becomes false and the route can never close. Hence the attempt budget:
    // consume at most [_maxConsecutiveBackAttempts] gestures that fail to
    // change the page, then let the route pop.
    return PopScope(
      canPop: !_canGoBack || _isBackBudgetExhausted,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBackGesture();
      },
      child: _buildScaffold(context),
    );
  }

  bool get _isBackBudgetExhausted =>
      _consecutiveBackAttempts >= _maxConsecutiveBackAttempts;

  Future<void> _handleBackGesture() async {
    final currentUrl = await _controller.currentUrl();

    // Same URL as the previous attempt means the last goBack() did not get us
    // anywhere — the site bounced us straight back.
    if (currentUrl != null && currentUrl == _lastUrlAtBackAttempt) {
      _consecutiveBackAttempts++;
    } else {
      _consecutiveBackAttempts = 1;
      _lastUrlAtBackAttempt = currentUrl;
    }

    if (_isBackBudgetExhausted) {
      // Budget spent: close the page instead of fighting the redirects.
      //
      // Must be `pop()`, not `maybePop()`: maybePop re-consults this same
      // PopScope, whose `canPop` has not rebuilt yet, so the callback would
      // re-enter itself forever.
      if (mounted) Navigator.of(context).pop();
      return;
    }

    await _controller.goBack();
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      appBar: GlassAppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: '后退',
            icon: const Icon(Icons.arrow_back),
            onPressed: _canGoBack ? () => _controller.goBack() : null,
          ),
          IconButton(
            tooltip: '前进',
            icon: const Icon(Icons.arrow_forward),
            onPressed: _canGoForward ? () => _controller.goForward() : null,
          ),
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: () => _controller.reload(),
          ),
          IconButton(
            tooltip: '外部打开',
            icon: const Icon(Icons.open_in_new),
            onPressed: _openExternal,
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loadingProgress > 0 && _loadingProgress < 100)
            LinearProgressIndicator(
              value: _loadingProgress / 100,
              minHeight: 2,
              color: AppColors.primary,
              backgroundColor: AppColors.tint.withValues(alpha: 0.2),
            ),
        ],
      ),
    );
  }
}
