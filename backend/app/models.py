"""ORM tables. The canonical PostgreSQL DDL (with extra indexes) lives in db/schema.sql."""
import uuid
from datetime import datetime, time

from sqlalchemy import (
    JSON,
    BigInteger,
    Boolean,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    Time,
    UniqueConstraint,
    Uuid,
    func,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base

JsonType = JSON().with_variant(JSONB(), "postgresql")
# SQLite only auto-increments INTEGER PRIMARY KEY, so use BIGINT on Postgres only.
BigIntPK = BigInteger().with_variant(Integer(), "sqlite")


class CompetitionRow(Base):
    __tablename__ = "competitions"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)  # provider id
    name: Mapped[str] = mapped_column(String(200))
    code: Mapped[str | None] = mapped_column(String(20))
    country: Mapped[str | None] = mapped_column(String(100))
    emblem_url: Mapped[str | None] = mapped_column(Text)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())


class TeamRow(Base):
    __tablename__ = "teams"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)  # provider id
    name: Mapped[str] = mapped_column(String(200), index=True)
    short_name: Mapped[str | None] = mapped_column(String(100))
    tla: Mapped[str | None] = mapped_column(String(10))
    crest_url: Mapped[str | None] = mapped_column(Text)
    country: Mapped[str | None] = mapped_column(String(100))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())


class TeamCompetitionRow(Base):
    __tablename__ = "team_competitions"

    team_id: Mapped[int] = mapped_column(ForeignKey("teams.id", ondelete="CASCADE"), primary_key=True)
    competition_id: Mapped[int] = mapped_column(ForeignKey("competitions.id", ondelete="CASCADE"), primary_key=True)


class MatchRow(Base):
    __tablename__ = "matches"
    __table_args__ = (
        Index("ix_matches_kickoff", "utc_kickoff"),
        Index("ix_matches_status", "status"),
        Index("ix_matches_home", "home_team_id", "utc_kickoff"),
        Index("ix_matches_away", "away_team_id", "utc_kickoff"),
    )

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)  # provider id
    competition_id: Mapped[int] = mapped_column(ForeignKey("competitions.id"))
    utc_kickoff: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    status: Mapped[str] = mapped_column(String(20))
    minute: Mapped[int | None] = mapped_column(Integer)
    home_team_id: Mapped[int] = mapped_column(ForeignKey("teams.id"))
    away_team_id: Mapped[int] = mapped_column(ForeignKey("teams.id"))
    home_score: Mapped[int | None] = mapped_column(Integer)
    away_score: Mapped[int | None] = mapped_column(Integer)
    pen_home: Mapped[int | None] = mapped_column(Integer)
    pen_away: Mapped[int | None] = mapped_column(Integer)
    # Incremented every time the score goes DOWN (VAR / disallowed goal) so a re-scored
    # goal at the same scoreline gets a fresh notification dedupe key.
    score_revision: Mapped[int] = mapped_column(Integer, default=0, server_default="0")
    # Full normalized app.domain.Match, used for diffing and for the detail endpoint.
    snapshot: Mapped[dict] = mapped_column(JsonType)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())


class MatchEventRow(Base):
    __tablename__ = "match_events"
    __table_args__ = (UniqueConstraint("match_id", "event_key"),)

    id: Mapped[int] = mapped_column(BigIntPK, primary_key=True, autoincrement=True)
    match_id: Mapped[int] = mapped_column(ForeignKey("matches.id", ondelete="CASCADE"), index=True)
    event_key: Mapped[str] = mapped_column(String(100))
    type: Mapped[str] = mapped_column(String(20))
    minute: Mapped[int | None] = mapped_column(Integer)
    extra_minute: Mapped[int | None] = mapped_column(Integer)
    team_id: Mapped[int | None] = mapped_column(BigInteger)
    player_id: Mapped[int | None] = mapped_column(BigInteger)
    player_name: Mapped[str | None] = mapped_column(String(200))
    related_player_name: Mapped[str | None] = mapped_column(String(200))
    detail: Mapped[str | None] = mapped_column(String(200))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class UserRow(Base):
    """Optional Apple/Google sign-in for syncing favorites across devices."""

    __tablename__ = "users"
    __table_args__ = (UniqueConstraint("auth_provider", "subject"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    auth_provider: Mapped[str] = mapped_column(String(20))  # "apple" | "google"
    subject: Mapped[str] = mapped_column(String(255))
    email: Mapped[str | None] = mapped_column(String(255))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class DeviceRow(Base):
    __tablename__ = "devices"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    # sha256 of the bearer secret handed to the app at registration
    secret_hash: Mapped[str] = mapped_column(String(64))
    user_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    fcm_token: Mapped[str | None] = mapped_column(Text, unique=True)
    platform: Mapped[str] = mapped_column(String(10))  # ios | android
    language: Mapped[str] = mapped_column(String(10), default="en")
    timezone: Mapped[str] = mapped_column(String(64), default="UTC")
    notifications_enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    quiet_hours_enabled: Mapped[bool] = mapped_column(Boolean, default=False)
    quiet_start: Mapped[time | None] = mapped_column(Time)
    quiet_end: Mapped[time | None] = mapped_column(Time)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())


# One boolean column per notification category; keys match app.notifications.Category.
NOTIFY_COLUMNS = ("starting_soon", "kickoff", "goals", "red_cards", "half_time", "full_time", "var")


class FavoriteTeamRow(Base):
    __tablename__ = "favorite_teams"
    __table_args__ = (Index("ix_favorite_teams_team", "team_id"),)

    device_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("devices.id", ondelete="CASCADE"), primary_key=True)
    team_id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    position: Mapped[int] = mapped_column(Integer, default=0)
    starting_soon: Mapped[bool] = mapped_column(Boolean, default=True)
    kickoff: Mapped[bool] = mapped_column(Boolean, default=True)
    goals: Mapped[bool] = mapped_column(Boolean, default=True)
    red_cards: Mapped[bool] = mapped_column(Boolean, default=True)
    half_time: Mapped[bool] = mapped_column(Boolean, default=True)
    full_time: Mapped[bool] = mapped_column(Boolean, default=True)
    var: Mapped[bool] = mapped_column(Boolean, default=True)


class FavoriteCompetitionRow(Base):
    __tablename__ = "favorite_competitions"

    device_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("devices.id", ondelete="CASCADE"), primary_key=True)
    competition_id: Mapped[int] = mapped_column(BigInteger, primary_key=True)


class NotificationLogRow(Base):
    """One row per logical notification; the primary key is the dedupe guarantee."""

    __tablename__ = "notification_log"

    dedupe_key: Mapped[str] = mapped_column(String(200), primary_key=True)
    match_id: Mapped[int] = mapped_column(BigInteger, index=True)
    kind: Mapped[str] = mapped_column(String(30))
    title: Mapped[str] = mapped_column(Text)
    recipients: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
