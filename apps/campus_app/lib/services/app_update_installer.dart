import 'dart:io';

import 'package:campus_platform/services/app_update_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

enum AppUpdateLaunchStatus {
  installerOpened,
  permissionRequired,
  browserOpened,
  failed,
}

/// 下载进度快照。
///
/// GitHub 的 CDN 有时不返回 Content-Length（尤其经过重定向），此时 dio 回调里
/// 的 total 为 -1，[fraction] 为 null。UI 要据此退回不确定态进度条，而不是把
/// 进度显示成 0% 或直接崩掉。
class AppUpdateDownloadProgress {
  const AppUpdateDownloadProgress({
    required this.receivedBytes,
    required this.totalBytes,
  });

  final int receivedBytes;

  /// 总字节数；未知时为 -1。
  final int totalBytes;

  bool get hasTotal => totalBytes > 0;

  /// 0.0-1.0；总大小未知时为 null。
  double? get fraction {
    if (!hasTotal) return null;
    return (receivedBytes / totalBytes).clamp(0.0, 1.0);
  }

  int? get percent {
    final value = fraction;
    return value == null ? null : (value * 100).round();
  }

  static String formatBytes(int bytes) {
    if (bytes < 0) return '';
    if (bytes < 1024) return '$bytes B';
    const units = ['KB', 'MB', 'GB'];
    var value = bytes / 1024;
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }
    final digits = value >= 100 ? 0 : 1;
    return '${value.toStringAsFixed(digits)} ${units[unitIndex]}';
  }

  /// `12.3 MB / 24.8 MB`，总大小未知时只显示已下载量。
  String get sizeLabel {
    final received = formatBytes(receivedBytes);
    if (!hasTotal) return received;
    return '$received / ${formatBytes(totalBytes)}';
  }
}

typedef AppUpdateProgressCallback =
    void Function(AppUpdateDownloadProgress progress);

class AppUpdateLaunchResult {
  const AppUpdateLaunchResult({required this.status, this.error});

  final AppUpdateLaunchStatus status;
  final Object? error;
}

class AppUpdateInstaller {
  static const _channel = MethodChannel('campus_app/app_update');

  static Future<AppUpdateLaunchResult> downloadAndLaunch(
    AppUpdateInfo update, {
    AppUpdateProgressCallback? onProgress,
  }) async {
    final fallbackUrl = update.releasePageUrl;
    final downloadUrl = update.resolveDownloadUrl();

    if (defaultTargetPlatform != TargetPlatform.android ||
        downloadUrl == null) {
      final opened = await _openExternalUrl(fallbackUrl);
      return AppUpdateLaunchResult(
        status: opened
            ? AppUpdateLaunchStatus.browserOpened
            : AppUpdateLaunchStatus.failed,
      );
    }

    try {
      final apkPath = await _downloadApk(
        downloadUrl,
        suggestedFileName: 'cqjtu-campus-assistant-${update.label}.apk',
        onProgress: onProgress,
      );
      final result = await _channel.invokeMethod<String>('installApk', {
        'path': apkPath,
      });

      if (result == 'install_started') {
        return const AppUpdateLaunchResult(
          status: AppUpdateLaunchStatus.installerOpened,
        );
      }
      if (result == 'permission_required') {
        return const AppUpdateLaunchResult(
          status: AppUpdateLaunchStatus.permissionRequired,
        );
      }
    } catch (error) {
      final opened = await _openExternalUrl(fallbackUrl);
      return AppUpdateLaunchResult(
        status: opened
            ? AppUpdateLaunchStatus.browserOpened
            : AppUpdateLaunchStatus.failed,
        error: error,
      );
    }

    final opened = await _openExternalUrl(fallbackUrl);
    return AppUpdateLaunchResult(
      status: opened
          ? AppUpdateLaunchStatus.browserOpened
          : AppUpdateLaunchStatus.failed,
    );
  }

  static Future<String> _downloadApk(
    String url, {
    required String suggestedFileName,
    AppUpdateProgressCallback? onProgress,
  }) async {
    final dir = await getTemporaryDirectory();
    final safeFileName = suggestedFileName.replaceAll(
      RegExp(r'[^A-Za-z0-9._-]'),
      '-',
    );
    final file = File('${dir.path}/$safeFileName');
    if (await file.exists()) {
      await file.delete();
    }

    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(minutes: 5),
        followRedirects: true,
        maxRedirects: 5,
      ),
    );
    await dio.download(
      url,
      file.path,
      onReceiveProgress: onProgress == null
          ? null
          : (received, total) => onProgress(
              AppUpdateDownloadProgress(
                receivedBytes: received,
                totalBytes: total,
              ),
            ),
    );

    final exists = await file.exists();
    final length = exists ? await file.length() : 0;
    if (!exists || length <= 0) {
      throw Exception('downloaded apk is empty');
    }
    return file.path;
  }

  static Future<bool> _openExternalUrl(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
