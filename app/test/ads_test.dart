import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:livescores/ads/ad_slots.dart';
import 'package:livescores/ads/ads_controller.dart';
import 'package:livescores/ads/ads_service.dart';
import 'package:livescores/features/home/home_screen.dart';
import 'package:livescores/features/settings/settings_screen.dart';

import 'helpers.dart';

/// Records calls; returns no ad unit ids, so slots never reach the real SDK.
class FakeAds implements AdsService {
  FakeAds({this.allowed = true, this.privacyRequired = false, this.fail = false});

  bool allowed;
  final bool privacyRequired;
  final bool fail;
  int starts = 0;
  int privacyFormShown = 0;

  @override
  Future<bool> start() async {
    starts++;
    if (fail) throw StateError('sdk');
    return allowed;
  }

  @override
  Future<bool> canRequestAds() async => allowed;
  @override
  Future<bool> privacyOptionsRequired() async => privacyRequired;
  @override
  Future<void> showPrivacyOptions() async => privacyFormShown++;
  @override
  String? get bannerUnitId => null;
  @override
  String? get nativeUnitId => null;
}

void main() {
  test('starts once, even when asked twice', () async {
    final ads = FakeAds(privacyRequired: true);
    final container = ProviderContainer(overrides: [adsServiceProvider.overrideWithValue(ads)]);
    addTearDown(container.dispose);

    await Future.wait([
      container.read(adsControllerProvider.notifier).start(),
      container.read(adsControllerProvider.notifier).start(),
    ]);
    expect(ads.starts, 1);
    expect(container.read(adsControllerProvider).ready, isTrue);
    expect(container.read(adsControllerProvider).privacyOptionsRequired, isTrue);
  });

  test('no consent, or an SDK error, means no ads and no crash', () async {
    for (final ads in [FakeAds(allowed: false), FakeAds(fail: true)]) {
      final container = ProviderContainer(overrides: [adsServiceProvider.overrideWithValue(ads)]);
      await container.read(adsControllerProvider.notifier).start();
      expect(container.read(adsControllerProvider).ready, isFalse);
      container.dispose();
    }
  });

  test('changing privacy choices updates whether ads may load', () async {
    final ads = FakeAds(privacyRequired: true);
    final container = ProviderContainer(overrides: [adsServiceProvider.overrideWithValue(ads)]);
    addTearDown(container.dispose);
    await container.read(adsControllerProvider.notifier).start();

    ads.allowed = false;
    await container.read(adsControllerProvider.notifier).showPrivacyOptions();
    expect(ads.privacyFormShown, 1);
    expect(container.read(adsControllerProvider).ready, isFalse);
    expect(container.read(adsControllerProvider).privacyOptionsRequired, isTrue);
  });

  group('home list', () {
    Future<void> pumpHome(WidgetTester tester, FakeAds ads) async {
      // Tall enough that every section is built.
      tester.view.physicalSize = const Size(1080, 8000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpApp(
        tester,
        const HomeScreen(),
        client: MockClient((_) async => jsonResponse(dayBody())),
        overrides: [adsServiceProvider.overrideWithValue(ads)],
      );
    }

    testWidgets('one native ad between the second and third league, once ads are allowed', (tester) async {
      final ads = FakeAds();
      await pumpHome(tester, ads);
      expect(ads.starts, 1); // the home screen starts ads (consent first)
      expect(find.byType(NativeAdSlot), findsOneWidget);
      expect(find.byType(BannerAdSlot), findsOneWidget);

      final headers = [
        for (final name in ['Premier League', 'Primera Division', 'Ligue 1']) tester.getTopLeft(find.textContaining(name)).dy,
      ]..sort();
      final adY = tester.getTopLeft(find.byType(NativeAdSlot)).dy;
      expect(adY, greaterThan(headers[1]));
      expect(adY, lessThan(headers[2]));
      await unmount(tester);
    });

    testWidgets('no ad slot in the list without consent', (tester) async {
      await pumpHome(tester, FakeAds(allowed: false));
      expect(find.byType(NativeAdSlot), findsNothing);
      await unmount(tester);
    });
  });

  testWidgets('Settings offers privacy choices only where they are required', (tester) async {
    final ads = FakeAds(privacyRequired: true);
    await pumpApp(
      tester,
      const SettingsScreen(),
      client: MockClient((_) async => jsonResponse('{}')),
      overrides: [adsServiceProvider.overrideWithValue(ads)],
      settle: false,
    );
    // Settings itself doesn't start ads; the home screen does.
    final container = ProviderScope.containerOf(tester.element(find.byType(SettingsScreen)));
    await container.read(adsControllerProvider.notifier).start();
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Privacy choices'), 200);
    await tester.tap(find.text('Privacy choices'));
    await tester.pumpAndSettle();
    expect(ads.privacyFormShown, 1);
    await tester.scrollUntilVisible(find.text('Match data from football-data.org'), 200);
    expect(find.text('Match data from football-data.org'), findsOneWidget);
    await unmount(tester);

    await pumpApp(
      tester,
      const SettingsScreen(),
      client: MockClient((_) async => jsonResponse('{}')),
      overrides: [adsServiceProvider.overrideWithValue(FakeAds())],
    );
    expect(find.text('Privacy choices'), findsNothing);
    await unmount(tester);
  });
}
