import os
from datetime import datetime, timezone

import fakeredis
import pytest
import pytest_asyncio

os.environ.setdefault("PROVIDER", "mock")

from app import cache, db  # noqa: E402
from app.domain import Competition, Match, MatchEvent, MatchStatus, Score, Team  # noqa: E402
from app.providers import set_provider  # noqa: E402
from app.providers.mock import MockProvider  # noqa: E402

ARS = Team(id=57, name="Arsenal FC", short_name="Arsenal", tla="ARS")
CHE = Team(id=61, name="Chelsea FC", short_name="Chelsea", tla="CHE")
PL = Competition(id=2021, name="Premier League", code="PL")


def make_match(status=MatchStatus.SCHEDULED, home=None, away=None, events=(), minute=None, has_event_data=True,
               match_id=1001, **score) -> Match:
    return Match(
        id=match_id, competition=PL, utc_kickoff=datetime(2026, 10, 28, 19, 0, tzinfo=timezone.utc),
        status=status, minute=minute, home=ARS, away=CHE, score=Score(home=home, away=away, **score),
        events=list(events), has_event_data=has_event_data,
    )


def goal(team, minute, player, assist=None, **kw) -> MatchEvent:
    from app.domain import EventType
    return MatchEvent(type=kw.pop("type", EventType.GOAL), minute=minute, team_id=team.id, player_name=player,
                      related_player_name=assist, **kw)


@pytest_asyncio.fixture
async def env(tmp_path):
    """Fresh SQLite DB + fake Redis + mock provider per test."""
    db.init_engine(f"sqlite+aiosqlite:///{tmp_path / 'test.db'}")
    await db.create_all()
    cache.set_redis(fakeredis.FakeAsyncRedis(decode_responses=True))
    provider = MockProvider()
    set_provider(provider)
    yield provider
    set_provider(None)
    await db.get_engine().dispose()


@pytest.fixture
def anyio_backend():
    return "asyncio"
