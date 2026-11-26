import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

/// The alert types a followed team can send, in display order. Names match the
/// backend's `NotificationPrefs` fields.
enum AlertType {
  startingSoon('starting_soon'),
  kickoff('kickoff'),
  goals('goals'),
  redCards('red_cards'),
  halfTime('half_time'),
  fullTime('full_time'),
  varDecision('var');

  const AlertType(this.apiName);

  final String apiName;
}

/// Local time of day as minutes since midnight, sent as "HH:MM".
class LocalTime {
  const LocalTime(this.hour, this.minute);

  final int hour;
  final int minute;

  String get hhmm => '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  static LocalTime? parse(Object? raw) {
    if (raw is! String) return null;
    final parts = raw.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]), m = int.tryParse(parts[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) return null;
    return LocalTime(h, m);
  }

  @override
  bool operator ==(Object other) => other is LocalTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => hour * 60 + minute;
}

class QuietHours {
  const QuietHours({this.enabled = false, this.start = const LocalTime(22, 0), this.end = const LocalTime(7, 0)});

  final bool enabled;
  final LocalTime start;

  /// May be earlier than [start]: the window wraps past midnight. Enforced by the
  /// backend in the device's timezone, so it keeps working when the app is closed.
  final LocalTime end;

  QuietHours copyWith({bool? enabled, LocalTime? start, LocalTime? end}) =>
      QuietHours(enabled: enabled ?? this.enabled, start: start ?? this.start, end: end ?? this.end);

  Map<String, dynamic> toJson() => {'enabled': enabled, 'start': start.hhmm, 'end': end.hhmm};

  factory QuietHours.fromJson(Map<String, dynamic> j) => QuietHours(
        enabled: j['enabled'] as bool? ?? false,
        start: LocalTime.parse(j['start']) ?? const LocalTime(22, 0),
        end: LocalTime.parse(j['end']) ?? const LocalTime(7, 0),
      );
}

/// What the user wants to be notified about. Every alert is on by default for a
/// newly followed team; only switched-off alerts are stored.
class NotificationSettings {
  const NotificationSettings({this.enabled = true, this.quietHours = const QuietHours(), this.disabled = const {}});

  /// The in-app master switch (the OS permission is tracked separately).
  final bool enabled;
  final QuietHours quietHours;

  /// team id -> alert types switched off for that team.
  final Map<int, Set<AlertType>> disabled;

  bool isOn(int teamId, AlertType type) => !(disabled[teamId]?.contains(type) ?? false);

  /// Alerts for one team in the backend's shape: {"goals": true, ...}.
  Map<String, bool> alertsJson(int teamId) => {for (final t in AlertType.values) t.apiName: isOn(teamId, t)};

  NotificationSettings copyWith({bool? enabled, QuietHours? quietHours, Map<int, Set<AlertType>>? disabled}) =>
      NotificationSettings(
        enabled: enabled ?? this.enabled,
        quietHours: quietHours ?? this.quietHours,
        disabled: disabled ?? this.disabled,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'quiet_hours': quietHours.toJson(),
        'disabled': {
          for (final e in disabled.entries)
            if (e.value.isNotEmpty) '${e.key}': [for (final t in e.value) t.apiName],
        },
      };

  factory NotificationSettings.fromJson(Map<String, dynamic> j) {
    final byApiName = {for (final t in AlertType.values) t.apiName: t};
    final disabled = <int, Set<AlertType>>{};
    ((j['disabled'] as Map<String, dynamic>?) ?? const {}).forEach((team, types) {
      final id = int.tryParse(team);
      if (id == null || types is! List) return;
      disabled[id] = {for (final name in types) if (byApiName[name] != null) byApiName[name]!};
    });
    return NotificationSettings(
      enabled: j['enabled'] as bool? ?? true,
      quietHours: QuietHours.fromJson((j['quiet_hours'] as Map<String, dynamic>?) ?? const {}),
      disabled: disabled,
    );
  }
}

class NotificationSettingsNotifier extends Notifier<NotificationSettings> {
  static const _key = 'notification_settings';

  @override
  NotificationSettings build() {
    final raw = ref.watch(sharedPrefsProvider).getString(_key);
    if (raw == null) return const NotificationSettings();
    try {
      return NotificationSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const NotificationSettings();
    }
  }

  Future<void> setEnabled(bool enabled) => _save(state.copyWith(enabled: enabled));

  Future<void> setQuietHours(QuietHours quietHours) => _save(state.copyWith(quietHours: quietHours));

  Future<void> setAlert(int teamId, AlertType type, bool on) {
    final current = {...?state.disabled[teamId]};
    on ? current.remove(type) : current.add(type);
    return _save(state.copyWith(disabled: {...state.disabled, teamId: current}));
  }

  Future<void> _save(NotificationSettings next) async {
    state = next;
    await ref.read(sharedPrefsProvider).setString(_key, jsonEncode(next.toJson()));
  }
}

final notificationSettingsProvider =
    NotifierProvider<NotificationSettingsNotifier, NotificationSettings>(NotificationSettingsNotifier.new);
