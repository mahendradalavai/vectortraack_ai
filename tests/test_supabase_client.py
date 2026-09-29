"""Unit tests for the Supabase access layer (supabase_client.py)."""

from __future__ import annotations

from typing import Any, Dict, List, Optional

import pytest

from tests.conftest import FAKE_SUPABASE_URL, TEST_USER_ID


# ── Fakes for the supabase-py client surface we use ──────────────────────────

class FakeResponse:
    def __init__(self, data: List[Dict[str, Any]]):
        self.data = data


class FakeTableQuery:
    def __init__(self, recorder: Dict[str, Any], table: str, fail: bool = False):
        self.recorder = recorder
        self.table = table
        self.fail = fail
        self.payload: Dict[str, Any] = {}

    def insert(self, payload: Dict[str, Any]) -> "FakeTableQuery":
        self.payload = payload
        return self

    def execute(self) -> FakeResponse:
        if self.fail:
            raise RuntimeError("postgrest exploded")
        self.recorder["inserts"].append({"table": self.table, "payload": self.payload})
        return FakeResponse([dict(self.payload, id="row-1")])


class FakeBucket:
    def __init__(self, recorder: Dict[str, Any], bucket: str, fail: bool = False):
        self.recorder = recorder
        self.bucket = bucket
        self.fail = fail

    def upload(self, path: str, file: bytes, file_options: Optional[Dict[str, Any]] = None):
        if self.fail:
            raise RuntimeError("storage exploded")
        self.recorder["uploads"].append(
            {"bucket": self.bucket, "path": path, "file": file, "file_options": file_options}
        )
        return {"path": path}

    def create_signed_url(self, path: str, expires_in: int):
        if self.fail:
            raise RuntimeError("signing exploded")
        self.recorder["signs"].append(
            {"bucket": self.bucket, "path": path, "expires_in": expires_in}
        )
        return {"signedURL": f"/object/sign/{self.bucket}/{path}"}


class FakeStorage:
    def __init__(self, recorder: Dict[str, Any], fail: bool = False):
        self.recorder = recorder
        self.fail = fail

    def from_(self, bucket: str) -> FakeBucket:
        return FakeBucket(self.recorder, bucket, fail=self.fail)


class FakeServiceClient:
    def __init__(self, fail: bool = False):
        self.recorder: Dict[str, Any] = {"inserts": [], "uploads": [], "signs": []}
        self.fail = fail
        self.storage = FakeStorage(self.recorder, fail=fail)

    def table(self, name: str) -> FakeTableQuery:
        return FakeTableQuery(self.recorder, name, fail=self.fail)


@pytest.fixture
def fake_client(monkeypatch):
    """Patch the cached service client with an in-memory fake."""
    import supabase_client

    client = FakeServiceClient()
    monkeypatch.setattr(supabase_client, "get_service_client", lambda: client)
    return client


# ── Database insertion ───────────────────────────────────────────────────────

def test_insert_detection_maps_every_column(fake_client):
    import supabase_client

    row = supabase_client.insert_detection(
        user_id=TEST_USER_ID,
        class_name="garbage",
        confidence=0.87,
        source="drone-cam-02",
        media_type="image",
        original_file_path=f"{TEST_USER_ID}/image/img_1.jpg",
        result_file_path=f"{TEST_USER_ID}/image/img_1.jpg",
        metadata={"bbox": [0.0, 0.0, 1.0, 1.0]},
    )

    assert row is not None
    assert row["id"] == "row-1"

    recorded = fake_client.recorder["inserts"]
    assert len(recorded) == 1
    assert recorded[0]["table"] == "detections"

    payload = recorded[0]["payload"]
    assert payload == {
        "user_id": TEST_USER_ID,
        "class": "garbage",
        "confidence": 0.87,
        "source": "drone-cam-02",
        "media_type": "image",
        "original_file_path": f"{TEST_USER_ID}/image/img_1.jpg",
        "result_file_path": f"{TEST_USER_ID}/image/img_1.jpg",
        "metadata": {"bbox": [0.0, 0.0, 1.0, 1.0]},
    }


def test_build_detection_row_defaults_metadata_to_empty_object():
    import supabase_client

    row = supabase_client.build_detection_row(
        user_id=TEST_USER_ID,
        class_name="rubbish",
        confidence=0.5,
        source=None,
        media_type="video",
        original_file_path=None,
        result_file_path=None,
    )

    assert row["metadata"] == {}
    assert row["confidence"] == pytest.approx(0.5)
    assert row["media_type"] == "video"


def test_insert_detection_failure_returns_none(monkeypatch):
    import supabase_client

    monkeypatch.setattr(supabase_client, "get_service_client", lambda: FakeServiceClient(fail=True))

    assert (
        supabase_client.insert_detection(
            user_id=TEST_USER_ID,
            class_name="garbage",
            confidence=0.4,
            media_type="image",
        )
        is None
    )


# ── Storage upload ───────────────────────────────────────────────────────────

def test_upload_media_returns_the_storage_path(fake_client):
    import supabase_client

    path = f"{TEST_USER_ID}/image/img_1.jpg"
    result = supabase_client.upload_media(
        "vectortrack-originals", path, b"jpeg-bytes", content_type="image/jpeg"
    )

    assert result == path
    upload = fake_client.recorder["uploads"][0]
    assert upload["bucket"] == "vectortrack-originals"
    assert upload["path"].startswith(f"{TEST_USER_ID}/")
    assert upload["file"] == b"jpeg-bytes"
    assert upload["file_options"] == {"content-type": "image/jpeg"}


def test_upload_media_failure_returns_none(monkeypatch):
    import supabase_client

    monkeypatch.setattr(supabase_client, "get_service_client", lambda: FakeServiceClient(fail=True))

    assert supabase_client.upload_media("vectortrack-results", "x/y.jpg", b"bytes") is None


def test_signed_url_is_absolutised_and_uses_configured_expiry(fake_client, configured, monkeypatch):
    import supabase_client
    from config import settings

    monkeypatch.setattr(settings, "signed_url_expiry_seconds", 120)

    url = supabase_client.create_signed_url("vectortrack-results", f"{TEST_USER_ID}/image/a.jpg")

    assert url == f"{FAKE_SUPABASE_URL}/storage/v1/object/sign/vectortrack-results/{TEST_USER_ID}/image/a.jpg"
    assert fake_client.recorder["signs"][0]["expires_in"] == 120


def test_explicit_signed_url_expiry_wins(fake_client):
    import supabase_client

    supabase_client.create_signed_url("vectortrack-originals", "a/b.jpg", expires_in=45)

    assert fake_client.recorder["signs"][0]["expires_in"] == 45


# ── Missing / invalid environment ────────────────────────────────────────────

def test_missing_config_reports_every_required_variable(unconfigured):
    from config import settings

    missing = settings.missing_required()

    assert missing == ["SUPABASE_URL", "SUPABASE_ANON_KEY", "SUPABASE_SERVICE_ROLE_KEY"]
    assert settings.is_configured is False


def test_helpers_are_no_ops_without_configuration(unconfigured, monkeypatch):
    import supabase_client

    supabase_client.reset_client_cache()
    monkeypatch.setattr(supabase_client, "_service_client", None)

    assert supabase_client.get_service_client() is None
    assert "SUPABASE_URL" in (supabase_client.last_error() or "")

    # No exception, no crash — the caller decides what a missing cloud means.
    assert supabase_client.upload_media("vectortrack-originals", "a/b.jpg", b"x") is None
    assert supabase_client.create_signed_url("vectortrack-originals", "a/b.jpg") is None
    assert (
        supabase_client.insert_detection(
            user_id=TEST_USER_ID, class_name="garbage", confidence=0.2, media_type="image"
        )
        is None
    )


def test_dev_user_helpers_skip_without_a_configured_user(unconfigured):
    import supabase_client

    assert (
        supabase_client.save_detection_for_dev_user(
            class_name="garbage", confidence=0.3, image_name="a.jpg"
        )
        is None
    )


def test_dev_user_helper_inserts_for_the_configured_user(fake_client, monkeypatch):
    import supabase_client
    from config import settings

    monkeypatch.setattr(settings, "dev_user_id", TEST_USER_ID)

    row = supabase_client.save_detection_for_dev_user(
        class_name="rubbish",
        confidence=0.66,
        image_name="frame_7.jpg",
        image_path="/tmp/frame_7.jpg",
        source="video",
        media_type="video",
        metadata={"frame": 7},
    )

    assert row is not None
    payload = fake_client.recorder["inserts"][0]["payload"]
    assert payload["user_id"] == TEST_USER_ID
    assert payload["media_type"] == "video"
    assert payload["metadata"] == {"media_file": "frame_7.jpg", "local_path": "/tmp/frame_7.jpg", "frame": 7}
