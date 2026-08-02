import 'package:flutter/material.dart';
import 'package:campus_app/theme/app_theme.dart';

/// 品牌徽章 —— 淡色底 + 品牌色文字
class AppBadge extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;
  final Color? textColor;
  final double fontSize;
  final EdgeInsetsGeometry padding;

  const AppBadge({
    super.key,
    required this.label,
    this.icon,
    this.color = AppColors.primary,
    this.textColor,
    this.fontSize = 11.5,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
  });

  @override
  Widget build(BuildContext context) {
    final fgColor = textColor ?? color;
    final bgColor = color.withValues(alpha: 0.14);

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: fontSize + 2, color: fgColor),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: fgColor,
            ),
          ),
        ],
      ),
    );
  }
}
