import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:livescores/data/models.dart';
import 'package:livescores/features/match/match_screen.dart';

import 'helpers.dart';

const finishedId = 2026102806; // Atleti 4-0 Barça
const liveId = 2026102800; // Chelsea 0-0 Newcastle, 36'
const scheduledId = 2026102803; // Man United v Arsenal, kicks off 18:14 UTC

void main() {
  testWidgets('finished match: header, timeline, lineups and stats', (tester) async {
    final semantics = tester.ensureSemantics();
    final requested = <String>[];
    final client = MockClient((req) async {
      requested.add(req.url.path);
      return jsonResponse(matchBody(finishedId));
    });
    await pumpApp(tester, const MatchScreen(matchId: finishedId), client: client);

    expect(requested, ['/matches/$finishedId']);
    // Header
    expect(find.text('Atleti'), findsOneWidget);
    expect(find.text('Barça'), findsOneWidget);
    expect(find.text('FT'), findsOneWidget);
    expect(find.text('HT 3–0'), findsOneWidget);
    expect(find.text("Y. Ziyech 12'"), findsOneWidget);
    expect(find.text("Y. Ziyech 87' (P)"), findsOneWidget);

    // Timeline, newest first
    expect(find.text('Full-time  4–0'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(
        r'^minute 87, Penalty goal, Club Atlético de Madrid, Y\. Ziyech, Club Atlético de Madrid 4, FC Barcelona 0$',
      )),
      findsOneWidget,
    );

    // Lineups: home team on the pitch
    await tester.tap(find.text('Lineups'));
    await tester.pumpAndSettle();
    expect(find.text('4-3-3'), findsOneWidget);
    expect(find.text('Ziyech'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^number 10, Y\. Ziyech, Goal, Goal, substituted 62$')), findsOneWidget);

    // Away team
    await tester.tap(find.text('Barça').last);
    await tester.pumpAndSettle();
    expect(find.text('Coach: Coach FCB'), findsOneWidget);

    // Stats
    await tester.tap(find.text('Stats'));
    await tester.pumpAndSettle();
    expect(find.text('Possession'), findsOneWidget);
    expect(find.text('55%'), findsOneWidget);
    expect(find.text('Fouls'), findsNothing); // not sent by the provider
    expect(
      find.bySemanticsLabel('Shots: Club Atlético de Madrid 8, FC Barcelona 7'),
      findsOneWidget,
    );

    semantics.dispose();
    await unmount(tester);
  });

  testWidgets('header from the home list shows while details load', (tester) async {
    final day = readFixture('matches_day.json') as Map<String, dynamic>;
    final json = (day['data'] as List<dynamic>).cast<Map<String, dynamic>>().firstWhere((m) => m['id'] == liveId);
    json['home']['crest_url'] = null;
    json['away']['crest_url'] = null;
    final preview = FootballMatch.fromJson(json);

    final response = Completer<http.Response>();
    final client = MockClient((req) => response.future);
    await pumpApp(tester, MatchScreen(matchId: liveId, preview: preview), client: client, settle: false);
    await tester.pump();

    expect(find.text('Chelsea'), findsOneWidget);
    expect(find.text("36'"), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    response.complete(jsonResponse(matchBody(liveId)));
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Kick-off'), findsOneWidget);
    expect(find.text('A. Walker'), findsOneWidget); // 6' yellow card
    await unmount(tester);
  });

  testWidgets('offline: keeps the match and says when it was last updated', (tester) async {
    var online = true;
    final client = MockClient((req) async {
      if (!online) throw const SocketException('no network');
      return jsonResponse(matchBody(liveId));
    });
    await pumpApp(tester, const MatchScreen(matchId: liveId), client: client);
    expect(find.textContaining('Updated'), findsOneWidget);

    online = false;
    await tester.fling(find.byType(ListView).first, const Offset(0, 400), 1000); // pull to refresh
    await tester.pumpAndSettle();

    expect(find.text('Chelsea'), findsOneWidget);
    expect(find.textContaining('Offline · last updated'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('deep link with no network shows retry, unknown match says not found', (tester) async {
    await pumpApp(
      tester,
      const MatchScreen(matchId: liveId),
      client: MockClient((req) async => throw const SocketException('no network')),
    );
    expect(find.text('Retry'), findsOneWidget);
    await unmount(tester);

    await pumpApp(
      tester,
      const MatchScreen(matchId: 42),
      client: MockClient((req) async => jsonResponse(jsonEncode({'detail': 'Match not found'}), 404)),
    );
    expect(find.text("This match couldn't be found."), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    await unmount(tester);
  });

  testWidgets('scheduled match: kickoff time, lineups announced, no stats yet', (tester) async {
    await pumpApp(
      tester,
      const MatchScreen(matchId: scheduledId),
      client: MockClient((req) async => jsonResponse(matchBody(scheduledId))),
    );
    expect(find.text("The match hasn't started."), findsOneWidget);

    await tester.tap(find.text('Lineups'));
    await tester.pumpAndSettle();
    expect(find.text('4-3-3'), findsOneWidget);

    await tester.tap(find.text('Stats'));
    await tester.pumpAndSettle();
    expect(find.text('Stats appear once the match starts.'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('Arabic: right-to-left with translated tabs', (tester) async {
    await pumpApp(
      tester,
      const MatchScreen(matchId: finishedId),
      client: MockClient((req) async => jsonResponse(matchBody(finishedId))),
      locale: const Locale('ar'),
    );
    expect(find.text('الأحداث'), findsOneWidget);
    expect(find.text('نهاية المباراة  4–0'), findsOneWidget);
    expect(Directionality.of(tester.element(find.byType(MatchScreen))), TextDirection.rtl);
    await unmount(tester);
  });
}
