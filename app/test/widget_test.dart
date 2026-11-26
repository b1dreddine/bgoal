import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:livescores/features/home/home_screen.dart';

import 'helpers.dart';

void main() {
  testWidgets('shows matches grouped by competition with favorites pinned', (tester) async {
    final semantics = tester.ensureSemantics();
    late Uri requested;
    final client = MockClient((req) async {
      requested = req.url;
      return jsonResponse(dayBody());
    });
    await pumpApp(tester, const HomeScreen(), client: client, prefs: {'favorite_team_ids': ['57']});

    expect(requested.path, '/matches');
    expect(requested.queryParameters, {'date': '2026-10-28', 'tz': 'Europe/London'});
    expect(find.text('Your teams'), findsOneWidget);
    expect(find.textContaining('Premier League'), findsOneWidget);
    expect(find.text('Chelsea'), findsOneWidget);
    expect(find.text("36'"), findsOneWidget); // live minute
    expect(find.text('HT'), findsOneWidget);
    expect(find.textContaining('Updated'), findsOneWidget);

    // Screen-reader label for the live match
    expect(
      find.bySemanticsLabel(RegExp(r'^Chelsea FC 0, Newcastle United FC 0, minute 36, Premier League')),
      findsOneWidget,
    );
    semantics.dispose();
    await unmount(tester);
  });

  testWidgets('offline: keeps cached data and says when it was last updated', (tester) async {
    var online = true;
    final client = MockClient((req) async {
      if (!online) throw const SocketException('no network');
      return jsonResponse(dayBody());
    });
    await pumpApp(tester, const HomeScreen(), client: client);
    expect(find.text('Chelsea'), findsOneWidget);

    online = false;
    await tester.fling(find.byType(ListView).first, const Offset(0, 400), 1000); // pull to refresh
    await tester.pumpAndSettle();

    expect(find.text('Chelsea'), findsOneWidget);
    expect(find.textContaining('Offline · last updated'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('first launch with no network shows retry', (tester) async {
    final client = MockClient((req) async => throw const SocketException('no network'));
    await pumpApp(tester, const HomeScreen(), client: client);
    expect(find.text('Retry'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('other competitions stay behind a button until tapped', (tester) async {
    // The day's fixture plus one Eredivisie match.
    final body = fixtureBody('matches_day.json', (json) {
      final list = json['data'] as List;
      list.add({
        ...(list.first as Map<String, dynamic>),
        'id': 1,
        'competition': {'id': 2003, 'name': 'Eredivisie', 'code': 'DED', 'country': 'Netherlands'},
        'home': {...(list.first['home'] as Map<String, dynamic>), 'id': 670, 'name': 'Ajax', 'short_name': 'Ajax'},
      });
    });
    await pumpApp(tester, const HomeScreen(), client: MockClient((_) async => jsonResponse(body)));

    // The match list, not the date strip above it.
    final list = find.descendant(of: find.byType(RefreshIndicator), matching: find.byType(Scrollable)).first;
    final button = find.text('Other competitions');
    await tester.scrollUntilVisible(button, 200, scrollable: list);
    expect(find.text('1 match'), findsOneWidget);
    expect(find.text('Ajax'), findsNothing);

    await tester.ensureVisible(button);
    await tester.pumpAndSettle(); // built isn't on screen yet; show it, then tap
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Ajax'), 200, scrollable: list);
    expect(find.text('Ajax'), findsOneWidget);
    expect(find.text('Hide other competitions'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('Arabic renders right-to-left', (tester) async {
    final client = MockClient((req) async => jsonResponse(dayBody()));
    await pumpApp(tester, const HomeScreen(), client: client, locale: const Locale('ar'));
    expect(find.text('اليوم'), findsOneWidget); // "Today" chip
    expect(Directionality.of(tester.element(find.byType(HomeScreen))), TextDirection.rtl);
    await unmount(tester);
  });
}
