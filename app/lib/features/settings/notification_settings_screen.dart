import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/favorites.dart';
import '../../data/models.dart';
import '../../l10n/strings.dart';
import '../../notifications/notification_settings.dart';
import '../../notifications/notifications_controller.dart';
import '../../notifications/push_service.dart';
import '../../widgets/team_crest.dart';

/// Match alerts on/off, quiet hours, and which alerts each followed team sends.
/// Every change is saved on the device and synced to the backend.
class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final settings = ref.watch(notificationSettingsProvider);
    final notifier = ref.read(notificationSettingsProvider.notifier);
    final favorites = ref.watch(favoritesProvider);
    final favoritesNotifier = ref.read(favoritesProvider.notifier);
    final push = ref.watch(pushServiceProvider);
    final permission = ref.watch(pushPermissionProvider);
    final quiet = settings.quietHours;
    String fmt(LocalTime t) => TimeOfDay(hour: t.hour, minute: t.minute).format(context);

    Future<void> pickTime({required bool start}) async {
      final current = start ? quiet.start : quiet.end;
      final picked = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
      );
      if (picked == null) return;
      final t = LocalTime(picked.hour, picked.minute);
      await notifier.setQuietHours(start ? quiet.copyWith(start: t) : quiet.copyWith(end: t));
    }

    return Scaffold(
      appBar: AppBar(title: Text(s.notificationSettings)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (!push.available)
            _Banner(text: s.pushUnavailable)
          else if (permission != PushPermission.granted)
            _Banner(
              text: permission == PushPermission.denied ? '${s.permissionOff} ${s.permissionHelp}' : s.permissionOff,
              action: TextButton(
                onPressed: () => ref.read(notificationsControllerProvider).requestPermission(),
                child: Text(s.turnOn),
              ),
            ),
          SwitchListTile(
            title: Text(s.matchAlerts),
            subtitle: Text(s.matchAlertsSubtitle),
            value: settings.enabled,
            onChanged: notifier.setEnabled,
          ),
          SwitchListTile(
            title: Text(s.quietHours),
            subtitle: Text(quiet.enabled ? s.quietHoursOn(fmt(quiet.start), fmt(quiet.end)) : s.quietHoursOff),
            value: quiet.enabled,
            onChanged: settings.enabled ? (v) => notifier.setQuietHours(quiet.copyWith(enabled: v)) : null,
          ),
          if (quiet.enabled) ...[
            ListTile(
              contentPadding: const EdgeInsetsDirectional.only(start: 32, end: 24),
              title: Text(s.quietFrom),
              trailing: Text(fmt(quiet.start), style: theme.textTheme.titleMedium),
              onTap: settings.enabled ? () => pickTime(start: true) : null,
            ),
            ListTile(
              contentPadding: const EdgeInsetsDirectional.only(start: 32, end: 24),
              title: Text(s.quietUntil),
              trailing: Text(fmt(quiet.end), style: theme.textTheme.titleMedium),
              onTap: settings.enabled ? () => pickTime(start: false) : null,
            ),
          ],
          const Divider(height: 32),
          Semantics(
            header: true,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(s.followedTeams, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ),
          ),
          if (favorites.isEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                s.noFollowedTeams,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: TextButton.icon(
                  onPressed: () => context.push('/teams'),
                  icon: const Icon(Icons.search),
                  label: Text(s.findTeams),
                ),
              ),
            ),
          ],
          for (final id in favorites)
            _TeamAlerts(
              team: favoritesNotifier.info(id) ?? Team(id: id, name: s.teamFallback(id)),
              settings: settings,
              onChanged: settings.enabled ? (type, on) => notifier.setAlert(id, type, on) : null,
              onUnfollow: () => favoritesNotifier.toggle(favoritesNotifier.info(id) ?? Team(id: id, name: '')),
            ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 8, 12),
      decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(Icons.notifications_off_outlined, color: scheme.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: TextStyle(color: scheme.onErrorContainer))),
          if (action != null) action!,
        ],
      ),
    );
  }
}

class _TeamAlerts extends StatelessWidget {
  const _TeamAlerts({required this.team, required this.settings, required this.onChanged, required this.onUnfollow});

  final Team team;
  final NotificationSettings settings;

  /// Null when match alerts are off as a whole.
  final void Function(AlertType type, bool on)? onChanged;
  final VoidCallback onUnfollow;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final onCount = AlertType.values.where((t) => settings.isOn(team.id, t)).length;
    return ExpansionTile(
      leading: TeamCrest(url: team.crestUrl, fallback: team.tla ?? team.displayName, size: 32),
      title: Text(team.name),
      subtitle: Text(s.alertsOnCount(onCount, AlertType.values.length)),
      children: [
        for (final type in AlertType.values)
          SwitchListTile(
            contentPadding: const EdgeInsetsDirectional.only(start: 32, end: 24),
            title: Text(s.alertName(type.name)),
            value: settings.isOn(team.id, type),
            onChanged: onChanged == null ? null : (on) => onChanged!(type, on),
          ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextButton.icon(
              onPressed: onUnfollow,
              icon: const Icon(Icons.star_rounded),
              label: Text(s.unfollow(team.name)),
            ),
          ),
        ),
      ],
    );
  }
}
