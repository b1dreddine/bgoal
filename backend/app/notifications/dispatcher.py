"""Fan a Notice out to every subscribed device, at most once."""
import logging
from collections import defaultdict
from datetime import datetime, time, timezone
from zoneinfo import ZoneInfo

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import upsert
from app.models import DeviceRow, FavoriteTeamRow, NotificationLogRow
from app.notifications.diff import CATEGORY, Notice
from app.notifications.messages import render
from app.notifications.sender import Push, PushSender

log = logging.getLogger(__name__)


def in_quiet_hours(now_utc: datetime, tz_name: str, start: time | None, end: time | None) -> bool:
    if start is None or end is None or start == end:
        return False
    try:
        local = now_utc.astimezone(ZoneInfo(tz_name)).time()
    except Exception:
        local = now_utc.time()
    if start < end:
        return start <= local < end
    return local >= start or local < end  # window wraps past midnight, e.g. 22:00-07:00


async def _claim(session: AsyncSession, notice: Notice, title: str) -> bool:
    """Insert the dedupe row; False if this notification was already sent (by us or another worker)."""
    stmt = upsert(session, NotificationLogRow).values(
        dedupe_key=notice.dedupe_key, match_id=notice.match.id, kind=notice.kind.value, title=title, recipients=0,
    ).on_conflict_do_nothing()
    result = await session.execute(stmt)
    await session.commit()
    return result.rowcount == 1


async def dispatch(session: AsyncSession, notice: Notice, sender: PushSender, now: datetime | None = None) -> int:
    """Returns the number of devices the notification was sent to."""
    now = now or datetime.now(timezone.utc)
    if not await _claim(session, notice, render(notice, "en")[0]):
        return 0

    column = getattr(FavoriteTeamRow, CATEGORY[notice.kind])
    rows = (await session.execute(
        select(DeviceRow.id, DeviceRow.fcm_token, DeviceRow.language, DeviceRow.timezone,
               DeviceRow.quiet_hours_enabled, DeviceRow.quiet_start, DeviceRow.quiet_end)
        .join(FavoriteTeamRow, FavoriteTeamRow.device_id == DeviceRow.id)
        .where(
            FavoriteTeamRow.team_id.in_([notice.match.home.id, notice.match.away.id]),
            column.is_(True),
            DeviceRow.notifications_enabled.is_(True),
            DeviceRow.fcm_token.is_not(None),
        )
    )).all()

    by_language: dict[str, list[str]] = defaultdict(list)
    seen: set = set()
    for r in rows:
        if r.id in seen:  # device follows both teams
            continue
        seen.add(r.id)
        if r.quiet_hours_enabled and in_quiet_hours(now, r.timezone, r.quiet_start, r.quiet_end):
            continue
        by_language[r.language].append(r.fcm_token)

    sent, invalid = 0, []
    data = {
        "type": notice.kind.value,
        "match_id": str(notice.match.id),
        "deep_link": f"bgoal://match/{notice.match.id}",
    }
    for language, tokens in by_language.items():
        title, body = render(notice, language)
        invalid += await sender.send(Push(tokens=tokens, title=title, body=body, data=data,
                                          thread_id=f"match_{notice.match.id}"))
        sent += len(tokens)

    if invalid:
        await session.execute(update(DeviceRow).where(DeviceRow.fcm_token.in_(invalid)).values(fcm_token=None))
    await session.execute(update(NotificationLogRow).where(NotificationLogRow.dedupe_key == notice.dedupe_key)
                          .values(recipients=sent - len(invalid)))
    await session.commit()
    log.info("notified %s -> %d devices", notice.dedupe_key, sent)
    return sent
