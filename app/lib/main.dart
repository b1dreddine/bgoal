import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ads/ads_controller.dart';
import 'ads/ads_service.dart';
import 'app.dart';
import 'config.dart';
import 'notifications/notifications_controller.dart';
import 'notifications/push_service.dart';
import 'providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Everything here is local and fast (no network), so the first frame can show
  // cached matches immediately; fresh data loads after.
  final prefsFuture = SharedPreferences.getInstance();
  final timezoneFuture = _deviceTimezone();
  await initializeDateFormatting();
  final prefs = await prefsFuture;
  final timezone = await timezoneFuture;

  runApp(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        timezoneProvider.overrideWithValue(timezone),
        // The web version (for testers without a store build) has no pushes and no ads:
        // AdMob doesn't run in a browser, and pushes there would need a separate setup.
        // Starts in NotificationsController after the first frame, so it doesn't slow launch.
        if (!kIsWeb) pushServiceProvider.overrideWithValue(FirebasePushService()),
        // Started from the home screen, after onboarding.
        if (AppConfig.adsEnabled && !kIsWeb)
          adsServiceProvider.overrideWithValue(AdMobService()),
      ],
      child: const BGoalApp(),
    ),
  );
}

Future<String> _deviceTimezone() async {
  try {
    final name = await FlutterTimezone.getLocalTimezone();
    if (!(kIsWeb && name == 'UTC')) return name;
  } catch (_) {}
  return _zoneFromOffset(DateTime.now().timeZoneOffset);
}

/// Fallback (the web version can't read the zone's name): a fixed-offset zone, so day
/// boundaries are the user's midnight. "Etc/GMT-1" is UTC+1: the sign is inverted.
String _zoneFromOffset(Duration offset) {
  if (offset.inMinutes % 60 != 0 || offset == Duration.zero) return 'UTC';
  final hours = offset.inHours;
  return 'Etc/GMT${hours > 0 ? '-' : '+'}${hours.abs()}';
}
