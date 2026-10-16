import 'package:flutter/material.dart';

/// 纸页双联：暖白纸张、墨蓝文字与克制的陶土色点缀。
class AppTheme {
  AppTheme._();

  static const Color primaryColor = Color(0xFF263C50);
  static const Color backgroundColor = Color(0xFFF7F5F1);
  static const Color surfaceColor = Color(0xFFFFFFFF);
  static const Color textPrimary = primaryColor;
  static const Color textSecondary = Color(0xFF6E7780);
  static const Color dividerColor = Color(0xFFEAE6DF);
  static const Color accentColor = Color(0xFFB77960);
  static const Color accentSurface = Color(0xFFF5EBE5);
  static const Color softSurface = Color(0xFFF2F3F3);
  static const Color dangerColor = Color(0xFFB6534E);
  static const Color selfColor = Color(0xFF526E87);
  static const Color partnerColor = accentColor;

  /// 冷静、平和与明朗三个区间，保留分数本身作为主要心情信息。
  static Color moodColor(int mood) {
    if (mood >= 8) return const Color(0xFFB58550);
    if (mood >= 5) return accentColor;
    return selfColor;
  }

  static const TextStyle momentNickname = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: selfColor,
  );

  static const TextStyle momentContent = TextStyle(
    fontSize: 15,
    color: textPrimary,
    height: 1.65,
  );

  static const TextStyle momentTime = TextStyle(
    fontSize: 12,
    color: textSecondary,
  );

  /// 供旧的局部主题入口复用，颜色和组件由同一套规则定义。
  static ThemeData applyTo(ThemeData base) {
    final fontFamily = base.textTheme.bodyMedium?.fontFamily;
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    return base.copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        primary: primaryColor,
        onPrimary: surfaceColor,
        secondary: accentColor,
        onSecondary: surfaceColor,
        surface: surfaceColor,
        onSurface: textPrimary,
        onSurfaceVariant: textSecondary,
        outline: dividerColor,
        error: dangerColor,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: backgroundColor,
      textTheme: base.textTheme.apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: backgroundColor,
        foregroundColor: textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 20,
          color: textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: surfaceColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: dividerColor),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: surfaceColor,
          disabledBackgroundColor: const Color(0xFFE5E8EB),
          disabledForegroundColor: textSecondary,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: buttonShape,
          textStyle: TextStyle(
            fontFamily: fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: surfaceColor,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: buttonShape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryColor,
          minimumSize: const Size(0, 44),
          side: const BorderSide(color: dividerColor),
          shape: buttonShape,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: primaryColor),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primaryColor,
        foregroundColor: surfaceColor,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surfaceColor.withAlpha(235),
        surfaceTintColor: Colors.transparent,
        indicatorColor: accentSurface,
        elevation: 0,
        height: 52,
        labelPadding: EdgeInsets.zero,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? primaryColor
                : textSecondary,
            size: 23,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontFamily: fontFamily,
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w400,
            color: states.contains(WidgetState.selected)
                ? primaryColor
                : textSecondary,
          ),
        ),
      ),
      badgeTheme: const BadgeThemeData(
        backgroundColor: accentColor,
        textColor: surfaceColor,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: primaryColor,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: softSurface,
        labelStyle: const TextStyle(color: textSecondary, fontSize: 14),
        hintStyle: const TextStyle(color: textSecondary),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primaryColor),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: primaryColor,
        contentTextStyle: TextStyle(color: surfaceColor),
        behavior: SnackBarBehavior.floating,
      ),
      dividerTheme: const DividerThemeData(color: dividerColor, thickness: 1),
    );
  }

  static ThemeData get lightTheme => applyTo(ThemeData(useMaterial3: true));
}
