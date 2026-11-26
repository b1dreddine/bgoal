import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';
import 'data/api_client.dart';
import 'data/cache_store.dart';
import 'data/matches_repository.dart';
import 'data/teams_repository.dart';

/// Overridden in main() with values loaded before the first frame.
final sharedPrefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError('override in main'));
final timezoneProvider = Provider<String>((ref) => 'UTC');

/// Injectable clock so tests can control "today".
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient(baseUrl: AppConfig.apiBaseUrl));
final cacheStoreProvider = Provider<CacheStore>((ref) => CacheStore(ref.watch(sharedPrefsProvider)));

final matchesRepositoryProvider = Provider<MatchesRepository>(
  (ref) => MatchesRepository(ref.watch(apiClientProvider), ref.watch(cacheStoreProvider), ref.watch(timezoneProvider)),
);

final teamsRepositoryProvider = Provider<TeamsRepository>(
  (ref) => TeamsRepository(ref.watch(apiClientProvider), ref.watch(cacheStoreProvider)),
);
