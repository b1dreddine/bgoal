import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'data/models.dart';
import 'features/home/home_screen.dart';
import 'features/match/match_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/onboarding/onboarding_state.dart';
import 'features/settings/app_settings.dart';
import 'features/settings/notification_settings_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/team/team_screen.dart';
import 'features/teams/teams_screen.dart';
import 'l10n/strings.dart';
import 'notifications/notifications_controller.dart';
import 'notifications/push_links.dart';
import 'theme.dart';

/// [onboardingDone] is read on each navigation, so finishing onboarding and then
/// going to '/' lands on the home screen.
GoRouter buildRouter({required bool Function() onboardingDone}) => GoRouter(
      redirect: (context, state) {
        // bgoal://match/<id> links opened from outside the app (notification taps
        // are handled by NotificationsController and don't go through here).
        final link = deepLinkRedirect(state.uri);
        if (link != null) return link;
        // Only the start screen is gated: a link straight to a match still opens it.
        if (state.uri.path == '/' && !onboardingDone()) return '/onboarding';
        return null;
      },
      routes: [
        GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
        GoRoute(
          path: '/onboarding',
          builder: (context, state) => OnboardingScreen(onDone: () => context.go('/')),
        ),
        GoRoute(
          path: '/match/:id',
          builder: (context, state) {
            final id = int.tryParse(state.pathParameters['id'] ?? '');
            if (id == null) return const MatchNotFoundScreen();
            final extra = state.extra;
            return MatchScreen(matchId: id, preview: extra is FootballMatch && extra.id == id ? extra : null);
          },
        ),
        GoRoute(
          path: '/team/:id',
          builder: (context, state) {
            final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
            final extra = state.extra;
            return TeamScreen(teamId: id, preview: extra is Team && extra.id == id ? extra : null);
          },
        ),
        GoRoute(path: '/teams', builder: (context, state) => const TeamsScreen()),
        GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
        GoRoute(path: '/settings/notifications', builder: (context, state) => const NotificationSettingsScreen()),
      ],
    );

class BGoalApp extends ConsumerStatefulWidget {
  const BGoalApp({super.key});

  @override
  ConsumerState<BGoalApp> createState() => _BGoalAppState();
}

class _BGoalAppState extends ConsumerState<BGoalApp> {
  late final GoRouter _router = buildRouter(onboardingDone: () => ref.read(onboardingDoneProvider));

  @override
  void initState() {
    super.initState();
    // After the first frame so the router is ready for a notification that launched the app.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notificationsControllerProvider).start(openMatch: (id) => _router.push('/match/$id'));
    });
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    return MaterialApp.router(
      onGenerateTitle: (context) => S.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: settings.themeMode,
      // Null follows the phone's language list (falling back to English).
      locale: settings.locale,
      supportedLocales: S.supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate, // RTL layout for Arabic
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: _router,
    );
  }
}
