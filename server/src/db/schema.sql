-- =====================================================================
-- Notes App: backend schema (PostgreSQL, e.g. Neon)
-- Applied by `npm run migrate` (see src/db/migrate.ts). Idempotent.
--
-- Mirrors the Drift local schema 1:1. Every row is scoped to a user_id;
-- the API layer enforces that user_id always comes from the JWT, never
-- from the client body.
-- =====================================================================

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------
-- Users (email/password authentication, bcrypt password hash)
-- ---------------------------------------------------------------------
create table if not exists users (
  id            uuid primary key default gen_random_uuid(),
  email         text not null unique,
  password_hash text not null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Notes
-- ---------------------------------------------------------------------
create table if not exists notes (
  id          uuid primary key,
  user_id     uuid not null references users (id) on delete cascade,
  title       text not null default '',
  content     text not null default '',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  is_deleted  boolean not null default false,
  version     bigint not null default 1,
  is_favorite boolean not null default false,
  is_pinned   boolean not null default false,
  note_type   text not null default 'text',
  folder_id   uuid
);

create index if not exists notes_user_updated_idx on notes (user_id, updated_at);
create index if not exists notes_user_deleted_idx on notes (user_id, is_deleted);

-- ---------------------------------------------------------------------
-- Folders
-- ---------------------------------------------------------------------
create table if not exists folders (
  id               uuid primary key,
  user_id          uuid not null references users (id) on delete cascade,
  name             text not null default '',
  parent_folder_id uuid,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  is_deleted       boolean not null default false
);

create index if not exists folders_user_updated_idx on folders (user_id, updated_at);
