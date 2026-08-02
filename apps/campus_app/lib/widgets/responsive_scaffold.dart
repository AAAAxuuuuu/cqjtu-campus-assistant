import 'package:flutter/material.dart';
import 'package:campus_app/theme/app_theme.dart';
import 'package:campus_app/widgets/glass_surface.dart';

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
class ResponsiveScaffold extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final isWideScreen = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      body: Row(
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
            // Apple 风格 tab 切换：纯 crossfade，无位移无缩放——
            // 内容在手指下原地淡入淡出，不打断阅读流（Interruptibility）
            child: AnimatedSwitcher(
              duration: AppMotion.standard,
              switchInCurve: AppMotion.easeOutStrong,
              switchOutCurve: AppMotion.easeInOutStrong,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: child,
                );
              },
              child: KeyedSubtree(
                key: ValueKey<int>(currentIndex),
                child: pages[currentIndex],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: isWideScreen
          ? null
          : GlassSurface(
              border: Border(
                top: BorderSide(
                  color: Colors.white.withValues(alpha: 0.6),
                  width: 0.5,
                ),
              ),
              child: SafeArea(
                top: false,
                child: NavigationBar(
                  selectedIndex: currentIndex,
                  onDestinationSelected: onTabSelected,
                  destinations: destinations,
                  elevation: 0,
                  backgroundColor: Colors.transparent,
                  indicatorColor: AppColors.primary.withValues(alpha: 0.16),
                ),
              ),
            ),
    );
  }
}
