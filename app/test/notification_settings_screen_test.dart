import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:livescores/features/settings/notification_settings_screen.dart';
import 'package:livescores/notifications/notifications_controller.dart';
import 'package:livescores/notifications/push_service.dart';
import 'package:livescores/notifications/secret_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_push.dart';
import 'helpers.dart';

void main() {
  final followingArsenal = <String, Object>{
    'favorite_team_ids': ['57'],
    'favorite_team_info': jsonEncode({
      '57': {'id': 57, 'name': 'Arsenal FC', 'short_name': 'Arsenal', 'tla': 'ARS'},
    }),
  };

  Future<FakePush> pumpSettings(WidgetTester tester, {PushPermission status = PushPermission.granted}) async {
    final push = FakePush(status: status);
    await pumpApp(
      tester,
      const NotificationSettingsScreen(),
      client: MockClient((req) async => http.Response(jsonEncode({'id': 'device-1', 'secret': 'secret-1'}), 200)),
      prefs: followingArsenal,
      overrides: [
        pushServiceProvider.overrideWithValue(push),
        pushPermissionProvider.overrideWith((ref) => status),
        secretStoreProvider.overrideWithValue(MemorySecretStore()),
        devicePlatformProvider.overrideWithValue('android'),
      ],
    );
    return push;
  }

  testWidgets('per-team alerts and quiet hours are saved', (tester) async {
    await pumpSettings(tester);
    expect(find.text('Match alerts'), findsOneWidget);
    expect(find.text('Arsenal FC'), findsOneWidget);
    expect(find.text('7 of 7 alerts on'), findsOneWidget);
    expect(find.textContaining('turned off'), findsNothing); // permission granted: no banner

    await tester.tap(find.text('Quiet hours'));
    await tester.pumpAndSettle();
    expect(find.text('No alerts from 10:00 PM to 7:00 AM'), findsOneWidget);
    expect(find.text('From'), findsOneWidget);

    await tester.tap(find.text('Arsenal FC'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Half-time'));
    await tester.pumpAndSettle(); // the jump only shows on the next frame
    await tester.tap(find.text('Half-time'));
    await tester.pumpAndSettle();
    expect(find.text('6 of 7 alerts on'), findsOneWidget);

    final saved = jsonDecode((await SharedPreferences.getInstance()).getString('notification_settings')!);
    expect(saved['quiet_hours']['enabled'], isTrue);
    expect(saved['disabled'], {'57': ['half_time']});
    await unmount(tester);
  });

  testWidgets('explains when the system permission is off and can ask again', (tester) async {
    final push = await pumpSettings(tester, status: PushPermission.denied);
    expect(find.textContaining('Notifications are turned off for this app.'), findsOneWidget);

    await tester.tap(find.text('Turn on'));
    await tester.pumpAndSettle();
    expect(push.permissionRequests, 1);
    expect(find.textContaining('turned off'), findsNothing);
    await unmount(tester);
  });

  testWidgets('switching match alerts off disables the per-team switches', (tester) async {
    await pumpSettings(tester);
    await tester.tap(find.text('Match alerts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Arsenal FC'));
    await tester.pumpAndSettle();
    final goals = tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Goals'));
    expect(goals.onChanged, isNull);
    await unmount(tester);
  });
}
