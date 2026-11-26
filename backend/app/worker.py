"""Background worker: polls the provider, detects events, sends notifications.

Run with `python -m app.worker`. Several replicas are safe: a Redis leader lock lets only
one poll at a time, and notification_log dedupes even if two overlap during failover.
"""
import asyncio
import logging
import math
import os
import socket
from datetime import datetime, timedelta, timezone

from sqlalchemy import delete, select

from app import cache, repository
from app.config import Settings, get_settings
from app.db import create_all, session_factory
from app.domain import Match, MatchStatus
from app.models import DeviceRow, FavoriteCompetitionRow, FavoriteTeamRow
from app.notifications.diff import Kind, Notice, diff
from app.notifications.dispatcher import dispatch
from app.notifications.sender import PushSender, build_sender
from app.providers import FootballProvider, get_provider
from app.services import LIVE_KEY

log = logging.getLogger("worker")

LEADER_KEY = "worker:leader"
MAX_EXTRA_FETCHES = 10  # per poll, for matches that left the live feed (usually just finished)


class Worker:
    def __init__(self, provider: FootballProvider, sender: PushSender, settings: Settings, clock=None):
        self.provider = provider
        self.sender = sender
        self.settings = settings
        self.clock = clock or (lambda: datetime.now(timezone.utc))
        self.identity = f"{socket.gethostname()}:{os.getpid()}"

    # ---- core: store new state, diff against old, notify ----

    async def process(self, matches: list[Match]) -> list[Notice]:
        notices: list[Notice] = []
        async with session_factory()() as session:
            previous = await repository.load_match_states(session, [m.id for m in matches])
            for match in matches:
                prev, revision = previous.get(match.id, (None, 0))
                result = diff(prev, match, revision)
                for old, new in result.scorer_corrections:
                    log.info("match %s: scorer corrected %s -> %s (%s')", match.id, old.player_name,
                             new.player_name, new.minute)
                await repository.save_match(session, match, result.score_revision)
                notices += result.notices
                if prev is not None and prev.status != match.status and not match.status.is_in_play:
                    await self._invalidate(match)
            await session.commit()

        # Save first, then notify: a crash in between loses a push rather than duplicating it.
        async with session_factory()() as session:
            for notice in notices:
                try:
                    await dispatch(session, notice, self.sender, self.clock())
                except Exception:
                    log.exception("dispatch failed for %s", notice.dedupe_key)
                    await session.rollback()
        return notices

    async def _invalidate(self, match: Match) -> None:
        """A match left the live feed (finished/postponed...): drop cached copies so the API refetches."""
        await cache.get_redis().delete(f"match:{match.id}", f"matches:date:{match.utc_kickoff.date().isoformat()}")

    # ---- scheduled jobs ----

    async def poll_live(self) -> list[Notice]:
        live = await self.provider.get_live_matches()
        live_ids = {m.id for m in live}
        async with session_factory()() as session:
            stale_ids = [i for i in await repository.stored_in_play_ids(session) if i not in live_ids]
        extra = []
        for match_id in stale_ids[:MAX_EXTRA_FETCHES]:
            try:
                extra.append(await self.provider.get_match(match_id))
            except Exception:
                log.exception("could not refresh match %s", match_id)
        notices = await self.process(live + extra)
        await cache.put(LIVE_KEY, [m.model_dump(mode="json") for m in live], ttl=self.settings.live_poll_seconds * 4)
        return notices

    async def sync_fixtures(self) -> None:
        today = self.clock().date()
        for day in (today - timedelta(days=1), today, today + timedelta(days=1)):
            matches = await self.provider.get_matches_by_date(day)
            # Live matches are owned by poll_live; only store the rest here.
            await self.process([m for m in matches if not m.status.is_in_play])
            await cache.put(f"matches:date:{day.isoformat()}", [m.model_dump(mode="json") for m in matches], ttl=300)

    async def starting_soon(self) -> list[Notice]:
        now = self.clock()
        lead = self.settings.starting_soon_minutes
        async with session_factory()() as session:
            upcoming = await repository.matches_between(session, now, now + timedelta(minutes=lead + 1))
            notices = []
            for m in upcoming:
                if m.status != MatchStatus.SCHEDULED:
                    continue
                mins = math.ceil((m.utc_kickoff - now).total_seconds() / 60)
                if mins < 5:  # too late to be useful; the kickoff alert follows shortly
                    continue
                notice = Notice(Kind.STARTING_SOON, m, f"soon:{m.id}", minutes_to_kickoff=mins)
                await dispatch(session, notice, self.sender, now)
                notices.append(notice)
        return notices

    async def sync_teams(self) -> None:
        competitions = await self.provider.list_competition_teams()
        async with session_factory()() as session:
            for comp, teams in competitions:
                await repository.upsert_competitions(session, [comp])
                await repository.upsert_teams(session, teams, comp.id)
            await session.commit()
        log.info("synced %d teams", sum(len(t) for _, t in competitions))

    async def purge_stale_devices(self) -> int:
        """Delete devices FCM has reported as gone (token cleared) once they've been idle for
        the retention period, with their favorites. Explicit deletes rather than relying on
        ON DELETE CASCADE, which SQLite (tests) doesn't enforce by default."""
        cutoff = self.clock() - timedelta(days=self.settings.device_retention_days)
        async with session_factory()() as session:
            ids = list((await session.execute(
                select(DeviceRow.id).where(DeviceRow.fcm_token.is_(None), DeviceRow.updated_at < cutoff)
            )).scalars())
            if ids:
                for table in (FavoriteTeamRow, FavoriteCompetitionRow):
                    await session.execute(delete(table).where(table.device_id.in_(ids)))
                await session.execute(delete(DeviceRow).where(DeviceRow.id.in_(ids)))
                await session.commit()
                log.info("purged %d stale devices", len(ids))
        return len(ids)

    # ---- loop ----

    async def _is_leader(self) -> bool:
        redis = cache.get_redis()
        ttl = self.settings.live_poll_seconds * 3
        if await redis.set(LEADER_KEY, self.identity, nx=True, ex=ttl):
            return True
        if await redis.get(LEADER_KEY) == self.identity:
            await redis.expire(LEADER_KEY, ttl)
            return True
        return False

    async def run_forever(self) -> None:
        jobs = [
            (self.sync_teams, self.settings.teams_sync_seconds),
            (self.sync_fixtures, self.settings.fixtures_sync_seconds),
            (self.poll_live, self.settings.live_poll_seconds),
            (self.starting_soon, 60),
            (self.purge_stale_devices, 86400),
        ]
        next_run = [0.0] * len(jobs)
        loop = asyncio.get_running_loop()
        while True:
            if not await self._is_leader():
                await asyncio.sleep(self.settings.live_poll_seconds)
                continue
            for i, (job, every) in enumerate(jobs):
                if loop.time() >= next_run[i]:
                    try:
                        await job()
                        next_run[i] = loop.time() + every
                    except Exception:
                        log.exception("job %s failed", job.__name__)
                        next_run[i] = loop.time() + min(every, 60)  # retry sooner after a failure
            await asyncio.sleep(1)


async def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    settings = get_settings()
    await create_all()
    worker = Worker(get_provider(), build_sender(settings.firebase_credentials_file), settings)
    log.info("worker started with provider=%s", settings.provider)
    await worker.run_forever()


if __name__ == "__main__":
    asyncio.run(main())
