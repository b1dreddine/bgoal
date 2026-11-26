# Launching BGoal on the App Store and Google Play

This takes BGoal from code to live in both stores, with ads. It's written for a first launch: follow the steps in order, because later ones need things from earlier ones (the backend URL is compiled into the app, the AdMob ids go into the native projects, the privacy policy URL goes into every store form).

Store rules change every year. Where this guide gives a number that Apple or Google revise (SDK levels, screenshot sizes, tester counts), check the current value on the page linked next to it.

**Your path, start to finish** (allow 3–5 weeks, mostly waiting for reviews and testers):

| # | Step | Time | Section |
|---|---|---|---|
| 1 | Create the accounts (Google Play, Apple, AdMob, Firebase) | 1–7 days of verification | [1](#1-accounts-and-what-they-cost) |
| 2 | Put the backend online | 1 hour | [2](#2-production-backend) |
| 3 | Decide about data and logo rights | 30 min | [3](#3-rights-to-the-data-and-logos) |
| 4 | Generate the Android/iOS projects with BGoal's settings | 30 min | [4](#4-generate-the-native-projects) |
| 5 | Set up AdMob: app, ad units, consent messages | 1 hour | [5](#5-admob-ads) |
| 6 | Publish the privacy policy and app-ads.txt | 30 min | [6](#6-privacy-policy-and-app-adstxt) |
| 7 | Build, test and upload to Google Play; run the closed test | 14+ days | [7](#7-android--google-play) |
| 8 | Build, test and upload to the App Store | 1–3 days | [8](#8-ios--app-store) |
| 9 | Fill in the store listings | 1 hour | [9](#9-store-listings) |
| 10 | Final checks, release | | [10](#10-release-checklist) |
| | Shipping updates later | | [11](#11-shipping-updates) |

The app's identity (name, icon, colours, voice) is in [BRAND.md](BRAND.md).

---

## 1. Accounts and what they cost

| You need | Cost | Notes |
|---|---|---|
| [Google Play Console](https://play.google.com/console/signup) developer account | $25, once | Identity verification can take a few days. A **personal** account created after November 2023 must run a closed test with at least 12 testers for 14 days before it can publish to production ([details](https://support.google.com/googleplay/android-developer/answer/14151465)). An **organization** account (needs a D-U-N-S number) skips that. |
| [Apple Developer Program](https://developer.apple.com/programs/enroll/) membership | $99 / year | Also needed for iOS push (APNs) and TestFlight. Enrolling as an organization also needs a D-U-N-S number. |
| [Google AdMob](https://admob.google.com) account | free | Sign in with a Google account. Payments need your tax details and address; Google mails a PIN to verify the address once earnings reach $10. Paid out monthly once the balance passes $100. |
| [Firebase](https://console.firebase.google.com) project | free (Spark plan) | Push notifications. Setup is in the main [README](README.md#2-firebase-project-free-spark-plan-is-enough). |
| A Mac with a recent Xcode | | **iOS apps can only be built and uploaded from macOS.** From Windows, use a cloud Mac or a CI service with macOS machines (Codemagic has a free tier for Flutter; GitHub Actions `macos-*` runners; Bitrise). Apple requires a recent SDK: since April 2026, builds must use Xcode 26 / the iOS 26 SDK ([upcoming requirements](https://developer.apple.com/news/upcoming-requirements/)). |
| A website | free | For the privacy policy, a support page and `app-ads.txt`. GitHub Pages works (section 6). |
| A public support email | | Shown on both store listings. |

**Choose the app id now.** Android's application id and iOS's bundle id identify the app forever; they can never change after the first upload, and Firebase needs them. This project uses **`com.bgoal.livescores`** (from `flutter create --org com.bgoal`). Change it now if you prefer, for example to your own domain reversed (`com.yourdomain.bgoal`): pass `--org` differently to `flutter create`, or `--application-id` to the setup script.

**Check the name.** Before paying for anything, search both stores for "BGoal". Apple doesn't allow two apps with the same name, and a similar name in the same category is a trademark risk. When this was written (November 2026) no "BGoal" app was found, but a different live-scores app called "bScore" exists.

## 2. Production backend

The app talks only to your backend, so it must be live, on HTTPS, before you build.

1. Deploy it as described in the main [README → Hosting](README.md#hosting). The **worker must run on an always-on instance**: if it sleeps, live scores freeze and no notifications go out.
2. Set these in the hosting environment:
   - `PROVIDER=football_data` and `FOOTBALL_DATA_API_KEY` (or the API-Football equivalents).
   - `FIREBASE_CREDENTIALS_FILE` pointing at the service-account JSON, uploaded as a secret file (never commit it).
   - `DATABASE_URL`, `REDIS_URL`.
   - Optional: `DEVICE_RETENTION_DAYS` (default 90; the privacy policy quotes it).
3. Check it from your browser:
   - `https://YOUR-API/docs` loads.
   - `https://YOUR-API/matches?date=<today>&tz=Europe/Paris` returns matches.
   - `https://YOUR-API/teams/browse` returns teams. If it's empty, the worker hasn't run its first team sync yet; check the worker logs for `synced N teams`.
4. Keep the URL stable. Every installed copy of the app has it compiled in. Put your own domain in front (for example `api.bgoal.app`) so you can change hosts without an app update.

Store reviewers use the app at an unpredictable time. With football-data's free tier there may be no live match then, but scheduled and finished matches still show, which is enough for review.

## 3. Rights to the data and logos

Read this before submitting. It's the most likely reason for a rejection or a takedown, and it's a business decision, not a technical one. **With ads, the app is commercial**, which matters for all three points.

- **Match data.** Read your data provider's terms for use in a published app, **including commercial use with ads**. Check whether football-data.org's terms allow commercial use on the plan you use; if they don't, move to a plan or provider that does before launching with ads. The app already credits the source in Settings ("Match data from football-data.org"); change that line in `app/lib/l10n/strings.dart` if you switch provider.
- **Club crests and league logos are trademarks.** The app shows the images the provider links to. Apple (App Review Guideline 5.2) and Google (Intellectual Property policy) can reject or remove an app that uses third-party trademarks without permission, and rights holders can file complaints; the risk is higher in a monetised app. Many score apps show crests anyway. If you'd rather not take the risk, or a reviewer objects, set `"SHOW_CRESTS": "false"` in your release config (section 7.2): the app then shows team initials everywhere.
- **Names.** Don't put a league, club or competition name, or its logo, in the app's name, icon, screenshots' marketing text or keywords. "Premier League Scores" will be rejected; "BGoal" with Premier League matches visible in the screenshots is normal.

## 4. Generate the native projects

The repository holds the Flutter code; the Android and iOS projects are generated once and then configured by a script. You need [Flutter](https://docs.flutter.dev/get-started/install) (3.27 or newer) and Python 3.9 or newer. From the `app/` folder:

```bash
flutter create --org com.bgoal --project-name livescores --platforms ios,android .
```

```bash
flutter pub get
```

Then apply BGoal's settings. Use the AdMob **app ids** from section 5 if you already have them; without them the script uses Google's test ids, which is fine until you build for the stores:

```bash
python tool/setup_platforms.py --admob-android-app-id ca-app-pub-XXXXXXXXXXXXXXXX~NNNNNNNNNN --admob-ios-app-id ca-app-pub-XXXXXXXXXXXXXXXX~NNNNNNNNNN
```

It sets the app name, the internet permission, the AdMob ids (the app crashes at launch without them), the tracking prompt text, `bgoal://` links, the notification icon, iOS 15 / Android 8 minimums, release signing and the Firebase plugin, and lists anything left to do by hand. Run it again any time; it only changes what's missing.

Then generate the icons and the launch screen from `assets/brand/`:

```bash
dart run flutter_launcher_icons
```

```bash
dart run flutter_native_splash:create
```

Do the Firebase steps in the main README, copy `google-services.json` into `android/app/` and `GoogleService-Info.plist` into Xcode, and run the setup script once more so it switches on the Google services plugin.

**Check the Android target level.** Google Play requires new apps and updates to target **Android 16 (API 36)** since 31 August 2026 ([target API requirement](https://developer.android.com/google/play/requirements/target-sdk)). Flutter sets `targetSdk = flutter.targetSdkVersion`; an up-to-date Flutter already uses 36 or higher. If Play Console complains, update Flutter, or set `targetSdk = 36` in `android/app/build.gradle.kts`.

## 5. AdMob (ads)

BGoal shows three kinds of ad placement, all decided in the code:

- **A banner** at the bottom of the Home, Match and Team screens (adaptive size, full width).
- **One native ad** between the second and third league on the Home list, styled like a match card and labelled "Ad".
- **None** in onboarding, Settings, the team picker, or notifications.

Ads only load after the consent step below, take no space until they've loaded, and disappear if loading fails, so a match list never shows an empty box. `"ADS": "false"` in the release config builds an app with no ads at all.

AdMob is Google's programmatic ad platform: each ad request is auctioned among Google's demand and third-party ad networks, so you don't have to sign deals with advertisers. You can add more networks later with AdMob **mediation** (section 11).

### 5.1 Register the app and create ad units

In [AdMob](https://admob.google.com) → **Apps → Add app**, once for Android and once for iOS:

1. "Is the app listed on a supported app store?" **No** for now (you'll link it after it's published).
2. App name **BGoal**, platform, then **Add**.
3. Note the **app id** (`ca-app-pub-…~…`). Pass both ids to `tool/setup_platforms.py` (section 4).
4. **Ad units → Add ad unit**, twice per app:
   - **Banner**, name `home-match-team-banner`. Leave automatic refresh on (Google-optimised).
   - **Native advanced**, name `home-list-native`.
5. Note the four **ad unit ids** (`ca-app-pub-…/…`). They go in the release config (section 7.2).

During development the app always uses Google's **test** ad units, whatever you configure, so you can't get your account flagged for clicking your own ads. Never tap real ads in your own app.

### 5.2 Consent messages (required)

Google requires a consent message for users in the EEA, UK and Switzerland, and a privacy message for some US states. The app shows them with Google's own tool; you write them in the console. In AdMob → **Privacy & messaging**:

1. **European regulations → Create message**: select both BGoal apps, language(s) English, French, Arabic, your privacy policy URL, and the default choices ("Consent" and "Do not consent" buttons). Publish.
2. **US state regulations → Create message**: select both apps, publish.
3. **IDFA explainer (iOS)**: create the message that appears before Apple's "Allow tracking?" prompt. Publish. Without it, the app never shows Apple's prompt and iOS ads can't be personalised (they still show).

The app shows these on the first visit to the home screen (never over onboarding), then starts the ad SDK. Settings shows **Privacy choices** wherever people must be able to change their answer.

### 5.3 Ad content and safety

In AdMob → **Blocking controls → All apps**:

- **Sensitive categories**: block **Gambling & betting** (sports apps attract a lot of betting ads; some countries ban them and both stores' age ratings depend on it), and anything else you don't want next to football scores (dating, alcohol, politics).
- **Max ad content rating**: the app already requests **T** (teen) at most.

## 6. Privacy policy and app-ads.txt

### 6.1 Privacy policy

A complete template is in [docs/privacy-policy.md](docs/privacy-policy.md). It describes exactly what the app, the backend and AdMob collect. Replace the placeholders and publish it.

### 6.2 app-ads.txt

Ad buyers check a file called `app-ads.txt` on the **developer website** you give in the store listings. Without it, many advertisers won't bid on your ads and earnings drop noticeably. [docs/app-ads.txt](docs/app-ads.txt) has the line; replace `pub-0000000000000000` with your publisher id (AdMob → **Settings → Account information**, or AdMob → **Apps → View all apps → app-ads.txt**).

The file must be at the **root** of the domain: `https://yourdomain/app-ads.txt`, not in a sub-folder.

### 6.3 Hosting both on GitHub Pages (free)

1. Create a GitHub repository named **`<your-github-username>.github.io`** (exactly that name makes it a root site).
2. Add `app-ads.txt` at the top level, and `privacy.md` with the filled-in policy (or `privacy.html`).
3. Repository **Settings → Pages**: deploy from the main branch.
4. After a minute: `https://<username>.github.io/app-ads.txt` and `https://<username>.github.io/privacy` are live.
5. Use `https://<username>.github.io` as the **developer website** in both stores (so AdMob finds `app-ads.txt`), and the `/privacy` URL as the privacy policy URL.

A custom domain (for example `bgoal.app`, about $10–15/year) works the same way and looks more trustworthy on the listing.

## 7. Android → Google Play

### 7.1 Upload key

Google re-signs your app with a key it keeps (**Play App Signing**). You sign uploads with your own **upload key**. If you lose it, Google can reset it, but keep a backup anyway.

```bash
keytool -genkey -v -keystore upload-keystore.jks -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Store the `.jks` file **outside** the repository, and back it up. Create `app/android/key.properties` (git ignores it):

```properties
storePassword=...
keyPassword=...
keyAlias=upload
storeFile=C:/Users/you/keys/upload-keystore.jks
```

The setup script already wired `build.gradle.kts` to use it for release builds (and the debug key while the file doesn't exist).

### 7.2 Release config

Copy `app/config/release.example.json` to `app/config/release.json` (git ignores it) and fill in:

| Key | Value |
|---|---|
| `API_BASE_URL` | Your backend, `https://…` (section 2). **Required**: without it the app points at `localhost` and shows "Couldn't load matches" for everyone. |
| `PRIVACY_POLICY_URL` | Your published policy (section 6). Shown in Settings. |
| `ADMOB_BANNER_ANDROID`, `ADMOB_NATIVE_ANDROID`, `ADMOB_BANNER_IOS`, `ADMOB_NATIVE_IOS` | The four ad unit ids (section 5.1). A missing one means no ad in that slot. |
| `SHOW_CRESTS` | `"false"` to show team initials instead of crests (section 3). |
| `ADS` | `"false"` to build without ads. |

### 7.3 Build

From `app/`:

```bash
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols --dart-define-from-file=config/release.json
```

- The output is `build/app/outputs/bundle/release/app-release.aab`.
- Keep `build/symbols` for each release; you need it to read crash stack traces from obfuscated builds.
- Check the setup script ran with your **real** AdMob app ids (it says so at the end). Test app ids in a store build mean no earnings.

Before uploading, install a release build on a real phone:

```bash
flutter build apk --release --dart-define-from-file=config/release.json
```

```bash
flutter install
```

Check: the consent message appears if you're in Europe (or use a VPN), matches load, a banner appears at the bottom of Home after a few seconds, the native ad appears between leagues, a followed team's notification arrives and opens the match, and offline shows the saved scores. Real ads may take a few hours to start serving for a new ad unit, and serve less until the app is live and linked (section 10).

### 7.4 Play Console setup

1. **Create app**: name **BGoal - Live Sports Scores**, default language, App (not game), Free, accept the declarations.
2. **Dashboard → Set up your app**, then complete each task:
   - **Privacy policy**: your policy URL.
   - **App access**: "All functionality is available without special access" (no login).
   - **Ads**: **Yes, my app contains ads.** The listing then shows "Contains ads".
   - **Advertising ID**: **Yes**, used for **Advertising or marketing** (the AdMob SDK adds the `AD_ID` permission).
   - **Content rating**: questionnaire, category "Reference, News, or Educational". Answer No to violence, gambling and the rest (gambling ads are blocked in section 5.3), Yes only to what's actually in the app. The result is usually "Everyone" / PEGI 3.
   - **Target audience**: **13 and over**. Including under-13s brings the Families policy, which restricts ads heavily.
   - **News app**: No.
   - **Data safety**: see 7.5.
   - **Government app, Financial features, Health**: No.
3. **Main store listing**: texts from section 9, app icon `app/assets/brand/play_store_icon_512.png`, feature graphic `app/assets/brand/play_feature_graphic.png`, at least 2 phone screenshots ([listing requirements](https://support.google.com/googleplay/android-developer/answer/9866151)). Add French and Arabic under **Manage translations**.
4. **Store settings**: category **Sports**, contact email, **website** = the site with `app-ads.txt` (section 6.3).

### 7.5 Data safety answers

Two sources of data: BGoal's own backend, and the AdMob SDK. Google publishes what its SDK collects for this form: [AdMob data disclosure for Google Play](https://developers.google.com/admob/android/privacy/play-data-disclosure). In summary:

- **Does your app collect or share data?** Yes. **Encrypted in transit?** Yes. **Can users request deletion?** Yes (by email, as the policy says).
- **Device or other IDs**: collected **and shared**. Purposes: App functionality (BGoal's device id and push token), Advertising or marketing, Analytics, Fraud prevention (advertising id, used by AdMob).
- **Location → Approximate location**: collected and shared, by AdMob from the IP address. Purposes: Advertising, Analytics, Fraud prevention.
- **App activity → App interactions**: collected and shared, by AdMob (ad views and taps). Purposes: Advertising, Analytics, Fraud prevention. **Other user-generated content / other actions**: collected, not shared (followed teams and alert settings). Purpose: App functionality, optional.
- **App info and performance → Diagnostics**: collected and shared, by AdMob. Purposes: Analytics, Fraud prevention.
- None of it is linked to an account (there are none), but Google's form asks per data type; answer as the privacy policy says.

Re-check Google's disclosure page when you update `google_mobile_ads`; it lists the current SDK's behaviour.

### 7.6 Testing tracks, then production

1. **Internal testing**: upload the `.aab`, add your own Google account as a tester, install from the opt-in link. Available within minutes, no review.
2. **Closed testing**: required for new personal accounts: 12+ testers who stay opted in for 14 days. Ask friends, a football forum, or a supporters' group. Fix what they find; each new build needs a higher version code (section 11).
3. **Production**: create a release, attach the build, choose countries, and start with a **staged rollout** (for example 20%), then increase. The first review usually takes a few days.

## 8. iOS → App Store

All of this happens on a Mac (or CI with macOS). Run section 4 there first, or copy the configured `ios/` folder over.

### 8.1 Xcode project settings

Open `app/ios/Runner.xcworkspace` (the workspace, not the `.xcodeproj`).

- **Runner → Signing & Capabilities**: your Team, "Automatically manage signing", bundle identifier = your final id. Add **Push Notifications** and **Background Modes → Remote notifications**.
- **Runner → General → Minimum Deployments**: iOS 15.0 (the setup script sets it).
- **Supported Destinations**: Flutter projects include iPad by default. If iPad is listed, App Store Connect requires iPad screenshots too, and reviewers may test on an iPad. The layouts work there, but if you don't want to support it, remove iPad here.
- **Privacy manifest**: the setup script wrote `ios/Runner/PrivacyInfo.xcprivacy`. If it isn't in Xcode's file list, drag it into **Runner** and tick the Runner target. It declares BGoal's own data and that the app may track (personalised ads, with permission). Google's SDK and Firebase ship their own manifests.
- **SKAdNetwork ids**: the setup script added Google's own id. For more ad demand, paste the full list of third-party buyer ids from Google's [iOS quick start → Update your Info.plist](https://developers.google.com/admob/ios/quick-start#update_your_infoplist) into `Info.plist` under `SKAdNetworkItems`.

After archiving, **Organizer → right-click the archive → Generate Privacy Report** shows everything the app and its SDKs declare. Make the App Privacy answers (8.3) match it.

**Push in release builds.** TestFlight and App Store builds use Apple's production push servers. The APNs key (.p8) uploaded to Firebase works for both, but test a push on a TestFlight build before release.

### 8.2 App Store Connect setup

At [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → **Apps → + → New App**: platform iOS, name **BGoal - Live Sports Scores** (30 characters max, must be unique in the store), primary language, bundle id, an SKU (any internal code, for example `bgoal-ios`).

Then, on the app's page:

- **App Information**: subtitle (section 9), category **Sports**, content rights: the app shows third-party content (match data, and crests unless built with `SHOW_CRESTS=false`), so say Yes and that you have the rights to use it (section 3).
- **Age rating**: answer the questionnaire honestly; the app has no user-generated content, no gambling (betting ads are blocked), and shows ads. The result is usually 4+ or 9+.
- **Pricing and Availability**: Free, countries.
- **Version page**: description, keywords, support URL, marketing URL (your site), screenshots: required 6.9" iPhone (1320×2868 or 1290×2796), and 13" iPad (2064×2752) if iPad is supported ([screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications)). Add French and Arabic localizations with the texts from section 9.

### 8.3 App Privacy answers

Google publishes the AdMob answers: [AdMob data disclosure for iOS](https://developers.google.com/admob/ios/privacy/data-disclosure). With BGoal's own data, the result is:

- **Data used to track you** (personalised ads, only if the user allows tracking): **Identifiers → Device ID**, **Usage Data → Advertising Data**.
- **Data linked to you**: none (no accounts).
- **Data not linked to you**:
  - **Identifiers → Device ID**: App Functionality (push and settings sync), Third-Party Advertising, Analytics.
  - **Location → Coarse Location**: Third-Party Advertising, Analytics (AdMob, from the IP address).
  - **Usage Data → Product Interaction, Advertising Data**: Third-Party Advertising, Analytics.
  - **Diagnostics → Crash Data, Performance Data, Other Diagnostic Data**: Analytics (AdMob SDK).
  - **User Content → Other User Content**: App Functionality (followed teams, alert settings).

Privacy policy URL: yours.

### 8.4 Build and upload

From `app/`:

```bash
flutter build ipa --release --obfuscate --split-debug-info=build/symbols --dart-define-from-file=config/release.json
```

Upload `build/ios/ipa/*.ipa` with Apple's **Transporter** app, or open `build/ios/archive/Runner.xcarchive` in Xcode's Organizer and choose **Distribute App → App Store Connect**. The build appears in App Store Connect after 10–30 minutes of processing. The export-compliance question is already answered (`ITSAppUsesNonExemptEncryption = NO`: the app only uses standard HTTPS).

### 8.5 TestFlight, then review

1. **TestFlight → Internal testing**: add yourself, install the TestFlight app on your iPhone. Check: the IDFA explainer and Apple's tracking prompt appear (once), scores load, ads appear, a notification arrives and opens the match.
2. Optional **external testing** (up to 10,000 testers by link) needs a short beta review first.
3. On the version page, select the build and **Add for Review**. In **App Review Information**:
   - Sign-in required: No.
   - Notes, for example:

     > No account is needed. On first launch, pick a team (for example Arsenal or Real Madrid) and allow notifications to receive goal, red card and full-time alerts for its matches. Scores update automatically while matches are live. The app is free and shows ads from Google AdMob; the tracking prompt is requested through Google's consent tool before any personalised ads. Settings (gear icon) has theme, language (English, French, Arabic), per-team alert options and privacy choices.

Review usually takes one to three days. Common rejections for this kind of app:

- **5.2 Intellectual property**: crests or league names (section 3).
- **5.1.2 Data use / App Tracking Transparency**: personalised ads without Apple's prompt. The app only shows the prompt through Google's IDFA explainer, so publish that message (section 5.2) before submitting.
- **4.3 Spam / 4.2 Minimum functionality**: score apps are a crowded category. Your notifications, per-team alert settings and three languages help; mention them in the notes.
- **2.1 Broken on the review device**: usually a missing `API_BASE_URL`, a sleeping backend, or an iPad layout issue.

## 9. Store listings

Character limits: Play title 30, short description 80, full description 4000; App Store name 30, subtitle 30, keywords 100, description 4000, promotional text 170.

**Only claim what your data plan delivers.** football-data.org's free tier has no scorers, cards, lineups or stats. If that's what you launch with, remove those words below (stores reject listings that promise features the app doesn't have).

**"Sports" in the name.** BGoal only covers football. Reviewers can object to a name that promises more than the app does; if one does, use **BGoal - Live Football Scores** (28 characters) instead.

### English

- Name (both stores): BGoal - Live Sports Scores
- Short description (Play): Live football scores and instant goal alerts for the teams you follow.
- Subtitle (App Store): Live scores & goal alerts
- Promotional text (App Store): Follow your teams and get a ping within seconds of every goal, red card and final whistle.
- Keywords (App Store): football,soccer,live,scores,results,goals,fixtures,lineups,league,alerts
- Description:

  > BGoal keeps you on top of every match.
  >
  > • Live scores, minute by minute, with scorers and red cards
  > • Instant alerts for your teams: kick-off, goals, red cards, half-time and full-time
  > • Choose exactly which alerts you get for each team, and set quiet hours
  > • Match timelines, lineups and stats
  > • Team pages with league position, form, next matches and results
  > • Works offline with the last saved scores
  > • English, French and Arabic, light and dark themes
  >
  > No account needed. Free, supported by ads.

### Français

- Nom : BGoal - Live Sports Scores
- Description courte : Scores de foot en direct et alertes de buts pour les équipes que vous suivez.
- Sous-titre : Scores et alertes de buts
- Texte promotionnel : Suivez vos équipes et soyez prévenu en quelques secondes à chaque but, carton rouge et coup de sifflet final.
- Mots-clés : foot,football,direct,scores,résultats,buts,calendrier,compositions,ligue,alertes
- Description :

  > BGoal vous tient informé de chaque match.
  >
  > • Scores en direct, minute par minute, avec buteurs et cartons rouges
  > • Alertes instantanées pour vos équipes : coup d'envoi, buts, cartons rouges, mi-temps et fin du match
  > • Choisissez les alertes de chaque équipe et définissez des heures calmes
  > • Déroulé du match, compositions et statistiques
  > • Pages d'équipe avec classement, forme, prochains matchs et résultats
  > • Fonctionne hors ligne avec les derniers scores enregistrés
  > • Français, anglais et arabe, thèmes clair et sombre
  >
  > Aucun compte nécessaire. Gratuit, financé par la publicité.

### العربية

- الاسم: BGoal - Live Sports Scores
- وصف قصير: نتائج كرة القدم مباشرة وتنبيهات فورية بأهداف الفرق التي تتابعها.
- العنوان الفرعي: نتائج مباشرة وتنبيهات
- النص الترويجي: تابع فرقك وتلقَّ تنبيهًا خلال ثوانٍ مع كل هدف وبطاقة حمراء وصافرة نهاية.
- الكلمات المفتاحية: كرة القدم,مباشر,نتائج,أهداف,مباريات,تشكيلات,دوري,تنبيهات
- الوصف:

  > يتيح لك BGoal متابعة كل مباراة لحظة بلحظة.
  >
  > • نتائج مباشرة دقيقة بدقيقة مع الهدافين والبطاقات الحمراء
  > • تنبيهات فورية لفرقك: صافرة البداية، الأهداف، البطاقات الحمراء، نهاية الشوط الأول ونهاية المباراة
  > • اختر التنبيهات التي تريدها لكل فريق وحدّد ساعات الهدوء
  > • أحداث المباراة والتشكيلات والإحصائيات
  > • صفحات الفرق مع الترتيب والمستوى والمباريات القادمة والنتائج
  > • يعمل دون اتصال بآخر النتائج المحفوظة
  > • العربية والإنجليزية والفرنسية، مع المظهر الفاتح والداكن
  >
  > دون حساب. مجاني ومدعوم بالإعلانات.

### Screenshots

Take them on a simulator or emulator at the required sizes, with the backend running `PROVIDER=mock` so live matches are always on screen, and with `"ADS": "false"` so no test ads appear in them. A good set of six: home with a live match, a match timeline, a team page, notification settings, the goal notification on the lock screen, and one in Arabic to show right-to-left. A short caption on top of each (white text on BGoal green, see BRAND.md) helps people scanning the store. Avoid leaning on club crests in the captions if you're unsure about rights.

## 10. Release checklist

- [ ] Backend live on HTTPS, worker always on, `/teams/browse` not empty.
- [ ] Data provider terms allow commercial use with ads; attribution line correct in Settings.
- [ ] `config/release.json` filled in: `API_BASE_URL`, `PRIVACY_POLICY_URL`, four ad unit ids (and `SHOW_CRESTS` as decided).
- [ ] `tool/setup_platforms.py` last run with the **real** AdMob app ids.
- [ ] AdMob: consent messages (Europe, US states, IDFA explainer) published; gambling ads blocked.
- [ ] Privacy policy and `app-ads.txt` live; the store's developer website points at the domain with `app-ads.txt`.
- [ ] App id final and matching the Firebase apps.
- [ ] Icons and splash generated; version bumped.
- [ ] Release build tested on a real Android phone and via TestFlight on a real iPhone: consent, scores, ads, a push that opens the match, offline.
- [ ] Play: Ads = Yes, Advertising ID declared, Data safety and target audience done. Apple: App Privacy matches the privacy report.
- [ ] Upload key backed up; `key.properties`, `release.json` and the service-account JSON not in git.
- [ ] `build/symbols` saved for this version.

**After launch:**

- In AdMob → **Apps**, open each app → **App settings → Add store**, and link it to the live store listing. AdMob then reviews the app ("app readiness"); until it's approved and `app-ads.txt` is verified, ads serve in limited numbers.
- Watch **AdMob → Policy center** for warnings in the first weeks.
- Reply to store reviews; the first ratings matter most.

## 11. Shipping updates

1. Bump the version in `app/pubspec.yaml` (for example `1.0.1+2`). The number after `+` must always increase, even after a rejected upload.
2. Build with the same commands and upload to the internal track / TestFlight first.
3. Release with a staged rollout on Play and **phased release** on the App Store, so a bad build reaches few people.
4. **Backend first, apps second.** Old app versions stay installed for months. Deploy backend changes that keep the existing JSON fields working (add fields, don't rename or remove them). The app ignores fields it doesn't know and falls back safely on unknown values, so adding is always safe.
5. **More ad networks (optional).** Once the app has steady traffic, AdMob → **Mediation** lets other networks (AppLovin, Meta Audience Network, Unity, …) compete for each slot. Each needs its adapter package added to `pubspec.yaml` (`gma_mediation_<network>`), its own account, and lines added to `app-ads.txt` and the Data safety / App Privacy answers.
6. When you update `google_mobile_ads`, re-check Google's data disclosure pages (7.5 and 8.3).
