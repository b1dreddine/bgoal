import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../providers.dart';

/// One team page. Same stale-while-revalidate behaviour as the match screen.
class TeamDetailController extends AutoDisposeFamilyAsyncNotifier<TeamDetail, int> {
  bool _refreshing = false;
  bool _disposed = false;

  @override
  Future<TeamDetail> build(int id) async {
    ref.onDispose(() => _disposed = true);
    final repo = ref.watch(teamsRepositoryProvider);
    final cached = repo.cachedTeam(id);
    if (cached != null) {
      Future.microtask(refresh);
      return cached;
    }
    return repo.fetchTeam(id);
  }

  Future<void> refresh() async {
    if (_refreshing || _disposed) return;
    _refreshing = true;
    final repo = ref.read(teamsRepositoryProvider);
    try {
      final fresh = await repo.fetchTeam(arg);
      if (!_disposed) state = AsyncData(fresh);
    } catch (e, st) {
      if (_disposed) return;
      final previous = state.valueOrNull ?? repo.cachedTeam(arg);
      state = previous != null ? AsyncData(previous.copyWith(offline: true)) : AsyncError(e, st);
    } finally {
      _refreshing = false;
    }
  }
}

final teamDetailProvider =
    AsyncNotifierProvider.autoDispose.family<TeamDetailController, TeamDetail, int>(TeamDetailController.new);
