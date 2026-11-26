from collections.abc import AsyncIterator

from sqlalchemy.dialects import postgresql, sqlite
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase

from app.config import get_settings


class Base(DeclarativeBase):
    pass


_engine: AsyncEngine | None = None
_sessionmaker: async_sessionmaker[AsyncSession] | None = None


def init_engine(url: str | None = None) -> AsyncEngine:
    global _engine, _sessionmaker
    url = url or get_settings().database_url
    kwargs = {} if url.startswith("sqlite") else {"pool_size": 10, "max_overflow": 10, "pool_pre_ping": True}
    _engine = create_async_engine(url, **kwargs)
    _sessionmaker = async_sessionmaker(_engine, expire_on_commit=False)
    return _engine


def get_engine() -> AsyncEngine:
    if _engine is None:
        init_engine()
    return _engine  # type: ignore[return-value]


def session_factory() -> async_sessionmaker[AsyncSession]:
    if _sessionmaker is None:
        init_engine()
    return _sessionmaker  # type: ignore[return-value]


async def get_session() -> AsyncIterator[AsyncSession]:
    async with session_factory()() as session:
        yield session


def upsert(session: AsyncSession, table):
    """Dialect-appropriate INSERT that supports .on_conflict_do_update / do_nothing."""
    dialect = session.bind.dialect.name
    return (postgresql.insert if dialect == "postgresql" else sqlite.insert)(table)


async def create_all() -> None:
    from app import models  # noqa: F401  (register tables)

    async with get_engine().begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
