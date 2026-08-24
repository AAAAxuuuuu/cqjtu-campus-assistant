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
  final PreferredSizeWidget? bottom;

  const GlassAppBar({
    super.key,
    this.title,
    this.leading,
    this.actions,
    this.centerTitle = true,
    this.bottom,
  });

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0.0));

  @override
  State<GlassAppBar> createState() => _GlassAppBarState();
}

class _GlassAppBarState extends State<GlassAppBar> {
  bool _scrolled = false;
  ScrollNotificationObserverState? _observer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Every consumer passes this widget to `Scaffold(appBar:)`, which makes it
    // a *sibling* of `body` rather than an ancestor. A NotificationListener
    // wrapped around the toolbar therefore never sees the body's scroll
    // notifications — they bubble up through Scaffold, not through us. Scaffold
    // installs a ScrollNotificationObserver above both slots for exactly this
    // case, so subscribe to that instead of listening to our own subtree.
    final observer = ScrollNotificationObserver.maybeOf(context);
    if (observer == _observer) return;
    _observer?.removeListener(_handleScrollNotification);
    _observer = observer?..addListener(_handleScrollNotification);
  }

  @override
  void dispose() {
    _observer?.removeListener(_handleScrollNotification);
    _observer = null;
    super.dispose();
  }

  void _handleScrollNotification(ScrollNotification notification) {
    if (notification is! ScrollUpdateNotification &&
        notification is! ScrollMetricsNotification) {
      return;
    }
    // Only the primary vertical scrollable sits under the toolbar; horizontal
    // scrollers (the timetable's day columns) and nested pickers must not
    // toggle the material.
    if (notification.metrics.axis != Axis.vertical) return;
    if (notification.depth != 0) return;

    // 阈值 1px：滚动刚开始就点亮材质，无 8px 死区迟滞
    final isScrolled = notification.metrics.extentBefore > 1;
    if (isScrolled != _scrolled && mounted) {
      setState(() => _scrolled = isScrolled);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    // 始终透明：材质由下方的背景层负责。这里再叠一层白底会盖掉玻璃。
    //
    // foregroundColor / titleTextStyle 必须显式钉死。透明背景下 Material 会
    // 走 surface-tint 推导，把前景算成接近白色 —— 表现就是"我的""服务"等
    // 页面标题在浅色背景上完全看不见（课表页因为自己写了 color 才没受影响）。
    final toolbar = AppBar(
      title: widget.title,
      leading: widget.leading,
      actions: widget.actions,
      centerTitle: widget.centerTitle,
      bottom: widget.bottom,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: AppColors.textPrimary,
      titleTextStyle: AppType.pageTitle.copyWith(color: AppColors.textPrimary),
      iconTheme: const IconThemeData(color: AppColors.textPrimary),
      actionsIconTheme: const IconThemeData(color: AppColors.primaryInk),
      elevation: 0,
      scrolledUnderElevation: 0,
    );

    return Stack(
      fit: StackFit.passthrough,
      children: [
        // 背景材质层：BackdropFilter 必须只包住背景，不能包住 toolbar。
        //
        // 之前整个 Stack（含 toolbar）都在 BackdropFilter 的子树里，
        // 于是标题文字、操作图标、以及 appBar 延伸到的状态栏区域全部被一起
        // 模糊——页面标题看起来是"糊的"。BackdropFilter 模糊的是它下方已经
        // 绘制的内容，所以它只应该覆盖背景区域，前景内容要放在滤镜之外。
        //
        // 材质构成与 GlassSurface 一致（折射 + 厚度渐变 + 上下缘），
        // 让顶栏和底栏看起来是同一种玻璃。
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: _scrolled ? 1.0 : 0.0,
              duration: reduceMotion ? Duration.zero : AppMotion.standard,
              curve: AppMotion.easeOutStrong,
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.compose(
                    outer: GlassSurface._refraction,
                    inner: ImageFilter.blur(
                      sigmaX: 24,
                      sigmaY: 24,
                      tileMode: TileMode.clamp,
                    ),
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: 0.78),
                          Colors.white.withValues(alpha: 0.62),
                          Colors.white.withValues(alpha: 0.44),
                        ],
                        stops: const [0.0, 0.6, 1.0],
                      ),
                      border: Border(
                        bottom: BorderSide(
                          color: AppColors.textPrimary.withValues(alpha: 0.05),
                          width: 0.5,
                        ),
                      ),
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        ),
        // 前景：标题与操作按钮，始终清晰。
        toolbar,
      ],
    );
  }
}

/// 液态玻璃浮层（底部导航等悬浮条通用）
///
/// 与普通毛玻璃（单层模糊 + 半透明白）的区别在于「厚度感」：真实玻璃是有体积
/// 的物体，光线穿过时会发生折射、在边缘聚集，并在上下缘留下高光和暗边。所以
/// 这里叠了五层，每层对应一个物理现象：
///
/// 1. **主体折射** —— 大半径模糊 + 轻微饱和度提升（`ColorFilter.matrix`）。
///    真玻璃会让穿过的颜色更浓，只做模糊会显得像磨砂塑料。
/// 2. **厚度渐变** —— 顶部更亮、底部更实的垂直渐变，模拟光线穿过玻璃体时的
///    衰减。这是"薄片"和"块体"观感的分界。
/// 3. **上缘高光** —— 1px 亮白边，光打在玻璃顶面的反射。
/// 4. **下缘暗边** —— 极淡的暗线，玻璃底面的内反射。
/// 5. **边缘光晕** —— 品牌色极低透明度外扩，玻璃体边缘的色散。
///
/// 这些层全部在 [BackdropFilter] 之内或之下，[child] 始终在最上层且不受
/// 任何滤镜影响。
class GlassSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BoxBorder? border;
  final Color? backgroundColor;

  /// 玻璃厚度。越大折射越强、渐变跨度越大。
  final double thickness;

  const GlassSurface({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.border,
    this.backgroundColor,
    this.thickness = 1.0,
  });

  /// 轻微提升饱和度：让穿过玻璃的颜色更浓，而不是被模糊洗淡。
  static const ColorFilter _refraction = ColorFilter.matrix(<double>[
    1.18, -0.09, -0.09, 0, 0, //
    -0.09, 1.18, -0.09, 0, 0, //
    -0.09, -0.09, 1.18, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);

  @override
  Widget build(BuildContext context) {
    final blur = 28.0 * thickness;

    return Stack(
      fit: StackFit.passthrough,
      children: [
        // ── 1. 玻璃体：折射 + 大半径模糊 ────────────────────────
        Positioned.fill(
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.compose(
                outer: _refraction,
                inner: ImageFilter.blur(
                  sigmaX: blur,
                  sigmaY: blur,
                  tileMode: TileMode.clamp,
                ),
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        // ── 2. 厚度渐变：顶亮底实，玻璃体的光衰减 ───────────────
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: border,
                gradient: backgroundColor == null
                    ? LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: 0.42),
                          Colors.white.withValues(alpha: 0.58),
                          Colors.white.withValues(alpha: 0.72),
                        ],
                        stops: const [0.0, 0.55, 1.0],
                      )
                    : null,
                color: backgroundColor,
                boxShadow: [
                  // 5. 边缘色散：品牌色极淡外扩
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.07),
                    blurRadius: 20,
                    offset: const Offset(0, -6),
                  ),
                ],
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        // ── 3. 上缘高光：光打在玻璃顶面的反射 ──────────────────
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.25),
                    Colors.white.withValues(alpha: 0.92),
                    Colors.white.withValues(alpha: 0.25),
                  ],
                ),
              ),
            ),
          ),
        ),
        // ── 4. 下缘暗边：玻璃底面的内反射 ──────────────────────
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Container(
              height: 0.5,
              color: AppColors.textPrimary.withValues(alpha: 0.05),
            ),
          ),
        ),
        // 前景内容：永远不受任何滤镜影响
        Padding(padding: padding, child: child),
      ],
    );
  }
}
