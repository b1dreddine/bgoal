import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// BGoal green, the brand colour (BRAND.md). Material 3 derives both themes from it.
const brandGreen = Color(0xFF0E8A4A);
const _seed = brandGreen;

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
  final light = brightness == Brightness.light;
  // Cards sit on a slightly darker page in light mode (and lighter in dark mode),
  // so lists read as separate, tappable items without heavy shadows.
  final page = light ? scheme.surfaceContainer : scheme.surface;
  final card = light ? scheme.surfaceContainerLowest : scheme.surfaceContainer;
  final selectedOr = WidgetStateColor.resolveWith;

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: page,
    appBarTheme: AppBarTheme(
      backgroundColor: page,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: scheme.onSurface, letterSpacing: -0.2),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: card,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: light ? 0.5 : 0.3)),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      showCheckmark: false,
      side: BorderSide(color: scheme.outlineVariant),
      backgroundColor: card,
      selectedColor: scheme.primary,
      labelStyle: TextStyle(
        fontWeight: FontWeight.w600,
        color: selectedOr((s) => s.contains(WidgetState.selected) ? scheme.onPrimary : scheme.onSurface),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    ),
    tabBarTheme: TabBarThemeData(
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: scheme.outlineVariant.withValues(alpha: 0.4),
      labelStyle: const TextStyle(fontWeight: FontWeight.w700),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.5)),
    // iPhone-style slide and swipe-back on iOS (also in the web version on an
    // iPhone); a soft zoom elsewhere.
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.android: ZoomPageTransitionsBuilder(),
      TargetPlatform.windows: ZoomPageTransitionsBuilder(),
      TargetPlatform.linux: ZoomPageTransitionsBuilder(),
    }),
    extensions: [ScoreColors.of(brightness)],
  );
}

/// Colors with a fixed meaning that shouldn't follow the seed palette.
@immutable
class ScoreColors extends ThemeExtension<ScoreColors> {
  const ScoreColors({required this.live, required this.redCard});

  final Color live;
  final Color redCard;

  static ScoreColors of(Brightness b) => b == Brightness.dark
      ? const ScoreColors(live: Color(0xFFFF6B6B), redCard: Color(0xFFE53935))
      : const ScoreColors(live: Color(0xFFD32F2F), redCard: Color(0xFFC62828));

  @override
  ScoreColors copyWith({Color? live, Color? redCard}) =>
      ScoreColors(live: live ?? this.live, redCard: redCard ?? this.redCard);

  @override
  ScoreColors lerp(ScoreColors? other, double t) => other == null
      ? this
      : ScoreColors(
          live: Color.lerp(live, other.live, t)!,
          redCard: Color.lerp(redCard, other.redCard, t)!,
        );
}

extension ScoreColorsX on BuildContext {
  // Falls back to the defaults under a theme that doesn't carry them (tests, previews).
  ScoreColors get scoreColors =>
      Theme.of(this).extension<ScoreColors>() ?? ScoreColors.of(Theme.of(this).brightness);
}
