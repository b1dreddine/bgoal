import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../providers.dart';
import 'home_logic.dart';

/// The local calendar day shown on the home screen.
final selectedDayProvider = StateProvider<DateTime>((ref) => dayFrom(ref.read(clockProvider)(), 0));

/// Matches for one local day.
///
/// Stale-while-revalidate: the on-device copy is returned immediately (fast startup),
/// then replaced by fresh data. If the refresh fails, the cached data stays on screen
/// with `offline: true` so the UI can show "last updated".
class MatchesController extends FamilyAsyncNotifier<MatchDay, DateTime> {
  bool _refreshing = false;

  @override
  Future<MatchDay> build(DateTime day) async {
    final repo = ref.watch(matchesRepositoryProvider);
    final cached = repo.cachedDay(day);
    if (cached != null) {
      Future.microtask(refresh);
      return cached;
    }
    return repo.fetchDay(day);
  }

  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    final repo = ref.read(matchesRepositoryProvider);
    try {
      state = AsyncData(await repo.fetchDay(arg));
    } catch (e, st) {
      final previous = state.valueOrNull ?? repo.cachedDay(arg);
      state = previous != null ? AsyncData(previous.copyWith(offline: true)) : AsyncError(e, st);
    } finally {
      _refreshing = false;
    }
  }
}

final matchesProvider =
    AsyncNotifierProvider.family<MatchesController, MatchDay, DateTime>(MatchesController.new);
