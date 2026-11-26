# Privacy policy template

Replace everything in **[brackets]**, delete this note, and publish the result at a public URL (for example with GitHub Pages, see PUBLISHING.md). It matches what the BGoal app, its backend and the Google AdMob SDK it uses do. If you add analytics, crash reporting, accounts, sign-in or another ad network, update it **before** releasing that version, and update the Play Data safety and App Store App Privacy answers too.

This is a starting point, not legal advice. Because the app shows ads, and if you have users in the EU/UK (GDPR), California and other US states (CCPA and similar laws), or other regulated places, have it reviewed.

---

# BGoal Privacy Policy

Last updated: [date]

BGoal ("the app") is published by [your name or company] ("we"). This policy explains what information the app uses, why, and the choices you have.

## Summary

- You don't need an account. We don't ask for your name, email, phone number or precise location.
- To send you match notifications, our server keeps an anonymous record of the teams you follow and your alert settings.
- The app is free and shows ads from Google AdMob. Where the law requires it, we ask for your consent first, and on iPhone Apple's tracking prompt lets you decide whether ads can use your device's advertising identifier.
- We don't sell your information.

## What our server collects

When you open the app for the first time, it registers your device with our server under a **random identifier** that isn't linked to your identity. The server stores:

- **Notification token:** an identifier from Google Firebase Cloud Messaging that lets us send notifications to your device.
- **Teams you follow and your alert choices** (for example: goals on, half-time off).
- **Notification settings:** whether match alerts are on, your quiet hours, your language and your timezone.
- **Your device platform** (iOS or Android).

The app also keeps your settings, followed teams and recently viewed scores on your phone so it can start quickly and work offline. That copy never leaves your device except as described here.

## Advertising

The app shows ads served by **Google AdMob**, a Google advertising service. To choose, show and measure ads and to prevent fraud, the AdMob software in the app collects and sends to Google:

- your device's **advertising identifier** (Android Advertising ID, or Apple's IDFA if you allow tracking);
- your **IP address**, from which an approximate location (such as the city or country) can be estimated;
- information about the **ads you see and tap**, and technical information about your device and the app (model, operating system, app version, diagnostics).

**Your choices:**

- **EEA, UK and Switzerland:** before any ads load, the app shows a consent message from Google's consent tool. You can accept, refuse or choose purposes. Refusing still shows ads, but they aren't personalised. You can change your answer at any time in **Settings → Privacy choices**.
- **US states with privacy laws:** where required, the app offers a way to opt out of the sale or sharing of your information for targeted advertising, in **Settings → Privacy choices**.
- **iPhone:** Apple's "Allow BGoal to track your activity…" prompt decides whether ads may use your device's advertising identifier. You can change it in **Settings → Privacy & Security → Tracking**.
- **Android:** you can reset or delete your advertising ID in your phone's **Settings → Privacy → Ads** (or **Google → Ads**).

Google uses this information under its own policies: see [How Google uses information from sites or apps that use our services](https://policies.google.com/technologies/partner-sites) and [Google's Privacy Policy](https://policies.google.com/privacy).

## What we don't collect

Your name, email address, contacts, photos, precise location, or browsing history. We don't use analytics or crash-reporting services.

## How we use information

- To provide the app: showing the right matches first, and sending notifications about your teams in your language, outside your quiet hours.
- To show ads that pay for the app, as described above.

## Who we share it with

- **Google Firebase Cloud Messaging** delivers notifications to Android devices and, through Apple's push service, to iPhones. It receives your notification token and the text of each notification. See [Firebase's privacy information](https://firebase.google.com/support/privacy).
- **Google AdMob** receives the advertising information described above.
- **Our hosting provider** ([e.g. Render]) stores our server and database on our behalf.

We don't sell your information to anyone. We share it otherwise only if required by law.

Match data, team names and crests are loaded from our server, which gets them from [data provider, e.g. football-data.org]. The data provider doesn't receive any information about you.

## How long we keep it

Our server keeps your device record as long as the app is installed. After you uninstall it, the next notification we try to send is reported by Firebase as undeliverable; we then remove the notification token straight away and delete the rest of your device's record, including your followed teams, [90] days later. Google keeps advertising information according to its own policies.

## Your rights

Depending on where you live, you may have the right to access, correct or delete your information, to object to or restrict its use, and to withdraw consent. To use them:

- **Ads:** Settings → Privacy choices in the app, and your phone's tracking and ad settings described above.
- **Our server's record:** uninstall the app (deleted automatically as described above), or email us at [email] and we'll delete it sooner. Because there's no account, we may ask roughly when you installed the app and which teams you follow, to find your record.
- **Notifications:** turn them off in the app (Settings → Notifications) or in your phone's settings.

If you're in the EEA or UK you can also complain to your data protection authority. [If you're established in the EU/UK, add your legal basis: we rely on your consent for personalised advertising, and on our legitimate interest in providing the app's features for notification data.]

## Security

All communication between the app and our server uses HTTPS. The secret your device uses to update its settings is stored in your phone's secure storage (Keychain on iPhone, Keystore on Android), and our server keeps only a one-way hash of it.

## Children

The app isn't directed at children under 13 (or the age of digital consent where you live), and we don't knowingly collect information from them. Ads in the app are limited to content suitable for teenagers.

## Changes

If we change this policy, we'll update the date at the top. Significant changes will be announced in the app's release notes.

## Contact

[Your name or company], [postal address if required in your country]
[email]
