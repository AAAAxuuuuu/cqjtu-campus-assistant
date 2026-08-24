import 'package:flutter/material.dart';
import 'package:campus_app/theme/app_theme.dart';

/// 品牌列表项 —— 图标容器 + 标题/副标题 + 按压反馈
class AppListTile extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const AppListTile({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  State<AppListTile> createState() => _AppListTileState();
}

class _AppListTileState extends State<AppListTile> {
  bool _isPressed = false;

  void _setPressed(bool pressed) {
    if (!mounted || widget.onTap == null || _isPressed == pressed) return;
    setState(() => _isPressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _isPressed ? AppMotion.cardPressScale : 1.0,
        duration: AppMotion.press,
        curve: AppMotion.easeOutStrong,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          leading: Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  widget.iconColor.withValues(alpha: 0.20),
                  widget.iconColor.withValues(alpha: 0.06),
                ],
              ),
              borderRadius: BorderRadius.circular(AppRadius.sm + 2),
              border: Border.all(
                color: widget.iconColor.withValues(alpha: 0.18),
                width: 1,
              ),
            ),
            child: Icon(widget.icon, color: widget.iconColor, size: 20),
          ),
          title: Text(
            widget.title,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14.5,
              color: AppColors.textBody,
            ),
          ),
          subtitle: widget.subtitle != null
              ? Text(
                  widget.subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textMuted,
                  ),
                )
              : null,
          trailing:
              widget.trailing ??
              const Icon(
                Icons.chevron_right,
                color: Color(0xFFAAAABB),
                size: 20,
              ),
          // Fires immediately. The press animation is driven by the pointer
          // Listener wrapped around this tile instead of gating the callback.
          //
          // This used to wrap onTap in `Future.delayed(AppMotion.press)` so the
          // scale-down could finish first, which put a 120ms delay in front of
          // every navigation in the 服务 tab (AppListTile backs all of its rows)
          // — and silently dropped the tap when the widget unmounted inside that
          // window.
          onTap: widget.onTap,
        ),
      ),
    );
  }
}
