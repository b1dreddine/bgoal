import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../providers.dart';

/// One match with lineups and stats. Same stale-while-revalidate behaviour as the
/// home screen: the on-device copy shows first, and stays (marked offline) if a
/// refresh fails. Disposed when the screen closes so it stops costing anything.
class MatchDetailController extends AutoDisposeFamilyAsyncNotifier<MatchDetail, int> {
  bool _refreshing = false;
  bool _disposed = false;

  @override
  Future<MatchDetail> build(int id) async {
    ref.onDispose(() => _disposed = true);
    final repo = ref.watch(matchesRepositoryProvider);
    final cached = repo.cachedMatch(id);
    if (cached != null) {
      Future.microtask(refresh);
      return cached;
    }
    return repo.fetchMatch(id);
  }

  Future<void> refresh() async {
    if (_refreshing || _disposed) return;
    _refreshing = true;
    final repo = ref.read(matchesRepositoryProvider);
    try {
      final fresh = await repo.fetchMatch(arg);
      if (!_disposed) state = AsyncData(fresh);
    } catch (e, st) {
      if (_disposed) return;
      final previous = state.valueOrNull ?? repo.cachedMatch(arg);
      state = previous != null ? AsyncData(previous.copyWith(offline: true)) : AsyncError(e, st);
    } finally {
      _refreshing = false;
    }
  }
}

final matchDetailProvider =
    AsyncNotifierProvider.autoDispose.family<MatchDetailController, MatchDetail, int>(MatchDetailController.new);
