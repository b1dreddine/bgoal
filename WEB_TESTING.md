# Sharing BGoal with iPhone testers by link (free)

Without an Apple Developer account you can't send an iPhone app. This sends a **website version** of BGoal instead: your friends open a link, follow a 4-step guide that appears on screen, and get a BGoal icon on their Home Screen that opens full screen like an app.

- **Costs nothing**, and the link **never expires**: it stays up as long as the GitHub repository exists. Every update you push reaches testers the next time they open the app.
- Android friends can use it too (or the APK, see PUBLISHING.md).

**What testers get:** live scores, matches, teams, following teams, settings, the three languages and dark mode.
**What they don't get:** goal notifications and ads (both need the store versions). Club crests may show as initials in the browser, because the image server doesn't allow other websites to load its pictures.

## What you need

1. **The backend online, on HTTPS.** A website on `https://` can't talk to `http://`, and testers' phones can't reach `localhost`. Free, with no card: **Vercel** (below).
2. **A free GitHub account**, with this project in a **public** repository (GitHub Pages is free for public repositories; a private one needs a paid plan). Your code is then visible to anyone; the backend keys are not in it.

## Free backend on Vercel (no card)

The backend detects Vercel and switches to a mode made for it: no separate worker (the API fetches live scores itself, cached for 15 seconds), a small database in `/tmp`, and an in-memory cache. Nothing to configure. It never sleeps in a way testers notice: each request starts it in about a second, even after weeks without visitors. No push notifications in this mode.

1. Go to [vercel.com/signup](https://vercel.com/signup), choose **Hobby**, and **Continue with GitHub**.
2. **Add New → Project**, import **bgoal**.
3. **Root Directory**: click **Edit** and choose `backend`. Leave everything else as it is.
4. **Deploy**. The address is shown when it's done, for example `https://bgoal-xxxx.vercel.app`.
5. Put that address in the GitHub variable `API_BASE_URL` (next section) and run the web workflow again.

It starts with simulated matches (`PROVIDER=mock`). For real ones: Vercel project → **Settings → Environment Variables**: `PROVIDER` = `football_data` and `FOOTBALL_DATA_API_KEY` = your free key from football-data.org, then **Redeploy**. The first opening of the team picker then takes up to a minute, because the free key allows 10 requests a minute and the team list needs 12.

Vercel's Hobby plan is for non-commercial use: fine for testing, but the store launch with ads needs a paid host (PUBLISHING.md, section 2).

## One-time setup (10 minutes, all in the browser)

1. Push the project to GitHub (GitHub Desktop is the easiest way if you haven't used git).
2. In the repository: **Settings → Pages → Build and deployment → Source: GitHub Actions**.
3. **Settings → Secrets and variables → Actions → Variables tab → New repository variable**: name `API_BASE_URL`, value your backend address, for example `https://api.your-domain.com` (no slash at the end).
4. **Actions** tab → **Web version for testers** → **Run workflow**. It takes about 5 minutes. When it's green, the link is shown on the run's page:
   `https://<your-username>.github.io/<repository-name>/`

Send that link. From then on, every push to `main` updates the site automatically. The workflow is in [.github/workflows/web-testers.yml](.github/workflows/web-testers.yml).

If the backend only allows some websites (`CORS_ORIGINS` in its settings), add `https://<your-username>.github.io` to the list. The default allows every website.

## What your friends see

When they open the link in Safari, a short guide appears instead of the app:

1. Tap the Share button (at the bottom of Safari; behind `•••` on newer iPhones).
2. Tap **Add to Home Screen**.
3. Tap **Add**.
4. Open BGoal from the Home Screen.

It's shown in English, French or Arabic, following the phone's language. If they opened the link inside Instagram, Facebook or similar, there's an extra first step to open it in Safari. On Android, Chrome shows an **Install BGoal** button instead. Anyone who'd rather not install it can tap **Continue in the browser**. Once opened from the Home Screen, the guide never shows again.

Something you can paste in a message:

> Can you test my app? Open this link on your iPhone in Safari and follow the 4 steps on screen (20 seconds): https://<your-username>.github.io/<repository-name>/

## Building it yourself instead (optional)

With Flutter installed, from `app/`:

```bash
flutter create --platforms web --org com.bgoal --project-name livescores .
```

```bash
flutter build web --release --base-href /<repository-name>/ --dart-define=API_BASE_URL=https://api.your-domain.com --dart-define=ADS=false
```

The site is in `app/build/web/`. Any static host works: you can also drag that folder onto [Netlify Drop](https://app.netlify.com/drop) (sign in with a free account so the site isn't deleted). For a host that serves the site at its root, use `--base-href /`.

To try it on your computer: `flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000` with the backend running locally.
