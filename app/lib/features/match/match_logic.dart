/// Pure helpers for the match screen (no Flutter imports, unit-tested).
library;

import '../../data/models.dart';

// ---------------------------------------------------------------------------
// Timeline

enum MarkerKind { kickOff, halfTime, penalties, fullTime }

sealed class TimelineItem {
  const TimelineItem();
}

class EventItem extends TimelineItem {
  const EventItem({required this.event, required this.isHome, this.homeScore, this.awayScore});

  final MatchEvent event;

  /// Side the row is drawn on. Own goals sit on the side that benefits, next to the
  /// score they changed.
  final bool isHome;

  /// Score after this goal. Null for non-goals, or when the events don't add up to the
  /// actual score (incomplete feed), so we never show a wrong running score.
  final int? homeScore;
  final int? awayScore;
}

class MarkerItem extends TimelineItem {
  const MarkerItem(this.kind, {this.home, this.away});

  final MarkerKind kind;
  final int? home;
  final int? away;
}

/// Whether goal [e] counts for the home side (own goals count for the other team).
bool goalForHome(FootballMatch m, MatchEvent e) => (e.teamId == m.home.id) != (e.type == EventType.ownGoal);

/// Chronological timeline: kick-off, events, half-time, ..., shootout, full-time.
/// The screen shows it newest first.
List<TimelineItem> buildTimeline(FootballMatch m) {
  if (!m.hasStarted) return const [];

  // Sort by minute, keeping the feed's order for events in the same minute.
  final indexed = [for (var i = 0; i < m.events.length; i++) (i, m.events[i])]
    ..sort((a, b) {
      final c = _minuteKey(a.$2).compareTo(_minuteKey(b.$2));
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
  final events = m.hasEventData ? [for (final e in indexed) e.$2] : const <MatchEvent>[];

  final goals = events.where((e) => e.type.isGoal).toList();
  final homeGoals = goals.where((e) => goalForHome(m, e)).length;
  final reconciles = homeGoals == (m.score.home ?? 0) && goals.length - homeGoals == (m.score.away ?? 0);

  final reachedHalfTime = m.score.htHome != null ||
      m.status == MatchStatus.halftime ||
      m.status == MatchStatus.finished ||
      (m.status.isInPlay && (m.minute ?? 0) > 45);

  var h = 0, a = 0;
  var halfTimeAdded = false;
  MarkerItem halfTime() => MarkerItem(
        MarkerKind.halfTime,
        home: m.score.htHome ?? (reconciles ? h : null),
        away: m.score.htAway ?? (reconciles ? a : null),
      );

  final items = <TimelineItem>[const MarkerItem(MarkerKind.kickOff)];
  for (final e in events) {
    if (reachedHalfTime && !halfTimeAdded && (e.minute ?? 0) > 45) {
      items.add(halfTime());
      halfTimeAdded = true;
    }
    final isGoal = e.type.isGoal;
    final isHome = isGoal ? goalForHome(m, e) : e.teamId == m.home.id;
    if (isGoal) isHome ? h++ : a++;
    items.add(EventItem(
      event: e,
      isHome: isHome,
      homeScore: isGoal && reconciles ? h : null,
      awayScore: isGoal && reconciles ? a : null,
    ));
  }
  if (reachedHalfTime && !halfTimeAdded) items.add(halfTime());
  if (m.score.hasPenalties) {
    items.add(MarkerItem(MarkerKind.penalties, home: m.score.penHome, away: m.score.penAway));
  }
  if (m.status == MatchStatus.finished) {
    items.add(MarkerItem(MarkerKind.fullTime, home: m.score.home, away: m.score.away));
  }
  return items;
}

int _minuteKey(MatchEvent e) => (e.minute ?? 0) * 100 + (e.extraMinute ?? 0);

/// Goals credited to one side (own goals included), in order, for the header.
List<MatchEvent> scorers(FootballMatch m, {required bool home}) {
  if (!m.hasEventData) return const [];
  return [
    for (final item in buildTimeline(m))
      if (item is EventItem && item.event.type.isGoal && item.isHome == home) item.event,
  ];
}

// ---------------------------------------------------------------------------
// Lineups

/// Starting XI as rows from goalkeeper to attack, for the pitch view.
///
/// Uses the provider's "row:col" grid when every player has one, otherwise the
/// formation string (players are listed GK, defence, midfield, attack). Returns null
/// when neither works, and the screen falls back to a plain list.
List<List<LineupPlayer>>? pitchRows(Lineup l) {
  final xi = l.starting;
  if (xi.length != 11) return null;

  final grids = [for (final p in xi) _parseGrid(p.grid)];
  if (grids.every((g) => g != null)) {
    final rows = <int, List<(int, LineupPlayer)>>{};
    for (var i = 0; i < xi.length; i++) {
      rows.putIfAbsent(grids[i]!.$1, () => []).add((grids[i]!.$2, xi[i]));
    }
    final keys = rows.keys.toList()..sort();
    return [
      for (final k in keys) [for (final cell in rows[k]!..sort((a, b) => a.$1.compareTo(b.$1))) cell.$2],
    ];
  }

  final parts = (l.formation ?? '').split('-').map(int.tryParse).toList();
  if (parts.any((n) => n == null || n <= 0) || parts.fold<int>(0, (sum, n) => sum + n!) != 10) return null;
  final rows = [
    [xi.first],
  ];
  var i = 1;
  for (final n in parts) {
    rows.add(xi.sublist(i, i + n!));
    i += n;
  }
  return rows;
}

(int, int)? _parseGrid(String? grid) {
  final parts = grid?.split(':');
  if (parts == null || parts.length != 2) return null;
  final row = int.tryParse(parts[0]), col = int.tryParse(parts[1]);
  return row == null || col == null ? null : (row, col);
}

/// What happened to one player, for the small icons next to their name.
class PlayerMarks {
  const PlayerMarks({
    this.goals = 0,
    this.ownGoals = 0,
    this.yellowCards = 0,
    this.sentOff = false,
    this.subbedOff,
    this.subbedOn,
  });

  final int goals;
  final int ownGoals;
  final int yellowCards;
  final bool sentOff;

  /// Minute of the substitution.
  final int? subbedOff;
  final int? subbedOn;

  bool get isEmpty =>
      goals == 0 && ownGoals == 0 && yellowCards == 0 && !sentOff && subbedOff == null && subbedOn == null;
}

PlayerMarks playerMarks(List<MatchEvent> events, LineupPlayer p) {
  var goals = 0, ownGoals = 0, yellows = 0;
  var sentOff = false;
  int? off, on;
  for (final e in events) {
    if (_samePlayer(e.playerId, e.playerName, p)) {
      switch (e.type) {
        case EventType.goal || EventType.penaltyGoal:
          goals++;
        case EventType.ownGoal:
          ownGoals++;
        case EventType.yellowCard:
          yellows++;
        case EventType.secondYellow || EventType.redCard:
          sentOff = true;
        case EventType.substitution:
          off = e.minute;
        default:
          break;
      }
    }
    if (e.type == EventType.substitution && _samePlayer(e.relatedPlayerId, e.relatedPlayerName, p)) {
      on = e.minute;
    }
  }
  return PlayerMarks(
    goals: goals,
    ownGoals: ownGoals,
    yellowCards: yellows,
    sentOff: sentOff,
    subbedOff: off,
    subbedOn: on,
  );
}

/// Ids when both sides have them (names can repeat), names otherwise.
bool _samePlayer(int? id, String? name, LineupPlayer p) =>
    id != null && p.id != null ? id == p.id : name != null && name == p.name;

// ---------------------------------------------------------------------------
// Stats

enum StatKind { possession, shots, shotsOnTarget, corners, fouls, yellowCards, redCards }

class StatRow {
  const StatRow(this.kind, this.home, this.away);

  final StatKind kind;
  final int home;
  final int away;

  /// Home share of the bar, 0..1 (0.5 when both are zero).
  double get homeShare => home + away == 0 ? 0.5 : home / (home + away);
}

int? _stat(TeamStats t, StatKind k) => switch (k) {
      StatKind.possession => t.possession,
      StatKind.shots => t.shots,
      StatKind.shotsOnTarget => t.shotsOnTarget,
      StatKind.corners => t.corners,
      StatKind.fouls => t.fouls,
      StatKind.yellowCards => t.yellowCards,
      StatKind.redCards => t.redCards,
    };

/// Rows the provider actually sent (a stat missing for both teams is skipped).
List<StatRow> statRows(MatchStats? stats) {
  if (stats == null) return const [];
  return [
    for (final k in StatKind.values)
      if (_stat(stats.home, k) != null || _stat(stats.away, k) != null)
        StatRow(k, _stat(stats.home, k) ?? 0, _stat(stats.away, k) ?? 0),
  ];
}
