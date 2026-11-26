"""Compare the previous and current state of a match and decide what to notify.

Pure functions only - no I/O - so every edge case is unit-tested.

Goals are detected from SCORE changes, not from the event list: free provider tiers send
scores without events, and event lists get rewritten (VAR, scorer reassignments). Events
are only used to decorate a goal with its scorer/minute.
"""
from dataclasses import dataclass, field
from enum import Enum

from app.domain import EventType, Match, MatchEvent, MatchStatus


class Kind(str, Enum):
    STARTING_SOON = "starting_soon"
    KICKOFF = "kickoff"
    GOAL = "goal"
    GOAL_DISALLOWED = "goal_disallowed"
    RED_CARD = "red_card"
    HALF_TIME = "half_time"
    FULL_TIME = "full_time"
    POSTPONED = "postponed"
    ABANDONED = "abandoned"
    CANCELLED = "cancelled"


# Which per-team preference toggle (favorite_teams column) controls each kind.
CATEGORY = {
    Kind.STARTING_SOON: "starting_soon",
    Kind.KICKOFF: "kickoff",
    Kind.GOAL: "goals",
    Kind.GOAL_DISALLOWED: "var",
    Kind.RED_CARD: "red_cards",
    Kind.HALF_TIME: "half_time",
    Kind.FULL_TIME: "full_time",
    Kind.POSTPONED: "kickoff",
    Kind.ABANDONED: "kickoff",
    Kind.CANCELLED: "kickoff",
}


@dataclass
class Notice:
    kind: Kind
    match: Match
    dedupe_key: str
    event: MatchEvent | None = None
    team_id: int | None = None           # scoring / carded team
    score: tuple[int, int] | None = None  # score to show (after the goal, or after the correction)
    minutes_to_kickoff: int | None = None  # STARTING_SOON only


@dataclass
class DiffResult:
    notices: list[Notice] = field(default_factory=list)
    score_revision: int = 0
    # (old_event, new_event) where a goal was reassigned to another player; stored, not pushed.
    scorer_corrections: list[tuple[MatchEvent, MatchEvent]] = field(default_factory=list)


_TERMINAL = {
    MatchStatus.POSTPONED: Kind.POSTPONED,
    MatchStatus.ABANDONED: Kind.ABANDONED,
    MatchStatus.CANCELLED: Kind.CANCELLED,
}


def _credited_side(ev: MatchEvent, match: Match) -> str | None:
    """'home' or 'away' - the side the goal counts for."""
    if ev.team_id not in (match.home.id, match.away.id):
        return None
    side = "home" if ev.team_id == match.home.id else "away"
    if ev.type == EventType.OWN_GOAL:
        # Providers record own goals under the player's team; the goal counts for the other side.
        side = "away" if side == "home" else "home"
    return side


def diff(prev: Match | None, curr: Match, score_revision: int = 0) -> DiffResult:
    result = DiffResult(score_revision=score_revision)
    if prev is None:
        # First time we see this match (e.g. worker restart): store, don't notify.
        return result
    mid = curr.id

    # --- status transitions ---
    if prev.status == MatchStatus.SCHEDULED and curr.status.is_in_play:
        result.notices.append(Notice(Kind.KICKOFF, curr, f"kickoff:{mid}"))
    if curr.status in _TERMINAL and prev.status != curr.status:
        kind = _TERMINAL[curr.status]
        result.notices.append(Notice(kind, curr, f"{kind.value}:{mid}"))

    # --- score changes ---
    started = curr.status.is_in_play or curr.status == MatchStatus.FINISHED
    ph, pa = prev.score.home or 0, prev.score.away or 0
    ch, ca = curr.score.home, curr.score.away
    if started and ch is not None and ca is not None:
        if ch < ph or ca < pa:
            side_team = curr.home.id if ch < ph else curr.away.id
            result.notices.append(Notice(Kind.GOAL_DISALLOWED, curr, f"disallowed:{mid}:{ph}-{pa}:r{result.score_revision}",
                                         team_id=side_team, score=(ch, ca)))
            result.score_revision += 1
            # continue from the corrected score in case the other side scored in the same poll
            ph, pa = min(ph, ch), min(pa, ca)

        prev_keys = {e.key for e in prev.events}
        new_goal_events = sorted(
            (e for e in curr.events if e.type.is_goal and e.key not in prev_keys),
            key=lambda e: ((e.minute or 0), (e.extra_minute or 0)),
        )
        pending = {"home": [e for e in new_goal_events if _credited_side(e, curr) == "home"],
                   "away": [e for e in new_goal_events if _credited_side(e, curr) == "away"]}
        goals: list[tuple[str, MatchEvent | None]] = []
        for side, before, after in (("home", ph, ch), ("away", pa, ca)):
            for _ in range(after - before):
                goals.append((side, pending[side].pop(0) if pending[side] else None))
        # Chronological when we know the minutes; otherwise home first.
        goals.sort(key=lambda g: (g[1].minute or 0, g[1].extra_minute or 0) if g[1] else (999, 0))

        h, a = ph, pa
        for side, ev in goals:
            if side == "home":
                h += 1
            else:
                a += 1
            team_id = curr.home.id if side == "home" else curr.away.id
            result.notices.append(Notice(Kind.GOAL, curr, f"goal:{mid}:{h}-{a}:r{result.score_revision}",
                                         event=ev, team_id=team_id, score=(h, a)))

    # --- red cards (only meaningful when the provider sends events) ---
    if curr.has_event_data:
        prev_keys = {e.key for e in prev.events}
        for ev in curr.events:
            if ev.type.is_red and ev.key not in prev_keys:
                result.notices.append(Notice(Kind.RED_CARD, curr, f"red:{mid}:{ev.key}:{ev.player_id or ev.player_name}",
                                             event=ev, team_id=ev.team_id))

        prev_goals = {e.key: e for e in prev.events if e.type.is_goal}
        for ev in curr.events:
            old = prev_goals.get(ev.key)
            if old and ev.type.is_goal and old.player_name and ev.player_name and old.player_name != ev.player_name:
                result.scorer_corrections.append((old, ev))

    # Half-time / full-time after goals so a last-minute goal arrives before the result.
    if curr.status == MatchStatus.HALFTIME and prev.status != MatchStatus.HALFTIME:
        result.notices.append(Notice(Kind.HALF_TIME, curr, f"ht:{mid}", score=(curr.score.home or 0, curr.score.away or 0)))
    if curr.status == MatchStatus.FINISHED and prev.status != MatchStatus.FINISHED:
        result.notices.append(Notice(Kind.FULL_TIME, curr, f"ft:{mid}", score=(curr.score.home or 0, curr.score.away or 0)))
    return result
