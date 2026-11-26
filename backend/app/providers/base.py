import asyncio
import logging
import time
from abc import ABC, abstractmethod
from datetime import date

import httpx

from app.domain import Competition, Match, StandingRow, Team

log = logging.getLogger(__name__)


class ProviderError(Exception):
    pass


class RateLimiter:
    """Spaces requests evenly so we never exceed `per_minute` calls to the provider."""

    def __init__(self, per_minute: int):
        self.interval = 60.0 / max(per_minute, 1)
        self._next = 0.0
        self._lock = asyncio.Lock()

    async def wait(self) -> None:
        async with self._lock:
            now = time.monotonic()
            delay = self._next - now
            if delay > 0:
                await asyncio.sleep(delay)
            self._next = max(now, self._next) + self.interval

    def penalize(self, seconds: float) -> None:
        self._next = max(self._next, time.monotonic() + seconds)


class FootballProvider(ABC):
    """Abstraction over a football data source. Swap providers by implementing this."""

    name: str
    supports_events: bool = False
    supports_lineups: bool = False
    supports_stats: bool = False
    supports_team_search: bool = False

    @abstractmethod
    async def get_matches_by_date(self, day: date) -> list[Match]:
        """All matches whose kickoff falls on `day` (UTC)."""

    @abstractmethod
    async def get_live_matches(self) -> list[Match]:
        """Matches currently in play."""

    @abstractmethod
    async def get_match(self, match_id: int) -> Match:
        """One match with as much detail (events, lineups, stats) as the provider offers."""

    @abstractmethod
    async def get_team(self, team_id: int) -> Team: ...

    @abstractmethod
    async def get_team_matches(self, team_id: int, upcoming: int = 5, recent: int = 5) -> list[Match]: ...

    @abstractmethod
    async def get_standings(self, competition_id: int) -> list[StandingRow]: ...

    @abstractmethod
    async def list_competition_teams(self) -> list[tuple[Competition, list[Team]]]:
        """Teams of the tracked competitions, used to fill the local search index."""

    async def search_teams(self, query: str) -> list[Team]:
        """Remote search, only used when supports_team_search is True."""
        return []

    async def aclose(self) -> None:
        pass


class HttpProvider(FootballProvider):
    base_url: str

    def __init__(self, headers: dict[str, str], per_minute: int):
        self._client = httpx.AsyncClient(base_url=self.base_url, headers=headers, timeout=15)
        self._limiter = RateLimiter(per_minute)

    async def _get(self, path: str, params: dict | None = None, retries: int = 2) -> dict:
        for attempt in range(retries + 1):
            await self._limiter.wait()
            try:
                resp = await self._client.get(path, params=params)
            except httpx.HTTPError as exc:
                if attempt == retries:
                    raise ProviderError(f"{self.name} request failed: {exc}") from exc
                continue
            if resp.status_code == 429:
                retry_after = float(resp.headers.get("Retry-After") or resp.headers.get("X-RequestCounter-Reset") or 60)
                log.warning("%s rate limited, backing off %.0fs", self.name, retry_after)
                self._limiter.penalize(retry_after)
                continue
            if resp.status_code >= 500 and attempt < retries:
                continue
            if resp.status_code >= 400:
                raise ProviderError(f"{self.name} {path} -> HTTP {resp.status_code}: {resp.text[:200]}")
            return resp.json()
        raise ProviderError(f"{self.name} {path}: retries exhausted")

    async def aclose(self) -> None:
        await self._client.aclose()
