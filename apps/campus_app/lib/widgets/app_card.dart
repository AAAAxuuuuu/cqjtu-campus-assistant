import 'package:flutter/material.dart';
import 'package:campus_app/theme/app_theme.dart';

/// 品牌卡片 —— 白卡 + 柔和品牌色阴影（Apple Simplicity：层次来自阴影与留白）
///
/// - 无描边：白色表面靠阴影从背景浮起，不需要边框
/// - 阴影用品牌色微光，比黑灰阴影更贴合主题
/// - 按压反馈：`scale(0.98)`，120ms 强 ease-out
class AppCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final LinearGradient? gradient;
  final Color? backgroundColor;
  final Color? borderColor;
  final double borderRadius;
  final VoidCallback? onTap;
  final double elevation;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.margin = EdgeInsets.zero,
    this.gradient,
    this.backgroundColor,
    this.borderColor,
    this.borderRadius = AppRadius.lg,
    this.onTap,
    this.elevation = 4,
  });

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final border = widget.borderColor != null
        ? Border.all(color: widget.borderColor!, width: 1)
        : null;

    final defaultBg =
        widget.backgroundColor ?? AppColors.surfaceCard.withValues(alpha: 0.95);

    Widget cardContent = Container(
      margin: widget.margin,
      decoration: BoxDecoration(
        color: widget.gradient == null ? defaultBg : null,
        gradient: widget.gradient,
        borderRadius: BorderRadius.circular(widget.borderRadius),
        border: border,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(
              alpha: widget.elevation * 0.015,
            ),
            blurRadius: widget.elevation * 4,
            offset: Offset(0, widget.elevation * 0.8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            onHighlightChanged: widget.onTap != null
                ? (highlight) => setState(() => _isPressed = highlight)
                : null,
            child: Padding(padding: widget.padding, child: widget.child),
          ),
        ),
      ),
    );

    if (widget.onTap != null) {
      return AnimatedScale(
        scale: _isPressed ? AppMotion.cardPressScale : 1.0,
        duration: AppMotion.press,
        curve: AppMotion.easeOutStrong,
        child: cardContent,
      );
    }

    return cardContent;
  }
}
