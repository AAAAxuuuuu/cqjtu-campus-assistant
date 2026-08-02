import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:campus_app/theme/app_theme.dart';

/// Apple Translucent Chrome —— 毛玻璃 AppBar///
/// 顶部透明，向下滚动时浮起「半透明白 + 模糊」材质，
/// 内容从玻璃下透出；玻璃下缘一道亮边模拟光线打在白材料上的反光。
///
/// 细节（Craft）：
/// - 滚动阈值 1px：手指一动材质立刻响应，无迟滞死区（Response）
/// - 尊重系统「减少动效」：禁用时直接切换不透明度，不做模糊渐变
///
/// 用法：`GlassAppBar(title: Text('服务'))`，可完全替代普通 AppBar。
class GlassAppBar extends StatefulWidget implements PreferredSizeWidget {
  final Widget? title;
  final Widget? leading;
  final List<Widget>? actions;
  final bool centerTitle;

  const GlassAppBar({
    super.key,
    this.title,
    this.leading,
    this.actions,
    this.centerTitle = true,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  State<GlassAppBar> createState() => _GlassAppBarState();
}

class _GlassAppBarState extends State<GlassAppBar> {
  bool _scrolled = false;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    final toolbar = Container(
      color: _scrolled
          ? Colors.white.withValues(alpha: 0.82)
          : Colors.transparent,
      child: AppBar(
        title: widget.title,
        leading: widget.leading,
        actions: widget.actions,
        centerTitle: widget.centerTitle,
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
    );

    return NotificationListener<ScrollNotification>(
      // 阈值 1px：滚动刚开始就点亮材质，无 8px 死区迟滞
      onNotification: (notification) {
        final isScrolled = notification.metrics.pixels > 1;
        if (isScrolled != _scrolled) {
          setState(() => _scrolled = isScrolled);
        }
        return false;
      },
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: _scrolled ? 18 : 0,
            sigmaY: _scrolled ? 18 : 0,
            tileMode: TileMode.clamp,
          ),
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              // 透明时无材质，滚动后浮起白色半透明层
              AnimatedContainer(
                duration: reduceMotion ? Duration.zero : AppMotion.standard,
                curve: AppMotion.easeOutStrong,
                color: _scrolled
                    ? Colors.white.withValues(alpha: 0.72)
                    : Colors.transparent,
              ),
              toolbar,
            ],
          ),
        ),
      ),
    );
  }
}

/// 毛玻璃浮层（底部导航等悬浮条通用）
///
/// Apple Translucent Chrome：半透明白 + 模糊，上缘亮边。
class GlassSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BoxBorder? border;
  final Color? backgroundColor;

  const GlassSurface({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.border,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 18,
          sigmaY: 18,
          tileMode: TileMode.clamp,
        ),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: backgroundColor ?? Colors.white.withValues(alpha: 0.72),
            border: border,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.06),
                blurRadius: 16,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
