import 'package:flutter/material.dart';
import 'package:campus_app/theme/app_theme.dart';

enum AppButtonStyle { filled, gradient, outlined, tonal }

/// 品牌按钮 —— 按压 `scale(0.97)` / 120ms 强 ease-out 反馈
class AppButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final AppButtonStyle style;
  final Color? color;
  final LinearGradient? gradient;
  final double? width;
  final double height;

  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.style = AppButtonStyle.gradient,
    this.color,
    this.gradient,
    this.width,
    this.height = 48,
  });

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _isPressed = false;

  static const _defaultGradient = AppColors.primaryGradient;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.isLoading;

    final childContent = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.isLoading) ...[
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: Colors.white,
            ),
          ),
        ] else ...[
          if (widget.icon != null) ...[
            Icon(widget.icon, size: 18),
            const SizedBox(width: 8),
          ],
          Text(
            widget.label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ],
    );

    Widget buttonWidget;

    switch (widget.style) {
      case AppButtonStyle.gradient:
        buttonWidget = Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            gradient: enabled ? (widget.gradient ?? _defaultGradient) : null,
            color: enabled ? null : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(AppRadius.md),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: (widget.color ?? AppColors.primary).withValues(
                        alpha: 0.25,
                      ),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.md),
              onTap: enabled ? widget.onPressed : null,
              onHighlightChanged: (highlight) {
                setState(() => _isPressed = highlight);
              },
              child: Center(
                child: DefaultTextStyle(
                  style: const TextStyle(color: Colors.white),
                  child: IconTheme(
                    data: const IconThemeData(color: Colors.white),
                    child: childContent,
                  ),
                ),
              ),
            ),
          ),
        );
        break;

      case AppButtonStyle.filled:
        final primaryColor = widget.color ?? AppColors.primary;
        buttonWidget = SizedBox(
          width: widget.width,
          height: widget.height,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: primaryColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
            ),
            onPressed: enabled ? widget.onPressed : null,
            child: childContent,
          ),
        );
        break;

      case AppButtonStyle.outlined:
        final strokeColor = widget.color ?? AppColors.primary;
        buttonWidget = SizedBox(
          width: widget.width,
          height: widget.height,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: strokeColor,
              side: BorderSide(
                color: strokeColor.withValues(alpha: 0.6),
                width: 1.5,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
            ),
            onPressed: enabled ? widget.onPressed : null,
            child: childContent,
          ),
        );
        break;

      case AppButtonStyle.tonal:
        final tonalBg = (widget.color ?? AppColors.tint).withValues(
          alpha: 0.14,
        );
        final tonalFg = widget.color ?? AppColors.primary;
        buttonWidget = SizedBox(
          width: widget.width,
          height: widget.height,
          child: FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: tonalBg,
              foregroundColor: tonalFg,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
            ),
            onPressed: enabled ? widget.onPressed : null,
            child: childContent,
          ),
        );
        break;
    }

    return AnimatedScale(
      scale: _isPressed ? AppMotion.pressScale : 1.0,
      duration: AppMotion.press,
      curve: AppMotion.easeOutStrong,
      child: buttonWidget,
    );
  }
}
