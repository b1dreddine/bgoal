import os
from functools import lru_cache

from pydantic import field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    env: str = "development"
    database_url: str = "postgresql+asyncpg://livescores:livescores@localhost:5432/livescores"
    redis_url: str = "redis://localhost:6379/0"

    # Data provider: "football_data" (free tier), "api_football", or "mock"
    provider: str = "mock"
    football_data_api_key: str = ""
    football_data_competitions: str = "PL,PD,SA,BL1,FL1,DED,PPL,ELC,CL,EC,WC,BSA"
    api_football_api_key: str = ""
    api_football_leagues: str = "39,140,135,78,61,2"  # league ids used for team sync
    api_football_season: int = 2026
    provider_requests_per_minute: int = 10

    # Worker timing
    live_poll_seconds: int = 15
    fixtures_sync_seconds: int = 600
    teams_sync_seconds: int = 86400
    # Devices that can't receive pushes (no FCM token, usually uninstalled) and haven't
    # changed anything for this long are deleted. The app re-registers if it's still installed.
    device_retention_days: int = 90
    starting_soon_minutes: int = 15

    # Push: path to Firebase service account JSON. Empty = log notifications instead of sending.
    firebase_credentials_file: str = ""

    cors_origins: str = "*"

    # Free hosting with a single service: the API process also runs the worker. Pair it with
    # DATABASE_URL=sqlite+aiosqlite:////tmp/bgoal.db and REDIS_URL=memory:// (see render.yaml).
    # Only for one instance: two would each poll the provider and send every push twice.
    run_worker_in_api: bool = False

    # Serverless hosting (Vercel's free plan): there is no worker, so the API fetches live
    # scores itself and loads the team list the first time it's asked for. Turned on
    # automatically on Vercel (which sets VERCEL=1), with a SQLite file in /tmp and an
    # in-memory cache unless DATABASE_URL / REDIS_URL say otherwise. No pushes in this mode.
    serverless: bool = bool(os.environ.get("VERCEL"))

    @field_validator("database_url")
    @classmethod
    def _async_driver(cls, v: str) -> str:
        # Hosts like Render/Railway hand out postgres:// URLs; SQLAlchemy async needs the asyncpg driver.
        for prefix in ("postgres://", "postgresql://"):
            if v.startswith(prefix):
                return "postgresql+asyncpg://" + v[len(prefix):]
        return v

    @model_validator(mode="after")
    def _serverless_defaults(self) -> "Settings":
        if self.serverless:
            if "database_url" not in self.model_fields_set:
                self.database_url = "sqlite+aiosqlite:////tmp/bgoal.db"
            if "redis_url" not in self.model_fields_set:
                self.redis_url = "memory://"
        return self

    @property
    def competitions_list(self) -> list[str]:
        return [c.strip() for c in self.football_data_competitions.split(",") if c.strip()]

    @property
    def api_football_leagues_list(self) -> list[int]:
        return [int(c) for c in self.api_football_leagues.split(",") if c.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()
