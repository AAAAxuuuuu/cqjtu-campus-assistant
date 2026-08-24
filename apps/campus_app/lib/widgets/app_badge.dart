import 'package:flutter/material.dart';
import 'package:campus_app/theme/app_theme.dart';

/// 徽章形状。
enum AppBadgeShape {
  /// 圆角矩形（默认，用于课表格子内的短标签）。
  rounded,

  /// 全圆药丸（用于培养计划等标签密集的列表）。
  pill,
}

/// 品牌徽章 —— 淡色底 + 品牌色文字
///
/// 页面里原本有四套各自手写的胶囊标签实现：`course_cell` 两处（本周无课 /
/// 考试·自定义）、`study_progress_page` 两处（`_SmallTag` / `_StatusTag`）。
/// 差异只在「有无描边、圆角是 12 还是全圆、底色是品牌色还是中性灰」，所以
/// 这里用 [shape]、[bordered]、[color] 三个参数把它们统一进来。
class AppBadge extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;
  final Color? textColor;
  final Color? backgroundColor;
  final double fontSize;
  final EdgeInsetsGeometry padding;
  final AppBadgeShape shape;

  /// 是否画一圈同色描边。中性灰标签（原 `_SmallTag`）不需要。
  final bool bordered;

  const AppBadge({
    super.key,
    required this.label,
    this.icon,
    this.color = AppColors.primary,
    this.textColor,
    this.backgroundColor,
    this.fontSize = 11.5,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    this.shape = AppBadgeShape.rounded,
    this.bordered = true,
  });

  /// 中性灰标签：无描边、药丸形、文字用 muted（原 `_SmallTag`）。
  const AppBadge.neutral({
    super.key,
    required this.label,
    this.icon,
    this.fontSize = 11,
    this.padding = const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
  }) : color = AppColors.outline,
       textColor = AppColors.textMuted,
       backgroundColor = null,
       shape = AppBadgeShape.pill,
       bordered = false;

  /// 语义状态标签：语义色底 + 语义色字、药丸形、无描边（原 `_StatusTag`）。
  const AppBadge.status({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.fontSize = 11,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
  }) : textColor = null,
       backgroundColor = null,
       shape = AppBadgeShape.pill,
       bordered = false;

  /// 实底标签：饱和底色 + 白字，用于「本周」这类需要强调的小标记。
  const AppBadge.solid({
    super.key,
    required this.label,
    this.color = AppColors.primary,
    this.icon,
    this.fontSize = 10,
    this.padding = const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
  }) : textColor = Colors.white,
       backgroundColor = color,
       shape = AppBadgeShape.pill,
       bordered = false;

  @override
  Widget build(BuildContext context) {
    final fgColor = textColor ?? color;
    final bgColor =
        backgroundColor ??
        color.withValues(alpha: shape == AppBadgeShape.pill ? 0.12 : 0.14);
    final radius = shape == AppBadgeShape.pill ? 999.0 : 12.0;

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(radius),
        border: bordered
            ? Border.all(color: color.withValues(alpha: 0.3), width: 1)
            : null,
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
