import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ads_service.dart';

/// Overridden in main() with [AdMobService] on Android and iOS.
final adsServiceProvider = Provider<AdsService>((ref) => const NoAdsService());

final adsControllerProvider = NotifierProvider<AdsController, AdsState>(AdsController.new);

class AdsState {
  const AdsState({this.ready = false, this.privacyOptionsRequired = false});

  /// Consent is settled and the SDK is running: ad slots may load.
  final bool ready;
  final bool privacyOptionsRequired;
}

class AdsController extends Notifier<AdsState> {
  Future<void>? _starting;

  @override
  AdsState build() => const AdsState();

  /// Called when the home screen first shows, so the consent message never covers
  /// onboarding. Safe to call more than once.
  Future<void> start() => _starting ??= _start();

  Future<void> _start() async {
    final service = ref.read(adsServiceProvider);
    try {
      final ready = await service.start();
      state = AdsState(ready: ready, privacyOptionsRequired: await service.privacyOptionsRequired());
    } catch (_) {
      // An ad SDK problem must never break the app: it just runs without ads.
      state = const AdsState();
    }
  }

  /// "Privacy choices" in Settings. The answer can change whether ads may load.
  Future<void> showPrivacyOptions() async {
    final service = ref.read(adsServiceProvider);
    try {
      await service.showPrivacyOptions();
      state = AdsState(ready: await service.canRequestAds(), privacyOptionsRequired: state.privacyOptionsRequired);
    } catch (_) {}
  }
}
