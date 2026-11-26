import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

/// On-device copy of the last good response per request, used for instant startup
/// and for offline mode. Keeps the [maxEntries] most recently written entries.
class CacheStore {
  CacheStore(this._prefs, {this.maxEntries = 30});

  final SharedPreferences _prefs;
  final int maxEntries;

  static const _prefix = 'cache:';
  static const _indexKey = 'cache_index';

  Envelope? read(String key) {
    final raw = _prefs.getString('$_prefix$key');
    if (raw == null) return null;
    try {
      return Envelope.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null; // corrupted or from an incompatible version
    }
  }

  Future<void> write(String key, Envelope envelope) async {
    await _prefs.setString('$_prefix$key', jsonEncode(envelope.toJson()));
    final index = (_prefs.getStringList(_indexKey) ?? [])
      ..remove(key)
      ..add(key);
    while (index.length > maxEntries) {
      await _prefs.remove('$_prefix${index.removeAt(0)}');
    }
    await _prefs.setStringList(_indexKey, index);
  }
}
