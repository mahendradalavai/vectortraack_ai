# Supabase setup for VectorTrack AI

All cloud state lives in Supabase: Auth for identity, Postgres for detection
records, Storage for media, and Realtime for the live detection log. The
FastAPI process holds the service-role key; the browser only ever sees the
public anon key plus the signed-in user's access token.

## Files

| File | Purpose |
| --- | --- |
| `migrations/001_initial_schema.sql` | `public.detections` table, indexes, RLS policies, Realtime publication |
| `migrations/002_storage_buckets.sql` | `vectortrack-originals` + `vectortrack-results` buckets and their Storage policies |

## 1. Run the migrations

**Option A — SQL editor (fastest):** open your project → *SQL Editor* → paste
`001_initial_schema.sql`, run it, then do the same with `002_storage_buckets.sql`.

**Option B — Supabase CLI:**

```bash
supabase link --project-ref <your-project-ref>
supabase db push
```

**Option C — psql:**

```bash
psql "$SUPABASE_DB_URL" -f supabase/migrations/001_initial_schema.sql
psql "$SUPABASE_DB_URL" -f supabase/migrations/002_storage_buckets.sql
```

Verify in *Table Editor* that `public.detections` exists, has RLS enabled, and
that *Database → Publications → supabase_realtime* lists the table.

## 2. Buckets

`002_storage_buckets.sql` creates both buckets as **private**:

- `vectortrack-originals` — the file the operator uploaded
- `vectortrack-results` — the annotated image/video YOLO produced

Object keys are `<user_id>/<media_type>/<file_name>`, which is what the Storage
policies match on. Do not make these buckets public; the dashboard displays
files through signed URLs that expire (default 3600 s).

## 3. Google sign-in

1. Google Cloud Console → *APIs & Services* → *Credentials* → **Create OAuth
   client ID** → *Web application*.
2. Authorized redirect URI:
   `https://<your-project-ref>.supabase.co/auth/v1/callback`
3. Supabase dashboard → *Authentication* → *Providers* → **Google** → enable it
   and paste the Client ID / Client Secret from step 1.
4. Supabase dashboard → *Authentication* → *URL Configuration*:
   - **Site URL:** where the dashboard is served, e.g. `http://localhost:8000`
   - **Redirect URLs:** add every origin you sign in from, e.g.
     `http://localhost:8000`, `https://your-app.example.com`.

The frontend calls `signInWithOAuth({ provider: 'google' })` with
`redirectTo: window.location.origin`, so the origin must be allow-listed here.

## 4. Verify

```sql
-- RLS should be on and both policies present
select relname, relrowsecurity from pg_class where relname = 'detections';

select policyname, cmd from pg_policies where tablename = 'detections';
```

Then start the API and confirm `GET /health` reports
`"supabase_configured": true`, sign in from the dashboard, and run a detection.
A new row should appear in `public.detections` with `user_id` equal to the
signed-in user's id.
