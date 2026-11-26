/// Pure helpers for the home screen (no Flutter imports, unit-tested).
library;

import '../../config.dart';
import '../../data/models.dart';

/// Big competitions first; anything else follows alphabetically.
const competitionPriority = ['CL', 'PL', 'PD', 'SA', 'BL1', 'FL1', 'EC', 'WC', 'DED', 'PPL', 'ELC', 'BSA'];

class MatchSection {
  const MatchSection({required this.matches, this.competition, this.isFavorites = false});

  /// Null for the "Your teams" section.
  final Competition? competition;
  final List<FootballMatch> matches;
  final bool isFavorites;
}

/// Favorites' matches are pinned in their own section at the top (and not repeated
/// below); the rest is grouped by competition, each group sorted by kickoff.
List<MatchSection> buildSections(List<FootballMatch> matches, List<int> favoriteTeamIds) {
  final favs = favoriteTeamIds.toSet();
  int byKickoff(FootballMatch a, FootballMatch b) {
    final c = a.kickoff.compareTo(b.kickoff);
    return c != 0 ? c : a.id.compareTo(b.id);
  }

  final pinned = matches.where((m) => m.involves(favs)).toList()..sort(byKickoff);
  final groups = <int, List<FootballMatch>>{};
  for (final m in matches) {
    if (m.involves(favs)) continue;
    groups.putIfAbsent(m.competition.id, () => []).add(m);
  }

  int rank(Competition c) {
    final i = competitionPriority.indexOf(c.code ?? '');
    return i == -1 ? competitionPriority.length : i;
  }

  final competitions = groups.values.map((g) => g.first.competition).toList()
    ..sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : a.name.compareTo(b.name);
    });

  return [
    if (pinned.isNotEmpty) MatchSection(matches: pinned, isFavorites: true),
    for (final c in competitions) MatchSection(competition: c, matches: groups[c.id]!..sort(byKickoff)),
  ];
}

/// Whether the screen should poll: something is in play, or about to kick off, or
/// should have kicked off but the feed hasn't caught up yet.
bool needsLivePolling(MatchDay day, DateTime now) => day.matches.any((m) => matchNeedsPolling(m, now));

/// Same rule for a single match (used by the match screen too).
bool matchNeedsPolling(FootballMatch m, DateTime now) {
  if (m.status.isInPlay) return true;
  if (m.status != MatchStatus.scheduled) return false;
  final untilKickoff = m.kickoff.difference(now.toUtc());
  return untilKickoff <= AppConfig.preKickoffPollWindow && untilKickoff > const Duration(hours: -3);
}

/// Calendar day (local) [offset] days from [now].
DateTime dayFrom(DateTime now, int offset) => DateTime(now.year, now.month, now.day + offset);
