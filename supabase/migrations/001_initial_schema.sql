-- VectorTrack AI — initial Supabase schema
-- Run this in the Supabase SQL editor, or with `supabase db push` / `psql`.
--
-- Security model:
--   * The FastAPI backend writes with the service-role key, which bypasses RLS.
--   * Browser sessions use the anon key plus the signed-in user's JWT, so RLS
--     restricts every read to the caller's own rows.
--   * There are deliberately no UPDATE or DELETE policies for `authenticated`:
--     users cannot rewrite or erase detection history.

create extension if not exists pgcrypto;

create table if not exists public.detections (
    id                 uuid primary key default gen_random_uuid(),
    user_id            uuid not null references auth.users (id) on delete cascade,
    class              text not null,
    confidence         double precision not null check (confidence >= 0 and confidence <= 1),
    source             text,
    media_type         text not null check (media_type in ('image', 'video')),
    original_file_path text,
    result_file_path   text,
    created_at         timestamptz not null default now(),
    metadata           jsonb not null default '{}'::jsonb
);

comment on table public.detections is
    'One row per detected object produced by the VectorTrack AI FastAPI backend.';
comment on column public.detections.original_file_path is
    'Object key of the uploaded media inside the originals bucket.';
comment on column public.detections.result_file_path is
    'Object key of the annotated media inside the results bucket.';
comment on column public.detections.metadata is
    'Bounding box, frame number, thresholds and other per-detection context.';

-- Indexes -------------------------------------------------------------------
create index if not exists detections_user_created_idx
    on public.detections (user_id, created_at desc);
create index if not exists detections_class_idx
    on public.detections (class);

-- Row Level Security --------------------------------------------------------
alter table public.detections enable row level security;

-- Realtime needs the full row identity so RLS is evaluated on every change.
alter table public.detections replica identity full;

drop policy if exists "users read own detections" on public.detections;
create policy "users read own detections"
    on public.detections
    for select
    to authenticated
    using (auth.uid() = user_id);

drop policy if exists "users insert own detections" on public.detections;
create policy "users insert own detections"
    on public.detections
    for insert
    to authenticated
    with check (auth.uid() = user_id);

-- Realtime ------------------------------------------------------------------
-- Adds the table to the publication the frontend subscribes to
-- ("Detection Logs (Supabase Realtime)" in the dashboard).
do $$
begin
    alter publication supabase_realtime add table public.detections;
exception
    when duplicate_object then null;
    when undefined_object then null;
end
$$;
