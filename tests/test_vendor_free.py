"""Assert the previous cloud vendor is completely gone.

The forbidden words are assembled from fragments so that this test file itself
contains no literal reference either: a repository-wide search for the old
vendor names must come back empty.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from typing import List

import pytest

ROOT = Path(__file__).resolve().parents[1]

# Assembled from fragments on purpose: this file must not contain the
# forbidden words either, so a repository-wide search stays empty.
VENDOR = "".join(["fire", "base"])
VENDOR_DB = "".join(["fire", "store"])
VENDOR_ADMIN_PACKAGE = VENDOR + "_admin"
CREDENTIAL_FILE = "".join(["service", "AccountKey"]) + ".json"
FORBIDDEN_TERMS = (VENDOR, VENDOR_DB, CREDENTIAL_FILE)

TEXT_SUFFIXES = {
    "",
    ".py",
    ".js",
    ".html",
    ".css",
    ".md",
    ".sql",
    ".txt",
    ".yaml",
    ".yml",
    ".ini",
    ".toml",
    ".example",
    ".cfg",
}
SKIP_DIRS = {
    ".git",
    ".venv",
    "venv",
    "node_modules",
    "__pycache__",
    ".pytest_cache",
    ".freebuff",
    "runs",
    "output",
    ".mypy_cache",
    ".ruff_cache",
}


def _iter_repo_text_files() -> List[Path]:
    files: List[Path] = []
    for path in ROOT.rglob("*"):
        if not path.is_file():
            continue
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        if path.suffix.lower() not in TEXT_SUFFIXES:
            continue
        files.append(path)
    return files


def test_no_vendor_references_anywhere_in_the_repository():
    offenders = []
    for path in _iter_repo_text_files():
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:  # pragma: no cover - unreadable file
            continue
        lowered = text.lower()
        for term in FORBIDDEN_TERMS:
            if term.lower() in lowered:
                offenders.append(f"{path.relative_to(ROOT)} -> {term}")

    assert offenders == [], "Removed-vendor references remain:\n" + "\n".join(offenders)


def test_requirements_declare_no_removed_packages():
    requirements = (ROOT / "requirements.txt").read_text(encoding="utf-8").lower()

    assert VENDOR not in requirements
    assert f"google-cloud-{VENDOR_DB}".lower() not in requirements
    # ...and the replacement is declared instead
    assert "supabase" in requirements
    assert "python-dotenv" in requirements
    assert "pyjwt" in requirements


def test_removed_sdk_is_not_installed():
    assert importlib.util.find_spec(VENDOR_ADMIN_PACKAGE) is None
    assert not any(module.startswith(VENDOR) for module in sys.modules)


def test_credential_file_is_gone_and_unreferenced():
    assert not (ROOT / CREDENTIAL_FILE).exists()

    gitignore = (ROOT / ".gitignore").read_text(encoding="utf-8")
    assert CREDENTIAL_FILE not in gitignore
    assert ".env" in gitignore


def test_application_imports_without_any_vendor_credentials(monkeypatch):
    """The app must boot with no removed-vendor secrets present at all."""
    for term in (CREDENTIAL_FILE,):
        monkeypatch.delenv(term, raising=False)

    import api

    assert api.app is not None
    assert not api.MODEL_PATH.name.startswith(VENDOR)
    assert not any(module.startswith(VENDOR) for module in sys.modules)


def test_env_example_documents_supabase_only():
    text = (ROOT / ".env.example").read_text(encoding="utf-8")

    assert "SUPABASE_URL=" in text
    assert "SUPABASE_ANON_KEY=" in text
    assert "SUPABASE_SERVICE_ROLE_KEY=" in text
    assert "SUPABASE_ORIGINALS_BUCKET=vectortrack-originals" in text
    assert "SUPABASE_RESULTS_BUCKET=vectortrack-results" in text
    for term in FORBIDDEN_TERMS:
        assert term.lower() not in text.lower()


@pytest.mark.anyio
async def test_frontend_never_receives_the_service_role_key(client, configured):
    from tests.conftest import FAKE_SERVICE_ROLE_KEY

    async with client as http:
        response = await http.get("/config")

    assert FAKE_SERVICE_ROLE_KEY not in response.text


def test_frontend_uses_supabase_auth_and_realtime():
    app_js = (ROOT / "static" / "app.js").read_text(encoding="utf-8")
    client_js = (ROOT / "static" / "supabase-client.js").read_text(encoding="utf-8")
    index_html = (ROOT / "static" / "index.html").read_text(encoding="utf-8")

    assert "Authorization" in app_js and "Bearer" in app_js
    assert "postgres_changes" in app_js
    assert "user_id=eq." in app_js
    assert "signInWithOAuth" in client_js
    assert "signOut" in client_js
    assert "Detection Logs (Supabase Realtime)" in index_html
    assert "btn-google-login" in index_html
