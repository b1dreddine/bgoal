import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../ads/ad_slots.dart';
import '../../config.dart';
import '../../data/api_client.dart';
import '../../data/favorites.dart';
import '../../data/models.dart';
import '../../l10n/strings.dart';
import '../../providers.dart';
import '../../widgets/follow_sheet.dart';
import '../../widgets/foreground_poller.dart';
import '../../widgets/info_message.dart';
import '../../widgets/updated_label.dart';
import '../home/home_logic.dart';
import 'lineups_tab.dart';
import 'match_controller.dart';
import 'match_header.dart';
import 'stats_tab.dart';
import 'timeline_tab.dart';

/// Match detail: header (score, status, scorers) above Timeline / Lineups / Stats tabs.
///
/// Opened from the home screen (with [preview], so the header shows instantly) or from
/// a notification deep link (id only).
class MatchScreen extends ConsumerStatefulWidget {
  const MatchScreen({super.key, required this.matchId, this.preview});

  final int matchId;
  final FootballMatch? preview;

  @override
  ConsumerState<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends ConsumerState<MatchScreen> {
  late final _poller = ForegroundPoller(interval: AppConfig.liveRefreshInterval, onPoll: _refresh);

  @override
  void initState() {
    super.initState();
    _poller.start();
  }

  @override
  void dispose() {
    _poller.dispose();
    super.dispose();
  }

  void _refresh({required bool force}) {
    if (!mounted) return;
    final current = ref.read(matchDetailProvider(widget.matchId)).valueOrNull;
    if (current == null) return;
    if (force || current.offline || matchNeedsPolling(current.match, ref.read(clockProvider)())) {
      ref.read(matchDetailProvider(widget.matchId).notifier).refresh();
    }
  }

  Future<void> _pullToRefresh() => ref.read(matchDetailProvider(widget.matchId).notifier).refresh();

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final async = ref.watch(matchDetailProvider(widget.matchId));
    final detail = async.valueOrNull;
    final match = detail?.match ?? widget.preview;

    final error = async.hasError && detail == null ? async.error : null;
    final notFound = error is ApiException && error.statusCode == 404;
    final Widget? errorView = error == null
        ? null
        : InfoMessage(
            icon: notFound ? Icons.search_off_rounded : Icons.wifi_off_rounded,
            text: notFound ? s.matchNotFound : s.errorLoadingMatch,
            action: notFound
                ? null
                : FilledButton(
                    onPressed: () => ref.invalidate(matchDetailProvider(widget.matchId)),
                    child: Text(s.retry),
                  ),
          );

    // Nothing to show yet (deep link, no cached copy).
    if (match == null) {
      return Scaffold(
        appBar: AppBar(),
        body: errorView ?? const Center(child: CircularProgressIndicator()),
      );
    }

    final favorites = ref.watch(favoritesProvider);
    final followed = match.involves(favorites.toSet());
    Widget tab(Widget child) => RefreshIndicator(onRefresh: _pullToRefresh, child: child);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(match.competition.name, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              tooltip: s.followTeams,
              icon: Icon(followed ? Icons.star_rounded : Icons.star_outline_rounded),
              onPressed: () => showFollowSheet(context, match),
            ),
          ],
        ),
        body: Column(
          children: [
            MatchHeader(match: match, onTeamTap: (team) => context.push('/team/${team.id}', extra: team)),
            if (detail != null) UpdatedLabel(updatedAt: detail.updatedAt, offline: detail.offline, stale: detail.stale),
            TabBar(tabs: [Tab(text: s.tabTimeline), Tab(text: s.tabLineups), Tab(text: s.tabStats)]),
            Expanded(
              child: detail == null
                  ? errorView ?? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      children: [
                        tab(TimelineTab(match: detail.match)),
                        tab(LineupsTab(match: detail.match)),
                        tab(StatsTab(match: detail.match)),
                      ],
                    ),
            ),
          ],
        ),
        bottomNavigationBar: const BannerAdSlot(),
      ),
    );
  }
}

/// Shown for a malformed match link (e.g. a bad deep link).
class MatchNotFoundScreen extends StatelessWidget {
  const MatchNotFoundScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(),
        body: InfoMessage(icon: Icons.search_off_rounded, text: S.of(context).matchNotFound),
      );
}
