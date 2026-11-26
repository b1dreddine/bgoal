from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app import services
from app.db import get_session
from app.providers import ProviderError

router = APIRouter(tags=["teams"])


@router.get("/teams/search")
async def search_teams(q: str = Query(min_length=2, max_length=50), session: AsyncSession = Depends(get_session)):
    try:
        return {"data": await services.search_teams(session, q)}
    except ProviderError as exc:
        raise HTTPException(503, f"Data provider unavailable: {exc}")


@router.get("/teams/browse")
async def browse_teams(session: AsyncSession = Depends(get_session)):
    """Teams of the tracked competitions, grouped by competition (local data, no provider call)."""
    return {"data": await services.browse_teams(session)}


@router.get("/teams/{team_id}")
async def team(team_id: int, session: AsyncSession = Depends(get_session)):
    try:
        return await services.team_overview(session, team_id)
    except ProviderError as exc:
        if "not found" in str(exc) or "404" in str(exc):
            raise HTTPException(404, "Team not found")
        raise HTTPException(503, f"Data provider unavailable: {exc}")


@router.get("/competitions/{competition_id}/standings")
async def standings(competition_id: int):
    try:
        return await services.standings(competition_id)
    except ProviderError as exc:
        raise HTTPException(503, f"Data provider unavailable: {exc}")
