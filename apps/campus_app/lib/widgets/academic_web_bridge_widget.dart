import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../features/auth/auth_providers.dart';
import '../services/academic_web_bridge.dart';

/// Hidden widget hosting the WebViewController for AcademicWebBridge.
/// Kept mounted at the root Stack so the Chromium JS environment stays alive.
class AcademicWebBridgeWidget extends ConsumerStatefulWidget {
  const AcademicWebBridgeWidget({super.key});

  @override
  ConsumerState<AcademicWebBridgeWidget> createState() =>
      _AcademicWebBridgeWidgetState();
}

class _AcademicWebBridgeWidgetState
    extends ConsumerState<AcademicWebBridgeWidget> {
  String? _lastUser;

  @override
  Widget build(BuildContext context) {
    final bridge = ref.watch(academicWebBridgeProvider);
    final creds = ref.watch(credentialsProvider);
    final username = creds?.username;

    if (username != null && username != _lastUser) {
      _lastUser = username;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(bridge.warmup());
      });
    }

    return Offstage(
      offstage: true,
      child: SizedBox(
        width: 1,
        height: 1,
        child: WebViewWidget(controller: bridge.controller),
      ),
    );
  }
}
