import 'package:flutter/material.dart';

/// 微信朋友圈风格主题
class AppTheme {
  AppTheme._();

  // 品牌色
  static const Color primaryColor = Color(0xFF07C160); // 微信绿
  static const Color backgroundColor = Color(0xFFF5F5F5);
  static const Color cardColor = Colors.white;
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF999999);
  static const Color dividerColor = Color(0xFFE5E5E5);

  // 朋友圈风格文本样式
  static const TextStyle momentNickname = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: Color(0xFF576B95), // 微信昵称蓝
  );

  static const TextStyle momentContent = TextStyle(
    fontSize: 15,
    color: textPrimary,
    height: 1.5,
  );

  static const TextStyle momentTime = TextStyle(
    fontSize: 12,
    color: textSecondary,
  );

  static const TextStyle dateHeaderStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: textPrimary,
  );

  // 全局主题
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: backgroundColor,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: textPrimary,
        elevation: 0.5,
        centerTitle: false,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }
}
