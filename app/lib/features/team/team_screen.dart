import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

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
import '../../widgets/team_crest.dart';
import '../../widgets/updated_label.dart';
import '../home/home_logic.dart';
import '../home/match_card.dart';
import 'team_controller.dart';

/// A team: follow button, league position, next matches and recent results.
///
/// Opened with [preview] (from a list or the match screen) the header shows at once.
class TeamScreen extends ConsumerStatefulWidget {
  const TeamScreen({super.key, required this.teamId, this.preview});

  final int teamId;
  final Team? preview;

  @override
  ConsumerState<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends ConsumerState<TeamScreen> {
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

  /// Polls only while one of the team's matches is live or about to start.
  void _refresh({required bool force}) {
    if (!mounted) return;
    final current = ref.read(teamDetailProvider(widget.teamId)).valueOrNull;
    if (current == null) return;
    final now = ref.read(clockProvider)();
    if (force || current.offline || current.upcoming.any((m) => matchNeedsPolling(m, now))) {
      ref.read(teamDetailProvider(widget.teamId).notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final async = ref.watch(teamDetailProvider(widget.teamId));
    final detail = async.valueOrNull;
    final team = detail?.team ?? widget.preview ?? ref.read(favoritesProvider.notifier).info(widget.teamId);
    final favorites = ref.watch(favoritesProvider);
    final followed = favorites.contains(widget.teamId);

    final error = async.hasError && detail == null ? async.error : null;
    final notFound = error is ApiException && error.statusCode == 404;
    final Widget? errorView = error == null
        ? null
        : InfoMessage(
            icon: notFound ? Icons.search_off_rounded : Icons.wifi_off_rounded,
            text: notFound ? s.teamNotFound : s.errorLoadingTeam,
            action: notFound
                ? null
                : FilledButton(
                    onPressed: () => ref.invalidate(teamDetailProvider(widget.teamId)),
                    child: Text(s.retry),
                  ),
          );

    void openMatch(FootballMatch m) => context.push('/match/${m.id}', extra: m);

    final children = <Widget>[
      if (team != null)
        _TeamHeader(
          team: team,
          followed: followed,
          onToggle: () => ref.read(favoritesProvider.notifier).toggle(team),
        ),
      if (detail != null) ...[
        UpdatedLabel(updatedAt: detail.updatedAt, offline: detail.offline, stale: detail.stale),
        if (detail.standing != null) _StandingCard(standing: detail.standing!),
        _SectionTitle(text: s.nextMatches),
        if (detail.upcoming.isEmpty) _EmptyLine(text: s.noUpcomingMatches),
        for (final m in detail.upcoming)
          _DatedMatch(match: m, favorites: favorites, onTap: () => openMatch(m)),
        _SectionTitle(text: s.recentResults),
        if (detail.recent.isEmpty) _EmptyLine(text: s.noRecentResults),
        for (final m in detail.recent.reversed)
          _DatedMatch(match: m, favorites: favorites, onTap: () => openMatch(m)),
        const SizedBox(height: 24),
      ] else
        errorView ?? const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator())),
    ];

    return Scaffold(
      appBar: AppBar(title: team == null ? null : Text(team.name, overflow: TextOverflow.ellipsis)),
      body: RefreshIndicator(
        onRefresh: () => ref.read(teamDetailProvider(widget.teamId).notifier).refresh(),
        child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: children),
      ),
      bottomNavigationBar: const BannerAdSlot(),
    );
  }
}

class _TeamHeader extends StatelessWidget {
  const _TeamHeader({required this.team, required this.followed, required this.onToggle});

  final Team team;
  final bool followed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        children: [
          TeamCrest(url: team.crestUrl, fallback: team.tla ?? team.displayName, size: 72),
          const SizedBox(height: 12),
          Semantics(
            header: true,
            child: Text(team.name, textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
          ),
          if (team.country != null)
            Text(
              team.country!,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          const SizedBox(height: 12),
          followed
              ? FilledButton.tonalIcon(
                  onPressed: onToggle,
                  icon: const Icon(Icons.star_rounded),
                  label: Text(s.following),
                )
              : FilledButton.icon(
                  onPressed: onToggle,
                  icon: const Icon(Icons.star_outline_rounded),
                  label: Text(s.followButton),
                ),
        ],
      ),
    );
  }
}

class _StandingCard extends StatelessWidget {
  const _StandingCard({required this.standing});

  final Standing standing;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final st = standing;
    final gd = st.goalDifference > 0 ? '+${st.goalDifference}' : '${st.goalDifference}';
    final cells = [
      (s.tablePlayed, '${st.played}'),
      (s.tableWon, '${st.won}'),
      (s.tableDrawn, '${st.draw}'),
      (s.tableLost, '${st.lost}'),
      (s.tableGoalDiff, gd),
      (s.tablePoints, '${st.points}'),
    ];
    final form = (st.form ?? '').split(',').map((f) => f.trim()).where((f) => f.isNotEmpty).toList();

    return Semantics(
      container: true,
      excludeSemantics: true,
      label: s.semStanding(st.position, st.competition.name, st.points, st.played, st.won, st.draw, st.lost),
      child: Card(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  TeamCrest(
                    url: st.competition.emblemUrl,
                    fallback: st.competition.code ?? st.competition.name,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      s.standingPosition(st.position, st.competition.name),
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (final (label, value) in cells)
                    Expanded(
                      child: Column(
                        children: [
                          Text(value, style: theme.textTheme.titleMedium),
                          Text(
                            label,
                            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              if (form.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(spacing: 6, children: [for (final f in form) _FormChip(result: f)]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// W / D / L as a coloured square, in the current language.
class _FormChip extends StatelessWidget {
  const _FormChip({required this.result});

  final String result;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    final (label, bg, fg) = switch (result.toUpperCase()) {
      'W' => (s.formWin, Colors.green.shade700, Colors.white),
      'L' => (s.formLoss, scheme.error, scheme.onError),
      _ => (s.formDraw, scheme.surfaceContainerHighest, scheme.onSurface),
    };
    return Container(
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
        header: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        ),
      );
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    );
  }
}

/// A match card with its date and competition above it: unlike the home screen, a
/// team's matches span several days.
class _DatedMatch extends StatelessWidget {
  const _DatedMatch({required this.match, required this.favorites, required this.onTap});

  final FootballMatch match;
  final List<int> favorites;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toString();
    final date = DateFormat.MMMEd(locale).format(match.kickoff.toLocal());
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4, bottom: 4),
            child: Text(
              '$date · ${match.competition.name}',
              style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          MatchCard(
            key: ValueKey(match.id),
            match: match,
            favoriteTeamIds: favorites,
            onTap: onTap,
            onLongPress: () => showFollowSheet(context, match),
          ),
        ],
      ),
    );
  }
}
