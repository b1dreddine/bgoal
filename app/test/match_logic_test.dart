import 'package:flutter_test/flutter_test.dart';
import 'package:livescores/data/models.dart';
import 'package:livescores/features/match/match_logic.dart';

import 'helpers.dart';

void main() {
  final details = readFixture('match_details.json') as Map<String, dynamic>;
  FootballMatch detail(int id) => FootballMatch.fromJson(details['$id']['data'] as Map<String, dynamic>);

  final finished = detail(2026102806); // Atleti 4-0 Barça, HT 3-0
  final live = detail(2026102800); // Chelsea 0-0 Newcastle, minute 36
  final scheduled = detail(2026102803);

  /// Same teams as [finished], custom events and score.
  FootballMatch synthetic({required Score score, required List<MatchEvent> events, bool hasEventData = true}) =>
      FootballMatch(
        id: 1,
        competition: finished.competition,
        kickoff: finished.kickoff,
        status: MatchStatus.finished,
        home: finished.home,
        away: finished.away,
        score: score,
        events: events,
        hasEventData: hasEventData,
      );

  String markerKinds(List<TimelineItem> items) =>
      [for (final i in items) if (i is MarkerItem) i.kind.name].join(',');

  test('parses lineups and stats from the backend contract', () {
    expect(finished.lineups, hasLength(2));
    final home = finished.lineupFor(78)!;
    expect(home.formation, '4-3-3');
    expect(home.starting, hasLength(11));
    expect(home.substitutes, hasLength(7));
    expect(home.starting.first.position, 'G');
    expect(finished.stats!.home.possession, 55);
    expect(finished.stats!.home.fouls, isNull);
    expect(finished.events.first.playerId, 7809);
    expect(scheduled.lineups, hasLength(2));
    expect(scheduled.stats, isNull);
  });

  test('finished match timeline: markers in place and running score', () {
    final items = buildTimeline(finished);
    expect(markerKinds(items), 'kickOff,halfTime,fullTime');
    expect(items, hasLength(1 + finished.events.length + 2));

    final goals = [
      for (final i in items)
        if (i is EventItem && i.event.type.isGoal) '${i.event.minute}:${i.homeScore}-${i.awayScore}',
    ];
    expect(goals, ['12:1-0', '33:2-0', '36:3-0', '87:4-0']);

    final ht = items.indexWhere((i) => i is MarkerItem && i.kind == MarkerKind.halfTime);
    expect((items[ht] as MarkerItem).home, 3);
    expect((items[ht - 1] as EventItem).event.minute, 36);
    expect((items[ht + 1] as EventItem).event.minute, 52);

    final ft = items.last as MarkerItem;
    expect([ft.kind, ft.home, ft.away], [MarkerKind.fullTime, 4, 0]);
  });

  test('live match before half-time has no HT or FT marker', () {
    final items = buildTimeline(live);
    expect(markerKinds(items), 'kickOff');
    expect(items.whereType<EventItem>(), hasLength(3));
  });

  test('not started: empty timeline', () {
    expect(buildTimeline(scheduled), isEmpty);
  });

  test('own goal is shown for, and counted to, the other side', () {
    final m = synthetic(score: const Score(home: 1, away: 1), events: const [
      MatchEvent(type: EventType.ownGoal, minute: 50, teamId: 78),
      MatchEvent(type: EventType.goal, minute: 10, teamId: 78),
    ]);
    final goals = buildTimeline(m).whereType<EventItem>().toList();
    expect(goals.map((g) => g.event.minute), [10, 50]); // sorted by minute
    expect(goals.map((g) => g.isHome), [true, false]);
    expect(goals.map((g) => '${g.homeScore}-${g.awayScore}'), ['1-0', '1-1']);
    final ht = buildTimeline(m).whereType<MarkerItem>().firstWhere((i) => i.kind == MarkerKind.halfTime);
    expect([ht.home, ht.away], [1, 0]); // no ht score from the feed: derived from events
    expect(scorers(m, home: false).single.type, EventType.ownGoal);
  });

  test('incomplete event feed: no running score rather than a wrong one', () {
    final m = synthetic(score: const Score(home: 2, away: 1), events: const [
      MatchEvent(type: EventType.goal, minute: 10, teamId: 78),
    ]);
    final goal = buildTimeline(m).whereType<EventItem>().single;
    expect(goal.homeScore, isNull);
  });

  test('extra time and penalties', () {
    final m = synthetic(
      score: const Score(home: 1, away: 1, htHome: 0, htAway: 0, penHome: 4, penAway: 3, duration: MatchDuration.penalties),
      events: const [
        MatchEvent(type: EventType.goal, minute: 70, teamId: 78),
        MatchEvent(type: EventType.goal, minute: 105, extraMinute: 1, teamId: 81),
      ],
    );
    final items = buildTimeline(m);
    expect(markerKinds(items), 'kickOff,halfTime,penalties,fullTime');
    final pens = items.whereType<MarkerItem>().firstWhere((i) => i.kind == MarkerKind.penalties);
    expect([pens.home, pens.away], [4, 3]);
  });

  test('without event data the timeline only has markers', () {
    final m = synthetic(score: const Score(home: 1, away: 0, htHome: 1, htAway: 0), events: const [], hasEventData: false);
    expect(buildTimeline(m).every((i) => i is MarkerItem), isTrue);
    expect(scorers(m, home: true), isEmpty);
  });

  test('scorers per side for the header', () {
    expect(scorers(finished, home: true).map((e) => e.minute), [12, 33, 36, 87]);
    expect(scorers(finished, home: false), isEmpty);
  });

  test('pitch rows from the formation, from the grid, or none', () {
    final lineup = finished.lineupFor(78)!;
    expect(pitchRows(lineup)!.map((r) => r.length), [1, 4, 3, 3]);

    Lineup withFormation(String? f) => Lineup(teamId: 78, formation: f, starting: lineup.starting);
    expect(pitchRows(withFormation('4-2-3-1'))!.map((r) => r.length), [1, 4, 2, 3, 1]);
    expect(pitchRows(withFormation('4-4-3')), isNull); // 11 outfield players
    expect(pitchRows(withFormation(null)), isNull);

    final grid = ['1:1', '2:4', '2:3', '2:2', '2:1', '3:3', '3:2', '3:1', '4:3', '4:2', '4:1'];
    final gridded = Lineup(teamId: 78, starting: [
      for (var i = 0; i < 11; i++) LineupPlayer(name: 'P$i', number: i + 1, grid: grid[i]),
    ]);
    final rows = pitchRows(gridded)!;
    expect(rows.map((r) => r.length), [1, 4, 3, 3]);
    expect(rows[1].map((p) => p.grid), ['2:1', '2:2', '2:3', '2:4']); // sorted by column
  });

  test('player marks: goals, cards, substitutions', () {
    final xi = finished.lineupFor(78)!.starting;
    LineupPlayer named(String n) => xi.firstWhere((p) => p.name == n);

    final ziyech = playerMarks(finished.events, named('Y. Ziyech'));
    expect(ziyech.goals, 2);
    expect(ziyech.subbedOff, 62);

    final diaz = playerMarks(finished.events, named('N. Diaz'));
    expect([diaz.yellowCards, diaz.goals, diaz.sentOff], [1, 0, false]);

    final keeper = playerMarks(finished.events, xi.first);
    expect(keeper.isEmpty, isTrue);

    final costa = finished.lineupFor(78)!.substitutes.firstWhere((p) => p.name == 'D. Costa');
    expect(playerMarks(finished.events, costa).subbedOn, 60);
  });

  test('stat rows skip stats missing for both teams', () {
    final rows = statRows(finished.stats);
    expect(rows.map((r) => r.kind), [StatKind.possession, StatKind.shots, StatKind.shotsOnTarget, StatKind.corners]);
    expect(rows.first.homeShare, closeTo(0.55, 1e-9));
    expect(statRows(null), isEmpty);
    expect(const StatRow(StatKind.corners, 0, 0).homeShare, 0.5);
  });
}
