import 'dart:async';
import 'dart:convert';

import 'package:data/data.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

final academicWebBridgeProvider = Provider<AcademicWebBridge>((ref) {
  final bridge = AcademicWebBridge();
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
  AcademicWebBridge() {
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
              if (url.contains('authserver/login')) {
                debugPrint(
                  '[AcademicBridge] landed on CAS login, session expired',
                );
                _isReady = false;
                if (!(_readyCompleter?.isCompleted ?? true)) {
                  _readyCompleter?.complete();
                }
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
              _isReady = false;
              if (!(_readyCompleter?.isCompleted ?? true)) {
                _readyCompleter?.complete();
              }
            }
          },
          onWebResourceError: (error) {
            debugPrint('[AcademicBridge] error: ${error.description}');
          },
        ),
      );
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
    final headersMap = <String, String>{if (headers != null) ...headers};
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
