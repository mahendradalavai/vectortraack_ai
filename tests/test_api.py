"""API-level tests for the VectorTrack AI backend."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from tests.conftest import (
    DETECTION_FORM,
    OTHER_USER_ID,
    TEST_USER_ID,
    FakeBox,
    FakeYOLO,
    image_files,
    video_files,
)


# ── GET / ────────────────────────────────────────────────────────────────────

@pytest.mark.anyio
async def test_root_serves_dashboard(client):
    async with client as http:
        response = await http.get("/")

    assert response.status_code == 200
    assert "VectorTrack AI" in response.text
    assert "Detection Logs (Supabase Realtime)" in response.text


# ── GET /health ──────────────────────────────────────────────────────────────

@pytest.mark.anyio
async def test_health_reports_model_and_unconfigured_supabase(client, unconfigured):
    async with client as http:
        response = await http.get("/health")

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "healthy"
    assert body["model_loaded"] is True
    assert body["model_name"].endswith(".pt")
    assert body["supabase_configured"] is False


@pytest.mark.anyio
async def test_health_reports_configured_supabase(client, configured):
    async with client as http:
        response = await http.get("/health")

    assert response.json()["supabase_configured"] is True


# ── GET /config ──────────────────────────────────────────────────────────────

@pytest.mark.anyio
async def test_config_exposes_public_values_only(client, configured):
    from tests.conftest import FAKE_ANON_KEY, FAKE_SERVICE_ROLE_KEY, FAKE_SUPABASE_URL

    async with client as http:
        response = await http.get("/config")

    assert response.status_code == 200
    body = response.json()
    assert body["supabase_url"] == FAKE_SUPABASE_URL
    assert body["supabase_anon_key"] == FAKE_ANON_KEY
    assert body["originals_bucket"] == "vectortrack-originals"
    assert body["results_bucket"] == "vectortrack-results"
    assert body["configured"] is True
    # the service-role key must never reach the browser
    assert FAKE_SERVICE_ROLE_KEY not in response.text
    assert "service_role" not in json.dumps(body)


# ── No sign-in required ─────────────────────────────────────────────────────
# The dashboard is usable without a session; such scans belong to the shared
# app account. A token that is present but unverifiable is still rejected.

@pytest.mark.anyio
async def test_image_detection_works_without_a_session(client, cloud):
    async with client as http:
        response = await http.post("/detect/image", files=image_files(), data=DETECTION_FORM)

    assert response.status_code == 201
    body = response.json()
    assert body["success"] is True
    assert body["identity_mode"] == "app-account"
    assert len(cloud.inserts) == 1
    assert cloud.inserts[0]["user_id"] == TEST_USER_ID
    assert all(upload["path"].startswith(f"{TEST_USER_ID}/") for upload in cloud.uploads)


@pytest.mark.anyio
async def test_video_detection_works_without_a_session(client, cloud, monkeypatch):
    import api

    def fake_process_video(video_path, result_path, conf, iou):
        Path(result_path).write_bytes(b"annotated-video-bytes")
        return {
            "frames_processed": 1,
            "total_frames": 1,
            "total_detections": 1,
            "class_counts": {"garbage": 1},
            "detections": [
                {"frame": 1, "class": "garbage", "confidence": 0.9, "bbox": [0.0, 0.0, 1.0, 1.0]}
            ],
        }

    monkeypatch.setattr(api, "_process_video", fake_process_video)

    async with client as http:
        response = await http.post("/detect/video", files=video_files(), data=DETECTION_FORM)

    assert response.status_code == 201
    body = response.json()
    assert body["identity_mode"] == "app-account"
    assert body["result_video_url"].startswith("https://signed.test/vectortrack-results/")
    assert cloud.inserts[0]["media_type"] == "video"


@pytest.mark.anyio
async def test_malformed_bearer_token_is_still_rejected(client, cloud):
    """A supplied-but-broken session must not be silently filed anonymously."""
    headers = {"Authorization": "Bearer not-a-jwt"}
    async with client as http:
        response = await http.post(
            "/detect/image", files=image_files(), data=DETECTION_FORM, headers=headers
        )

    assert response.status_code == 401
    assert response.headers.get("www-authenticate") == "Bearer"
    assert cloud.inserts == []
    assert cloud.uploads == []


@pytest.mark.anyio
async def test_detection_without_any_identity_still_returns_results(
    client, cloud, monkeypatch
):
    """No Supabase identity at all: infer, upload media, skip the database."""
    import api

    monkeypatch.setattr(api, "resolve_app_user_id", lambda: None)

    async with client as http:
        response = await http.post("/detect/image", files=image_files(), data=DETECTION_FORM)

    assert response.status_code == 201
    body = response.json()
    assert body["success"] is True
    assert body["detections"]
    assert cloud.inserts == []
    assert body["warning"]
    assert all(upload["path"].startswith("anonymous/") for upload in cloud.uploads)


@pytest.mark.anyio
async def test_annotated_image_is_returned_inline_when_storage_fails(
    client, cloud, monkeypatch
):
    """The operator still sees the YOLO result with no Storage available."""
    import api

    monkeypatch.setattr(api, "upload_media", lambda *args, **kwargs: None)
    monkeypatch.setattr(api, "create_signed_url", lambda *args, **kwargs: None)

    async with client as http:
        response = await http.post("/detect/image", files=image_files(), data=DETECTION_FORM)

    assert response.status_code == 201
    body = response.json()
    assert body["result_image_url"] is None
    assert body["result_image_data_url"].startswith("data:image/jpeg;base64,")
    assert body["media_stored"] is False


# ── Authenticated image detection ────────────────────────────────────────────

@pytest.mark.anyio
async def test_authenticated_image_detection(client, cloud, as_user, configured):
    as_user()

    async with client as http:
        response = await http.post("/detect/image", files=image_files(), data=DETECTION_FORM)

    assert response.status_code == 201
    body = response.json()

    # Existing response contract — the dashboard depends on every one of these.
    for key in (
        "success",
        "message",
        "image_name",
        "source",
        "conf_threshold",
        "detections",
        "original_image_url",
        "result_image_url",
    ):
        assert key in body

    assert body["success"] is True
    assert body["source"] == "drone-cam-02"
    assert body["conf_threshold"] == pytest.approx(0.10)
    assert body["identity_mode"] == "signed-in"
    assert body["detections"] == [
        {"class": "garbage", "confidence": pytest.approx(0.91), "bbox": [1.0, 2.0, 3.0, 4.0]}
    ]

    # Signed URLs point at the private buckets.
    assert body["original_image_url"].startswith("https://signed.test/vectortrack-originals/")
    assert body["result_image_url"].startswith("https://signed.test/vectortrack-results/")

    # One row per detected object, attributed to the verified token subject.
    assert len(cloud.inserts) == 1
    insert = cloud.inserts[0]
    assert insert["user_id"] == TEST_USER_ID
    assert insert["class_name"] == "garbage"
    assert insert["media_type"] == "image"
    assert insert["source"] == "drone-cam-02"
    assert insert["original_file_path"].startswith(f"{TEST_USER_ID}/image/")
    assert insert["result_file_path"].startswith(f"{TEST_USER_ID}/image/")
    assert insert["metadata"]["bbox"] == [1.0, 2.0, 3.0, 4.0]

    assert sorted(upload["bucket"] for upload in cloud.uploads) == [
        "vectortrack-originals",
        "vectortrack-results",
    ]
    assert all(upload["path"].startswith(f"{TEST_USER_ID}/image/") for upload in cloud.uploads)
    assert body["detection_ids"] == ["row-1"]


@pytest.mark.anyio
async def test_one_row_per_detected_object(client, cloud, as_user, configured, monkeypatch):
    import api

    monkeypatch.setattr(
        api,
        "model",
        FakeYOLO([FakeBox(0, 0.90, [0.0, 0.0, 1.0, 1.0]), FakeBox(1, 0.55, [2.0, 2.0, 3.0, 3.0])]),
    )
    as_user()

    async with client as http:
        response = await http.post("/detect/image", files=image_files(), data=DETECTION_FORM)

    assert response.status_code == 201
    assert [insert["class_name"] for insert in cloud.inserts] == ["garbage", "rubbish"]
    assert [det["class"] for det in response.json()["detections"]] == ["garbage", "rubbish"]


@pytest.mark.anyio
async def test_browser_supplied_user_id_is_ignored(client, cloud, as_user, configured):
    as_user()
    form = dict(DETECTION_FORM, user_id=OTHER_USER_ID)

    async with client as http:
        response = await http.post("/detect/image", files=image_files(), data=form)

    assert response.status_code == 201
    assert cloud.inserts[0]["user_id"] == TEST_USER_ID
    assert all(upload["path"].startswith(TEST_USER_ID) for upload in cloud.uploads)


@pytest.mark.anyio
async def test_unsupported_image_format_is_rejected(client, as_user, configured):
    as_user()

    async with client as http:
        response = await http.post(
            "/detect/image",
            files={"file": ("notes.txt", b"hello", "text/plain")},
            data=DETECTION_FORM,
        )

    assert response.status_code == 400
    assert "Unsupported image format" in response.json()["detail"]


@pytest.mark.anyio
async def test_detection_returns_503_without_a_loaded_model(client, as_user, configured, monkeypatch):
    import api

    monkeypatch.setattr(api, "model", None)
    as_user()

    async with client as http:
        response = await http.post("/detect/image", files=image_files(), data=DETECTION_FORM)

    assert response.status_code == 503
    assert "model" in response.json()["detail"].lower()


# ── Authenticated video detection ────────────────────────────────────────────

@pytest.mark.anyio
async def test_authenticated_video_detection(client, cloud, as_user, configured, monkeypatch):
    import api

    summary = {
        "frames_processed": 3,
        "total_frames": 3,
        "total_detections": 2,
        "class_counts": {"garbage": 2},
        "detections": [
            {"frame": 1, "class": "garbage", "confidence": 0.80, "bbox": [0.0, 0.0, 1.0, 1.0]},
            {"frame": 2, "class": "garbage", "confidence": 0.70, "bbox": [0.0, 0.0, 1.0, 1.0]},
        ],
    }

    def fake_process_video(video_path, result_path, conf, iou):
        Path(result_path).write_bytes(b"annotated-video-bytes")
        return summary

    monkeypatch.setattr(api, "_process_video", fake_process_video)
    as_user()

    async with client as http:
        response = await http.post("/detect/video", files=video_files(), data=DETECTION_FORM)

    assert response.status_code == 201
    body = response.json()

    for key in (
        "success",
        "message",
        "video_name",
        "source",
        "frames_processed",
        "total_frames",
        "total_detections",
        "class_counts",
        "detections",
        "original_video_url",
        "result_video_url",
    ):
        assert key in body

    assert body["frames_processed"] == 3
    assert body["total_detections"] == 2
    assert body["class_counts"] == {"garbage": 2}
    assert body["result_video_url"].startswith("https://signed.test/vectortrack-results/")

    assert len(cloud.inserts) == 2
    assert all(insert["media_type"] == "video" for insert in cloud.inserts)
    assert [insert["metadata"]["frame"] for insert in cloud.inserts] == [1, 2]
    assert cloud.inserts[0]["metadata"]["class_counts"] == {"garbage": 2}
    assert all(upload["path"].startswith(f"{TEST_USER_ID}/video/") for upload in cloud.uploads)


# ── Storage / cleanup behaviour ──────────────────────────────────────────────

@pytest.mark.anyio
async def test_storage_failure_is_reported_without_failing_the_scan(
    client, cloud, as_user, configured, monkeypatch
):
    import api

    monkeypatch.setattr(api, "upload_media", lambda *args, **kwargs: None)
    monkeypatch.setattr(api, "create_signed_url", lambda *args, **kwargs: None)
    as_user()

    async with client as http:
        response = await http.post("/detect/image", files=image_files(), data=DETECTION_FORM)

    assert response.status_code == 201
    body = response.json()
    assert body["success"] is True
    assert body["media_stored"] is False
    assert body["original_image_url"] is None
    assert body["result_image_url"] is None
    assert body["warning"]
    # the detection itself is still recorded, just without media paths
    assert len(cloud.inserts) == 1
    assert cloud.inserts[0]["original_file_path"] is None


@pytest.mark.anyio
async def test_local_temp_files_are_cleaned_up(client, as_user, configured):
    import api

    as_user()

    async with client as http:
        response = await http.post("/detect/image", files=image_files(), data=DETECTION_FORM)

    assert response.status_code == 201
    assert list(api.SCRATCH_DIR.iterdir()) == []


@pytest.mark.anyio
async def test_video_temp_files_are_cleaned_up(client, as_user, configured, monkeypatch):
    import api

    def fake_process_video(video_path, result_path, conf, iou):
        Path(result_path).write_bytes(b"annotated-video-bytes")
        return {
            "frames_processed": 1,
            "total_frames": 1,
            "total_detections": 0,
            "class_counts": {},
            "detections": [],
        }

    monkeypatch.setattr(api, "_process_video", fake_process_video)
    as_user()

    async with client as http:
        response = await http.post("/detect/video", files=video_files(), data=DETECTION_FORM)

    assert response.status_code == 201
    assert list(api.SCRATCH_DIR.iterdir()) == []
