import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../l10n/strings.dart';
import '../../theme.dart';
import 'match_logic.dart';

const _yellow = Color(0xFFFFC107);
const _subOnColor = Color(0xFF2E7D32);

/// Small card shape; [second] draws a yellow behind a red for a second booking.
class CardIcon extends StatelessWidget {
  const CardIcon({super.key, required this.color, this.size = 14, this.second = false});

  final Color color;
  final double size;
  final bool second;

  @override
  Widget build(BuildContext context) {
    Widget card(Color c) => Container(
          width: size * 0.7,
          height: size,
          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(size * 0.12)),
        );
    if (!second) return card(color);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          PositionedDirectional(start: 0, top: 0, child: card(_yellow)),
          PositionedDirectional(end: 0, bottom: 0, child: Transform.scale(scale: 0.9, child: card(color))),
        ],
      ),
    );
  }
}

/// Icon for a timeline event. Decorative: rows carry their own spoken label.
class EventIcon extends StatelessWidget {
  const EventIcon({super.key, required this.type, this.size = 20});

  final EventType type;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final red = context.scoreColors.redCard;
    return switch (type) {
      EventType.goal || EventType.penaltyGoal => Icon(Icons.sports_soccer, size: size),
      EventType.ownGoal => Icon(Icons.sports_soccer, size: size, color: red),
      EventType.missedPenalty => Icon(Icons.block_rounded, size: size, color: red),
      EventType.yellowCard => CardIcon(color: _yellow, size: size * 0.8),
      EventType.secondYellow => CardIcon(color: red, size: size * 0.8, second: true),
      EventType.redCard => CardIcon(color: red, size: size * 0.8),
      EventType.substitution => Icon(Icons.swap_horiz_rounded, size: size, color: scheme.primary),
      EventType.varDecision => Icon(Icons.tv_rounded, size: size),
      EventType.unknown => Icon(Icons.circle_outlined, size: size * 0.6),
    };
  }
}

/// Goals, cards and substitution minute next to a player's name, with a spoken summary.
class PlayerMarksRow extends StatelessWidget {
  const PlayerMarksRow({super.key, required this.marks, this.color});

  final PlayerMarks marks;

  /// Text/icon color override (white on the pitch).
  final Color? color;

  static String spoken(S s, PlayerMarks m) => [
        for (var i = 0; i < m.goals; i++) s.eventName(EventType.goal.name),
        for (var i = 0; i < m.ownGoals; i++) s.eventName(EventType.ownGoal.name),
        for (var i = 0; i < m.yellowCards; i++) s.eventName(EventType.yellowCard.name),
        if (m.sentOff) s.eventName(EventType.redCard.name),
        if (m.subbedOn != null) '${s.semSubbedOn} ${m.subbedOn}',
        if (m.subbedOff != null) '${s.semSubbedOff} ${m.subbedOff}',
      ].join(', ');

  @override
  Widget build(BuildContext context) {
    if (marks.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final red = context.scoreColors.redCard;
    final textStyle = theme.textTheme.labelSmall?.copyWith(
      color: color ?? theme.colorScheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    const gap = SizedBox(width: 3);
    return ExcludeSemantics(
      child: Wrap(
        spacing: 3,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (var i = 0; i < marks.goals; i++) Icon(Icons.sports_soccer, size: 14, color: color),
          for (var i = 0; i < marks.ownGoals; i++) Icon(Icons.sports_soccer, size: 14, color: red),
          if (marks.sentOff)
            CardIcon(color: red, size: 12, second: marks.yellowCards > 0)
          else
            for (var i = 0; i < marks.yellowCards; i++) const CardIcon(color: _yellow, size: 12),
          if (marks.subbedOn != null)
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.arrow_upward_rounded, size: 14, color: _subOnColor),
              gap,
              Text("${marks.subbedOn}'", style: textStyle),
            ]),
          if (marks.subbedOff != null)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.arrow_downward_rounded, size: 14, color: red),
              gap,
              Text("${marks.subbedOff}'", style: textStyle),
            ]),
        ],
      ),
    );
  }
}
