"""Token-verification tests for the FastAPI auth dependency."""

from __future__ import annotations

import time

import pytest
from cryptography.hazmat.primitives.asymmetric import rsa

from tests.conftest import DETECTION_FORM, TEST_USER_EMAIL, TEST_USER_ID, image_files

ISSUER = "https://test-project.supabase.co/auth/v1"


@pytest.fixture
def rsa_key():
    return rsa.generate_private_key(public_exponent=65537, key_size=2048)


@pytest.fixture
def jwt_headers(monkeypatch, configured, rsa_key):
    """Sign tokens with a throwaway RSA key and stub out the JWKS lookup."""
    import jwt

    import auth

    class StubSigningKey:
        def __init__(self, key):
            self.key = key

    class StubJWKSClient:
        def get_signing_key_from_jwt(self, token):  # noqa: ARG002 - signature parity
            return StubSigningKey(rsa_key.public_key())

    monkeypatch.setattr(auth, "_get_jwks_client", lambda: StubJWKSClient())

    def _sign(**overrides):
        now = int(time.time())
        claims = {
            "sub": TEST_USER_ID,
            "email": TEST_USER_EMAIL,
            "aud": "authenticated",
            "iss": ISSUER,
            "iat": now,
            "exp": now + 3600,
        }
        claims.update(overrides)
        return jwt.encode(claims, rsa_key, algorithm="RS256", headers={"kid": "test-key"})

    return _sign


# ── Unit level ───────────────────────────────────────────────────────────────

def test_valid_token_yields_claims(jwt_headers):
    import auth

    claims = auth.verify_access_token(jwt_headers())

    assert claims["sub"] == TEST_USER_ID
    assert claims["email"] == TEST_USER_EMAIL


def test_expired_token_is_rejected(jwt_headers):
    import auth
    from fastapi import HTTPException

    expired = jwt_headers(exp=int(time.time()) - 60, iat=int(time.time()) - 3600)

    with pytest.raises(HTTPException) as excinfo:
        auth.verify_access_token(expired)

    assert excinfo.value.status_code == 401


def test_token_with_wrong_audience_is_rejected(jwt_headers):
    import auth
    from fastapi import HTTPException

    with pytest.raises(HTTPException) as excinfo:
        auth.verify_access_token(jwt_headers(aud="some-other-app"))

    assert excinfo.value.status_code == 401


def test_token_signed_by_another_key_is_rejected(jwt_headers):
    import jwt

    import auth
    from fastapi import HTTPException

    attacker_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    now = int(time.time())
    forged = jwt.encode(
        {
            "sub": TEST_USER_ID,
            "aud": "authenticated",
            "iss": ISSUER,
            "iat": now,
            "exp": now + 3600,
        },
        attacker_key,
        algorithm="RS256",
        headers={"kid": "test-key"},
    )

    with pytest.raises(HTTPException) as excinfo:
        auth.verify_access_token(forged)

    assert excinfo.value.status_code == 401


def test_jwks_failure_is_unauthorized_not_a_crash(monkeypatch, configured):
    import auth
    from fastapi import HTTPException

    class ExplodingJWKS:
        def get_signing_key_from_jwt(self, token):
            raise RuntimeError("jwks unreachable")

    monkeypatch.setattr(auth, "_get_jwks_client", lambda: ExplodingJWKS())

    with pytest.raises(HTTPException) as excinfo:
        auth.verify_access_token("any.token.value")

    assert excinfo.value.status_code == 401


# ── Optional auth: the dashboard also works signed-out ───────────────────────

def test_optional_user_allows_missing_header(configured):
    import auth

    for header in (None, "", "Bearer", "Bearer   "):
        assert auth.optional_user(authorization=header) is None


def test_optional_user_allows_non_bearer_scheme(configured):
    import auth

    assert auth.optional_user(authorization="Token abc.def.ghi") is None


def test_optional_user_still_rejects_a_broken_token(configured, monkeypatch):
    import auth
    from fastapi import HTTPException

    class ExplodingJWKS:
        def get_signing_key_from_jwt(self, token):
            raise RuntimeError("jwks unreachable")

    monkeypatch.setattr(auth, "_get_jwks_client", lambda: ExplodingJWKS())

    with pytest.raises(HTTPException) as excinfo:
        auth.optional_user(authorization="Bearer some.broken.token")

    assert excinfo.value.status_code == 401


def test_optional_user_returns_the_caller_for_a_valid_token(jwt_headers):
    import auth

    user = auth.optional_user(authorization=f"Bearer {jwt_headers()}")

    assert user is not None
    assert user.id == TEST_USER_ID


def test_require_user_rejects_missing_and_malformed_headers(configured):
    import auth
    from fastapi import HTTPException

    for header in (None, "", "Bearer", "Basic abc", "Bearer   "):
        with pytest.raises(HTTPException) as excinfo:
            auth.require_user(authorization=header)
        assert excinfo.value.status_code == 401


# ── End to end through the API ───────────────────────────────────────────────

@pytest.mark.anyio
async def test_real_token_authorises_a_detection(client, cloud, jwt_headers):
    headers = {"Authorization": f"Bearer {jwt_headers()}"}

    async with client as http:
        response = await http.post(
            "/detect/image", files=image_files(), data=DETECTION_FORM, headers=headers
        )

    assert response.status_code == 201
    assert cloud.inserts[0]["user_id"] == TEST_USER_ID


@pytest.mark.anyio
async def test_forged_token_cannot_run_detections(client, cloud, jwt_headers):
    import jwt

    now = int(time.time())
    forged = jwt.encode(
        {
            "sub": TEST_USER_ID,
            "aud": "authenticated",
            "iss": ISSUER,
            "iat": now,
            "exp": now + 3600,
        },
        rsa.generate_private_key(public_exponent=65537, key_size=2048),
        algorithm="RS256",
        headers={"kid": "test-key"},
    )

    async with client as http:
        response = await http.post(
            "/detect/image",
            files=image_files(),
            data=DETECTION_FORM,
            headers={"Authorization": f"Bearer {forged}"},
        )

    assert response.status_code == 401
    assert cloud.inserts == []


@pytest.mark.anyio
async def test_token_without_subject_is_rejected(client, jwt_headers):
    token = jwt_headers(sub="")
    async with client as http:
        response = await http.post(
            "/detect/image",
            files=image_files(),
            data=DETECTION_FORM,
            headers={"Authorization": f"Bearer {token}"},
        )

    assert response.status_code == 401
