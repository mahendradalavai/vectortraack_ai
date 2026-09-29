-- VectorTrack AI — Supabase Storage buckets and policies
--
-- Buckets stay private. FastAPI uploads with the service-role key (which
-- bypasses these policies) and hands the browser short-lived signed URLs.
-- The policies below are the safety net for any direct browser access: a
-- signed-in user can only touch objects under a folder named after their own
-- user id, i.e. "<user_id>/<media_type>/<file>".

insert into storage.buckets (id, name, public)
values
    ('vectortrack-originals', 'vectortrack-originals', false),
    ('vectortrack-results',   'vectortrack-results',   false)
on conflict (id) do nothing;

drop policy if exists "users read own media" on storage.objects;
create policy "users read own media"
    on storage.objects
    for select
    to authenticated
    using (
        bucket_id in ('vectortrack-originals', 'vectortrack-results')
        and (storage.foldername(name))[1] = auth.uid()::text
    );

drop policy if exists "users upload own media" on storage.objects;
create policy "users upload own media"
    on storage.objects
    for insert
    to authenticated
    with check (
        bucket_id in ('vectortrack-originals', 'vectortrack-results')
        and (storage.foldername(name))[1] = auth.uid()::text
    );

-- Updates and deletes are intentionally left to the service-role key only.
