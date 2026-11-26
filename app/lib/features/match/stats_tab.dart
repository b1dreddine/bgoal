import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../l10n/strings.dart';
import '../../widgets/info_message.dart';
import '../../widgets/team_crest.dart';
import 'match_logic.dart';

/// Side-by-side stats with comparison bars. Only stats the provider sent are shown.
class StatsTab extends StatelessWidget {
  const StatsTab({super.key, required this.match});

  final FootballMatch match;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final rows = statRows(match.stats);
    if (rows.isEmpty) {
      return InfoMessage(
        icon: Icons.bar_chart_rounded,
        text: match.status == MatchStatus.scheduled ? s.statsSoon : s.noStats,
      );
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        ExcludeSemantics(
          child: Row(
            children: [
              TeamCrest(url: match.home.crestUrl, fallback: match.home.tla ?? match.home.displayName, size: 24),
              const Spacer(),
              TeamCrest(url: match.away.crestUrl, fallback: match.away.tla ?? match.away.displayName, size: 24),
            ],
          ),
        ),
        for (final row in rows) _StatLine(row: row, match: match),
      ],
    );
  }
}

class _StatLine extends StatelessWidget {
  const _StatLine({required this.row, required this.match});

  final StatRow row;
  final FootballMatch match;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final label = s.statName(row.kind.name);
    String fmt(int v) => row.kind == StatKind.possession ? '$v%' : '$v';
    final valueStyle = theme.textTheme.titleSmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    TextStyle? styleFor(bool leads) => valueStyle?.copyWith(fontWeight: leads ? FontWeight.w800 : FontWeight.w400);
    const radius = BorderRadius.all(Radius.circular(3));

    return Semantics(
      container: true,
      label: s.semStat(label, match.home.name, fmt(row.home), match.away.name, fmt(row.away)),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          children: [
            Row(
              children: [
                Text(fmt(row.home), style: styleFor(row.home > row.away)),
                Expanded(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                Text(fmt(row.away), style: styleFor(row.away > row.home)),
              ],
            ),
            const SizedBox(height: 6),
            // Two bars growing outwards from the middle.
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 6,
                    alignment: AlignmentDirectional.centerEnd,
                    decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: radius),
                    child: FractionallySizedBox(
                      widthFactor: row.homeShare,
                      heightFactor: 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: theme.colorScheme.primary, borderRadius: radius),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Container(
                    height: 6,
                    alignment: AlignmentDirectional.centerStart,
                    decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: radius),
                    child: FractionallySizedBox(
                      widthFactor: 1 - row.homeShare,
                      heightFactor: 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: theme.colorScheme.tertiary, borderRadius: radius),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
