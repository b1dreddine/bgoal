"""API-Football (api-sports.io) v3 adapter.

Full detail (scorers, assists, cards, subs, VAR, lineups, stats) in one /fixtures?id= call.
The free plan is 100 requests/day, which is too little for live polling - use a paid plan
if you switch PROVIDER=api_football in production.
Docs: https://www.api-football.com/documentation-v3
"""
from datetime import date, datetime, timezone

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
from app.providers.base import HttpProvider, ProviderError

STATUS_MAP = {
    "TBD": MatchStatus.SCHEDULED,
    "NS": MatchStatus.SCHEDULED,
    "1H": MatchStatus.LIVE,
    "2H": MatchStatus.LIVE,
    "LIVE": MatchStatus.LIVE,
    "HT": MatchStatus.HALFTIME,
    "ET": MatchStatus.EXTRA_TIME,
    "BT": MatchStatus.EXTRA_TIME,
    "P": MatchStatus.PENALTIES,
    "FT": MatchStatus.FINISHED,
    "AET": MatchStatus.FINISHED,
    "PEN": MatchStatus.FINISHED,
    "AWD": MatchStatus.FINISHED,
    "WO": MatchStatus.FINISHED,
    "SUSP": MatchStatus.SUSPENDED,
    "INT": MatchStatus.SUSPENDED,
    "PST": MatchStatus.POSTPONED,
    "CANC": MatchStatus.CANCELLED,
    "ABD": MatchStatus.ABANDONED,
}


def _team(raw: dict) -> Team:
    return Team(id=raw["id"], name=raw.get("name") or "?", short_name=raw.get("code") or raw.get("name"),
                 tla=raw.get("code"), crest_url=raw.get("logo"), country=raw.get("country"))


def _event(raw: dict) -> MatchEvent | None:
    kind, detail = (raw.get("type") or "").lower(), raw.get("detail") or ""
    if kind == "goal":
        etype = {"Own Goal": EventType.OWN_GOAL, "Penalty": EventType.PENALTY_GOAL,
                 "Missed Penalty": EventType.MISSED_PENALTY}.get(detail, EventType.GOAL)
    elif kind == "card":
        etype = (EventType.SECOND_YELLOW if "second" in detail.lower()
                 else EventType.RED_CARD if "red" in detail.lower() else EventType.YELLOW_CARD)
    elif kind == "subst":
        etype = EventType.SUBSTITUTION
    elif kind == "var":
        etype = EventType.VAR
    else:
        return None
    # For substitutions API-Football puts the player going off in `player`, the one coming on in `assist`.
    t, player, assist = raw.get("time") or {}, raw.get("player") or {}, raw.get("assist") or {}
    return MatchEvent(
        type=etype,
        minute=t.get("elapsed"),
        extra_minute=t.get("extra"),
        team_id=(raw.get("team") or {}).get("id"),
        player_id=player.get("id"),
        player_name=player.get("name"),
        related_player_id=assist.get("id"),
        related_player_name=assist.get("name"),
        detail=detail or None,
    )


def _pct(value) -> int | None:
    if value is None:
        return None
    try:
        return int(str(value).rstrip("%"))
    except ValueError:
        return None


def _stats(raw_list: list[dict], team_id: int) -> TeamStats:
    for entry in raw_list:
        if (entry.get("team") or {}).get("id") != team_id:
            continue
        s = {item["type"]: item.get("value") for item in entry.get("statistics", [])}
        return TeamStats(
            possession=_pct(s.get("Ball Possession")),
            shots=_pct(s.get("Total Shots")),
            shots_on_target=_pct(s.get("Shots on Goal")),
            corners=_pct(s.get("Corner Kicks")),
            fouls=_pct(s.get("Fouls")),
            yellow_cards=_pct(s.get("Yellow Cards")),
            red_cards=_pct(s.get("Red Cards")),
        )
    return TeamStats()


def _lineup(raw: dict) -> Lineup:
    def player(p: dict) -> LineupPlayer:
        p = p.get("player") or p
        return LineupPlayer(id=p.get("id"), name=p.get("name", "?"), number=p.get("number"),
                            position=p.get("pos"), grid=p.get("grid"))
    return Lineup(
        team_id=raw["team"]["id"],
        formation=raw.get("formation"),
        coach=(raw.get("coach") or {}).get("name"),
        starting=[player(p) for p in raw.get("startXI") or []],
        substitutes=[player(p) for p in raw.get("substitutes") or []],
    )


def parse_fixture(raw: dict) -> Match:
    fx, league, teams = raw["fixture"], raw["league"], raw["teams"]
    status_short = (fx.get("status") or {}).get("short", "NS")
    goals, score = raw.get("goals") or {}, raw.get("score") or {}
    pens = score.get("penalty") or {}
    duration = (Duration.PENALTIES if status_short in ("P", "PEN") or pens.get("home") is not None
                else Duration.EXTRA_TIME if status_short in ("ET", "BT", "AET") else Duration.REGULAR)
    home, away = _team(teams["home"]), _team(teams["away"])
    events = [e for e in (_event(ev) for ev in raw.get("events") or []) if e]
    stats_raw = raw.get("statistics") or []
    return Match(
        id=fx["id"],
        competition=Competition(id=league["id"], name=league.get("name", "?"), country=league.get("country"),
                                emblem_url=league.get("logo")),
        utc_kickoff=datetime.fromtimestamp(fx["timestamp"], tz=timezone.utc) if "timestamp" in fx
        else datetime.fromisoformat(fx["date"]).astimezone(timezone.utc),
        status=STATUS_MAP.get(status_short, MatchStatus.SCHEDULED),
        minute=(fx.get("status") or {}).get("elapsed"),
        injury_time=(fx.get("status") or {}).get("extra"),
        home=home,
        away=away,
        score=Score(
            home=goals.get("home"),
            away=goals.get("away"),
            ht_home=(score.get("halftime") or {}).get("home"),
            ht_away=(score.get("halftime") or {}).get("away"),
            pen_home=pens.get("home"),
            pen_away=pens.get("away"),
            duration=duration,
        ),
        venue=(fx.get("venue") or {}).get("name"),
        events=events,
        lineups=[_lineup(lu) for lu in raw.get("lineups") or []],
        stats=MatchStats(home=_stats(stats_raw, home.id), away=_stats(stats_raw, away.id)) if stats_raw else None,
        has_event_data="events" in raw,
    )


class ApiFootballProvider(HttpProvider):
    name = "api_football"
    base_url = "https://v3.football.api-sports.io"
    supports_events = supports_lineups = supports_stats = supports_team_search = True

    def __init__(self, api_key: str, leagues: list[int], season: int, per_minute: int = 10):
        super().__init__({"x-apisports-key": api_key}, per_minute)
        self.leagues, self.season = leagues, season

    async def _response(self, path: str, params: dict) -> list[dict]:
        data = await self._get(path, params)
        if data.get("errors"):
            raise ProviderError(f"api_football {path}: {data['errors']}")
        return data.get("response", [])

    async def get_matches_by_date(self, day: date) -> list[Match]:
        return [parse_fixture(f) for f in await self._response("/fixtures", {"date": day.isoformat(), "timezone": "UTC"})]

    async def get_live_matches(self) -> list[Match]:
        # Live fixtures include events, so goal scorers arrive with the score change.
        return [parse_fixture(f) for f in await self._response("/fixtures", {"live": "all"})]

    async def get_match(self, match_id: int) -> Match:
        rows = await self._response("/fixtures", {"id": match_id})
        if not rows:
            raise ProviderError(f"api_football fixture {match_id} not found")
        return parse_fixture(rows[0])

    async def get_team(self, team_id: int) -> Team:
        rows = await self._response("/teams", {"id": team_id})
        if not rows:
            raise ProviderError(f"api_football team {team_id} not found")
        return _team({**rows[0]["team"]})

    async def search_teams(self, query: str) -> list[Team]:
        if len(query) < 3:  # API-Football rejects shorter searches
            return []
        return [_team(r["team"]) for r in await self._response("/teams", {"search": query})]

    async def get_team_matches(self, team_id: int, upcoming: int = 5, recent: int = 5) -> list[Match]:
        last = await self._response("/fixtures", {"team": team_id, "last": recent, "timezone": "UTC"})
        nxt = await self._response("/fixtures", {"team": team_id, "next": upcoming, "timezone": "UTC"})
        return sorted((parse_fixture(f) for f in last + nxt), key=lambda m: m.utc_kickoff)

    async def get_standings(self, competition_id: int) -> list[StandingRow]:
        rows = await self._response("/standings", {"league": competition_id, "season": self.season})
        result: list[StandingRow] = []
        for league in rows:
            for group in league["league"].get("standings", []):
                for r in group:
                    allg = r.get("all") or {}
                    goals = allg.get("goals") or {}
                    result.append(StandingRow(
                        position=r["rank"], team=_team(r["team"]), played=allg.get("played", 0),
                        won=allg.get("win", 0), draw=allg.get("draw", 0), lost=allg.get("lose", 0),
                        goals_for=goals.get("for", 0), goals_against=goals.get("against", 0),
                        goal_difference=r.get("goalsDiff", 0), points=r.get("points", 0),
                        form=r.get("form"), group=r.get("group"),
                    ))
        return result

    async def list_competition_teams(self) -> list[tuple[Competition, list[Team]]]:
        result = []
        for league_id in self.leagues:
            rows = await self._response("/teams", {"league": league_id, "season": self.season})
            info = await self._response("/leagues", {"id": league_id})
            lg = info[0] if info else {"league": {"id": league_id, "name": str(league_id)}, "country": {}}
            comp = Competition(id=league_id, name=lg["league"]["name"], country=(lg.get("country") or {}).get("name"),
                               emblem_url=lg["league"].get("logo"))
            result.append((comp, [_team(r["team"]) for r in rows]))
        return result
