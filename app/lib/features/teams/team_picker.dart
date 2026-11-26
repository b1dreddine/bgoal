import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/favorites.dart';
import '../../data/models.dart';
import '../../l10n/strings.dart';
import '../../widgets/info_message.dart';
import '../../widgets/team_crest.dart';
import 'teams_controller.dart';

/// Search box over a list of teams: search results while typing, otherwise the teams
/// you follow and then every tracked league's teams.
///
/// With [onOpen] (Teams screen) a row opens the team and its star follows it. Without
/// it (onboarding) tapping anywhere on the row follows or unfollows.
class TeamPicker extends ConsumerStatefulWidget {
  const TeamPicker({super.key, this.onOpen, this.showFollowed = true});

  final ValueChanged<Team>? onOpen;
  final bool showFollowed;

  static const debounce = Duration(milliseconds: 350);

  @override
  ConsumerState<TeamPicker> createState() => _TeamPickerState();
}

class _TeamPickerState extends ConsumerState<TeamPicker> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(TeamPicker.debounce, () {
      if (mounted) setState(() => _query = text.trim());
    });
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    setState(() => _query = '');
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _controller,
            onChanged: _onChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: s.searchTeams,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: ListenableBuilder(
                listenable: _controller,
                builder: (context, _) => _controller.text.isEmpty
                    ? const SizedBox.shrink()
                    : IconButton(tooltip: s.clearSearch, icon: const Icon(Icons.close), onPressed: _clear),
              ),
              border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(28))),
              isDense: true,
            ),
          ),
        ),
        Expanded(
          child: _query.length >= 2
              ? _SearchResults(query: _query, onOpen: widget.onOpen)
              : _BrowseList(onOpen: widget.onOpen, showFollowed: widget.showFollowed),
        ),
      ],
    );
  }
}

class _SearchResults extends ConsumerWidget {
  const _SearchResults({required this.query, required this.onOpen});

  final String query;
  final ValueChanged<Team>? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    return ref.watch(teamSearchProvider(query)).when(
          data: (teams) => teams.isEmpty
              ? InfoMessage(icon: Icons.search_off_rounded, text: s.noTeamsFound(query))
              : ListView(children: [for (final t in teams) TeamTile(team: t, onOpen: onOpen)]),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => InfoMessage(
            icon: Icons.wifi_off_rounded,
            text: s.errorLoadingTeams,
            action: FilledButton(onPressed: () => ref.invalidate(teamSearchProvider(query)), child: Text(s.retry)),
          ),
        );
  }
}

class _BrowseList extends ConsumerWidget {
  const _BrowseList({required this.onOpen, required this.showFollowed});

  final ValueChanged<Team>? onOpen;
  final bool showFollowed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final favorites = ref.watch(favoritesProvider);
    final notifier = ref.read(favoritesProvider.notifier);
    final browse = ref.watch(teamBrowseProvider);
    final groups = browse.valueOrNull ?? const <CompetitionTeams>[];

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (showFollowed && favorites.isNotEmpty) ...[
          _Header(text: s.followedTeams),
          for (final id in favorites)
            TeamTile(team: notifier.info(id) ?? Team(id: id, name: s.teamFallback(id)), onOpen: onOpen),
        ],
        for (final g in groups) ...[
          _Header(text: g.competition.name, emblemUrl: g.competition.emblemUrl, code: g.competition.code),
          for (final t in g.teams) TeamTile(team: t, onOpen: onOpen),
        ],
        if (browse.isLoading && groups.isEmpty)
          const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
        if (browse.hasError && groups.isEmpty)
          InfoMessage(
            icon: Icons.wifi_off_rounded,
            text: s.errorLoadingTeams,
            action: FilledButton(onPressed: () => ref.invalidate(teamBrowseProvider), child: Text(s.retry)),
          ),
        // Backend reachable but its team list isn't filled yet: search still works.
        if (browse.hasValue && groups.isEmpty)
          InfoMessage(icon: Icons.search, text: s.searchTeamsHint),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.text, this.emblemUrl, this.code});

  final String text;
  final String? emblemUrl;
  final String? code;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Row(
          children: [
            if (code != null || emblemUrl != null) ...[
              TeamCrest(url: emblemUrl, fallback: code ?? text, size: 20),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(text, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

/// One team with its follow state.
class TeamTile extends ConsumerWidget {
  const TeamTile({super.key, required this.team, this.onOpen});

  final Team team;

  /// Null: the whole row follows/unfollows.
  final ValueChanged<Team>? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final followed = ref.watch(favoritesProvider).contains(team.id);
    Future<void> toggle() => ref.read(favoritesProvider.notifier).toggle(team);
    final star = Icon(
      followed ? Icons.star_rounded : Icons.star_outline_rounded,
      color: followed ? Theme.of(context).colorScheme.primary : null,
    );
    final crest = TeamCrest(url: team.crestUrl, fallback: team.tla ?? team.displayName, size: 32);
    final subtitle = team.country == null ? null : Text(team.country!);

    if (onOpen == null) {
      return Semantics(
        toggled: followed,
        child: ListTile(
          leading: crest,
          title: Text(team.name),
          subtitle: subtitle,
          trailing: ExcludeSemantics(child: star),
          onTap: toggle,
        ),
      );
    }
    return ListTile(
      leading: crest,
      title: Text(team.name),
      subtitle: subtitle,
      trailing: IconButton(
        tooltip: followed ? s.unfollow(team.name) : s.follow(team.name),
        isSelected: followed,
        icon: star,
        onPressed: toggle,
      ),
      onTap: () => onOpen!(team),
    );
  }
}
