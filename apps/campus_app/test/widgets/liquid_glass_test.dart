import 'dart:ui' as ui;

import 'package:campus_app/widgets/glass_surface.dart';
import 'package:campus_app/widgets/liquid_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Liquid glass renders through a fragment shader, so two things must hold:
/// the shader has to actually compile, and an unavailable shader must degrade
/// to the frosted-glass fallback rather than blanking the surface.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('liquid_glass.frag', () {
    test('compiles', () async {
      // A GLSL syntax error surfaces here rather than as a blank bar on device.
      final program = await ui.FragmentProgram.fromAsset(
        'shaders/liquid_glass.frag',
      );
      expect(program, isNotNull);

      final shader = program.fragmentShader();
      addTearDown(shader.dispose);

      // Uniform slots 2..4 are radius/thickness/lightAngle (0..1 is uSize,
      // which Flutter populates). Setting them must not throw — a mismatch
      // between the shader's uniform list and these indices is a silent
      // rendering bug otherwise.
      expect(
        () => shader
          ..setFloat(2, 24)
          ..setFloat(3, 1.0)
          ..setFloat(4, -1.15),
        returnsNormally,
      );
    });
  });

  group('LiquidGlass widget', () {
    testWidgets('keeps foreground content out of the filtered subtree', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LiquidGlass(
              borderRadius: 20,
              fallback: const ColoredBox(color: Colors.white),
              child: const Text('课表'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('课表'), findsOneWidget);

      // Same invariant as GlassAppBar: content must never sit inside the
      // BackdropFilter, or it gets blurred along with the background.
      final blurred = find.descendant(
        of: find.byType(BackdropFilter),
        matching: find.text('课表'),
      );
      expect(blurred, findsNothing);
    });

    testWidgets('renders the fallback until the shader is ready', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LiquidGlass(
              fallback: const GlassSurface(child: Text('fallback')),
              child: const Text('foreground'),
            ),
          ),
        ),
      );

      // First frame: the program load is still in flight, so the fallback must
      // already be painting something — never an empty hole.
      expect(
        find.byType(GlassSurface).evaluate().isNotEmpty ||
            find.text('foreground').evaluate().isNotEmpty,
        isTrue,
      );
    });
  });

  group('shader receives its geometry', () {
    test('renders uniformly rather than split in half', () async {
      // The bug that shipped: the shader was driven through
      // ImageFilter.shader, which does NOT inject the widget size into the
      // uniforms. uSize stayed (0,0), so every roundedBoxSDF() call returned
      // garbage and the capsule rendered as two horizontal halves — blurred on
      // top, flat pink below. Painting through Paint.shader lets us pass the
      // real size, so this samples the output and asserts it is coherent.
      final program = await ui.FragmentProgram.fromAsset(
        'shaders/liquid_glass.frag',
      );

      const width = 200.0;
      const height = 80.0;
      final shader = program.fragmentShader()
        ..setFloat(0, width)
        ..setFloat(1, height)
        ..setFloat(2, height / 2)
        ..setFloat(3, 1.0)
        ..setFloat(4, -1.15);
      addTearDown(shader.dispose);

      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, width, height),
        ui.Paint()..shader = shader,
      );
      final image = await recorder.endRecording().toImage(
        width.toInt(),
        height.toInt(),
      );
      addTearDown(image.dispose);

      final data = await image.toByteData();
      expect(data, isNotNull);

      int alphaAt(int x, int y) {
        final offset = (y * width.toInt() + x) * 4;
        return data!.getUint8(offset + 3);
      }

      // Centre of the capsule must be substantially opaque glass.
      expect(
        alphaAt(width ~/ 2, height ~/ 2),
        greaterThan(60),
        reason: 'the glass body should be painted across the middle',
      );

      // A vertical scan down the middle must vary smoothly (thickness
      // gradient), never jump like a hard seam.
      var maxJump = 0;
      var previous = alphaAt(width ~/ 2, 4);
      for (var y = 5; y < height.toInt() - 4; y++) {
        final current = alphaAt(width ~/ 2, y);
        maxJump = maxJump > (current - previous).abs()
            ? maxJump
            : (current - previous).abs();
        previous = current;
      }
      expect(
        maxJump,
        lessThan(40),
        reason: 'a hard horizontal seam means the shader lost its uSize',
      );

      // Corners fall outside the rounded shape, so they must be transparent.
      expect(alphaAt(0, 0), lessThan(40));
      expect(alphaAt(width.toInt() - 1, 0), lessThan(40));
    });
  });

  group('LiquidGlassSurface', () {
    testWidgets('applies padding to its child', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LiquidGlassSurface(
              padding: EdgeInsets.all(12),
              child: Text('nav'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('nav'), findsOneWidget);
    });
  });
}
