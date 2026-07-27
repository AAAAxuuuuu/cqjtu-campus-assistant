import 'package:campus_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppTheme ThemeData Color Scheme Verification', () {
    test('AppTheme static constants match primary #BB6688 and secondary #8888CC', () {
      expect(AppTheme.primaryColor, const Color(0xFFBB6688));
      expect(AppTheme.secondaryColor, const Color(0xFF8888CC));
    });

    test('AppTheme.lightTheme colorScheme contains primary #BB6688 and secondary #8888CC', () {
      final theme = AppTheme.lightTheme;
      expect(theme.colorScheme.primary, const Color(0xFFBB6688));
      expect(theme.colorScheme.secondary, const Color(0xFF8888CC));
    });

    test('Button and FAB theme elements use primaryColor #BB6688', () {
      final theme = AppTheme.lightTheme;
      expect(
        theme.filledButtonTheme.style?.backgroundColor?.resolve({}),
        const Color(0xFFBB6688),
      );
      expect(
        theme.elevatedButtonTheme.style?.backgroundColor?.resolve({}),
        const Color(0xFFBB6688),
      );
      expect(
        theme.floatingActionButtonTheme.backgroundColor,
        const Color(0xFFBB6688),
      );
    });
  });
}
