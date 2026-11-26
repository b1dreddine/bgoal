/// Pure helpers for the home screen (no Flutter imports, unit-tested).
library;

import '../../config.dart';
import '../../data/models.dart';

/// Shown on the home screen straight away, in this order: the European club cups,
/// then the five big leagues (football-data.org codes).
const topCompetitions = ['CL', 'EL', 'ECL', 'PL', 'PD', 'SA', 'BL1', 'FL1'];

/// The rest sit behind "Other competitions", in this order, then alphabetically.
const otherCompetitionOrder = ['EC', 'WC', 'DED', 'PPL', 'ELC', 'BSA'];

/// Codes for the big leagues when a provider has none (API-Football names them).
const _codeByNameAndCountry = {
  ('Premier League', 'England'): 'PL',
  ('La Liga', 'Spain'): 'PD',
  ('LaLiga', 'Spain'): 'PD',
  ('Primera Division', 'Spain'): 'PD',
  ('Serie A', 'Italy'): 'SA',
  ('Bundesliga', 'Germany'): 'BL1',
  ('Ligue 1', 'France'): 'FL1',
};

/// Position in [topCompetitions], or null for the "other" ones. UEFA's club cups
/// count as top whatever code the provider gives them.
int? topRank(Competition c) {
  final name = c.name.toLowerCase();
  final code = c.code ??
      _codeByNameAndCountry[(c.name, c.country)] ??
      (!name.contains('uefa')
          ? null
          : name.contains('champions league')
              ? 'CL'
              : name.contains('conference league')
                  ? 'ECL'
                  : name.contains('europa league')
                      ? 'EL'
                      : null);
  final i = topCompetitions.indexOf(code ?? '');
  return i >= 0 ? i : null;
}

class MatchSection {
  const MatchSection({required this.matches, this.competition, this.isFavorites = false, this.isTop = true});

  /// Null for the "Your teams" section.
  final Competition? competition;
  final List<FootballMatch> matches;
  final bool isFavorites;

  /// False for competitions shown behind the "Other competitions" button.
  final bool isTop;
}

/// Favorites' matches are pinned in their own section at the top (and not repeated
/// below); the rest is grouped by competition, each group sorted by kickoff. Top
/// competitions come first; the others follow with `isTop: false`.
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
    final top = topRank(c);
    if (top != null) return top;
    final i = otherCompetitionOrder.indexOf(c.code ?? '');
    return topCompetitions.length + (i == -1 ? otherCompetitionOrder.length : i);
  }

  final competitions = groups.values.map((g) => g.first.competition).toList()
    ..sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : a.name.compareTo(b.name);
    });

  return [
    if (pinned.isNotEmpty) MatchSection(matches: pinned, isFavorites: true),
    for (final c in competitions)
      MatchSection(competition: c, matches: groups[c.id]!..sort(byKickoff), isTop: topRank(c) != null),
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
