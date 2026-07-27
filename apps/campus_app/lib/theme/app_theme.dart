import 'package:flutter/material.dart';

class AppTheme {
  static const Color primaryColor = Color(0xFFBB6688);
  static const Color secondaryColor = Color(0xFF8888CC);
  static const Color darkPrimaryText = Color(0xFF7E3958);
  static const Color darkSecondaryText = Color(0xFF2F2F66);
  static const Color _surfaceColor = Color(0xFFFCFAFC);
  static const Color _outlineColor = Color(0xFFE9DCE3);
  static const Color _mutedColor = Color(0xFF766F7C);

  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primaryColor,
      primary: primaryColor,
      secondary: secondaryColor,
      brightness: Brightness.light,
      surface: Colors.white,
      surfaceTint: Colors.transparent,
      onSecondaryContainer: darkSecondaryText,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: _surfaceColor,
      cardTheme: CardThemeData(
        elevation: 0,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: _outlineColor),
        ),
      ),
      dividerTheme: const DividerThemeData(color: _outlineColor),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        focusColor: primaryColor,
        labelStyle: const TextStyle(color: _mutedColor),
        floatingLabelStyle: const TextStyle(color: primaryColor),
        enabledBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: _outlineColor),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: primaryColor, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: darkPrimaryText),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryColor,
          side: const BorderSide(color: primaryColor),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        foregroundColor: darkPrimaryText,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: primaryColor,
        unselectedLabelColor: _mutedColor,
        indicatorColor: primaryColor,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: primaryColor,
        linearTrackColor: Color(0xFFE8D4DE),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        selectedIconTheme: IconThemeData(color: primaryColor),
        selectedLabelTextStyle: TextStyle(
          color: primaryColor,
          fontWeight: FontWeight.bold,
        ),
        unselectedIconTheme: IconThemeData(color: _mutedColor),
        unselectedLabelTextStyle: TextStyle(color: _mutedColor),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        selectedItemColor: primaryColor,
        unselectedItemColor: _mutedColor,
        backgroundColor: Colors.white,
        elevation: 8,
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: primaryColor.withValues(alpha: 0.14),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? primaryColor
                : _mutedColor,
          ),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? primaryColor
              : Colors.transparent,
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? primaryColor
              : _mutedColor,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? primaryColor : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? secondaryColor.withValues(alpha: 0.45)
              : null,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: primaryColor.withValues(alpha: 0.08),
        selectedColor: secondaryColor.withValues(alpha: 0.18),
        side: BorderSide(color: primaryColor.withValues(alpha: 0.24)),
        labelStyle: const TextStyle(color: darkPrimaryText),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: darkPrimaryText,
        contentTextStyle: TextStyle(color: Colors.white),
      ),
    );
  }
}
