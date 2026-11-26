import 'api_client.dart';
import 'cache_store.dart';
import 'models.dart';

class TeamsRepository {
  TeamsRepository(this._api, this._cache);

  final ApiClient _api;
  final CacheStore _cache;

  static const _browseKey = 'teams:browse';

  /// Last saved copy of a team page, shown while it refreshes.
  TeamDetail? cachedTeam(int id) {
    final env = _cache.read('team:$id');
    return env == null ? null : _toDetail(env);
  }

  Future<TeamDetail> fetchTeam(int id) async {
    final env = await _api.getEnvelope('/teams/$id');
    await _cache.write('team:$id', env);
    return _toDetail(env);
  }

  /// Not cached: results depend on what was typed.
  Future<List<Team>> search(String query) async {
    final env = await _api.getEnvelope('/teams/search', {'q': query.trim()});
    return [for (final t in (env.data as List<dynamic>? ?? const [])) Team.fromJson(t as Map<String, dynamic>)];
  }

  /// Teams grouped by league. Saved, so the picker also works offline after one load.
  List<CompetitionTeams>? cachedBrowse() {
    final env = _cache.read(_browseKey);
    return env == null ? null : _toBrowse(env);
  }

  Future<List<CompetitionTeams>> fetchBrowse() async {
    final env = await _api.getEnvelope('/teams/browse');
    await _cache.write(_browseKey, env);
    return _toBrowse(env);
  }

  TeamDetail _toDetail(Envelope env) =>
      TeamDetail.fromJson(env.data as Map<String, dynamic>, updatedAt: env.updatedAt, stale: env.stale);

  List<CompetitionTeams> _toBrowse(Envelope env) => [
        for (final g in (env.data as List<dynamic>? ?? const [])) CompetitionTeams.fromJson(g as Map<String, dynamic>),
      ];
}
