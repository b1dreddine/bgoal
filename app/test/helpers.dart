import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:intl/date_symbol_data_local.dart';
import 'package:livescores/data/api_client.dart';
import 'package:livescores/l10n/strings.dart';
import 'package:livescores/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fixtures are real backend output (mock provider at 2026-10-28 18:00 UTC).
dynamic readFixture(String name) => jsonDecode(File('test/fixtures/$name').readAsStringSync());

/// No network images in widget tests.
void _stripImages(Map<String, dynamic> m) {
  m['competition']['emblem_url'] = null;
  m['home']['crest_url'] = null;
  m['away']['crest_url'] = null;
}

/// GET /matches?date=2026-10-28 response.
String dayBody() {
  final env = readFixture('matches_day.json') as Map<String, dynamic>;
  for (final m in env['data'] as List<dynamic>) {
    _stripImages(m as Map<String, dynamic>);
  }
  return jsonEncode(env);
}

/// GET /matches/{id} response; ids 2026102800 (live), 2026102803 (scheduled), 2026102806 (finished).
String matchBody(int id) {
  final env = (readFixture('match_details.json') as Map<String, dynamic>)['$id'] as Map<String, dynamic>;
  _stripImages(env['data'] as Map<String, dynamic>);
  return jsonEncode(env);
}

/// Any fixture with every crest/emblem URL removed. [edit] can adjust the decoded JSON.
String fixtureBody(String name, [void Function(dynamic json)? edit]) {
  final json = readFixture(name);
  void strip(dynamic node) {
    if (node is Map<String, dynamic>) {
      for (final key in ['crest_url', 'emblem_url']) {
        if (node.containsKey(key)) node[key] = null;
      }
      node.values.forEach(strip);
    } else if (node is List) {
      node.forEach(strip);
    }
  }

  strip(json);
  edit?.call(json);
  return jsonEncode(json);
}

http.Response jsonResponse(String body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(body), status, headers: {'content-type': 'application/json'});

Future<void> pumpApp(
  WidgetTester tester,
  Widget home, {
  required http.Client client,
  Map<String, Object> prefs = const {},
  Locale locale = const Locale('en'),
  bool settle = true,
  List<Override> overrides = const [],
}) async {
  await initializeDateFormatting();
  holdAnimationsStill(tester);
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(sp),
        timezoneProvider.overrideWithValue('Europe/London'),
        clockProvider.overrideWithValue(() => DateTime(2026, 10, 28, 18)),
        apiClientProvider.overrideWithValue(ApiClient(baseUrl: 'http://test', client: client)),
        ...overrides,
      ],
      child: MaterialApp(
        locale: locale,
        supportedLocales: S.supportedLocales,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: home,
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

/// Reduced motion, as a phone setting would ask: the live dot and loading shapes
/// stop pulsing, so pumpAndSettle can settle.
void holdAnimationsStill(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

/// Unmount so auto-refresh timers are cancelled before the test ends.
Future<void> unmount(WidgetTester tester) => tester.pumpWidget(const SizedBox());
