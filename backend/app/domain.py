"""Provider-independent football models.

Every data provider adapter converts its own payloads into these models, so the rest of
the backend (cache, diffing, notifications, API) never sees provider-specific shapes.
"""
from datetime import datetime
from enum import Enum

from pydantic import BaseModel, Field


class MatchStatus(str, Enum):
    SCHEDULED = "scheduled"
    LIVE = "live"              # first or second half in play
    HALFTIME = "halftime"
    EXTRA_TIME = "extra_time"  # in play during extra time (or the break before it)
    PENALTIES = "penalties"    # shootout in progress
    FINISHED = "finished"      # FT, AET or after penalties - see Score.duration
    SUSPENDED = "suspended"    # interrupted, may resume
    POSTPONED = "postponed"
    ABANDONED = "abandoned"
    CANCELLED = "cancelled"

    @property
    def is_in_play(self) -> bool:
        return self in IN_PLAY_STATUSES


IN_PLAY_STATUSES = {
    MatchStatus.LIVE,
    MatchStatus.HALFTIME,
    MatchStatus.EXTRA_TIME,
    MatchStatus.PENALTIES,
    MatchStatus.SUSPENDED,
}


class Duration(str, Enum):
    REGULAR = "regular"
    EXTRA_TIME = "extra_time"
    PENALTIES = "penalties"


class EventType(str, Enum):
    GOAL = "goal"
    OWN_GOAL = "own_goal"
    PENALTY_GOAL = "penalty_goal"
    MISSED_PENALTY = "missed_penalty"
    YELLOW_CARD = "yellow_card"
    SECOND_YELLOW = "second_yellow"
    RED_CARD = "red_card"
    SUBSTITUTION = "substitution"
    VAR = "var"

    @property
    def is_goal(self) -> bool:
        return self in (EventType.GOAL, EventType.OWN_GOAL, EventType.PENALTY_GOAL)

    @property
    def is_red(self) -> bool:
        return self in (EventType.RED_CARD, EventType.SECOND_YELLOW)


class Competition(BaseModel):
    id: int
    name: str
    code: str | None = None
    country: str | None = None
    emblem_url: str | None = None


class Team(BaseModel):
    id: int
    name: str
    short_name: str | None = None
    tla: str | None = None
    crest_url: str | None = None
    country: str | None = None


class Score(BaseModel):
    # home/away are the goals that count for the match result (incl. extra time, excl. shootout)
    home: int | None = None
    away: int | None = None
    ht_home: int | None = None
    ht_away: int | None = None
    pen_home: int | None = None
    pen_away: int | None = None
    duration: Duration = Duration.REGULAR


class MatchEvent(BaseModel):
    type: EventType
    minute: int | None = None
    extra_minute: int | None = None
    team_id: int | None = None
    player_id: int | None = None
    player_name: str | None = None
    # assist for goals, player coming ON for substitutions
    related_player_id: int | None = None
    related_player_name: str | None = None
    detail: str | None = None

    @property
    def key(self) -> str:
        """Identity used to spot new events between polls.

        Deliberately excludes the player so a goal reassigned to another scorer keeps the
        same key and is detected as a correction rather than a new goal.
        """
        return f"{self.type.value}:{self.team_id}:{self.minute}:{self.extra_minute or 0}"


class LineupPlayer(BaseModel):
    id: int | None = None
    name: str
    number: int | None = None
    position: str | None = None
    grid: str | None = None  # "row:col" when the provider gives pitch positions


class Lineup(BaseModel):
    team_id: int
    formation: str | None = None
    coach: str | None = None
    starting: list[LineupPlayer] = Field(default_factory=list)
    substitutes: list[LineupPlayer] = Field(default_factory=list)


class TeamStats(BaseModel):
    possession: int | None = None
    shots: int | None = None
    shots_on_target: int | None = None
    corners: int | None = None
    fouls: int | None = None
    yellow_cards: int | None = None
    red_cards: int | None = None


class MatchStats(BaseModel):
    home: TeamStats = Field(default_factory=TeamStats)
    away: TeamStats = Field(default_factory=TeamStats)


class Match(BaseModel):
    id: int
    competition: Competition
    utc_kickoff: datetime
    status: MatchStatus
    minute: int | None = None
    injury_time: int | None = None
    home: Team
    away: Team
    score: Score = Field(default_factory=Score)
    venue: str | None = None
    events: list[MatchEvent] = Field(default_factory=list)
    lineups: list[Lineup] = Field(default_factory=list)
    stats: MatchStats | None = None
    # True when `events` is authoritative; free tiers often return scores without events.
    has_event_data: bool = False


class StandingRow(BaseModel):
    position: int
    team: Team
    played: int
    won: int
    draw: int
    lost: int
    goals_for: int
    goals_against: int
    goal_difference: int
    points: int
    form: str | None = None
    group: str | None = None
