"""Supabase access-token verification for the FastAPI backend.

The dashboard authenticates with Supabase Auth and forwards the session access
token as ``Authorization: Bearer <access_token>``. Tokens are verified locally
against the project's public JWKS keys (no network round-trip to Supabase Auth
per request) and the resulting user id is the only identity the detection
endpoints trust.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from typing import Any, Dict, Optional

from fastapi import Header, HTTPException, status

from config import settings

logger = logging.getLogger("vectortrack.auth")

ASYMMETRIC_ALGORITHMS = ["RS256", "RS384", "ES256", "ES384"]
LEGACY_ALGORITHMS = ["HS256"]
TOKEN_AUDIENCE = "authenticated"

_jwks_client: Optional[Any] = None
_jwks_client_url: Optional[str] = None


@dataclass(frozen=True)
class AuthUser:
    """The verified caller: the token's subject plus a few helpful claims."""

    id: str
    email: Optional[str] = None
    claims: Dict[str, Any] = field(default_factory=dict)


def _unauthorized(detail: str) -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail=detail,
        headers={"WWW-Authenticate": "Bearer"},
    )


def _bearer_token(authorization: Optional[str]) -> Optional[str]:
    """Extract the raw token from an ``Authorization: Bearer ...`` header."""
    if not authorization:
        return None
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer":
        return None
    token = token.strip()
    return token or None


def _get_jwks_client() -> Any:
    """Return a cached JWKS client for the configured Supabase project."""
    global _jwks_client, _jwks_client_url

    import jwt  # PyJWT

    if _jwks_client is None or _jwks_client_url != settings.jwks_url:
        _jwks_client = jwt.PyJWKClient(settings.jwks_url, cache_keys=True)
        _jwks_client_url = settings.jwks_url
    return _jwks_client


def reset_jwks_cache() -> None:
    """Drop the cached JWKS client (used by tests and after config changes)."""
    global _jwks_client, _jwks_client_url
    _jwks_client = None
    _jwks_client_url = None


def _decode_with_jwks(token: str) -> Dict[str, Any]:
    import jwt

    try:
        signing_key = _get_jwks_client().get_signing_key_from_jwt(token).key
    except Exception as exc:
        logger.warning("JWKS lookup failed: %s", exc)
        raise _unauthorized("Access token could not be verified against the project keys.") from exc

    try:
        return jwt.decode(
            token,
            signing_key,
            algorithms=ASYMMETRIC_ALGORITHMS,
            audience=TOKEN_AUDIENCE,
            issuer=settings.issuer,
            leeway=10,
            options={"require": ["exp", "sub"]},
        )
    except jwt.InvalidIssuerError:
        # Signature and audience are still checked; only the issuer string
        # differed, which happens with custom domains and self-hosted Auth.
        logger.warning(
            "Access token issuer did not match %s; signature and audience were still verified.",
            settings.issuer,
        )
        return jwt.decode(
            token,
            signing_key,
            algorithms=ASYMMETRIC_ALGORITHMS,
            audience=TOKEN_AUDIENCE,
            leeway=10,
            options={"require": ["exp", "sub"], "verify_iss": False},
        )
    except jwt.PyJWTError as exc:
        raise _unauthorized("Invalid or expired Supabase access token.") from exc


def _decode_with_secret(token: str) -> Dict[str, Any]:
    """Legacy path for projects that still sign tokens with the shared secret."""
    import jwt

    try:
        return jwt.decode(
            token,
            settings.jwt_secret,
            algorithms=LEGACY_ALGORITHMS,
            audience=TOKEN_AUDIENCE,
            leeway=10,
            options={"require": ["exp", "sub"], "verify_iss": False},
        )
    except jwt.PyJWTError as exc:
        raise _unauthorized("Invalid or expired Supabase access token.") from exc


def verify_access_token(token: str) -> Dict[str, Any]:
    """Verify an access token and return its claims."""
    if settings.jwt_secret:
        return _decode_with_secret(token)
    return _decode_with_jwks(token)


def optional_user(authorization: Optional[str] = Header(default=None)) -> Optional[AuthUser]:
    """FastAPI dependency for endpoints that also work without a session.

    The dashboard is usable before sign-in, so a missing token is not an error:
    the endpoint then falls back to the shared app account. A token that *is*
    supplied but cannot be verified still gets a ``401`` — a stale or forged
    session must never be silently misfiled onto the shared account.
    """
    token = _bearer_token(authorization)
    if not token:
        return None

    # Nothing to verify against: treat the request as anonymous rather than
    # failing, so a half-configured server still runs detections.
    if not settings.is_configured and not settings.jwt_secret:
        return None

    claims = verify_access_token(token)
    subject = str(claims.get("sub") or "").strip()
    if not subject:
        raise _unauthorized("Access token has no subject claim.")

    return AuthUser(id=subject, email=claims.get("email"), claims=claims)


def require_user(authorization: Optional[str] = Header(default=None)) -> AuthUser:
    """FastAPI dependency that rejects unauthenticated detection requests."""
    token = _bearer_token(authorization)
    if not token:
        raise _unauthorized(
            "Missing bearer token. Sign in with Supabase Auth and send "
            "'Authorization: Bearer <access_token>'."
        )

    if not settings.is_configured and not settings.jwt_secret:
        missing = ", ".join(settings.missing_required()) or "SUPABASE_URL"
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"Supabase auth is not configured on the server (missing: {missing}).",
        )

    claims = verify_access_token(token)
    subject = str(claims.get("sub") or "").strip()
    if not subject:
        raise _unauthorized("Access token has no subject claim.")

    return AuthUser(id=subject, email=claims.get("email"), claims=claims)
