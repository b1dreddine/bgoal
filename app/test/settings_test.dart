import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:livescores/features/settings/app_settings.dart';
import 'package:livescores/features/settings/settings_screen.dart';
import 'package:livescores/notifications/notifications_controller.dart';
import 'package:livescores/notifications/push_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_push.dart';
import 'helpers.dart';

void main() {
  test('app settings survive a save/load round trip, and ignore unknown values', () {
    const s = AppSettings(themeMode: ThemeMode.dark, languageCode: 'ar');
    final back = AppSettings.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
    expect(back.themeMode, ThemeMode.dark);
    expect(back.locale, const Locale('ar'));

    final odd = AppSettings.fromJson({'theme': 'sepia', 'language': 'de'});
    expect(odd.themeMode, ThemeMode.system);
    expect(odd.locale, isNull); // follow the phone
  });

  testWidgets('theme and language choices are saved', (tester) async {
    await pumpApp(
      tester,
      const SettingsScreen(),
      client: MockClient((_) async => jsonResponse('{}')),
      prefs: {'favorite_team_ids': ['57']},
      overrides: [
        pushServiceProvider.overrideWithValue(FakePush(status: PushPermission.granted)),
        pushPermissionProvider.overrideWith((ref) => PushPermission.granted),
      ],
    );
    expect(find.text('1 team'), findsOneWidget);
    expect(find.text('Match alerts on'), findsOneWidget);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Français'));
    await tester.tap(find.text('Français'));
    await tester.pumpAndSettle();

    final saved = jsonDecode((await SharedPreferences.getInstance()).getString('app_settings')!);
    expect(saved, {'theme': 'dark', 'language': 'fr'});

    await tester.tap(find.text('Phone language'));
    await tester.pumpAndSettle();
    final again = jsonDecode((await SharedPreferences.getInstance()).getString('app_settings')!);
    expect(again['language'], isNull);
    await unmount(tester);
  });
}
