"""Single-service free hosting: in-memory cache, and the worker inside the API process."""
import asyncio

import pytest

from app import cache, main
from app.config import get_settings


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
