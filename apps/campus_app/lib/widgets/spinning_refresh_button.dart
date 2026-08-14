import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:campus_app/theme/app_theme.dart';

enum _RefreshOutcome { none, running, success, failure }

/// 旋转刷新按钮 —— 点击时图标转一圈，完成后给出成功/失败反馈
///
/// 反馈由实际因果事件触发：按下瞬间旋转（动作已收到），
/// [onPressed] 返回的 Future 结束后短暂显示对勾（成功）或感叹号（失败），
/// 约 1.2 秒后恢复为刷新图标。失败时附加强烈触觉反馈。
class SpinningRefreshButton extends StatefulWidget {
  final Future<void> Function()? onPressed;
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
  _RefreshOutcome _outcome = _RefreshOutcome.none;

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

  Future<void> _handlePressed() async {
    // 从当前角度继续转，快速连点可中断重定向（Interruptibility）
    _controller.forward(from: 0);
    final onPressed = widget.onPressed;
    if (onPressed == null) return;
    setState(() => _outcome = _RefreshOutcome.running);
    try {
      await onPressed();
      if (!mounted) return;
      HapticFeedback.lightImpact();
      setState(() => _outcome = _RefreshOutcome.success);
    } catch (_) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() => _outcome = _RefreshOutcome.failure);
    }
    Future<void>.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _outcome = _RefreshOutcome.none);
    });
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    final IconData icon = switch (_outcome) {
      _RefreshOutcome.success => Icons.check_circle_outline,
      _RefreshOutcome.failure => Icons.error_outline,
      _RefreshOutcome.running || _RefreshOutcome.none => Icons.refresh,
    };

    final Color? iconColor = switch (_outcome) {
      _RefreshOutcome.success => AppColors.success,
      _RefreshOutcome.failure => AppColors.danger,
      _RefreshOutcome.running || _RefreshOutcome.none => widget.color,
    };

    return IconButton(
      tooltip: widget.tooltip,
      onPressed: widget.onPressed == null ? null : _handlePressed,
      icon: reduceMotion
          ? Icon(icon, size: widget.size, color: iconColor)
          : RotationTransition(
              turns: CurvedAnimation(
                parent: _controller,
                curve: AppMotion.easeOutStrong,
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: Icon(
                  icon,
                  key: ValueKey(icon),
                  size: widget.size,
                  color: iconColor,
                ),
              ),
            ),
    );
  }
}
