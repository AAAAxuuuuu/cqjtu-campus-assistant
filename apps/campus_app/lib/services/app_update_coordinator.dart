import 'package:campus_platform/services/app_update_service.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../theme/app_theme.dart';
import '../widgets/app_snackbar.dart';
import 'app_update_installer.dart';

class AppUpdateCoordinator {
  static Future<String> currentVersionLabel() async {
    final installed = await _loadInstalledVersion();
    return installed.version;
  }

  static Future<void> checkAndPrompt(
    BuildContext context, {
    bool manual = false,
  }) async {
    try {
      final current = await _loadInstalledVersion();
      final result = await AppUpdateService.checkForUpdate(
        current: current,
        forceRefresh: manual,
      );
      if (!context.mounted) return;

      switch (result.status) {
        case AppUpdateCheckStatus.notConfigured:
          if (manual) {
            _showSnackBar(context, '还没有配置更新地址');
          }
          return;
        case AppUpdateCheckStatus.upToDate:
          if (manual) {
            _showSnackBar(context, '当前已经是最新版本');
          }
          return;
        case AppUpdateCheckStatus.updateAvailable:
          final latest = result.latest;
          if (latest != null) {
            await AppUpdateService.markNotified(latest);
            if (!context.mounted) return;
          }
          await _showUpdateDialog(context, result);
          return;
      }
    } catch (error) {
      if (!context.mounted) return;
      if (manual) {
        _showSnackBar(context, '检查更新失败：$error');
      } else {
        debugPrint('[Update] auto check failed: $error');
      }
    }
  }

  static Future<InstalledAppVersion> _loadInstalledVersion() async {
    final info = await PackageInfo.fromPlatform();
    final buildNumber = int.tryParse(info.buildNumber.trim()) ?? 0;
    final installed = InstalledAppVersion(
      version: info.version.trim(),
      buildNumber: buildNumber,
    );
    await AppUpdateService.saveInstalledVersion(installed);
    return installed;
  }

  static Future<void> _showUpdateDialog(
    BuildContext context,
    AppUpdateCheckResult result,
  ) async {
    final latest = result.latest;
    if (latest == null) return;

    final hasDirectDownload = latest.resolveDownloadUrl() != null;
    final forceUpdate = latest.force && hasDirectDownload;

    await showDialog<void>(
      context: context,
      barrierDismissible: !forceUpdate,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.system_update_alt, color: AppColors.secondary),
            const SizedBox(width: 8),
            Expanded(child: Text(latest.title)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('当前版本：${result.current.label}'),
              const SizedBox(height: 6),
              Text('最新版本：${latest.label}'),
              if (latest.notes.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  '更新内容',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  latest.notes,
                  style: const TextStyle(
                    color: AppColors.textBody,
                    height: 1.45,
                  ),
                ),
              ],
              if (!hasDirectDownload) ...[
                const SizedBox(height: 16),
                Text(
                  '没有拿到 APK 直链，将跳转到 Release 页面：${latest.releasePageUrl}',
                  style: const TextStyle(color: AppColors.warning),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (!forceUpdate)
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('稍后'),
            ),
          FilledButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await _startUpdate(context, latest);
            },
            child: Text(hasDirectDownload ? '立即更新' : '打开 Release'),
          ),
        ],
      ),
    );
  }

  static Future<void> _startUpdate(
    BuildContext context,
    AppUpdateInfo latest,
  ) async {
    if (!context.mounted) return;

    // 进度经 ValueNotifier 推给对话框，避免每个数据块都重建整棵子树。
    final progress = ValueNotifier<AppUpdateDownloadProgress?>(null);

    final dialogFuture = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UpdateDownloadDialog(progress: progress),
    );

    AppUpdateLaunchResult? result;
    try {
      result = await AppUpdateInstaller.downloadAndLaunch(
        latest,
        onProgress: (value) => progress.value = value,
      );
    } finally {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        await dialogFuture;
      }
      progress.dispose();
    }
    if (!context.mounted) return;

    switch (result.status) {
      case AppUpdateLaunchStatus.installerOpened:
        _showSnackBar(context, '下载完成，已打开系统安装器');
        return;
      case AppUpdateLaunchStatus.permissionRequired:
        _showSnackBar(context, '请在系统设置中开启「允许安装未知应用」，开启后返回将自动继续安装');
        return;
      case AppUpdateLaunchStatus.browserOpened:
        _showSnackBar(context, '直装失败，已为你打开 GitHub Release 页面');
        return;
      case AppUpdateLaunchStatus.failed:
        _showSnackBar(context, '更新失败：${result.error ?? '无法打开下载页'}');
        return;
    }
  }

  static void _showSnackBar(BuildContext context, String message) {
    AppSnackBar.status(context, message);
  }
}

/// 下载更新包时的进度对话框。
///
/// 服务端未返回 Content-Length 时进度未知，退回不确定态进度条并只显示已下载
/// 大小，不谎报百分比。
class _UpdateDownloadDialog extends StatelessWidget {
  const _UpdateDownloadDialog({required this.progress});

  final ValueNotifier<AppUpdateDownloadProgress?> progress;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: ValueListenableBuilder<AppUpdateDownloadProgress?>(
        valueListenable: progress,
        builder: (context, value, _) {
          final percent = value?.percent;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(child: Text('正在下载更新包...')),
                  if (percent != null)
                    Text(
                      '$percent%',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textBody,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  // fraction 为 null 时交给不确定态动画。
                  value: value?.fraction,
                  minHeight: 6,
                  color: AppColors.primary,
                  backgroundColor: AppColors.tint.withValues(alpha: 0.2),
                ),
              ),
              if (value != null && value.receivedBytes > 0) ...[
                const SizedBox(height: 10),
                Text(
                  value.sizeLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
