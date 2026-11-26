import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/api_client.dart';
import 'notification_settings.dart';
import 'secret_store.dart';

/// Body for POST /devices and PUT /devices/{id}/preferences (pure, unit-tested).
///
/// [notificationsEnabled] is the in-app switch AND the OS permission, so the backend
/// doesn't spend pushes on a device that can't show them.
Map<String, dynamic> devicePayload({
  required String? fcmToken,
  required String language,
  required String timezone,
  required bool notificationsEnabled,
  required NotificationSettings settings,
  required List<int> favoriteTeamIds,
}) =>
    {
      'fcm_token': fcmToken ?? '',
      'language': language,
      'timezone': timezone,
      'notifications_enabled': notificationsEnabled,
      'quiet_hours': settings.quietHours.toJson(),
      'favorite_teams': [
        for (final id in favoriteTeamIds) {'team_id': id, 'notifications': settings.alertsJson(id)},
      ],
    };

/// Keeps the backend's copy of this device up to date.
///
/// Registers on first use (anonymous device id + secret), then sends the full state
/// whenever it changes. Calls are serialized and only the latest state is sent; a
/// failed sync is retried on the next call, so being offline loses nothing.
class DeviceSync {
  DeviceSync({required ApiClient api, required SharedPreferences prefs, required SecretStore secrets, required this.platform})
      : _api = api,
        _prefs = prefs,
        _secrets = secrets;

  final ApiClient _api;
  final SharedPreferences _prefs;
  final SecretStore _secrets;

  /// "ios" or "android".
  final String platform;

  static const _idKey = 'device_id';
  static const _secretKey = 'device_secret';
  static const _syncedKey = 'device_synced_payload';

  Future<void>? _running;
  Map<String, dynamic>? _pending;

  String? get deviceId => _prefs.getString(_idKey);

  /// Sends [payload] unless the backend already has exactly this. Completes when the
  /// latest requested state has been sent (or has failed; errors are rethrown).
  Future<void> sync(Map<String, dynamic> payload) {
    _pending = payload;
    return _running ??= _drain().whenComplete(() => _running = null);
  }

  Future<void> _drain() async {
    while (_pending != null) {
      final payload = _pending!;
      _pending = null;
      await _send(payload);
    }
  }

  Future<void> _send(Map<String, dynamic> payload) async {
    final encoded = jsonEncode(payload);
    final id = _prefs.getString(_idKey);
    final secret = await _secrets.read(_secretKey);
    if (id != null && secret != null) {
      if (_prefs.getString(_syncedKey) == encoded) return;
      try {
        await _api.sendJson('PUT', '/devices/$id/preferences', payload, headers: {'Authorization': 'Bearer $secret'});
        await _prefs.setString(_syncedKey, encoded);
        return;
      } on ApiException catch (e) {
        // 404: the backend forgot us (database reset) or the secret was lost on a
        // restore. Start over with a fresh registration.
        if (e.statusCode != 404) rethrow;
      }
    }
    final res = await _api.sendJson('POST', '/devices', {...payload, 'platform': platform});
    await _secrets.write(_secretKey, res['secret'] as String);
    await _prefs.setString(_idKey, res['id'] as String);
    await _prefs.setString(_syncedKey, encoded);
  }
}
