import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../ads/ads_controller.dart';
import '../../config.dart';

import '../../data/favorites.dart';
import '../../l10n/strings.dart';
import '../../notifications/notification_settings.dart';
import '../../notifications/notifications_controller.dart';
import '../../notifications/push_service.dart';
import 'app_settings.dart';

/// Theme, language, links to notification settings and followed teams, and privacy.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final app = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);
    final teamCount = ref.watch(favoritesProvider).length;
    final alertsOn = ref.watch(notificationSettingsProvider).enabled &&
        ref.watch(pushPermissionProvider) == PushPermission.granted &&
        ref.watch(pushServiceProvider).available;
    final privacyChoices = ref.watch(adsControllerProvider.select((a) => a.privacyOptionsRequired));
    const policyUrl = AppConfig.privacyPolicyUrl;

    Widget header(String text) => Semantics(
          header: true,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(text, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: Text(s.settings)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          ListTile(
            leading: const Icon(Icons.star_outline_rounded),
            title: Text(s.followedTeams),
            subtitle: Text(s.teamCount(teamCount)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/teams'),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: Text(s.notificationSettings),
            subtitle: Text(alertsOn ? s.alertsOnSummary : s.alertsOffSummary),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/notifications'),
          ),
          header(s.appearance),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<ThemeMode>(
              segments: [
                for (final (mode, icon, label) in [
                  (ThemeMode.system, Icons.brightness_auto, s.themeSystem),
                  (ThemeMode.light, Icons.light_mode, s.themeLight),
                  (ThemeMode.dark, Icons.dark_mode, s.themeDark),
                ])
                  ButtonSegment(value: mode, icon: Icon(icon), label: Text(label)),
              ],
              selected: {app.themeMode},
              onSelectionChanged: (v) => notifier.setThemeMode(v.single),
            ),
          ),
          header(s.language),
          _LanguageTile(label: s.phoneLanguage, code: null, selected: app.languageCode, onSelect: notifier.setLanguage),
          for (final e in languageNames.entries)
            _LanguageTile(label: e.value, code: e.key, selected: app.languageCode, onSelect: notifier.setLanguage),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              s.languageAlertsNote,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          if (privacyChoices || policyUrl.isNotEmpty) header(s.privacySection),
          // Required wherever the consent message is shown (EEA, UK, ...): lets people change their answer.
          if (privacyChoices)
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: Text(s.privacyChoices),
              subtitle: Text(s.privacyChoicesSubtitle),
              onTap: () => ref.read(adsControllerProvider.notifier).showPrivacyOptions(),
            ),
          if (policyUrl.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(s.privacyPolicy),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => launchUrl(Uri.parse(policyUrl), mode: LaunchMode.inAppBrowserView),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
            child: Text(
              s.dataSource,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// A radio row. Written out rather than RadioListTile, whose group API changed in
/// recent Flutter versions.
class _LanguageTile extends StatelessWidget {
  const _LanguageTile({required this.label, required this.code, required this.selected, required this.onSelect});

  final String label;
  final String? code;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    final isSelected = code == selected;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: isSelected,
      child: ListTile(
        // Each name is shown in its own script; tell screen readers which language it is in.
        title: code == null ? Text(label) : Text(label, locale: Locale(code!)),
        trailing: isSelected ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary) : null,
        selected: isSelected,
        onTap: () => onSelect(code),
      ),
    );
  }
}
