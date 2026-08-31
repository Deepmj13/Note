-- =====================================================================
-- Notes App: initial schema for Supabase (PostgreSQL)
-- Paste this into the Supabase SQL Editor (Dashboard > SQL > New query)
-- and run it once. Tables are RLS-protected; only the signed-in user can
-- read/write their own rows.
--
-- IMPORTANT: `updated_at` is client-authored and written as-is (no
-- server trigger overwriting it) so that last-write-wins conflict
-- resolution stays consistent between devices.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Profiles (one row per auth user, created automatically on signup)
-- ---------------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text,
  display_name text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, email, display_name, avatar_url)
  values (
    new.id,
    new.email,
    coalesce(
      new.raw_user_meta_data ->> 'display_name',
      new.raw_user_meta_data ->> 'full_name',
      ''
    ),
    coalesce(new.raw_user_meta_data ->> 'avatar_url', '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ---------------------------------------------------------------------
-- Notes
-- ---------------------------------------------------------------------
create table if not exists public.notes (
  id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  title text not null default '',
  content text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  is_deleted boolean not null default false,
  version bigint not null default 1,
  is_favorite boolean not null default false,
  is_pinned boolean not null default false,
  note_type text not null default 'text',
  folder_id uuid
);

create index if not exists notes_user_updated_idx
  on public.notes (user_id, updated_at);
create index if not exists notes_user_deleted_idx
  on public.notes (user_id, is_deleted);

-- ---------------------------------------------------------------------
-- Folders
-- ---------------------------------------------------------------------
create table if not exists public.folders (
  id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null default '',
  parent_folder_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  is_deleted boolean not null default false
);

create index if not exists folders_user_updated_idx
  on public.folders (user_id, updated_at);

-- ---------------------------------------------------------------------
-- Foreign keys (added here because `folders` is created after `notes`).
-- `on delete set null` keeps references safe if a row is ever hard-deleted
-- (the app only soft-deletes, so this never fires in normal operation).
-- ---------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'notes_folder_id_fkey'
  ) then
    alter table public.notes
      add constraint notes_folder_id_fkey
      foreign key (folder_id) references public.folders (id) on delete set null;
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'folders_parent_folder_id_fkey'
  ) then
    alter table public.folders
      add constraint folders_parent_folder_id_fkey
      foreign key (parent_folder_id) references public.folders (id)
      on delete set null;
  end if;
end
$$;

-- ---------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.notes enable row level security;
alter table public.folders enable row level security;

-- Profiles: users manage their own profile only
drop policy if exists profiles_select_own on public.profiles;
create policy profiles_select_own
  on public.profiles for select
  using (auth.uid() = id);

drop policy if exists profiles_insert_own on public.profiles;
create policy profiles_insert_own
  on public.profiles for insert
  with check (auth.uid() = id);

drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own
  on public.profiles for update
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- Notes: users manage their own notes only
drop policy if exists notes_select_own on public.notes;
create policy notes_select_own
  on public.notes for select
  using (auth.uid() = user_id);

drop policy if exists notes_insert_own on public.notes;
create policy notes_insert_own
  on public.notes for insert
  with check (auth.uid() = user_id);

drop policy if exists notes_update_own on public.notes;
create policy notes_update_own
  on public.notes for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists notes_delete_own on public.notes;
create policy notes_delete_own
  on public.notes for delete
  using (auth.uid() = user_id);

-- Folders: users manage their own folders only
drop policy if exists folders_select_own on public.folders;
create policy folders_select_own
  on public.folders for select
  using (auth.uid() = user_id);

drop policy if exists folders_insert_own on public.folders;
create policy folders_insert_own
  on public.folders for insert
  with check (auth.uid() = user_id);

drop policy if exists folders_update_own on public.folders;
create policy folders_update_own
  on public.folders for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists folders_delete_own on public.folders;
create policy folders_delete_own
  on public.folders for delete
  using (auth.uid() = user_id);

-- ---------------------------------------------------------------------
-- Optional: grant usage on the public schema (needed for PostgREST).
-- Table/routine privileges go to `authenticated` only: `anon` is filtered
-- to zero rows by RLS and needs no DML grants here.
-- ---------------------------------------------------------------------
grant usage on schema public to anon, authenticated;
grant all on all tables in schema public to authenticated;
grant all on all routines in schema public to authenticated;
grant all on all sequences in schema public to authenticated;
