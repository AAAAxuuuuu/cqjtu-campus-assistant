import 'package:flutter/material.dart';
import 'package:campus_app/theme/app_theme.dart';

/// SnackBar 反馈分色 —— Apple 四类反馈：状态/完成/警告/错误
///
/// - 状态（信息）→ 品牌深色底
/// - 完成（成功）→ 品牌绿
/// - 警告 → 暖沙金
/// - 错误 → 品牌红
///
/// 用法：`AppSnackBar.success(context, '余额已更新')`
abstract final class AppSnackBar {
  static void show(
    BuildContext context,
    String message, {
    IconData? icon,
    Color? color,
  }) {
    final effectiveColor = color ?? AppColors.textPrimary;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: effectiveColor,
        content: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
            ],
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  /// 状态/信息
  static void status(BuildContext context, String message) =>
      show(context, message, icon: Icons.info_outline);

  /// 完成/成功
  static void success(BuildContext context, String message) => show(
    context,
    message,
    icon: Icons.check_circle_outline,
    color: AppColors.success,
  );

  /// 警告
  static void warning(BuildContext context, String message) => show(
    context,
    message,
    icon: Icons.warning_amber_outlined,
    color: AppColors.warning,
  );

  /// 错误
  static void error(BuildContext context, String message) => show(
    context,
    message,
    icon: Icons.error_outline,
    color: AppColors.danger,
  );
}
