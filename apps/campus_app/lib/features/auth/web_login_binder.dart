import 'package:data/data.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/runtime_mode.dart';
import '../../providers/session.dart';
import '../../providers/shared.dart';
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

    if (artifacts.ticket.isNotEmpty) {
      try {
        await gateway.loginWithTicket(username, artifacts.ticket);
        return;
      } catch (e) {
        // Ticket may have already been consumed by SSO redirect in WebView
      }
    }

    if (artifacts.jwgCookies.isNotEmpty || artifacts.casCookies.isNotEmpty) {
      await gateway.loginWithCookies(
        username,
        casCookies: artifacts.casCookies,
        jwgCookies: artifacts.jwgCookies,
        ecardCookies: artifacts.ecardCookies,
      );
      return;
    }

    throw const AuthInvalidFailure('未获取到有效的网页登录凭证（ticket 或 Cookie），请重新尝试网页登录');
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
