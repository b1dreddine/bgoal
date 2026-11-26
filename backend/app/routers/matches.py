from datetime import date
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from fastapi import APIRouter, HTTPException, Query

from app import services
from app.providers import ProviderError

router = APIRouter(prefix="/matches", tags=["matches"])


@router.get("")
async def matches_by_date(
    date_: date = Query(alias="date", description="Local calendar day, YYYY-MM-DD"),
    tz: str = Query("UTC", description="IANA timezone of the user, e.g. Europe/Paris"),
):
    try:
        ZoneInfo(tz)
    except (ZoneInfoNotFoundError, ValueError):
        raise HTTPException(400, f"Unknown timezone {tz!r}")
    try:
        return await services.matches_for_local_date(date_, tz)
    except ProviderError as exc:
        raise HTTPException(503, f"Data provider unavailable: {exc}")


@router.get("/live")
async def live():
    try:
        return await services.live_matches()
    except ProviderError as exc:
        raise HTTPException(503, f"Data provider unavailable: {exc}")


@router.get("/{match_id}")
async def match_detail(match_id: int):
    try:
        return await services.match_detail(match_id)
    except ProviderError as exc:
        if "not found" in str(exc) or "404" in str(exc):
            raise HTTPException(404, "Match not found")
        raise HTTPException(503, f"Data provider unavailable: {exc}")
