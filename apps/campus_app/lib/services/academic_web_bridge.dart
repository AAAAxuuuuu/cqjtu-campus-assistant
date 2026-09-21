import 'dart:async';
import 'dart:convert';

import 'package:data/data.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../features/auth/auth_providers.dart';

final academicWebBridgeProvider = Provider<AcademicWebBridge>((ref) {
  final bridge = AcademicWebBridge(
    getCredentials: () => ref.read(credentialsProvider),
  );
  ref.onDispose(bridge.dispose);
  return bridge;
});

/// Background WebView bridge that proxies HTTP requests destined for
/// `jwgln.cqjtu.edu.cn` through a real Chromium JavaScript runtime.
///
/// This transparently satisfies the school's 瑞数 (Ruishu) 6 dynamic anti-bot WAF
/// by allowing the WAF's client-side scripts to dynamically compute and attach
/// valid request signatures (`mGW1fXiL4aFHT`) to every outgoing academic request.
class AcademicWebBridge {
  AcademicWebBridge({
    ({String username, String password})? Function()? getCredentials,
  }) : _getCredentials = getCredentials {
    _controller = WebViewController()
      ..setUserAgent(campusWebUserAgent)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'AcademicBridgeChannel',
        onMessageReceived: _onMessageReceived,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            debugPrint('[AcademicBridge] page started: $url');
          },
          onPageFinished: (url) async {
            debugPrint('[AcademicBridge] page finished: $url');
            if (url.contains('jwgln.cqjtu.edu.cn')) {
              _isSubmittingCas = false;
              if (url.contains('authserver/login')) {
                await _handleCasRedirect(url);
              } else {
                // If this is the initial Ruishu challenge page (very short body with $_ts),
                // Chromium is about to auto-reload. Delay marking ready until the real page settles.
                try {
                  final checkResult = await _controller
                      .runJavaScriptReturningResult(
                        '(function() { return Boolean(document.body && document.body.innerHTML.length > 500); })()',
                      );
                  final isRealPage =
                      checkResult == true || checkResult.toString() == 'true';
                  if (isRealPage) {
                    debugPrint(
                      '[AcademicBridge] jwgln page loaded & confirmed real content',
                    );
                    _markReady();
                  } else {
                    debugPrint(
                      '[AcademicBridge] jwgln page seems to be challenge interim, awaiting reload',
                    );
                  }
                } catch (_) {
                  _markReady();
                }
              }
            } else if (url.contains('ids.cqjtu.edu.cn')) {
              debugPrint('[AcademicBridge] redirected to CAS login ($url)');
              await _handleCasRedirect(url);
            }
          },
          onWebResourceError: (error) {
            debugPrint('[AcademicBridge] error: ${error.description}');
          },
        ),
      );
  }

  final ({String username, String password})? Function()? _getCredentials;
  bool _isSubmittingCas = false;

  Future<void> _handleCasRedirect(String url) async {
    _isReady = false;
    final creds = _getCredentials?.call();
    if (creds == null) {
      debugPrint(
        '[AcademicBridge] landed on CAS login, but no credentials available',
      );
      if (!(_readyCompleter?.isCompleted ?? true)) {
        _readyCompleter?.complete();
      }
      return;
    }

    if (_isSubmittingCas) {
      debugPrint(
        '[AcademicBridge] already attempting CAS login, awaiting result',
      );
      return;
    }

    try {
      final jsResult = await _controller.runJavaScriptReturningResult(r'''
        (function() {
          var isNeedCaptcha = false;
          if (typeof window.needCaptcha !== 'undefined' && (window.needCaptcha === true || window.needCaptcha === '1' || window.needCaptcha === 1)) {
            isNeedCaptcha = true;
          }
          var captchaDiv = document.getElementById('captchaDiv') || document.getElementById('cAuthCode') || document.getElementById('sliderCaptchaDiv');
          if (captchaDiv) {
            var style = window.getComputedStyle(captchaDiv);
            var isVisible = style.display !== 'none' && style.visibility !== 'hidden' && !captchaDiv.classList.contains('hide');
            var captchaImg = document.getElementById('captchaImg');
            var hasImgSrc = captchaImg && captchaImg.getAttribute('src') && captchaImg.getAttribute('src').length > 0;
            if (isVisible && (hasImgSrc || isNeedCaptcha)) {
              isNeedCaptcha = true;
            }
          }
          var errElem = document.getElementById('msg') ||
            document.querySelector('.auth_error, .show_error, #showErrorMsg, .errors');
          var errText = errElem ? (errElem.textContent || '').trim() : '';
          var isFatal = errText.indexOf('锁定') !== -1 ||
            errText.indexOf('错误') !== -1 ||
            errText.indexOf('无效') !== -1;
          return JSON.stringify({
            hasCaptcha: Boolean(isNeedCaptcha),
            hasFatalError: Boolean(isFatal),
            errorMessage: errText
          });
        })()
      ''');
      final normalized = _normalizeJsString(jsResult);
      if (normalized != null && normalized.isNotEmpty) {
        final data = jsonDecode(normalized) as Map<String, dynamic>;
        if (data['hasCaptcha'] == true || data['hasFatalError'] == true) {
          debugPrint(
            '[AcademicBridge] CAS page requires CAPTCHA or shows error: ${data['errorMessage']}; aborting silent login',
          );
          if (!(_readyCompleter?.isCompleted ?? true)) {
            _readyCompleter?.complete();
          }
          return;
        }
      }

      _isSubmittingCas = true;
      debugPrint(
        '[AcademicBridge] landed on CAS login, automatically filling and submitting credentials',
      );
      final encodedUsername = jsonEncode(creds.username);
      final encodedPassword = jsonEncode(creds.password);
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
    } catch (e) {
      debugPrint('[AcademicBridge] CAS auto-submit error: $e');
      _isSubmittingCas = false;
      if (!(_readyCompleter?.isCompleted ?? true)) {
        _readyCompleter?.complete();
      }
    }
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

  late final WebViewController _controller;
  WebViewController get controller => _controller;

  final Map<String, Completer<SchoolHttpResponse>> _pendingRequests = {};
  int _seq = 0;
  bool _isReady = false;
  Completer<void>? _readyCompleter;
  bool _disposed = false;

  bool get isReady => _isReady;

  void _markReady() {
    _isReady = true;
    if (!(_readyCompleter?.isCompleted ?? true)) {
      _readyCompleter?.complete();
    }
  }

  Future<void> reloadWithNewSession({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (_disposed) return;
    debugPrint('[AcademicBridge] reloadWithNewSession triggered');
    _isReady = false;
    _readyCompleter = Completer<void>();
    await _controller.loadRequest(
      Uri.parse('https://jwgln.cqjtu.edu.cn/jsxsd/framework/xsMain.jsp'),
    );
    try {
      await _readyCompleter!.future.timeout(timeout);
      debugPrint(
        '[AcademicBridge] reloadWithNewSession completed, isReady=$_isReady',
      );
    } catch (_) {
      debugPrint('[AcademicBridge] reloadWithNewSession timed out');
    } finally {
      _readyCompleter = null;
    }
  }

  Future<void> warmup({Duration timeout = const Duration(seconds: 10)}) async {
    if (_disposed) return;
    final currentUrl = await _controller.currentUrl();
    if (currentUrl != null &&
        currentUrl.contains('jwgln.cqjtu.edu.cn') &&
        !currentUrl.contains('authserver/login') &&
        _isReady) {
      return;
    }
    if (_readyCompleter == null) {
      _readyCompleter = Completer<void>();
      _isReady = false;
      debugPrint('[AcademicBridge] warming up by loading xsMain.jsp');
      await _controller.loadRequest(
        Uri.parse('https://jwgln.cqjtu.edu.cn/jsxsd/framework/xsMain.jsp'),
      );
    }
    try {
      await _readyCompleter!.future.timeout(timeout);
    } catch (_) {
      debugPrint('[AcademicBridge] warmup timed out, proceeding anyway');
    } finally {
      _readyCompleter = null;
    }
  }

  Future<SchoolHttpResponse?> dispatch(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    List<int>? body,
  }) async {
    if (uri.host != 'jwgln.cqjtu.edu.cn' ||
        uri.path.contains('sso.jsp') ||
        uri.path.contains('login')) {
      // Fall through to native HttpClient for sso.jsp redirects and non-jwgln hosts
      return null;
    }

    final currentUrl = await _controller.currentUrl();
    final onJwgln =
        currentUrl != null &&
        currentUrl.contains('jwgln.cqjtu.edu.cn') &&
        !currentUrl.contains('authserver/login');

    if (!onJwgln || !_isReady) {
      await warmup();
    }

    final postWarmupUrl = await _controller.currentUrl();
    final canFetch =
        postWarmupUrl != null &&
        postWarmupUrl.contains('jwgln.cqjtu.edu.cn') &&
        !postWarmupUrl.contains('authserver/login');

    if (!canFetch) {
      debugPrint(
        '[AcademicBridge] not on jwgln origin (current: $postWarmupUrl); '
        'throwing BotChallengeFailure to trigger web login',
      );
      throw const BotChallengeFailure();
    }

    final id = 'req_${++_seq}';
    final completer = Completer<SchoolHttpResponse>();
    _pendingRequests[id] = completer;

    final bodyStr = body != null
        ? utf8.decode(body, allowMalformed: true)
        : null;
    final headersMap = <String, String>{...?headers};
    if (bodyStr != null &&
        !headersMap.containsKey('content-type') &&
        !headersMap.containsKey('Content-Type')) {
      headersMap['content-type'] = 'application/x-www-form-urlencoded';
    }

    debugPrint('[AcademicBridge] dispatching $method ${uri.path} (id=$id)');
    final script = _buildFetchScript(
      id,
      uri.toString(),
      method,
      headersMap,
      bodyStr,
    );

    try {
      await _controller.runJavaScript(script);
      return await completer.future.timeout(
        const Duration(seconds: 25),
        onTimeout: () {
          _pendingRequests.remove(id);
          throw TimeoutException('教务系统请求超时 (URL: ${uri.path})');
        },
      );
    } catch (e) {
      _pendingRequests.remove(id);
      rethrow;
    }
  }

  void _onMessageReceived(JavaScriptMessage message) {
    try {
      final data = jsonDecode(message.message) as Map<String, dynamic>;
      final id = data['id'] as String;
      final completer = _pendingRequests.remove(id);
      if (completer == null) return;

      if (data.containsKey('error')) {
        final err = data['error'].toString();
        debugPrint('[AcademicBridge] request $id failed with JS error: $err');
        if (err.contains('Failed to fetch') ||
            err.contains('NetworkError') ||
            err.contains('TypeError')) {
          completer.completeError(const NetworkFailure('教务网络请求异常，请稍后重试'));
        } else {
          completer.completeError(Exception(err));
        }
      } else {
        final status = data['status'] as int;
        final headers =
            (data['headers'] as Map<String, dynamic>?)?.map(
              (k, v) => MapEntry(k.toLowerCase(), v.toString()),
            ) ??
            {};
        final body = data['body'] as String? ?? '';
        debugPrint(
          '[AcademicBridge] request $id completed with status=$status bodyLen=${body.length}',
        );
        completer.complete(
          SchoolHttpResponse(statusCode: status, headers: headers, body: body),
        );
      }
    } catch (e) {
      debugPrint('[AcademicBridge] failed to parse message: $e');
    }
  }

  String _buildFetchScript(
    String id,
    String url,
    String method,
    Map<String, String> headers,
    String? body,
  ) {
    final headersJson = jsonEncode(headers);
    final bodyJson = body != null ? jsonEncode(body) : 'null';
    return '''
(function() {
  var id = "$id";
  var url = "$url";
  var method = "$method";
  var headers = $headersJson;
  var body = $bodyJson;

  var options = {
    method: method,
    headers: headers,
    credentials: "include",
    redirect: "follow"
  };
  if (body !== null && method !== "GET" && method !== "HEAD") {
    options.body = body;
  }

  fetch(url, options)
    .then(function(res) {
      return res.text().then(function(text) {
        var h = {};
        try {
          res.headers.forEach(function(val, key) {
            h[key.toLowerCase()] = val;
          });
        } catch (_) {}
        AcademicBridgeChannel.postMessage(JSON.stringify({
          id: id,
          status: res.status,
          headers: h,
          body: text
        }));
      });
    })
    .catch(function(err) {
      AcademicBridgeChannel.postMessage(JSON.stringify({
        id: id,
        error: String(err)
      }));
    });
})();
''';
  }

  void dispose() {
    _disposed = true;
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(Exception('AcademicWebBridge disposed'));
      }
    }
    _pendingRequests.clear();
  }
}
