"""Adapters parse real-shaped payloads into the common model."""
from app.domain import Duration, EventType, MatchStatus
from app.providers.api_football import parse_fixture
from app.providers.football_data import parse_match

FD_MATCH = {
    "id": 498765, "utcDate": "2026-10-28T19:00:00Z", "status": "FINISHED", "minute": None,
    "area": {"name": "Europe"},
    "competition": {"id": 2001, "name": "UEFA Champions League", "code": "CL", "emblem": "x.png"},
    "homeTeam": {"id": 57, "name": "Arsenal FC", "shortName": "Arsenal", "tla": "ARS", "crest": "57.png"},
    "awayTeam": {"id": 86, "name": "Real Madrid CF", "shortName": "Real Madrid", "tla": "RMA", "crest": "86.png"},
    "score": {"winner": "HOME_TEAM", "duration": "PENALTY_SHOOTOUT",
              "fullTime": {"home": 6, "away": 5}, "halfTime": {"home": 1, "away": 0},
              "regularTime": {"home": 1, "away": 1}, "extraTime": {"home": 1, "away": 1},
              "penalties": {"home": 4, "away": 3}},
    "goals": [
        {"minute": 23, "injuryTime": None, "type": "REGULAR", "team": {"id": 57}, "scorer": {"id": 1, "name": "Saka"},
         "assist": {"id": 2, "name": "Ødegaard"}},
        {"minute": 90, "injuryTime": 3, "type": "OWN", "team": {"id": 57}, "scorer": {"id": 3, "name": "Saliba"},
         "assist": None},
    ],
    "bookings": [{"minute": 70, "team": {"id": 86}, "player": {"id": 9, "name": "Rüdiger"}, "card": "YELLOW_RED"}],
    "substitutions": [],
}


def test_football_data_penalty_shootout_score():
    m = parse_match(FD_MATCH)
    assert m.status == MatchStatus.FINISHED
    assert (m.score.home, m.score.away) == (2, 2)  # 1-1 + 1-1 in ET, shootout excluded
    assert (m.score.pen_home, m.score.pen_away) == (4, 3)
    assert m.score.duration == Duration.PENALTIES
    assert [e.type for e in m.events] == [EventType.GOAL, EventType.SECOND_YELLOW, EventType.OWN_GOAL]
    assert m.events[2].extra_minute == 3


def test_football_data_free_tier_without_events():
    raw = {k: v for k, v in FD_MATCH.items() if k not in ("goals", "bookings", "substitutions")}
    raw = {**raw, "status": "IN_PLAY", "minute": "45+2",
           "score": {"duration": "REGULAR", "fullTime": {"home": 1, "away": 0}, "halfTime": {}}}
    m = parse_match(raw)
    assert m.status == MatchStatus.LIVE and (m.minute, m.injury_time) == (45, 2)
    assert m.has_event_data is False and (m.score.home, m.score.away) == (1, 0)


AF_FIXTURE = {
    "fixture": {"id": 1035000, "timestamp": 1793214000, "date": "2026-10-28T19:00:00+00:00",
                "venue": {"name": "Emirates Stadium"}, "status": {"short": "2H", "elapsed": 67, "extra": None}},
    "league": {"id": 39, "name": "Premier League", "country": "England", "logo": "pl.png"},
    "teams": {"home": {"id": 42, "name": "Arsenal", "logo": "a.png"}, "away": {"id": 49, "name": "Chelsea", "logo": "c.png"}},
    "goals": {"home": 2, "away": 1},
    "score": {"halftime": {"home": 1, "away": 1}, "fulltime": {}, "extratime": {}, "penalty": {}},
    "events": [
        {"time": {"elapsed": 67, "extra": None}, "team": {"id": 42}, "player": {"id": 1, "name": "B. Saka"},
         "assist": {"id": 2, "name": "M. Ødegaard"}, "type": "Goal", "detail": "Normal Goal"},
        {"time": {"elapsed": 50, "extra": None}, "team": {"id": 49}, "player": {"id": 5, "name": "R. James"},
         "assist": {}, "type": "Card", "detail": "Red Card"},
        {"time": {"elapsed": 60, "extra": None}, "team": {"id": 49}, "player": {"id": 6, "name": "Out"},
         "assist": {"id": 7, "name": "In"}, "type": "subst", "detail": "Substitution 1"},
        {"time": {"elapsed": 30, "extra": None}, "team": {"id": 42}, "player": {"id": 8, "name": "X"},
         "assist": {}, "type": "Var", "detail": "Goal cancelled"},
    ],
    "statistics": [
        {"team": {"id": 42}, "statistics": [{"type": "Ball Possession", "value": "58%"}, {"type": "Total Shots", "value": 12},
                                            {"type": "Shots on Goal", "value": 5}, {"type": "Corner Kicks", "value": 6}]},
        {"team": {"id": 49}, "statistics": [{"type": "Ball Possession", "value": "42%"}]},
    ],
    "lineups": [{"team": {"id": 42}, "formation": "4-3-3", "coach": {"name": "Arteta"},
                 "startXI": [{"player": {"id": 1, "name": "B. Saka", "number": 7, "pos": "F", "grid": "4:3"}}],
                 "substitutes": []}],
}


def test_api_football_fixture():
    m = parse_fixture(AF_FIXTURE)
    assert m.status == MatchStatus.LIVE and m.minute == 67
    assert m.utc_kickoff.tzinfo is not None
    assert [e.type for e in m.events] == [EventType.GOAL, EventType.RED_CARD, EventType.SUBSTITUTION, EventType.VAR]
    assert m.events[2].related_player_name == "In"
    assert m.stats.home.possession == 58 and m.stats.away.possession == 42
    assert m.lineups[0].formation == "4-3-3" and m.lineups[0].starting[0].grid == "4:3"
