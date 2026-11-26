import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../l10n/strings.dart';
import 'ads_controller.dart';

/// Adaptive banner pinned under a screen's content (use as `Scaffold.bottomNavigationBar`).
///
/// Takes no space until an ad has loaded, and gives the space back if loading fails
/// or the user is offline, so scores never sit next to an empty box.
class BannerAdSlot extends ConsumerStatefulWidget {
  const BannerAdSlot({super.key});

  @override
  ConsumerState<BannerAdSlot> createState() => _BannerAdSlotState();
}

class _BannerAdSlotState extends ConsumerState<BannerAdSlot> {
  BannerAd? _ad;
  bool _loaded = false;
  int? _width;

  Future<void> _load(int width) async {
    _width = width;
    final unit = ref.read(adsServiceProvider).bannerUnitId;
    if (unit == null) return;
    final size = await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(width);
    if (size == null || !mounted || width != _width) return;
    _ad?.dispose();
    _loaded = false;
    _ad = BannerAd(
      adUnitId: unit,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
          if (mounted) setState(() => _ad = null);
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = ref.watch(adsControllerProvider.select((s) => s.ready));
    final width = MediaQuery.sizeOf(context).width.truncate();
    // Load once ads are allowed, and again when the width changes (rotation).
    if (ready && width != _width) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Several builds in one frame schedule several callbacks: only the first loads.
        if (mounted && width != _width) _load(width);
      });
    }
    final ad = _ad;
    if (!ready || !_loaded || ad == null) return const SizedBox.shrink();

    return Semantics(
      container: true,
      label: S.of(context).advertisement,
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Divider(height: 1),
              SizedBox(
                width: ad.size.width.toDouble(),
                height: ad.size.height.toDouble(),
                child: AdWidget(ad: ad),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A native ad drawn with Google's small template, styled like a match card.
/// Placed between leagues in the home list; collapses to nothing until loaded.
class NativeAdSlot extends ConsumerStatefulWidget {
  const NativeAdSlot({super.key});

  @override
  ConsumerState<NativeAdSlot> createState() => _NativeAdSlotState();
}

class _NativeAdSlotState extends ConsumerState<NativeAdSlot> with AutomaticKeepAliveClientMixin {
  NativeAd? _ad;
  bool _loaded = false;
  Brightness? _brightness;

  // Kept while scrolled out of view, so scrolling doesn't request a new ad each time.
  @override
  bool get wantKeepAlive => true;

  void _load(ColorScheme scheme) {
    _brightness = scheme.brightness;
    final unit = ref.read(adsServiceProvider).nativeUnitId;
    if (unit == null) return;
    _ad?.dispose();
    _loaded = false;
    _ad = NativeAd(
      adUnitId: unit,
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
          if (mounted) setState(() => _ad = null);
        },
      ),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.small,
        mainBackgroundColor: scheme.surfaceContainerLow,
        cornerRadius: 12,
        callToActionTextStyle: NativeTemplateTextStyle(
          textColor: scheme.onPrimary,
          backgroundColor: scheme.primary,
          style: NativeTemplateFontStyle.bold,
          size: 14,
        ),
        primaryTextStyle: NativeTemplateTextStyle(textColor: scheme.onSurface, style: NativeTemplateFontStyle.bold, size: 15),
        secondaryTextStyle: NativeTemplateTextStyle(textColor: scheme.onSurfaceVariant, size: 13),
        tertiaryTextStyle: NativeTemplateTextStyle(textColor: scheme.onSurfaceVariant, size: 13),
      ),
    )..load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final ready = ref.watch(adsControllerProvider.select((s) => s.ready));
    final scheme = Theme.of(context).colorScheme;
    // The template's colours are fixed when the ad loads: reload after a theme switch.
    if (ready && scheme.brightness != _brightness) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && scheme.brightness != _brightness) _load(scheme);
      });
    }
    final ad = _ad;
    if (!ready || !_loaded || ad == null) return const SizedBox.shrink();

    return Semantics(
      container: true,
      label: S.of(context).advertisement,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        // Google's size range for the small template.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 90, maxHeight: 120),
          child: AdWidget(ad: ad),
        ),
      ),
    );
  }
}
