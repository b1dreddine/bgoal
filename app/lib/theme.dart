import 'package:flutter/material.dart';

/// BGoal green, the brand colour (BRAND.md). Material 3 derives both themes from it.
const brandGreen = Color(0xFF0E8A4A);
const _seed = brandGreen;

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
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
  ScoreColors get scoreColors => Theme.of(this).extension<ScoreColors>()!;
}
