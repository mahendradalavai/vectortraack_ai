"""Supabase access layer for VectorTrack AI.

This module owns the whole cloud layer:

* the lazily created service-role client (server side only),
* Storage uploads for originals and annotated results,
* signed URL generation for the dashboard,
* inserts into the ``public.detections`` table.

Every helper degrades gracefully: if Supabase is not configured, or a call
fails, the helper logs a clear message and returns ``None`` instead of raising.
Inference therefore keeps working even when the cloud layer is temporarily
unavailable.
"""

from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional

from config import settings

logger = logging.getLogger("vectortrack.supabase")

DETECTIONS_TABLE = "detections"

_service_client: Optional[Any] = None
_last_error: Optional[str] = None
_app_user_id: Optional[str] = None


def get_service_client() -> Optional[Any]:
    """Return the cached service-role client, or ``None`` when unavailable.

    The service-role key bypasses Row Level Security, so this client must only
    ever be used from the FastAPI process.
    """
    global _service_client, _last_error

    if _service_client is not None:
        return _service_client

    missing = settings.missing_required()
    if missing:
        _last_error = (
            "Supabase is not configured. Missing environment variables: " + ", ".join(missing)
        )
        logger.warning(_last_error)
        return None

    try:
        from supabase import create_client  # imported lazily so the app can boot without it
    except ImportError as exc:  # pragma: no cover - depends on the installed environment
        _last_error = f"The 'supabase' package is not installed: {exc}"
        logger.error(_last_error)
        return None

    try:
        _service_client = create_client(
            settings.supabase_url, settings.supabase_service_role_key
        )
    except Exception as exc:  # pragma: no cover - network/config failure
        _last_error = f"Could not create the Supabase service client: {exc}"
        logger.error(_last_error)
        return None

    _last_error = None
    return _service_client


def reset_client_cache() -> None:
    """Drop the cached client (used by tests and after config changes)."""
    global _service_client, _last_error, _app_user_id
    _service_client = None
    _last_error = None
    _app_user_id = None


def last_error() -> Optional[str]:
    """Human readable reason for the most recent failure, if any."""
    return _last_error


def upload_media(
    bucket: str,
    path: str,
    content: bytes,
    content_type: str = "application/octet-stream",
) -> Optional[str]:
    """Upload bytes to ``bucket`` at ``path``.

    Returns the storage path on success, ``None`` on failure.
    """
    client = get_service_client()
    if client is None:
        return None

    try:
        client.storage.from_(bucket).upload(
            path=path,
            file=content,
            file_options={"content-type": content_type},
        )
    except Exception as exc:
        logger.error("Storage upload failed for %s/%s: %s", bucket, path, exc)
        global _last_error
        _last_error = f"Storage upload failed for {bucket}/{path}: {exc}"
        return None

    return path


def create_signed_url(
    bucket: str, path: str, expires_in: Optional[int] = None
) -> Optional[str]:
    """Create a time-limited download URL for a private storage object."""
    client = get_service_client()
    if client is None:
        return None

    ttl = expires_in or settings.signed_url_expiry_seconds
    try:
        response = client.storage.from_(bucket).create_signed_url(path, ttl)
    except Exception as exc:
        logger.error("Could not sign %s/%s: %s", bucket, path, exc)
        return None

    url = _extract_signed_url(response)
    if not url:
        logger.error("Signed URL response for %s/%s had no URL: %r", bucket, path, response)
        return None
    return url


def _extract_signed_url(response: Any) -> Optional[str]:
    """Normalise the different shapes returned by storage clients."""
    if isinstance(response, str):
        url = response
    elif isinstance(response, dict):
        url = (
            response.get("signedURL")
            or response.get("signedUrl")
            or response.get("signed_url")
            or ""
        )
    else:  # object with attributes
        url = (
            getattr(response, "signedURL", None)
            or getattr(response, "signedUrl", None)
            or ""
        )
    if not url:
        return None
    if url.startswith("/"):
        return f"{settings.supabase_url}/storage/v1{url}"
    return url


def build_detection_row(
    *,
    user_id: str,
    class_name: str,
    confidence: float,
    source: Optional[str],
    media_type: str,
    original_file_path: Optional[str],
    result_file_path: Optional[str],
    metadata: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    """Build the row payload for the ``detections`` table."""
    return {
        "user_id": user_id,
        "class": class_name,
        "confidence": float(confidence),
        "source": source,
        "media_type": media_type,
        "original_file_path": original_file_path,
        "result_file_path": result_file_path,
        "metadata": metadata or {},
    }


def insert_detection(
    *,
    user_id: str,
    class_name: str,
    confidence: float,
    source: Optional[str] = "camera",
    media_type: str = "image",
    original_file_path: Optional[str] = None,
    result_file_path: Optional[str] = None,
    metadata: Optional[Dict[str, Any]] = None,
) -> Optional[Dict[str, Any]]:
    """Insert a single detection row and return the stored record."""
    client = get_service_client()
    if client is None:
        return None

    payload = build_detection_row(
        user_id=user_id,
        class_name=class_name,
        confidence=confidence,
        source=source,
        media_type=media_type,
        original_file_path=original_file_path,
        result_file_path=result_file_path,
        metadata=metadata,
    )

    try:
        response = client.table(DETECTIONS_TABLE).insert(payload).execute()
    except Exception as exc:
        logger.error("Detection insert failed: %s", exc)
        global _last_error
        _last_error = f"Detection insert failed: {exc}"
        return None

    rows = getattr(response, "data", None)
    if isinstance(rows, list) and rows:
        return rows[0]
    return payload


def resolve_app_user_id() -> Optional[str]:
    """The identity signed-out detections are attributed to.

    Resolution order:

    1. ``SUPABASE_DEV_USER_ID`` when set — an explicit override,
    2. an existing Supabase account with the configured app e-mail,
    3. a new account with that e-mail, created with the service-role key.

    Returns ``None`` when Supabase is unavailable, in which case callers skip
    the database write and only store media.
    """
    global _app_user_id

    if settings.dev_user_id:
        return settings.dev_user_id
    if _app_user_id:
        return _app_user_id

    client = get_service_client()
    if client is None:
        return None

    email = settings.app_user_email

    try:
        users = client.auth.admin.list_users()
    except Exception as exc:
        logger.error("Could not list Supabase users: %s", exc)
        users = []

    for user in users or []:
        if (getattr(user, "email", None) or "").lower() == email:
            _app_user_id = getattr(user, "id", None)
            return _app_user_id

    try:
        import secrets

        created = client.auth.admin.create_user(
            {
                "email": email,
                "password": secrets.token_urlsafe(32),
                "email_confirm": True,
            }
        )
    except Exception as exc:
        logger.error("Could not create the app account %s: %s", email, exc)
        return None

    user = getattr(created, "user", None) or created
    if isinstance(user, dict):
        _app_user_id = user.get("id")
    else:
        _app_user_id = getattr(user, "id", None)

    if _app_user_id:
        logger.info("Created the VectorTrack app account used for signed-out detections.")
    return _app_user_id


def save_detection_for_dev_user(
    *,
    class_name: str,
    confidence: float,
    image_name: str,
    image_path: Optional[str] = None,
    source: str = "image",
    media_type: str = "image",
    metadata: Optional[Dict[str, Any]] = None,
) -> Optional[Dict[str, Any]]:
    """Persistence used by the standalone CLI scripts.

    The API always derives the user id from the verified access token. Scripts
    have no session, so they only write when ``SUPABASE_DEV_USER_ID`` is set;
    otherwise the detection is simply printed by the caller.
    """
    if not settings.dev_user_id:
        print(
            "[Supabase] Skipping detection upload: SUPABASE_DEV_USER_ID is not set. "
            "Set it to a Supabase auth user id to persist CLI detections."
        )
        return None

    row_metadata: Dict[str, Any] = {"media_file": image_name}
    if image_path:
        row_metadata["local_path"] = image_path
    if metadata:
        row_metadata.update(metadata)

    return insert_detection(
        user_id=settings.dev_user_id,
        class_name=class_name,
        confidence=confidence,
        source=source,
        media_type=media_type,
        original_file_path=None,
        result_file_path=None,
        metadata=row_metadata,
    )


def detection_rows_for_api(
    rows: List[Dict[str, Any]],
) -> List[Dict[str, Any]]:  # pragma: no cover - helper kept for symmetry
    """Filter out ``None`` results coming from ``insert_detection``."""
    return [row for row in rows if row]
