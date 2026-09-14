import 'package:data/data.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/runtime_mode.dart';
import '../../providers/session.dart';
import '../../providers/shared.dart';
import '../../services/academic_web_bridge.dart';
import 'package:campus_platform/services/session_service.dart';

class WebLoginBinder {
  const WebLoginBinder(this.ref);

  final Ref ref;

  Future<void> bind({
    required String username,
    required Map<String, dynamic> result,
  }) async {
    final mode = ref.read(campusRuntimeModeProvider);
    switch (mode) {
      case CampusRuntimeMode.localAndroid:
        await _bindLocalAndroid(username: username, result: result);
      case CampusRuntimeMode.selfHosted:
        await _bindSelfHosted(username: username, result: result);
    }

    ref.read(sessionUpdateProvider.notifier).triggerRefresh();
    ref.read(zoveTokenRefreshProvider.notifier).requestRefresh();
  }

  Future<void> _bindLocalAndroid({
    required String username,
    required Map<String, dynamic> result,
  }) async {
    final artifacts = _WebLoginArtifacts.fromResult(result);
    final gateway = ref.read(campusGatewayProvider);
    if (gateway is! DirectSchoolCampusGateway) {
      throw const UnsupportedModeFailure('本地 CAS ticket 绑定');
    }

    // The WebView has established the authoritative session. Discard the
    // failed direct-login jar before persisting or importing its artifacts.
    await gateway.resetLoginSession(username);
    await ref
        .read(sessionServiceProvider)
        .saveWebLoginArtifacts(
          username,
          casCookies: artifacts.casCookies,
          jwgCookies: artifacts.jwgCookies,
          ecardCookies: artifacts.ecardCookies,
          zoveToken: artifacts.zoveToken,
        );

    final hasCookies =
        artifacts.jwgCookies.isNotEmpty || artifacts.casCookies.isNotEmpty;

    // Import the cookies BEFORE touching the ticket. The 瑞数 WAF cookie exists
    // only in the WebView's jar, and redeeming a ticket is itself a request to
    // the protected host — without that cookie the ticket call is a guaranteed
    // 412 whose failure we would silently swallow.
    if (hasCookies) {
      await gateway.loginWithCookies(
        username,
        casCookies: artifacts.casCookies,
        jwgCookies: artifacts.jwgCookies,
        ecardCookies: artifacts.ecardCookies,
      );
    }

    // A ticket is only still needed when the WebView never got a service
    // session cookie of its own.
    final hasSession = _hasServiceSession(artifacts.jwgCookies);
    if (!hasSession) {
      if (artifacts.ticket.isNotEmpty) {
        try {
          await gateway.loginWithTicket(username, artifacts.ticket);
          return;
        } catch (_) {
          throw const AuthInvalidFailure('教务系统人机验证未通过，未能获取会话，请重试');
        }
      }
      throw const AuthInvalidFailure('未获取到有效的教务系统会话，请重新尝试网页登录');
    }

    // Refresh the academic background bridge so it immediately navigates to jwgln with the new cookies.
    await ref.read(academicWebBridgeProvider).reloadWithNewSession();
  }

  /// Whether a raw cookie header already carries an academic-system session.
  ///
  /// The 瑞数 WAF sets its own random-named cookie on the challenge page, so a
  /// non-empty header does not imply a usable session — only these names do.
  bool _hasServiceSession(String cookieHeader) {
    final names = cookieHeader
        .split(';')
        .map((pair) {
          final separator = pair.indexOf('=');
          return separator <= 0 ? '' : pair.substring(0, separator).trim();
        })
        .where((name) => name.isNotEmpty)
        .map((name) => name.toLowerCase())
        .toSet();
    return names.any(
      (name) =>
          name == 'jsessionid' ||
          name == 'session' ||
          name.startsWith('bzb_') ||
          name.contains('jsxsd'),
    );
  }

  Future<String> _bindSelfHosted({
    required String username,
    required Map<String, dynamic> result,
  }) async {
    final artifacts = _WebLoginArtifacts.fromResult(result);
    final api = ref.read(apiServiceProvider);
    final sessionManager = ref.read(sessionManagerProvider);

    var sessionId = await sessionManager.refreshSessionId(username);

    Future<void> bindWithSession(String currentSessionId) async {
      await sessionManager.saveWebLoginArtifacts(
        username,
        casCookies: artifacts.casCookies,
        jwgCookies: artifacts.jwgCookies,
        ecardCookies: artifacts.ecardCookies,
        zoveToken: artifacts.zoveToken,
      );

      if (artifacts.ticket.isNotEmpty) {
        await api.loginWithTicket(
          username,
          artifacts.ticket,
          sessionId: currentSessionId,
        );
      }

      if (artifacts.casCookies.isNotEmpty) {
        await api.injectCookies(
          username,
          'ids.cqjtu.edu.cn',
          artifacts.casCookies,
          sessionId: currentSessionId,
        );
      }
      if (artifacts.jwgCookies.isNotEmpty) {
        await api.injectCookies(
          username,
          'jwgln.cqjtu.edu.cn',
          artifacts.jwgCookies,
          sessionId: currentSessionId,
        );
      }
      if (artifacts.ecardCookies.isNotEmpty) {
        await api.injectCookies(
          username,
          'ecard.cqjtu.edu.cn',
          artifacts.ecardCookies,
          sessionId: currentSessionId,
        );
      }
    }

    try {
      await bindWithSession(sessionId);
    } catch (error) {
      if (!sessionManager.isSessionExpiredError(error)) rethrow;
      sessionId = await sessionManager.refreshSessionId(username);
      await bindWithSession(sessionId);
    }

    return sessionId;
  }
}

final webLoginBinderProvider = Provider<WebLoginBinder>(WebLoginBinder.new);

class _WebLoginArtifacts {
  const _WebLoginArtifacts({
    required this.ticket,
    required this.casCookies,
    required this.jwgCookies,
    required this.ecardCookies,
    required this.zoveToken,
  });

  final String ticket;
  final String casCookies;
  final String jwgCookies;
  final String ecardCookies;
  final String zoveToken;

  factory _WebLoginArtifacts.fromResult(Map<String, dynamic> result) {
    return _WebLoginArtifacts(
      ticket: result['ticket']?.toString().trim() ?? '',
      casCookies: result['casCookies']?.toString() ?? '',
      jwgCookies: result['jwgCookies']?.toString() ?? '',
      ecardCookies: result['ecardCookies']?.toString() ?? '',
      zoveToken: result['zoveToken']?.toString() ?? '',
    );
  }
}
