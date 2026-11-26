"""Offline provider that simulates matches from the wall clock.

Lets you run the backend and the app with no API key: today always has a match in the
first half, one at half-time, one finished, and one kicking off in ~15 minutes, and
their scores and events advance in real time.
"""
import random
from datetime import date, datetime, time, timedelta, timezone

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
from app.providers.base import FootballProvider, ProviderError

CREST = "https://crests.football-data.org/{}.png"

COMPETITIONS = {
    2021: Competition(id=2021, name="Premier League", code="PL", country="England", emblem_url="https://crests.football-data.org/PL.png"),
    2014: Competition(id=2014, name="Primera Division", code="PD", country="Spain", emblem_url="https://crests.football-data.org/PD.png"),
    2015: Competition(id=2015, name="Ligue 1", code="FL1", country="France", emblem_url="https://crests.football-data.org/FL1.png"),
}

_TEAM_DATA = {
    2021: [(57, "Arsenal FC", "Arsenal", "ARS"), (61, "Chelsea FC", "Chelsea", "CHE"), (64, "Liverpool FC", "Liverpool", "LIV"),
           (65, "Manchester City FC", "Man City", "MCI"), (66, "Manchester United FC", "Man United", "MUN"),
           (73, "Tottenham Hotspur FC", "Tottenham", "TOT"), (67, "Newcastle United FC", "Newcastle", "NEW"),
           (58, "Aston Villa FC", "Aston Villa", "AVL")],
    2014: [(81, "FC Barcelona", "Barça", "FCB"), (86, "Real Madrid CF", "Real Madrid", "RMA"),
           (78, "Club Atlético de Madrid", "Atleti", "ATM"), (559, "Sevilla FC", "Sevilla", "SEV"),
           (95, "Valencia CF", "Valencia", "VAL"), (94, "Villarreal CF", "Villarreal", "VIL")],
    2015: [(524, "Paris Saint-Germain FC", "PSG", "PSG"), (516, "Olympique de Marseille", "Marseille", "MAR"),
           (523, "Olympique Lyonnais", "Lyon", "OL"), (548, "AS Monaco FC", "Monaco", "ASM")],
}
TEAMS: dict[int, Team] = {}
TEAM_COMP: dict[int, int] = {}
for _cid, _rows in _TEAM_DATA.items():
    for _tid, _name, _short, _tla in _rows:
        TEAMS[_tid] = Team(id=_tid, name=_name, short_name=_short, tla=_tla, crest_url=CREST.format(_tid),
                           country=COMPETITIONS[_cid].country)
        TEAM_COMP[_tid] = _cid

SURNAMES = ["Silva", "Martin", "Kane", "Diaz", "Müller", "Saka", "Rossi", "Haddad", "Benali", "Okafor", "Novak",
            "Fernandes", "Dubois", "Garcia", "Johnson", "Larsen", "Mendy", "Rahman", "Costa", "Ito", "Walker", "Ziyech"]


def _squad(team: Team) -> list[LineupPlayer]:
    rng = random.Random(team.id)
    positions = ["G"] + ["D"] * 4 + ["M"] * 3 + ["F"] * 3 + ["G", "D", "D", "M", "M", "F", "F"]
    names = rng.sample(SURNAMES, k=18)
    return [LineupPlayer(id=team.id * 100 + i, name=f"{chr(65 + rng.randrange(26))}. {names[i]}", number=i + 1,
                         position=positions[i]) for i in range(18)]


def _fixtures_for(day: date, now: datetime) -> list[tuple[int, int, int, datetime]]:
    """(match_id, home_id, away_id, kickoff) for a given UTC day."""
    rng = random.Random(day.toordinal())
    result = []
    today = now.date()
    for cid, rows in _TEAM_DATA.items():
        ids = [r[0] for r in rows]
        rng.shuffle(ids)
        for i in range(0, len(ids) - 1, 2):
            n = len(result)
            if day == today:
                # Relative kickoffs so there is always something live to look at.
                anchor = now.replace(second=0, microsecond=0)
                offsets = [-35, -55, -130, 14, 90, 180, -200, 240, 300]
                kickoff = anchor + timedelta(minutes=offsets[n % len(offsets)])
                if kickoff.date() != day:
                    kickoff = datetime.combine(day, time(12 + n % 10), tzinfo=timezone.utc)
            else:
                kickoff = datetime.combine(day, time([12, 14, 16, 19, 20][n % 5], [0, 30][n % 2]), tzinfo=timezone.utc)
            match_id = int(day.strftime("%Y%m%d")) * 100 + n
            result.append((match_id, ids[i], ids[i + 1], kickoff))
    return result


def _simulate(match_id: int, home: Team, away: Team, kickoff: datetime, now: datetime, detail: bool) -> Match:
    rng = random.Random(match_id)
    elapsed = (now - kickoff).total_seconds() / 60
    if match_id % 50 == 7:  # occasional postponed match to exercise that UI state
        status, minute = MatchStatus.POSTPONED, None
    elif elapsed < 0:
        status, minute = MatchStatus.SCHEDULED, None
    elif elapsed < 45:
        status, minute = MatchStatus.LIVE, int(elapsed) + 1
    elif elapsed < 60:
        status, minute = MatchStatus.HALFTIME, 45
    elif elapsed < 105:
        status, minute = MatchStatus.LIVE, int(elapsed) - 14
    else:
        status, minute = MatchStatus.FINISHED, 90
    played = minute or 0
    if status == MatchStatus.FINISHED:
        played = 90

    squads = {home.id: _squad(home), away.id: _squad(away)}
    script: list[MatchEvent] = []
    for _ in range(rng.randint(0, 5)):
        team = rng.choice([home, away])
        scorer, assist = rng.sample(squads[team.id][5:11], 2)
        kind = rng.choices([EventType.GOAL, EventType.PENALTY_GOAL, EventType.OWN_GOAL], [8, 1, 1])[0]
        script.append(MatchEvent(type=kind, minute=rng.randint(2, 90), team_id=team.id, player_id=scorer.id,
                                 player_name=scorer.name,
                                 related_player_id=assist.id if kind == EventType.GOAL else None,
                                 related_player_name=assist.name if kind == EventType.GOAL else None))
    for _ in range(rng.randint(1, 4)):
        team = rng.choice([home, away])
        p = rng.choice(squads[team.id][1:11])
        kind = rng.choices([EventType.YELLOW_CARD, EventType.RED_CARD], [9, 1])[0]
        script.append(MatchEvent(type=kind, minute=rng.randint(5, 90), team_id=team.id, player_id=p.id, player_name=p.name))
    for team in (home, away):
        for off, on in zip(squads[team.id][8:11], squads[team.id][15:18]):
            script.append(MatchEvent(type=EventType.SUBSTITUTION, minute=rng.randint(55, 85), team_id=team.id,
                                     player_id=off.id, player_name=off.name, related_player_id=on.id,
                                     related_player_name=on.name))
    events = sorted((e for e in script if e.minute <= played), key=lambda e: e.minute)
    if status in (MatchStatus.SCHEDULED, MatchStatus.POSTPONED):
        events = []

    def goals_for(team: Team) -> int:
        return sum(1 for e in events if e.type.is_goal and
                   ((e.team_id == team.id) != (e.type == EventType.OWN_GOAL)))

    started = status not in (MatchStatus.SCHEDULED, MatchStatus.POSTPONED)
    score = Score(home=goals_for(home) if started else None, away=goals_for(away) if started else None,
                  duration=Duration.REGULAR)
    if played >= 45:
        ht = [e for e in events if e.minute <= 45]
        score.ht_home = sum(1 for e in ht if e.type.is_goal and ((e.team_id == home.id) != (e.type == EventType.OWN_GOAL)))
        score.ht_away = sum(1 for e in ht if e.type.is_goal and ((e.team_id == away.id) != (e.type == EventType.OWN_GOAL)))

    lineups, stats = [], None
    if detail and (started or elapsed > -60):
        lineups = [Lineup(team_id=t.id, formation="4-3-3", coach=f"Coach {t.tla}", starting=squads[t.id][:11],
                          substitutes=squads[t.id][11:]) for t in (home, away)]
    if detail and started:
        poss = rng.randint(35, 65)
        f = played / 90
        stats = MatchStats(
            home=TeamStats(possession=poss, shots=int(rng.randint(6, 20) * f), shots_on_target=int(rng.randint(2, 8) * f),
                           corners=int(rng.randint(2, 10) * f)),
            away=TeamStats(possession=100 - poss, shots=int(rng.randint(6, 20) * f),
                           shots_on_target=int(rng.randint(2, 8) * f), corners=int(rng.randint(2, 10) * f)),
        )
    return Match(id=match_id, competition=COMPETITIONS[TEAM_COMP[home.id]], utc_kickoff=kickoff, status=status,
                 minute=minute if status.is_in_play else None, home=home, away=away, score=score,
                 venue=f"{home.short_name} Stadium", events=events, lineups=lineups, stats=stats, has_event_data=True)


class MockProvider(FootballProvider):
    name = "mock"
    supports_events = supports_lineups = supports_stats = True

    def __init__(self, clock=None):
        self._clock = clock or (lambda: datetime.now(timezone.utc))
        # Pinned "now" for today's relative fixtures, so kickoffs don't drift between calls.
        self._anchor = self._clock()

    def _all_for(self, day: date, detail: bool = False) -> list[Match]:
        now = self._clock()
        anchor = self._anchor if day == self._anchor.date() else now
        return [_simulate(mid, TEAMS[h], TEAMS[a], ko, now, detail) for mid, h, a, ko in _fixtures_for(day, anchor)]

    async def get_matches_by_date(self, day: date) -> list[Match]:
        return self._all_for(day)

    async def get_live_matches(self) -> list[Match]:
        now = self._clock()
        matches = self._all_for(now.date(), detail=True) + self._all_for(now.date() - timedelta(days=1), detail=True)
        return [m for m in matches if m.status.is_in_play]

    async def get_match(self, match_id: int) -> Match:
        day = datetime.strptime(str(match_id // 100), "%Y%m%d").date()
        for m in self._all_for(day, detail=True):
            if m.id == match_id:
                return m
        raise ProviderError(f"mock match {match_id} not found")

    async def get_team(self, team_id: int) -> Team:
        if team_id not in TEAMS:
            raise ProviderError(f"mock team {team_id} not found")
        return TEAMS[team_id]

    async def get_team_matches(self, team_id: int, upcoming: int = 5, recent: int = 5) -> list[Match]:
        today = self._clock().date()
        found = []
        for delta in range(-14, 15):
            found += [m for m in self._all_for(today + timedelta(days=delta)) if team_id in (m.home.id, m.away.id)]
        done = [m for m in found if m.status == MatchStatus.FINISHED][-recent:]
        rest = [m for m in found if m.status != MatchStatus.FINISHED][:upcoming + 1]
        return done + rest

    async def get_standings(self, competition_id: int) -> list[StandingRow]:
        rng = random.Random(competition_id)
        team_ids = [r[0] for r in _TEAM_DATA.get(competition_id, [])]
        rows = []
        for tid in team_ids:
            w, d, l = rng.randint(0, 9), rng.randint(0, 4), rng.randint(0, 6)
            gf, ga = rng.randint(w, w * 3 + 3), rng.randint(l, l * 2 + 3)
            rows.append([TEAMS[tid], w + d + l, w, d, l, gf, ga])
        rows.sort(key=lambda r: (r[2] * 3 + r[3], r[5] - r[6]), reverse=True)
        return [StandingRow(position=i + 1, team=t, played=p, won=w, draw=d, lost=l, goals_for=gf, goals_against=ga,
                            goal_difference=gf - ga, points=w * 3 + d)
                for i, (t, p, w, d, l, gf, ga) in enumerate(rows)]

    async def list_competition_teams(self) -> list[tuple[Competition, list[Team]]]:
        return [(COMPETITIONS[cid], [TEAMS[r[0]] for r in rows]) for cid, rows in _TEAM_DATA.items()]
