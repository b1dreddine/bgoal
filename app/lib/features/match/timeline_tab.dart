import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../l10n/strings.dart';
import '../../widgets/info_message.dart';
import '../../widgets/match_format.dart';
import 'event_icons.dart';
import 'match_logic.dart';

/// Events newest first. Home events on the start side, away events on the end side
/// (mirrored in Arabic, matching the header).
class TimelineTab extends StatelessWidget {
  const TimelineTab({super.key, required this.match});

  final FootballMatch match;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    if (!match.hasStarted) return InfoMessage(icon: Icons.schedule_rounded, text: s.notStarted);

    final items = buildTimeline(match).reversed.toList();
    final onlyMarkers = items.every((i) => i is MarkerItem);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: [
        if (!match.hasEventData) _Note(text: s.noEventData),
        if (match.hasEventData && onlyMarkers && match.status.isInPlay) _Note(text: s.noEventsYet),
        for (final item in items)
          switch (item) {
            MarkerItem() => _MarkerRow(item: item, match: match),
            EventItem() => _EventRow(item: item, match: match),
          },
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _MarkerRow extends StatelessWidget {
  const _MarkerRow({required this.item, required this.match});

  final MarkerItem item;
  final FootballMatch match;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final name = switch (item.kind) {
      MarkerKind.kickOff => s.markerKickOff,
      MarkerKind.halfTime => s.markerHalfTime,
      MarkerKind.penalties => s.markerPenalties,
      MarkerKind.fullTime => match.score.duration == MatchDuration.regular ? s.markerFullTime : s.markerAet,
    };
    final hasScore = item.home != null && item.away != null;
    final spoken = hasScore ? '$name, ${s.semScore(match.home.name, item.home!, match.away.name, item.away!)}' : name;

    return Semantics(
      label: spoken,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                hasScore ? '$name  ${item.home}–${item.away}' : name,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const Expanded(child: Divider()),
          ],
        ),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.item, required this.match});

  final EventItem item;
  final FootballMatch match;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final e = item.event;
    final isGoal = e.type.isGoal;
    final isSub = e.type == EventType.substitution;
    final hasRunningScore = item.homeScore != null && item.awayScore != null;

    // Substitutions: player coming on first, player going off below.
    final primary = isSub ? (e.relatedPlayerName ?? '') : (e.playerName ?? s.eventName(e.type.name));
    final tag = switch (e.type) {
      EventType.penaltyGoal => ' (${s.penaltyTag})',
      EventType.ownGoal => ' (${s.ownGoalTag})',
      _ => '',
    };
    final secondary = [
      if (isSub && e.playerName != null) e.playerName!,
      if (hasRunningScore) '${item.homeScore}–${item.awayScore}',
      if (e.type == EventType.goal && e.relatedPlayerName != null) s.assist(e.relatedPlayerName!),
      if (!isGoal && !isSub && e.detail != null) e.detail!,
      if (e.type == EventType.varDecision && e.playerName == null) s.eventName(e.type.name),
    ].join(' · ');

    final team = item.isHome ? match.home : match.away;
    final minute = eventMinuteText(e);
    final spokenDetail = [
      if (isSub)
        s.semSubstitution(e.relatedPlayerName ?? '?', e.playerName ?? '?')
      else if (e.playerName != null)
        e.playerName!,
      if (hasRunningScore) s.semScore(match.home.name, item.homeScore!, match.away.name, item.awayScore!),
      if (e.type == EventType.goal && e.relatedPlayerName != null) s.assist(e.relatedPlayerName!),
    ].join(', ');

    final textAlign = item.isHome ? TextAlign.end : TextAlign.start;
    final details = Column(
      crossAxisAlignment: item.isHome ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          '$primary$tag',
          textAlign: textAlign,
          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: isGoal ? FontWeight.w700 : FontWeight.w500),
        ),
        if (secondary.isNotEmpty)
          Text(
            secondary,
            textAlign: textAlign,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
      ],
    );
    final side = Row(
      mainAxisAlignment: item.isHome ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: item.isHome
          ? [Flexible(child: details), const SizedBox(width: 10), EventIcon(type: e.type)]
          : [EventIcon(type: e.type), const SizedBox(width: 10), Flexible(child: details)],
    );

    return Semantics(
      container: true,
      label: s.semEvent(minute.replaceAll("'", ''), s.eventName(e.type.name), team.name, spokenDetail),
      excludeSemantics: true,
      child: Container(
        color: isGoal ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35) : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(child: item.isHome ? side : const SizedBox.shrink()),
            _MinuteBadge(text: minute),
            Expanded(child: item.isHome ? const SizedBox.shrink() : side),
          ],
        ),
      ),
    );
  }
}

class _MinuteBadge extends StatelessWidget {
  const _MinuteBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 48),
      margin: const EdgeInsets.symmetric(horizontal: 10),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
