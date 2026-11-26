import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../providers.dart';

/// Each language in its own script, so it's recognisable whatever the current language.
const languageNames = {'en': 'English', 'fr': 'Français', 'ar': 'العربية'};

/// Theme and language chosen in Settings. Null language = follow the phone.
class AppSettings {
  const AppSettings({this.themeMode = ThemeMode.system, this.languageCode});

  final ThemeMode themeMode;
  final String? languageCode;

  /// Null lets MaterialApp pick from the phone's languages.
  Locale? get locale => languageCode == null ? null : Locale(languageCode!);

  Map<String, dynamic> toJson() => {'theme': themeMode.name, 'language': languageCode};

  factory AppSettings.fromJson(Map<String, dynamic> j) {
    final lang = j['language'] as String?;
    return AppSettings(
      themeMode: ThemeMode.values.asNameMap()[j['theme']] ?? ThemeMode.system,
      languageCode: S.supportedLocales.any((l) => l.languageCode == lang) ? lang : null,
    );
  }
}

class AppSettingsNotifier extends Notifier<AppSettings> {
  static const _key = 'app_settings';

  @override
  AppSettings build() {
    final raw = ref.watch(sharedPrefsProvider).getString(_key);
    if (raw == null) return const AppSettings();
    try {
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> setThemeMode(ThemeMode mode) => _save(AppSettings(themeMode: mode, languageCode: state.languageCode));

  /// Null = phone language.
  Future<void> setLanguage(String? code) => _save(AppSettings(themeMode: state.themeMode, languageCode: code));

  Future<void> _save(AppSettings next) async {
    state = next;
    await ref.read(sharedPrefsProvider).setString(_key, jsonEncode(next.toJson()));
  }
}

final appSettingsProvider = NotifierProvider<AppSettingsNotifier, AppSettings>(AppSettingsNotifier.new);
