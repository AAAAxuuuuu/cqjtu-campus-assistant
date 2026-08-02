import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../theme/app_theme.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/error_view.dart';
import '../widgets/glass_surface.dart';
import '../utils/campus_error_message.dart';
import '../services/webview_session_scope.dart';

enum WebViewLoginMode { jwgSession, zoveTokenOnly }

class WebViewLoginPage extends StatefulWidget {
  final String username;
  final String password;
  final WebViewLoginMode mode;

  const WebViewLoginPage({
    super.key,
    required this.username,
    required this.password,
    this.mode = WebViewLoginMode.jwgSession,
  });

  @override
  State<WebViewLoginPage> createState() => _WebViewLoginPageState();
}

class _WebViewLoginPageState extends State<WebViewLoginPage> {
  static const _loginUrl =
      'https://ids.cqjtu.edu.cn/authserver/login?service=http%3A%2F%2Fjwgln.cqjtu.edu.cn%2Fjsxsd%2Fsso.jsp';
  static const _ecardEntryUrl = 'https://ecard.cqjtu.edu.cn/epay/h5/payele';
  static const _studentIndexUrl =
      'https://zhxg.cqjtu.edu.cn/mobile/stuhall/studentindex';
  static const _cookieChannel = MethodChannel('campus_app/cookie_manager');

  late final WebViewController _controller;
  bool _isHandled = false;
  bool _isLoading = true;
  String? _loadError;
  String? _latestTicket;
  String? _capturedPassword;
  Completer<void>? _pageLoadedCompleter;
  Completer<String>? _tokenCompleter;
  String? _capturedZoveToken;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setUserAgent(
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      )
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'LoginCredential',
        onMessageReceived: (msg) {
          final password = msg.message;
          if (password.isEmpty) return;
          _capturedPassword = password;
          debugPrint(
            '[WebViewLoginPage] captured password len=${password.length}',
          );
        },
      )
      ..addJavaScriptChannel(
        'ZoveToken',
        onMessageReceived: (msg) {
          final token = msg.message.trim();
          if (token.isEmpty) return;
          _capturedZoveToken = token;
          debugPrint(
            '[WebViewLoginPage] captured zoveToken len=${token.length}',
          );
          if (!(_tokenCompleter?.isCompleted ?? true)) {
            _tokenCompleter?.complete(token);
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            _captureTicket(url);
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (url) async {
            _captureTicket(url);
            if (!(_pageLoadedCompleter?.isCompleted ?? true)) {
              _pageLoadedCompleter?.complete();
            }
            if (mounted) setState(() => _isLoading = false);

            if (url.contains('authserver/login')) {
              await _installCredentialBridge();
              await _autofillCredentials();
            }

            if (widget.mode == WebViewLoginMode.zoveTokenOnly) {
              await _controller.runJavaScript(_hookScript);
            }

            final isJwgln =
                url.startsWith('http://jwgln.cqjtu.edu.cn') ||
                url.startsWith('https://jwgln.cqjtu.edu.cn');
            final isZhxgMobile = url.startsWith(
              'https://zhxg.cqjtu.edu.cn/mobile/',
            );

            final shouldHandle = widget.mode == WebViewLoginMode.jwgSession
                ? isJwgln
                : isZhxgMobile;

            if (!_isHandled && shouldHandle) {
              _isHandled = true;
              await _extractAndReturnArtifacts();
            }
          },
          onWebResourceError: _handleWebResourceError,
        ),
      );

    _clearCookiesAndLoad();
  }

  void _captureTicket(String url) {
    final ticket = Uri.tryParse(url)?.queryParameters['ticket'];
    if (ticket != null && ticket.isNotEmpty) {
      _latestTicket = ticket;
    }
  }

  Future<void> _autofillCredentials() async {
    await _controller.runJavaScript('''
      setTimeout(function () {
        var u = document.getElementById('username');
        var p = document.getElementById('password');
        if (u && p) {
          u.value = '${widget.username}';
          p.value = '${widget.password}';
          u.dispatchEvent(new Event('input', { bubbles: true }));
          p.dispatchEvent(new Event('input', { bubbles: true }));
        }
      }, 300);
    ''');
  }

  Future<void> _clearCookiesAndLoad() async {
    try {
      await WebViewCookieManager().clearCookies();
      await _controller.clearCache();
      await _controller.clearLocalStorage();
    } catch (error) {
      debugPrint(
        '[WebViewLoginPage] clear previous session failed: ${formatCampusError(error)}',
      );
      _showLoadError('无法清除上一个账号的登录状态，请重试');
      return;
    }

    if (mounted) {
      final url = widget.mode == WebViewLoginMode.jwgSession
          ? _loginUrl
          : _studentIndexUrl;
      await _controller.loadRequest(Uri.parse(url));
    }
  }

  void _handleWebResourceError(WebResourceError error) {
    final url = error.url ?? '';
    final isAuthenticationPage =
        url.isEmpty ||
        url.contains('ids.cqjtu.edu.cn') ||
        url.contains('jwgln.cqjtu.edu.cn');
    if (_isHandled ||
        error.isForMainFrame != true ||
        !isAuthenticationPage ||
        !isCampusNetworkError(error.description)) {
      return;
    }
    _showLoadError(formatCampusError(error.description));
  }

  void _showLoadError(String message) {
    if (!mounted) return;
    setState(() {
      _loadError = message;
      _isLoading = false;
    });
  }

  void _retryLoginPage() {
    setState(() {
      _isHandled = false;
      _isLoading = true;
      _loadError = null;
      _latestTicket = null;
    });
    unawaited(_clearCookiesAndLoad());
  }

  Future<void> _extractAndReturnArtifacts() async {
    try {
      final casCookies = await _readCookiesWithRetry(
        'https://ids.cqjtu.edu.cn/authserver/',
      );
      String jwgCookies = '';
      String ecardCookies = '';
      if (widget.mode == WebViewLoginMode.jwgSession) {
        // The CAS callback can finish before Chromium commits the JSESSIONID.
        // Do not return a CAS-only session while that write is still pending.
        jwgCookies = await _readCookiesWithRetry(
          'https://jwgln.cqjtu.edu.cn/jsxsd/',
        );
        ecardCookies = await _captureEcardCookies();
      }

      if (casCookies.isEmpty) {
        _fail('未能获取到统一认证 Cookie，请重试');
        return;
      }

      final zoveToken = widget.mode == WebViewLoginMode.zoveTokenOnly
          ? await _captureZoveToken()
          : '';
      final ticket = widget.mode == WebViewLoginMode.jwgSession
          ? (_latestTicket ?? '')
          : '';

      if (widget.mode == WebViewLoginMode.jwgSession &&
          jwgCookies.isEmpty &&
          ticket.isEmpty) {
        _fail('未能获取教务系统会话，请在验证完成后稍候重试');
        return;
      }

      if (mounted) {
        await WebViewSessionScope.markAuthenticated(widget.username);
      }
      if (mounted) {
        debugPrint(
          '[WebViewLoginPage] return result mode=${widget.mode} ticketLen=${ticket.length} casCookieLen=${casCookies.length} jwgCookieLen=${jwgCookies.length} ecardCookieLen=${ecardCookies.length} zoveTokenLen=${zoveToken.length} passwordLen=${(_capturedPassword ?? widget.password).length}',
        );
        Navigator.of(context).pop({
          'ticket': ticket,
          'casCookies': casCookies,
          'jwgCookies': jwgCookies,
          'ecardCookies': ecardCookies,
          'zoveToken': zoveToken,
          'password': _capturedPassword ?? widget.password,
        });
      }
    } catch (e) {
      _fail('WebView 会话提取异常: $e');
    }
  }

  Future<String> _captureZoveToken() async {
    try {
      _capturedZoveToken = null;
      _tokenCompleter = Completer<String>();
      await _loadAndWait(_studentIndexUrl);
      await _controller.runJavaScript(_hookScript);
      await _loadAndWait(_studentIndexUrl);

      final byChannel = await _waitTokenFromChannel(
        timeout: const Duration(seconds: 8),
      );
      if (byChannel != null && byChannel.isNotEmpty) return byChannel;

      return _capturedZoveToken ?? await _readZoveToken() ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<String> _captureEcardCookies() async {
    try {
      await _loadAndWait(_ecardEntryUrl);
      return _readCookiesWithRetry('https://ecard.cqjtu.edu.cn/epay/h5/');
    } catch (_) {
      return '';
    }
  }

  Future<String> _readCookiesWithRetry(
    String url, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final deadline = DateTime.now().add(timeout);
    do {
      final cookies =
          await _cookieChannel.invokeMethod<String>('getCookies', {
            'url': url,
          }) ??
          '';
      if (cookies.trim().isNotEmpty) return cookies;
      if (DateTime.now().isAfter(deadline)) return '';
      await Future<void>.delayed(const Duration(milliseconds: 250));
    } while (true);
  }

  Future<String?> _waitTokenFromChannel({required Duration timeout}) async {
    final completer = _tokenCompleter;
    if (completer == null) return null;
    final token = await completer.future.timeout(timeout, onTimeout: () => '');
    return token.isEmpty ? null : token;
  }

  Future<void> _loadAndWait(String url) async {
    _pageLoadedCompleter = Completer<void>();
    await _controller.loadRequest(Uri.parse(url));
    await _pageLoadedCompleter!.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () {},
    );
  }

  Future<String?> _readZoveToken() async {
    final jsResult = await _controller.runJavaScriptReturningResult('''
      (function() {
        try {
          return localStorage.getItem("zoveToken") || window.__zoveToken || "";
        } catch (e) {
          return "";
        }
      })();
    ''');
    return _normalizeJsString(jsResult);
  }

  Future<void> _installCredentialBridge() async {
    await _controller.runJavaScript('''
      (function () {
        if (window.__credential_bridge_installed__) return;
        window.__credential_bridge_installed__ = true;

        var pwdInput = document.getElementById('password');
        var form = document.querySelector('form');

        function reportPassword() {
          try {
            var v = pwdInput && pwdInput.value ? pwdInput.value : "";
            if (v) LoginCredential.postMessage(v);
          } catch (_) {}
        }

        if (pwdInput) {
          pwdInput.addEventListener('input', reportPassword);
          pwdInput.addEventListener('change', reportPassword);
          reportPassword();
        }
        if (form) {
          form.addEventListener('submit', reportPassword);
        }
      })();
    ''');
  }

  String? _normalizeJsString(Object? value) {
    if (value == null) return null;
    var text = value.toString().trim();
    if (text == 'null' || text == 'undefined') return null;
    if (text.length >= 2 && text.startsWith('"') && text.endsWith('"')) {
      text = text.substring(1, text.length - 1);
    }
    text = text.replaceAll(r'\"', '"').replaceAll(r'\n', '\n').trim();
    return text.isEmpty ? null : text;
  }

  void _fail(String msg) {
    if (!mounted) return;
    AppSnackBar.error(context, msg);
    Navigator.of(context).pop(null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GlassAppBar(
        title: const Text('安全验证'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(null),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loadError != null)
            Positioned.fill(
              child: ColoredBox(
                color: AppColors.surface,
                child: ErrorView(
                  message: _loadError!,
                  onRetry: _retryLoginPage,
                ),
              ),
            ),
          if (_isLoading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}

const String _hookScript = r'''
(() => {
  if (window.__zove_hooked__) return;
  window.__zove_hooked__ = true;

  function report(t) {
    if (!t) return;
    localStorage.setItem("zoveToken", t);
    window.__zoveToken = t;
    try { ZoveToken.postMessage(t); } catch (_) {}
  }

  const oldFetch = window.fetch;
  const oldSetHeader = XMLHttpRequest.prototype.setRequestHeader;

  window.fetch = function (input, init) {
    try {
      const req = input instanceof Request ? input : new Request(input, init);
      report(req.headers.get("h-zove-token"));
    } catch (_) {}
    return oldFetch.apply(this, arguments);
  };

  XMLHttpRequest.prototype.setRequestHeader = function (k, v) {
    if (String(k).toLowerCase() === "h-zove-token") report(v);
    return oldSetHeader.apply(this, arguments);
  };
})();
''';
