import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:livescores/app.dart';
import 'package:livescores/data/api_client.dart';
import 'package:livescores/notifications/notifications_controller.dart';
import 'package:livescores/notifications/secret_store.dart';
import 'package:livescores/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_push.dart';
import 'helpers.dart';

final _backend = MockClient((req) async {
  return switch ((req.method, req.url.path)) {
    ('GET', '/matches') => jsonResponse(dayBody()),
    ('GET', '/teams/browse') => jsonResponse(fixtureBody('teams_browse.json')),
    ('POST', '/devices') => jsonResponse(jsonEncode({'id': 'device-1', 'secret': 'secret-1'}), 201),
    ('PUT', _) => jsonResponse('{}'),
    _ => http.Response('{"detail": "not found"}', 404),
  };
});

/// The real app (router, theme, locale) with the network and Firebase faked.
Future<FakePush> pumpFullApp(WidgetTester tester, SharedPreferences prefs) async {
  await initializeDateFormatting();
  holdAnimationsStill(tester);
  final push = FakePush();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        timezoneProvider.overrideWithValue('Europe/London'),
        clockProvider.overrideWithValue(() => DateTime(2026, 10, 28, 18)),
        apiClientProvider.overrideWithValue(ApiClient(baseUrl: 'http://test', client: _backend)),
        pushServiceProvider.overrideWithValue(push),
        secretStoreProvider.overrideWithValue(MemorySecretStore()),
        devicePlatformProvider.overrideWithValue('android'),
        systemLanguageProvider.overrideWithValue('en'),
      ],
      child: const BGoalApp(),
    ),
  );
  await tester.pumpAndSettle();
  return push;
}

Future<SharedPreferences> freshPrefs([Map<String, Object> values = const {}]) {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('first launch: language, pick a team, then the alerts prompt, then home', (tester) async {
    final prefs = await freshPrefs();
    final push = await pumpFullApp(tester, prefs);
    expect(find.text('Never miss a goal'), findsOneWidget);

    // The language changes the whole app at once.
    await tapText(tester, 'Français');
    expect(find.text('Ne manquez plus aucun but'), findsOneWidget);
    await tapText(tester, 'English');
    expect(find.text('Never miss a goal'), findsOneWidget);

    await tapText(tester, 'Get started');
    expect(find.text('Pick your teams'), findsOneWidget);
    expect(find.text('Skip for now'), findsOneWidget);

    await tapText(tester, 'Arsenal FC');
    // No system prompt in the middle of picking teams.
    expect(push.permissionRequests, 0);
    await tapText(tester, 'Continue (1)');

    expect(find.text('Get alerts for your teams'), findsOneWidget);
    await tapText(tester, 'Turn on alerts');
    expect(push.permissionRequests, 1);

    expect(find.text('BGoal'), findsOneWidget); // home screen
    expect(find.text('Your teams'), findsOneWidget);
    expect(prefs.getBool('onboarding_done'), isTrue);
    await unmount(tester);
  });

  testWidgets('back goes to the previous step', (tester) async {
    await pumpFullApp(tester, await freshPrefs());
    await tapText(tester, 'Get started');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Never miss a goal'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('"Not now" finishes without the system prompt and remembers it', (tester) async {
    final prefs = await freshPrefs();
    final push = await pumpFullApp(tester, prefs);
    await tapText(tester, 'Get started');
    await tapText(tester, 'Arsenal FC');
    await tapText(tester, 'Continue (1)');
    await tapText(tester, 'Not now');
    expect(push.permissionRequests, 0);
    expect(find.text('BGoal'), findsOneWidget);
    expect(prefs.getBool('push_permission_asked'), isTrue);
    await unmount(tester);
  });

  testWidgets('skip goes home, and onboarding is not shown again', (tester) async {
    final prefs = await freshPrefs();
    await pumpFullApp(tester, prefs);
    await tapText(tester, 'Skip');
    expect(find.text('BGoal'), findsOneWidget);
    await unmount(tester);

    await pumpFullApp(tester, prefs);
    expect(find.text('Never miss a goal'), findsNothing);
    expect(find.text('BGoal'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('existing users who follow teams skip onboarding; saved theme and language apply', (tester) async {
    final prefs = await freshPrefs({
      'favorite_team_ids': ['57'],
      'app_settings': jsonEncode({'theme': 'dark', 'language': 'fr'}),
    });
    await pumpFullApp(tester, prefs);
    expect(find.text('Scores en direct'), findsOneWidget);
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    expect(app.locale, const Locale('fr'));
    await unmount(tester);
  });
}
