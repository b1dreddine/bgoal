import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'models.dart';

/// Favorite team ids, in the order the user picked them.
///
/// Stored on the device and synced to the backend by the notifications controller
/// (POST/PUT /devices) so pushes can be targeted. Names and crests are kept alongside
/// so the settings screen can list teams without a network call.
class FavoritesNotifier extends Notifier<List<int>> {
  static const _key = 'favorite_team_ids';
  static const _infoKey = 'favorite_team_info';

  @override
  List<int> build() {
    final raw = ref.watch(sharedPrefsProvider).getStringList(_key) ?? const [];
    return raw.map(int.tryParse).whereType<int>().toList();
  }

  bool isFavorite(int teamId) => state.contains(teamId);

  /// Saved details of a followed team, or null for ids saved before details were kept.
  Team? info(int teamId) {
    final j = _readInfo()['$teamId'];
    return j is Map<String, dynamic> ? Team.fromJson(j) : null;
  }

  Future<void> toggle(Team team) async {
    final prefs = ref.read(sharedPrefsProvider);
    final info = _readInfo();
    if (isFavorite(team.id)) {
      state = [...state.where((id) => id != team.id)];
      info.remove('${team.id}');
    } else {
      state = [...state, team.id];
      info['${team.id}'] = team.toJson();
    }
    await prefs.setString(_infoKey, jsonEncode(info));
    await prefs.setStringList(_key, [for (final id in state) '$id']);
  }

  Map<String, dynamic> _readInfo() {
    final raw = ref.read(sharedPrefsProvider).getString(_infoKey);
    if (raw == null) return {};
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }
}

final favoritesProvider = NotifierProvider<FavoritesNotifier, List<int>>(FavoritesNotifier.new);
