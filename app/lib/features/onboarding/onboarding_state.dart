import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/favorites.dart';
import '../../providers.dart';

/// Whether the first-launch flow has been completed (or skipped).
///
/// Someone upgrading from a version without onboarding who already follows teams
/// isn't sent through it.
class OnboardingNotifier extends Notifier<bool> {
  static const _key = 'onboarding_done';

  @override
  bool build() => ref.read(sharedPrefsProvider).getBool(_key) ?? ref.read(favoritesProvider).isNotEmpty;

  Future<void> complete() async {
    state = true;
    await ref.read(sharedPrefsProvider).setBool(_key, true);
  }
}

final onboardingDoneProvider = NotifierProvider<OnboardingNotifier, bool>(OnboardingNotifier.new);
