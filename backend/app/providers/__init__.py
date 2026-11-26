from app.config import Settings, get_settings
from app.providers.base import FootballProvider, ProviderError

__all__ = ["FootballProvider", "ProviderError", "build_provider", "get_provider", "set_provider"]

_provider: FootballProvider | None = None


def build_provider(settings: Settings) -> FootballProvider:
    if settings.provider == "football_data":
        from app.providers.football_data import FootballDataProvider

        if not settings.football_data_api_key:
            raise RuntimeError("FOOTBALL_DATA_API_KEY is required when PROVIDER=football_data")
        return FootballDataProvider(settings.football_data_api_key, settings.competitions_list,
                                    settings.provider_requests_per_minute, settings.team_list_competitions_list)
    if settings.provider == "api_football":
        from app.providers.api_football import ApiFootballProvider

        if not settings.api_football_api_key:
            raise RuntimeError("API_FOOTBALL_API_KEY is required when PROVIDER=api_football")
        return ApiFootballProvider(settings.api_football_api_key, settings.api_football_leagues_list,
                                   settings.api_football_season, settings.provider_requests_per_minute)
    if settings.provider == "mock":
        from app.providers.mock import MockProvider

        return MockProvider()
    raise RuntimeError(f"Unknown PROVIDER {settings.provider!r}")


def get_provider() -> FootballProvider:
    global _provider
    if _provider is None:
        _provider = build_provider(get_settings())
    return _provider


def set_provider(provider: FootballProvider | None) -> None:
    global _provider
    _provider = provider
