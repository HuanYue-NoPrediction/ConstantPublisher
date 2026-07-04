import 'package:flutter/material.dart';

/// 四组主题种子色,对应原型里的 紫 / 海蓝 / 松绿 / 陶土。
const Map<String, Color> kSeeds = {
  'purple': Color(0xFF6750A4),
  'blue': Color(0xFF415F91),
  'green': Color(0xFF4C662B),
  'clay': Color(0xFF8F4C38),
};

ThemeData buildTheme(String seedKey, Brightness brightness) {
  final seed = kSeeds[seedKey] ?? kSeeds['purple']!;
  final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: EdgeInsets.zero,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

/// 语义色(成功/警告),M3 色板里没有,统一从这里取。
class SemanticColors {
  final Color success;
  final Color onSuccessContainer;
  final Color successContainer;
  final Color warn;
  final Color warnContainer;
  final Color onWarnContainer;

  const SemanticColors._({
    required this.success,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warn,
    required this.warnContainer,
    required this.onWarnContainer,
  });

  factory SemanticColors.of(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return dark
        ? const SemanticColors._(
            success: Color(0xFF9BD47F),
            successContainer: Color(0xFF354E16),
            onSuccessContainer: Color(0xFFCDEDA3),
            warn: Color(0xFFF5BD4F),
            warnContainer: Color(0xFF633F00),
            onWarnContainer: Color(0xFFFFDDB1),
          )
        : const SemanticColors._(
            success: Color(0xFF386A20),
            successContainer: Color(0xFFCDEDA3),
            onSuccessContainer: Color(0xFF0A2100),
            warn: Color(0xFF825500),
            warnContainer: Color(0xFFFFDDB1),
            onWarnContainer: Color(0xFF2A1800),
          );
  }
}
