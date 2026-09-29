"""Shared fixtures for the VectorTrack AI test suite.

Nothing here talks to a real Supabase project: the cloud layer is replaced by
recording fakes, and the YOLO model is replaced by a deterministic stub.
"""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

import httpx
import numpy as np
import pytest

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

TEST_USER_ID = "11111111-2222-3333-4444-555555555555"
OTHER_USER_ID = "99999999-8888-7777-6666-555555555555"
TEST_USER_EMAIL = "operator@example.com"

# Fake, obviously non-production values used only to exercise the config paths.
FAKE_SUPABASE_URL = "https://test-project.supabase.co"
FAKE_ANON_KEY = "test-anon-key"
FAKE_SERVICE_ROLE_KEY = "test-service-role-key"


@pytest.fixture
def anyio_backend() -> str:
    """Run async tests on asyncio via the anyio pytest plugin."""
    return "asyncio"


# ── Fake YOLO model ──────────────────────────────────────────────────────────

class FakeBox:
    def __init__(self, class_id: int, confidence: float, xyxy: List[float]):
        self.cls = [class_id]
        self.conf = [confidence]
        self.xyxy = [xyxy]


class FakeResult:
    """Mimics the pieces of an Ultralytics result the API touches."""

    def __init__(self, boxes: List[FakeBox]):
        self.boxes = boxes

    def plot(self) -> np.ndarray:
        return np.zeros((16, 16, 3), dtype=np.uint8)


class FakeYOLO:
    names = {0: "garbage", 1: "rubbish"}

    def __init__(self, boxes: Optional[List[FakeBox]] = None):
        self.boxes = boxes if boxes is not None else [FakeBox(0, 0.91, [1.0, 2.0, 3.0, 4.0])]
        self.calls: List[Dict[str, Any]] = []

    def __call__(self, source, conf=0.10, iou=0.45, stream=False, verbose=False, **kwargs):
        self.calls.append({"source": str(source), "conf": conf, "iou": iou, "stream": stream})
        if stream:
            return iter([FakeResult(list(self.boxes))])
        return [FakeResult(list(self.boxes))]


@pytest.fixture
def fake_model() -> FakeYOLO:
    return FakeYOLO()


# ── Cloud recorder ───────────────────────────────────────────────────────────

class CloudRecorder:
    """Captures every Supabase interaction the API performs."""

    def __init__(self) -> None:
        self.inserts: List[Dict[str, Any]] = []
        self.uploads: List[Dict[str, Any]] = []
        self.signs: List[Dict[str, Any]] = []


@pytest.fixture
def cloud(monkeypatch) -> CloudRecorder:
    """Replace the supabase_client helpers used by api.py."""
    import api

    recorder = CloudRecorder()

    def fake_upload_media(bucket, path, content, content_type="application/octet-stream"):
        recorder.uploads.append(
            {"bucket": bucket, "path": path, "content": content, "content_type": content_type}
        )
        return path

    def fake_create_signed_url(bucket, path, expires_in=None):
        recorder.signs.append({"bucket": bucket, "path": path, "expires_in": expires_in})
        return f"https://signed.test/{bucket}/{path}"

    def fake_insert_detection(**kwargs):
        recorder.inserts.append(kwargs)
        return dict(kwargs, id=f"row-{len(recorder.inserts)}")

    monkeypatch.setattr(api, "upload_media", fake_upload_media)
    monkeypatch.setattr(api, "create_signed_url", fake_create_signed_url)
    monkeypatch.setattr(api, "insert_detection", fake_insert_detection)
    # Signed-out requests fall back to the shared app account; tests pin it to
    # the known test user id so attribution is deterministic.
    monkeypatch.setattr(api, "resolve_app_user_id", lambda: TEST_USER_ID)
    return recorder


# ── Settings helpers ─────────────────────────────────────────────────────────

@pytest.fixture
def configured(monkeypatch) -> None:
    """Pretend the Supabase environment is fully populated (fake values only)."""
    from config import settings

    monkeypatch.setattr(settings, "supabase_url", FAKE_SUPABASE_URL)
    monkeypatch.setattr(settings, "supabase_anon_key", FAKE_ANON_KEY)
    monkeypatch.setattr(settings, "supabase_service_role_key", FAKE_SERVICE_ROLE_KEY)
    monkeypatch.setattr(settings, "jwt_secret", "")


@pytest.fixture
def unconfigured(monkeypatch) -> None:
    """Clear every Supabase setting and environment variable."""
    from config import settings

    for name in (
        "SUPABASE_URL",
        "SUPABASE_ANON_KEY",
        "SUPABASE_SERVICE_ROLE_KEY",
        "SUPABASE_JWT_SECRET",
        "SUPABASE_DEV_USER_ID",
    ):
        monkeypatch.delenv(name, raising=False)

    monkeypatch.setattr(settings, "supabase_url", "")
    monkeypatch.setattr(settings, "supabase_anon_key", "")
    monkeypatch.setattr(settings, "supabase_service_role_key", "")
    monkeypatch.setattr(settings, "jwt_secret", "")
    monkeypatch.setattr(settings, "dev_user_id", "")


# ── API client + auth ────────────────────────────────────────────────────────

@pytest.fixture
def client(monkeypatch, fake_model, cloud):
    """An httpx client bound to the FastAPI app with a stubbed YOLO model."""
    import api

    monkeypatch.setattr(api, "model", fake_model)
    return httpx.AsyncClient(
        transport=httpx.ASGITransport(app=api.app), base_url="http://testserver"
    )


@pytest.fixture
def as_user():
    """Override the auth dependency so a request looks like a signed-in user."""
    import api
    from auth import AuthUser

    def _apply(user_id: str = TEST_USER_ID, email: str = TEST_USER_EMAIL) -> str:
        actor = AuthUser(id=user_id, email=email)
        api.app.dependency_overrides[api.optional_user] = lambda: actor
        return user_id

    yield _apply
    api.app.dependency_overrides.clear()


def image_files(name: str = "sample.jpg", payload: bytes = b"\xff\xd8\xff\xd9"):
    return {"file": (name, payload, "image/jpeg")}


def video_files(name: str = "sample.mp4", payload: bytes = b"fake-video-bytes"):
    return {"file": (name, payload, "video/mp4")}


DETECTION_FORM = {"source": "drone-cam-02", "conf": "0.10", "iou": "0.45"}
