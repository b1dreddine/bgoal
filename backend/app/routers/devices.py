"""Anonymous device registration and notification preferences.

POST /devices returns a one-time `secret`; the app keeps it in secure storage and sends it
as `Authorization: Bearer <secret>` on later calls, so nobody can edit another device.
"""
import hashlib
import hmac
import secrets
import uuid
from datetime import time
from typing import Literal
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from fastapi import APIRouter, Depends, Header, HTTPException
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import delete, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import get_session
from app.models import NOTIFY_COLUMNS, DeviceRow, FavoriteCompetitionRow, FavoriteTeamRow

router = APIRouter(prefix="/devices", tags=["devices"])

Language = Literal["en", "fr", "ar"]


class NotificationPrefs(BaseModel):
    starting_soon: bool = True
    kickoff: bool = True
    goals: bool = True
    red_cards: bool = True
    half_time: bool = True
    full_time: bool = True
    var: bool = True


class FavoriteTeam(BaseModel):
    team_id: int
    notifications: NotificationPrefs = Field(default_factory=NotificationPrefs)


class QuietHours(BaseModel):
    enabled: bool = False
    start: time | None = None  # local time, e.g. "22:00"
    end: time | None = None    # may be earlier than start (wraps past midnight)


class _DeviceFields(BaseModel):
    fcm_token: str | None = Field(None, max_length=4096)
    language: Language | None = None
    timezone: str | None = None
    notifications_enabled: bool | None = None
    quiet_hours: QuietHours | None = None
    # When present these REPLACE the stored lists (order = display order).
    favorite_teams: list[FavoriteTeam] | None = Field(None, max_length=100)
    favorite_competitions: list[int] | None = Field(None, max_length=100)

    @field_validator("timezone")
    @classmethod
    def _valid_tz(cls, v: str | None) -> str | None:
        if v is not None:
            try:
                ZoneInfo(v)
            except (ZoneInfoNotFoundError, ValueError):
                raise ValueError(f"unknown timezone {v!r}")
        return v


class DeviceRegister(_DeviceFields):
    platform: Literal["ios", "android"]


class DevicePreferences(_DeviceFields):
    pass


def _hash(secret: str) -> str:
    return hashlib.sha256(secret.encode()).hexdigest()


async def _authorized_device(device_id: uuid.UUID, authorization: str | None, session: AsyncSession) -> DeviceRow:
    device = await session.get(DeviceRow, device_id)
    token = (authorization or "").removeprefix("Bearer ").strip()
    if device is None or not token or not hmac.compare_digest(device.secret_hash, _hash(token)):
        # Same error for "missing" and "wrong secret" so ids can't be probed.
        raise HTTPException(404, "Device not found")
    return device


async def _apply(session: AsyncSession, device: DeviceRow, body: _DeviceFields) -> None:
    if body.fcm_token is not None:
        if body.fcm_token:
            # A token belongs to one install; detach it from any older registration.
            await session.execute(
                update(DeviceRow).where(DeviceRow.fcm_token == body.fcm_token, DeviceRow.id != device.id)
                .values(fcm_token=None)
            )
        device.fcm_token = body.fcm_token or None
    if body.language is not None:
        device.language = body.language
    if body.timezone is not None:
        device.timezone = body.timezone
    if body.notifications_enabled is not None:
        device.notifications_enabled = body.notifications_enabled
    if body.quiet_hours is not None:
        qh = body.quiet_hours
        if qh.enabled and (qh.start is None or qh.end is None):
            raise HTTPException(422, "quiet_hours.start and quiet_hours.end are required when enabled")
        device.quiet_hours_enabled = qh.enabled
        device.quiet_start, device.quiet_end = qh.start, qh.end
    await session.flush()

    if body.favorite_teams is not None:
        await session.execute(delete(FavoriteTeamRow).where(FavoriteTeamRow.device_id == device.id))
        seen = set()
        for pos, fav in enumerate(body.favorite_teams):
            if fav.team_id in seen:
                continue
            seen.add(fav.team_id)
            session.add(FavoriteTeamRow(device_id=device.id, team_id=fav.team_id, position=pos,
                                        **fav.notifications.model_dump()))
    if body.favorite_competitions is not None:
        await session.execute(delete(FavoriteCompetitionRow).where(FavoriteCompetitionRow.device_id == device.id))
        for cid in dict.fromkeys(body.favorite_competitions):
            session.add(FavoriteCompetitionRow(device_id=device.id, competition_id=cid))


async def _serialize(session: AsyncSession, device: DeviceRow) -> dict:
    teams = (await session.execute(
        select(FavoriteTeamRow).where(FavoriteTeamRow.device_id == device.id).order_by(FavoriteTeamRow.position)
    )).scalars()
    comps = (await session.execute(
        select(FavoriteCompetitionRow.competition_id).where(FavoriteCompetitionRow.device_id == device.id)
    )).scalars()
    return {
        "id": str(device.id),
        "platform": device.platform,
        "has_fcm_token": device.fcm_token is not None,
        "language": device.language,
        "timezone": device.timezone,
        "notifications_enabled": device.notifications_enabled,
        "quiet_hours": {
            "enabled": device.quiet_hours_enabled,
            "start": device.quiet_start.strftime("%H:%M") if device.quiet_start else None,
            "end": device.quiet_end.strftime("%H:%M") if device.quiet_end else None,
        },
        "favorite_teams": [
            {"team_id": t.team_id, "notifications": {c: getattr(t, c) for c in NOTIFY_COLUMNS}} for t in teams
        ],
        "favorite_competitions": list(comps),
    }


@router.post("", status_code=201)
async def register_device(body: DeviceRegister, session: AsyncSession = Depends(get_session)):
    secret = secrets.token_urlsafe(32)
    device = DeviceRow(id=uuid.uuid4(), secret_hash=_hash(secret), platform=body.platform,
                       language=body.language or "en", timezone=body.timezone or "UTC",
                       notifications_enabled=True, quiet_hours_enabled=False)
    session.add(device)
    await session.flush()
    await _apply(session, device, body)
    await session.commit()
    return {**await _serialize(session, device), "secret": secret}


@router.get("/{device_id}")
async def get_device(device_id: uuid.UUID, authorization: str | None = Header(None),
                     session: AsyncSession = Depends(get_session)):
    device = await _authorized_device(device_id, authorization, session)
    return await _serialize(session, device)


@router.put("/{device_id}/preferences")
async def update_preferences(device_id: uuid.UUID, body: DevicePreferences, authorization: str | None = Header(None),
                             session: AsyncSession = Depends(get_session)):
    device = await _authorized_device(device_id, authorization, session)
    await _apply(session, device, body)
    await session.commit()
    return await _serialize(session, device)


@router.delete("/{device_id}", status_code=204)
async def delete_device(device_id: uuid.UUID, authorization: str | None = Header(None),
                        session: AsyncSession = Depends(get_session)):
    device = await _authorized_device(device_id, authorization, session)
    await session.execute(delete(FavoriteTeamRow).where(FavoriteTeamRow.device_id == device.id))
    await session.execute(delete(FavoriteCompetitionRow).where(FavoriteCompetitionRow.device_id == device.id))
    await session.delete(device)
    await session.commit()
