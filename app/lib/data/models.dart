/// Mirrors backend/app/domain.py. Parsing is lenient: unknown enum values fall back
/// to a safe default so an older app keeps working when the backend adds values.
library;

enum MatchStatus {
  scheduled,
  live,
  halftime,
  extraTime,
  penalties,
  finished,
  suspended,
  postponed,
  abandoned,
  cancelled;

  static MatchStatus parse(String? raw) => switch (raw) {
        'live' => live,
        'halftime' => halftime,
        'extra_time' => extraTime,
        'penalties' => penalties,
        'finished' => finished,
        'suspended' => suspended,
        'postponed' => postponed,
        'abandoned' => abandoned,
        'cancelled' => cancelled,
        _ => scheduled,
      };

  bool get isInPlay => this == live || this == halftime || this == extraTime || this == penalties || this == suspended;
  bool get isTicking => this == live || this == extraTime || this == penalties;
}

enum MatchDuration { regular, extraTime, penalties }

enum EventType {
  goal,
  ownGoal,
  penaltyGoal,
  missedPenalty,
  yellowCard,
  secondYellow,
  redCard,
  substitution,
  varDecision,
  unknown;

  static EventType parse(String? raw) => switch (raw) {
        'goal' => goal,
        'own_goal' => ownGoal,
        'penalty_goal' => penaltyGoal,
        'missed_penalty' => missedPenalty,
        'yellow_card' => yellowCard,
        'second_yellow' => secondYellow,
        'red_card' => redCard,
        'substitution' => substitution,
        'var' => varDecision,
        _ => unknown,
      };

  bool get isGoal => this == goal || this == ownGoal || this == penaltyGoal;
  bool get isRed => this == redCard || this == secondYellow;
}

int? _int(Object? v) => v is num ? v.toInt() : null;

class Competition {
  const Competition({required this.id, required this.name, this.code, this.country, this.emblemUrl});

  final int id;
  final String name;
  final String? code;
  final String? country;
  final String? emblemUrl;

  factory Competition.fromJson(Map<String, dynamic> j) => Competition(
        id: _int(j['id'])!,
        name: j['name'] as String? ?? '?',
        code: j['code'] as String?,
        country: j['country'] as String?,
        emblemUrl: j['emblem_url'] as String?,
      );
}

class Team {
  const Team({required this.id, required this.name, this.shortName, this.tla, this.crestUrl, this.country});

  final int id;
  final String name;
  final String? shortName;
  final String? tla;
  final String? crestUrl;
  final String? country;

  /// Name to show in tight layouts.
  String get displayName => shortName?.isNotEmpty == true ? shortName! : name;

  factory Team.fromJson(Map<String, dynamic> j) => Team(
        id: _int(j['id'])!,
        name: j['name'] as String? ?? '?',
        shortName: j['short_name'] as String?,
        tla: j['tla'] as String?,
        crestUrl: j['crest_url'] as String?,
        country: j['country'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'short_name': shortName,
        'tla': tla,
        'crest_url': crestUrl,
        'country': country,
      };
}

class Score {
  const Score({this.home, this.away, this.htHome, this.htAway, this.penHome, this.penAway, this.duration = MatchDuration.regular});

  final int? home;
  final int? away;
  final int? htHome;
  final int? htAway;
  final int? penHome;
  final int? penAway;
  final MatchDuration duration;

  bool get hasPenalties => penHome != null && penAway != null;

  factory Score.fromJson(Map<String, dynamic> j) => Score(
        home: _int(j['home']),
        away: _int(j['away']),
        htHome: _int(j['ht_home']),
        htAway: _int(j['ht_away']),
        penHome: _int(j['pen_home']),
        penAway: _int(j['pen_away']),
        duration: switch (j['duration']) {
          'extra_time' => MatchDuration.extraTime,
          'penalties' => MatchDuration.penalties,
          _ => MatchDuration.regular,
        },
      );
}

class MatchEvent {
  const MatchEvent({
    required this.type,
    this.minute,
    this.extraMinute,
    this.teamId,
    this.playerId,
    this.playerName,
    this.relatedPlayerId,
    this.relatedPlayerName,
    this.detail,
  });

  final EventType type;
  final int? minute;
  final int? extraMinute;
  final int? teamId;

  /// Scorer, booked player, or player going off for substitutions.
  final int? playerId;
  final String? playerName;

  /// Assist for goals, player coming on for substitutions.
  final int? relatedPlayerId;
  final String? relatedPlayerName;
  final String? detail;

  factory MatchEvent.fromJson(Map<String, dynamic> j) => MatchEvent(
        type: EventType.parse(j['type'] as String?),
        minute: _int(j['minute']),
        extraMinute: _int(j['extra_minute']),
        teamId: _int(j['team_id']),
        playerId: _int(j['player_id']),
        playerName: j['player_name'] as String?,
        relatedPlayerId: _int(j['related_player_id']),
        relatedPlayerName: j['related_player_name'] as String?,
        detail: j['detail'] as String?,
      );
}

class LineupPlayer {
  const LineupPlayer({required this.name, this.id, this.number, this.position, this.grid});

  final int? id;
  final String name;
  final int? number;

  /// G, D, M or F.
  final String? position;

  /// "row:col" when the provider gives pitch positions.
  final String? grid;

  factory LineupPlayer.fromJson(Map<String, dynamic> j) => LineupPlayer(
        id: _int(j['id']),
        name: j['name'] as String? ?? '?',
        number: _int(j['number']),
        position: j['position'] as String?,
        grid: j['grid'] as String?,
      );
}

class Lineup {
  const Lineup({required this.teamId, this.formation, this.coach, this.starting = const [], this.substitutes = const []});

  final int teamId;
  final String? formation;
  final String? coach;
  final List<LineupPlayer> starting;
  final List<LineupPlayer> substitutes;

  factory Lineup.fromJson(Map<String, dynamic> j) => Lineup(
        teamId: _int(j['team_id'])!,
        formation: j['formation'] as String?,
        coach: j['coach'] as String?,
        starting: [for (final p in (j['starting'] as List<dynamic>?) ?? const []) LineupPlayer.fromJson(p as Map<String, dynamic>)],
        substitutes: [
          for (final p in (j['substitutes'] as List<dynamic>?) ?? const []) LineupPlayer.fromJson(p as Map<String, dynamic>),
        ],
      );
}

class TeamStats {
  const TeamStats({
    this.possession,
    this.shots,
    this.shotsOnTarget,
    this.corners,
    this.fouls,
    this.yellowCards,
    this.redCards,
  });

  final int? possession;
  final int? shots;
  final int? shotsOnTarget;
  final int? corners;
  final int? fouls;
  final int? yellowCards;
  final int? redCards;

  factory TeamStats.fromJson(Map<String, dynamic> j) => TeamStats(
        possession: _int(j['possession']),
        shots: _int(j['shots']),
        shotsOnTarget: _int(j['shots_on_target']),
        corners: _int(j['corners']),
        fouls: _int(j['fouls']),
        yellowCards: _int(j['yellow_cards']),
        redCards: _int(j['red_cards']),
      );
}

class MatchStats {
  const MatchStats({this.home = const TeamStats(), this.away = const TeamStats()});

  final TeamStats home;
  final TeamStats away;

  factory MatchStats.fromJson(Map<String, dynamic> j) => MatchStats(
        home: TeamStats.fromJson((j['home'] as Map<String, dynamic>?) ?? const {}),
        away: TeamStats.fromJson((j['away'] as Map<String, dynamic>?) ?? const {}),
      );
}

/// Named FootballMatch to avoid clashing with dart:core's regex `Match`.
class FootballMatch {
  const FootballMatch({
    required this.id,
    required this.competition,
    required this.kickoff,
    required this.status,
    required this.home,
    required this.away,
    required this.score,
    this.minute,
    this.injuryTime,
    this.venue,
    this.events = const [],
    this.lineups = const [],
    this.stats,
    this.hasEventData = false,
  });

  final int id;
  final Competition competition;

  /// Kickoff in UTC; convert with `.toLocal()` for display.
  final DateTime kickoff;
  final MatchStatus status;
  final int? minute;
  final int? injuryTime;
  final Team home;
  final Team away;
  final Score score;
  final String? venue;
  final List<MatchEvent> events;

  /// Only filled by GET /matches/{id}, and only when the data plan includes them.
  final List<Lineup> lineups;
  final MatchStats? stats;

  /// False when [events] can't be trusted (free tiers send scores without scorers).
  final bool hasEventData;

  bool get hasStarted =>
      status != MatchStatus.scheduled && status != MatchStatus.postponed && status != MatchStatus.cancelled;

  Lineup? lineupFor(int teamId) {
    for (final l in lineups) {
      if (l.teamId == teamId) return l;
    }
    return null;
  }

  bool involves(Set<int> teamIds) => teamIds.contains(home.id) || teamIds.contains(away.id);

  /// Red cards per side, for the small card indicator on the home screen.
  int redCards(int teamId) => events.where((e) => e.type.isRed && e.teamId == teamId).length;

  factory FootballMatch.fromJson(Map<String, dynamic> j) => FootballMatch(
        id: _int(j['id'])!,
        competition: Competition.fromJson(j['competition'] as Map<String, dynamic>),
        kickoff: DateTime.parse(j['utc_kickoff'] as String).toUtc(),
        status: MatchStatus.parse(j['status'] as String?),
        minute: _int(j['minute']),
        injuryTime: _int(j['injury_time']),
        home: Team.fromJson(j['home'] as Map<String, dynamic>),
        away: Team.fromJson(j['away'] as Map<String, dynamic>),
        score: Score.fromJson((j['score'] as Map<String, dynamic>?) ?? const {}),
        venue: j['venue'] as String?,
        events: [
          for (final e in (j['events'] as List<dynamic>?) ?? const [])
            MatchEvent.fromJson(e as Map<String, dynamic>),
        ],
        lineups: [
          for (final l in (j['lineups'] as List<dynamic>?) ?? const []) Lineup.fromJson(l as Map<String, dynamic>),
        ],
        stats: j['stats'] == null ? null : MatchStats.fromJson(j['stats'] as Map<String, dynamic>),
        hasEventData: j['has_event_data'] as bool? ?? false,
      );
}

/// One match with lineups/stats plus freshness info, for the match screen.
class MatchDetail {
  const MatchDetail({required this.match, required this.updatedAt, this.offline = false, this.stale = false});

  final FootballMatch match;
  final DateTime updatedAt;
  final bool offline;
  final bool stale;

  MatchDetail copyWith({bool? offline}) =>
      MatchDetail(match: match, updatedAt: updatedAt, offline: offline ?? this.offline, stale: stale);
}

/// A team's row in its league table.
class Standing {
  const Standing({
    required this.position,
    required this.competition,
    required this.played,
    required this.won,
    required this.draw,
    required this.lost,
    required this.goalDifference,
    required this.points,
    this.form,
  });

  final int position;
  final Competition competition;
  final int played;
  final int won;
  final int draw;
  final int lost;
  final int goalDifference;
  final int points;

  /// Last results, newest last, e.g. "W,D,L,W,W" (not every provider sends it).
  final String? form;

  factory Standing.fromJson(Map<String, dynamic> j) => Standing(
        position: _int(j['position']) ?? 0,
        competition: Competition.fromJson(j['competition'] as Map<String, dynamic>),
        played: _int(j['played']) ?? 0,
        won: _int(j['won']) ?? 0,
        draw: _int(j['draw']) ?? 0,
        lost: _int(j['lost']) ?? 0,
        goalDifference: _int(j['goal_difference']) ?? 0,
        points: _int(j['points']) ?? 0,
        form: j['form'] as String?,
      );
}

/// GET /teams/{id}: the team, its last results, next fixtures and league position.
class TeamDetail {
  const TeamDetail({
    required this.team,
    required this.updatedAt,
    this.recent = const [],
    this.upcoming = const [],
    this.standing,
    this.offline = false,
    this.stale = false,
  });

  final Team team;

  /// Oldest first.
  final List<FootballMatch> recent;

  /// Soonest first; includes a match in play.
  final List<FootballMatch> upcoming;
  final Standing? standing;
  final DateTime updatedAt;
  final bool offline;
  final bool stale;

  TeamDetail copyWith({bool? offline}) => TeamDetail(
        team: team,
        updatedAt: updatedAt,
        recent: recent,
        upcoming: upcoming,
        standing: standing,
        offline: offline ?? this.offline,
        stale: stale,
      );

  factory TeamDetail.fromJson(Map<String, dynamic> j, {required DateTime updatedAt, bool stale = false}) {
    List<FootballMatch> matches(Object? raw) =>
        [for (final m in (raw as List<dynamic>?) ?? const []) FootballMatch.fromJson(m as Map<String, dynamic>)];
    return TeamDetail(
      team: Team.fromJson(j['team'] as Map<String, dynamic>),
      recent: matches(j['recent']),
      upcoming: matches(j['upcoming']),
      standing: j['standing'] == null ? null : Standing.fromJson(j['standing'] as Map<String, dynamic>),
      updatedAt: updatedAt,
      stale: stale,
    );
  }
}

/// One competition and its teams, for browsing in the team picker.
class CompetitionTeams {
  const CompetitionTeams({required this.competition, required this.teams});

  final Competition competition;
  final List<Team> teams;

  factory CompetitionTeams.fromJson(Map<String, dynamic> j) => CompetitionTeams(
        competition: Competition.fromJson(j['competition'] as Map<String, dynamic>),
        teams: [for (final t in (j['teams'] as List<dynamic>?) ?? const []) Team.fromJson(t as Map<String, dynamic>)],
      );
}

/// A day's matches plus freshness info for the "last updated" label.
class MatchDay {
  const MatchDay({required this.matches, required this.updatedAt, this.offline = false, this.stale = false});

  final List<FootballMatch> matches;

  /// When the backend last got this data from the provider.
  final DateTime updatedAt;

  /// True when we couldn't reach the backend and are showing the on-device cache.
  final bool offline;

  /// True when the backend itself couldn't reach the provider and served old data.
  final bool stale;

  bool get hasLiveOrImminent => matches.any((m) => m.status.isInPlay);

  MatchDay copyWith({bool? offline}) =>
      MatchDay(matches: matches, updatedAt: updatedAt, offline: offline ?? this.offline, stale: stale);
}
