import 'package:flutter/widgets.dart';

/// App strings for English, French and Arabic (RTL is handled by Flutter from the locale).
///
/// Kept as plain maps rather than generated ARB code so the project builds with no
/// code-generation step. Placeholders use `{name}`.
class S {
  S(this.languageCode);

  final String languageCode;

  static const supportedLocales = [Locale('en'), Locale('fr'), Locale('ar')];

  static S of(BuildContext context) {
    final code = Localizations.localeOf(context).languageCode;
    return S(_strings.containsKey(code) ? code : 'en');
  }

  String _t(String key, [Map<String, Object?> args = const {}]) {
    var text = _strings[languageCode]![key] ?? _strings['en']![key] ?? key;
    args.forEach((k, v) => text = text.replaceAll('{$k}', '$v'));
    return text;
  }

  String get appTitle => _t('appTitle');
  String get today => _t('today');
  String get yesterday => _t('yesterday');
  String get tomorrow => _t('tomorrow');
  String get pickDate => _t('pickDate');
  String get yourTeams => _t('yourTeams');
  String get liveBadge => _t('liveBadge');
  String get noMatches => _t('noMatches');
  String get errorLoading => _t('errorLoading');
  String get retry => _t('retry');
  String updatedAt(String time) => _t('updatedAt', {'time': time});
  String offline(String time) => _t('offline', {'time': time});
  String follow(String team) => _t('follow', {'team': team});
  String unfollow(String team) => _t('unfollow', {'team': team});

  // Notification settings
  String get notificationSettings => _t('notificationSettings');
  String get pushUnavailable => _t('pushUnavailable');
  String get permissionOff => _t('permissionOff');
  String get permissionHelp => _t('permissionHelp');
  String get turnOn => _t('turnOn');
  String get matchAlerts => _t('matchAlerts');
  String get matchAlertsSubtitle => _t('matchAlertsSubtitle');
  String get quietHours => _t('quietHours');
  String quietHoursOn(String start, String end) => _t('quietHoursOn', {'start': start, 'end': end});
  String get quietHoursOff => _t('quietHoursOff');
  String get quietFrom => _t('quietFrom');
  String get quietUntil => _t('quietUntil');
  String get followedTeams => _t('followedTeams');
  String get noFollowedTeams => _t('noFollowedTeams');
  String teamFallback(int id) => _t('teamFallback', {'id': id});
  String alertsOnCount(int on, int total) => _t('alertsOnCount', {'on': on, 'total': total});

  /// [key] is an `AlertType.name`.
  String alertName(String key) => _t('alert_$key');

  // Match screen
  String get followTeams => _t('followTeams');
  String get tabTimeline => _t('tabTimeline');
  String get tabLineups => _t('tabLineups');
  String get tabStats => _t('tabStats');
  String get markerKickOff => _t('markerKickOff');
  String get markerHalfTime => _t('markerHalfTime');
  String get markerFullTime => _t('markerFullTime');
  String get markerAet => _t('markerAet');
  String get markerPenalties => _t('markerPenalties');
  String get noEventsYet => _t('noEventsYet');
  String get noEventData => _t('noEventData');
  String get notStarted => _t('notStarted');
  String get lineupsSoon => _t('lineupsSoon');
  String get noLineups => _t('noLineups');
  String get statsSoon => _t('statsSoon');
  String get noStats => _t('noStats');
  String get substitutes => _t('substitutes');
  String coach(String name) => _t('coach', {'name': name});
  String get matchNotFound => _t('matchNotFound');
  String get errorLoadingMatch => _t('errorLoadingMatch');
  String htScore(int h, int a) => _t('htScore', {'h': h, 'a': a});
  String pensScore(int h, int a) => _t('pensScore', {'h': h, 'a': a});
  String get ownGoalTag => _t('ownGoalTag');
  String get penaltyTag => _t('penaltyTag');
  String assist(String name) => _t('assist', {'name': name});

  /// [key] is an `EventType.name` / `StatKind.name`.
  String eventName(String key) => _t('event_$key');
  String statName(String key) => _t('stat_$key');

  String semEvent(String minute, String what, String team, String? detail) =>
      [_t('semMinute', {'minute': minute}), what, team, if (detail != null && detail.isNotEmpty) detail].join(', ');
  String semSubstitution(String on, String off) => _t('semSub', {'on': on, 'off': off});
  String semStat(String label, String home, String hv, String away, String av) =>
      _t('semStat', {'label': label, 'home': home, 'hv': hv, 'away': away, 'av': av});
  String semPlayer(int? number, String name) => number == null ? name : _t('semPlayer', {'n': number, 'name': name});
  String get semSubbedOn => _t('semSubbedOn');
  String get semSubbedOff => _t('semSubbedOff');

  // Onboarding
  String get skip => _t('skip');
  String get getStarted => _t('getStarted');
  String get welcomeTitle => _t('welcomeTitle');
  String get welcomeBody => _t('welcomeBody');
  String get pickTeamsTitle => _t('pickTeamsTitle');
  String get pickTeamsBody => _t('pickTeamsBody');
  String get skipForNow => _t('skipForNow');
  String continueWithTeams(int n) => _t('continueWithTeams', {'n': n});
  String get alertsTitle => _t('alertsTitle');
  String get alertsBody => _t('alertsBody');
  String get allowAlerts => _t('allowAlerts');
  String get notNow => _t('notNow');

  // Teams
  String get teams => _t('teams');
  String get searchTeams => _t('searchTeams');
  String get searchTeamsHint => _t('searchTeamsHint');
  String get clearSearch => _t('clearSearch');
  String noTeamsFound(String q) => _t('noTeamsFound', {'q': q});
  String get errorLoadingTeams => _t('errorLoadingTeams');
  String get findTeams => _t('findTeams');
  String teamPage(String team) => _t('teamPage', {'team': team});
  String get teamNotFound => _t('teamNotFound');
  String get errorLoadingTeam => _t('errorLoadingTeam');
  String get followButton => _t('followButton');
  String get following => _t('following');
  String get nextMatches => _t('nextMatches');
  String get noUpcomingMatches => _t('noUpcomingMatches');
  String get recentResults => _t('recentResults');
  String get noRecentResults => _t('noRecentResults');
  String standingPosition(int pos, String competition) =>
      _t(pos == 1 ? 'standingFirst' : 'standingPosition', {'pos': pos, 'competition': competition});
  String semStanding(int pos, String competition, int pts, int p, int w, int d, int l) => _t(
      'semStanding', {'pos': pos, 'competition': competition, 'pts': pts, 'p': p, 'w': w, 'd': d, 'l': l});
  String get tablePlayed => _t('tablePlayed');
  String get tableWon => _t('tableWon');
  String get tableDrawn => _t('tableDrawn');
  String get tableLost => _t('tableLost');
  String get tableGoalDiff => _t('tableGoalDiff');
  String get tablePoints => _t('tablePoints');
  String get formWin => _t('formWin');
  String get formDraw => _t('formDraw');
  String get formLoss => _t('formLoss');

  // Settings
  String get settings => _t('settings');
  String teamCount(int n) => _t(switch (n) { 0 => 'teamCountZero', 1 => 'teamCountOne', _ => 'teamCount' }, {'n': n});
  String get alertsOnSummary => _t('alertsOnSummary');
  String get alertsOffSummary => _t('alertsOffSummary');
  String get appearance => _t('appearance');
  String get themeSystem => _t('themeSystem');
  String get themeLight => _t('themeLight');
  String get themeDark => _t('themeDark');
  String get language => _t('language');
  String get phoneLanguage => _t('phoneLanguage');
  String get languageAlertsNote => _t('languageAlertsNote');
  String get privacySection => _t('privacySection');
  String get privacyChoices => _t('privacyChoices');
  String get privacyChoicesSubtitle => _t('privacyChoicesSubtitle');
  String get privacyPolicy => _t('privacyPolicy');
  String get dataSource => _t('dataSource');

  // Ads
  String get advertisement => _t('advertisement');

  // Short status labels shown in match cards
  String get statusHalfTime => _t('statusHT');
  String get statusFullTime => _t('statusFT');
  String get statusAet => _t('statusAET');
  String get statusPens => _t('statusPens');
  String get statusPostponed => _t('statusPST');
  String get statusSuspended => _t('statusSUSP');
  String get statusAbandoned => _t('statusABD');
  String get statusCancelled => _t('statusCANC');
  String get statusExtraTime => _t('statusET');
  String get statusPenaltiesLive => _t('statusPenLive');

  // Screen-reader phrases
  String semScore(String home, int homeGoals, String away, int awayGoals) =>
      _t('semScore', {'home': home, 'hs': homeGoals, 'away': away, 'as': awayGoals});
  String semVersus(String home, String away) => _t('semVersus', {'home': home, 'away': away});
  String semMinute(String minute) => _t('semMinute', {'minute': minute});
  String semKickoff(String time) => _t('semKickoff', {'time': time});
  String semPenalties(int h, int a) => _t('semPenalties', {'h': h, 'a': a});
  String get semHalfTime => _t('semHalfTime');
  String get semFullTime => _t('semFullTime');
  String get semPostponed => _t('semPostponed');
  String get semSuspended => _t('semSuspended');
  String get semAbandoned => _t('semAbandoned');
  String get semCancelled => _t('semCancelled');
  String get semFollowed => _t('semFollowed');
  String get semOpenHint => _t('semOpenHint');
}

const Map<String, Map<String, String>> _strings = {
  'en': {
    'appTitle': 'BGoal',
    'today': 'Today',
    'yesterday': 'Yesterday',
    'tomorrow': 'Tomorrow',
    'pickDate': 'Pick a date',
    'yourTeams': 'Your teams',
    'liveBadge': 'LIVE',
    'noMatches': 'No matches on this day',
    'errorLoading': "Couldn't load matches. Check your connection.",
    'retry': 'Retry',
    'updatedAt': 'Updated {time}',
    'offline': 'Offline · last updated {time}',
    'follow': 'Follow {team}',
    'unfollow': 'Unfollow {team}',
    'notificationSettings': 'Notifications',
    'pushUnavailable': "Notifications aren't set up in this build of the app.",
    'permissionOff': 'Notifications are turned off for this app.',
    'permissionHelp': 'You can turn them on in your phone settings.',
    'turnOn': 'Turn on',
    'matchAlerts': 'Match alerts',
    'matchAlertsSubtitle': 'Goals, cards and results for the teams you follow',
    'quietHours': 'Quiet hours',
    'quietHoursOn': 'No alerts from {start} to {end}',
    'quietHoursOff': 'Alerts at any time',
    'quietFrom': 'From',
    'quietUntil': 'Until',
    'followedTeams': 'Teams you follow',
    'noFollowedTeams': "You don't follow any teams yet.",
    'skip': 'Skip',
    'getStarted': 'Get started',
    'welcomeTitle': 'Never miss a goal',
    'welcomeBody': 'Live scores from the top leagues, and alerts the moment something happens to your teams.',
    'pickTeamsTitle': 'Pick your teams',
    'pickTeamsBody': 'Their matches are pinned to the top, and you can get alerts for them.',
    'skipForNow': 'Skip for now',
    'continueWithTeams': 'Continue ({n})',
    'alertsTitle': 'Get alerts for your teams',
    'alertsBody': 'Kick-off, goals, red cards and the final score, within seconds. You choose which ones in Settings.',
    'allowAlerts': 'Turn on alerts',
    'notNow': 'Not now',
    'teams': 'Teams',
    'searchTeams': 'Search teams',
    'searchTeamsHint': 'Type a team name to find it.',
    'clearSearch': 'Clear search',
    'noTeamsFound': 'No teams found for "{q}".',
    'errorLoadingTeams': "Couldn't load teams. Check your connection.",
    'findTeams': 'Find teams',
    'teamPage': '{team} team page',
    'teamNotFound': "This team couldn't be found.",
    'errorLoadingTeam': "Couldn't load this team. Check your connection.",
    'followButton': 'Follow',
    'following': 'Following',
    'nextMatches': 'Next matches',
    'noUpcomingMatches': 'No upcoming matches scheduled.',
    'recentResults': 'Recent results',
    'noRecentResults': 'No recent results.',
    'standingFirst': 'Position 1 · {competition}',
    'standingPosition': 'Position {pos} · {competition}',
    'semStanding': 'Position {pos} in {competition}, {pts} points, {p} played, {w} won, {d} drawn, {l} lost',
    'tablePlayed': 'P',
    'tableWon': 'W',
    'tableDrawn': 'D',
    'tableLost': 'L',
    'tableGoalDiff': 'GD',
    'tablePoints': 'Pts',
    'formWin': 'W',
    'formDraw': 'D',
    'formLoss': 'L',
    'settings': 'Settings',
    'teamCountZero': 'None yet',
    'teamCountOne': '1 team',
    'teamCount': '{n} teams',
    'alertsOnSummary': 'Match alerts on',
    'alertsOffSummary': 'Match alerts off',
    'appearance': 'Appearance',
    'themeSystem': 'System',
    'themeLight': 'Light',
    'themeDark': 'Dark',
    'language': 'Language',
    'phoneLanguage': 'Phone language',
    'languageAlertsNote': 'Notifications are sent in this language too.',
    'privacySection': 'Privacy',
    'privacyChoices': 'Privacy choices',
    'privacyChoicesSubtitle': 'Change how ads use your data',
    'privacyPolicy': 'Privacy policy',
    'dataSource': 'Match data from football-data.org',
    'advertisement': 'Advertisement',
    'teamFallback': 'Team {id}',
    'alertsOnCount': '{on} of {total} alerts on',
    'alert_startingSoon': 'Starting soon',
    'alert_kickoff': 'Kick-off',
    'alert_goals': 'Goals',
    'alert_redCards': 'Red cards',
    'alert_halfTime': 'Half-time',
    'alert_fullTime': 'Full-time',
    'alert_varDecision': 'VAR corrections',
    'followTeams': 'Follow teams',
    'tabTimeline': 'Timeline',
    'tabLineups': 'Lineups',
    'tabStats': 'Stats',
    'markerKickOff': 'Kick-off',
    'markerHalfTime': 'Half-time',
    'markerFullTime': 'Full-time',
    'markerAet': 'Full-time (after extra time)',
    'markerPenalties': 'Penalty shootout',
    'noEventsYet': 'Nothing has happened yet.',
    'noEventData': "Scorers and cards aren't available for this match.",
    'notStarted': "The match hasn't started.",
    'lineupsSoon': 'Lineups are usually announced about an hour before kick-off.',
    'noLineups': "Lineups aren't available for this match.",
    'statsSoon': 'Stats appear once the match starts.',
    'noStats': "Stats aren't available for this match.",
    'substitutes': 'Substitutes',
    'coach': 'Coach: {name}',
    'matchNotFound': "This match couldn't be found.",
    'errorLoadingMatch': "Couldn't load this match. Check your connection.",
    'htScore': 'HT {h}–{a}',
    'pensScore': 'Penalties {h}–{a}',
    'ownGoalTag': 'OG',
    'penaltyTag': 'P',
    'assist': 'Assist: {name}',
    'event_goal': 'Goal',
    'event_ownGoal': 'Own goal',
    'event_penaltyGoal': 'Penalty goal',
    'event_missedPenalty': 'Missed penalty',
    'event_yellowCard': 'Yellow card',
    'event_secondYellow': 'Second yellow card',
    'event_redCard': 'Red card',
    'event_substitution': 'Substitution',
    'event_varDecision': 'VAR decision',
    'event_unknown': 'Event',
    'stat_possession': 'Possession',
    'stat_shots': 'Shots',
    'stat_shotsOnTarget': 'Shots on target',
    'stat_corners': 'Corners',
    'stat_fouls': 'Fouls',
    'stat_yellowCards': 'Yellow cards',
    'stat_redCards': 'Red cards',
    'semSub': '{on} on, {off} off',
    'semStat': '{label}: {home} {hv}, {away} {av}',
    'semPlayer': 'number {n}, {name}',
    'semSubbedOn': 'came on',
    'semSubbedOff': 'substituted',
    'statusHT': 'HT',
    'statusFT': 'FT',
    'statusAET': 'AET',
    'statusPens': 'Pens',
    'statusPST': 'Postp.',
    'statusSUSP': 'Susp.',
    'statusABD': 'Aband.',
    'statusCANC': 'Canc.',
    'statusET': 'ET',
    'statusPenLive': 'Pens',
    'semScore': '{home} {hs}, {away} {as}',
    'semVersus': '{home} versus {away}',
    'semMinute': 'minute {minute}',
    'semKickoff': 'kick-off at {time}',
    'semPenalties': '{h} to {a} on penalties',
    'semHalfTime': 'half-time',
    'semFullTime': 'full-time',
    'semPostponed': 'postponed',
    'semSuspended': 'suspended',
    'semAbandoned': 'abandoned',
    'semCancelled': 'cancelled',
    'semFollowed': 'followed team',
    'semOpenHint': 'open match details',
  },
  'fr': {
    'appTitle': 'BGoal',
    'today': "Aujourd'hui",
    'yesterday': 'Hier',
    'tomorrow': 'Demain',
    'pickDate': 'Choisir une date',
    'yourTeams': 'Vos équipes',
    'liveBadge': 'DIRECT',
    'noMatches': 'Aucun match ce jour-là',
    'errorLoading': 'Impossible de charger les matchs. Vérifiez votre connexion.',
    'retry': 'Réessayer',
    'updatedAt': 'Mis à jour à {time}',
    'offline': 'Hors ligne · mis à jour à {time}',
    'follow': 'Suivre {team}',
    'unfollow': 'Ne plus suivre {team}',
    'notificationSettings': 'Notifications',
    'pushUnavailable': "Les notifications ne sont pas configurées dans cette version de l'app.",
    'permissionOff': 'Les notifications sont désactivées pour cette app.',
    'permissionHelp': 'Vous pouvez les activer dans les réglages du téléphone.',
    'turnOn': 'Activer',
    'matchAlerts': 'Alertes de match',
    'matchAlertsSubtitle': 'Buts, cartons et résultats de vos équipes',
    'quietHours': 'Heures calmes',
    'quietHoursOn': 'Aucune alerte de {start} à {end}',
    'quietHoursOff': 'Alertes à toute heure',
    'quietFrom': 'De',
    'quietUntil': "Jusqu'à",
    'followedTeams': 'Équipes suivies',
    'noFollowedTeams': 'Vous ne suivez encore aucune équipe.',
    'skip': 'Passer',
    'getStarted': 'Commencer',
    'welcomeTitle': 'Ne manquez plus aucun but',
    'welcomeBody': 'Les scores en direct des grands championnats, et une alerte dès qu’il se passe quelque chose pour vos équipes.',
    'pickTeamsTitle': 'Choisissez vos équipes',
    'pickTeamsBody': 'Leurs matchs sont affichés en premier, et vous pouvez recevoir des alertes.',
    'skipForNow': 'Plus tard',
    'continueWithTeams': 'Continuer ({n})',
    'alertsTitle': 'Recevez les alertes de vos équipes',
    'alertsBody': "Coup d'envoi, buts, cartons rouges et score final, en quelques secondes. Vous choisissez lesquelles dans les Réglages.",
    'allowAlerts': 'Activer les alertes',
    'notNow': 'Pas maintenant',
    'teams': 'Équipes',
    'searchTeams': 'Rechercher une équipe',
    'searchTeamsHint': "Tapez le nom d'une équipe pour la trouver.",
    'clearSearch': 'Effacer la recherche',
    'noTeamsFound': 'Aucune équipe trouvée pour « {q} ».',
    'errorLoadingTeams': 'Impossible de charger les équipes. Vérifiez votre connexion.',
    'findTeams': 'Trouver des équipes',
    'teamPage': "Page de l'équipe {team}",
    'teamNotFound': 'Cette équipe est introuvable.',
    'errorLoadingTeam': 'Impossible de charger cette équipe. Vérifiez votre connexion.',
    'followButton': 'Suivre',
    'following': 'Suivie',
    'nextMatches': 'Prochains matchs',
    'noUpcomingMatches': 'Aucun match prévu.',
    'recentResults': 'Derniers résultats',
    'noRecentResults': 'Aucun résultat récent.',
    'standingFirst': '1er · {competition}',
    'standingPosition': '{pos}e · {competition}',
    'semStanding': '{competition} : {pos}e place, {pts} points, {p} joués, {w} victoires, {d} nuls, {l} défaites',
    'tablePlayed': 'J',
    'tableWon': 'G',
    'tableDrawn': 'N',
    'tableLost': 'P',
    'tableGoalDiff': 'Diff',
    'tablePoints': 'Pts',
    'formWin': 'V',
    'formDraw': 'N',
    'formLoss': 'D',
    'settings': 'Réglages',
    'teamCountZero': 'Aucune pour le moment',
    'teamCountOne': '1 équipe',
    'teamCount': '{n} équipes',
    'alertsOnSummary': 'Alertes de match activées',
    'alertsOffSummary': 'Alertes de match désactivées',
    'appearance': 'Apparence',
    'themeSystem': 'Système',
    'themeLight': 'Clair',
    'themeDark': 'Sombre',
    'language': 'Langue',
    'phoneLanguage': 'Langue du téléphone',
    'languageAlertsNote': 'Les notifications sont aussi envoyées dans cette langue.',
    'privacySection': 'Confidentialité',
    'privacyChoices': 'Choix de confidentialité',
    'privacyChoicesSubtitle': 'Modifier l''utilisation de vos données pour la publicité',
    'privacyPolicy': 'Politique de confidentialité',
    'dataSource': 'Données des matchs : football-data.org',
    'advertisement': 'Publicité',
    'teamFallback': 'Équipe {id}',
    'alertsOnCount': '{on} alertes sur {total} activées',
    'alert_startingSoon': 'Début imminent',
    'alert_kickoff': "Coup d'envoi",
    'alert_goals': 'Buts',
    'alert_redCards': 'Cartons rouges',
    'alert_halfTime': 'Mi-temps',
    'alert_fullTime': 'Fin du match',
    'alert_varDecision': 'Corrections VAR',
    'followTeams': 'Suivre les équipes',
    'tabTimeline': 'Déroulé',
    'tabLineups': 'Compositions',
    'tabStats': 'Stats',
    'markerKickOff': "Coup d'envoi",
    'markerHalfTime': 'Mi-temps',
    'markerFullTime': 'Fin du match',
    'markerAet': 'Fin du match (après prolongation)',
    'markerPenalties': 'Séance de tirs au but',
    'noEventsYet': "Rien à signaler pour l'instant.",
    'noEventData': 'Les buteurs et les cartons ne sont pas disponibles pour ce match.',
    'notStarted': "Le match n'a pas commencé.",
    'lineupsSoon': "Les compositions sont généralement annoncées environ une heure avant le coup d'envoi.",
    'noLineups': 'Les compositions ne sont pas disponibles pour ce match.',
    'statsSoon': 'Les statistiques apparaissent dès le début du match.',
    'noStats': 'Les statistiques ne sont pas disponibles pour ce match.',
    'substitutes': 'Remplaçants',
    'coach': 'Entraîneur : {name}',
    'matchNotFound': 'Ce match est introuvable.',
    'errorLoadingMatch': 'Impossible de charger ce match. Vérifiez votre connexion.',
    'htScore': 'MT {h}–{a}',
    'pensScore': 'T.a.b. {h}–{a}',
    'ownGoalTag': 'csc',
    'penaltyTag': 'pén.',
    'assist': 'Passe : {name}',
    'event_goal': 'But',
    'event_ownGoal': 'But contre son camp',
    'event_penaltyGoal': 'But sur penalty',
    'event_missedPenalty': 'Penalty manqué',
    'event_yellowCard': 'Carton jaune',
    'event_secondYellow': 'Second carton jaune',
    'event_redCard': 'Carton rouge',
    'event_substitution': 'Remplacement',
    'event_varDecision': 'Décision VAR',
    'event_unknown': 'Événement',
    'stat_possession': 'Possession',
    'stat_shots': 'Tirs',
    'stat_shotsOnTarget': 'Tirs cadrés',
    'stat_corners': 'Corners',
    'stat_fouls': 'Fautes',
    'stat_yellowCards': 'Cartons jaunes',
    'stat_redCards': 'Cartons rouges',
    'semSub': '{on} entre, {off} sort',
    'semStat': '{label} : {home} {hv}, {away} {av}',
    'semPlayer': 'numéro {n}, {name}',
    'semSubbedOn': 'entré en jeu',
    'semSubbedOff': 'remplacé',
    'statusHT': 'MT',
    'statusFT': 'Fin',
    'statusAET': 'a.p.',
    'statusPens': 't.a.b.',
    'statusPST': 'Reporté',
    'statusSUSP': 'Susp.',
    'statusABD': 'Arrêté',
    'statusCANC': 'Annulé',
    'statusET': 'Prol.',
    'statusPenLive': 't.a.b.',
    'semScore': '{home} {hs}, {away} {as}',
    'semVersus': '{home} contre {away}',
    'semMinute': '{minute}e minute',
    'semKickoff': "coup d'envoi à {time}",
    'semPenalties': '{h} à {a} aux tirs au but',
    'semHalfTime': 'mi-temps',
    'semFullTime': 'fin du match',
    'semPostponed': 'reporté',
    'semSuspended': 'suspendu',
    'semAbandoned': 'arrêté',
    'semCancelled': 'annulé',
    'semFollowed': 'équipe suivie',
    'semOpenHint': 'ouvrir les détails du match',
  },
  'ar': {
    'appTitle': 'BGoal',
    'today': 'اليوم',
    'yesterday': 'أمس',
    'tomorrow': 'غدًا',
    'pickDate': 'اختر تاريخًا',
    'yourTeams': 'فرقك',
    'liveBadge': 'مباشر',
    'noMatches': 'لا توجد مباريات في هذا اليوم',
    'errorLoading': 'تعذّر تحميل المباريات. تحقّق من الاتصال.',
    'retry': 'إعادة المحاولة',
    'updatedAt': 'آخر تحديث {time}',
    'offline': 'غير متصل · آخر تحديث {time}',
    'follow': 'متابعة {team}',
    'unfollow': 'إلغاء متابعة {team}',
    'notificationSettings': 'الإشعارات',
    'pushUnavailable': 'الإشعارات غير مُعدّة في هذا الإصدار من التطبيق.',
    'permissionOff': 'الإشعارات متوقفة لهذا التطبيق.',
    'permissionHelp': 'يمكنك تفعيلها من إعدادات الهاتف.',
    'turnOn': 'تفعيل',
    'matchAlerts': 'تنبيهات المباريات',
    'matchAlertsSubtitle': 'الأهداف والبطاقات والنتائج للفرق التي تتابعها',
    'quietHours': 'ساعات الهدوء',
    'quietHoursOn': 'لا تنبيهات من {start} إلى {end}',
    'quietHoursOff': 'التنبيهات في أي وقت',
    'quietFrom': 'من',
    'quietUntil': 'حتى',
    'followedTeams': 'الفرق التي تتابعها',
    'noFollowedTeams': 'لا تتابع أي فريق بعد.',
    'skip': 'تخطٍّ',
    'getStarted': 'ابدأ',
    'welcomeTitle': 'لا يفوتك أي هدف',
    'welcomeBody': 'النتائج المباشرة لأكبر الدوريات، وتنبيه فور حدوث أي شيء لفرقك.',
    'pickTeamsTitle': 'اختر فرقك',
    'pickTeamsBody': 'تظهر مبارياتها في الأعلى، ويمكنك تلقّي تنبيهات بشأنها.',
    'skipForNow': 'لاحقًا',
    'continueWithTeams': 'التالي ({n})',
    'alertsTitle': 'تلقَّ تنبيهات فرقك',
    'alertsBody': 'صافرة البداية والأهداف والبطاقات الحمراء والنتيجة النهائية خلال ثوانٍ. تختار ما تريده منها في الإعدادات.',
    'allowAlerts': 'تفعيل التنبيهات',
    'notNow': 'ليس الآن',
    'teams': 'الفرق',
    'searchTeams': 'ابحث عن فريق',
    'searchTeamsHint': 'اكتب اسم فريق للعثور عليه.',
    'clearSearch': 'مسح البحث',
    'noTeamsFound': 'لم يُعثر على فرق لـ "{q}".',
    'errorLoadingTeams': 'تعذّر تحميل الفرق. تحقّق من الاتصال.',
    'findTeams': 'ابحث عن فرق',
    'teamPage': 'صفحة فريق {team}',
    'teamNotFound': 'تعذّر العثور على هذا الفريق.',
    'errorLoadingTeam': 'تعذّر تحميل هذا الفريق. تحقّق من الاتصال.',
    'followButton': 'متابعة',
    'following': 'متابَع',
    'nextMatches': 'المباريات القادمة',
    'noUpcomingMatches': 'لا مباريات مقررة.',
    'recentResults': 'آخر النتائج',
    'noRecentResults': 'لا نتائج حديثة.',
    'standingFirst': 'المركز 1 · {competition}',
    'standingPosition': 'المركز {pos} · {competition}',
    'semStanding': 'المركز {pos} في {competition}، {pts} نقطة، لعب {p}، فاز {w}، تعادل {d}، خسر {l}',
    'tablePlayed': 'لعب',
    'tableWon': 'فوز',
    'tableDrawn': 'تعادل',
    'tableLost': 'خسارة',
    'tableGoalDiff': 'الفارق',
    'tablePoints': 'نقاط',
    'formWin': 'ف',
    'formDraw': 'ت',
    'formLoss': 'خ',
    'settings': 'الإعدادات',
    'teamCountZero': 'لا شيء بعد',
    'teamCountOne': 'فريق واحد',
    'teamCount': 'عدد الفرق: {n}',
    'alertsOnSummary': 'تنبيهات المباريات مفعّلة',
    'alertsOffSummary': 'تنبيهات المباريات متوقفة',
    'appearance': 'المظهر',
    'themeSystem': 'النظام',
    'themeLight': 'فاتح',
    'themeDark': 'داكن',
    'language': 'اللغة',
    'phoneLanguage': 'لغة الهاتف',
    'languageAlertsNote': 'تُرسل الإشعارات بهذه اللغة أيضًا.',
    'privacySection': 'الخصوصية',
    'privacyChoices': 'خيارات الخصوصية',
    'privacyChoicesSubtitle': 'غيّر طريقة استخدام الإعلانات لبياناتك',
    'privacyPolicy': 'سياسة الخصوصية',
    'dataSource': 'بيانات المباريات من football-data.org',
    'advertisement': 'إعلان',
    'teamFallback': 'فريق {id}',
    'alertsOnCount': '{on} من {total} تنبيهات مفعّلة',
    'alert_startingSoon': 'قبل البداية',
    'alert_kickoff': 'صافرة البداية',
    'alert_goals': 'الأهداف',
    'alert_redCards': 'البطاقات الحمراء',
    'alert_halfTime': 'نهاية الشوط الأول',
    'alert_fullTime': 'نهاية المباراة',
    'alert_varDecision': 'تصحيحات الفيديو المساعد',
    'followTeams': 'متابعة الفرق',
    'tabTimeline': 'الأحداث',
    'tabLineups': 'التشكيلات',
    'tabStats': 'الإحصائيات',
    'markerKickOff': 'صافرة البداية',
    'markerHalfTime': 'نهاية الشوط الأول',
    'markerFullTime': 'نهاية المباراة',
    'markerAet': 'نهاية المباراة (بعد الأشواط الإضافية)',
    'markerPenalties': 'ركلات الترجيح',
    'noEventsYet': 'لا أحداث حتى الآن.',
    'noEventData': 'الهدافون والبطاقات غير متاحين لهذه المباراة.',
    'notStarted': 'لم تبدأ المباراة بعد.',
    'lineupsSoon': 'تُعلَن التشكيلات عادةً قبل ساعة تقريبًا من بداية المباراة.',
    'noLineups': 'التشكيلات غير متاحة لهذه المباراة.',
    'statsSoon': 'تظهر الإحصائيات عند بداية المباراة.',
    'noStats': 'الإحصائيات غير متاحة لهذه المباراة.',
    'substitutes': 'البدلاء',
    'coach': 'المدرب: {name}',
    'matchNotFound': 'تعذّر العثور على هذه المباراة.',
    'errorLoadingMatch': 'تعذّر تحميل هذه المباراة. تحقّق من الاتصال.',
    'htScore': 'الشوط الأول {h}–{a}',
    'pensScore': 'ركلات الترجيح {h}–{a}',
    'ownGoalTag': 'عكسي',
    'penaltyTag': 'جزاء',
    'assist': 'تمريرة حاسمة: {name}',
    'event_goal': 'هدف',
    'event_ownGoal': 'هدف عكسي',
    'event_penaltyGoal': 'هدف من ركلة جزاء',
    'event_missedPenalty': 'ركلة جزاء ضائعة',
    'event_yellowCard': 'بطاقة صفراء',
    'event_secondYellow': 'بطاقة صفراء ثانية',
    'event_redCard': 'بطاقة حمراء',
    'event_substitution': 'تبديل',
    'event_varDecision': 'قرار الفيديو المساعد',
    'event_unknown': 'حدث',
    'stat_possession': 'الاستحواذ',
    'stat_shots': 'التسديدات',
    'stat_shotsOnTarget': 'التسديدات على المرمى',
    'stat_corners': 'الركنيات',
    'stat_fouls': 'الأخطاء',
    'stat_yellowCards': 'البطاقات الصفراء',
    'stat_redCards': 'البطاقات الحمراء',
    'semSub': 'دخول {on}، خروج {off}',
    'semStat': '{label}: {home} {hv}، {away} {av}',
    'semPlayer': 'رقم {n}، {name}',
    'semSubbedOn': 'دخل بديلًا',
    'semSubbedOff': 'خرج',
    'statusHT': 'استراحة',
    'statusFT': 'انتهت',
    'statusAET': 'بعد التمديد',
    'statusPens': 'ترجيح',
    'statusPST': 'مؤجلة',
    'statusSUSP': 'معلّقة',
    'statusABD': 'أوقفت',
    'statusCANC': 'ملغاة',
    'statusET': 'تمديد',
    'statusPenLive': 'ترجيح',
    'semScore': '{home} {hs}، {away} {as}',
    'semVersus': '{home} ضد {away}',
    'semMinute': 'الدقيقة {minute}',
    'semKickoff': 'تبدأ الساعة {time}',
    'semPenalties': '{h} مقابل {a} بركلات الترجيح',
    'semHalfTime': 'استراحة بين الشوطين',
    'semFullTime': 'نهاية المباراة',
    'semPostponed': 'مؤجلة',
    'semSuspended': 'معلّقة',
    'semAbandoned': 'أوقفت',
    'semCancelled': 'ملغاة',
    'semFollowed': 'فريق متابَع',
    'semOpenHint': 'فتح تفاصيل المباراة',
  },
};
