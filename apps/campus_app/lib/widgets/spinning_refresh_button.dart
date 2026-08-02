import 'package:flutter/material.dart';
import 'package:campus_app/theme/app_theme.dart';

/// 旋转刷新按钮 —— 点击时图标转一圈，视觉确认「刷新已触发」
///
/// Apple Multimodal Feedback 原则：反馈必须由实际因果事件触发，
/// 点击刷新的瞬间图标旋转，告诉用户「动作已收到」。
/// 旋转用 [AppMotion.easeOutStrong]，300ms 内完成，< 400ms 不拖沓。
class SpinningRefreshButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final double size;
  final Color? color;
  final String? tooltip;

  const SpinningRefreshButton({
    super.key,
    this.onPressed,
    this.size = 20,
    this.color,
    this.tooltip = '刷新',
  });

  @override
  State<SpinningRefreshButton> createState() => _SpinningRefreshButtonState();
}

class _SpinningRefreshButtonState extends State<SpinningRefreshButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handlePressed() {
    // 从当前角度继续转，快速连点可中断重定向（Interruptibility）
    _controller.forward(from: 0);
    widget.onPressed?.call();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return IconButton(
      tooltip: widget.tooltip,
      onPressed: widget.onPressed == null ? null : _handlePressed,
      icon: reduceMotion
          ? Icon(Icons.refresh, size: widget.size, color: widget.color)
          : RotationTransition(
              turns: CurvedAnimation(
                parent: _controller,
                curve: AppMotion.easeOutStrong,
              ),
              child: Icon(
                Icons.refresh,
                size: widget.size,
                color: widget.color,
              ),
            ),
    );
  }
}
