/// 应用主题：Material 3 + 可选主题色。
library;

import 'package:flutter/material.dart';

/// 默认品牌绿。
const seedColor = Color(0xFF02743B);

/// 可选主题色：只换种子色，明暗与组件风格保持一致。
enum ThemeAccent {
  green('晨绿', seedColor),
  blue('海蓝', Color(0xFF1565C0)),
  purple('靛紫', Color(0xFF5E35B1)),
  orange('暖橙', Color(0xFFE65100)),
  rose('玫红', Color(0xFFC2185B)),
  teal('青碧', Color(0xFF00695C));

  const ThemeAccent(this.label, this.seed);

  final String label;
  final Color seed;
}

/// 从设置值还原主题色；未知值回落到默认绿。
ThemeAccent themeAccentFrom(String? value) {
  for (final accent in ThemeAccent.values) {
    if (accent.name == value) return accent;
  }
  return ThemeAccent.green;
}

ThemeData buildAppTheme(Brightness brightness, {Color seed = seedColor}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: brightness == Brightness.light
        ? const Color(0xFFF7F7F8)
        : scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: brightness == Brightness.light
          ? const Color(0xFFF7F7F8)
          : scheme.surface,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      isDense: true,
    ),
  );
}
