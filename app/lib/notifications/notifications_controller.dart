import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/favorites.dart';
import '../features/home/matches_controller.dart';
import '../features/match/match_controller.dart';
import '../features/onboarding/onboarding_state.dart';
import '../features/settings/app_settings.dart';
import '../providers.dart';
import 'device_sync.dart';
import 'notification_settings.dart';
import 'push_service.dart';
import 'secret_store.dart';

/// Overridden in main() with [FirebasePushService].
final pushServiceProvider = Provider<PushService>((ref) => NoPushService());
final secretStoreProvider = Provider<SecretStore>((ref) => SecureSecretStore());
final devicePlatformProvider = Provider<String>((ref) => defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android');

/// Phone language, overridable in tests.
final systemLanguageProvider = Provider<String>((ref) => PlatformDispatcher.instance.locale.languageCode);

/// Language for notification texts: the one chosen in Settings, else the phone's
/// if the backend has it.
final deviceLanguageProvider = Provider<String>((ref) {
  final String? code = ref.watch(appSettingsProvider).languageCode ?? ref.watch(systemLanguageProvider);
  return code != null && const ['en', 'fr', 'ar'].contains(code) ? code : 'en';
});

final deviceSyncProvider = Provider<DeviceSync>(
  (ref) => DeviceSync(
    api: ref.watch(apiClientProvider),
    prefs: ref.watch(sharedPrefsProvider),
    secrets: ref.watch(secretStoreProvider),
    platform: ref.watch(devicePlatformProvider),
  ),
);

/// OS permission to show notifications, refreshed on start and whenever the app resumes.
final pushPermissionProvider = StateProvider<PushPermission>((ref) => PushPermission.notDetermined);

/// Wires pushes into the app:
/// - asks for permission when the user follows their first team (not at launch),
/// - registers the device and keeps favorites / alert settings / token in sync,
/// - opens the match when a notification is tapped (also from a cold start),
/// - shows pushes that arrive while the app is open, and refreshes the scores on screen.
class NotificationsController {
  NotificationsController(this._ref);

  final Ref _ref;
  static const _askedKey = 'push_permission_asked';
  static const debounce = Duration(seconds: 1);
  static const retryAfter = Duration(minutes: 1);

  final _subs = <StreamSubscription<Object?>>[];
  AppLifecycleListener? _lifecycle;
  Timer? _timer;
  String? _token;
  void Function(int matchId)? _openMatch;

  PushService get _push => _ref.read(pushServiceProvider);

  Future<void> start({required void Function(int matchId) openMatch}) async {
    _openMatch = openMatch;
    await _push.init();
    await _refreshPermission();
    _subs
      ..add(_push.onTokenRefresh.listen((t) {
        _token = t;
        scheduleSync(immediate: true);
      }))
      ..add(_push.onOpened.listen(_open))
      ..add(_push.onForegroundMessage.listen(_onForeground));
    _lifecycle = AppLifecycleListener(onResume: () async {
      // The user may have changed the permission in system settings meanwhile.
      await _refreshPermission();
      _token ??= await _push.token();
      scheduleSync(immediate: true);
    });
    _token = await _push.token();
    // Handy for "Send test message" in the Firebase console.
    if (kDebugMode) debugPrint('FCM token: $_token');

    final initial = await _push.initialMessage();
    if (initial != null) _open(initial);
    await syncNow();
  }

  void dispose() {
    _timer?.cancel();
    _lifecycle?.dispose();
    for (final s in _subs) {
      s.cancel();
    }
  }

  /// Called when the favorites list changes. During onboarding the prompt waits for
  /// its own "Get alerts" page instead of interrupting the team picking.
  void onFavoritesChanged(List<int>? previous, List<int> next) {
    if (next.length > (previous?.length ?? 0) && _ref.read(onboardingDoneProvider)) {
      unawaited(maybeAskPermission());
    }
    scheduleSync();
  }

  /// Whether onboarding should show its "Get alerts" page.
  bool get shouldOfferPermission =>
      _push.available &&
      _ref.read(pushPermissionProvider) != PushPermission.granted &&
      !(_ref.read(sharedPrefsProvider).getBool(_askedKey) ?? false);

  /// "Not now" on that page: don't prompt automatically later either; Settings can.
  Future<void> declinePermissionOffer() => _ref.read(sharedPrefsProvider).setBool(_askedKey, true);

  /// The system prompt, once, right after the user follows a team: that's when it
  /// makes sense to them. Later attempts go through [requestPermission] from settings.
  Future<void> maybeAskPermission() async {
    final prefs = _ref.read(sharedPrefsProvider);
    if (!_push.available || _ref.read(pushPermissionProvider) == PushPermission.granted) return;
    if (prefs.getBool(_askedKey) ?? false) return;
    await prefs.setBool(_askedKey, true);
    await requestPermission();
  }

  Future<PushPermission> requestPermission() async {
    final result = await _push.requestPermission();
    _ref.read(pushPermissionProvider.notifier).state = result;
    if (result == PushPermission.granted) _token ??= await _push.token();
    scheduleSync(immediate: true);
    return result;
  }

  /// What the backend should know about this device right now.
  Map<String, dynamic> currentPayload() {
    final settings = _ref.read(notificationSettingsProvider);
    return devicePayload(
      fcmToken: _token,
      language: _ref.read(deviceLanguageProvider),
      timezone: _ref.read(timezoneProvider),
      notificationsEnabled: settings.enabled && _ref.read(pushPermissionProvider) == PushPermission.granted,
      settings: settings,
      favoriteTeamIds: _ref.read(favoritesProvider),
    );
  }

  /// Debounced so flipping several switches sends one request.
  void scheduleSync({bool immediate = false}) {
    _timer?.cancel();
    _timer = Timer(immediate ? Duration.zero : debounce, syncNow);
  }

  Future<void> syncNow() async {
    _timer?.cancel();
    try {
      await _ref.read(deviceSyncProvider).sync(currentPayload());
    } catch (e) {
      // Offline or server down: try again later; nothing is lost meanwhile.
      debugPrint('Device sync failed, retrying in ${retryAfter.inSeconds}s: $e');
      _timer = Timer(retryAfter, syncNow);
    }
  }

  Future<void> _refreshPermission() async {
    _ref.read(pushPermissionProvider.notifier).state = await _push.permission();
  }

  void _open(PushMessage m) {
    final id = m.matchId;
    if (id != null) _openMatch?.call(id);
  }

  void _onForeground(PushMessage m) {
    unawaited(_push.showForeground(m));
    // Something just happened: refresh what's on screen instead of waiting for the next poll.
    final id = m.matchId;
    if (id != null && _ref.exists(matchDetailProvider(id))) {
      unawaited(_ref.read(matchDetailProvider(id).notifier).refresh());
    }
    final day = _ref.read(selectedDayProvider);
    if (_ref.exists(matchesProvider(day))) unawaited(_ref.read(matchesProvider(day).notifier).refresh());
  }
}

final notificationsControllerProvider = Provider<NotificationsController>((ref) {
  final controller = NotificationsController(ref);
  ref.listen(favoritesProvider, controller.onFavoritesChanged);
  ref.listen(notificationSettingsProvider, (_, __) => controller.scheduleSync());
  ref.listen(deviceLanguageProvider, (_, __) => controller.scheduleSync());
  ref.onDispose(controller.dispose);
  return controller;
});
