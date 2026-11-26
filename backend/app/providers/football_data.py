"""football-data.org v4 adapter.

The free tier (10 requests/minute, ~12 top competitions) gives live scores, status and
minute. Scorers, cards, lineups and stats are only included on paid tiers; when they are
missing the backend still detects goals from score changes.
Docs: https://www.football-data.org/documentation/api
"""
import asyncio
import logging
from datetime import date, datetime, timedelta, timezone

from app.domain import (
    Competition,
    Duration,
    EventType,
    Lineup,
    LineupPlayer,
    Match,
    MatchEvent,
    MatchStats,
    MatchStatus,
    Score,
    StandingRow,
    Team,
    TeamStats,
)
from app.providers.base import HttpProvider

log = logging.getLogger(__name__)

STATUS_MAP = {
    "SCHEDULED": MatchStatus.SCHEDULED,
    "TIMED": MatchStatus.SCHEDULED,
    "IN_PLAY": MatchStatus.LIVE,
    "PAUSED": MatchStatus.HALFTIME,
    "EXTRA_TIME": MatchStatus.EXTRA_TIME,
    "PENALTY_SHOOTOUT": MatchStatus.PENALTIES,
    "FINISHED": MatchStatus.FINISHED,
    "AWARDED": MatchStatus.FINISHED,
    "SUSPENDED": MatchStatus.SUSPENDED,
    "POSTPONED": MatchStatus.POSTPONED,
    "CANCELLED": MatchStatus.CANCELLED,
}

DURATION_MAP = {
    "REGULAR": Duration.REGULAR,
    "EXTRA_TIME": Duration.EXTRA_TIME,
    "PENALTY_SHOOTOUT": Duration.PENALTIES,
}


def _parse_minute(raw) -> tuple[int | None, int | None]:
    """football-data returns minute as 67, "67" or "45+2"."""
    if raw is None:
        return None, None
    if isinstance(raw, int):
        return raw, None
    text = str(raw).strip().rstrip("'")
    if "+" in text:
        base, extra = text.split("+", 1)
        return int(base), int(extra or 0)
    return (int(text), None) if text.isdigit() else (None, None)


def _team(raw: dict) -> Team:
    return Team(
        id=raw["id"],
        name=raw.get("name") or raw.get("shortName") or "?",
        short_name=raw.get("shortName"),
        tla=raw.get("tla"),
        crest_url=raw.get("crest"),
        country=(raw.get("area") or {}).get("name"),
    )


def _competition(raw: dict, area: dict | None = None) -> Competition:
    return Competition(
        id=raw["id"],
        name=raw.get("name", "?"),
        code=raw.get("code"),
        country=(area or raw.get("area") or {}).get("name"),
        emblem_url=raw.get("emblem"),
    )


def _score(raw: dict) -> Score:
    duration = DURATION_MAP.get(raw.get("duration") or "REGULAR", Duration.REGULAR)
    full = raw.get("fullTime") or {}
    half = raw.get("halfTime") or {}
    regular = raw.get("regularTime") or {}
    extra = raw.get("extraTime") or {}
    pens = raw.get("penalties") or {}
    home, away = full.get("home"), full.get("away")
    # After extra time / shootouts fullTime can include shootout goals; rebuild the real score.
    if duration != Duration.REGULAR and regular.get("home") is not None:
        home = regular["home"] + (extra.get("home") or 0)
        away = regular["away"] + (extra.get("away") or 0)
    elif duration == Duration.PENALTIES and pens.get("home") is not None and home is not None:
        home, away = home - pens["home"], away - pens["away"]
    return Score(
        home=home,
        away=away,
        ht_home=half.get("home"),
        ht_away=half.get("away"),
        pen_home=pens.get("home"),
        pen_away=pens.get("away"),
        duration=duration,
    )


def _lineup(team_raw: dict) -> Lineup | None:
    if not team_raw.get("lineup"):
        return None
    to_player = lambda p: LineupPlayer(id=p.get("id"), name=p.get("name", "?"), number=p.get("shirtNumber"), position=p.get("position"))  # noqa: E731
    return Lineup(
        team_id=team_raw["id"],
        formation=team_raw.get("formation"),
        coach=(team_raw.get("coach") or {}).get("name"),
        starting=[to_player(p) for p in team_raw.get("lineup", [])],
        substitutes=[to_player(p) for p in team_raw.get("bench", [])],
    )


def _team_stats(raw: dict | None) -> TeamStats:
    raw = raw or {}
    return TeamStats(
        possession=raw.get("ball_possession"),
        shots=raw.get("shots"),
        shots_on_target=raw.get("shots_on_goal"),
        corners=raw.get("corner_kicks"),
        fouls=raw.get("fouls"),
        yellow_cards=raw.get("yellow_cards"),
        red_cards=raw.get("red_cards"),
    )


def parse_match(raw: dict) -> Match:
    status = STATUS_MAP.get(raw.get("status", ""), MatchStatus.SCHEDULED)
    score = _score(raw.get("score") or {})
    # PAUSED before extra time is a break, not half-time.
    if status == MatchStatus.HALFTIME and score.duration != Duration.REGULAR:
        status = MatchStatus.EXTRA_TIME
    minute, injury = _parse_minute(raw.get("minute"))

    events: list[MatchEvent] = []
    has_event_data = any(k in raw for k in ("goals", "bookings", "substitutions"))
    for g in raw.get("goals") or []:
        etype = {"OWN": EventType.OWN_GOAL, "PENALTY": EventType.PENALTY_GOAL}.get(g.get("type"), EventType.GOAL)
        events.append(MatchEvent(
            type=etype,
            minute=g.get("minute"),
            extra_minute=g.get("injuryTime"),
            team_id=(g.get("team") or {}).get("id"),
            player_id=(g.get("scorer") or {}).get("id"),
            player_name=(g.get("scorer") or {}).get("name"),
            related_player_id=(g.get("assist") or {}).get("id"),
            related_player_name=(g.get("assist") or {}).get("name"),
        ))
    for b in raw.get("bookings") or []:
        etype = {"YELLOW_RED": EventType.SECOND_YELLOW, "RED": EventType.RED_CARD}.get(b.get("card"), EventType.YELLOW_CARD)
        events.append(MatchEvent(
            type=etype,
            minute=b.get("minute"),
            team_id=(b.get("team") or {}).get("id"),
            player_id=(b.get("player") or {}).get("id"),
            player_name=(b.get("player") or {}).get("name"),
        ))
    for s in raw.get("substitutions") or []:
        events.append(MatchEvent(
            type=EventType.SUBSTITUTION,
            minute=s.get("minute"),
            team_id=(s.get("team") or {}).get("id"),
            player_id=(s.get("playerOut") or {}).get("id"),
            player_name=(s.get("playerOut") or {}).get("name"),
            related_player_id=(s.get("playerIn") or {}).get("id"),
            related_player_name=(s.get("playerIn") or {}).get("name"),
        ))
    events.sort(key=lambda e: ((e.minute or 0), (e.extra_minute or 0)))

    home_raw, away_raw = raw["homeTeam"], raw["awayTeam"]
    lineups = [lu for lu in (_lineup(home_raw), _lineup(away_raw)) if lu]
    stats = None
    if home_raw.get("statistics") or away_raw.get("statistics"):
        stats = MatchStats(home=_team_stats(home_raw.get("statistics")), away=_team_stats(away_raw.get("statistics")))

    return Match(
        id=raw["id"],
        competition=_competition(raw["competition"], raw.get("area")),
        utc_kickoff=datetime.fromisoformat(raw["utcDate"].replace("Z", "+00:00")),
        status=status,
        minute=minute,
        injury_time=injury or raw.get("injuryTime"),
        home=_team(home_raw),
        away=_team(away_raw),
        score=score,
        venue=raw.get("venue"),
        events=events,
        lineups=lineups,
        stats=stats,
        has_event_data=has_event_data,
    )


class FootballDataProvider(HttpProvider):
    name = "football_data"
    base_url = "https://api.football-data.org/v4"

    def __init__(self, api_key: str, competitions: list[str], per_minute: int = 10):
        super().__init__({"X-Auth-Token": api_key}, per_minute)
        self.competitions = competitions
        self._comp_filter = ",".join(competitions)

    async def get_matches_by_date(self, day: date) -> list[Match]:
        data = await self._get("/matches", {
            "dateFrom": day.isoformat(),
            "dateTo": (day + timedelta(days=1)).isoformat(),
            "competitions": self._comp_filter,
        })
        matches = [parse_match(m) for m in data.get("matches", [])]
        return [m for m in matches if m.utc_kickoff.date() == day]

    async def get_live_matches(self) -> list[Match]:
        data = await self._get("/matches", {"status": "LIVE", "competitions": self._comp_filter})
        return [parse_match(m) for m in data.get("matches", [])]

    async def get_match(self, match_id: int) -> Match:
        data = await self._get(f"/matches/{match_id}")
        return parse_match(data)

    async def get_team(self, team_id: int) -> Team:
        return _team(await self._get(f"/teams/{team_id}"))

    async def get_team_matches(self, team_id: int, upcoming: int = 5, recent: int = 5) -> list[Match]:
        today = datetime.now(timezone.utc).date()
        data = await self._get(f"/teams/{team_id}/matches", {
            "dateFrom": (today - timedelta(days=90)).isoformat(),
            "dateTo": (today + timedelta(days=90)).isoformat(),
        })
        matches = sorted((parse_match(m) for m in data.get("matches", [])), key=lambda m: m.utc_kickoff)
        done = [m for m in matches if m.status == MatchStatus.FINISHED][-recent:]
        rest = [m for m in matches if m.status != MatchStatus.FINISHED][:upcoming + 1]
        return done + rest

    async def get_standings(self, competition_id: int) -> list[StandingRow]:
        data = await self._get(f"/competitions/{competition_id}/standings")
        rows: list[StandingRow] = []
        for table in data.get("standings", []):
            if table.get("type") != "TOTAL":
                continue
            for r in table.get("table", []):
                rows.append(StandingRow(
                    position=r["position"],
                    team=_team(r["team"]),
                    played=r.get("playedGames", 0),
                    won=r.get("won", 0),
                    draw=r.get("draw", 0),
                    lost=r.get("lost", 0),
                    goals_for=r.get("goalsFor", 0),
                    goals_against=r.get("goalsAgainst", 0),
                    goal_difference=r.get("goalDifference", 0),
                    points=r.get("points", 0),
                    form=r.get("form"),
                    group=table.get("group"),
                ))
        return rows

    async def list_competition_teams(self) -> list[tuple[Competition, list[Team]]]:
        # In parallel: the rate limiter lets a burst through, so the app's team picker
        # doesn't wait for one league after another.
        async def one(code: str) -> tuple[Competition, list[Team]]:
            data = await self._get(f"/competitions/{code}/teams")
            comp = _competition(data["competition"], data.get("area") or (data["competition"].get("area")))
            return comp, [_team(t) for t in data.get("teams", [])]

        return list(await asyncio.gather(*(one(code) for code in self.competitions)))
