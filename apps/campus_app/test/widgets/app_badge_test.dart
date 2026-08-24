import 'package:campus_app/theme/app_theme.dart';
import 'package:campus_app/widgets/app_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// `AppBadge` was dead code while four separate pill implementations lived in
/// the pages: two in `course_cell.dart` (本周无课 / 考试·自定义), and
/// `_SmallTag` / `_StatusTag` in `study_progress_page.dart`, plus a solid
/// 本周 marker in the week navigator. They differed only in border, radius and
/// palette, so the named constructors below exist to absorb all of them.
void main() {
  Future<BoxDecoration> decorationOf(WidgetTester tester, Widget badge) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Center(child: badge)),
      ),
    );
    final container = tester.widget<Container>(find.byType(Container));
    return container.decoration! as BoxDecoration;
  }

  group('AppBadge variants', () {
    testWidgets('default is a bordered rounded rectangle', (tester) async {
      final decoration = await decorationOf(
        tester,
        const AppBadge(label: '考试'),
      );

      expect(decoration.border, isNotNull);
      expect(
        (decoration.borderRadius! as BorderRadius).topLeft.x,
        12.0,
        reason: 'the default badge keeps the 12px radius used in course cells',
      );
    });

    testWidgets('neutral is an unbordered grey pill', (tester) async {
      final decoration = await decorationOf(
        tester,
        const AppBadge.neutral(label: '3 学分'),
      );

      expect(decoration.border, isNull);
      expect(
        (decoration.borderRadius! as BorderRadius).topLeft.x,
        999.0,
        reason: 'neutral tags were fully rounded in study_progress_page',
      );
      expect(find.text('3 学分'), findsOneWidget);
    });

    testWidgets('status uses the semantic colour for text and fill', (
      tester,
    ) async {
      final decoration = await decorationOf(
        tester,
        const AppBadge.status(label: '已修完', color: AppColors.success),
      );

      expect(decoration.border, isNull);
      // Fill is a tint of the semantic colour, not the colour itself.
      expect(decoration.color, isNot(AppColors.success));
      expect(decoration.color!.a, lessThan(0.3));

      final text = tester.widget<Text>(find.text('已修完'));
      expect(text.style!.color, AppColors.success);
    });

    testWidgets('solid fills with the colour and writes in white', (
      tester,
    ) async {
      final decoration = await decorationOf(
        tester,
        const AppBadge.solid(label: '本周'),
      );

      expect(decoration.color, AppColors.primary);
      expect(decoration.border, isNull);

      final text = tester.widget<Text>(find.text('本周'));
      expect(
        text.style!.color,
        Colors.white,
        reason: 'a saturated fill needs white text to stay legible',
      );
    });

    testWidgets('bordered: false drops the outline on the default shape', (
      tester,
    ) async {
      final decoration = await decorationOf(
        tester,
        const AppBadge(label: '自定义', bordered: false),
      );

      expect(decoration.border, isNull);
      expect((decoration.borderRadius! as BorderRadius).topLeft.x, 12.0);
    });

    testWidgets('renders a leading icon when given one', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: AppBadge(label: '提醒', icon: Icons.alarm),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.alarm), findsOneWidget);
      expect(find.text('提醒'), findsOneWidget);
    });
  });
}
