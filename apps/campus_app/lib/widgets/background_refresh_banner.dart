import 'dart:async';

import 'package:flutter/material.dart';
import 'package:campus_app/theme/app_theme.dart';

class BackgroundRefreshBanner extends StatefulWidget {
  const BackgroundRefreshBanner({
    super.key,
    required this.onRefresh,
    this.message = '后台刷新连续失败，当前显示的是上次缓存。',
  });

  final FutureOr<void> Function() onRefresh;
  final String message;

  @override
  State<BackgroundRefreshBanner> createState() =>
      _BackgroundRefreshBannerState();
}

class _BackgroundRefreshBannerState extends State<BackgroundRefreshBanner> {
  bool _isRefreshing = false;

  Future<void> _handleRefresh() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    try {
      final res = widget.onRefresh();
      if (res is Future) {
        await res;
      }
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.sync_problem,
            color: AppColors.warning.withValues(alpha: 0.9),
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.message,
              style: TextStyle(color: AppColors.textBody, fontSize: 12),
            ),
          ),
          TextButton.icon(
            onPressed: _isRefreshing ? null : _handleRefresh,
            icon: _isRefreshing
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.warning,
                      ),
                    ),
                  )
                : const Icon(Icons.refresh, size: 16),
            label: Text(_isRefreshing ? '正在刷新' : '手动刷新'),
          ),
        ],
      ),
    );
  }
}
