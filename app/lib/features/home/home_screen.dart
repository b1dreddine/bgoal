import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../ads/ad_slots.dart';
import '../../ads/ads_controller.dart';
import '../../config.dart';
import '../../data/favorites.dart';
import '../../data/models.dart';
import '../../l10n/strings.dart';
import '../../providers.dart';
import '../../widgets/follow_sheet.dart';
import '../../widgets/foreground_poller.dart';
import '../../widgets/info_message.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/team_crest.dart';
import '../../widgets/updated_label.dart';
import 'date_strip.dart';
import 'home_logic.dart';
import 'match_card.dart';
import 'matches_controller.dart';

/// Whether the competitions outside the top ones are shown (kept while the app is open).
final showOtherCompetitionsProvider = StateProvider<bool>((ref) => false);

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late final _poller = ForegroundPoller(interval: AppConfig.liveRefreshInterval, onPoll: _refresh);

  @override
  void initState() {
    super.initState();
    _poller.start();
    // After onboarding, so a consent message never covers it.
    ref.read(adsControllerProvider.notifier).start();
  }

  @override
  void dispose() {
    _poller.dispose();
    super.dispose();
  }

  void _refresh({required bool force}) {
    if (!mounted) return;
    final day = ref.read(selectedDayProvider);
    final current = ref.read(matchesProvider(day)).valueOrNull;
    if (current == null) return;
    if (force || current.offline || needsLivePolling(current, ref.read(clockProvider)())) {
      ref.read(matchesProvider(day).notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final today = dayFrom(ref.watch(clockProvider)(), 0);
    final day = ref.watch(selectedDayProvider);
    final matches = ref.watch(matchesProvider(day));
    final favorites = ref.watch(favoritesProvider);
    final stripHeight = MediaQuery.textScalerOf(context).scale(40) + 16;
    final adsReady = ref.watch(adsControllerProvider.select((s) => s.ready));

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/brand/mark_green.png', width: 28, height: 28, excludeFromSemantics: true),
            const SizedBox(width: 8),
            Text(s.appTitle),
          ],
        ),
        actions: [
          IconButton(
            tooltip: s.searchTeams,
            icon: const Icon(Icons.search),
            onPressed: () => context.push('/teams'),
          ),
          IconButton(
            tooltip: s.settings,
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(stripHeight),
          child: SizedBox(
            height: stripHeight,
            child: DateStrip(
              today: today,
              selected: day,
              onSelected: (d) => ref.read(selectedDayProvider.notifier).state = d,
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(matchesProvider(day).notifier).refresh(),
        child: matches.when(
          skipLoadingOnRefresh: true,
          skipLoadingOnReload: true,
          data: (data) => _MatchList(
            day: data,
            favorites: favorites,
            showAd: adsReady,
            // The match is passed along so its header shows instantly while details load.
            onTap: (m) => context.push('/match/${m.id}', extra: m),
            onLongPress: (m) => showFollowSheet(context, m),
          ),
          loading: () => const MatchListSkeleton(),
          error: (_, __) => InfoMessage(
            icon: Icons.wifi_off_rounded,
            text: s.errorLoading,
            action: FilledButton(onPressed: () => ref.invalidate(matchesProvider(day)), child: Text(s.retry)),
          ),
        ),
      ),
      bottomNavigationBar: const BannerAdSlot(),
    );
  }
}

class _MatchList extends ConsumerWidget {
  const _MatchList({
    required this.day,
    required this.favorites,
    required this.showAd,
    required this.onTap,
    required this.onLongPress,
  });

  final MatchDay day;
  final List<int> favorites;
  final bool showAd;
  final ValueChanged<FootballMatch> onTap;
  final ValueChanged<FootballMatch> onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final sections = buildSections(day.matches, favorites);
    final main = [for (final sec in sections) if (sec.isTop || sec.isFavorites) sec];
    final others = [for (final sec in sections) if (!sec.isTop && !sec.isFavorites) sec];
    // With nothing in the top competitions that day, show the others straight away.
    final expanded = ref.watch(showOtherCompetitionsProvider) || main.isEmpty;
    final visible = [...main, if (expanded) ...others];
    // One native ad between leagues: after the second section, never at the top.
    final adAfter = showAd && visible.length >= 3 ? 1 : -1;

    Widget section(int i, MatchSection section) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionHeader(section: section),
            for (final m in section.matches)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: MatchCard(
                  key: ValueKey(m.id),
                  match: m,
                  favoriteTeamIds: favorites,
                  onTap: () => onTap(m),
                  onLongPress: () => onLongPress(m),
                ),
              ),
            if (i == adAfter) const NativeAdSlot(key: ValueKey('native-ad')),
          ],
        );

    final items = <Widget>[
      UpdatedLabel(updatedAt: day.updatedAt, offline: day.offline, stale: day.stale),
      if (sections.isEmpty) InfoMessage(icon: Icons.sports_soccer, text: s.noMatches),
      for (final (i, sec) in main.indexed) section(i, sec),
      if (others.isNotEmpty && main.isNotEmpty)
        _OtherCompetitionsButton(
          expanded: expanded,
          matchCount: others.fold(0, (n, sec) => n + sec.matches.length),
          onPressed: () => ref.read(showOtherCompetitionsProvider.notifier).state = !expanded,
        ),
      // Grows open smoothly instead of jumping.
      AnimatedSize(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: !expanded
            ? const SizedBox(width: double.infinity)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [for (final (i, sec) in others.indexed) section(main.length + i, sec)],
              ),
      ),
      const SizedBox(height: 24),
    ];
    // Always scrollable so pull-to-refresh works even with few matches.
    return ListView(physics: const AlwaysScrollableScrollPhysics(), children: items);
  }
}

class _OtherCompetitionsButton extends StatelessWidget {
  const _OtherCompetitionsButton({required this.expanded, required this.matchCount, required this.onPressed});

  final bool expanded;
  final int matchCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: FilledButton.tonal(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        onPressed: onPressed,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(expanded ? s.hideOtherCompetitions : s.otherCompetitions),
            if (!expanded) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: theme.colorScheme.primary, borderRadius: BorderRadius.circular(10)),
                child: Text(
                  s.matchCount(matchCount),
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.w700),
                ),
              ),
            ],
            const SizedBox(width: 4),
            AnimatedRotation(
              turns: expanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 250),
              child: const Icon(Icons.expand_more),
            ),
          ],
        ),
      ),
    );
  }
}
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.section});

  final MatchSection section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = section.competition;
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Row(
          children: [
            if (section.isFavorites)
              Icon(Icons.star_rounded, size: 20, color: theme.colorScheme.primary)
            else
              TeamCrest(url: c!.emblemUrl, fallback: c.code ?? c.name, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: section.isFavorites ? S.of(context).yourTeams : c!.name,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (!section.isFavorites && c!.country != null)
                    TextSpan(
                      text: '  ·  ${c.country}',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
