from datetime import datetime, time, timedelta, timezone

import httpx

from app import cache
from app.config import Settings
from app.domain import MatchStatus
from app.main import app
from app.notifications.diff import Kind
from app.notifications.dispatcher import in_quiet_hours
from app.notifications.sender import LogSender
from app.services import LIVE_KEY
from app.worker import Worker
from tests.conftest import ARS, goal, make_match


def client():
    return httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test")


async def register(c, **extra):
    body = {"platform": "ios", "fcm_token": "tok-1", "language": "en", "timezone": "Europe/London",
            "favorite_teams": [{"team_id": ARS.id}], **extra}
    r = await c.post("/devices", json=body)
    assert r.status_code == 201, r.text
    return r.json()


class FakeProvider:
    """Feeds the worker a scripted sequence of live states."""

    def __init__(self):
        self.live = []

    async def get_live_matches(self):
        return self.live

    async def get_match(self, match_id):
        raise AssertionError("not expected")


async def test_matches_endpoints(env):
    async with client() as c:
        today = datetime.now(timezone.utc).date().isoformat()
        r = await c.get("/matches", params={"date": today, "tz": "Europe/Paris"})
        assert r.status_code == 200
        body = r.json()
        assert body["data"] and "updated_at" in body
        statuses = {m["status"] for m in body["data"]}
        assert "live" in statuses or "halftime" in statuses

        live = (await c.get("/matches/live")).json()["data"]
        assert live and all(m["status"] in ("live", "halftime") for m in live)

        detail = (await c.get(f"/matches/{live[0]['id']}")).json()["data"]
        assert detail["lineups"] and detail["stats"]

        assert (await c.get("/matches", params={"date": today, "tz": "Not/AZone"})).status_code == 400


async def test_team_search_and_overview(env):
    worker = Worker(env, LogSender(), Settings())
    await worker.sync_teams()
    async with client() as c:
        found = (await c.get("/teams/search", params={"q": "arsen"})).json()["data"]
        assert [t["id"] for t in found] == [57]
        team = (await c.get("/teams/57")).json()["data"]
        assert team["team"]["name"] == "Arsenal FC"
        assert team["standing"]["competition"]["code"] == "PL"
        assert team["upcoming"] or team["recent"]

        groups = (await c.get("/teams/browse")).json()["data"]
        codes = [g["competition"]["code"] for g in groups]
        assert "PL" in codes
        assert codes.index("PL") < codes.index("CL") if "CL" in codes else True  # leagues before cups
        pl = next(g for g in groups if g["competition"]["code"] == "PL")
        assert 57 in [t["id"] for t in pl["teams"]]


async def test_team_overview_shows_live_score(env):
    worker = Worker(env, LogSender(), Settings())
    await worker.sync_teams()
    async with client() as c:
        live = (await c.get("/matches/live")).json()["data"]
        team_id = live[0]["home"]["id"]
        await c.get(f"/teams/{team_id}")  # fixtures now cached for 10 minutes

        # The worker sees a goal; the team page must show it without waiting for that cache.
        live[0]["score"] = {**live[0]["score"], "home": 9}
        await cache.put(LIVE_KEY, live, ttl=60)
        team = (await c.get(f"/teams/{team_id}")).json()["data"]
        shown = next(m for m in team["upcoming"] if m["id"] == live[0]["id"])
        assert shown["score"]["home"] == 9


async def test_device_registration_and_auth(env):
    async with client() as c:
        dev = await register(c, quiet_hours={"enabled": True, "start": "23:00", "end": "07:00"})
        assert dev["favorite_teams"][0]["notifications"]["goals"] is True
        assert dev["quiet_hours"] == {"enabled": True, "start": "23:00", "end": "07:00"}

        url = f"/devices/{dev['id']}/preferences"
        assert (await c.put(url, json={"language": "fr"})).status_code == 404  # no secret
        assert (await c.put(url, json={"language": "fr"}, headers={"Authorization": "Bearer nope"})).status_code == 404

        auth = {"Authorization": f"Bearer {dev['secret']}"}
        r = await c.put(url, headers=auth, json={
            "language": "ar",
            "favorite_teams": [{"team_id": 61, "notifications": {"goals": False}}, {"team_id": 57}],
        })
        assert r.status_code == 200
        prefs = r.json()
        assert prefs["language"] == "ar"
        assert [t["team_id"] for t in prefs["favorite_teams"]] == [61, 57]
        assert prefs["favorite_teams"][0]["notifications"]["goals"] is False

        # Same FCM token registered by a reinstall moves to the new device.
        dev2 = await register(c)
        assert dev2["has_fcm_token"]
        old = (await c.get(f"/devices/{dev['id']}", headers=auth)).json()
        assert old["has_fcm_token"] is False


async def test_purges_only_long_idle_devices_without_a_token(env):
    async with client() as c:
        gone = await register(c, fcm_token="")  # e.g. FCM reported the app uninstalled
        kept = await register(c)
        assert gone["has_fcm_token"] is False

        now = datetime.now(timezone.utc)
        assert await Worker(env, LogSender(), Settings(), clock=lambda: now).purge_stale_devices() == 0
        later = now + timedelta(days=91)
        assert await Worker(env, LogSender(), Settings(), clock=lambda: later).purge_stale_devices() == 1

        assert (await c.get(f"/devices/{gone['id']}", headers={"Authorization": f"Bearer {gone['secret']}"})
                ).status_code == 404
        assert (await c.get(f"/devices/{kept['id']}", headers={"Authorization": f"Bearer {kept['secret']}"})
                ).status_code == 200


async def test_worker_notifies_once_and_respects_prefs(env):
    sender = LogSender()
    fake = FakeProvider()
    worker = Worker(fake, sender, Settings(live_poll_seconds=15))
    async with client() as c:
        fan = await register(c)  # follows Arsenal, all events
        muted = await register(c, fcm_token="tok-2",
                               favorite_teams=[{"team_id": ARS.id, "notifications": {"goals": False}}])
        await register(c, fcm_token="tok-3", favorite_teams=[{"team_id": 999}])  # unrelated team

    await worker.process([make_match()])  # fixture sync: scheduled
    fake.live = [make_match(MatchStatus.LIVE, 0, 0, minute=1)]
    await worker.poll_live()
    fake.live = [make_match(MatchStatus.LIVE, 1, 0, minute=67, events=[goal(ARS, 67, "Saka")])]
    await worker.poll_live()
    await worker.poll_live()  # same state again -> nothing new

    titles = [(p.title, sorted(p.tokens)) for p in sender.sent]
    assert titles == [
        ("▶️ Kick-off: Arsenal vs Chelsea", ["tok-1", "tok-2"]),
        ("⚽ GOAL! Arsenal 1–0 Chelsea — Saka 67'", ["tok-1"]),
    ]
    assert sender.sent[1].data == {"type": "goal", "match_id": "1001", "deep_link": "bgoal://match/1001"}

    # The live cache now feeds the API.
    async with client() as c:
        live = (await c.get("/matches/live")).json()["data"]
        assert live[0]["score"]["home"] == 1
    assert fan and muted


async def test_dedupe_survives_restart(env):
    """A second worker instance replaying the same transition must not re-send."""
    fake = FakeProvider()
    s1, s2 = LogSender(), LogSender()
    async with client() as c:
        await register(c)
    w1 = Worker(fake, s1, Settings())
    await w1.process([make_match(MatchStatus.LIVE, 0, 0)])
    await w1.process([make_match(MatchStatus.LIVE, 1, 0)])
    # simulate a restart that lost the last stored state
    w2 = Worker(fake, s2, Settings())
    from app import repository
    from app.db import session_factory
    async with session_factory()() as session:
        await repository.save_match(session, make_match(MatchStatus.LIVE, 0, 0), 0)
        await session.commit()
    await w2.process([make_match(MatchStatus.LIVE, 1, 0)])
    assert len(s1.sent) == 1 and s2.sent == []


async def test_quiet_hours_and_starting_soon(env):
    now = datetime(2026, 10, 28, 18, 45, tzinfo=timezone.utc)
    sender = LogSender()
    worker = Worker(FakeProvider(), sender, Settings(), clock=lambda: now)
    async with client() as c:
        await register(c)  # London: 18:45 local, not quiet
        await register(c, fcm_token="tok-sleepy", timezone="Asia/Tokyo",  # 03:45 local
                       quiet_hours={"enabled": True, "start": "23:00", "end": "07:00"})
    await worker.process([make_match()])  # kickoff 19:00 UTC
    notices = await worker.starting_soon()
    assert [n.kind for n in notices] == [Kind.STARTING_SOON]
    assert [(p.title, p.body, p.tokens) for p in sender.sent] == [
        ("⏰ Starting soon: Arsenal vs Chelsea", "Kick-off in 15 minutes · Premier League", ["tok-1"]),
    ]
    await worker.starting_soon()
    assert len(sender.sent) == 1


def test_quiet_hours_window():
    t = lambda h, m=0: datetime(2026, 1, 1, h, m, tzinfo=timezone.utc)  # noqa: E731
    assert in_quiet_hours(t(23, 30), "UTC", time(22), time(7))
    assert in_quiet_hours(t(6, 59), "UTC", time(22), time(7))
    assert not in_quiet_hours(t(7), "UTC", time(22), time(7))
    assert in_quiet_hours(t(13), "UTC", time(12), time(14))
    assert not in_quiet_hours(t(13), "UTC", time(9), time(9))
    assert in_quiet_hours(t(22) - timedelta(hours=1), "Europe/Paris", time(22), time(7))  # 22:00 Paris in winter
