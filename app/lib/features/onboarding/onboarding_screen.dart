import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/favorites.dart';
import '../../l10n/strings.dart';
import '../../notifications/notifications_controller.dart';
import '../settings/app_settings.dart';
import '../teams/team_picker.dart';
import 'onboarding_state.dart';

enum _Step { welcome, teams, alerts }

/// First launch: welcome (with language choice), pick teams, then an explanation
/// before the system notification prompt. Every step can be skipped.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, required this.onDone});

  /// Called once onboarding is saved as done (the app then shows the home screen).
  final VoidCallback onDone;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  _Step _step = _Step.welcome;

  Future<void> _finish() async {
    await ref.read(onboardingDoneProvider.notifier).complete();
    if (mounted) widget.onDone();
  }

  void _afterTeams() {
    final picked = ref.read(favoritesProvider).isNotEmpty;
    if (picked && ref.read(notificationsControllerProvider).shouldOfferPermission) {
      setState(() => _step = _Step.alerts);
    } else {
      _finish();
    }
  }

  Future<void> _allowAlerts() async {
    await ref.read(notificationsControllerProvider).requestPermission();
    await _finish();
  }

  Future<void> _notNow() async {
    await ref.read(notificationsControllerProvider).declinePermissionOffer();
    await _finish();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final page = switch (_step) {
      _Step.welcome => _WelcomePage(onNext: () => setState(() => _step = _Step.teams)),
      _Step.teams => _TeamsPage(onNext: _afterTeams),
      _Step.alerts => _AlertsPage(onAllow: _allowAlerts, onNotNow: _notNow),
    };

    return PopScope(
      // System back goes to the previous step rather than leaving the app.
      canPop: _step == _Step.welcome,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _step = _Step.values[_step.index - 1]);
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: _step == _Step.welcome
              ? null
              : BackButton(onPressed: () => setState(() => _step = _Step.values[_step.index - 1])),
          actions: [
            if (_step != _Step.alerts) TextButton(onPressed: _finish, child: Text(s.skip)),
          ],
        ),
        body: SafeArea(top: false, child: page),
      ),
    );
  }
}

class _WelcomePage extends ConsumerWidget {
  const _WelcomePage({required this.onNext});

  final VoidCallback onNext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final language = ref.watch(appSettingsProvider).languageCode;
    final settings = ref.read(appSettingsProvider.notifier);

    return _PageLayout(
      button: FilledButton(onPressed: onNext, child: Text(s.getStarted)),
      children: [
        Image.asset('assets/brand/mark_green.png', width: 88, height: 88, excludeFromSemantics: true),
        const SizedBox(height: 8),
        Text(
          s.appTitle,
          style: theme.textTheme.titleLarge?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 16),
        Text(s.welcomeTitle, textAlign: TextAlign.center, style: theme.textTheme.headlineMedium),
        const SizedBox(height: 12),
        Text(s.welcomeBody, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
        const SizedBox(height: 32),
        Semantics(
          header: true,
          child: Text(s.language, style: theme.textTheme.titleSmall),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: Text(s.phoneLanguage),
              selected: language == null,
              onSelected: (_) => settings.setLanguage(null),
            ),
            for (final e in languageNames.entries)
              ChoiceChip(
                label: Text(e.value),
                selected: language == e.key,
                onSelected: (_) => settings.setLanguage(e.key),
              ),
          ],
        ),
      ],
    );
  }
}

class _TeamsPage extends ConsumerWidget {
  const _TeamsPage({required this.onNext});

  final VoidCallback onNext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final count = ref.watch(favoritesProvider).length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
          child: Text(s.pickTeamsTitle, textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text(
            s.pickTeamsBody,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        // The followed list would repeat the rows being tapped: this page shows a count instead.
        const Expanded(child: TeamPicker(showFollowed: false)),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onNext,
              child: Text(count == 0 ? s.skipForNow : s.continueWithTeams(count)),
            ),
          ),
        ),
      ],
    );
  }
}

class _AlertsPage extends StatelessWidget {
  const _AlertsPage({required this.onAllow, required this.onNotNow});

  final VoidCallback onAllow;
  final VoidCallback onNotNow;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    return _PageLayout(
      button: FilledButton(onPressed: onAllow, child: Text(s.allowAlerts)),
      secondary: TextButton(onPressed: onNotNow, child: Text(s.notNow)),
      children: [
        Icon(Icons.notifications_active_outlined, size: 72, color: theme.colorScheme.primary),
        const SizedBox(height: 24),
        Text(s.alertsTitle, textAlign: TextAlign.center, style: theme.textTheme.headlineMedium),
        const SizedBox(height: 12),
        Text(s.alertsBody, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
      ],
    );
  }
}

/// Centered content that scrolls with large fonts, with the buttons pinned at the bottom.
class _PageLayout extends StatelessWidget {
  const _PageLayout({required this.children, required this.button, this.secondary});

  final List<Widget> children;
  final Widget button;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(mainAxisSize: MainAxisSize.min, children: children),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: Column(
            children: [
              SizedBox(width: double.infinity, child: button),
              if (secondary != null) SizedBox(width: double.infinity, child: secondary),
            ],
          ),
        ),
      ],
    );
  }
}
