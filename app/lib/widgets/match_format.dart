import 'package:flutter/material.dart';

import '../data/models.dart';
import '../l10n/strings.dart';

/// Kickoff/update time in the device's timezone, honouring its 12/24-hour setting.
String localTime(BuildContext context, DateTime utc) =>
    TimeOfDay.fromDateTime(utc.toLocal()).format(context);

String minuteText(FootballMatch m) {
  if (m.minute == null) return '';
  final extra = m.injuryTime;
  return extra != null && extra > 0 ? "${m.minute}+$extra'" : "${m.minute}'";
}

/// Minute of an event, e.g. "67'" or "45+2'". Empty when the feed has no minute.
String eventMinuteText(MatchEvent e) {
  if (e.minute == null) return '';
  final extra = e.extraMinute;
  return extra != null && extra > 0 ? "${e.minute}+$extra'" : "${e.minute}'";
}

class StatusDisplay {
  const StatusDisplay(this.label, this.semantics, {this.isLive = false});

  /// Short text in the card's status column.
  final String label;

  /// Spoken by screen readers.
  final String semantics;
  final bool isLive;
}

StatusDisplay statusDisplay(BuildContext context, FootballMatch m) {
  final s = S.of(context);
  switch (m.status) {
    case MatchStatus.scheduled:
      final t = localTime(context, m.kickoff);
      return StatusDisplay(t, s.semKickoff(t));
    case MatchStatus.live:
    case MatchStatus.extraTime:
      final min = minuteText(m);
      if (min.isEmpty) {
        final label = m.status == MatchStatus.extraTime ? s.statusExtraTime : s.liveBadge;
        return StatusDisplay(label, label, isLive: true);
      }
      return StatusDisplay(min, s.semMinute(min.replaceAll("'", '')), isLive: true);
    case MatchStatus.penalties:
      return StatusDisplay(s.statusPenaltiesLive, s.statusPenaltiesLive, isLive: true);
    case MatchStatus.halftime:
      return StatusDisplay(s.statusHalfTime, s.semHalfTime, isLive: true);
    case MatchStatus.finished:
      final label = switch (m.score.duration) {
        MatchDuration.penalties => s.statusPens,
        MatchDuration.extraTime => s.statusAet,
        MatchDuration.regular => s.statusFullTime,
      };
      return StatusDisplay(label, s.semFullTime);
    case MatchStatus.suspended:
      return StatusDisplay(s.statusSuspended, s.semSuspended, isLive: true);
    case MatchStatus.postponed:
      return StatusDisplay(s.statusPostponed, s.semPostponed);
    case MatchStatus.abandoned:
      return StatusDisplay(s.statusAbandoned, s.semAbandoned);
    case MatchStatus.cancelled:
      return StatusDisplay(s.statusCancelled, s.semCancelled);
  }
}

/// Full sentence for screen readers, e.g. "Arsenal 2, Chelsea 1, minute 67, Premier League".
String matchSemantics(BuildContext context, FootballMatch m, {bool followed = false}) {
  final s = S.of(context);
  final status = statusDisplay(context, m);
  final hasScore = m.score.home != null && m.score.away != null;
  final parts = [
    hasScore
        ? s.semScore(m.home.name, m.score.home!, m.away.name, m.score.away!)
        : s.semVersus(m.home.name, m.away.name),
    status.semantics,
    if (m.score.hasPenalties) s.semPenalties(m.score.penHome!, m.score.penAway!),
    m.competition.name,
    if (followed) s.semFollowed,
  ];
  return parts.join(', ');
}
