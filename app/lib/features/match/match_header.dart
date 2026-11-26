import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/models.dart';
import '../../l10n/strings.dart';
import '../../theme.dart';
import '../../widgets/match_format.dart';
import '../../widgets/team_crest.dart';
import 'match_logic.dart';

/// Crests, score, status and goal scorers. Read by screen readers as one summary.
class MatchHeader extends StatelessWidget {
  const MatchHeader({super.key, required this.match, this.onTeamTap});

  final FootballMatch match;

  /// Tapping a crest or name. Screen readers reach team pages through the follow sheet,
  /// since the header is read as one summary.
  final ValueChanged<Team>? onTeamTap;

  Widget _tappable(Team team, Widget child) => onTeamTap == null
      ? child
      : InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => onTeamTap!(team),
          child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: child),
        );

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toString();
    final kickoff = match.kickoff.toLocal();
    final when = '${DateFormat.MMMMEEEEd(locale).format(kickoff)} · ${localTime(context, match.kickoff)}';
    final homeGoals = scorers(match, home: true);
    final awayGoals = scorers(match, home: false);

    String spokenGoals(Team team, List<MatchEvent> goals) =>
        '${team.name}: ${goals.map((g) => _scorerText(s, g)).join(', ')}';

    final label = [
      matchSemantics(context, match),
      if (homeGoals.isNotEmpty) spokenGoals(match.home, homeGoals),
      if (awayGoals.isNotEmpty) spokenGoals(match.away, awayGoals),
      when,
      if (match.venue != null) match.venue!,
    ].join('. ');

    return Semantics(
      container: true,
      label: label,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _tappable(match.home, _TeamColumn(team: match.home, goals: homeGoals))),
                _ScoreColumn(match: match),
                Expanded(child: _tappable(match.away, _TeamColumn(team: match.away, goals: awayGoals))),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              [when, if (match.venue != null) match.venue!].join(' · '),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

String _scorerText(S s, MatchEvent g) {
  final tag = switch (g.type) {
    EventType.penaltyGoal => ' (${s.penaltyTag})',
    EventType.ownGoal => ' (${s.ownGoalTag})',
    _ => '',
  };
  return [if (g.playerName != null) g.playerName!, eventMinuteText(g)].join(' ') + tag;
}

class _TeamColumn extends StatelessWidget {
  const _TeamColumn({required this.team, required this.goals});

  final Team team;
  final List<MatchEvent> goals;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = S.of(context);
    return Column(
      children: [
        TeamCrest(url: team.crestUrl, fallback: team.tla ?? team.displayName, size: 48),
        const SizedBox(height: 8),
        Text(
          team.displayName,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        for (final g in goals)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              _scorerText(s, g),
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

class _ScoreColumn extends StatelessWidget {
  const _ScoreColumn({required this.match});

  final FootballMatch match;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final status = statusDisplay(context, match);
    final score = match.score;
    final hasScore = score.home != null && score.away != null;
    final statusColor = status.isLive ? context.scoreColors.live : theme.colorScheme.onSurfaceVariant;
    final big = theme.textTheme.displaySmall?.copyWith(
      fontWeight: FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final showHalfTime = score.htHome != null && score.htAway != null && match.status != MatchStatus.halftime;

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 112),
      child: Column(
        children: [
          const SizedBox(height: 6),
          if (hasScore)
            // A Row, not one string, so the home score sits on the home side in RTL too.
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${score.home}', style: big),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text('–', style: big)),
                Text('${score.away}', style: big),
              ],
            )
          else
            Text(localTime(context, match.kickoff), style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          if (match.status != MatchStatus.scheduled)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (status.isLive)
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsetsDirectional.only(end: 6),
                    decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                  ),
                Text(
                  status.label,
                  style: theme.textTheme.labelLarge?.copyWith(color: statusColor, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          if (showHalfTime)
            Text(s.htScore(score.htHome!, score.htAway!), style: theme.textTheme.labelSmall),
          if (score.hasPenalties)
            Text(
              s.pensScore(score.penHome!, score.penAway!),
              style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
        ],
      ),
    );
  }
}
