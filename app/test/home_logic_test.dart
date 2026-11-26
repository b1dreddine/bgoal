import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:livescores/data/models.dart';
import 'package:livescores/features/home/home_logic.dart';

/// Real backend output (generated from the backend's mock provider).
List<FootballMatch> loadFixture() {
  final env = jsonDecode(File('test/fixtures/matches_day.json').readAsStringSync()) as Map<String, dynamic>;
  return [for (final m in env['data'] as List<dynamic>) FootballMatch.fromJson(m as Map<String, dynamic>)];
}

void main() {
  final matches = loadFixture();
  FootballMatch byId(int id) => matches.firstWhere((m) => m.id == id);

  test('parses the backend contract', () {
    expect(matches, hasLength(9));
    final live = byId(2026102800);
    expect(live.status, MatchStatus.live);
    expect(live.minute, 36);
    expect(live.home.displayName, 'Chelsea');
    expect(live.kickoff.isUtc, isTrue);
    expect(byId(2026102801).status, MatchStatus.halftime);
    expect(byId(2026102806).score.home, 4);
    expect(byId(2026102807).status, MatchStatus.postponed);
    expect(byId(2026102803).score.home, isNull);
  });

  test('unknown status falls back to scheduled', () {
    expect(MatchStatus.parse('something_new'), MatchStatus.scheduled);
    expect(EventType.parse('something_new'), EventType.unknown);
  });

  test('sections: favorites pinned on top, then competitions by priority', () {
    final sections = buildSections(matches, [57]); // Arsenal
    expect(sections.first.isFavorites, isTrue);
    expect(sections.first.matches.map((m) => m.id), [2026102803]);
    expect(sections.skip(1).map((s) => s.competition!.code), ['PL', 'PD', 'FL1']);
    // pinned match is not repeated in its competition
    final pl = sections[1];
    expect(pl.matches.any((m) => m.id == 2026102803), isFalse);
    // kickoff order inside a group
    final kickoffs = pl.matches.map((m) => m.kickoff).toList();
    expect([...kickoffs]..sort(), kickoffs);
  });

  test('no favorites section when nothing followed', () {
    expect(buildSections(matches, const []).first.isFavorites, isFalse);
    expect(buildSections(const [], const [57]), isEmpty);
  });

  test('live polling only when something is in play or about to start', () {
    final now = DateTime.utc(2026, 10, 28, 18, 0);
    expect(needsLivePolling(MatchDay(matches: matches, updatedAt: now), now), isTrue);

    final finishedOnly = matches.where((m) => m.status == MatchStatus.finished).toList();
    expect(needsLivePolling(MatchDay(matches: finishedOnly, updatedAt: now), now), isFalse);

    final soon = [byId(2026102803)]; // kicks off 18:14
    expect(needsLivePolling(MatchDay(matches: soon, updatedAt: now), now), isTrue);
    final later = [byId(2026102804)]; // 19:30
    expect(needsLivePolling(MatchDay(matches: later, updatedAt: now), now), isFalse);
  });

  test('dayFrom crosses month boundaries', () {
    expect(dayFrom(DateTime(2026, 10, 31, 23, 59), 1), DateTime(2026, 11, 1));
    expect(dayFrom(DateTime(2026, 3, 1, 0, 1), -1), DateTime(2026, 2, 28));
  });
}
