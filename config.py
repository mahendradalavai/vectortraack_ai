"""Environment-driven configuration for VectorTrack AI.

Every cloud value comes from the environment. Nothing is hardcoded and no
secret is ever written into the frontend bundle: the browser only receives
``SUPABASE_URL`` and ``SUPABASE_ANON_KEY`` through ``GET /config``, while the
service-role key stays on the server.
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from typing import List

# A local .env file is convenient for development but strictly optional.
try:  # pragma: no cover - trivial import guard
    from dotenv import load_dotenv

    load_dotenv()
except ImportError:  # pragma: no cover - python-dotenv is optional
    pass


DEFAULT_ORIGINALS_BUCKET = "vectortrack-originals"
DEFAULT_RESULTS_BUCKET = "vectortrack-results"
DEFAULT_SIGNED_URL_EXPIRY_SECONDS = 3600
# The account anonymous (signed-out) detections belong to. It is looked up by
# e-mail and created with the service-role key on first use.
DEFAULT_APP_USER_EMAIL = "vectortrack-app@vectortrack.local"


def _clean(value: str | None) -> str:
    return (value or "").strip()


def _clean_url(value: str | None) -> str:
    return _clean(value).rstrip("/")


@dataclass
class Settings:
    """Resolved application settings.

    The object is mutable on purpose so tests can patch individual values
    without reloading the process environment.
    """

    supabase_url: str = field(default_factory=lambda: _clean_url(os.getenv("SUPABASE_URL")))
    supabase_anon_key: str = field(default_factory=lambda: _clean(os.getenv("SUPABASE_ANON_KEY")))
    supabase_service_role_key: str = field(
        default_factory=lambda: _clean(os.getenv("SUPABASE_SERVICE_ROLE_KEY"))
    )
    originals_bucket: str = field(
        default_factory=lambda: _clean(os.getenv("SUPABASE_ORIGINALS_BUCKET")) or DEFAULT_ORIGINALS_BUCKET
    )
    results_bucket: str = field(
        default_factory=lambda: _clean(os.getenv("SUPABASE_RESULTS_BUCKET")) or DEFAULT_RESULTS_BUCKET
    )
    # Only used by older projects that still sign access tokens with the
    # legacy shared secret instead of asymmetric JWKS keys.
    jwt_secret: str = field(default_factory=lambda: _clean(os.getenv("SUPABASE_JWT_SECRET")))
    signed_url_expiry_seconds: int = field(
        default_factory=lambda: int(
            _clean(os.getenv("SUPABASE_SIGNED_URL_EXPIRY_SECONDS")) or DEFAULT_SIGNED_URL_EXPIRY_SECONDS
        )
    )
    # Optional: lets the standalone CLI scripts (detect.py / test_image.py)
    # persist detections for a single known user id. It also overrides the
    # shared app account used for signed-out detections.
    dev_user_id: str = field(default_factory=lambda: _clean(os.getenv("SUPABASE_DEV_USER_ID")))
    # E-mail of the shared app account that signed-out detections belong to.
    app_user_email: str = field(
        default_factory=lambda: _clean(os.getenv("SUPABASE_APP_EMAIL")) or DEFAULT_APP_USER_EMAIL
    )
    cors_allow_origins: List[str] = field(
        default_factory=lambda: [
            origin.strip()
            for origin in (_clean(os.getenv("CORS_ALLOW_ORIGINS")) or "*").split(",")
            if origin.strip()
        ]
    )

    # ── Derived values ────────────────────────────────────────────────────────
    @property
    def auth_url(self) -> str:
        """Base URL of the Supabase Auth API for this project."""
        return f"{self.supabase_url}/auth/v1" if self.supabase_url else ""

    @property
    def issuer(self) -> str:
        """Expected ``iss`` claim of a Supabase access token."""
        return self.auth_url

    @property
    def jwks_url(self) -> str:
        """Public JWKS endpoint used to verify access-token signatures."""
        return f"{self.auth_url}/.well-known/jwks.json" if self.auth_url else ""

    @property
    def is_configured(self) -> bool:
        """True when every mandatory Supabase value is present."""
        return not self.missing_required()

    def missing_required(self) -> List[str]:
        """Names of the mandatory environment variables that are unset."""
        required = {
            "SUPABASE_URL": self.supabase_url,
            "SUPABASE_ANON_KEY": self.supabase_anon_key,
            "SUPABASE_SERVICE_ROLE_KEY": self.supabase_service_role_key,
        }
        return [name for name, value in required.items() if not value]


settings = Settings()


def reload_settings() -> Settings:
    """Re-read the environment into the shared settings object."""
    global settings
    settings = Settings()
    return settings
