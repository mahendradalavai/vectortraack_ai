# VectorTrack AI

VectorTrack AI is a computer vision application that detects and tracks garbage
and rubbish in aerial and ground imagery using Ultralytics YOLOv8. FastAPI
serves the dashboard and the inference API; **Supabase** provides identity
(Supabase Auth), the detection database (Postgres + RLS), media storage
(Storage), and the live detection log (Realtime).

## Architecture

```
 ┌──────────────┐   1. Google sign-in        ┌─────────────────────┐
 │   Browser    │ ─────────────────────────► │  Supabase Auth      │
 │  dashboard   │ ◄───── session JWT ─────── │  (Google provider)  │
 │ static/*.js  │                            └─────────────────────┘
 └──────┬───────┘
        │ 2. POST /detect/image|video
        │    Authorization: Bearer <access_token>
        ▼
 ┌──────────────────────────┐   3. verify token (JWKS, local)
 │  FastAPI  (api.py)       │   4. YOLOv8 + OpenCV inference
 │  auth.py                 │   5. upload media ─► Supabase Storage
 │  supabase_client.py      │      (service-role key, server only)
 └──────────────────────────┘   6. insert rows ──► public.detections
        │                                             │
        │ 7. signed URLs + results                    │ 8. Realtime INSERT
        ▼                                             ▼
 ┌──────────────────────────────────────────────────────────────┐
 │  Browser: annotated media, metrics, and the detection log     │
 └──────────────────────────────────────────────────────────────┘
```

Key design points:

- **The browser never holds a service-role key.** It receives only
  `SUPABASE_URL` and `SUPABASE_ANON_KEY` from `GET /config`.
- **Sign-in is optional.** The dashboard and both detection endpoints work
  signed-out; those scans are attributed to a single shared app account that is
  found (or created once with the service-role key) from `SUPABASE_APP_EMAIL`.
  Signing in with Google takes precedence, so a session's detections stay in its
  own workspace — but a session is never required to use the site.
- **Identity always comes from the server.** A verified JWT's `sub` claim wins;
  any `user_id` sent by the browser is ignored, and a token that is supplied but
  cannot be verified is rejected with `401` rather than silently downgraded.
- **Row Level Security** decides what a session can read: a user sees their own
  detection rows and nothing else.
- **Local disk is scratch space.** Uploads and annotated outputs are written to
  a temporary directory for the duration of a request and deleted afterwards;
  Supabase Storage keeps the permanent copies, exposed through signed URLs.
- **YOLO stays in FastAPI.** Inference is Python, OpenCV, and PyTorch, not edge
  functions.

## Repository structure

- [api.py](api.py) – FastAPI app: dashboard, health, config, image/video detection
- [auth.py](auth.py) – Supabase access-token verification (`Bearer` dependency)
- [supabase_client.py](supabase_client.py) – Storage uploads, signed URLs, detection inserts
- [config.py](config.py) – environment-driven settings
- [supabase/](supabase/) – SQL migrations and Supabase setup instructions
- [static/](static/) – dashboard (`index.html`, `app.js`, `supabase-client.js`, `style.css`)
- [tests/](tests/) – pytest suite (auth, API, Supabase layer, vendor-free check)
- [train.py](train.py) – YOLOv8 training script
- [detect.py](detect.py) – CLI video inference
- [test_image.py](test_image.py) – CLI image inference
- [dataset/](dataset/) – training, validation, and test data
- [models/](models/) – trained weights (`best.pt`, falls back to `yolov8n.pt`)
- [requirements.txt](requirements.txt) – runtime dependencies
- [requirements-dev.txt](requirements-dev.txt) – test dependencies

## Model information

- Base model: YOLOv8n (`yolov8n.pt`)
- Production weights: `models/best.pt` (falls back to `yolov8n.pt` if missing)
- Classes: `garbage`, `rubbish`

`api.py` loads the model once at startup; inference runs in a threadpool so the
event loop stays responsive.

## 1. Environment variables

Copy the template and fill in your own project values:

```bash
cp .env.example .env
```

| Variable | Required | Purpose |
| --- | --- | --- |
| `SUPABASE_URL` | yes | `https://<project-ref>.supabase.co` |
| `SUPABASE_ANON_KEY` | yes | Public key; served to the browser through `/config` |
| `SUPABASE_SERVICE_ROLE_KEY` | yes | **Server only.** Bypasses RLS for backend writes |
| `SUPABASE_ORIGINALS_BUCKET` | no | Defaults to `vectortrack-originals` |
| `SUPABASE_RESULTS_BUCKET` | no | Defaults to `vectortrack-results` |
| `SUPABASE_SIGNED_URL_EXPIRY_SECONDS` | no | Signed URL lifetime, default `3600` |
| `SUPABASE_JWT_SECRET` | no | Only for legacy projects signing tokens with the shared secret |
| `SUPABASE_DEV_USER_ID` | no | Lets the CLI scripts persist detections for one user id |
| `CORS_ALLOW_ORIGINS` | no | Comma-separated allow-list, default `*` |

`.env` is gitignored. Never commit real keys, and never place the service-role
key in `static/`.

Locate all three required values in the Supabase dashboard under
*Project Settings → API*.

## 2. Supabase setup

Full instructions live in [supabase/README.md](supabase/README.md). In short:

1. **Run the migrations** — `supabase/migrations/001_initial_schema.sql` creates
   `public.detections` with indexes, RLS policies, and Realtime publication
   membership; `supabase/migrations/002_storage_buckets.sql` creates the two
   private buckets and their Storage policies. Paste them into the SQL editor,
   or run `supabase db push`, or apply them with `psql`.
2. **Buckets** — `vectortrack-originals` and `vectortrack-results`, both
   private, with object keys shaped `<user_id>/<media_type>/<file>`.
3. **Google sign-in** — create a Web OAuth client in Google Cloud Console with
   redirect URI `https://<project-ref>.supabase.co/auth/v1/callback`, enable the
   Google provider in *Authentication → Providers*, then add your dashboard
   origins (`http://localhost:8000`, production URL) to *Authentication → URL
   Configuration*.
4. **Verify** — `GET /health` should report `"supabase_configured": true`.

### Database schema

`public.detections`, one row per detected object:

| Column | Type | Notes |
| --- | --- | --- |
| `id` | `uuid` | primary key, `gen_random_uuid()` |
| `user_id` | `uuid` | references `auth.users(id)`, cascade delete |
| `class` | `text` | `garbage` / `rubbish` |
| `confidence` | `double precision` | 0–1 |
| `source` | `text` | telemetry tag chosen in the dashboard |
| `media_type` | `text` | `image` or `video` |
| `original_file_path` | `text` | object key in the originals bucket |
| `result_file_path` | `text` | object key in the results bucket |
| `created_at` | `timestamptz` | defaults to `now()` |
| `metadata` | `jsonb` | bbox, frame number, thresholds, class counts |

## 3. Install and run

Python 3.10+ (matching the Docker image) is recommended.

```bash
python -m venv .venv
source .venv/Scripts/activate      # Windows; use .venv/bin/activate on macOS/Linux
pip install -r requirements.txt
python -m uvicorn api:app --host 0.0.0.0 --port 8000
```

Open <http://127.0.0.1:8000/>. The dashboard shows the dashboard, the YOLO
status badge, the Google sign-in button, and the Realtime detection log.

The application starts even when no Supabase variables are set: inference works,
`/health` reports `"supabase_configured": false`, and detection requests are
rejected with a clear `503` instead of crashing. No credential file of any kind
is required on disk.

### Endpoints

| Method | Path | Auth | Description |
| --- | --- | --- | --- |
| `GET` | `/` | no | Dashboard HTML |
| `GET` | `/health` | no | Status, model name, Supabase configuration flag |
| `GET` | `/config` | no | Public Supabase URL + anon key for the dashboard |
| `POST` | `/detect/image` | optional | Image detection; stores media + rows |
| `POST` | `/detect/video` | optional | Per-frame video detection; stores media + rows |

Both detection endpoints accept an optional `Authorization: Bearer <access_token>`
header. Without one the scan is attributed to the shared app account described in
`SUPABASE_APP_EMAIL`; with one, the verified user owns the rows and media.

Detection responses keep their original keys (`detections`, `original_image_url`,
`result_image_url`, `frames_processed`, `class_counts`, …) and add
`detection_count`, `detection_ids`, `media_stored`, and `warning`. Media URLs are
short-lived Supabase signed URLs; if an upload fails the scan still succeeds with
`media_stored: false` and an explanatory `warning`.

## 4. Frontend

- Google sign-in / sign-out with Supabase Auth session handling (PKCE).
- Sign-in is optional: uploads and detections work immediately, and a session
  only decides whose workspace the results are stored in.
- If Storage is unavailable (not configured, or buckets not created yet), the
  backend returns the annotated frame inline so the result is still visible.
- Every request to FastAPI carries `Authorization: Bearer <access_token>`, with
  one silent token refresh on `401`.
- "Detection Logs (Supabase Realtime)" subscribes to `postgres_changes` inserts
  filtered by `user_id=eq.<current user>` and backfills the newest stored
  detections on sign-in.
- `@supabase/supabase-js` is loaded from a pinned CDN build through an import map
  in `static/index.html`.

## 5. Testing

```bash
pip install -r requirements.txt -r requirements-dev.txt
python -m pytest
```

The suite covers `/health`, `/config`, unauthenticated rejection (image and
video), authenticated image and video detection, one-row-per-detection inserts,
Storage uploads, signed URLs, graceful behaviour when environment variables are
missing, token verification (valid, forged, expired, wrong audience), and a
guard that no removed cloud-vendor reference remains in the codebase or
requirements. No network access or real Supabase project is needed.

## 6. Training and CLI inference

```bash
python train.py          # train on dataset/data.yaml
python detect.py         # video inference from videos/ → output/
python test_image.py     # image inference from images/ → output/
```

The CLI scripts print their results and only write to Supabase when
`SUPABASE_DEV_USER_ID` (plus the service-role key) is configured.

## 7. Deployment

The included [Dockerfile](Dockerfile) builds a CPU-only image:

```bash
docker build -t vectortrack-ai .
docker run -p 8080:8080 \
  -e SUPABASE_URL="https://<project-ref>.supabase.co" \
  -e SUPABASE_ANON_KEY="<anon-key>" \
  -e SUPABASE_SERVICE_ROLE_KEY="<service-role-key>" \
  vectortrack-ai
```

Notes for hosted platforms (Cloud Run, Fly.io, Render, ECS…):

- Supply secrets through the platform's secret manager — never bake them into
  the image. `.dockerignore` keeps `.env` and `.venv` out of the build context.
- The container writes only to `/tmp/vectortrack`; no persistent volume is
  needed because media lives in Supabase Storage.
- Add the deployed origin to Supabase *URL Configuration* and to
  `CORS_ALLOW_ORIGINS` if you restrict it.
- Scale instances freely: all shared state is in Supabase.

## Security notes

- The service-role key is used exclusively by the FastAPI process. It is never
  returned by `/config`, never present in `static/`, and never logged.
- Access tokens are verified against the project's public JWKS keys
  (`RS256`/`ES256`) with issuer, audience, and expiry checks. Only the verified
  `sub` claim is used as the user id.
- Both Storage buckets stay private; the dashboard reads time-limited signed
  URLs generated server-side.
- RLS grants `authenticated` users `select` on their own detection rows only.
  There are no update or delete policies, so history cannot be rewritten or
  erased from the browser.
- Temporary media is deleted at the end of every request, including failures.
- `.env` is gitignored and excluded from the Docker build context.
- Rotate keys in the Supabase dashboard if a key is ever exposed.

## License

This project is intended for educational and research use. Confirm the exact
licensing terms for the dataset and model weights before commercial deployment.

## Credits

- Ultralytics YOLOv8
- Supabase (Auth, Postgres, Storage, Realtime)
- FastAPI + OpenCV inference stack
- Roboflow dataset configuration
