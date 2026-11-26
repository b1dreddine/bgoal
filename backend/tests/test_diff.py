from app.domain import Duration, EventType, MatchStatus
from app.notifications.diff import Kind, diff
from app.notifications.messages import render
from tests.conftest import ARS, CHE, goal, make_match

LIVE = MatchStatus.LIVE


def kinds(result):
    return [n.kind for n in result.notices]


def test_first_sighting_is_silent():
    assert diff(None, make_match(LIVE, 1, 0)).notices == []


def test_kickoff():
    r = diff(make_match(), make_match(LIVE, 0, 0, minute=1))
    assert kinds(r) == [Kind.KICKOFF]
    assert r.notices[0].dedupe_key == "kickoff:1001"


def test_goal_with_scorer_matches_spec_format():
    prev = make_match(LIVE, 1, 1, minute=66)
    curr = make_match(LIVE, 2, 1, minute=67, events=[goal(ARS, 67, "Saka", "Ødegaard")])
    r = diff(prev, curr)
    assert kinds(r) == [Kind.GOAL]
    n = r.notices[0]
    assert n.score == (2, 1) and n.event.player_name == "Saka"
    title, body = render(n, "en")
    assert title == "⚽ GOAL! Arsenal 2–1 Chelsea — Saka 67'"
    assert body == "Assist: Ødegaard · Premier League"


def test_goal_without_event_data_still_notifies():
    r = diff(make_match(LIVE, 0, 0, has_event_data=False), make_match(LIVE, 0, 1, has_event_data=False))
    assert kinds(r) == [Kind.GOAL]
    assert render(r.notices[0], "en")[0] == "⚽ GOAL! Arsenal 0–1 Chelsea"


def test_two_goals_in_one_poll_are_ordered_by_minute():
    prev = make_match(LIVE, 0, 0)
    curr = make_match(LIVE, 1, 1, events=[goal(CHE, 10, "Palmer"), goal(ARS, 12, "Saka")])
    r = diff(prev, curr)
    assert [(n.score, n.event.player_name) for n in r.notices] == [((0, 1), "Palmer"), ((1, 1), "Saka")]


def test_own_goal_credited_to_other_side():
    prev = make_match(LIVE, 0, 0)
    curr = make_match(LIVE, 1, 0, events=[goal(CHE, 30, "Colwill", type=EventType.OWN_GOAL)])
    r = diff(prev, curr)
    assert r.notices[0].team_id == ARS.id
    assert render(r.notices[0], "en")[1].startswith("Own goal")


def test_same_state_twice_is_silent():
    m = make_match(LIVE, 1, 0, events=[goal(ARS, 5, "Saka")])
    assert diff(m, m).notices == []


def test_var_disallowed_goal_sends_correction_and_rescore_gets_new_key():
    before = make_match(LIVE, 0, 0)
    scored = make_match(LIVE, 1, 0, events=[goal(ARS, 20, "Havertz")])
    r1 = diff(before, scored, 0)
    assert r1.notices[0].dedupe_key == "goal:1001:1-0:r0"

    cancelled = make_match(LIVE, 0, 0)
    r2 = diff(scored, cancelled, r1.score_revision)
    assert kinds(r2) == [Kind.GOAL_DISALLOWED]
    assert r2.score_revision == 1
    assert render(r2.notices[0], "en")[0] == "❌ Goal disallowed: Arsenal 0–0 Chelsea"

    rescored = make_match(LIVE, 1, 0, events=[goal(ARS, 25, "Saka")])
    r3 = diff(cancelled, rescored, r2.score_revision)
    assert r3.notices[0].dedupe_key == "goal:1001:1-0:r1"  # not deduped against the cancelled goal


def test_scorer_reassignment_is_a_correction_not_a_new_goal():
    prev = make_match(LIVE, 1, 0, events=[goal(ARS, 40, "Saka")])
    curr = make_match(LIVE, 1, 0, events=[goal(ARS, 40, "Martinelli")])
    r = diff(prev, curr)
    assert r.notices == []
    assert [(o.player_name, n.player_name) for o, n in r.scorer_corrections] == [("Saka", "Martinelli")]


def test_red_card():
    prev = make_match(LIVE, 0, 0)
    red = goal(CHE, 54, "James", type=EventType.RED_CARD)
    r = diff(prev, make_match(LIVE, 0, 0, events=[red]))
    assert kinds(r) == [Kind.RED_CARD]
    assert render(r.notices[0], "en")[0] == "🟥 Red card: James (Chelsea) 54'"


def test_half_time_and_full_time_after_last_goal():
    r = diff(make_match(LIVE, 0, 0), make_match(MatchStatus.HALFTIME, 1, 0))
    assert kinds(r) == [Kind.GOAL, Kind.HALF_TIME]
    r = diff(make_match(LIVE, 1, 0), make_match(MatchStatus.FINISHED, 1, 0))
    assert kinds(r) == [Kind.FULL_TIME]


def test_full_time_after_penalties():
    prev = make_match(MatchStatus.PENALTIES, 1, 1, duration=Duration.PENALTIES)
    curr = make_match(MatchStatus.FINISHED, 1, 1, duration=Duration.PENALTIES, pen_home=4, pen_away=3)
    r = diff(prev, curr)
    assert kinds(r) == [Kind.FULL_TIME]  # shootout goals are not "goals"
    assert render(r.notices[0], "en")[0] == "🏁 Full-time: Arsenal 1–1 Chelsea — Arsenal win 4–3 on penalties"
    assert "aux tirs au but" in render(r.notices[0], "fr")[0]


def test_postponed_and_abandoned():
    assert kinds(diff(make_match(), make_match(MatchStatus.POSTPONED))) == [Kind.POSTPONED]
    assert kinds(diff(make_match(LIVE, 1, 0), make_match(MatchStatus.ABANDONED, 1, 0))) == [Kind.ABANDONED]


def test_arabic_render():
    r = diff(make_match(LIVE, 0, 0), make_match(LIVE, 1, 0, events=[goal(ARS, 9, "Saka")]))
    assert render(r.notices[0], "ar")[0].startswith("⚽ هدف!")
