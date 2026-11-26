import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../l10n/strings.dart';
import '../../theme.dart';
import '../../widgets/match_format.dart';
import '../../widgets/team_crest.dart';

/// One match row: status column, then home and away teams stacked with their scores.
/// Uses directional padding so it mirrors correctly in Arabic, and no fixed heights so it
/// grows with large accessibility font sizes.
class MatchCard extends StatelessWidget {
  const MatchCard({
    super.key,
    required this.match,
    required this.favoriteTeamIds,
    required this.onTap,
    required this.onLongPress,
  });

  final FootballMatch match;
  final List<int> favoriteTeamIds;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final status = statusDisplay(context, match);
    final followed = match.involves(favoriteTeamIds.toSet());
    final s = S.of(context);
    final finished = match.status == MatchStatus.finished;
    final homeWins = finished && _winner(match) == 1;
    final awayWins = finished && _winner(match) == -1;

    return Semantics(
      container: true,
      button: true,
      label: matchSemantics(context, match, followed: followed),
      onTapHint: s.semOpenHint,
      excludeSemantics: true,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(8, 10, 12, 10),
            child: Row(
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 56),
                  child: _StatusColumn(status: status),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _TeamLine(
                        team: match.home,
                        goals: match.score.home,
                        penalties: match.score.penHome,
                        redCards: match.redCards(match.home.id),
                        bold: homeWins,
                        dimmed: awayWins,
                        followed: favoriteTeamIds.contains(match.home.id),
                      ),
                      const SizedBox(height: 6),
                      _TeamLine(
                        team: match.away,
                        goals: match.score.away,
                        penalties: match.score.penAway,
                        redCards: match.redCards(match.away.id),
                        bold: awayWins,
                        dimmed: homeWins,
                        followed: favoriteTeamIds.contains(match.away.id),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 1 home, -1 away, 0 draw (penalties decide when level).
  static int _winner(FootballMatch m) {
    final h = m.score.home ?? 0, a = m.score.away ?? 0;
    if (h != a) return h > a ? 1 : -1;
    if (m.score.hasPenalties && m.score.penHome != m.score.penAway) {
      return m.score.penHome! > m.score.penAway! ? 1 : -1;
    }
    return 0;
  }
}

class _StatusColumn extends StatelessWidget {
  const _StatusColumn({required this.status});

  final StatusDisplay status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = status.isLive ? context.scoreColors.live : theme.colorScheme.onSurfaceVariant;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (status.isLive)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
        Text(
          status.label,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelMedium?.copyWith(
            color: color,
            fontWeight: status.isLive ? FontWeight.w700 : FontWeight.w500,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _TeamLine extends StatelessWidget {
  const _TeamLine({
    required this.team,
    required this.goals,
    required this.penalties,
    required this.redCards,
    required this.bold,
    required this.dimmed,
    required this.followed,
  });

  final Team team;
  final int? goals;
  final int? penalties;
  final int redCards;
  final bool bold;
  final bool dimmed;
  final bool followed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodyLarge!;
    final color = dimmed ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.onSurface;
    final style = base.copyWith(color: color, fontWeight: bold ? FontWeight.w700 : FontWeight.w400);

    return Row(
      children: [
        TeamCrest(url: team.crestUrl, fallback: team.tla ?? team.displayName, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Row(
            children: [
              Flexible(child: Text(team.displayName, style: style, overflow: TextOverflow.ellipsis, maxLines: 1)),
              for (var i = 0; i < redCards; i++)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 4),
                  child: Container(
                    width: 8,
                    height: 11,
                    decoration: BoxDecoration(
                      color: context.scoreColors.redCard,
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
                ),
              if (followed)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 4),
                  child: Icon(Icons.star_rounded, size: base.fontSize, color: theme.colorScheme.primary),
                ),
            ],
          ),
        ),
        if (goals != null) ...[
          const SizedBox(width: 8),
          Text(
            '$goals',
            style: style.copyWith(fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ],
        if (penalties != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4),
            child: Text(
              '($penalties)',
              style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}
