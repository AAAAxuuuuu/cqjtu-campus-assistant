import 'package:flutter/material.dart';
import 'package:campus_app/theme/app_theme.dart';

/// 入场动效组件 —— 交错（stagger）+ scale(0.95) + opacity 进入
///
/// 遵循 Design Engineering 规则：
/// - 入场从 `scale(0.95) + opacity 0` 开始（绝不从 scale(0)，物体要有形状感）
/// - 强 ease-out 曲线，标准时长 < 300ms
/// - 相邻项间隔 [AppMotion.staggerStep]，通过 `Interval` 折叠进动画曲线，
///   无定时器、可中断，避免依赖挂起的 Timer
/// - 尊重系统"减少动效"设置（[MediaQuery.disableAnimationsOf]）
class AppEntrance extends StatefulWidget {
  /// 交错序号（从 0 开始）
  final int index;

  final Widget child;

  /// 向上滑入的距离
  final double slideOffset;

  const AppEntrance({
    super.key,
    this.index = 0,
    required this.child,
    this.slideOffset = 16,
  });

  @override
  State<AppEntrance> createState() => _AppEntranceState();
}

class _AppEntranceState extends State<AppEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    // 交错延迟通过 Interval 折叠进单个动画，总时长 = 延迟 + 标准时长。
    // 延迟阶段动画值为 0（保持隐藏），进入阶段按强 ease-out 展开。
    final delayMs = widget.index * AppMotion.staggerStep.inMilliseconds;
    final totalMs = delayMs + AppMotion.standard.inMilliseconds;

    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: totalMs),
    );

    _animation = CurvedAnimation(
      parent: _controller,
      curve: Interval(delayMs / totalMs, 1.0, curve: AppMotion.easeOutStrong),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return widget.child;
    }

    return FadeTransition(
      opacity: _animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset(0, widget.slideOffset / 400),
          end: Offset.zero,
        ).animate(_animation),
        child: ScaleTransition(
          scale: Tween<double>(
            begin: AppMotion.enterScale,
            end: 1.0,
          ).animate(_animation),
          child: widget.child,
        ),
      ),
    );
  }
}
