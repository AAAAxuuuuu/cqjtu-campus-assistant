import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart';

/// 品牌色板 —— CQJTU Hub
///
/// ## 角色分配（2026-08-22 重排）
///
/// 四个品牌色原本饱和度全部挤在 38–43%、亮度 57–77%，权重几乎相同，
/// 被平级当作四个语义色使用。两个后果：
///
/// 1. **没有主次。** 四个色一样重，视线没有落点。尤其 [tint] `#DDAACC` 与
///    [primary] `#BB6688` 只差 16° 色相，环形图里两者相邻时几乎分不出来。
/// 2. **没有一个色能承载白底小字。** WCAG AA 正文要求 4.5:1，四色实测
///    3.91 / 3.26 / 2.17 / 1.96，全部不达标——彩色小字看起来发虚。
///
/// 所以颜色本身不换（柔和玫紫的气质要保留），改的是**角色**：
///
/// | 角色 | 色值 | 用途 |
/// |------|------|------|
/// | [primary] | `#BB6688` | 唯一主色。渐变、大色块、按钮底、选中态 |
/// | [primaryInk] | `#983E62` | 主色的文字/图标版本，白底 6.56:1 |
/// | [secondary] | `#8888CC` | 唯一辅色。仅用于需要区分的第二数据序列 |
/// | [secondaryInk] | `#4D4D9D` | 辅色的文字版本，白底 7.33:1 |
/// | [accent] | `#CCAA88` | 仅「提示/待办」一个语义（唯一暖色） |
/// | [accentInk] | `#8C6136` | 暖色文字版本，白底 5.41:1 |
/// | [tint] | `#DDAACC` | **纯装饰**：渐变尾色、tint 底、选中态背景 |
///
/// ## 使用规则
///
/// - **白底上的文字与小图标一律用 `*Ink`**，不要用填充色——填充色对比度
///   在 1.96–3.91 之间，做正文必然发虚。
/// - **[tint] 不再承载语义。** 它和 [primary] 色相太近，一旦用来表示某个
///   数据维度就会和主色混淆。只做氛围。
/// - **[accent] 不要当第四个平级色用。** 它是唯一暖色（30°，与 [secondary]
///   240° 接近补色），当强调色比当平级色有价值得多。
abstract final class AppColors {
  // ── 填充色（色块、渐变、按钮底；其上放白色大字）──────────
  static const Color primary = Color(0xFFBB6688);
  static const Color secondary = Color(0xFF8888CC);
  static const Color accent = Color(0xFFCCAA88);
  static const Color tint = Color(0xFFDDAACC);

  // ── Ink 系列（白底上的文字与小图标，均 >= 4.5:1）───────────
  /// 主色的文字版本（336° 同色相压暗），白底 6.56:1。
  static const Color primaryInk = Color(0xFF983E62);

  /// 辅色的文字版本（240° 同色相压暗），白底 7.33:1。
  static const Color secondaryInk = Color(0xFF4D4D9D);

  /// 暖色的文字版本（30° 同色相压暗），白底 5.41:1。
  static const Color accentInk = Color(0xFF8C6136);

  /// 品牌色渐变
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, secondary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// 暖色渐变（电费卡片）
  ///
  /// 原为 `[primary, accent]`，即 336° → 30°：跨 54° 色相，玫红直接过渡到
  /// 驼色，两端在同一个卡片上互相打架。改为经 [tint] 320° 中转到 [accent]，
  /// 336° → 320° → 30° 逐段推进，暖意保留但过渡连续。
  static const LinearGradient warmGradient = LinearGradient(
    colors: [primary, tint, accent],
    stops: [0.0, 0.45, 1.0],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── 文本色 ───────────────────────────────────────────────
  static const Color textPrimary = Color(0xFF5E2E44);
  static const Color textSecondary = Color(0xFF333366);
  static const Color textBody = Color(0xFF333344);
  static const Color textMuted = Color(0xFF827885);

  // ── 表面与描边 ───────────────────────────────────────────
  static const Color surface = Color(0xFFFAF7F9);
  static const Color surfaceCard = Color(0xFFFFFFFF);
  static const Color outline = Color(0xFFEBDCE4);

  /// 品牌淡粉氛围层（tint 9%）
  static const Color tintSoft = Color(0x17DDAACC);

  /// 页面背景 —— 品牌渐变氛围（顶边玫瑰粉 → 薰衣草 → 暖沙金）
  static const LinearGradient pageGradient = LinearGradient(
    colors: [Color(0xFFFAF7F9), Color(0xFFF5EBF2), Color(0xFFF2EEE9)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  /// 页面背景的装饰光晕（超大径向渐变，叠在页面角落）
  static const RadialGradient pageGlow = RadialGradient(
    colors: [Color(0x33DDAACC), Color(0x00DDAACC)],
    center: Alignment.center,
    radius: 0.9,
  );

  /// 卡片渐变描边 —— 品牌四色的细亮边
  static const LinearGradient cardBorderGradient = LinearGradient(
    colors: [Color(0x66BB6688), Color(0x668888CC), Color(0x66CCAA88)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── 语义色（状态/成绩等业务语义保持独立）───────────────
  static const Color success = Color(0xFF2F9E6E);
  static const Color info = Color(0xFF4C6FA8);
  static const Color warning = Color(0xFFC89A5A);
  static const Color danger = Color(0xFFC25E68);
}

/// 动效设计令牌 —— 统一缓动曲线与时长
///
/// 遵循 Design Engineering 哲学：
/// - 入场一律强 ease-out，绝不 ease-in（响应感）
/// - 屏幕内位移用强 ease-in-out
/// - UI 动效一律 < 300ms
/// - 按压反馈 100–160ms
/// - 入场从不从 scale(0) 开始，从 0.95 + opacity 进入
abstract final class AppMotion {
  /// 强 ease-out：UI 入场/反馈默认曲线（≈ cubic-bezier(0.23, 1, 0.32, 1)）
  static const Curve easeOutStrong = Cubic(0.22, 1, 0.36, 1);

  /// 强 ease-in-out：屏幕内位移（≈ cubic-bezier(0.77, 0, 0.175, 1)）
  static const Curve easeInOutStrong = Cubic(0.77, 0, 0.175, 1);

  /// 退出用 ease-in（快入慢出，避免拖沓）
  static const Curve easeInStrong = Cubic(0.55, 0, 0.85, 0.36);

  /// 按压反馈时长（按钮/卡片）
  static const Duration press = Duration(milliseconds: 120);

  /// 快速过渡（hover、小元素）
  static const Duration quick = Duration(milliseconds: 160);

  /// 标准过渡（下拉、弹出、状态切换）
  static const Duration standard = Duration(milliseconds: 240);

  /// 慢过渡（模态、抽屉）
  static const Duration slow = Duration(milliseconds: 320);

  /// 按压反馈缩放（按钮 0.97 / 卡片 0.98）
  static const double pressScale = 0.97;
  static const double cardPressScale = 0.98;

  /// 入场初始缩放（从不从 0 开始，保证有形状感）
  static const double enterScale = 0.95;

  /// 交错动画：相邻项间隔
  static const Duration staggerStep = Duration(milliseconds: 50);
}

/// 几何设计令牌
abstract final class AppRadius {
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 18;
  static const double xl = 22;
  static const double hero = 24;
}

/// 布局令牌
abstract final class AppInsets {
  /// 主 Tab 页滚动内容的底部避让高度。
  ///
  /// 主壳的 Scaffold 使用 `extendBody: true`，且导航栏是浮在内容之上的胶囊
  /// （见 `FloatingGlassNavBar`），所以每个可滚动内容都必须自己预留这段高度，
  /// 否则最后一项会被胶囊永久遮住。
  ///
  /// = 胶囊高度 62 + 底部间隙 12 + 呼吸空间。安全区不计入这里，由
  /// [navBarClearanceOf] 另加。二级页面（全屏路由、没有底部栏）不需要。
  static const double navBarClearance = 82.0;

  /// 扩展型 FloatingActionButton 的高度 + 与胶囊之间的间隙。
  ///
  /// 课表页的 FAB 浮在胶囊之上，所以那一页的滚动内容要在胶囊之外**再**让出
  /// 这一段，否则备注行会被 FAB 压住。
  static const double fabClearance = 60.0;

  /// 给滚动容器追加底部避让。
  ///
  /// 用法：`padding: AppInsets.withNavBarClearance(const EdgeInsets.all(16))`
  ///
  /// 注意这个重载不含系统安全区。浮动胶囊会把自己抬到安全区之上，所以在有
  /// BuildContext 的地方优先用 [navBarClearanceOf]，它把安全区一起算进去。
  static EdgeInsets withNavBarClearance(EdgeInsets base) {
    return base.copyWith(bottom: base.bottom + navBarClearance);
  }

  /// 含系统安全区的底部避让（推荐）。
  static double navBarClearanceOf(BuildContext context) {
    return navBarClearance + MediaQuery.viewPaddingOf(context).bottom;
  }

  /// 含系统安全区的 padding 追加。
  static EdgeInsets withNavBarClearanceOf(
    BuildContext context,
    EdgeInsets base,
  ) {
    return base.copyWith(bottom: base.bottom + navBarClearanceOf(context));
  }
}

/// 排版阶梯 —— Apple 式光学尺寸（Typography: tracking & leading）
///
/// - 大标题：**负字距**（越大越紧）+ 紧行高（h1.05 ~ 1.15）
/// - 正文/说明：字距趋 0，行高放宽（1.5 ~ 1.6）
/// - 层次来自「字重 + 字号 + 行高」组合，而非字号单打独斗
abstract final class AppType {
  /// 页面大标题（AppBar）
  static const TextStyle pageTitle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1.15,
    letterSpacing: -0.5,
  );

  /// 卡片主标题
  static const TextStyle sectionTitle = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.3,
  );

  /// 列表行标题（成绩行、服务项等）
  ///
  /// 介于 [body] 与 [sectionTitle] 之间。补这一档是因为页面里大量列表行原本
  /// 手写 `fontSize: 14.5 / 15 / 15.5 + w500/w600`，缺一个可复用的中间层级。
  static const TextStyle rowTitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.3,
    letterSpacing: -0.1,
  );

  /// 数据大数字（余额、GPA）
  static const TextStyle metric = TextStyle(
    fontSize: 36,
    fontWeight: FontWeight.w800,
    height: 1.0,
    letterSpacing: -1.0,
  );

  /// 正文
  static const TextStyle body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
    letterSpacing: 0,
  );

  /// 说明文字（列表副标题、卡片描述）
  ///
  /// 实测页面里 `fontSize: 13` 出现 23 次，是仅次于 12 的高频档，多用于
  /// 「副标题 / 一句话说明」。补这一档避免它们退回内联写法。
  static const TextStyle subtitle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.45,
    letterSpacing: 0,
  );

  /// 次要文字
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.4,
    letterSpacing: 0.2,
  );

  /// 最小号标注（徽章、角标、表格内标签）
  ///
  /// 11px 是可读下限，只用于短标签，不要用于成句文本。
  static const TextStyle label = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    height: 1.25,
    letterSpacing: 0.1,
  );
}

// Flutter 3.44 moved CupertinoPageTransitionsBuilder out of Material.
class _CupertinoPageTransitionsBuilder extends PageTransitionsBuilder {
  const _CupertinoPageTransitionsBuilder();

  @override
  Duration get transitionDuration =>
      cupertino.CupertinoRouteTransitionMixin.kTransitionDuration;

  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      cupertino.CupertinoPageTransition.delegatedTransition;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => cupertino.CupertinoRouteTransitionMixin.buildPageTransitions<T>(
    route,
    context,
    animation,
    secondaryAnimation,
    child,
  );
}

class AppTheme {
  @Deprecated('使用 AppColors.primary')
  static const Color primaryColor = AppColors.primary;
  @Deprecated('使用 AppColors.secondary')
  static const Color secondaryColor = AppColors.secondary;
  @Deprecated('使用 AppColors.accent')
  static const Color accentColor = AppColors.accent;
  @Deprecated('使用 AppColors.tint')
  static const Color subtleSurfaceTint = AppColors.tint;

  static Color get subtleSurfaceBg => AppColors.tintSoft;

  @Deprecated('使用 AppColors.textPrimary')
  static const Color darkPrimaryText = AppColors.textPrimary;
  @Deprecated('使用 AppColors.textSecondary')
  static const Color darkSecondaryText = AppColors.textSecondary;

  @Deprecated('使用 AppColors.primaryGradient')
  static LinearGradient get primaryGradient => AppColors.primaryGradient;

  @Deprecated('使用 AppColors.warmGradient')
  static LinearGradient get warmGradient => AppColors.warmGradient;

  static BoxDecoration glassDecoration({
    double borderRadius = 16,
    Color? borderColor,
    Color? backgroundColor,
  }) {
    return BoxDecoration(
      color: backgroundColor ?? AppColors.tintSoft,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color: borderColor ?? AppColors.outline.withValues(alpha: 0.6),
        width: 1,
      ),
      boxShadow: [
        BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.05),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  /// 品牌卡片装饰 —— 白色底 + 品牌色描边 + 可见的品牌色投影
  ///
  /// 替代原来近乎不可见的灰色边框/黑色微阴影，
  /// 让卡片从页面中"浮"出来。
  static BoxDecoration brandedCardDecoration({
    double borderRadius = AppRadius.lg,
    Color? backgroundColor,
    Color? borderColor,
    double elevation = 1,
  }) {
    return BoxDecoration(
      color: backgroundColor ?? Colors.white,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color: borderColor ?? AppColors.primary.withValues(alpha: 0.14),
        width: 1,
      ),
      boxShadow: [
        BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.06 * elevation),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
        BoxShadow(
          color: AppColors.secondary.withValues(alpha: 0.04 * elevation),
          blurRadius: 24,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  /// 页面 Scaffold 背景 —— 品牌渐变氛围 + 右上角光晕
  static Widget pageBackground({required Widget child}) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppColors.pageGradient),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned(
            top: -80,
            right: -60,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [Color(0x33DDAACC), Color(0x00DDAACC)],
                  ),
                  shape: BoxShape.circle,
                ),
                child: SizedBox(width: 280, height: 280),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }

  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      secondary: AppColors.secondary,
      tertiary: AppColors.accent,
      brightness: Brightness.light,
      surface: AppColors.surface,
      surfaceTint: Colors.transparent,
      onSecondaryContainer: AppColors.textSecondary,
    );

    final baseCardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      side: BorderSide(color: AppColors.outline.withValues(alpha: 0.8)),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.surface,
      splashFactory: InkRipple.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: _CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: _CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: baseCardShape,
        color: AppColors.surfaceCard.withValues(alpha: 0.95),
      ),
      dividerTheme: DividerThemeData(
        color: AppColors.outline.withValues(alpha: 0.6),
        thickness: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        focusColor: AppColors.primary,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
        floatingLabelStyle: const TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.w600,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(
            color: AppColors.outline.withValues(alpha: 0.9),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.danger, width: 1),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 2,
          shadowColor: AppColors.primary.withValues(alpha: 0.2),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          // 文字按钮是白底上的纯文字，用 Ink 版本才够对比度。
          foregroundColor: AppColors.primaryInk,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          // 文字用 Ink，描边保留填充色（描边不承载可读性）。
          foregroundColor: AppColors.primaryInk,
          side: const BorderSide(color: AppColors.primary, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        foregroundColor: AppColors.textPrimary,
        titleTextStyle: AppType.pageTitle,
      ),
      tabBarTheme: TabBarThemeData(
        // 标签是文字，用 Ink；指示器是色块，用填充色。
        labelColor: AppColors.primaryInk,
        unselectedLabelColor: AppColors.textMuted,
        indicatorColor: AppColors.primary,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: AppColors.tint.withValues(alpha: 0.25),
      ),
      navigationRailTheme: NavigationRailThemeData(
        // 导航项是小图标 + 小字，是最需要 Ink 的地方。
        selectedIconTheme: const IconThemeData(color: AppColors.primaryInk),
        selectedLabelTextStyle: const TextStyle(
          color: AppColors.primaryInk,
          fontWeight: FontWeight.bold,
        ),
        unselectedIconTheme: const IconThemeData(color: AppColors.textMuted),
        unselectedLabelTextStyle: const TextStyle(color: AppColors.textMuted),
        backgroundColor: Colors.white,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        selectedItemColor: AppColors.primaryInk,
        unselectedItemColor: AppColors.textMuted,
        backgroundColor: Colors.white,
        elevation: 8,
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: AppColors.primary.withValues(alpha: 0.16),
        // 底部栏由 GlassSurface 提供毛玻璃材质，这里必须透明，
        // 否则不透明白底会盖掉玻璃。
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? AppColors.primaryInk
                : AppColors.textMuted,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? AppColors.primaryInk
                : AppColors.textMuted,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.bold
                : FontWeight.normal,
            fontSize: 12,
          ),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.primary
              : Colors.transparent,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.textMuted,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? AppColors.primary : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.secondary.withValues(alpha: 0.4)
              : null,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.tint.withValues(alpha: 0.12),
        selectedColor: AppColors.secondary.withValues(alpha: 0.2),
        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.2)),
        labelStyle: const TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.textPrimary,
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStateProperty.all(Colors.white),
          surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
          side: WidgetStateProperty.all(
            BorderSide(color: AppColors.outline.withValues(alpha: 0.9)),
          ),
        ),
      ),
    );
  }
}
