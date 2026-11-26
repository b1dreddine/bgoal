import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/favorites.dart';
import '../data/models.dart';
import '../l10n/strings.dart';
import 'team_crest.dart';

/// Bottom sheet to follow/unfollow either team of [m], or open its team page.
Future<void> showFollowSheet(BuildContext context, FootballMatch m) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => Consumer(
      builder: (sheetContext, ref, _) {
        final favorites = ref.watch(favoritesProvider);
        final s = S.of(sheetContext);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final team in [m.home, m.away])
                ListTile(
                  leading: TeamCrest(url: team.crestUrl, fallback: team.tla ?? team.displayName, size: 32),
                  title: Text(favorites.contains(team.id) ? s.unfollow(team.name) : s.follow(team.name)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(favorites.contains(team.id) ? Icons.star_rounded : Icons.star_outline_rounded),
                      IconButton(
                        tooltip: s.teamPage(team.name),
                        icon: const Icon(Icons.chevron_right),
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          context.push('/team/${team.id}', extra: team);
                        },
                      ),
                    ],
                  ),
                  onTap: () => ref.read(favoritesProvider.notifier).toggle(team),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    ),
  );
}
