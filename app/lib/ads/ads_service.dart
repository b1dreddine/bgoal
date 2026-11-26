import 'dart:async';

import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../config.dart';

/// What the app needs from the ad SDK, behind an interface so tests, and builds
/// with `ADS=false`, never touch it.
abstract class AdsService {
  /// Shows the consent message where the law requires one (EEA, UK, Switzerland,
  /// some US states; on iOS also Apple's tracking prompt if it's enabled in AdMob),
  /// then starts the SDK. Returns whether ads may be requested.
  Future<bool> start();

  Future<bool> canRequestAds();

  /// True where users must be able to change their consent later (Settings shows
  /// "Privacy choices" then).
  Future<bool> privacyOptionsRequired();

  Future<void> showPrivacyOptions();

  /// Null means no ad in that slot (for example a release build without that id).
  String? get bannerUnitId;
  String? get nativeUnitId;
}

class NoAdsService implements AdsService {
  const NoAdsService();

  @override
  Future<bool> start() async => false;
  @override
  Future<bool> canRequestAds() async => false;
  @override
  Future<bool> privacyOptionsRequired() async => false;
  @override
  Future<void> showPrivacyOptions() async {}
  @override
  String? get bannerUnitId => null;
  @override
  String? get nativeUnitId => null;
}

/// Google AdMob, with Google's own consent tool (UMP). The consent and tracking
/// messages themselves are written in the AdMob console (Privacy & messaging).
class AdMobService implements AdsService {
  @override
  Future<bool> start() async {
    final done = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () => ConsentForm.loadAndShowConsentFormIfRequired((_) => done.complete()),
      // Offline or misconfigured: the consent given in an earlier session still applies.
      (_) => done.complete(),
    );
    await done.future;
    if (!await canRequestAds()) return false;

    await MobileAds.instance.updateRequestConfiguration(RequestConfiguration(
      // Teen-rated ads at most: the app is rated for everyone, and football fans include kids.
      maxAdContentRating: MaxAdContentRating.t,
      tagForChildDirectedTreatment: TagForChildDirectedTreatment.no,
    ));
    await MobileAds.instance.initialize();
    return true;
  }

  @override
  Future<bool> canRequestAds() => ConsentInformation.instance.canRequestAds();

  @override
  Future<bool> privacyOptionsRequired() async =>
      await ConsentInformation.instance.getPrivacyOptionsRequirementStatus() ==
      PrivacyOptionsRequirementStatus.required;

  @override
  Future<void> showPrivacyOptions() {
    final done = Completer<void>();
    ConsentForm.showPrivacyOptionsForm((_) => done.complete());
    return done.future;
  }

  @override
  String? get bannerUnitId => AppConfig.bannerAdUnitId;
  @override
  String? get nativeUnitId => AppConfig.nativeAdUnitId;
}
