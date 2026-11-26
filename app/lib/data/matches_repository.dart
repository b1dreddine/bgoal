import 'api_client.dart';
import 'cache_store.dart';
import 'models.dart';

String isoDate(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

class MatchesRepository {
  MatchesRepository(this._api, this._cache, this._timezone);

  final ApiClient _api;
  final CacheStore _cache;

  /// IANA name of the device timezone, so the backend returns the user's *local* day.
  final String _timezone;

  String _key(DateTime day) => 'matches:${isoDate(day)}:$_timezone';

  /// Last saved copy for [day], shown instantly while the network request runs.
  MatchDay? cachedDay(DateTime day) {
    final env = _cache.read(_key(day));
    return env == null ? null : _toDay(env);
  }

  Future<MatchDay> fetchDay(DateTime day) async {
    final env = await _api.getEnvelope('/matches', {'date': isoDate(day), 'tz': _timezone});
    await _cache.write(_key(day), env);
    return _toDay(env);
  }

  /// Last saved copy of one match (detail screen), shown while it refreshes.
  MatchDetail? cachedMatch(int id) {
    final env = _cache.read('match:$id');
    return env == null ? null : _toDetail(env);
  }

  Future<MatchDetail> fetchMatch(int id) async {
    final env = await _api.getEnvelope('/matches/$id');
    await _cache.write('match:$id', env);
    return _toDetail(env);
  }

  MatchDetail _toDetail(Envelope env) => MatchDetail(
        match: FootballMatch.fromJson(env.data as Map<String, dynamic>),
        updatedAt: env.updatedAt,
        stale: env.stale,
      );

  MatchDay _toDay(Envelope env) => MatchDay(
        matches: [
          for (final m in (env.data as List<dynamic>? ?? const []))
            FootballMatch.fromJson(m as Map<String, dynamic>),
        ],
        updatedAt: env.updatedAt,
        stale: env.stale,
      );
}
