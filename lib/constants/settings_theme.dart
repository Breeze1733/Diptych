import 'package:flutter/material.dart';

import 'app_theme.dart';

/// 兼容已有设置组件；所有颜色与样式复用应用主题。
class SettingsTheme {
  SettingsTheme._();

  static const ink = AppTheme.primaryColor;
  static const background = AppTheme.backgroundColor;
  static const surface = AppTheme.surfaceColor;
  static const muted = AppTheme.textSecondary;
  static const border = AppTheme.dividerColor;
  static const accent = AppTheme.accentColor;
  static const accentSurface = AppTheme.accentSurface;
  static const softSurface = AppTheme.softSurface;
  static const danger = AppTheme.dangerColor;

  static ThemeData data(ThemeData base) => AppTheme.applyTo(base);

  static Widget wrap(BuildContext context, Widget child) =>
      Theme(data: data(Theme.of(context)), child: child);
}
