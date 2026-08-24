import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'glass_surface.dart';

/// 液态玻璃材质 —— 边缘折射 + 镜面拉伸。
///
/// 与 [GlassSurface] 的毛玻璃（半透明白 + 模糊）不同，这里用 fragment shader
/// 把玻璃当作**有厚度的透明体**来渲染：
///
/// - **边缘折射**：贴近边缘的背景被沿法线向内挤压、放大，产生「吸附」观感。
///   折射带宽随厚度变化，中央区域完全不变形——整块都在扭曲会显得廉价。
/// - **镜面拉伸**：沿长边的一道高光，在圆角处按法线收窄。
/// - **色散**：边缘处 R/B 通道错开亚像素距离，一丝彩边。
///
/// shader 源码在 `shaders/liquid_glass.frag`，各现象的推导写在那里。
///
/// ## 为什么需要预先模糊
///
/// shader 采样的是**已经模糊过的**背景纹理。在 shader 内做高斯模糊需要几十次
/// 采样，代价过高；所以模糊仍交给 [BackdropFilter]，shader 只负责几何变形。
///
/// ## 降级
///
/// shader 编译或加载失败时回退到 [fallback]（通常是原来的毛玻璃），
/// 不会白屏。Impeller 之外的老设备也走这条路。
class LiquidGlass extends StatefulWidget {
  const LiquidGlass({
    super.key,
    required this.child,
    required this.fallback,
    this.borderRadius = 0,
    this.thickness = 1.0,
    this.blurSigma = 24,
    this.lightAngle = -1.15,
  });

  /// 玻璃之上的前景内容，永不受滤镜影响。
  final Widget child;

  /// shader 不可用时的替代材质。
  final Widget fallback;

  final double borderRadius;

  /// 玻璃厚度：0 = 薄片，1 = 厚玻璃。控制折射强度与边缘带宽。
  final double thickness;

  final double blurSigma;

  /// 主光源角度（弧度）。默认偏左上，与 app 内卡片阴影方向一致。
  final double lightAngle;

  @override
  State<LiquidGlass> createState() => _LiquidGlassState();
}

class _LiquidGlassState extends State<LiquidGlass> {
  static ui.FragmentProgram? _program;
  static bool _loadFailed = false;
  static Future<void>? _loading;

  @override
  void initState() {
    super.initState();
    _ensureProgram();
  }

  void _ensureProgram() {
    if (_program != null || _loadFailed) return;
    _loading ??= ui.FragmentProgram.fromAsset('shaders/liquid_glass.frag').then(
      (program) {
        // CustomPaint + Paint.shader 在 Skia 与 Impeller 上都可用，
        // 不需要像 ImageFilter.shader 那样探测渲染后端。
        _program = program;
      },
      onError: (Object error, StackTrace stack) {
        // 编译失败/不支持：静默降级，绝不让 UI 白屏。
        debugPrint('[LiquidGlass] shader unavailable, using fallback: $error');
        _loadFailed = true;
      },
    );
    _loading!.whenComplete(() {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final program = _program;

    // [fallback] 只提供**材质**，不负责前景。child 永远由这里渲染，
    // 否则降级路径上很容易把内容整块丢掉。
    final material = program == null
        ? widget.fallback
        : ClipRRect(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            child: BackdropFilter(
              // 模糊先行；shader 只做几何变形与高光。
              filter: ui.ImageFilter.blur(
                sigmaX: widget.blurSigma,
                sigmaY: widget.blurSigma,
                tileMode: TileMode.clamp,
              ),
              child: _LiquidGlassPaint(
                program: program,
                borderRadius: widget.borderRadius,
                thickness: widget.thickness,
                lightAngle: widget.lightAngle,
              ),
            ),
          );

    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(child: IgnorePointer(child: material)),
        widget.child,
      ],
    );
  }
}

/// 把 shader 作为一层绘制在已模糊的背景之上。
///
/// 用 [CustomPaint] 而不是 `ImageFilter.shader`：后者不会把控件尺寸注入
/// uniform，也不把背景绑到 sampler，`uSize` 拿到的是 0 —— SDF 全部算错，
/// 表现是胶囊被横向切成两半（上半模糊、下半纯色）。这里显式传 size。
class _LiquidGlassPaint extends StatelessWidget {
  const _LiquidGlassPaint({
    required this.program,
    required this.borderRadius,
    required this.thickness,
    required this.lightAngle,
  });

  final ui.FragmentProgram program;
  final double borderRadius;
  final double thickness;
  final double lightAngle;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LiquidGlassPainter(
        program: program,
        borderRadius: borderRadius,
        thickness: thickness,
        lightAngle: lightAngle,
      ),
      size: Size.infinite,
    );
  }
}

class _LiquidGlassPainter extends CustomPainter {
  _LiquidGlassPainter({
    required this.program,
    required this.borderRadius,
    required this.thickness,
    required this.lightAngle,
  });

  final ui.FragmentProgram program;
  final double borderRadius;
  final double thickness;
  final double lightAngle;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final shader = program.fragmentShader()
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, borderRadius)
      ..setFloat(3, thickness)
      ..setFloat(4, lightAngle);

    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
    shader.dispose();
  }

  @override
  bool shouldRepaint(_LiquidGlassPainter old) {
    return old.borderRadius != borderRadius ||
        old.thickness != thickness ||
        old.lightAngle != lightAngle ||
        old.program != program;
  }
}

/// 液态玻璃的浮层封装 —— 用法与 GlassSurface 对齐，便于逐处替换。
class LiquidGlassSurface extends StatelessWidget {
  const LiquidGlassSurface({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.borderRadius = 0,
    this.thickness = 1.0,
    this.fallbackColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final double thickness;
  final Color? fallbackColor;

  @override
  Widget build(BuildContext context) {
    return LiquidGlass(
      borderRadius: borderRadius,
      thickness: thickness,
      // 降级材质：原来的毛玻璃（半透明白 + 模糊 + 上下缘）。
      // 注意只传材质、不传内容——内容由 LiquidGlass 统一渲染。
      fallback: GlassSurface(
        backgroundColor: fallbackColor,
        thickness: thickness,
        child: const SizedBox.expand(),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
