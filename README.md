# BGoal – live football scores (iOS + Android)

Flutter app + FastAPI backend (PostgreSQL, Redis) + Firebase Cloud Messaging + Google AdMob. Brand: [BRAND.md](BRAND.md). Launching: [PUBLISHING.md](PUBLISHING.md).

| Step | Status |
|---|---|
| 1. Backend + data provider integration | ✅ done (26 tests passing) |
| 2. Home screen (live scores) | ✅ written, see [app/README.md](app/README.md) (not yet compiled: no Flutter SDK on the build machine) |
| 3. Match detail screen | ✅ written (same: not yet compiled) |
| 4. Notifications in the app (FCM, permission, deep links, alert settings) | ✅ written (same: not yet compiled) |
| 5. Onboarding, team search, team screen, settings (theme, language) | ✅ written (same: not yet compiled) |
| 6. App Store / Google Play publishing guide | ✅ [PUBLISHING.md](PUBLISHING.md), with a [privacy policy template](docs/privacy-policy.md) |
| 7. Launch readiness: BGoal identity, icons and splash, AdMob ads with consent, native project setup script | ✅ written (app part not yet compiled) |
| 8. Free web version for iPhone testers (link + Add to Home Screen guide) | ✅ [WEB_TESTING.md](WEB_TESTING.md) (not yet built) |

## Decisions (within the spec)

- **Stack:** Flutter + Python FastAPI.
- **Data provider:** `football-data.org` by default. It's free (10 req/min, 12 top competitions) with live scores, status and minute. Scorers, cards, lineups and stats need one of its paid tiers or **API-Football** (adapter included, set `PROVIDER=api_football`). API-Football's free plan (100 req/day) is too small for live polling. A **mock** provider simulates live matches, so everything runs without any key.
- **Push fan-out:** per-device FCM tokens instead of FCM topics, so quiet hours and the language of each notification are honoured on iOS too. FCM is free either way.
- **Ads:** Google AdMob (banner + one native ad on the home list), with Google's consent tool for GDPR / US-state messages and Apple's tracking prompt. Chosen because it's the standard programmatic network with an official Flutter plugin; other networks can join later through AdMob mediation.
- **IDs:** the API exposes the provider's ids. Switching provider later needs a one-off id mapping (see “Swapping provider”).

## Project structure

```
backend/
  app/
    main.py              FastAPI app (API process)
    worker.py            Poller + event detection + push fan-out (worker process)
    config.py            Settings from environment / .env
    domain.py            Provider-independent models (Match, Team, MatchEvent, ...)
    db.py, models.py     SQLAlchemy engine + tables
    repository.py        DB reads/writes
    cache.py             Redis cache (single-flight + stale fallback)
    services.py          Read paths used by the API
    providers/           Data provider abstraction layer
      base.py              FootballProvider interface, rate limiter, HTTP retry
      football_data.py     football-data.org v4 adapter (default, free)
      api_football.py      API-Football v3 adapter
      mock.py              Offline simulator
    notifications/
      diff.py              Old vs new match state -> notices (pure, unit-tested)
      messages.py          Notification texts in en / fr / ar
      dispatcher.py        Dedupe, subscriber lookup, quiet hours, batching
      sender.py            FCM sender (Android + iOS via APNs) / log sender
    routers/             matches.py, teams.py, devices.py
  db/schema.sql          PostgreSQL schema
  tests/                 pytest suite
  Dockerfile, docker-compose.yml, .env.example
render.yaml              Free hosting on Render for testers (one service, sleeps when idle)
render.production.yaml   Store-launch hosting on Render (always-on worker, Postgres, Redis)
app/                     Flutter app (see app/README.md)
```

## Database schema

Full DDL is in [backend/db/schema.sql](backend/db/schema.sql).

| Table | Purpose |
|---|---|
| `competitions`, `teams`, `team_competitions` | Reference data, plus the team search index (trigram) |
| `matches` | Latest state per match. `snapshot` (JSONB) holds the full normalized match. `score_revision` is bumped when a goal is disallowed. |
| `match_events` | Goals, cards, subs and VAR per match. The key excludes the player, so a scorer reassignment is an update, not a new goal. |
| `devices` | Anonymous device: hashed secret, FCM token, platform, language, timezone, quiet hours |
| `favorite_teams` | Device ↔ team, with one boolean per notification type |
| `favorite_competitions` | Optional favorite leagues |
| `users` | Optional Apple/Google sign-in, for syncing across devices (endpoints come in a later step) |
| `notification_log` | Primary key = dedupe key, so a notification is sent at most once even across restarts or replicas |

## API

All read endpoints return `{"data": ..., "updated_at": ISO-8601, "stale": bool}`. `stale: true` means the provider was unreachable and cached data was served.

| Method | Path | Notes |
|---|---|---|
| GET | `/matches?date=YYYY-MM-DD&tz=Europe/Paris` | Matches on that *local* day. `tz` defaults to UTC. |
| GET | `/matches/live` | Updated by the worker every 15 s |
| GET | `/matches/{id}` | Score, status, events, lineups, stats |
| GET | `/teams/search?q=` | Min. 2 characters |
| GET | `/teams/browse` | Teams of the tracked competitions, grouped by competition, leagues before cups (for the app's team picker) |
| GET | `/teams/{id}` | Team, last 5 results, next 5 fixtures, league position. A match in play carries the worker's live score. |
| GET | `/competitions/{id}/standings` | |
| POST | `/devices` | Register. Returns `id` and a one-time `secret`. |
| GET | `/devices/{id}` | Needs `Authorization: Bearer <secret>` |
| PUT | `/devices/{id}/preferences` | Partial update. Lists you send replace the stored ones. |
| DELETE | `/devices/{id}` | |

Interactive docs: `http://localhost:8000/docs`.

Example registration:

```json
POST /devices
{
  "platform": "ios",
  "fcm_token": "…",
  "language": "fr",
  "timezone": "Europe/Paris",
  "quiet_hours": {"enabled": true, "start": "23:00", "end": "07:00"},
  "favorite_teams": [
    {"team_id": 57, "notifications": {"goals": true, "red_cards": false}}
  ]
}
```

Notification types per team: `starting_soon`, `kickoff`, `goals`, `red_cards`, `half_time`, `full_time`, `var`. Every push carries the data `{"type", "match_id", "deep_link": "bgoal://match/<id>"}`, which the app uses to open the match screen.

## How live detection works

1. Every 15 s the worker fetches live matches, plus any match the DB still thinks is live, which catches full-time.
2. `notifications/diff.py` compares each match with its stored state.
   - **Goals** are detected from **score changes**, so they work on free tiers with no event data. Event data, when present, adds the scorer, minute and assist.
   - **Score goes down** → a “goal disallowed” correction, and `score_revision` is bumped so a re-scored goal gets a fresh dedupe key.
   - Scorer reassigned → the data is updated, no push.
   - Penalty shootouts don't count as goals. Full-time says “(AET)” or “X win 4–3 on penalties”.
   - Postponed, abandoned and cancelled matches each get their own alert.
3. The state is saved first, then `notification_log` is written (the dedupe check), then the push is sent. A crash can lose a push but never duplicates one.
4. Devices are selected per team and notification type, and filtered by quiet hours in each device's timezone. Texts are rendered in each device's language and sent in batches of 500.

Worst-case delay ≈ poll interval (15 s) + provider latency + FCM (~1–2 s), within the 30 s target. With the defaults the worker uses about 5 of football-data's 10 requests per minute.

## Running locally

### Option A: Docker (recommended)

```bash
cd backend
cp .env.example .env          # PROVIDER=mock works with no keys
docker compose up --build
```

API at http://localhost:8000/docs. The worker logs every notification it would send.

### Option B: Python only (no Docker)

You still need PostgreSQL and Redis running locally (or point `DATABASE_URL`/`REDIS_URL` to hosted ones).

```bash
cd backend
python -m venv .venv
.venv/bin/pip install -r requirements-dev.txt      # Windows: .venv\Scripts\pip
uvicorn app.main:app --reload                      # terminal 1
python -m app.worker                               # terminal 2
```

> **Windows note:** if you see `DLL load failed … Nom de fichier ou extension trop long` (filename too long), create the venv in a short path such as `C:\venvs\livescores`.

### Tests

```bash
cd backend
pytest
```

Tests use SQLite and an in-memory Redis, so they need no services.

## Setup: API keys, Firebase, APNs

### 1. Football data

- **football-data.org (free):** register at https://www.football-data.org/client/register. Put the emailed token in `FOOTBALL_DATA_API_KEY` and set `PROVIDER=football_data`.
- **API-Football (optional, paid for live use):** create a key at https://dashboard.api-football.com. Set `API_FOOTBALL_API_KEY`, `PROVIDER=api_football`, and set `PROVIDER_REQUESTS_PER_MINUTE` to your plan's limit.

Keys live only in the backend's environment. The app never talks to the provider.

### 2. Firebase project (free Spark plan is enough)

1. Go to https://console.firebase.google.com, choose **Add project**, and turn off Analytics if you don't need it.
2. **Add an Android app** with package `com.bgoal.livescores` and download `google-services.json` (used by the Flutter app).
3. **Add an iOS app** with bundle id `com.bgoal.livescores` and download `GoogleService-Info.plist` (used by the Flutter app).
4. Open **Project settings → Service accounts → Generate new private key**. Save the file as `backend/secrets/firebase-service-account.json` and set `FIREBASE_CREDENTIALS_FILE=/srv/secrets/firebase-service-account.json` (the Docker path).

### 3. APNs (iOS push)

Use an **APNs Auth Key (.p8)**. It never expires and is simpler than certificates. You need a paid Apple Developer account ($99/yr).

1. Go to https://developer.apple.com/account → **Certificates, IDs & Profiles → Keys → +**, tick **Apple Push Notifications service (APNs)**, then download the `.p8` file (it can only be downloaded once) and note the **Key ID**.
2. Note your **Team ID** (shown at the top right of the developer portal).
3. In Firebase, open **Project settings → Cloud Messaging → Apple app configuration → APNs Authentication Key → Upload**, and enter the .p8 file, Key ID and Team ID.
4. In Xcode, enable the **Push Notifications** and **Background Modes → Remote notifications** capabilities. The app side is in [app/README.md](app/README.md#push-notifications-firebase).

## Hosting

**Free, for testers:** [render.yaml](render.yaml) runs the whole backend as one free Render web service: the API also runs the worker (`RUN_WORKER_IN_API=true`), with a SQLite file (`DATABASE_URL=sqlite+aiosqlite:////tmp/bgoal.db`) and an in-memory cache (`REDIS_URL=memory://`). It sleeps after 15 minutes without visitors and takes about a minute to wake, live scores only update while someone uses it, and there are no pushes. Fine for friends testing the web version ([WEB_TESTING.md](WEB_TESTING.md)), not for the store launch.

**For the store launch:** [render.production.yaml](render.production.yaml) deploys the API (free), Postgres (free) and Redis (free) on Render. The **worker must be an always-on paid instance** (~$7/mo) because free instances sleep and would stop live polling. Choose it with **Blueprint path: render.production.yaml** when creating the Blueprint.

For a fully free alternative, run the API and worker on a free VM such as Oracle Cloud Always Free, using `docker compose`.

Steps on Render: push the repo to GitHub, choose **New → Blueprint**, select the repo, fill in `FOOTBALL_DATA_API_KEY`, and add `firebase-service-account.json` as a **Secret File** on the worker.

## Swapping provider

Write a class implementing `providers/base.py::FootballProvider` that returns `domain.py` models, register it in `providers/__init__.py`, and set `PROVIDER=`. The rest of the backend never sees provider payloads.

Because ids are the provider's, existing favorites need a one-off remap (team name → new id) when switching. This only matters if you switch after launch.
