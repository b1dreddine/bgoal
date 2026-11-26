"""Single-service free hosting: in-memory cache, and the worker inside the API process."""
import asyncio
from datetime import datetime, timezone

import pytest

from app import cache, main
from app.config import Settings, get_settings


@pytest.mark.asyncio
async def test_memory_url_uses_an_in_process_cache(monkeypatch):
    monkeypatch.setenv("REDIS_URL", "memory://")
    get_settings.cache_clear()
    cache.set_redis(None)
    try:
        await cache.put("k", {"a": 1}, ttl=60)
        assert (await cache.get_entry("k"))["data"] == {"a": 1}
    finally:
        cache.set_redis(None)
        get_settings.cache_clear()


@pytest.mark.asyncio
async def test_rate_limiter_lets_a_burst_through_then_respects_the_window():
    from app.providers.base import RateLimiter

    limiter = RateLimiter(per_minute=3, window=0.5)
    loop = asyncio.get_running_loop()
    start = loop.time()
    for _ in range(3):
        await limiter.wait()
    assert loop.time() - start < 0.1  # the first 3 go at once
    await limiter.wait()
    assert loop.time() - start >= 0.45  # the 4th waits for the first to leave the window

    limiter.penalize(0.2)
    before = loop.time()
    await limiter.wait()
    assert loop.time() - before >= 0.15


def test_image_pass_through_only_serves_provider_images(monkeypatch):
    from fastapi.testclient import TestClient

    from app.routers import images

    async def fake_fetch(url):
        return b"\x89PNG...", "image/png"

    monkeypatch.setattr(images, "fetch_image", fake_fetch)
    client = TestClient(main.app)
    ok = client.get("/img", params={"url": "https://crests.football-data.org/57.png"},
                    headers={"Origin": "https://b1dreddine.github.io"})
    assert ok.status_code == 200
    assert ok.headers["content-type"] == "image/png"
    assert "max-age" in ok.headers["cache-control"]
    assert ok.headers["access-control-allow-origin"] in ("*", "https://b1dreddine.github.io")

    for bad in ("https://example.com/a.png", "http://crests.football-data.org/57.png",
                "https://crests.football-data.org.evil.com/57.png", "file:///etc/passwd"):
        assert client.get("/img", params={"url": bad}).status_code == 400


def test_on_vercel_defaults_to_sqlite_and_memory_cache(monkeypatch):
    monkeypatch.setenv("SERVERLESS", "true")
    monkeypatch.delenv("DATABASE_URL", raising=False)
    monkeypatch.delenv("REDIS_URL", raising=False)
    s = Settings(_env_file=None)
    assert s.database_url == "sqlite+aiosqlite:////tmp/bgoal.db"
    assert s.redis_url == "memory://"
    # Matches from every competition (one request), team list from the biggest only.
    assert "DED" in s.competitions_list
    assert s.team_list_competitions_list == ["PL", "PD", "SA", "BL1", "FL1", "CL"]
    # Explicit settings still win.
    monkeypatch.setenv("REDIS_URL", "redis://cache:6379/0")
    assert Settings(_env_file=None).redis_url == "redis://cache:6379/0"


@pytest.mark.asyncio
async def test_serverless_loads_teams_on_first_browse_and_overlays_live_scores(env, monkeypatch):
    from app import db, services
    from app.domain import MatchStatus

    monkeypatch.setenv("SERVERLESS", "true")
    get_settings.cache_clear()
    try:
        async with db.session_factory()() as session:
            groups = await services.browse_teams(session)
        assert groups and all(g["teams"] for g in groups)  # no worker ran, yet teams are there

        today = datetime.now(timezone.utc).date()
        day = await services.matches_for_local_date(today, "UTC")
        live_ids = {m.id for m in await env.get_live_matches()}
        assert live_ids, "the mock provider always has live matches today"
        listed = {m["id"]: m for m in day["data"]}
        for mid in live_ids & listed.keys():
            assert listed[mid]["status"] in {s.value for s in MatchStatus if s.is_in_play}
        assert await cache.get_entry(services.LIVE_KEY) is not None  # fetched by the API itself
    finally:
        get_settings.cache_clear()


@pytest.mark.asyncio
async def test_api_runs_the_worker_when_asked_and_stops_it_on_shutdown(env, monkeypatch):
    started = asyncio.Event()
    stopped = asyncio.Event()

    async def fake_run_forever(self):
        started.set()
        try:
            await asyncio.Event().wait()
        finally:
            stopped.set()

    monkeypatch.setattr("app.worker.Worker.run_forever", fake_run_forever)
    monkeypatch.setenv("RUN_WORKER_IN_API", "true")
    get_settings.cache_clear()
    try:
        async with main.lifespan(main.app):
            await asyncio.wait_for(started.wait(), 2)
        assert stopped.is_set()
    finally:
        get_settings.cache_clear()
