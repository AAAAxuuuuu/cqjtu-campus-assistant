import 'package:flutter/material.dart';
import 'package:campus_app/theme/app_theme.dart';

class BackgroundRefreshBanner extends StatelessWidget {
  const BackgroundRefreshBanner({
    super.key,
    required this.onRefresh,
    this.message = '后台刷新连续失败，当前显示的是上次缓存。',
  });

  final VoidCallback onRefresh;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: AppColors.warning.withValues(alpha: 0.25),
        ),
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
              message,
              style: TextStyle(
                color: AppColors.textBody,
                fontSize: 12,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('手动刷新'),
          ),
        ],
      ),
    );
  }
}
