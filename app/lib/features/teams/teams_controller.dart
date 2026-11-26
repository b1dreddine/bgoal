import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../providers.dart';

/// Teams grouped by league for the picker: the saved copy first, refreshed in the
/// background (the list changes about once a season).
class TeamBrowseController extends AutoDisposeAsyncNotifier<List<CompetitionTeams>> {
  @override
  Future<List<CompetitionTeams>> build() async {
    var disposed = false;
    ref.onDispose(() => disposed = true);
    final repo = ref.watch(teamsRepositoryProvider);
    final cached = repo.cachedBrowse();
    if (cached != null) {
      Future.microtask(() async {
        try {
          final fresh = await repo.fetchBrowse();
          if (!disposed) state = AsyncData(fresh);
        } catch (_) {
          // Keep the saved copy.
        }
      });
      return cached;
    }
    return repo.fetchBrowse();
  }
}

final teamBrowseProvider =
    AsyncNotifierProvider.autoDispose<TeamBrowseController, List<CompetitionTeams>>(TeamBrowseController.new);

/// Search results for an already-debounced query (2+ characters).
final teamSearchProvider = FutureProvider.autoDispose.family<List<Team>, String>(
  (ref, query) => ref.watch(teamsRepositoryProvider).search(query),
);
