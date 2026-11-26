"""Database reads/writes for reference data and match state."""
from collections.abc import Iterable
from datetime import datetime

from sqlalchemy import delete, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import upsert
from app.domain import Competition, Match, MatchStatus, Team
from app.models import CompetitionRow, MatchEventRow, MatchRow, TeamCompetitionRow, TeamRow


async def upsert_competitions(session: AsyncSession, comps: Iterable[Competition]) -> None:
    rows = {c.id: c.model_dump() for c in comps}
    if not rows:
        return
    stmt = upsert(session, CompetitionRow).values(list(rows.values()))
    stmt = stmt.on_conflict_do_update(
        index_elements=[CompetitionRow.id],
        set_={c: stmt.excluded[c] for c in ("name", "code", "country", "emblem_url")},
    )
    await session.execute(stmt)


async def upsert_teams(session: AsyncSession, teams: Iterable[Team], competition_id: int | None = None) -> None:
    rows = {t.id: t.model_dump() for t in teams}
    if not rows:
        return
    stmt = upsert(session, TeamRow).values(list(rows.values()))
    stmt = stmt.on_conflict_do_update(
        index_elements=[TeamRow.id],
        # keep previously known values when a provider payload omits them
        set_={c: func.coalesce(stmt.excluded[c], getattr(TeamRow, c))
              for c in ("name", "short_name", "tla", "crest_url", "country")},
    )
    await session.execute(stmt)
    if competition_id is not None:
        link = upsert(session, TeamCompetitionRow).values(
            [{"team_id": tid, "competition_id": competition_id} for tid in rows]
        ).on_conflict_do_nothing()
        await session.execute(link)


async def save_match(session: AsyncSession, match: Match, score_revision: int) -> None:
    """Persist the latest state of a match (worker-owned; the API never writes match state)."""
    await upsert_competitions(session, [match.competition])
    await upsert_teams(session, [match.home, match.away])
    values = {
        "id": match.id,
        "competition_id": match.competition.id,
        "utc_kickoff": match.utc_kickoff,
        "status": match.status.value,
        "minute": match.minute,
        "home_team_id": match.home.id,
        "away_team_id": match.away.id,
        "home_score": match.score.home,
        "away_score": match.score.away,
        "pen_home": match.score.pen_home,
        "pen_away": match.score.pen_away,
        "score_revision": score_revision,
        "snapshot": match.model_dump(mode="json"),
        "updated_at": datetime.now().astimezone(),
    }
    stmt = upsert(session, MatchRow).values(values)
    stmt = stmt.on_conflict_do_update(index_elements=[MatchRow.id], set_={k: v for k, v in values.items() if k != "id"})
    await session.execute(stmt)

    if match.has_event_data:
        # Replace the event list: handles disallowed goals (removed) and reassigned scorers.
        await session.execute(delete(MatchEventRow).where(MatchEventRow.match_id == match.id))
        seen: set[str] = set()
        rows = []
        for ev in match.events:
            key = ev.key
            n = 1
            while key in seen:  # two events of the same type/team/minute
                n += 1
                key = f"{ev.key}#{n}"
            seen.add(key)
            rows.append(MatchEventRow(
                match_id=match.id, event_key=key, type=ev.type.value, minute=ev.minute, extra_minute=ev.extra_minute,
                team_id=ev.team_id, player_id=ev.player_id, player_name=ev.player_name,
                related_player_name=ev.related_player_name, detail=ev.detail,
            ))
        session.add_all(rows)


async def load_match_states(session: AsyncSession, ids: Iterable[int]) -> dict[int, tuple[Match, int]]:
    ids = list(ids)
    if not ids:
        return {}
    rows = (await session.execute(select(MatchRow).where(MatchRow.id.in_(ids)))).scalars()
    return {r.id: (Match.model_validate(r.snapshot), r.score_revision) for r in rows}


async def stored_in_play_ids(session: AsyncSession) -> list[int]:
    statuses = [s.value for s in MatchStatus if s.is_in_play]
    return list((await session.execute(select(MatchRow.id).where(MatchRow.status.in_(statuses)))).scalars())


async def matches_between(session: AsyncSession, start: datetime, end: datetime) -> list[Match]:
    rows = (await session.execute(
        select(MatchRow.snapshot).where(MatchRow.utc_kickoff >= start, MatchRow.utc_kickoff < end)
    )).scalars()
    return [Match.model_validate(s) for s in rows]


async def search_teams(session: AsyncSession, q: str, limit: int = 20) -> list[Team]:
    pattern = f"%{q.strip()}%"
    rows = (await session.execute(
        select(TeamRow)
        .where(or_(TeamRow.name.ilike(pattern), TeamRow.short_name.ilike(pattern), TeamRow.tla.ilike(q.strip())))
        .order_by(func.length(TeamRow.name))
        .limit(limit)
    )).scalars()
    return [Team(id=r.id, name=r.name, short_name=r.short_name, tla=r.tla, crest_url=r.crest_url, country=r.country)
            for r in rows]


async def get_team(session: AsyncSession, team_id: int) -> Team | None:
    r = await session.get(TeamRow, team_id)
    if r is None:
        return None
    return Team(id=r.id, name=r.name, short_name=r.short_name, tla=r.tla, crest_url=r.crest_url, country=r.country)


async def competition_teams(session: AsyncSession) -> list[tuple[Competition, list[Team]]]:
    """Every tracked competition with its teams (filled by the worker's team sync)."""
    rows = (await session.execute(
        select(CompetitionRow, TeamRow)
        .join(TeamCompetitionRow, TeamCompetitionRow.competition_id == CompetitionRow.id)
        .join(TeamRow, TeamRow.id == TeamCompetitionRow.team_id)
        .order_by(CompetitionRow.name, TeamRow.name)
    )).all()
    grouped: dict[int, tuple[Competition, list[Team]]] = {}
    for c, t in rows:
        entry = grouped.setdefault(c.id, (
            Competition(id=c.id, name=c.name, code=c.code, country=c.country, emblem_url=c.emblem_url), []))
        entry[1].append(Team(id=t.id, name=t.name, short_name=t.short_name, tla=t.tla, crest_url=t.crest_url,
                             country=t.country))
    return list(grouped.values())


async def team_competitions(session: AsyncSession, team_id: int) -> list[Competition]:
    rows = (await session.execute(
        select(CompetitionRow).join(TeamCompetitionRow, TeamCompetitionRow.competition_id == CompetitionRow.id)
        .where(TeamCompetitionRow.team_id == team_id)
    )).scalars()
    return [Competition(id=r.id, name=r.name, code=r.code, country=r.country, emblem_url=r.emblem_url) for r in rows]
