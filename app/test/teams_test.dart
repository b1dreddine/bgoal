import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:livescores/config.dart';
import 'package:livescores/features/team/team_screen.dart';
import 'package:livescores/features/teams/team_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

/// Fake backend for the team endpoints; records every request.
class TeamsBackend {
  final requests = <Uri>[];

  late final client = MockClient((req) async {
    requests.add(req.url);
    return switch (req.url.path) {
      '/teams/57' => jsonResponse(fixtureBody('team_57.json', (j) => j['data']['standing']['form'] = 'W,W,D,L,W')),
      '/teams/browse' => jsonResponse(fixtureBody('teams_browse.json')),
      '/teams/search' when req.url.queryParameters['q'] == 'real' => jsonResponse(fixtureBody('teams_search_real.json')),
      '/teams/search' => jsonResponse('{"data": []}'),
      _ => http.Response('{"detail": "Team not found"}', 404),
    };
  });

  int count(String path) => requests.where((u) => u.path == path).length;
}

void main() {
  group('team screen', () {
    testWidgets('shows position, next matches and results, and follows the team', (tester) async {
      final backend = TeamsBackend();
      await pumpApp(tester, const TeamScreen(teamId: 57), client: backend.client);

      expect(find.text('Arsenal FC'), findsWidgets); // app bar + header
      expect(find.text('Position 1 · Premier League'), findsOneWidget);
      expect(find.text('Pts'), findsOneWidget);
      expect(find.text('Next matches'), findsOneWidget);
      expect(find.textContaining('· Premier League'), findsWidgets); // date and competition above each card
      // Form W,W,D,L,W
      expect(find.text('W'), findsNWidgets(4)); // 3 wins + the "W" column header
      expect(find.text('L'), findsNWidgets(2));

      await tester.scrollUntilVisible(find.text('Recent results'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('Recent results'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Follow'), -300, scrollable: find.byType(Scrollable).first);

      await tester.tap(find.text('Follow'));
      await tester.pumpAndSettle();
      expect(find.text('Following'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('favorite_team_ids'), ['57']);
      await unmount(tester);
    });

    testWidgets('keeps refreshing while a match is about to start', (tester) async {
      final backend = TeamsBackend();
      // The fixture's first upcoming match kicks off at 18:14; the test clock says 18:00.
      await pumpApp(tester, const TeamScreen(teamId: 57), client: backend.client);
      expect(backend.count('/teams/57'), 1);
      await tester.pump(AppConfig.liveRefreshInterval);
      await tester.pumpAndSettle();
      expect(backend.count('/teams/57'), 2);
      await unmount(tester);
    });

    testWidgets('unknown team', (tester) async {
      await pumpApp(tester, const TeamScreen(teamId: 999), client: TeamsBackend().client);
      expect(find.text("This team couldn't be found."), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      await unmount(tester);
    });

    testWidgets('reads the table as a sentence', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpApp(tester, const TeamScreen(teamId: 57), client: TeamsBackend().client);
      expect(find.bySemanticsLabel(RegExp(r'^Position 1 in Premier League, 22 points')), findsOneWidget);
      semantics.dispose();
      await unmount(tester);
    });
  });

  group('team picker', () {
    testWidgets('lists teams by league; tapping a row follows it (onboarding mode)', (tester) async {
      final backend = TeamsBackend();
      await pumpApp(tester, const Scaffold(body: TeamPicker(showFollowed: false)), client: backend.client);

      expect(find.text('Ligue 1'), findsOneWidget);
      await tester.ensureVisible(find.text('Arsenal FC'));
      await tester.tap(find.text('Arsenal FC'));
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('favorite_team_ids'), ['57']);
      expect(find.byIcon(Icons.star_rounded), findsOneWidget);

      await tester.tap(find.text('Arsenal FC'));
      await tester.pumpAndSettle();
      expect(prefs.getStringList('favorite_team_ids'), isEmpty);
      await unmount(tester);
    });

    testWidgets('searches after a pause in typing', (tester) async {
      final backend = TeamsBackend();
      await pumpApp(tester, const Scaffold(body: TeamPicker()), client: backend.client);

      await tester.enterText(find.byType(TextField), 'r');
      await tester.enterText(find.byType(TextField), 're');
      await tester.enterText(find.byType(TextField), 'real');
      await tester.pump(TeamPicker.debounce);
      await tester.pumpAndSettle();
      expect(backend.count('/teams/search'), 1); // one request, not one per keystroke
      expect(find.text('Real Madrid CF'), findsOneWidget);
      expect(find.text('Villarreal CF'), findsOneWidget);
      expect(find.text('Ligue 1'), findsNothing);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump(TeamPicker.debounce);
      await tester.pumpAndSettle();
      expect(find.text('No teams found for "zzz".'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(find.text('Ligue 1'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('teams you follow are listed first, with a star to unfollow', (tester) async {
      await pumpApp(
        tester,
        const Scaffold(body: TeamPicker(onOpen: _noop)),
        client: TeamsBackend().client,
        prefs: {
          'favorite_team_ids': ['86'],
          'favorite_team_info': '{"86": {"id": 86, "name": "Real Madrid CF"}}',
        },
      );
      expect(find.text('Teams you follow'), findsOneWidget);
      expect(find.byTooltip('Unfollow Real Madrid CF'), findsWidgets);
      await tester.tap(find.byTooltip('Unfollow Real Madrid CF').first);
      await tester.pumpAndSettle();
      expect(find.text('Teams you follow'), findsNothing);
      await unmount(tester);
    });
  });
}

void _noop(Object _) {}
