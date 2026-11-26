# BGoal – Flutter app

## First-time setup

Requires Flutter 3.27 or newer (`flutter --version`) and Python 3.9 or newer.

The repo only contains `lib/`, `test/`, `assets/`, `tool/` and `pubspec.yaml`. Generate the native iOS and Android projects once, then let the setup script apply BGoal's settings to them:

```bash
flutter create --org com.bgoal --project-name livescores --platforms ios,android .
```

```bash
flutter pub get
```

```bash
python tool/setup_platforms.py
```

```bash
dart run flutter_launcher_icons
```

```bash
dart run flutter_native_splash:create
```

`flutter create .` only adds missing files; it doesn't overwrite `lib/` or `pubspec.yaml`. The app id becomes `com.bgoal.livescores` (see [PUBLISHING.md](../PUBLISHING.md#1-accounts-and-what-they-cost) before you pick a different one: it can never change after the first upload).

`tool/setup_platforms.py` is safe to run again and prints what it changed and what's left. It does:

- **Android:** app name BGoal; the `INTERNET` permission (`flutter create` only adds it for debug builds); `minSdk 26` (Android 8); core library desugaring (needed by `flutter_local_notifications`); the AdMob app id; `bgoal://match/<id>` links; the notification icon and colour; release signing from `android/key.properties`; plain `http://` allowed in **debug** builds only (local backend); and, once `android/app/google-services.json` exists, the Google services plugin.
- **iOS:** display name BGoal; the AdMob app id and Google's SKAdNetwork id; the tracking prompt text; `bgoal://` links; remote-notification background mode; languages (en, fr, ar); `NSAllowsLocalNetworking` for the local backend; iOS 15 minimum (Podfile and Xcode project); `ITSAppUsesNonExemptEncryption = NO`; and a `PrivacyInfo.xcprivacy`.
- Without `--admob-android-app-id` / `--admob-ios-app-id` it uses Google's test AdMob app ids. That's right for development; [PUBLISHING.md](../PUBLISHING.md#5-admob-ads) explains where the real ones come from.

Left to do by hand (the script reminds you): in Xcode, add `PrivacyInfo.xcprivacy` to the Runner target if it isn't listed, and add the **Push Notifications** and **Background Modes → Remote notifications** capabilities.

If your Flutter still generates Groovy `build.gradle` files instead of `build.gradle.kts`, the script says so; update Flutter, or apply the same settings by hand.

### Push notifications (Firebase)

The app runs without this: if Firebase isn't configured, everything works except pushes, and the notification settings screen says so. Do the Firebase project steps in the [main README](../README.md#2-firebase-project-free-spark-plan-is-enough) first. They give you `google-services.json` and `GoogleService-Info.plist`.

- **Android:** copy `google-services.json` to `android/app/`, then run `python tool/setup_platforms.py` again so it adds the Google services Gradle plugin. The Android 13+ notification permission (`POST_NOTIFICATIONS`) is added by `firebase_messaging`. The "Match events" notification channel, which the backend targets, is created at launch.
- **iOS** (needs a paid Apple Developer account, and a real iPhone: the simulator can't receive remote pushes):
  1. In Xcode, drag `GoogleService-Info.plist` into **Runner** and tick "Copy items if needed" and the Runner target.
  2. **Runner → Signing & Capabilities → + Capability**: add **Push Notifications** and **Background Modes**, then tick **Remote notifications**.
  3. Upload your APNs key to Firebase (main README, "APNs").

`flutterfire configure` also works for the Firebase files. It generates `lib/firebase_options.dart`, which this app doesn't need: it reads the native files.

### Web version (testers without the stores)

`web/` holds the page for the free web version: icons, the Home Screen settings, and a guide that shows phone users how to add BGoal to their Home Screen before the app loads. In a browser the app runs without notifications and ads. Sharing it is explained in [WEB_TESTING.md](../WEB_TESTING.md).

### Ads (AdMob)

Debug builds always use Google's **test** ad units, so you can run and tap ads freely. The real ad unit ids are passed at build time (`--dart-define-from-file=config/release.json`, see [PUBLISHING.md](../PUBLISHING.md#72-release-config)); a release build without them shows no ads in those slots. `--dart-define=ADS=false` builds without ads.

- **Where:** a banner at the bottom of Home, Match and Team; one native ad between the second and third league on Home. No ads in onboarding, Settings or the team picker.
- **Consent first:** the first time the home screen shows (never over onboarding), Google's consent tool shows the GDPR / US-state message where required (and on iOS, the IDFA explainer and Apple's tracking prompt if set up in AdMob). The ad SDK starts only after that. Settings → **Privacy choices** appears wherever people must be able to change their answer.
- **Never in the way:** an ad slot takes no space until its ad has loaded, collapses if loading fails or the phone is offline, and is announced as "Advertisement" by screen readers. Any ad SDK error leaves the app running without ads.
- To see the consent message from outside Europe during development, add your device as a test device in AdMob → **Privacy & messaging → Settings**, or use a VPN.
**Trying it**

- Run the backend with `PROVIDER=mock` and `FIREBASE_CREDENTIALS_FILE` set. Follow a team that has a live or soon-starting match today (long-press it), accept the permission prompt, and the simulated goals arrive within ~30 s.
- To send a single test push, a debug build prints `FCM token: ...` in the console. Use it in Firebase console → **Messaging → New campaign → Send test message**, with the custom data `match_id` = a match id, to check that tapping opens the match.
- Deep link from a terminal:

  ```bash
  adb shell am start -a android.intent.action.VIEW -d "bgoal://match/2026102800"
  ```

  ```bash
  xcrun simctl openurl booted "bgoal://match/2026102800"
  ```

## Run

Start the backend first (`cd backend && docker compose up`, with `PROVIDER=mock` for simulated live matches). Then:

```bash
flutter run                       # emulator/simulator → local backend
flutter run --dart-define=API_BASE_URL=https://your-api.onrender.com
```

On a **physical phone**, use your computer's LAN IP, for example `--dart-define=API_BASE_URL=http://192.168.1.20:8000`.

`--dart-define=SHOW_CRESTS=false` shows team initials instead of club crests (see [PUBLISHING.md](../PUBLISHING.md#3-rights-to-the-data-and-logos)). `--dart-define=PRIVACY_POLICY_URL=https://…` adds the policy link to Settings. Release builds are covered in [PUBLISHING.md](../PUBLISHING.md).

## Tests

```bash
flutter test
```

The files in `test/fixtures/` are real output from the backend's mock provider (`GET /matches`, `/matches/{id}`, `/teams/57`, `/teams/browse`, `/teams/search?q=real`), so the tests also check the app ↔ backend JSON contract.

## Structure

```
lib/
  main.dart                     startup: prefs, timezone, date symbols (all local, no network)
  app.dart                      MaterialApp.router, themes, locales, routes
  config.dart                   API_BASE_URL, ad unit ids, privacy policy URL, refresh interval
  theme.dart                    Material 3 light/dark + live/red-card colors
  providers.dart                Riverpod wiring
  l10n/strings.dart             en / fr / ar strings
  ads/
    ads_service.dart            AdMob + Google consent tool behind a testable interface
    ads_controller.dart         consent then SDK start (once), privacy choices
    ad_slots.dart               bottom banner and in-list native ad, collapse when empty
  data/
    models.dart                 FootballMatch, Team, Score, MatchEvent, Lineup, MatchStats, MatchDay, MatchDetail
    api_client.dart             HTTP + {data, updated_at, stale} envelope
    cache_store.dart            on-device copy of last responses (offline + instant start)
    matches_repository.dart     /matches?date=&tz= and /matches/{id}
    teams_repository.dart       /teams/{id}, /teams/search, /teams/browse
    favorites.dart              followed team ids (+ name and crest)
  features/onboarding/
    onboarding_screen.dart      welcome + language, pick teams, "Get alerts" before the system prompt
    onboarding_state.dart       done/skipped flag
  features/teams/
    team_picker.dart            search box + teams by league, follow stars (onboarding and Teams screen)
    teams_screen.dart, teams_controller.dart
  features/team/
    team_screen.dart            follow button, league position and form, next matches, recent results
    team_controller.dart        cache-first loading, offline fallback
  features/home/
    home_screen.dart            screen, auto-refresh, pull-to-refresh
    matches_controller.dart     cache-first loading, offline fallback
    home_logic.dart             grouping/pinning, when to poll (pure, unit-tested)
    date_strip.dart             yesterday / today / tomorrow / +7 days / calendar
    match_card.dart             one match row
  features/match/
    match_screen.dart           header + Timeline / Lineups / Stats tabs, auto-refresh
    match_controller.dart       cache-first loading of one match, offline fallback
    match_logic.dart            timeline, running score, pitch rows, player marks, stats (pure, unit-tested)
    match_header.dart           crests, score, status, HT/penalties, scorers
    timeline_tab.dart, lineups_tab.dart, stats_tab.dart, event_icons.dart
  features/settings/
    settings_screen.dart        theme, language, links to teams and notifications
    app_settings.dart           theme/language (saved on device)
    notification_settings_screen.dart   alerts on/off, quiet hours, per-team alerts
  notifications/
    notifications_controller.dart   permission timing, token, sync, notification taps, foreground pushes
    push_service.dart           Firebase Messaging + local notifications behind a testable interface
    device_sync.dart            POST /devices once, then PUT /devices/{id}/preferences on changes
    notification_settings.dart  alert types, quiet hours, per-team switches (saved on device)
    secret_store.dart           device secret in Keychain / Keystore
    push_links.dart             match id from a push or bgoal:// link (pure, unit-tested)
  widgets/                      crest image, status/time formatting, follow sheet,
                                "last updated" label, empty/error message, foreground poller

assets/brand/                   icon, splash, store graphics, notification icon (see BRAND.md)
tool/
  brand/make_icons.py           draws every brand image from shapes
  setup_platforms.py            applies BGoal's settings to android/ and ios/
  ios/PrivacyInfo.xcprivacy     iOS privacy manifest (copied by the setup script)
config/release.example.json     release settings: API URL, ad unit ids, privacy policy URL
```

## How the home screen behaves

- **Startup:** the last saved copy of the day is shown immediately, then replaced by fresh data. On a first launch with no network, it shows a Retry button.
- **Auto-refresh:** every 20 s, but only while the app is in the foreground and when a match is live, about to kick off (within 15 min), or overdue. It refreshes immediately when the app comes back to the foreground.
- **Offline:** cached matches stay on screen with “Offline · last updated HH:MM”. If the backend itself is serving old provider data, the label is highlighted too.
- **Favorites:** pick teams during onboarding, from the search icon, on a team page, or by long-pressing a match. Followed teams' matches are pinned under “Your teams”. They're synced to the backend for notifications.
- **Top bar:** search (find and follow teams) and Settings.
- **Time zones:** kickoff times use the device timezone and 12/24-hour setting. The day boundaries are the user's local midnight (the backend gets `tz=`).
- **Accessibility:** each card is read as one sentence (“Arsenal 2, Chelsea 1, minute 67, Premier League, followed team”). Layouts grow with system font size, there are no fixed heights, and Arabic mirrors right-to-left.

## How the match screen behaves

- **Opening:** from the home screen the header (teams, score, minute) shows instantly from the list data while details load. From a notification link (`/match/<id>`) it loads the saved copy if there is one, otherwise shows a spinner, then Retry if offline, or “couldn't be found” for an unknown id.
- **Header:** crests, score, live minute / HT / FT / AET, half-time score, penalty shootout score, goal scorers under each team (penalties and own goals tagged), date, kickoff time and venue.
- **Timeline:** newest first. Home events on one side, away on the other, with kick-off, half-time, shootout and full-time markers. Goals show the running score, but only when the events add up to the real score, so an incomplete feed never shows a wrong score. Own goals appear on the side that benefits. A scorer reassignment just replaces the name on the next refresh.
- **Lineups:** one team at a time. The starting XI is drawn on a pitch from the formation (or the provider's grid positions), with goals, cards and substitution minutes per player, then the substitutes. Before kick-off it says lineups usually come about an hour before.
- **Stats:** possession, shots, shots on target, corners, fouls and cards with comparison bars. Only stats the provider sends are shown.
- **Free data plan:** football-data.org's free tier has no scorers, lineups or stats. The screen then shows the score, status and half-time score, with a note in each tab. API-Football (or a paid football-data tier) fills them in with no app change.
- **Refresh:** every 20 s while the match is live or about to start, immediately on returning to the app, and with pull-to-refresh. Offline, the last copy stays with the “Offline · last updated” label.
- **Accessibility:** every timeline row, player and stat is read as a sentence, e.g. “minute 87, Penalty goal, Atlético Madrid, Ziyech, Atlético Madrid 4, Barcelona 0”.

## How onboarding, teams and settings behave

- **Onboarding** (first launch only): welcome page with a language choice that applies immediately, then "Pick your teams" (search, or browse by league; tap a row to follow), then the alerts page. Every step has Skip, and Android's back button goes to the previous step. Someone updating from a version without onboarding who already follows teams goes straight to the home screen. A match link or notification opened on first launch still opens the match.
- **Teams screen** (search icon): type 2+ letters to search (one request after you pause typing, not one per letter). With an empty search it lists the teams you follow, then every tracked league's teams. Tap a row to open the team, or the star to follow.
- **Team page:** crest, Follow / Following button, league position with played/won/drawn/lost/goal difference/points and recent form (when the provider sends it), next matches and recent results with dates. Tap a match to open it. Reached from the Teams screen, by tapping a crest in a match header, or from the long-press sheet. It refreshes every 20 s while one of its matches is live or about to start, and works offline from its saved copy.
- **Settings** (gear icon): teams you follow, notifications, theme (system / light / dark) and language (phone language / English / Français / العربية), then Privacy choices (where required) and the privacy policy link, and the data source credit. The language applies at once, Arabic switches the layout to right-to-left, and notifications switch to the chosen language too.

## How notifications behave

- **Device registration:** on first launch the app registers an anonymous device (`POST /devices`) and keeps the returned secret in the Keychain / Android Keystore. After that it sends only changes (`PUT /devices/{id}/preferences`): followed teams, per-team alerts, quiet hours, language, timezone and FCM token. Offline changes are sent when the connection comes back.
- **Permission:** never at launch. In onboarding, after you pick teams, a "Get alerts for your teams" page explains what you'll get before the system prompt ("Not now" skips it). Outside onboarding, it's asked the first time you follow a team. If you decline, the notification settings screen explains it and offers "Turn on" (Android can ask again; on iOS it points to the phone settings). While permission is off the backend is told `notifications_enabled: false`, so no pushes are wasted.
- **Settings** (Settings → Notifications): a match alerts master switch, quiet hours (enforced by the backend in your timezone, so they work with the app closed), and per followed team: starting soon, kick-off, goals, red cards, half-time, full-time, VAR corrections.
- **Tapping a notification** opens that match, whether the app was closed, in the background or open. `bgoal://match/<id>` links work too.
- **With the app open:** Android shows the push as a normal notification (iOS does this itself), and the scores on screen refresh right away instead of waiting for the next 20 s poll.
- **No duplicates:** the backend sends each event once (dedupe log). The same message delivered twice replaces the earlier notification instead of stacking, and iOS groups a match's notifications together.
