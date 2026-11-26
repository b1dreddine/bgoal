"""Read paths used by the API. They go Redis -> provider and never write match state,
which belongs to the worker (otherwise the worker could miss a score change it should notify)."""
from collections import Counter
from datetime import date, datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo

from sqlalchemy.ext.asyncio import AsyncSession

from app import cache, repository
from app.config import get_settings
from app.domain import Match, MatchStatus, Team
from app.providers import get_provider

LIVE_KEY = "matches:live"
INTERNATIONAL_CODES = {"CL", "EL", "EC", "WC", "CLI", "UCL"}


def _day_ttl(day: date) -> int:
    today = datetime.now(timezone.utc).date()
    if abs((day - today).days) <= 1:
        return 300
    return 6 * 3600 if day < today else 3600


async def _matches_for_utc_day(day: date) -> dict:
    async def fetch():
        return [m.model_dump(mode="json") for m in await get_provider().get_matches_by_date(day)]
    return await cache.cached(f"matches:date:{day.isoformat()}", _day_ttl(day), fetch)


async def live_matches() -> dict:
    """Written by the worker every poll; falls back to the provider if no worker is running."""
    async def fetch():
        return [m.model_dump(mode="json") for m in await get_provider().get_live_matches()]
    return await cache.cached(LIVE_KEY, max(get_settings().live_poll_seconds, 10), fetch)


async def _live_overlay() -> dict | None:
    """Live scores to lay over cached matches: the worker's latest poll, or, with no worker
    (serverless), a provider call cached for one poll interval."""
    if get_settings().serverless:
        try:
            return await live_matches()
        except Exception:
            return None  # the cached match data is still shown
    return await cache.get_entry(LIVE_KEY)


async def matches_for_local_date(day: date, tz_name: str) -> dict:
    """Matches whose kickoff falls on `day` in the user's timezone.

    A local day spans two UTC days for any non-UTC timezone, so both are fetched (and cached).
    Live data from the worker is overlaid so scores are never older than one poll.
    """
    tz = ZoneInfo(tz_name)
    start = datetime.combine(day, time.min, tzinfo=tz).astimezone(timezone.utc)
    end = datetime.combine(day + timedelta(days=1), time.min, tzinfo=tz).astimezone(timezone.utc)
    utc_days = sorted({start.date(), (end - timedelta(seconds=1)).date()})

    by_id: dict[int, dict] = {}
    updated, stale = [], False
    for d in utc_days:
        entry = await _matches_for_utc_day(d)
        updated.append(entry["updated_at"])
        stale = stale or entry["stale"]
        for m in entry["data"]:
            by_id[m["id"]] = m

    live = await _live_overlay()
    if live:
        for m in live["data"]:
            if m["id"] in by_id:
                by_id[m["id"]] = _merge_live(by_id[m["id"]], m)

    matches = [m for m in by_id.values() if start <= datetime.fromisoformat(m["utc_kickoff"]) < end]
    matches.sort(key=lambda m: (m["utc_kickoff"], m["competition"]["name"]))
    return {"data": matches, "updated_at": min(updated) if updated else cache.now_iso(), "stale": stale}


def _merge_live(base: dict, live: dict) -> dict:
    merged = {**base}
    for k in ("status", "minute", "injury_time", "score"):
        merged[k] = live[k]
    if live.get("has_event_data"):
        merged["events"] = live["events"]
        merged["has_event_data"] = True
    return merged


async def match_detail(match_id: int) -> dict:
    async def fetch():
        return (await get_provider().get_match(match_id)).model_dump(mode="json")

    entry = await cache.get_entry(f"match:{match_id}")
    if entry is None:
        entry = await cache.cached(f"match:{match_id}", 60, fetch)
        # Finished matches change rarely (late scorer corrections) - keep them longer.
        if entry["data"]["status"] in (MatchStatus.FINISHED.value, MatchStatus.POSTPONED.value,
                                       MatchStatus.CANCELLED.value, MatchStatus.ABANDONED.value):
            await cache.put(f"match:{match_id}", entry["data"], 3600, entry["updated_at"])
    else:
        entry = {**entry, "stale": False}

    live = await _live_overlay()
    if live:
        for m in live["data"]:
            if m["id"] == match_id:
                return {"data": _merge_live(entry["data"], m), "updated_at": live["updated_at"], "stale": False}
    return entry


async def search_teams(session: AsyncSession, q: str) -> list[dict]:
    teams = await repository.search_teams(session, q)
    provider = get_provider()
    if len(teams) < 5 and provider.supports_team_search and len(q) >= 3:
        entry = await cache.cached(f"teams:search:{q.lower()}", 86400,
                                   lambda: _remote_search(provider, q))
        known = {t.id for t in teams}
        remote = [t for t in entry["data"] if t["id"] not in known]
        if remote:
            await repository.upsert_teams(session, [Team.model_validate(t) for t in remote])
            await session.commit()
        return [t.model_dump() for t in teams] + remote
    return [t.model_dump() for t in teams]


async def _remote_search(provider, q: str) -> list[dict]:
    return [t.model_dump() for t in await provider.search_teams(q)]


async def team_overview(session: AsyncSession, team_id: int) -> dict:
    provider = get_provider()

    team = await repository.get_team(session, team_id)
    if team is None:
        entry = await cache.cached(f"team:{team_id}", 86400, lambda: _dump(provider.get_team(team_id)))
        team_data = entry["data"]
    else:
        team_data = team.model_dump()

    fixtures_entry = await cache.cached(
        f"team:{team_id}:matches", 600,
        lambda: _dump_list(provider.get_team_matches(team_id)),
    )
    # Fixtures are cached for 10 minutes; overlay the worker's live data so an
    # in-play score is never older than one poll.
    live = await _live_overlay()
    live_by_id = {m["id"]: m for m in live["data"]} if live else {}
    fixtures = [Match.model_validate(_merge_live(m, live_by_id[m["id"]]) if m["id"] in live_by_id else m)
                for m in fixtures_entry["data"]]
    now = datetime.now(timezone.utc)
    recent = [m for m in fixtures if m.status == MatchStatus.FINISHED]
    upcoming = [m for m in fixtures if m.status != MatchStatus.FINISHED and m.utc_kickoff >= now - timedelta(hours=3)]

    standing = None
    league = await _domestic_league(session, team_id, fixtures)
    if league is not None:
        table = await cache.cached(f"standings:{league.id}", 3600,
                                   lambda: _dump_list(provider.get_standings(league.id)))
        for row in table["data"]:
            if row["team"]["id"] == team_id:
                standing = {**row, "competition": league.model_dump()}
                break

    return {
        "data": {
            "team": team_data,
            "recent": [m.model_dump(mode="json") for m in recent[-5:]],
            "upcoming": [m.model_dump(mode="json") for m in upcoming[:5]],
            "standing": standing,
        },
        "updated_at": fixtures_entry["updated_at"],
        "stale": fixtures_entry["stale"],
    }


async def browse_teams(session: AsyncSession) -> list[dict]:
    """Teams grouped by competition, domestic leagues first, for the app's team picker."""
    groups = await repository.competition_teams(session)
    if not groups and get_settings().serverless:
        # No worker syncs teams here: load them on first use, then they're in the database.
        for comp, teams in await get_provider().list_competition_teams():
            await repository.upsert_competitions(session, [comp])
            await repository.upsert_teams(session, teams, comp.id)
        await session.commit()
        groups = await repository.competition_teams(session)
    groups.sort(key=lambda g: (g[0].code in INTERNATIONAL_CODES, g[0].name))
    return [{"competition": c.model_dump(), "teams": [t.model_dump() for t in teams]} for c, teams in groups]


async def _domestic_league(session: AsyncSession, team_id: int, fixtures: list[Match]):
    comps = [c for c in await repository.team_competitions(session, team_id) if c.code not in INTERNATIONAL_CODES]
    if comps:
        return comps[0]
    counts = Counter(m.competition.id for m in fixtures if m.competition.code not in INTERNATIONAL_CODES)
    if not counts:
        return None
    best = counts.most_common(1)[0][0]
    return next(m.competition for m in fixtures if m.competition.id == best)


async def standings(competition_id: int) -> dict:
    return await cache.cached(f"standings:{competition_id}", 3600,
                              lambda: _dump_list(get_provider().get_standings(competition_id)))


async def _dump(coro):
    return (await coro).model_dump(mode="json")


async def _dump_list(coro):
    return [x.model_dump(mode="json") for x in await coro]
