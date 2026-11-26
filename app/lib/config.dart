import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb, kReleaseMode;

// defaultTargetPlatform rather than dart:io's Platform, which throws in the web version.

/// Build-time configuration. Override with
/// `flutter run --dart-define=API_BASE_URL=https://api.example.com`.
class AppConfig {
  static const _fromEnv = String.fromEnvironment('API_BASE_URL');

  static String get apiBaseUrl {
    if (_fromEnv.isNotEmpty) return _fromEnv;
    // Local backend: the Android emulator reaches the host machine via 10.0.2.2.
    return _isAndroid && !kIsWeb ? 'http://10.0.2.2:8000' : 'http://localhost:8000';
  }

  /// Club crests and league emblems are trademarks. `--dart-define=SHOW_CRESTS=false`
  /// builds an app that shows team initials instead (see PUBLISHING.md).
  static const showCrests = bool.fromEnvironment('SHOW_CRESTS', defaultValue: true);

  /// Public privacy policy page, shown in Settings. Required by both stores.
  static const privacyPolicyUrl = String.fromEnvironment('PRIVACY_POLICY_URL');

  /// `--dart-define=ADS=false` builds an app without any ads (no ad SDK calls at all).
  static const adsEnabled = bool.fromEnvironment('ADS', defaultValue: true);

  // AdMob ad unit ids, from AdMob → Apps → Ad units. Debug builds fall back to
  // Google's test units; a release build without an id shows no ad in that slot,
  // so test ads can never ship (and real ones are never clicked during development).
  static const _bannerAndroid = String.fromEnvironment('ADMOB_BANNER_ANDROID');
  static const _bannerIos = String.fromEnvironment('ADMOB_BANNER_IOS');
  static const _nativeAndroid = String.fromEnvironment('ADMOB_NATIVE_ANDROID');
  static const _nativeIos = String.fromEnvironment('ADMOB_NATIVE_IOS');

  static String? get bannerAdUnitId => _unit(
        android: _bannerAndroid,
        ios: _bannerIos,
        testAndroid: 'ca-app-pub-3940256099942544/9214589741',
        testIos: 'ca-app-pub-3940256099942544/2435281174',
      );

  static String? get nativeAdUnitId => _unit(
        android: _nativeAndroid,
        ios: _nativeIos,
        testAndroid: 'ca-app-pub-3940256099942544/2247696110',
        testIos: 'ca-app-pub-3940256099942544/3986624511',
      );

  static String? _unit({required String android, required String ios, required String testAndroid, required String testIos}) {
    final real = _isAndroid ? android : ios;
    if (real.isNotEmpty) return real;
    return kReleaseMode ? null : (_isAndroid ? testAndroid : testIos);
  }

  static bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

  /// How often live scores refresh while the home screen is visible.
  static const liveRefreshInterval = Duration(seconds: 20);

  /// Scheduled matches start being polled this long before kickoff.
  static const preKickoffPollWindow = Duration(minutes: 15);
}
