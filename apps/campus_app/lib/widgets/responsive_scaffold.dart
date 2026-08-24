import 'package:flutter/material.dart';
import 'package:campus_app/theme/app_theme.dart';
import 'package:campus_app/widgets/liquid_glass.dart';

/// 响应式框架 —— 宽屏 NavigationRail / 窄屏毛玻璃 NavigationBar
///
/// Apple Translucent Chrome 原则：
/// - 底部导航是半透明毛玻璃层（BackdropFilter + 白色 72%），
///   内容滚动时从材质下透出，导航不占一条不透明白带
/// - 玻璃边缘一道 1px 亮边，模拟光线打在白材料上的反光
///
/// 页面切换动效遵循 Design Engineering 规则：
/// - 进场强 ease-out（快速响应），退场强 ease-in（快速离场）
/// - 从不从 scale(0) 进入，从 0.98 + opacity 过渡
class ResponsiveScaffold extends StatefulWidget {
  const ResponsiveScaffold({
    super.key,
    required this.currentIndex,
    required this.onTabSelected,
    required this.pages,
    required this.destinations,
    required this.railDestinations,
  });

  final int currentIndex;
  final ValueChanged<int> onTabSelected;
  final List<Widget> pages;
  final List<NavigationDestination> destinations;
  final List<NavigationRailDestination> railDestinations;

  @override
  State<ResponsiveScaffold> createState() => _ResponsiveScaffoldState();
}

class _ResponsiveScaffoldState extends State<ResponsiveScaffold> {
  /// 切换方向：+1 向右（索引变大），-1 向左。
  ///
  /// 需要记住上一个索引才能判断方向 —— 这也是本组件必须有状态的原因。
  int _direction = 1;
  late int _previousIndex = widget.currentIndex;

  @override
  void didUpdateWidget(ResponsiveScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentIndex != oldWidget.currentIndex) {
      _direction = widget.currentIndex > oldWidget.currentIndex ? 1 : -1;
      _previousIndex = oldWidget.currentIndex;
    }
  }

  int get currentIndex => widget.currentIndex;
  ValueChanged<int> get onTabSelected => widget.onTabSelected;
  List<Widget> get pages => widget.pages;
  List<NavigationDestination> get destinations => widget.destinations;
  List<NavigationRailDestination> get railDestinations =>
      widget.railDestinations;

  @override
  Widget build(BuildContext context) {
    final isWideScreen = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      // Without extendBody the body stops above the navigation bar, so there is
      // nothing behind the glass to blur and the translucency is wasted.
      // Pages already reserve bottom inset where it matters (see
      // schedule_utils.dart `_kTimetableBottomInset`).
      extendBody: true,
      body: Stack(
        children: [
          Positioned.fill(child: _buildContent(isWideScreen)),
          // 悬浮胶囊导航叠在内容之上。宽屏用 NavigationRail，不需要它。
          if (!isWideScreen)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: FloatingGlassNavBar(
                currentIndex: currentIndex,
                onTabSelected: onTabSelected,
                destinations: destinations,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContent(bool isWideScreen) {
    return Row(
      children: [
        if (isWideScreen)
          NavigationRail(
            selectedIndex: currentIndex,
            onDestinationSelected: onTabSelected,
            labelType: NavigationRailLabelType.all,
            destinations: railDestinations,
            backgroundColor: Colors.white,
            elevation: 2,
            indicatorColor: AppColors.primary.withValues(alpha: 0.16),
          ),
        Expanded(
          // IndexedStack keeps every tab's element tree alive across
          // switches, preserving scroll offset and provider subscriptions.
          //
          // This was an AnimatedSwitcher over
          // `KeyedSubtree(key: ValueKey(currentIndex))`, which tore the
          // outgoing page down and rebuilt the incoming one from scratch:
          // scroll position in 服务/我的 was lost on every switch, and
          // CampusCardPage's initState refresh re-fired each time the user
          // returned to it. The crossfade also kept both pages laid out at
          // once for its whole duration.
          child: IndexedStack(
            index: currentIndex,
            sizing: StackFit.expand,
            children: [
              for (var i = 0; i < pages.length; i++)
                // Offstage tabs stay mounted but must not paint or take hits.
                Visibility(
                  visible: i == currentIndex,
                  maintainState: true,
                  child: _TabTransition(
                    // 只有刚成为当前页的那个才播入场动画；离场页不动
                    // （IndexedStack 会立刻隐藏它，播了也看不见）。
                    active: i == currentIndex,
                    direction: _direction,
                    // key 带上索引与切换序号，确保每次切到该页都重新播放。
                    animationKey: '$i-$currentIndex-$_previousIndex',
                    child: pages[i],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Tab 切换的入场动效：按方向轻微横移 + 淡入。
///
/// 为什么不用 `AnimatedSwitcher`：它靠替换子树来做过渡，而 tab 页必须始终挂载
/// 在 [IndexedStack] 里以保住滚动位置和 provider 订阅（换掉这个曾导致服务/我的
/// 每次切换都丢滚动位置、校园卡页重复发请求）。所以这里只在**已挂载**的页上
/// 播一次入场动画，不做交叉淡出——离场页会被 IndexedStack 立即隐藏，
/// 给它播动画是白费绘制。
///
/// 位移取 24px：够读出方向，又不会让整页"飞"进来。从 0.98 不透明度起步而非 0，
/// 避免闪烁感。
class _TabTransition extends StatefulWidget {
  const _TabTransition({
    required this.child,
    required this.active,
    required this.direction,
    required this.animationKey,
  });

  final Widget child;
  final bool active;
  final int direction;
  final String animationKey;

  @override
  State<_TabTransition> createState() => _TabTransitionState();
}

class _TabTransitionState extends State<_TabTransition>
    with SingleTickerProviderStateMixin {
  // 必须在 initState 立即创建，不能用 late final 懒初始化：reduce-motion 下
  // build 直接返回 child，controller 从未被访问，于是 dispose() 里第一次访问它
  // 反而**触发**了创建 —— 此时 vsync 所在的 element 已在销毁中，
  // 会抛 "Looking up a deactivated widget's ancestor is unsafe"。
  late final AnimationController _controller;
  late final Animation<double> _curved;

  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: AppMotion.standard,
      vsync: this,
      value: 1.0,
    );
    _curved = CurvedAnimation(
      parent: _controller,
      curve: AppMotion.easeOutStrong,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 必须在这里读、缓存下来：在 build 里调用会注册 InheritedWidget 依赖，
    // 而这些 tab 会随壳一起销毁，销毁期间再查祖先会触发
    // "Looking up a deactivated widget's ancestor is unsafe"。
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
  }

  @override
  void didUpdateWidget(_TabTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 成为当前页时从头播一次；已经是当前页则不打断。
    if (widget.active && widget.animationKey != oldWidget.animationKey) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_reduceMotion) return widget.child;

    final curved = _curved;

    return AnimatedBuilder(
      animation: curved,
      child: widget.child,
      builder: (context, child) {
        final t = curved.value;
        return Opacity(
          // 从 0.35 起步：完全透明会让切换显得"闪"，而不是"移入"。
          opacity: 0.35 + 0.65 * t,
          child: Transform.translate(
            offset: Offset(widget.direction * 24 * (1 - t), 0),
            child: child,
          ),
        );
      },
    );
  }
}

/// 悬浮胶囊式底部导航。
///
/// 与整条通栏的区别：左右留白让背景从两侧透出来，大圆角 + 阴影让它读作一块
/// 「浮在内容之上的玻璃」，而不是贴在屏幕底边的一条实心块。
class FloatingGlassNavBar extends StatelessWidget {
  const FloatingGlassNavBar({
    super.key,
    required this.currentIndex,
    required this.onTabSelected,
    required this.destinations,
  });

  final int currentIndex;
  final ValueChanged<int> onTabSelected;
  final List<NavigationDestination> destinations;

  /// 胶囊自身高度（不含安全区）。
  ///
  /// 这里不用 Material 的 [NavigationBar]：它的固有高度锁定在 80，压小会把
  /// 标签挤成零高度、图标溢出到胶囊之外（表现为整条导航点不动且只显示一半）。
  /// 自己排图标 + 标签，高度与垂直居中才可控。
  static const double barHeight = 62.0;

  /// 胶囊左右外边距。
  static const double sideMargin = 16.0;

  /// 胶囊与屏幕底边（安全区之上）的距离。
  static const double bottomGap = 12.0;

  /// 选中指示器尺寸。
  static const double _indicatorHeight = 30.0;
  static const double _indicatorWidth = 56.0;

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    final radius = barHeight / 2;

    return Padding(
      padding: EdgeInsets.only(
        left: sideMargin,
        right: sideMargin,
        bottom: safeBottom + bottomGap,
      ),
      child: DecoratedBox(
        // 阴影必须画在玻璃外层：BackdropFilter 会裁掉自己边界外的绘制，
        // 放在里面的话投影会被切掉。圆角要和玻璃一致，否则四角会露出底色。
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.14),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: AppColors.textPrimary.withValues(alpha: 0.06),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: LiquidGlassSurface(
          borderRadius: radius,
          thickness: 1.0,
          child: SizedBox(
            height: barHeight,
            child: Row(
              children: [
                for (var i = 0; i < destinations.length; i++)
                  Expanded(
                    child: _NavItem(
                      destination: destinations[i],
                      selected: i == currentIndex,
                      indicatorHeight: _indicatorHeight,
                      indicatorWidth: _indicatorWidth,
                      onTap: () => onTabSelected(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 胶囊内的单个导航项：药丸指示器 + 图标 + 标签，整体垂直居中。
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.indicatorHeight,
    required this.indicatorWidth,
    required this.onTap,
  });

  final NavigationDestination destination;
  final bool selected;
  final double indicatorHeight;
  final double indicatorWidth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primaryInk : AppColors.textMuted;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 药丸指示器只包住图标，不撑满整格。
            AnimatedContainer(
              duration: reduceMotion ? Duration.zero : AppMotion.quick,
              curve: AppMotion.easeOutStrong,
              width: indicatorWidth,
              height: indicatorHeight,
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primary.withValues(alpha: 0.14)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(indicatorHeight / 2),
              ),
              child: IconTheme(
                data: IconThemeData(color: color, size: 20),
                child: selected
                    ? (destination.selectedIcon ?? destination.icon)
                    : destination.icon,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              destination.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // 不随系统字号放大：胶囊是固定高度，放大会溢出。
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: 11,
                height: 1.1,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
