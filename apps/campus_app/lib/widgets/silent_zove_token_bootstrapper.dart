import 'dart:async';
import 'dart:convert';

import 'package:campus_platform/services/session_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../utils/providers.dart';
import '../utils/campus_error_message.dart';

String _redactUsername(String value) {
  final trimmed = value.trim();
  if (trimmed.length <= 4) return 'user_****';
  return 'user_${trimmed.substring(0, 2)}****${trimmed.substring(trimmed.length - 2)}';
}

/// Silently warms up h-zove-token in background after user login.
/// It stays hidden in widget tree and does not block entering main pages.
class SilentZoveTokenBootstrapper extends ConsumerStatefulWidget {
  const SilentZoveTokenBootstrapper({super.key});

  @override
  ConsumerState<SilentZoveTokenBootstrapper> createState() =>
      _SilentZoveTokenBootstrapperState();
}

class _SilentZoveTokenBootstrapperState
    extends ConsumerState<SilentZoveTokenBootstrapper>
    with WidgetsBindingObserver {
  static const _loginUrl =
      'https://ids.cqjtu.edu.cn/authserver/login?service=http%3A%2F%2Fjwgln.cqjtu.edu.cn%2Fjsxsd%2Fsso.jsp';
  static const _ecardEntryUrl = 'https://ecard.cqjtu.edu.cn/epay/h5/payele';
  static const _studentIndexUrl =
      'https://zhxg.cqjtu.edu.cn/mobile/stuhall/studentindex';
  static const _casCookieUrl = 'https://ids.cqjtu.edu.cn/authserver/';
  static const _jwgCookieUrl = 'https://jwgln.cqjtu.edu.cn/jsxsd/';
  static const _ecardCookieUrl = 'https://ecard.cqjtu.edu.cn/epay/h5/';
  static const _healthCheckInterval = Duration(minutes: 25);
  static const _cookieChannel = MethodChannel('campus_app/cookie_manager');

  late final WebViewController _controller;
  Completer<void>? _pageLoadCompleter;
  Completer<String>? _tokenCompleter;
  String? _capturedZoveToken;
  Timer? _healthTimer;

  bool _running = false;
  String? _lastSeenUser;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.listenManual<int>(zoveTokenRefreshProvider, (_, next) {
      unawaited(_maybeStart(force: true));
    });
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'ZoveToken',
        onMessageReceived: (msg) {
          final token = msg.message.trim();
          if (token.isEmpty) return;
          _capturedZoveToken = token;
          if (!(_tokenCompleter?.isCompleted ?? true)) {
            _tokenCompleter?.complete(token);
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {},
          onPageFinished: (url) async {
            if (!(_pageLoadCompleter?.isCompleted ?? true)) {
              _pageLoadCompleter?.complete();
            }
            await _controller.runJavaScript(_hookScript);
            if (url.contains('ids.cqjtu.edu.cn/authserver/login')) {
              final creds = ref.read(credentialsProvider);
              if (creds != null) {
                await _autofillAndSubmit(creds.username, creds.password);
              }
            }
            if (Uri.tryParse(url)?.host.toLowerCase() == 'zhxg.cqjtu.edu.cn') {
              final creds = ref.read(credentialsProvider);
              if (creds != null) {
                await _autofillZhxgAndSubmit(creds.username, creds.password);
              }
            }
          },
        ),
      );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_maybeStart());
    });
    _healthTimer = Timer.periodic(_healthCheckInterval, (_) {
      // h-zove-token can expire before the broader leave-session freshness
      // window. Renew it on every health interval while the app is alive.
      unawaited(_maybeStart(force: true));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _healthTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_maybeStart());
    }
  }

  Future<void> _maybeStart({bool force = false}) async {
    if (_running) return;
    final creds = ref.read(credentialsProvider);
    if (creds == null) return;

    final sessionService = ref.read(sessionServiceProvider);
    if (!force) {
      final shouldRefresh = await _shouldRefreshArtifacts(
        creds.username,
        sessionService,
      );
      if (!shouldRefresh) return;
    }

    _running = true;
    unawaited(_bootstrap(creds.username, sessionService));
  }

  Future<bool> _shouldRefreshArtifacts(
    String username,
    SessionService sessionService,
  ) async {
    if (await _isArtifactMissingOrStale(
      valueLoader: () => sessionService.loadTicket(username),
      updatedAtLoader: () => sessionService.loadTicketUpdatedAt(username),
      maxAge: SystemDomain.schedule.freshness,
    )) {
      return true;
    }

    if (await _isArtifactMissingOrStale(
      valueLoader: () => sessionService.loadCasCookies(username),
      updatedAtLoader: () => sessionService.loadCasCookiesUpdatedAt(username),
      maxAge: SystemDomain.schedule.freshness,
    )) {
      return true;
    }

    if (await _isArtifactMissingOrStale(
      valueLoader: () => sessionService.loadJwgCookies(username),
      updatedAtLoader: () => sessionService.loadJwgCookiesUpdatedAt(username),
      maxAge: SystemDomain.schedule.freshness,
    )) {
      return true;
    }

    if (await _isArtifactMissingOrStale(
      valueLoader: () => sessionService.loadEcardCookies(username),
      updatedAtLoader: () => sessionService.loadEcardCookiesUpdatedAt(username),
      maxAge: SystemDomain.oneCard.freshness,
    )) {
      return true;
    }

    return _isArtifactMissingOrStale(
      valueLoader: () => sessionService.loadZoveToken(username),
      updatedAtLoader: () => sessionService.loadZoveTokenUpdatedAt(username),
      maxAge: SystemDomain.leave.freshness,
    );
  }

  Future<bool> _isArtifactMissingOrStale({
    required Future<String?> Function() valueLoader,
    required Future<int?> Function() updatedAtLoader,
    required Duration maxAge,
  }) async {
    final value = (await valueLoader())?.trim() ?? '';
    if (value.isEmpty) return true;

    final updatedAt = await updatedAtLoader();
    if (updatedAt == null) return true;

    final age = DateTime.now().millisecondsSinceEpoch - updatedAt;
    return age >= maxAge.inMilliseconds;
  }

  Future<void> _bootstrap(
    String username,
    SessionService sessionService,
  ) async {
    var updated = false;
    try {
      updated = await _refreshCookieArtifacts(username, sessionService);

      _capturedZoveToken = null;
      _tokenCompleter = Completer<String>();
      await _loadAndWait(_studentIndexUrl);
      await _controller.runJavaScript(_hookScript);
      await _loadAndWait(_studentIndexUrl);

      final token = await _waitForToken(timeout: const Duration(seconds: 8));
      if (token != null && token.isNotEmpty) {
        await sessionService.saveZoveToken(username, token);
        debugPrint(
          '[SilentZoveToken] refreshed token for ${_redactUsername(username)} '
          '(length=${token.length})',
        );
        updated = true;
      }
    } catch (error) {
      debugPrint(
        '[SilentZoveToken] bootstrap failed: ${formatCampusError(error)}',
      );
    } finally {
      _running = false;
      if (updated) {
        ref.read(sessionUpdateProvider.notifier).triggerRefresh();
      }
    }
  }

  Future<bool> _refreshCookieArtifacts(
    String username,
    SessionService sessionService,
  ) async {
    var updated = false;
    try {
      await _loadAndWait(_loginUrl);

      final casCookies = await _readCookies(_casCookieUrl);
      if (casCookies.isNotEmpty) {
        await sessionService.saveCasCookies(username, casCookies);
        updated = true;
      }

      final jwgCookies = await _readCookies(_jwgCookieUrl);
      if (jwgCookies.isNotEmpty) {
        await sessionService.saveJwgCookies(username, jwgCookies);
        updated = true;
      }

      await _loadAndWait(_ecardEntryUrl);
      final ecardCookies = await _readCookies(_ecardCookieUrl);
      if (ecardCookies.isNotEmpty) {
        await sessionService.saveEcardCookies(username, ecardCookies);
        updated = true;
      }
    } catch (error) {
      debugPrint(
        '[SilentZoveToken] cookie refresh failed: ${formatCampusError(error)}',
      );
    }
    return updated;
  }

  Future<String> _readCookies(String url) async {
    final cookies = await _cookieChannel.invokeMethod<String>('getCookies', {
      'url': url,
    });
    return cookies?.trim() ?? '';
  }

  Future<void> _autofillAndSubmit(String username, String password) async {
    final encodedUsername = jsonEncode(username);
    final encodedPassword = jsonEncode(password);
    await _controller.runJavaScript('''
      (function () {
        var u = document.getElementById('username');
        var p = document.getElementById('password');
        if (u && p) {
          u.value = $encodedUsername;
          p.value = $encodedPassword;
          u.dispatchEvent(new Event('input', { bubbles: true }));
          p.dispatchEvent(new Event('input', { bubbles: true }));
        }
        var btn =
          document.querySelector('#login_submit') ||
          document.querySelector('button[type="submit"]') ||
          document.querySelector('input[type="submit"]');
        if (btn && !btn.disabled) {
          btn.click();
        }
      })();
    ''');
  }

  Future<void> _autofillZhxgAndSubmit(String username, String password) async {
    final encodedUsername = jsonEncode(username);
    final encodedPassword = jsonEncode(password);
    await _controller.runJavaScript('''
      (function () {
        var username = $encodedUsername;
        var password = $encodedPassword;
        var attempts = 0;

        function findUsername() {
          return document.getElementById('username') ||
            document.querySelector('input[name="username"], input[name="account"], input[name="userName"], input[name="userNo"], input[autocomplete="username"], input[placeholder*="账号"], input[placeholder*="学号"]');
        }

        function findPassword() {
          return document.getElementById('password') ||
            document.querySelector('input[name="password"], input[type="password"], input[autocomplete="current-password"], input[placeholder*="密码"]');
        }

        function setValue(input, value) {
          var setter = Object.getOwnPropertyDescriptor(
            HTMLInputElement.prototype,
            'value'
          ).set;
          setter.call(input, value);
          input.dispatchEvent(new Event('input', { bubbles: true }));
          input.dispatchEvent(new Event('change', { bubbles: true }));
        }

        function fillAndSubmit() {
          var userInput = findUsername();
          var passwordInput = findPassword();
          if (!userInput || !passwordInput) return false;
          if (!userInput.value) setValue(userInput, username);
          if (!passwordInput.value) setValue(passwordInput, password);
          var button = document.querySelector('#login_submit') ||
            document.querySelector('button[type="submit"]') ||
            document.querySelector('input[type="submit"]') ||
            Array.prototype.find.call(document.querySelectorAll('button'), function (item) {
              return item.textContent && item.textContent.trim() === '登录';
            });
          if (button && !button.disabled) button.click();
          return true;
        }

        function retry() {
          if (fillAndSubmit() || attempts++ >= 20) return;
          setTimeout(retry, 250);
        }
        retry();
      })();
    ''');
  }

  Future<void> _loadAndWait(String url) async {
    _pageLoadCompleter = Completer<void>();
    await _controller.loadRequest(Uri.parse(url));
    await _pageLoadCompleter!.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () {},
    );
  }

  Future<String?> _waitForToken({required Duration timeout}) async {
    final completer = _tokenCompleter;
    if (completer != null) {
      final token = await completer.future.timeout(
        timeout,
        onTimeout: () => '',
      );
      if (token.isNotEmpty) return token;
    }
    return _capturedZoveToken ?? _readToken();
  }

  Future<String?> _readToken() async {
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

  @override
  Widget build(BuildContext context) {
    final creds = ref.watch(credentialsProvider);
    final username = creds?.username;
    if (username == null) {
      _lastSeenUser = null;
    } else if (!_running && username != _lastSeenUser) {
      _lastSeenUser = username;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_maybeStart(force: true));
      });
    }

    return Offstage(
      offstage: true,
      child: SizedBox(
        width: 1,
        height: 1,
        child: WebViewWidget(controller: _controller),
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
