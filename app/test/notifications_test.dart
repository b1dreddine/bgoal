import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:livescores/data/api_client.dart';
import 'package:livescores/data/favorites.dart';
import 'package:livescores/data/models.dart';
import 'package:livescores/features/settings/app_settings.dart';
import 'package:livescores/notifications/device_sync.dart';
import 'package:livescores/notifications/notification_settings.dart';
import 'package:livescores/notifications/notifications_controller.dart';
import 'package:livescores/notifications/push_links.dart';
import 'package:livescores/notifications/push_service.dart';
import 'package:livescores/notifications/secret_store.dart';
import 'package:livescores/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_push.dart';

/// Minimal stand-in for the backend's /devices endpoints.
class FakeBackend {
  final requests = <http.Request>[];
  bool online = true;
  bool forgetDevices = false;
  int _next = 0;

  late final client = MockClient((req) async {
    requests.add(req);
    if (!online) throw const SocketException('no network');
    if (req.method == 'POST' && req.url.path == '/devices') {
      _next++;
      return http.Response(jsonEncode({'id': 'device-$_next', 'secret': 'secret-$_next'}), 201);
    }
    if (req.method == 'PUT') {
      return forgetDevices ? http.Response('{"detail":"Device not found"}', 404) : http.Response('{}', 200);
    }
    return http.Response('{}', 404);
  });

  Map<String, dynamic> body(int i) => jsonDecode(requests[i].body) as Map<String, dynamic>;
  List<String> get calls => [for (final r in requests) '${r.method} ${r.url.path}'];
}

/// Lets pending microtasks and zero-delay timers run.
Future<void> settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

const arsenal = Team(id: 57, name: 'Arsenal FC', shortName: 'Arsenal', tla: 'ARS');
const chelsea = Team(id: 61, name: 'Chelsea FC', shortName: 'Chelsea', tla: 'CHE');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized(); // AppLifecycleListener in the controller

  group('push links', () {
    test('match id from push data', () {
      expect(matchIdFromData({'match_id': '2026102800'}), 2026102800);
      expect(matchIdFromData({'deep_link': 'bgoal://match/42'}), 42);
      expect(matchIdFromData({'type': 'goal'}), isNull);
    });

    test('deep link redirect', () {
      expect(deepLinkRedirect(Uri.parse('bgoal://match/42')), '/match/42');
      expect(deepLinkRedirect(Uri.parse('/42')), '/match/42'); // how some platforms deliver it
      expect(deepLinkRedirect(Uri.parse('bgoal://nonsense')), '/');
      expect(deepLinkRedirect(Uri.parse('/match/42')), isNull);
      expect(deepLinkRedirect(Uri.parse('/')), isNull);
    });
  });

  group('settings and payload', () {
    test('settings survive a save/load round trip', () {
      const settings = NotificationSettings(
        enabled: false,
        quietHours: QuietHours(enabled: true, start: LocalTime(23, 30), end: LocalTime(6, 0)),
        disabled: {57: {AlertType.halfTime, AlertType.varDecision}},
      );
      final back = NotificationSettings.fromJson(jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>);
      expect(back.enabled, isFalse);
      expect(back.quietHours.start, const LocalTime(23, 30));
      expect(back.isOn(57, AlertType.halfTime), isFalse);
      expect(back.isOn(57, AlertType.goals), isTrue);
      expect(back.isOn(61, AlertType.halfTime), isTrue); // other teams keep defaults
    });

    test('device payload matches the backend contract', () {
      final p = devicePayload(
        fcmToken: null,
        language: 'ar',
        timezone: 'Africa/Casablanca',
        notificationsEnabled: true,
        settings: const NotificationSettings(disabled: {57: {AlertType.redCards}}),
        favoriteTeamIds: [57, 61],
      );
      expect(p['fcm_token'], ''); // "" clears a stale token on the backend
      expect(p['quiet_hours'], {'enabled': false, 'start': '22:00', 'end': '07:00'});
      expect(p['favorite_teams'], [
        {
          'team_id': 57,
          'notifications': {
            'starting_soon': true,
            'kickoff': true,
            'goals': true,
            'red_cards': false,
            'half_time': true,
            'full_time': true,
            'var': true,
          },
        },
        {'team_id': 61, 'notifications': const NotificationSettings().alertsJson(61)},
      ]);
    });
  });

  group('DeviceSync', () {
    late FakeBackend backend;
    late SharedPreferences prefs;
    late MemorySecretStore secrets;
    late DeviceSync sync;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      backend = FakeBackend();
      secrets = MemorySecretStore();
      sync = DeviceSync(
        api: ApiClient(baseUrl: 'http://test', client: backend.client),
        prefs: prefs,
        secrets: secrets,
        platform: 'ios',
      );
    });

    test('registers once, then only sends changes with its secret', () async {
      await sync.sync({'language': 'en'});
      expect(backend.calls, ['POST /devices']);
      expect(backend.body(0)['platform'], 'ios');
      expect(sync.deviceId, 'device-1');
      expect(secrets.values['device_secret'], 'secret-1');

      await sync.sync({'language': 'en'}); // unchanged: no request
      await sync.sync({'language': 'fr'});
      expect(backend.calls, ['POST /devices', 'PUT /devices/device-1/preferences']);
      expect(backend.requests.last.headers['Authorization'], 'Bearer secret-1');
    });

    test('offline: the failed change is sent on the next attempt', () async {
      await sync.sync({'language': 'en'});
      backend.online = false;
      await expectLater(sync.sync({'language': 'fr'}), throwsA(isA<ApiException>()));
      backend.online = true;
      await sync.sync({'language': 'fr'});
      expect(backend.calls.last, 'PUT /devices/device-1/preferences');
      expect(backend.body(backend.requests.length - 1)['language'], 'fr');
    });

    test('re-registers when the backend no longer knows the device', () async {
      await sync.sync({'language': 'en'});
      backend.forgetDevices = true;
      await sync.sync({'language': 'fr'});
      expect(backend.calls, ['POST /devices', 'PUT /devices/device-1/preferences', 'POST /devices']);
      expect(sync.deviceId, 'device-2');
      expect(secrets.values['device_secret'], 'secret-2');
    });
  });

  group('NotificationsController', () {
    late FakeBackend backend;
    late FakePush push;
    late ProviderContainer container;
    late NotificationsController controller;
    late List<int> openedMatches;

    Future<void> setUpWith(Map<String, Object> prefsValues) async {
      SharedPreferences.setMockInitialValues(prefsValues);
      final prefs = await SharedPreferences.getInstance();
      backend = FakeBackend();
      push = FakePush();
      openedMatches = [];
      container = ProviderContainer(overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        timezoneProvider.overrideWithValue('Europe/Paris'),
        apiClientProvider.overrideWithValue(ApiClient(baseUrl: 'http://test', client: backend.client)),
        pushServiceProvider.overrideWithValue(push),
        secretStoreProvider.overrideWithValue(MemorySecretStore()),
        devicePlatformProvider.overrideWithValue('android'),
        systemLanguageProvider.overrideWithValue('fr'),
      ]);
      controller = container.read(notificationsControllerProvider);
    }

    // Onboarding done: the prompt-on-first-follow rule applies.
    setUp(() => setUpWith({'onboarding_done': true}));

    tearDown(() => container.dispose());

    Future<void> start() => controller.start(openMatch: openedMatches.add);

    test('registers at launch without asking for permission', () async {
      await start();
      expect(push.permissionRequests, 0);
      expect(backend.calls, ['POST /devices']);
      final body = backend.body(0);
      expect(body['platform'], 'android');
      expect(body['language'], 'fr');
      expect(body['timezone'], 'Europe/Paris');
      expect(body['fcm_token'], 'token-1');
      expect(body['notifications_enabled'], isFalse); // no permission yet
      expect(body['favorite_teams'], isEmpty);
    });

    test('asks for permission when the first team is followed, then syncs it', () async {
      await start();
      await container.read(favoritesProvider.notifier).toggle(arsenal);
      await settle();
      expect(push.permissionRequests, 1);
      expect(container.read(pushPermissionProvider), PushPermission.granted);

      await controller.syncNow();
      final body = backend.body(backend.requests.length - 1);
      expect(backend.calls.last, 'PUT /devices/device-1/preferences');
      expect(body['notifications_enabled'], isTrue);
      expect(body['favorite_teams'], [
        {'team_id': 57, 'notifications': const NotificationSettings().alertsJson(57)},
      ]);

      // Following another team doesn't ask again.
      await container.read(favoritesProvider.notifier).toggle(chelsea);
      await settle();
      expect(push.permissionRequests, 1);
    });

    test('turned-off alerts and the master switch reach the backend', () async {
      await start();
      await container.read(favoritesProvider.notifier).toggle(arsenal);
      await settle();
      final settings = container.read(notificationSettingsProvider.notifier);
      await settings.setAlert(57, AlertType.halfTime, false);
      await settings.setQuietHours(const QuietHours(enabled: true));
      await controller.syncNow();
      var body = backend.body(backend.requests.length - 1);
      expect((body['favorite_teams'] as List).single['notifications']['half_time'], isFalse);
      expect(body['quiet_hours'], {'enabled': true, 'start': '22:00', 'end': '07:00'});

      await settings.setEnabled(false);
      await controller.syncNow();
      body = backend.body(backend.requests.length - 1);
      expect(body['notifications_enabled'], isFalse);
    });

    test('a new FCM token is sent right away', () async {
      await start();
      push.tokenRefresh.add('token-2');
      await settle();
      await controller.syncNow();
      expect(backend.body(backend.requests.length - 1)['fcm_token'], 'token-2');
    });

    test('notification taps open the match, including the one that launched the app', () async {
      push.initial = const PushMessage(data: {'type': 'goal', 'match_id': '2026102800'});
      await start();
      expect(openedMatches, [2026102800]);

      push.opened.add(const PushMessage(data: {'deep_link': 'bgoal://match/2026102806'}));
      await settle();
      expect(openedMatches, [2026102800, 2026102806]);
    });

    test('pushes received while the app is open are shown', () async {
      await start();
      push.foreground.add(const PushMessage(data: {'match_id': '1'}, title: 'GOAL', messageId: 'm1'));
      await settle();
      expect(push.shown.single.title, 'GOAL');
    });

    test('during onboarding, following a team does not prompt (onboarding asks itself)', () async {
      container.dispose();
      await setUpWith({});
      await start();
      await container.read(favoritesProvider.notifier).toggle(arsenal);
      await settle();
      expect(push.permissionRequests, 0);
      expect(controller.shouldOfferPermission, isTrue);

      await controller.declinePermissionOffer();
      expect(controller.shouldOfferPermission, isFalse);
    });

    test('the language chosen in Settings is used for notifications', () async {
      await start();
      expect(backend.body(0)['language'], 'fr'); // phone language
      await container.read(appSettingsProvider.notifier).setLanguage('ar');
      await settle();
      await controller.syncNow();
      expect(backend.calls.last, 'PUT /devices/device-1/preferences');
      expect(backend.body(backend.requests.length - 1)['language'], 'ar');
    });

    test('works offline and catches up later', () async {
      backend.online = false;
      await start(); // must not throw
      expect(backend.calls, ['POST /devices']);
      backend.online = true;
      await controller.syncNow();
      expect(backend.calls.last, 'POST /devices');
    });
  });
}
