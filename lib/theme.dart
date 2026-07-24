import 'package:flutter/material.dart';

const Map<String, Color> kSeeds = {
  'purple': Color(0xFF6750A4),
  'indigo': Color(0xFF4355B9),
  'blue': Color(0xFF415F91),
  'cyan': Color(0xFF00696E),
  'teal': Color(0xFF196A5A),
  'green': Color(0xFF4C662B),
  'lime': Color(0xFF5C6300),
  'amber': Color(0xFF7C5800),
  'orange': Color(0xFF8B4F24),
  'clay': Color(0xFF8F4C38),
  'red': Color(0xFFA33B3B),
  'pink': Color(0xFF9A4058),
  'magenta': Color(0xFF8B418F),
  'slate': Color(0xFF4F5B62),
};

const Map<String, String> kSeedNames = {
  'purple': '紫',
  'indigo': '靛蓝',
  'blue': '海蓝',
  'cyan': '青',
  'teal': '蓝绿',
  'green': '松绿',
  'lime': '橄榄',
  'amber': '琥珀',
  'orange': '橙',
  'clay': '陶土',
  'red': '绯红',
  'pink': '玫红',
  'magenta': '品红',
  'slate': '石板灰',
};

const String _bodyFont = 'Segoe UI Variable Text';
const String _displayFont = 'Segoe UI Variable Display';
const List<String> _fallback = [
  'Segoe UI',
  'Microsoft YaHei UI',
  'Microsoft YaHei',
  'PingFang SC',
];

ThemeData buildTheme(String seedKey, Brightness brightness) {
  final seed = kSeeds[seedKey] ?? kSeeds['purple']!;
  final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: _bodyFont,
    fontFamilyFallback: _fallback,
  );

  TextStyle? display(TextStyle? s, FontWeight weight) => s?.copyWith(
    fontFamily: _displayFont,
    fontFamilyFallback: _fallback,
    fontWeight: weight,
    letterSpacing: -0.2,
  );
  final t = base.textTheme;
  final tt = t.copyWith(
    displayLarge: display(t.displayLarge, FontWeight.w300),
    displayMedium: display(t.displayMedium, FontWeight.w300),
    displaySmall: display(t.displaySmall, FontWeight.w300),
    headlineLarge: display(t.headlineLarge, FontWeight.w300),
    headlineMedium: display(t.headlineMedium, FontWeight.w300),
    headlineSmall: display(t.headlineSmall, FontWeight.w300),
    titleLarge: display(t.titleLarge, FontWeight.w400),
  );

  final isLight = brightness == Brightness.light;

  final bg = isLight ? scheme.surfaceContainer : scheme.surface;
  final cardColor = isLight ? scheme.surface : scheme.surfaceContainerLow;
  final border = BorderSide(color: scheme.outlineVariant, width: 1);

  return base.copyWith(
    scaffoldBackgroundColor: bg,
    textTheme: tt,
    cardTheme: CardThemeData(
      elevation: 0,
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: border,
      ),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isLight
          ? scheme.surfaceContainerLow
          : scheme.surfaceContainerHighest,
      isDense: true,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: border,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: border,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

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
