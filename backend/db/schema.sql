-- Live Football Scores - PostgreSQL schema (PostgreSQL 14+)
-- Applied automatically by docker-compose on first start. The backend also runs
-- SQLAlchemy create_all() at startup, which is a no-op when these tables exist.

CREATE EXTENSION IF NOT EXISTS pg_trgm;   -- fast fuzzy team search

-- Reference data (ids are the data provider's ids) ---------------------------

CREATE TABLE IF NOT EXISTS competitions (
    id          BIGINT PRIMARY KEY,
    name        VARCHAR(200) NOT NULL,
    code        VARCHAR(20),
    country     VARCHAR(100),
    emblem_url  TEXT,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS teams (
    id          BIGINT PRIMARY KEY,
    name        VARCHAR(200) NOT NULL,
    short_name  VARCHAR(100),
    tla         VARCHAR(10),
    crest_url   TEXT,
    country     VARCHAR(100),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_teams_name ON teams (name);
CREATE INDEX IF NOT EXISTS ix_teams_name_trgm ON teams USING gin (lower(name) gin_trgm_ops);
CREATE INDEX IF NOT EXISTS ix_teams_short_trgm ON teams USING gin (lower(short_name) gin_trgm_ops);

CREATE TABLE IF NOT EXISTS team_competitions (
    team_id         BIGINT NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
    competition_id  BIGINT NOT NULL REFERENCES competitions(id) ON DELETE CASCADE,
    PRIMARY KEY (team_id, competition_id)
);

-- Matches -------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS matches (
    id              BIGINT PRIMARY KEY,
    competition_id  BIGINT NOT NULL REFERENCES competitions(id),
    utc_kickoff     TIMESTAMPTZ NOT NULL,
    status          VARCHAR(20) NOT NULL,   -- scheduled|live|halftime|extra_time|penalties|finished|suspended|postponed|abandoned|cancelled
    minute          INTEGER,
    home_team_id    BIGINT NOT NULL REFERENCES teams(id),
    away_team_id    BIGINT NOT NULL REFERENCES teams(id),
    home_score      INTEGER,
    away_score      INTEGER,
    pen_home        INTEGER,
    pen_away        INTEGER,
    score_revision  INTEGER NOT NULL DEFAULT 0,  -- bumped when a goal is disallowed
    snapshot        JSONB NOT NULL,              -- normalized match incl. events/lineups/stats
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_matches_kickoff ON matches (utc_kickoff);
CREATE INDEX IF NOT EXISTS ix_matches_status  ON matches (status);
CREATE INDEX IF NOT EXISTS ix_matches_home    ON matches (home_team_id, utc_kickoff);
CREATE INDEX IF NOT EXISTS ix_matches_away    ON matches (away_team_id, utc_kickoff);

CREATE TABLE IF NOT EXISTS match_events (
    id                   BIGSERIAL PRIMARY KEY,
    match_id             BIGINT NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
    event_key            VARCHAR(100) NOT NULL,   -- type:team:minute:extra (scorer excluded on purpose)
    type                 VARCHAR(20) NOT NULL,
    minute               INTEGER,
    extra_minute         INTEGER,
    team_id              BIGINT,
    player_id            BIGINT,
    player_name          VARCHAR(200),
    related_player_name  VARCHAR(200),            -- assist, or player coming on
    detail               VARCHAR(200),
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (match_id, event_key)
);
CREATE INDEX IF NOT EXISTS ix_match_events_match_id ON match_events (match_id);

-- Users & devices -----------------------------------------------------------

CREATE TABLE IF NOT EXISTS users (
    id             UUID PRIMARY KEY,
    auth_provider  VARCHAR(20) NOT NULL,     -- apple | google
    subject        VARCHAR(255) NOT NULL,
    email          VARCHAR(255),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (auth_provider, subject)
);

CREATE TABLE IF NOT EXISTS devices (
    id                     UUID PRIMARY KEY,           -- anonymous device id
    secret_hash            VARCHAR(64) NOT NULL,       -- sha256 of the device bearer secret
    user_id                UUID REFERENCES users(id) ON DELETE SET NULL,
    fcm_token              TEXT UNIQUE,
    platform               VARCHAR(10) NOT NULL,       -- ios | android
    language               VARCHAR(10) NOT NULL DEFAULT 'en',
    timezone               VARCHAR(64) NOT NULL DEFAULT 'UTC',
    notifications_enabled  BOOLEAN NOT NULL DEFAULT true,
    quiet_hours_enabled    BOOLEAN NOT NULL DEFAULT false,
    quiet_start            TIME,                       -- local time in devices.timezone
    quiet_end              TIME,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS favorite_teams (
    device_id      UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    team_id        BIGINT NOT NULL,
    position       INTEGER NOT NULL DEFAULT 0,
    starting_soon  BOOLEAN NOT NULL DEFAULT true,
    kickoff        BOOLEAN NOT NULL DEFAULT true,
    goals          BOOLEAN NOT NULL DEFAULT true,
    red_cards      BOOLEAN NOT NULL DEFAULT true,
    half_time      BOOLEAN NOT NULL DEFAULT true,
    full_time      BOOLEAN NOT NULL DEFAULT true,
    var            BOOLEAN NOT NULL DEFAULT true,
    PRIMARY KEY (device_id, team_id)
);
CREATE INDEX IF NOT EXISTS ix_favorite_teams_team ON favorite_teams (team_id);

CREATE TABLE IF NOT EXISTS favorite_competitions (
    device_id       UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    competition_id  BIGINT NOT NULL,
    PRIMARY KEY (device_id, competition_id)
);

-- Notifications -------------------------------------------------------------

-- The primary key makes every logical notification send at most once, even with
-- several worker instances or a restart mid-match.
CREATE TABLE IF NOT EXISTS notification_log (
    dedupe_key  VARCHAR(200) PRIMARY KEY,   -- e.g. goal:123456:2-1:r0
    match_id    BIGINT NOT NULL,
    kind        VARCHAR(30) NOT NULL,
    title       TEXT NOT NULL,
    recipients  INTEGER NOT NULL DEFAULT 0,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_notification_log_match_id ON notification_log (match_id);
