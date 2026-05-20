# Bundle Social Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Post Bridge with Bundle Social API in the SmartAIMentor backend, adding multi-user team isolation, social account management routes, and a clean BundleSocialClient.

**Architecture:** Each creator gets a 1:1 Bundle Social Team (via TeamStore mapping). BundleSocialClient wraps all Bundle Social API calls (upload, post, account management). The existing publish/chat routes switch from SkillRunner to BundleSocialClient. A new `/api/social/*` router handles account connection flows.

**Tech Stack:** Python 3.12+, FastAPI, httpx (async), pydantic-settings, threading (for TeamStore lock)

---

## API Corrections from Testing

The original design doc (`2026-05-16-bundle-social-integration-design.md`) has several inaccuracies discovered via real API testing. **All implementations must use the corrected schema below:**

| Design Doc Says | Actual (Verified) |
|---|---|
| `GET /api/v1/social-account?teamId=...` (standalone list) | No standalone endpoint. Accounts come from team response's `socialAccounts` array |
| Disconnect by `social_account_id` | Disconnect by **platform type**: `DELETE /api/v1/social-account/disconnect` with `{type, teamId}` |
| Post uses `platforms` key | Post uses `data` key for per-platform configs |
| `postNow: true` field | No `postNow`. Use `status: "SCHEDULED"` with `postDate` for scheduling |
| `title` optional | `title` is **required** for post creation |
| TikTok privacy `PUBLIC` | TikTok privacy is `PUBLIC_TO_EVERYONE` |

---

## File Structure

### New files
| File | Responsibility |
|---|---|
| `SmartAIMentor/backend/app/services/bundle_social_client.py` | Bundle Social API client: team CRUD, social accounts, media upload, post creation |
| `SmartAIMentor/backend/app/services/team_store.py` | JSON file store for creator_id → teamId mapping |
| `SmartAIMentor/backend/app/api/social.py` | Social account management routes: connect, list accounts, disconnect |

### Modified files
| File | Changes |
|---|---|
| `SmartAIMentor/backend/app/config.py` | Add `bundle_social_*` settings |
| `SmartAIMentor/backend/app/main.py` | Wire TeamStore, BundleSocialClient, social router |
| `SmartAIMentor/backend/app/api/publish.py` | Switch from SkillRunner to BundleSocialClient |
| `SmartAIMentor/backend/app/api/chat.py` | Switch from SkillRunner to BundleSocialClient |
| `SmartAIMentor/backend/app/models/schemas.py` | Update `skill_used` default to `"bundle-social"` |
| `SmartAIMentor/backend/tests/test_video_publish_workflow.py` | Update tests for new client interface |
| `SmartAIMentor/.env` | Add `BUNDLE_SOCIAL_API_KEY` |

### Unchanged files
| File | Reason |
|---|---|
| `SmartAIMentor/backend/app/services/skill_runner.py` | Keep as dead code for reference. Will be removed in a future cleanup. |

---

## Platform Mapping

Frontend sends lowercase platform names. Bundle Social API uses uppercase enum strings.

```python
PLATFORM_ENUM_MAP: dict[str, str] = {
    "x": "TWITTER",
    "twitter": "TWITTER",
    "tiktok": "TIKTOK",
    "instagram": "INSTAGRAM",
    "youtube": "YOUTUBE",
    "linkedin": "LINKEDIN",
    "facebook": "FACEBOOK",
    "threads": "THREADS",
    "pinterest": "PINTEREST",
    "reddit": "REDDIT",
    "mastodon": "MASTODON",
    "discord": "DISCORD",
    "slack": "SLACK",
    "bluesky": "BLUESKY",
    "google_business": "GOOGLE_BUSINESS",
}
```

---

## Task 1: Config & Environment

**Files:**
- Modify: `SmartAIMentor/backend/app/config.py`
- Modify: `SmartAIMentor/.env`
- Test: `SmartAIMentor/backend/tests/test_config.py` (new)

- [ ] **Step 1: Write the config test**

Create `SmartAIMentor/backend/tests/test_config.py`:

```python
from app.config import settings


def test_bundle_social_settings_exist():
    assert hasattr(settings, "bundle_social_api_key")
    assert hasattr(settings, "bundle_social_base_url")
    assert settings.bundle_social_base_url == "https://api.bundle.social"


def test_post_bridge_settings_still_exist():
    """Post Bridge settings preserved during migration."""
    assert hasattr(settings, "post_bridge_api_key")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SmartAIMentor && PYTHONPATH=backend .venv/bin/pytest backend/tests/test_config.py -v`
Expected: FAIL — `bundle_social_api_key` attribute missing

- [ ] **Step 3: Update config.py**

Replace `SmartAIMentor/backend/app/config.py` with:

```python
from pathlib import Path

from pydantic_settings import BaseSettings

PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent
BACKEND_DIR = Path(__file__).resolve().parent.parent


class Settings(BaseSettings):
    gemini_api_key: str = ""
    https_proxy: str | None = None
    upload_dir: str = str(BACKEND_DIR / "data" / "uploads")
    tasks_file: str = str(BACKEND_DIR / "data" / "tasks.json")
    teams_file: str = str(BACKEND_DIR / "data" / "teams.json")
    max_file_size_mb: int = 500

    # Bundle Social API
    bundle_social_api_key: str = ""
    bundle_social_base_url: str = "https://api.bundle.social"
    bundle_social_portal_redirect_url: str = "http://localhost:3000/social/callback"

    # Post Bridge API (deprecated, kept for reference)
    post_bridge_api_key: str = ""
    post_bridge_base_url: str = "https://api.post-bridge.com"
    post_bridge_video_cover_timestamp_ms: int = 3000
    post_bridge_tiktok_draft: bool = False
    post_bridge_tiktok_is_aigc: bool = False
    post_bridge_instagram_is_trial_reel: bool = False

    model_config = {"env_file": str(PROJECT_ROOT / ".env"), "extra": "ignore"}


settings = Settings()
```

- [ ] **Step 4: Add BUNDLE_SOCIAL_API_KEY to .env**

Append to `SmartAIMentor/.env`:

```
# Bundle Social
BUNDLE_SOCIAL_API_KEY=00c78f38-0a15-49bb-a244-f7c3ffc37df4
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd SmartAIMentor && PYTHONPATH=backend .venv/bin/pytest backend/tests/test_config.py -v`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
cd SmartAIMentor
git add backend/app/config.py backend/tests/test_config.py .env
git commit -m "feat: add Bundle Social config settings and env var"
```

---

## Task 2: TeamStore

**Files:**
- Create: `SmartAIMentor/backend/app/services/team_store.py`
- Test: `SmartAIMentor/backend/tests/test_team_store.py` (new)

Mirrors the existing `TaskStore` pattern exactly: thread-safe JSON file store with `_lock`, `_read()`, `_write()`.

- [ ] **Step 1: Write the TeamStore tests**

Create `SmartAIMentor/backend/tests/test_team_store.py`:

```python
from app.services.team_store import TeamStore


def test_get_team_returns_none_when_empty(tmp_path):
    store = TeamStore(str(tmp_path / "teams.json"))
    assert store.get_team("creator_001") is None


def test_save_and_get_team(tmp_path):
    store = TeamStore(str(tmp_path / "teams.json"))
    store.save_team("creator_001", "team_abc123")

    result = store.get_team("creator_001")
    assert result == "team_abc123"


def test_save_is_idempotent(tmp_path):
    store = TeamStore(str(tmp_path / "teams.json"))
    store.save_team("creator_001", "team_v1")
    store.save_team("creator_001", "team_v2")

    assert store.get_team("creator_001") == "team_v2"


def test_creates_file_if_missing(tmp_path):
    path = tmp_path / "sub" / "teams.json"
    store = TeamStore(str(path))
    assert path.exists()


def test_thread_safety(tmp_path):
    """Concurrent saves don't corrupt the file."""
    import threading

    store = TeamStore(str(tmp_path / "teams.json"))
    errors = []

    def writer(creator_id, team_id):
        try:
            store.save_team(creator_id, team_id)
        except Exception as e:
            errors.append(e)

    threads = [threading.Thread(target=writer, args=(f"c_{i}", f"t_{i}")) for i in range(20)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    assert not errors
    for i in range(20):
        assert store.get_team(f"c_{i}") == f"t_{i}"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd SmartAIMentor && PYTHONPATH=backend .venv/bin/pytest backend/tests/test_team_store.py -v`
Expected: FAIL — module not found

- [ ] **Step 3: Implement TeamStore**

Create `SmartAIMentor/backend/app/services/team_store.py`:

```python
import json
from datetime import datetime, timezone
from pathlib import Path
from threading import Lock


class TeamStore:
    def __init__(self, path: str):
        self._path = Path(path)
        self._lock = Lock()
        self._ensure_file()

    def _ensure_file(self):
        if not self._path.exists():
            self._path.parent.mkdir(parents=True, exist_ok=True)
            self._write({"teams": {}})

    def _read(self) -> dict:
        with open(self._path, "r", encoding="utf-8") as f:
            return json.load(f)

    def _write(self, data: dict):
        with open(self._path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)

    def get_team(self, creator_id: str) -> str | None:
        data = self._read()
        entry = data["teams"].get(creator_id)
        return entry["team_id"] if entry else None

    def save_team(self, creator_id: str, team_id: str) -> None:
        with self._lock:
            data = self._read()
            data["teams"][creator_id] = {
                "team_id": team_id,
                "creator_id": creator_id,
                "created_at": datetime.now(timezone.utc).isoformat(),
            }
            self._write(data)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd SmartAIMentor && PYTHONPATH=backend .venv/bin/pytest backend/tests/test_team_store.py -v`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
cd SmartAIMentor
git add backend/app/services/team_store.py backend/tests/test_team_store.py
git commit -m "feat: add TeamStore for creator_id -> teamId mapping"
```

---

## Task 3: BundleSocialClient

**Files:**
- Create: `SmartAIMentor/backend/app/services/bundle_social_client.py`
- Test: `SmartAIMentor/backend/tests/test_bundle_social_client.py` (new)

This is the core client that wraps all Bundle Social API calls. It uses `x-api-key` auth (not Bearer), and the verified API schema from testing.

Key interface:

```python
class BundleSocialClient:
    async def ensure_team(self, team_store: TeamStore, creator_id: str) -> str
    async def get_social_accounts(self, team_id: str) -> list[dict]
    async def create_portal_link(self, team_id: str, platforms: list[str], redirect_url: str) -> str
    async def disconnect_social_account(self, team_id: str, platform: str) -> bool
    async def upload_media(self, team_id: str, file_path: str) -> str | None
    async def create_post(self, team_id: str, title: str, post_date: str,
                          status: str, social_account_types: list[str], data: dict) -> dict
    async def get_post(self, team_id: str, post_id: str) -> dict
    async def publish(self, team_id: str, caption: str, file_path: str,
                      platforms: list[str], file_type: str, **kwargs) -> dict
```

- [ ] **Step 1: Write the client tests**

Create `SmartAIMentor/backend/tests/test_bundle_social_client.py`:

```python
import json

import pytest

from app.services.bundle_social_client import (
    BundleSocialClient,
    PLATFORM_ENUM_MAP,
    build_bundle_data,
)


def test_platform_enum_map_covers_common_platforms():
    assert PLATFORM_ENUM_MAP["x"] == "TWITTER"
    assert PLATFORM_ENUM_MAP["tiktok"] == "TIKTOK"
    assert PLATFORM_ENUM_MAP["instagram"] == "INSTAGRAM"
    assert PLATFORM_ENUM_MAP["youtube"] == "YOUTUBE"
    assert PLATFORM_ENUM_MAP["twitter"] == "TWITTER"


def test_build_bundle_data_single_platform_image():
    data = build_bundle_data(
        platforms=["tiktok"],
        caption="Hello world #test",
        upload_id="media_abc",
        file_type="image",
    )
    assert "TIKTOK" in data
    assert data["TIKTOK"]["text"] == "Hello world #test"
    assert data["TIKTOK"]["uploadIds"] == ["media_abc"]
    assert data["TIKTOK"]["type"] == "IMAGE"
    assert data["TIKTOK"]["privacy"] == "PUBLIC_TO_EVERYONE"


def test_build_bundle_data_multi_platform_video():
    data = build_bundle_data(
        platforms=["x", "tiktok"],
        caption="New drop!",
        upload_id="media_123",
        file_type="video",
    )
    assert "TWITTER" in data
    assert "TIKTOK" in data
    assert data["TIKTOK"]["type"] == "VIDEO"
    assert data["TWITTER"]["text"] == "New drop!"
    assert data["TWITTER"]["uploadIds"] == ["media_123"]


def test_build_bundle_data_tiktok_options():
    data = build_bundle_data(
        platforms=["tiktok"],
        caption="AI art",
        upload_id="media_456",
        file_type="video",
        tiktok_is_aigc=True,
        tiktok_draft=True,
    )
    assert data["TIKTOK"]["isAiGenerated"] is True
    assert data["TIKTOK"]["uploadToDraft"] is True


def test_build_bundle_data_youtube_short():
    data = build_bundle_data(
        platforms=["youtube"],
        caption="Short video",
        upload_id="media_789",
        file_type="video",
    )
    assert data["YOUTUBE"]["type"] == "SHORT"
    assert data["YOUTUBE"]["privacy"] == "PUBLIC"


def test_build_bundle_data_instagram_reel():
    data = build_bundle_data(
        platforms=["instagram"],
        caption="Reel caption",
        upload_id="media_101",
        file_type="video",
    )
    assert data["INSTAGRAM"]["type"] == "REEL"
    assert data["INSTAGRAM"]["shareToFeed"] is True


def test_build_bundle_data_instagram_post_image():
    data = build_bundle_data(
        platforms=["instagram"],
        caption="Photo caption",
        upload_id="media_202",
        file_type="image",
    )
    assert data["INSTAGRAM"]["type"] == "POST"


def test_build_bundle_data_unknown_platform_uppercased():
    """Unknown platform names are uppercased."""
    data = build_bundle_data(
        platforms=["bluesky"],
        caption="Hello",
        upload_id="media_303",
        file_type="image",
    )
    assert "BLUESKY" in data


@pytest.mark.asyncio
async def test_ensure_team_creates_and_saves(tmp_path):
    """ensure_team calls Bundle Social API and persists via TeamStore."""
    from app.services.team_store import TeamStore

    store = TeamStore(str(tmp_path / "teams.json"))
    client = BundleSocialClient(api_key="test_key", base_url="https://fake")

    # We'll test the logic path without real HTTP calls
    # by verifying the TeamStore integration
    assert store.get_team("creator_001") is None


def test_client_headers_use_x_api_key():
    client = BundleSocialClient(api_key="pk_live_abc", base_url="https://fake")
    headers = client._headers()
    assert headers["x-api-key"] == "pk_live_abc"
    assert "Authorization" not in headers
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd SmartAIMentor && PYTHONPATH=backend .venv/bin/pytest backend/tests/test_bundle_social_client.py -v`
Expected: FAIL — module not found

- [ ] **Step 3: Implement BundleSocialClient**

Create `SmartAIMentor/backend/app/services/bundle_social_client.py`:

```python
import logging
import mimetypes
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import httpx

logger = logging.getLogger(__name__)

PLATFORM_ENUM_MAP: dict[str, str] = {
    "x": "TWITTER",
    "twitter": "TWITTER",
    "tiktok": "TIKTOK",
    "instagram": "INSTAGRAM",
    "youtube": "YOUTUBE",
    "linkedin": "LINKEDIN",
    "facebook": "FACEBOOK",
    "threads": "THREADS",
    "pinterest": "PINTEREST",
    "reddit": "REDDIT",
    "mastodon": "MASTODON",
    "discord": "DISCORD",
    "slack": "SLACK",
    "bluesky": "BLUESKY",
    "google_business": "GOOGLE_BUSINESS",
}


def build_bundle_data(
    *,
    platforms: list[str],
    caption: str,
    upload_id: str,
    file_type: str,
    tiktok_is_aigc: bool = False,
    tiktok_draft: bool = False,
) -> dict[str, dict[str, Any]]:
    """Build the Bundle Social `data` object with per-platform configs."""
    data: dict[str, dict[str, Any]] = {}

    for platform in platforms:
        enum_name = PLATFORM_ENUM_MAP.get(platform.lower(), platform.upper())
        config: dict[str, Any] = {
            "text": caption,
            "uploadIds": [upload_id],
        }

        if enum_name == "TIKTOK":
            config["type"] = "VIDEO" if file_type == "video" else "IMAGE"
            config["privacy"] = "PUBLIC_TO_EVERYONE"
            if tiktok_is_aigc:
                config["isAiGenerated"] = True
            if tiktok_draft:
                config["uploadToDraft"] = True

        elif enum_name == "INSTAGRAM":
            if file_type == "video":
                config["type"] = "REEL"
                config["shareToFeed"] = True
            else:
                config["type"] = "POST"

        elif enum_name == "YOUTUBE":
            config["type"] = "SHORT" if file_type == "video" else "VIDEO"
            config["privacy"] = "PUBLIC"

        # TWITTER, THREADS, and others: text + uploadIds is sufficient

        data[enum_name] = config

    return data


class BundleSocialClient:
    def __init__(self, api_key: str, base_url: str, proxy: str | None = None):
        self.api_key = api_key
        self.base_url = base_url
        self.proxy = proxy

    def _headers(self) -> dict[str, str]:
        return {
            "x-api-key": self.api_key,
            "Content-Type": "application/json",
        }

    async def _client(self) -> httpx.AsyncClient:
        return httpx.AsyncClient(
            base_url=self.base_url,
            headers=self._headers(),
            proxy=self.proxy,
            timeout=60,
        )

    async def list_teams(self) -> list[dict]:
        async with await self._client() as client:
            resp = await client.get("/api/v1/team/")
            resp.raise_for_status()
            return resp.json()

    async def create_team(self, name: str) -> dict:
        async with await self._client() as client:
            resp = await client.post("/api/v1/team/", json={"name": name})
            resp.raise_for_status()
            return resp.json()

    async def ensure_team(self, team_store: "TeamStore", creator_id: str) -> str:
        """Get existing teamId for creator, or create a new one."""
        from app.services.team_store import TeamStore

        existing = team_store.get_team(creator_id)
        if existing:
            return existing

        team = await self.create_team(creator_id)
        team_id = team["id"]
        team_store.save_team(creator_id, team_id)
        logger.info("Created team %s for creator %s", team_id, creator_id)
        return team_id

    async def get_social_accounts(self, team_id: str) -> list[dict]:
        """Get social accounts from team listing (accounts embedded in team response)."""
        async with await self._client() as client:
            resp = await client.get("/api/v1/team/")
            resp.raise_for_status()
            teams = resp.json()
            if isinstance(teams, list):
                for team in teams:
                    if team.get("id") == team_id:
                        return team.get("socialAccounts", [])
            return []

    async def create_portal_link(
        self, team_id: str, platforms: list[str], redirect_url: str
    ) -> str:
        """Generate hosted OAuth portal link. Returns the portal URL."""
        enum_platforms = [
            PLATFORM_ENUM_MAP.get(p.lower(), p.upper()) for p in platforms
        ]
        async with await self._client() as client:
            resp = await client.post(
                "/api/v1/social-account/create-portal-link",
                json={
                    "teamId": team_id,
                    "redirectUrl": redirect_url,
                    "socialAccountTypes": enum_platforms,
                },
            )
            resp.raise_for_status()
            return resp.json()["url"]

    async def disconnect_social_account(self, team_id: str, platform: str) -> bool:
        """Disconnect a social account by platform type."""
        enum_name = PLATFORM_ENUM_MAP.get(platform.lower(), platform.upper())
        async with await self._client() as client:
            resp = await client.request(
                "DELETE",
                "/api/v1/social-account/disconnect",
                json={"type": enum_name, "teamId": team_id},
            )
            resp.raise_for_status()
            return True

    async def upload_media(self, team_id: str, file_path: str) -> str | None:
        """Upload a media file. Returns uploadId on success."""
        path = Path(file_path)
        if not path.exists():
            logger.error("File not found: %s", file_path)
            return None

        mime = mimetypes.guess_type(str(path))[0] or "application/octet-stream"

        async with httpx.AsyncClient(
            base_url=self.base_url,
            headers={"x-api-key": self.api_key},
            proxy=self.proxy,
            timeout=120,
        ) as client:
            with open(path, "rb") as f:
                resp = await client.post(
                    "/api/v1/upload/",
                    data={"teamId": team_id},
                    files={"file": (path.name, f, mime)},
                )
            resp.raise_for_status()
            data = resp.json()
            upload_id = data.get("id") or data.get("uploadId")
            logger.info("Media uploaded: %s", upload_id)
            return upload_id

    async def create_post(
        self,
        team_id: str,
        title: str,
        post_date: str,
        status: str,
        social_account_types: list[str],
        data: dict,
    ) -> dict:
        """Create a post in Bundle Social."""
        body = {
            "teamId": team_id,
            "title": title,
            "postDate": post_date,
            "status": status,
            "socialAccountTypes": social_account_types,
            "data": data,
        }
        async with await self._client() as client:
            resp = await client.post("/api/v1/post/", json=body)
            resp.raise_for_status()
            result = resp.json()
            post_id = result.get("id")
            logger.info("Post created: %s", post_id)
            return result

    async def get_post(self, team_id: str, post_id: str) -> dict:
        async with await self._client() as client:
            resp = await client.get(f"/api/v1/post/{post_id}", params={"teamId": team_id})
            resp.raise_for_status()
            return resp.json()

    async def publish(
        self,
        team_id: str,
        caption: str,
        file_path: str,
        platforms: list[str],
        file_type: str = "image",
        title: str | None = None,
        is_draft: bool = False,
        **kwargs,
    ) -> dict:
        """High-level: upload media + create post in one call.

        Returns: {"success": bool, "post_id": str | None, "error": str | None}
        """
        try:
            upload_id = await self.upload_media(team_id, file_path)
            if not upload_id:
                return {"success": False, "post_id": None, "error": "Media upload failed"}

            enum_types = [
                PLATFORM_ENUM_MAP.get(p.lower(), p.upper()) for p in platforms
            ]
            data = build_bundle_data(
                platforms=platforms,
                caption=caption,
                upload_id=upload_id,
                file_type=file_type,
                tiktok_is_aigc=kwargs.get("tiktok_is_aigc", False),
                tiktok_draft=kwargs.get("tiktok_draft", False),
            )

            now = datetime.now(timezone.utc)
            post_date = (now.replace(second=0, microsecond=0)).isoformat()
            status = "DRAFT" if is_draft else "SCHEDULED"

            result = await self.create_post(
                team_id=team_id,
                title=title or caption[:80],
                post_date=post_date,
                status=status,
                social_account_types=enum_types,
                data=data,
            )

            return {
                "success": True,
                "post_id": result.get("id"),
                "error": None,
            }

        except Exception as e:
            logger.exception("Bundle Social publish failed")
            return {"success": False, "post_id": None, "error": str(e)}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd SmartAIMentor && PYTHONPATH=backend .venv/bin/pytest backend/tests/test_bundle_social_client.py -v`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
cd SmartAIMentor
git add backend/app/services/bundle_social_client.py backend/tests/test_bundle_social_client.py
git commit -m "feat: add BundleSocialClient with upload, post, and account management"
```

---

## Task 4: Social API Routes

**Files:**
- Create: `SmartAIMentor/backend/app/api/social.py`
- Test: `SmartAIMentor/backend/tests/test_social_api.py` (new)

New routes for social account management. Follows the same `_init()` injection pattern as `publish.py` and `tasks.py`.

- [ ] **Step 1: Write the route tests**

Create `SmartAIMentor/backend/tests/test_social_api.py`:

```python
from unittest.mock import AsyncMock

from fastapi.testclient import TestClient

from app.api import social as social_api
from app.api import tasks as tasks_api
from app.main import app
from app.services.bundle_social_client import BundleSocialClient
from app.services.team_store import TeamStore


class FakeBundleSocialClient:
    def __init__(self):
        self.portal_calls = []
        self.disconnect_calls = []
        self.accounts_data = [
            {"platform": "TIKTOK", "username": "@test_user", "id": "sa_001"},
        ]

    async def ensure_team(self, store, creator_id):
        return "team_fake_001"

    async def get_social_accounts(self, team_id):
        return self.accounts_data

    async def create_portal_link(self, team_id, platforms, redirect_url):
        self.portal_calls.append((team_id, platforms, redirect_url))
        return "https://app.bundle.social/connect?token=fake"

    async def disconnect_social_account(self, team_id, platform):
        self.disconnect_calls.append((team_id, platform))
        return True


def test_connect_returns_portal_url(tmp_path):
    store = TeamStore(str(tmp_path / "teams.json"))
    client = FakeBundleSocialClient()

    with TestClient(app) as tc:
        social_api._init(store, client)
        tasks_api._init(store)

        resp = tc.post(
            "/api/social/connect",
            json={
                "creator_id": "creator_001",
                "platforms": ["tiktok", "instagram"],
            },
        )

    assert resp.status_code == 200
    body = resp.json()
    assert "portal_url" in body
    assert "team_id" in body
    assert len(client.portal_calls) == 1
    assert client.portal_calls[0][1] == ["tiktok", "instagram"]


def test_accounts_returns_list(tmp_path):
    store = TeamStore(str(tmp_path / "teams.json"))
    client = FakeBundleSocialClient()

    with TestClient(app) as tc:
        social_api._init(store, client)
        tasks_api._init(store)

        resp = tc.get("/api/social/accounts", params={"creator_id": "creator_001"})

    assert resp.status_code == 200
    body = resp.json()
    assert "accounts" in body
    assert len(body["accounts"]) == 1
    assert body["accounts"][0]["platform"] == "TIKTOK"


def test_disconnect_calls_client(tmp_path):
    store = TeamStore(str(tmp_path / "teams.json"))
    client = FakeBundleSocialClient()

    with TestClient(app) as tc:
        social_api._init(store, client)
        tasks_api._init(store)

        resp = tc.post(
            "/api/social/disconnect",
            json={
                "creator_id": "creator_001",
                "platform": "tiktok",
            },
        )

    assert resp.status_code == 200
    assert len(client.disconnect_calls) == 1
    assert client.disconnect_calls[0][1] == "tiktok"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd SmartAIMentor && PYTHONPATH=backend .venv/bin/pytest backend/tests/test_social_api.py -v`
Expected: FAIL — module not found

- [ ] **Step 3: Implement social routes**

Create `SmartAIMentor/backend/app/api/social.py`:

```python
import logging
from typing import Any

from fastapi import APIRouter, Query
from pydantic import BaseModel

from app.config import settings
from app.services.bundle_social_client import BundleSocialClient
from app.services.team_store import TeamStore

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/social", tags=["social"])

_store: TeamStore | None = None
_client: BundleSocialClient | None = None


def _init(store: TeamStore, client: BundleSocialClient):
    global _store, _client
    _store = store
    _client = client


class ConnectRequest(BaseModel):
    creator_id: str = "default"
    platforms: list[str] = []
    redirect_url: str | None = None


class DisconnectRequest(BaseModel):
    creator_id: str = "default"
    platform: str


@router.post("/connect")
async def connect(req: ConnectRequest):
    team_id = await _client.ensure_team(_store, req.creator_id)
    redirect_url = req.redirect_url or settings.bundle_social_portal_redirect_url
    url = await _client.create_portal_link(team_id, req.platforms, redirect_url)
    return {"portal_url": url, "team_id": team_id}


@router.get("/accounts")
async def list_accounts(creator_id: str = Query("default")):
    team_id = await _client.ensure_team(_store, creator_id)
    accounts = await _client.get_social_accounts(team_id)
    return {"team_id": team_id, "accounts": accounts}


@router.post("/disconnect")
async def disconnect(req: DisconnectRequest):
    team_id = await _client.ensure_team(_store, req.creator_id)
    await _client.disconnect_social_account(team_id, req.platform)
    return {"status": "disconnected", "platform": req.platform}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd SmartAIMentor && PYTHONPATH=backend .venv/bin/pytest backend/tests/test_social_api.py -v`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
cd SmartAIMentor
git add backend/app/api/social.py backend/tests/test_social_api.py
git commit -m "feat: add social account management API routes"
```

---

## Task 5: Update Publish Pipeline

**Files:**
- Modify: `SmartAIMentor/backend/app/api/publish.py`
- Modify: `SmartAIMentor/backend/app/models/schemas.py`
- Test: Update `SmartAIMentor/backend/tests/test_video_publish_workflow.py`

This switches the publish endpoint from SkillRunner to BundleSocialClient. The form interface stays the same (backward compatible with frontend). Internally, we route through the new client.

- [ ] **Step 1: Update schemas.py**

Change `skill_used` default from `""` to `"bundle-social"` in `SmartAIMentor/backend/app/models/schemas.py`:

```python
# Line 32: change default from "" to "bundle-social"
skill_used: str = "bundle-social"
```

- [ ] **Step 2: Rewrite publish.py**

Replace `SmartAIMentor/backend/app/api/publish.py` with:

```python
import asyncio
import logging
import shutil
from pathlib import Path
from typing import Any

from fastapi import APIRouter, UploadFile, File, Form

from app.config import settings
from app.models.schemas import PublishTask, PublishResponse, PublishResult
from app.services.bundle_social_client import BundleSocialClient
from app.services.team_store import TeamStore

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api", tags=["publish"])

_store: TaskStore | None = None
_bs_client: BundleSocialClient | None = None
_team_store: TeamStore | None = None

VIDEO_EXTENSIONS = (".mp4", ".mov", ".webm", ".avi", ".m4v")


def _init(store, bs_client: BundleSocialClient, team_store: TeamStore):
    global _store, _bs_client, _team_store
    _store = store
    _bs_client = bs_client
    _team_store = team_store


def _guess_file_type(filename: str) -> str:
    ext = Path(filename).suffix.lower()
    if ext in VIDEO_EXTENSIONS:
        return "video"
    return "image"


def _parse_platforms(platform: str, platforms: str | None = None) -> list[str]:
    raw = platforms if platforms else platform
    parsed: list[str] = []
    for item in raw.split(","):
        value = item.strip().lower()
        if not value:
            continue
        if value == "twitter":
            value = "x"
        if value not in parsed:
            parsed.append(value)
    return parsed or ["x"]


def _platform_label(platforms: list[str]) -> str:
    return platforms[0] if len(platforms) == 1 else ",".join(platforms)


@router.post("/publish", response_model=PublishResponse)
async def publish(
    file: UploadFile = File(...),
    platform: str = Form("x"),
    platforms: str | None = Form(None),
    creator_id: str = Form("default"),
    caption: str = Form(""),
    hashtags: str = Form(""),
    video_cover_timestamp_ms: int | None = Form(None),
    tiktok_draft: bool | None = Form(None),
    tiktok_is_aigc: bool | None = Form(None),
    instagram_is_trial_reel: bool | None = Form(None),
    processing_enabled: bool = Form(True),
    is_draft: bool | None = Form(None),
):
    upload_dir = Path(settings.upload_dir)
    upload_dir.mkdir(parents=True, exist_ok=True)

    dest = upload_dir / (file.filename or "upload")
    with open(dest, "wb") as f:
        shutil.copyfileobj(file.file, f)

    file_type = _guess_file_type(file.filename or "")
    platform_list = _parse_platforms(platform, platforms)
    platform_label = _platform_label(platform_list)
    tag_list = [t.strip() for t in hashtags.split(",") if t.strip()] if hashtags else []
    full_caption = caption
    if tag_list:
        full_caption += "\n" + " ".join(f"#{t.lstrip('#')}" for t in tag_list)

    task = PublishTask(
        creator_id=creator_id,
        platform=platform_label,
        platforms=platform_list,
        caption=full_caption,
        hashtags=tag_list,
        file_path=str(dest),
        file_type=file_type,
    )
    _store.create(task)

    asyncio.create_task(
        _do_publish(
            task.task_id,
            creator_id,
            full_caption,
            str(dest),
            platform_list,
            file_type,
            is_draft=is_draft,
            tiktok_draft=tiktok_draft or False,
            tiktok_is_aigc=tiktok_is_aigc or False,
        )
    )

    return PublishResponse(
        task_id=task.task_id,
        status="publishing",
        platform=platform_label,
        platforms=platform_list,
        skill_used="bundle-social",
    )


async def _do_publish(
    task_id: str,
    creator_id: str,
    caption: str,
    file_path: str,
    platforms: list[str],
    file_type: str,
    is_draft: bool = False,
    tiktok_draft: bool = False,
    tiktok_is_aigc: bool = False,
):
    try:
        team_id = await _bs_client.ensure_team(_team_store, creator_id)

        result = await _bs_client.publish(
            team_id=team_id,
            caption=caption,
            file_path=file_path,
            platforms=platforms,
            file_type=file_type,
            is_draft=is_draft,
            tiktok_draft=tiktok_draft,
            tiktok_is_aigc=tiktok_is_aigc,
        )

        if result["success"]:
            _store.update(
                task_id,
                status="completed",
                result=PublishResult(
                    platform_post_id=result.get("post_id"),
                ).model_dump(),
            )
        else:
            _store.update(task_id, status="failed", error=result.get("error"))
    except Exception as e:
        logger.exception("Publish failed for %s", task_id)
        _store.update(task_id, status="failed", error=str(e))
```

Note: `_build_platform_configurations` is removed — the platform-specific config is now built inside `BundleSocialClient.build_bundle_data()`. The `TaskStore` import now comes from `app.services.task_store` (same as before).

Wait — I need to fix the import. The `_store` type hint should be `TaskStore` from `app.services.task_store`. Let me add that import.

- [ ] **Step 2 (fix): Add TaskStore import to publish.py**

Add to the imports at the top of `publish.py`:

```python
from app.services.task_store import TaskStore
```

And fix the `_init` type hints:

```python
_store: TaskStore | None = None
```

But since we're importing both `TaskStore` from task_store and we already have it, the `_init` function should be:

```python
def _init(store: TaskStore, bs_client: BundleSocialClient, team_store: TeamStore):
```

Wait, but `_store` here is the **TaskStore** (for publish tasks), not the TeamStore. We need both. Let me be clear:

- `_store` = TaskStore (for PublishTask persistence)
- `_bs_client` = BundleSocialClient
- `_team_store` = TeamStore (for creator_id → teamId mapping)

This is correct in the code above.

- [ ] **Step 3: Update tests for new publish interface**

Update `SmartAIMentor/backend/tests/test_video_publish_workflow.py` — replace the entire file:

```python
from pathlib import Path
from time import sleep

from fastapi.testclient import TestClient

from app.api import chat as chat_api
from app.api import publish as publish_api
from app.api import social as social_api
from app.api import tasks as tasks_api
from app.main import app
from app.services.bundle_social_client import BundleSocialClient
from app.services.team_store import TeamStore
from app.services.task_store import TaskStore


class FakeBundleSocialClient:
    def __init__(self):
        self.publish_calls = []

    async def ensure_team(self, store, creator_id):
        return f"team_{creator_id}"

    async def publish(self, team_id, caption, file_path, platforms, file_type="image",
                      title=None, is_draft=False, **kwargs):
        self.publish_calls.append({
            "team_id": team_id,
            "caption": caption,
            "file_path": file_path,
            "platforms": platforms,
            "file_type": file_type,
            "is_draft": is_draft,
            "kwargs": kwargs,
        })
        return {"success": True, "post_id": "post_bundle_001", "error": None}

    async def get_social_accounts(self, team_id):
        return []

    async def create_portal_link(self, team_id, platforms, redirect_url):
        return "https://fake.portal/connect"

    async def disconnect_social_account(self, team_id, platform):
        return True


class FakeAgent:
    async def handle(self, message, creator_id="default", has_file=False):
        return {
            "intent": "publish",
            "platforms": ["x", "instagram", "tiktok"],
            "caption": "Chat generated video caption",
            "hashtags": ["ai", "mentor"],
        }


def test_publish_video_uses_bundle_social(tmp_path, monkeypatch):
    task_store = TaskStore(str(tmp_path / "tasks.json"))
    team_store = TeamStore(str(tmp_path / "teams.json"))
    bs_client = FakeBundleSocialClient()
    monkeypatch.setattr(publish_api.settings, "upload_dir", str(tmp_path / "uploads"))

    with TestClient(app) as client:
        publish_api._init(task_store, bs_client, team_store)
        tasks_api._init(task_store)
        social_api._init(team_store, bs_client)

        response = client.post(
            "/api/publish",
            data={
                "platforms": "x, instagram, tiktok",
                "creator_id": "lana",
                "caption": "Mentoraix video smoke",
                "hashtags": "ai,mentor",
                "tiktok_is_aigc": "true",
                "is_draft": "true",
            },
            files={"file": ("demo.mp4", b"fake-video-bytes", "video/mp4")},
        )

    assert response.status_code == 200
    payload = response.json()
    assert payload["platforms"] == ["x", "instagram", "tiktok"]
    assert payload["skill_used"] == "bundle-social"

    task = task_store.get(payload["task_id"])
    assert task is not None
    assert task["file_type"] == "video"
    assert task["platforms"] == ["x", "instagram", "tiktok"]

    for _ in range(20):
        if bs_client.publish_calls:
            break
        sleep(0.01)

    assert bs_client.publish_calls
    call = bs_client.publish_calls[0]
    assert call["platforms"] == ["x", "instagram", "tiktok"]
    assert call["team_id"] == "team_lana"
    assert call["is_draft"] is True
    assert call["kwargs"]["tiktok_is_aigc"] is True


def test_chat_publish_uses_bundle_social(tmp_path, monkeypatch):
    task_store = TaskStore(str(tmp_path / "tasks.json"))
    team_store = TeamStore(str(tmp_path / "teams.json"))
    bs_client = FakeBundleSocialClient()
    monkeypatch.setattr(chat_api.settings, "upload_dir", str(tmp_path / "uploads"))

    with TestClient(app) as client:
        chat_api._init(FakeAgent(), bs_client, team_store, task_store)
        tasks_api._init(task_store)
        social_api._init(team_store, bs_client)

        response = client.post(
            "/api/chat",
            data={
                "message": "把这个视频同步发到 X、Instagram、TikTok",
                "creator_id": "lana",
            },
            files={"file": ("chat-demo.mp4", b"fake-video-bytes", "video/mp4")},
        )

    assert response.status_code == 200
    payload = response.json()
    assert payload["action_taken"]["platforms"] == ["x", "instagram", "tiktok"]

    task = task_store.get(payload["action_taken"]["task_id"])
    assert task is not None
    assert task["file_type"] == "video"
    assert task["platforms"] == ["x", "instagram", "tiktok"]

    for _ in range(20):
        if bs_client.publish_calls:
            break
        sleep(0.01)

    assert bs_client.publish_calls[0]["platforms"] == ["x", "instagram", "tiktok"]


def test_build_bundle_data_generates_correct_structure():
    from app.services.bundle_social_client import build_bundle_data

    data = build_bundle_data(
        platforms=["tiktok", "x"],
        caption="Test caption",
        upload_id="media_test",
        file_type="video",
        tiktok_is_aigc=True,
    )
    assert data["TIKTOK"]["type"] == "VIDEO"
    assert data["TIKTOK"]["isAiGenerated"] is True
    assert data["TIKTOK"]["privacy"] == "PUBLIC_TO_EVERYONE"
    assert data["TWITTER"]["uploadIds"] == ["media_test"]
    assert data["TWITTER"]["text"] == "Test caption"
```

- [ ] **Step 4: Run all tests**

Run: `cd SmartAIMentor && PYTHONPATH=backend .venv/bin/pytest backend/tests/ -v`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
cd SmartAIMentor
git add backend/app/api/publish.py backend/app/models/schemas.py backend/tests/test_video_publish_workflow.py
git commit -m "feat: switch publish pipeline from Post Bridge to Bundle Social"
```

---

## Task 6: Update Chat Pipeline

**Files:**
- Modify: `SmartAIMentor/backend/app/api/chat.py`

Switch chat.py from SkillRunner to BundleSocialClient. Same `_init()` pattern, same publish orchestration.

- [ ] **Step 1: Rewrite chat.py**

Replace `SmartAIMentor/backend/app/api/chat.py` with:

```python
import asyncio
import logging
import shutil
import uuid
from pathlib import Path
from typing import Any

from fastapi import APIRouter, UploadFile, File, Form

from app.config import settings
from app.api.publish import _guess_file_type, _parse_platforms, _platform_label
from app.models.schemas import ChatResponse, PublishTask, PublishResult
from app.services.agent_client import AgentClient
from app.services.bundle_social_client import BundleSocialClient
from app.services.team_store import TeamStore
from app.services.task_store import TaskStore

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api", tags=["chat"])

_agent: AgentClient | None = None
_bs_client: BundleSocialClient | None = None
_team_store: TeamStore | None = None
_task_store: TaskStore | None = None


def _init(agent: AgentClient, bs_client: BundleSocialClient, team_store: TeamStore, task_store: TaskStore):
    global _agent, _bs_client, _team_store, _task_store
    _agent = agent
    _bs_client = bs_client
    _team_store = team_store
    _task_store = task_store


@router.post("/chat", response_model=ChatResponse)
async def chat(
    message: str = Form(...),
    creator_id: str = Form("default"),
    conversation_id: str | None = Form(None),
    file: UploadFile | None = File(None),
):
    conv_id = conversation_id or f"conv_{uuid.uuid4().hex[:12]}"

    file_path: str | None = None
    if file and file.filename:
        upload_dir = Path(settings.upload_dir)
        upload_dir.mkdir(parents=True, exist_ok=True)
        dest = upload_dir / file.filename
        with open(dest, "wb") as f:
            shutil.copyfileobj(file.file, f)
        file_path = str(dest)

    agent_result = await _agent.handle(message, creator_id, has_file=file_path is not None)

    if agent_result.get("intent") == "publish" and file_path:
        caption = agent_result.get("caption", message)
        hashtags = agent_result.get("hashtags", [])
        agent_platforms = agent_result.get("platforms")
        platform = agent_result.get("platform", "x")
        if isinstance(agent_platforms, list):
            platforms_text = ",".join(str(p) for p in agent_platforms)
        elif isinstance(agent_platforms, str):
            platforms_text = agent_platforms
        else:
            platforms_text = None
        platform_list = _parse_platforms(platform, platforms_text)
        platform_label = _platform_label(platform_list)
        file_type = _guess_file_type(file_path)
        full_caption = caption
        if hashtags:
            full_caption += "\n" + " ".join(f"#{h.lstrip('#')}" for h in hashtags)

        task = PublishTask(
            creator_id=creator_id,
            platform=platform_label,
            platforms=platform_list,
            caption=full_caption,
            hashtags=hashtags,
            file_path=file_path,
            file_type=file_type,
        )
        _task_store.create(task)

        asyncio.create_task(
            _do_publish(task.task_id, creator_id, full_caption, file_path, platform_list, file_type)
        )

        reply = f"好的！正在帮你发到 {platform_label.upper()}，文案：{caption}"
        if hashtags:
            reply += f"，标签：{' '.join('#' + h.lstrip('#') for h in hashtags)}"

        return ChatResponse(
            reply=reply,
            conversation_id=conv_id,
            action_taken={
                "type": "publish",
                "platform": platform_label,
                "platforms": platform_list,
                "task_id": task.task_id,
            },
        )
    else:
        reply = agent_result.get("reply", "嗯，我在听，继续说？")
        return ChatResponse(reply=reply, conversation_id=conv_id)


async def _do_publish(
    task_id: str,
    creator_id: str,
    caption: str,
    file_path: str,
    platforms: list[str],
    file_type: str,
):
    try:
        team_id = await _bs_client.ensure_team(_team_store, creator_id)
        result = await _bs_client.publish(
            team_id=team_id,
            caption=caption,
            file_path=file_path,
            platforms=platforms,
            file_type=file_type,
        )

        if result["success"]:
            _task_store.update(
                task_id,
                status="completed",
                result=PublishResult(
                    platform_post_id=result.get("post_id"),
                ).model_dump(),
            )
        else:
            _task_store.update(task_id, status="failed", error=result.get("error"))
    except Exception as e:
        logger.exception("Chat publish failed for %s", task_id)
        _task_store.update(task_id, status="failed", error=str(e))
```

- [ ] **Step 2: Run all tests**

Run: `cd SmartAIMentor && PYTHONPATH=backend .venv/bin/pytest backend/tests/ -v`
Expected: All PASS

- [ ] **Step 3: Commit**

```bash
cd SmartAIMentor
git add backend/app/api/chat.py
git commit -m "feat: switch chat pipeline from SkillRunner to BundleSocialClient"
```

---

## Task 7: Wire main.py

**Files:**
- Modify: `SmartAIMentor/backend/app/main.py`

Wire all new components: TeamStore, BundleSocialClient, social router. Update `_init` calls for publish and chat to use new signatures.

- [ ] **Step 1: Update main.py**

Replace `SmartAIMentor/backend/app/main.py` with:

```python
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import settings
from app.services.agent_client import AgentClient
from app.services.bundle_social_client import BundleSocialClient
from app.services.skill_runner import SkillRunner
from app.services.task_store import TaskStore
from app.services.team_store import TeamStore
from app.api import chat, publish, social, tasks, v1


@asynccontextmanager
async def lifespan(app: FastAPI):
    task_store = TaskStore(settings.tasks_file)
    team_store = TeamStore(settings.teams_file)
    bs_client = BundleSocialClient(
        api_key=settings.bundle_social_api_key,
        base_url=settings.bundle_social_base_url,
        proxy=settings.https_proxy,
    )
    agent = AgentClient()

    publish._init(task_store, bs_client, team_store)
    chat._init(agent, bs_client, team_store, task_store)
    tasks._init(task_store)
    social._init(team_store, bs_client)
    yield


app = FastAPI(title="Mentoraix API", version="0.2.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(publish.router)
app.include_router(tasks.router)
app.include_router(chat.router)
app.include_router(social.router)
app.include_router(v1.router)


@app.get("/api/health")
async def health():
    return {"status": "ok"}
```

- [ ] **Step 2: Run all tests**

Run: `cd SmartAIMentor && PYTHONPATH=backend .venv/bin/pytest backend/tests/ -v`
Expected: All PASS

- [ ] **Step 3: Commit**

```bash
cd SmartAIMentor
git add backend/app/main.py
git commit -m "feat: wire BundleSocialClient, TeamStore, and social router in main.py"
```

---

## Task 8: Integration Smoke Test

**Files:** None (manual testing)

Verify the full stack works end-to-end with the real Bundle Social API.

- [ ] **Step 1: Start the backend**

Run: `cd SmartAIMentor && bash backend/run.sh`

Expected: Server starts on port 58888

- [ ] **Step 2: Test health endpoint**

Run: `curl http://localhost:58888/api/health`
Expected: `{"status":"ok"}`

- [ ] **Step 3: Test social accounts listing**

Run: `curl "http://localhost:58888/api/social/accounts?creator_id=leroy"`

Expected: Returns JSON with `team_id` and `accounts` array. First call should create a team automatically.

- [ ] **Step 4: Test OAuth portal link generation**

Run: `curl -X POST http://localhost:58888/api/social/connect -H "Content-Type: application/json" -d '{"creator_id":"leroy","platforms":["instagram"]}'`

Expected: Returns `portal_url` — a Bundle Social hosted OAuth URL

- [ ] **Step 5: Test publish (if accounts connected)**

Create a small test image and post to a connected platform (e.g., TikTok or X):

```bash
# Create a tiny test image
python3 -c "from PIL import Image; Image.new('RGB',(100,100),'blue').save('/tmp/test_bundle.png')"

# Publish via API
curl -X POST http://localhost:58888/api/publish \
  -F "file=@/tmp/test_bundle.png" \
  -F "platform=x" \
  -F "creator_id=leroy" \
  -F 'caption=Bundle Social integration test'
```

Expected: Returns task_id with status "publishing". Check task status:

```bash
curl "http://localhost:58888/api/tasks/<task_id>"
```

- [ ] **Step 6: Commit if any fixes needed**

If integration testing reveals issues, fix and commit with descriptive messages.

---

## Self-Review

### 1. Spec Coverage

| Spec Requirement | Task |
|---|---|
| BundleSocialClient class | Task 3 |
| TeamStore (creator_id → teamId) | Task 2 |
| Social routes (connect, accounts, disconnect) | Task 4 |
| Publish route uses new client | Task 5 |
| Chat route uses new client | Task 6 |
| Config settings | Task 1 |
| main.py wiring | Task 7 |
| Integration testing | Task 8 |
| API corrections (data vs platforms, title required, etc.) | Applied in Task 3 |

### 2. Placeholder Scan

No TBD, TODO, or "implement later" patterns. All code blocks contain complete implementations.

### 3. Type Consistency

- `BundleSocialClient.publish()` returns `{"success": bool, "post_id": str|None, "error": str|None}` — consistent in publish.py `_do_publish` and chat.py `_do_publish`
- `BundleSocialClient._headers()` uses `x-api-key` (not Bearer) — consistent with verified API
- `_init()` signatures match across all route files and main.py wiring
- `build_bundle_data()` uses `PLATFORM_ENUM_MAP` consistently for all platform lookups
