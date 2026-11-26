"""Redis cache in front of the data provider.

Every value is stored twice: a fresh copy with the requested TTL and a long-lived "stale"
copy. If the provider is down or rate-limited we serve the stale copy (with its original
`updated_at`) instead of failing, so the app can show "last updated" data.
"""
import asyncio
import json
import logging
from collections.abc import Awaitable, Callable
from datetime import datetime, timezone
from typing import Any

from redis import asyncio as aioredis

from app.config import get_settings

log = logging.getLogger(__name__)

STALE_TTL = 2 * 24 * 3600
LOCK_TTL_MS = 20_000

_redis: aioredis.Redis | None = None


def get_redis() -> aioredis.Redis:
    global _redis
    if _redis is None:
        url = get_settings().redis_url
        if url.startswith("memory://"):
            # In-process cache for single-instance free hosting (no Redis server).
            from fakeredis import FakeAsyncRedis

            _redis = FakeAsyncRedis(decode_responses=True)
        else:
            _redis = aioredis.from_url(url, decode_responses=True)
    return _redis


def set_redis(client: aioredis.Redis | None) -> None:
    global _redis
    _redis = client


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


async def get_entry(key: str) -> dict | None:
    raw = await get_redis().get(key)
    return json.loads(raw) if raw else None


async def put(key: str, data: Any, ttl: int, updated_at: str | None = None) -> dict:
    entry = {"data": data, "updated_at": updated_at or now_iso()}
    payload = json.dumps(entry, default=str)
    pipe = get_redis().pipeline()
    pipe.set(key, payload, ex=max(ttl, 1))
    pipe.set(f"stale:{key}", payload, ex=STALE_TTL)
    await pipe.execute()
    return entry


async def cached(key: str, ttl: int, fetch: Callable[[], Awaitable[Any]]) -> dict:
    """Return {"data", "updated_at", "stale"} for `key`, calling `fetch` at most once across
    all API instances when the entry is missing (single-flight via a Redis lock)."""
    redis = get_redis()
    entry = await get_entry(key)
    if entry:
        return {**entry, "stale": False}

    lock_key = f"lock:{key}"
    got_lock = await redis.set(lock_key, "1", nx=True, px=LOCK_TTL_MS)
    if not got_lock:
        # Someone else is fetching; wait briefly for their result.
        for _ in range(40):
            await asyncio.sleep(0.25)
            entry = await get_entry(key)
            if entry:
                return {**entry, "stale": False}
    try:
        data = await fetch()
        entry = await put(key, data, ttl)
        return {**entry, "stale": False}
    except Exception as exc:
        stale = await get_entry(f"stale:{key}")
        if stale is not None:
            log.warning("serving stale %s: %s", key, exc)
            return {**stale, "stale": True}
        raise
    finally:
        if got_lock:
            await redis.delete(lock_key)
